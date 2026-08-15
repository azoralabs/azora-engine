# Azora Engine Profiler

Status: Proposal
Initial delivery: file capture and offline inspection
Future delivery: live in-engine graphs and remote capture
Primary package: `azora-profiler`
Primary module: `engine.profiler`

## 1. Summary

Azora Engine needs a profiler that answers a practical question: **what consumed
the frame's time and resources, and why?** A process-wide CPU percentage or a
single frame duration is not enough. The profiler must attribute work to the
actual engine system, job, function site, media session, asset, GPU pass, audio
device, or other context that caused it.

The first implementation records profiling data to a file. It must capture
frames, nested CPU spans, asynchronous work, counters, memory, I/O, job queue
waits, audio deadlines, and GPU timings without blocking the measured work. A
future graph UI must consume the same event stream and snapshots; it must not
require a second instrumentation API.

The design has five layers:

1. **Instrumentation sites** identify where a measurement originates.
2. **Tracks and contexts** identify where work ran and which logical owner
   caused it.
3. **Per-thread recorders** append fixed-size events with bounded overhead.
4. **The collector** merges records, maintains summaries, and writes a
   crash-tolerant `.aztrace` file.
5. **Exporters and viewers** convert or visualize completed snapshots without
   entering the recording hot path.

`engine.profiler` is a neutral engine service. It must not import ECS, jobs,
GPU, audio, video, render, or UI packages. Those packages emit generic profiler
events through small adapters. This prevents circular dependencies and lets the
profiler measure the scheduler and renderer themselves.

`engine.debug` is a separate consumer-facing diagnostics layer. Debug inspects
what state exists and may link objects to profiler contexts; Profiler records
when work occurred and how much it cost. Debug does not own timeline storage,
and Profiler does not expose mutable subsystem state or control simulation.

## 2. Goals

### 2.1 Required first release

The first release must:

- start and stop one profiling session per process;
- continuously write a bounded capture to a local file;
- record frame boundaries and frame duration;
- record nested synchronous spans on every participating thread;
- connect asynchronous work across threads with flows and logical contexts;
- record counters, gauges, rates, and sampled distributions;
- distinguish active execution from queue wait, I/O wait, lock wait, and GPU
  wait when the subsystem can report the distinction;
- attribute events by stable site, symbol, resource, and context identity;
- capture process and per-thread CPU time where the platform supports it;
- capture resident memory, allocation counts, allocated bytes, and peaks;
- capture ECS system, job scheduler, I/O, render, GPU, UI, audio, and media
  measurements through adapters;
- avoid allocations, locks, file I/O, string interning, and callbacks in
  real-time recording paths;
- remain readable after a truncated final chunk or unclean shutdown;
- report all dropped events and unavailable capabilities;
- export a human-readable summary and Chrome Trace Event JSON;
- run with deterministic clocks and fake platform counters in tests;
- become nearly free when disabled.

### 2.2 Product goals

- A developer can find the systems and jobs responsible for a slow frame.
- A developer can distinguish useful parallel work from workers waiting in a
  queue or blocked by a serial stage.
- A developer can connect an asset read to decode, GPU upload, and final draw.
- A developer can see whether an audio underrun was caused by decoding,
  scheduling, mixing, or the device callback.
- A capture made on a user's machine can be inspected without the game running.
- CI can compare stable summary metrics against a performance budget.
- Shipping builds can retain low-cost counters and a bounded flight recorder
  without enabling detailed source or path information.
- A later `engine.profiler.ui` can show live graphs without changing producers.

### 2.3 Non-goals

The first release does not replace Azora Debug, a platform debugger, Instruments,
system-wide kernel tracing, a heap correctness sanitizer, or a distributed
observability service. It does not promise instruction-level CPU profiling on
every target. It does not upload captures automatically.

The profiler reports evidence; it does not automatically change scheduler
priorities, drop graphics quality, resize queues, or terminate jobs. Adaptive
systems may consume profiler summaries through an explicit policy later.

## 3. Package and module layout

The primary package remains `azora-profiler`, as requested by the original
draft. File exporters and the future UI are split so the recording core stays
small and does not depend on rendering:

```text
packages/
  azora-profiler/           # engine.profiler recording, aggregation, file sink
  azora-profiler-platform/  # clocks, process/thread CPU and memory providers
  azora-profiler-export/    # offline JSON/CSV/Perfetto conversion
  azora-profiler-ui/        # future engine.profiler.ui graphs and overlay
```

Suggested modules:

```text
engine.profiler
engine.profiler.platform
engine.profiler.export
engine.profiler.ui
```

Dependency direction:

```text
engine.core        engine.io
      \              /
       engine.profiler
          ^  ^  ^  ^
          |  |  |  +--- engine.audio / engine.video
          |  |  +------ engine.gpu / engine.render
          |  +--------- engine.jobs
          +------------ engine.ecs / engine.ui

engine.profiler.ui ------> engine.profiler + engine.ui + engine.render
engine.profiler.export ---> engine.profiler + engine.io + engine.jobs
```

The arrows into `engine.profiler` represent event emission, not profiler
imports of those packages. `azora-engine` may re-export `engine.profiler`.
Applications that do not use the graph UI do not include
`azora-profiler-ui`.

## 4. Language-conforming public model

This proposal uses the current Azora language:

- `pack` for records and handles;
- `enum` for payload-free choices;
- `variant enum` for payload-bearing values;
- `variant error` and `?!` for recoverable capture/export failures;
- `spec` and `impl` for platform and sink capabilities;
- postfix `&` and `!` for shared and exclusive borrows;
- `annot` for optional compiler-assisted instrumentation;
- `react func`, `remember`, and `effect` only in the future UI package;
- `@System(.Phase)` and `@query [...] @with ... @without ...` in engine
  integration examples.

There are no `struct`, `trait`, `type`, `res`, or `mut res` declarations. Pack
and enum members are newline-separated without commas.

## 5. Profiling model

### 5.1 Events, tracks, and contexts

A profiling event answers three separate questions:

- **Site:** which instrumentation or compiler symbol produced it?
- **Track:** where did it execute or occur?
- **Context:** which logical operation or resource should own the cost?

These identities must not be collapsed into a string name. Two systems named
`update`, two files named `main.az`, or two media streams labeled `English` may
have different meanings and costs. Names are display metadata only.

A track is an ordered timeline. Normal CPU tracks correspond to threads. Other
tracks represent a job, GPU queue, audio device, frame sequence, or custom
timeline. This follows the track-event model used by Perfetto: bounded slices,
counters, and flows are placed on separate ordered tracks and flows connect
related work across tracks. See the [Perfetto track-event documentation](https://perfetto.dev/docs/instrumentation/track-events).

A context is logical ownership. A media decode job executes on a worker thread,
but its context is the media session and selected stream. An ECS system may
submit a GPU upload; the CPU and GPU work have different tracks but share a
flow and parent context.

### 5.2 Stable identity

```azora
pack ProfileSiteId {
    fin value: std::Long
}

pack ProfileSymbolId {
    fin value: std::Long
}

pack ProfileTrackId {
    fin value: std::Long
}

pack ProfileContextId {
    fin value: std::Long
}

pack ProfileMetricId {
    fin value: std::Long
}

pack ProfileFlowId {
    fin value: std::Long
}

pack ProfileStringId {
    fin value: std::Int
}
```

The compiler creates a `ProfileSymbolId` from the resolved symbol, module,
specialization, and build identity. It creates a `ProfileSiteId` from the
resolved symbol plus source location and instrumentation kind. The display
name may change without changing whether two events are distinct.

Runtime-created resources receive monotonically unique IDs scoped to the
session generation. Pointer values and object addresses are never public IDs:
they leak implementation details, are reused, and make captures unstable.

Cross-build comparison uses a build ID plus compiler-emitted symbol map.
Unknown symbols remain valid numeric identities and are displayed as
`<unresolved:...>` instead of being merged by name.

The compiler and collector compare the canonical descriptor fingerprint when
two entries have the same numeric ID. A collision is a build/capture diagnostic,
never permission to merge unrelated symbols. Exporters can use the full
fingerprint as an extended identity when reading such a capture.

### 5.3 Context kinds

```azora
enum ProfileContextKind {
    Process
    Thread
    Frame
    System
    Job
    Task
    Entity
    Asset
    Resource
    IoRequest
    GpuSubmission
    AudioStream
    MediaSession
    UiOwner
    Custom
}

pack ProfileContext {
    fin id: ProfileContextId
    fin kind: ProfileContextKind
    fin parent: ProfileContextId?
    fin symbol: ProfileSymbolId?
    fin label: ProfileStringId?
}

pack ProfileContextToken {
    fin context: ProfileContextId
    fin generation: std::Long
}

func profilerCreateContext(
    kind: ProfileContextKind,
    parent: ProfileContextId?,
    symbol: ProfileSymbolId?,
    label: ProfileStringId?
): ProfileContext ?! ProfilerError

func profilerCloseContext(context: ProfileContextId)
func profilerCurrentContext(): ProfileContextToken?
func profilerCaptureContext(): ProfileContextToken?
func profilerEnterContext(token: ProfileContextToken): ProfileContextToken?
func profilerLeaveContext(previous: ProfileContextToken?)
```

Subsystems create contexts on cold paths and emit their metadata once. A job
captures the current `ProfileContextToken` when submitted and installs it while
executing. A stale generation cannot attach work to a context from a previous
capture.

## 6. Runtime modes and configuration

### 6.1 Modes

```azora
enum ProfilerMode {
    Off
    Counters
    Timeline
    Detailed
}
```

- `Off` records nothing. Instrumentation sites reduce to a predictable disabled
  branch or are compiled out according to the build profile.
- `Counters` maintains bounded aggregates and low-frequency process metrics.
  It is suitable for shipping diagnostics.
- `Timeline` records spans, instants, flows, frames, and counters into the
  capture stream.
- `Detailed` adds allocation events, source locations, per-core samples,
  provider calls, stack samples, and backend-specific GPU counters when
  available.

Detailed categories can perturb the measured program. Captures state their
mode and measured profiler overhead so comparisons do not mix unlike modes.

### 6.2 Output and overflow policy

```azora
variant enum ProfileOutput {
    Memory
    File(path: std::String)
    MemoryAndFile(path: std::String)
}

enum ProfileOverflowPolicy {
    DropNewest
    StopCapture
}

enum ProfilePrivacy {
    Safe
    Development
    Explicit
}
```

`DropNewest` is the real-time-safe default. A producer never waits for the
collector. It increments a per-track dropped counter and emits one gap marker
when space becomes available again. `StopCapture` atomically disables recording
after overflow and preserves the valid prefix. Blocking producers is not an
option.

### 6.3 Configuration

```azora
@Resource
pack ProfilerConfig {
    var mode: ProfilerMode
    var output: ProfileOutput
    var overflow: ProfileOverflowPolicy
    var privacy: ProfilePrivacy
    var samplePeriodMs: std::Int
    var bufferBytesPerThread: std::Int
    var maxMemoryBytes: std::Long
    var maxFileBytes: std::Long
    var flushIntervalMs: std::Int
    var maxAttributesPerEvent: std::Int
    var captureCpu: std::Bool
    var capturePerCore: std::Bool
    var captureMemory: std::Bool
    var captureAllocations: std::Bool
    var captureGpu: std::Bool
    var captureJobs: std::Bool
    var captureSystems: std::Bool
    var captureIo: std::Bool
    var includeSourceLocations: std::Bool
    var includeDynamicStrings: std::Bool
    var enabledCategories: std::Array<std::String>
    var disabledCategories: std::Array<std::String>
}
```

Configuration is validated before threads start recording. Buffer sizes are
rounded to implementation alignment, minimum and maximum values are enforced,
and unknown category IDs are reported. Changing capture detail during a session
creates a configuration marker; changes requiring different buffer layouts
start a new session generation.

### 6.4 Session lifecycle

```azora
pack ProfilerSession {
    fin id: std::Long
    fin generation: std::Long
}

enum ProfilerState {
    Stopped
    Starting
    Recording
    Stopping
    Failed
}

variant error ProfilerError {
    AlreadyRunning
    NotRunning
    InvalidConfig(reason: std::String)
    InvalidPath(path: std::String)
    PermissionDenied(path: std::String)
    SinkUnavailable
    UnsupportedCapability(name: std::String)
    BufferAllocationFailed
    WriteFailed(path: std::String)
    CorruptCapture(path: std::String)
    UnsupportedVersion(version: std::Int)
    ExportFailed(format: std::String)
    Internal(reason: std::String)
}

func profilerStart(config: ProfilerConfig): ProfilerSession ?! ProfilerError
func profilerFlush(session: ProfilerSession): std::Unit ?! ProfilerError
func profilerStop(session: ProfilerSession): ProfilerSnapshot ?! ProfilerError
func profilerState(): ProfilerState
func profilerIsEnabled(): std::Bool
```

Only one process session records at a time. `profilerStop` is idempotent for the
current generation and returns its final immutable snapshot. A stale session
handle cannot stop a newer capture.

`profilerFlush` asks the collector to persist all events already visible to it.
It may wait on the calling control thread, so it is forbidden from real-time,
render submission, and profiler producer paths.

## 7. Clock and track model

### 7.1 Timestamp contract

Every event timestamp is an integer nanosecond value in one monotonic session
clock domain:

```azora
pack ProfileTimestamp {
    fin nanos: std::Long
}

spec ProfileClock {
    func nowNs[self: Self&](): std::Long
    func name[self: Self&](): std::String
    func resolutionNs[self: Self&](): std::Long
}
```

The capture header records the provider and conversion metadata. Wall-clock
time is optional session metadata and is never used for duration arithmetic.
Clock adjustments must not make a track move backward. If a backend clock
violates monotonicity, the recorder clamps that track and increments a clock
error counter.

On macOS, the provider should use the nanosecond monotonic clock API backed by
Mach time. Apple recommends `clock_gettime_nsec_np` over manually converting
raw Mach ticks when those clock domains are sufficient; see
[mach_continuous_time](https://developer.apple.com/documentation/kernel/1646199-mach_continuous_time?changes=la_9_8___7__5_7%2Cla_9_8___7__5_7&language=objc%2Cobjc).
The provider emits application suspend/resume markers so a large suspended
interval is not mistaken for active frame work.

### 7.2 Tracks

```azora
enum ProfileTrackKind {
    Process
    Thread
    Worker
    Frame
    Task
    GpuQueue
    GpuPass
    AudioDevice
    Counter
    Custom
}

pack ProfileTrack {
    fin id: ProfileTrackId
    fin kind: ProfileTrackKind
    fin parent: ProfileTrackId?
    fin name: ProfileStringId
    fin sortOrder: std::Int
}
```

Events on one track are monotonically ordered. Parallel execution uses separate
tracks. A span that begins and ends on different threads uses an explicit task
track or asynchronous span; it must not corrupt either thread's nesting stack.

Thread registration allocates and names its buffer before hot-path recording.
Unknown foreign threads may register lazily on a non-real-time path. A real-time
thread without a registered buffer drops events and reports that fact later.

## 8. Sites, symbols, and compiler assistance

### 8.1 Site descriptors

```azora
pack ProfileSite {
    fin id: ProfileSiteId
    fin symbol: ProfileSymbolId?
    fin category: ProfileStringId
    fin name: ProfileStringId
    fin file: ProfileStringId?
    fin line: std::Int?
    fin column: std::Int?
}
```

Static site descriptors live in compiler-emitted read-only metadata. Recording
a static site writes IDs only. It performs no hashing, symbol lookup, path
copying, or string interning.

```azora
func profileString(value: std::String): ProfileStringId
func profileSite(category: std::String, name: std::String): ProfileSite
func profilerInternString(value: std::String): ProfileStringId ?! ProfilerError
```

`profileString` and `profileSite` accept compile-time string literals. The
compiler emits their descriptors and replaces each call with its stable
ID-bearing value. A non-constant argument is rejected with guidance to use the
cold-path `profilerInternString` or `profilerCreateSite` API. Dynamic interning
applies the active privacy policy and is invalid from a real-time thread.

Dynamic sites are allowed only through an explicit cold-path function:

```azora
func profilerCreateSite(
    category: std::String,
    name: std::String
): ProfileSite ?! ProfilerError
```

Dynamic site creation is invalid from a real-time thread. Captures mark dynamic
sites so tools do not assume cross-run stability.

### 8.2 Function annotation

```azora
annot Profile for .Func {
    fin category: std::String = "app"
    fin name: std::String = ""
    fin minimumMode: ProfilerMode = ProfilerMode.Timeline
}

annot NoProfile for .Func
```

Example:

```azora
@Profile(category: "physics")
func solveContacts(world: World!) {
    solveBroadPhase(world)
    solveNarrowPhase(world)
}
```

The compiler wraps the function body in a generated begin/end pair and uses
the resolved function symbol, not `"solveContacts"`, as identity. All returns,
failable exits, and unwinding paths close the span. Generic specializations may
have distinct symbols while retaining a link to the generic declaration.

`@NoProfile` prevents automatic wrapping of profiler internals, tiny runtime
helpers, and callbacks where re-entry would be unsafe. It does not suppress
manually emitted events unless their category is disabled.

The annotation introduces no new language keyword and does not change function
semantics. The optimizer may remove disabled sites in builds configured without
profiling support.

### 8.3 Manual scoped instrumentation

```azora
func decodeFrame(decoder: Decoder!, packet: Packet&): Frame ?! DecodeError {
    fin span = profilerBegin(profileSite("media", "decode-frame"))
    defer profilerEnd(span)

    return try decoder.decode(packet)
}
```

`profileSite` in this example is a compiler-recognized static-site constructor
because both arguments are literals. It emits a descriptor and returns its ID.
Passing dynamic strings requires `profilerCreateSite` outside the hot path.

## 9. Event model and recording API

### 9.1 Event kinds

```azora
enum ProfileEventKind {
    SpanBegin
    SpanEnd
    AsyncBegin
    AsyncEnd
    Instant
    Counter
    Gauge
    Distribution
    FlowBegin
    FlowStep
    FlowEnd
    FrameBegin
    FrameEnd
    Allocation
    Deallocation
    ContextEnter
    ContextLeave
    Metadata
    Gap
}

pack ProfileSpan {
    fin site: ProfileSiteId
    fin track: ProfileTrackId
    fin context: ProfileContextId?
    fin sequence: std::Long
    fin generation: std::Long
}
```

Each producer writes a compact internal record containing timestamp, event
kind, track, site or metric, context, correlation ID, and small inline values.
The public `ProfileEventKind` does not require the on-disk record to waste space
on fields unused by that event.

### 9.2 Values and attributes

```azora
variant enum ProfileValue {
    Integer(std::Long)
    Decimal(std::Double)
    Flag(std::Bool)
    Text(ProfileStringId)
    Symbol(ProfileSymbolId)
    Context(ProfileContextId)
}

pack ProfileAttribute {
    fin key: ProfileStringId
    fin value: ProfileValue
}
```

Attributes are bounded by `maxAttributesPerEvent`. Static attribute keys and
text values are interned metadata. Dynamic text is rejected unless
`includeDynamicStrings` and the selected privacy mode allow it. Large payloads,
arrays, maps, object dumps, and arbitrary `display` calls are never performed
by the recorder.

The naming conventions for common attributes should align where practical with
OpenTelemetry's resource, span, metric, event, and profile semantic conventions,
which exist to make telemetry from different components correlate consistently.
Azora does not need an OpenTelemetry runtime dependency to use compatible
meanings. See the [OpenTelemetry semantic conventions](https://opentelemetry.io/docs/specs/semconv/general/).

### 9.3 Span and instant API

```azora
func profilerBegin(site: ProfileSite): ProfileSpan
func profilerEnd(span: ProfileSpan)
func profilerInstant(site: ProfileSite)

func profilerAsyncBegin(
    site: ProfileSite,
    context: ProfileContextId
): ProfileSpan

func profilerAsyncEnd(span: ProfileSpan)
```

Synchronous spans nest on one track. `profilerEnd` validates the token's track,
sequence, and generation. A mismatched end does not corrupt later events: it
emits a diagnostic and closes only the matching span when possible.

Asynchronous spans are associated with an explicit context or task track and
may end on another thread. A normal synchronous span must never cross threads.

### 9.4 Flows

```azora
func profilerFlowBegin(site: ProfileSite): ProfileFlowId
func profilerFlowStep(flow: ProfileFlowId, site: ProfileSite)
func profilerFlowEnd(flow: ProfileFlowId, site: ProfileSite)
```

Flows connect related work without pretending it executed continuously. They
show relationships such as:

```text
ECS system -> job queued -> worker decode -> GPU upload -> render pass
```

The gap between flow steps remains visible as queue or dependency latency.
Flows are process-scoped and include the session generation to prevent ID reuse.

## 10. Metrics

### 10.1 Metric descriptors

```azora
enum ProfileMetricKind {
    Counter
    UpDownCounter
    Gauge
    Distribution
}

enum ProfileMetricUnit {
    Count
    Bytes
    Nanoseconds
    Seconds
    Frames
    Samples
    Percent
    Hertz
    Custom
}

pack ProfileMetric {
    fin id: ProfileMetricId
    fin name: ProfileStringId
    fin description: ProfileStringId
    fin kind: ProfileMetricKind
    fin unit: ProfileMetricUnit
    fin customUnit: ProfileStringId?
    fin contextKind: ProfileContextKind?
}

func profilerCreateMetric(
    name: std::String,
    description: std::String,
    kind: ProfileMetricKind,
    unit: ProfileMetricUnit,
    customUnit: std::String?,
    contextKind: ProfileContextKind?
): ProfileMetric ?! ProfilerError
```

Metric descriptors are registered before frequent observation. A descriptor's
name, kind, unit, and meaning are immutable within a schema version. Renaming a
metric for presentation does not reuse an incompatible ID.

### 10.2 Recording metrics

```azora
func profilerCounterAdd(
    metric: ProfileMetric,
    amount: std::Long,
    context: ProfileContextId?
)

func profilerGaugeSet(
    metric: ProfileMetric,
    value: std::Double,
    context: ProfileContextId?
)

func profilerObserve(
    metric: ProfileMetric,
    value: std::Double,
    context: ProfileContextId?
)
```

Counters are monotonic unless declared `UpDownCounter`. Gauges represent the
latest sampled value. Distributions maintain count, sum, minimum, maximum, and
bounded histogram buckets so tools can compute p50, p95, and p99 without
retaining every observation in `Counters` mode.

Metric labels are contexts or predeclared bounded attributes. Arbitrary user
strings must not create unbounded cardinality. An asset path, entity ID, URL,
or job name is represented by a context identity and separately controlled
metadata, not a new metric name.

## 11. Recorder and collector architecture

### 11.1 Producer buffers

Each participating thread owns a preallocated single-producer buffer. The
collector is its only consumer. The normal record operation is:

1. test whether the mode and category are enabled;
2. read the monotonic timestamp;
3. reserve one fixed-size record or bounded continuation records;
4. copy IDs and primitive values;
5. publish the new write cursor.

There is no shared producer mutex. Strings and site metadata are emitted from
static tables or cold-path registration. Producer buffers use cache-line
separation so adjacent worker cursors do not create false sharing.

### 11.2 Collector ownership

`engine.profiler` owns one dedicated infrastructure collector thread while a
file or live capture is active. It is not a general worker pool and does not run
application work. This exception is necessary because:

- `engine.jobs` itself must be measurable;
- a stalled job queue must not prevent the profiler from exposing that stall;
- submitting every drain as a job would recursively profile the profiler;
- file flushing must not consume an audio or render deadline worker.

The collector thread is marked `@NoProfile`. It reads producer buffers, merges
events by timestamp within a bounded reorder window, updates aggregates, and
passes completed chunks to sinks. Its own CPU time, bytes written, queue depth,
and dropped records are reported as profiler-overhead metadata sampled outside
its instrumentation path.

Offline export and expensive report generation use
`engine.jobs` with `JobPriority.Background` because they occur after or outside
recording and cannot recursively affect the captured scheduler timeline.

### 11.3 Reordering

Tracks are already ordered. The collector does not globally sort the entire
capture in memory. It performs a bounded k-way merge over visible producer
heads, preserving per-track order. Events arriving after their chunk was
sealed are written to a later chunk with their original timestamp; readers
merge chunks by timestamp.

Clock skew, late records, and sequence gaps are explicit diagnostics. The
collector never rewrites a timestamp to hide a producer error except for the
per-track monotonic clamp described in the clock contract.

### 11.4 Backpressure and loss

When a producer buffer fills:

- the producer follows `ProfileOverflowPolicy` without waiting;
- dropped count and first/last dropped timestamp are retained atomically;
- the next successful write emits a `Gap` event;
- summaries mark affected intervals as incomplete;
- CI comparisons can reject incomplete captures explicitly.

The collector may reduce optional sampling frequency under pressure, but it
must not silently disable required frame markers or change counter meaning.

## 12. File capture format

### 12.1 Canonical `.aztrace` format

`.aztrace` is the canonical recording format. It is compact, append-only,
versioned, and independent of a particular viewer. JSON is an export format,
not the hot-path storage format.

The file contains:

```text
AzTraceHeader
MetadataChunk
StringTableChunk*
SiteAndSymbolChunk*
TrackAndContextChunk*
EventChunk*
AggregateChunk*
IndexChunk?
AzTraceFooter?
```

The fixed header includes:

- magic bytes and format version;
- byte order and pointer-width metadata;
- compiler, language, engine, application, and build IDs;
- platform, architecture, process ID, and executable identity;
- session ID, generation, start wall time, and monotonic clock description;
- profiler mode, privacy policy, and configuration hash;
- capability flags and unavailable-provider reasons.

Every chunk has a kind, schema version, sequence number, byte length, time
range, and checksum. Unknown optional chunks are skipped. Unknown required
chunks produce `UnsupportedVersion`.

### 12.2 Crash and truncation behavior

The writer appends complete chunks and publishes their final length/checksum
last. A reader scans from the header and accepts every complete valid chunk.
The footer and index improve fast opening but are not required for recovery.

A process crash may lose the producer-buffer tail and current file chunk. It
must not invalidate earlier chunks. The next inspection reports an unclean end,
missing tracks, unmatched spans, and estimated lost interval.

Signal or exception handlers must not attempt complex allocation, locking, JSON
serialization, or arbitrary filesystem recovery. A best-effort crash marker is
allowed only when the platform sink provides an async-signal-safe path.

### 12.3 File limits and rotation

`maxFileBytes` bounds a continuous capture. When the limit is reached the sink
either:

- seals the file and stops, for a normal explicit capture; or
- rotates numbered chunks for an explicitly configured flight recorder.

Rotation is atomic at chunk boundaries. Each part records the same session ID
and a monotonically increasing part number. Deleting old parts is performed by
the control/collector path using explicit validated file names, never by a
producer.

### 12.4 Export formats

```azora
enum ProfileExportFormat {
    AzTrace
    ChromeTraceJson
    SummaryJson
    SummaryCsv
    PerfettoProto
}

func profilerExport(
    inputPath: std::String,
    outputPath: std::String,
    format: ProfileExportFormat
): std::Unit ?! ProfilerError
```

The first release implements `ChromeTraceJson`, `SummaryJson`, and
`SummaryCsv`. Chrome Trace Event JSON can be opened by common trace viewers,
including Perfetto's importer; Perfetto documents support for external trace
formats and conversion paths in its
[external-format guide](https://perfetto.dev/docs/getting-started/other-formats).

`PerfettoProto` is a later direct exporter. It maps Azora tracks, slices,
counters, flows, clock metadata, and process/thread descriptors to Perfetto
trace packets. `.aztrace` remains the source of truth so an external schema
change does not invalidate Azora captures.

## 13. Snapshots and summaries

### 13.1 Snapshot model

```azora
pack ProfilePercentiles {
    fin p50: std::Double
    fin p95: std::Double
    fin p99: std::Double
    fin maximum: std::Double
}

pack ProfileConsumer {
    fin context: ProfileContextId
    fin symbol: ProfileSymbolId?
    fin inclusiveNs: std::Long
    fin exclusiveNs: std::Long
    fin waitNs: std::Long
    fin allocationBytes: std::Long
    fin ioBytes: std::Long
    fin samples: std::Long
}

pack ProfilerSnapshot {
    fin session: ProfilerSession
    fin mode: ProfilerMode
    fin startNs: std::Long
    fin endNs: std::Long
    fin eventCount: std::Long
    fin droppedEvents: std::Long
    fin droppedAttributes: std::Long
    fin incomplete: std::Bool
    fin profilerCpuNs: std::Long
    fin profilerMemoryBytes: std::Long
    fin frameTimeNs: ProfilePercentiles
    fin topConsumers: std::Array<ProfileConsumer>
}

func profilerSnapshot(): ProfilerSnapshot ?! ProfilerError
```

The snapshot is an immutable view assembled by the collector. Calling
`profilerSnapshot` may allocate and synchronize with the collector, so it is a
control/UI operation and is forbidden from real-time callbacks.

### 13.2 Attribution rules

The summary reports both inclusive and exclusive CPU time:

- inclusive time includes nested child spans;
- exclusive time subtracts nested spans on the same execution track;
- queue and wait time are separate, not charged as active CPU time;
- asynchronous children are linked by context/flow but not subtracted from the
  parent's thread time;
- GPU duration is reported in its own clock/track and is not added to CPU time;
- overlapping workers are not summed into wall duration without being labeled
  aggregate core time.

This prevents misleading statements such as “decode took 80 ms” when four
workers each ran for 20 ms during one 22 ms wall interval.

### 13.3 Human-readable report

The first report should make the answer visible without a graph viewer:

```text
capture: game.aztrace | 38.2 s | Timeline | complete
frames: 2294 | 16.6 ms target | p50 12.1 | p95 19.8 | p99 31.4 | max 74.2

top frame consumers (exclusive CPU):
  physics::solveContacts       4.8 ms p95   24.1%   system 0x...
  media::decode               3.3 ms p95   16.6%   session 12 / stream 2
  ui::layout                  1.9 ms p95    9.5%   owner 44

waits:
  media packet queue          2.1 ms p95
  jobs queue                  1.4 ms p95
  GPU present                 0.7 ms p95

memory: resident 412 MiB | peak 438 MiB | allocations 18.2 MiB/s
I/O: read 92 MiB | 38 MiB/s peak | 6.2 ms p95 request
profiler: 0.7% CPU | 12 MiB | 0 dropped events
```

Display labels are accompanied by stable IDs in machine-readable output.

## 14. Frame and engine-loop integration

### 14.1 Frame markers

```azora
pack ProfileFrame {
    fin number: std::Long
    fin beginNs: std::Long
    fin endNs: std::Long
    fin presented: std::Bool
}

func profilerFrameBegin(number: std::Long)
func profilerFrameEnd(number: std::Long, presented: std::Bool)
```

The platform/app loop emits `FrameBegin` after input/event pumping begins the
new frame and `FrameEnd` after render submission/present has completed. GPU
completion remains a separate asynchronous event.

Frame summaries distinguish:

- CPU frame preparation;
- render submission;
- present wait;
- GPU execution;
- application suspension or debugger pause;
- fixed-step catch-up count;
- missed target and dropped presentation.

### 14.2 Schedule phases and systems

The ECS scheduler wraps every enabled `@System` invocation automatically. The
site descriptor contains the resolved system symbol and phase. The context
contains frame number and, when useful, system-set identity.

```azora
@System(.Update)
func movePlayers(
    query: @query [Transform!, Velocity&] @with Player @without Disabled
) {
    for entity in query {
        integrate(entity.0, entity.1)
    }
}
```

The profile identity is the resolved `movePlayers` symbol, not its string name.
The scheduler also emits:

- enabled and skipped system counts;
- phase begin/end spans;
- query iteration count;
- structural command count;
- declared access sets;
- ordering/dependency wait;
- worker assignment and parallel overlap;
- conflict or cycle diagnostics.

Per-entity spans are disabled by default because they create extreme event
volume. Detailed mode may sample entities or profile an explicitly selected
entity context.

## 15. Job-system integration

`engine.jobs` emits a flow from submission through execution and completion.
It captures the current `ProfileContextToken`, but the profiler core does not
import `JobToken`.

Required job events and metrics:

- submit timestamp and submitting context;
- stable job site/symbol and scheduler token metadata;
- public priority: `Urgent`, `Interactive`, `Normal`, or `Background`;
- optional deadline;
- queue selected and queue depth;
- worker assignment and CPU/core sample;
- queue wait duration;
- active execution duration;
- suspension and resumed execution for async work;
- completion, failure, or cooperative cancellation;
- deadline miss and cancellation-check latency;
- worker useful time, idle time, and steal attempts;
- global and per-priority backlog.

The profiler must distinguish these intervals:

```text
submitted ---- queue wait ---- started ---- active/suspended ---- completed
```

One job that resumes several times uses one logical task context and several
execution slices. Summing slices gives active CPU time; first-to-last gives wall
latency.

Profiler collection never submits work to the measured job pool. Offline
exports may use `Background` jobs after recording, as described earlier.

## 16. CPU sampling and thread state

Instrumentation shows known spans. Statistical sampling finds expensive code
that was not manually instrumented. They are complementary and share symbol,
track, and context IDs.

### 16.1 Process and thread counters

The platform provider samples:

- process user and kernel CPU time;
- per-thread CPU time when available;
- logical CPU and active-core count;
- thread name, priority class, and affinity metadata where available;
- runnable, running, waiting, sleeping, and blocked state where reliable;
- context switches and page faults where the target exposes them cheaply.

Unavailable values are omitted with a capability reason. Zero must never mean
“unsupported.”

### 16.2 Stack sampling

Detailed mode may sample stacks at a bounded configurable frequency. Sampling
must use a platform-safe mechanism and write raw instruction identities into a
separate preallocated sample buffer. Symbolization occurs in the collector or
offline tools, never in the interrupted thread.

The first implementation may ship without stack sampling on a target while
still supporting instrumented timelines and process counters. Captures state
whether samples are unavailable, disabled, permission-denied, or dropped.

Sampling frequency is capped. The profiler reports sample count and estimated
sampling overhead. A report must not present sample percentages as exact time.

## 17. Memory profiling

### 17.1 Process memory

At `Counters` mode or above, the platform provider samples:

- resident and virtual memory;
- private/dirty memory when available;
- allocator committed and active bytes;
- mapped file and GPU resource estimates where providers expose them;
- current and peak values.

### 17.2 Allocation instrumentation

The Azora runtime allocator gains optional profiler hooks around allocation,
reallocation, and deallocation. The hook records:

- allocation site and current context;
- size and alignment;
- allocation class or arena;
- lifetime token;
- thread and timestamp.

```azora
pack ProfileAllocation {
    fin token: std::Long
    fin site: ProfileSiteId
    fin context: ProfileContextId?
    fin bytes: std::Long
    fin alignment: std::Int
}
```

Raw addresses are not written in `Safe` privacy mode. A session-scoped token
connects allocation and deallocation. Reused addresses therefore cannot merge
two lifetimes.

The allocator hook writes directly to preallocated recorder storage and has a
thread-local recursion guard. Allocations made by profiler metadata, buffers,
symbolization, or sinks bypass application allocation hooks and are charged to
the reserved profiler context. Profiling an allocation must never allocate
another profiling record dynamically.

`Counters` mode aggregates allocation count/bytes by bounded context without
emitting every lifetime. `Detailed` mode may record individual allocations or
sample them above a threshold. Stack capture is independently configurable.

The report includes allocation rate, peak live bytes, lifetime distribution,
largest contexts, and allocations still live at a clean session stop. “Still
live” is a leak candidate, not proof of a leak; caches and long-lived resources
are labeled by context.

### 17.3 Profiler memory

All recorder buffers, metadata tables, collector queues, snapshots, and sink
buffers are charged to a reserved profiler context. This memory is shown
separately and excluded from application allocation rankings by default, but it
is never hidden from process totals.

## 18. I/O profiling

`engine.io` wraps each request with a site, request context, and flow. Required
fields and metrics include:

- operation kind: open, read, write, map, unmap, close, stat;
- logical asset/resource context;
- requested and completed bytes;
- queue wait, syscall/provider time, and consumer wait;
- cache hit/miss and source provider;
- completion, short read, cancellation, and error class;
- throughput and concurrent request count.

Paths are metadata governed by `ProfilePrivacy`. `Safe` mode stores an asset ID,
extension/category if approved, and a one-way session salt hash rather than the
full path. File contents are never captured.

Synchronous I/O on a render, audio, or other deadline track emits a diagnostic
instant in addition to the normal span.

## 19. GPU and render profiling

### 19.1 CPU/GPU separation

The renderer emits distinct measurements for:

- render extraction and queue construction on CPU;
- shader/pipeline lookup and compilation;
- resource upload preparation;
- command encoding and submission;
- time waiting for an available drawable or queue slot;
- GPU queue wait;
- render, compute, blit, upload, and present GPU execution;
- completion latency and frame association.

CPU command encoding time is not GPU execution time. A frame may have a low CPU
submission cost and still miss because the GPU queue is saturated.

### 19.2 GPU provider boundary

```azora
spec GpuProfilerProvider {
    func available[self: Self&](): std::Bool
    func beginFrame[self: Self!](frame: std::Long)
    func beginPass[self: Self!](context: ProfileContextId): std::Long
    func endPass[self: Self!](token: std::Long)
    func resolve[self: Self!]()
}
```

This spec belongs to the GPU adapter package; it is shown here as the required
contract. `engine.profiler` sees generic tracks and events, not Metal objects.

On Metal, use timestamp counter sample buffers when the device supports them,
and correlate the GPU clock with the CPU trace clock. Apple documents that
counter support must be queried and that timestamp samples may require
GPU-to-CPU clock conversion; see
[GPU counters and counter sample buffers](https://developer.apple.com/documentation/Metal/gpu-counters-and-counter-sample-buffers?language=objc).

When hardware counters are unavailable, the provider records CPU submission,
command-buffer scheduled/completed timestamps, and an explicit reduced-
precision capability. It never synchronously waits for the GPU merely to obtain
a profile sample.

### 19.3 Render metrics

At minimum the render adapter reports:

- draw, dispatch, primitive, instance, and pass counts;
- uploaded and resident buffer/texture bytes;
- transient allocation and staging-pool pressure;
- pipeline/shader cache hits, misses, and compilation time;
- command-buffer count and in-flight depth;
- drawable wait and present latency;
- GPU duration by pass and frame when supported;
- dropped GPU samples and unsupported counter sets.

## 20. Audio and media profiling

### 20.1 Audio real-time path

The audio callback may emit only fixed-size events and counters into a
pre-registered buffer. It must never:

- allocate or free memory;
- intern a string or define a dynamic site/context;
- lock a general mutex;
- wake and wait for the collector;
- write a file;
- call UI, ECS, jobs, decoder, or exporter code;
- capture a stack unless a platform mechanism is explicitly proven real-time
  safe for that backend.

Required audio measurements include callback duration/deadline, device buffer
size, active voices/effects, PCM queue depth, underruns/overruns, decoder and
resampler work, mixer work, device latency, and audio/video drift.

An audio deadline miss with a healthy PCM queue points to mixer/device pressure.
An empty queue points to source, decoder, or job starvation. The report keeps
these diagnoses separate.

### 20.2 Media stages

Media defines its own stable sites for:

```text
probe, read, demux, packet queue, decode, reorder, color conversion,
GPU upload, present, audio decode, audio mix, subtitle, seek, close
```

Each event carries media-session and stream contexts. Worker counts distinguish
requested, active, and useful workers. The profiler reports queue duration and
bytes, frame drops, deadline misses, seek latency, hardware/software provider,
GPU upload cost, and A/V drift.

The generic profiler does not import `MediaTime`, `StreamId`, `VideoPlayer`, or
`AudioStreamId`. Media emits those as context metadata or bounded attributes.
`VIDEO.MD` and `AUDIO.MD` remain responsible for the media-specific metrics;
this document owns the common profiler types and recording semantics.

## 21. Reactive UI and ECS diagnostics

### 21.1 UI stages

The UI adapter records separate spans for:

- reactive invalidation discovery;
- `react func` execution;
- `remember`/`retain`/`preserve` state lookup;
- composition;
- keyed reconciliation;
- command publication;
- layout and intrinsic measurement;
- paint generation;
- event dispatch and effect execution;
- disposal and `effect defer` cleanup.

Each UI owner is a `UiOwner` context with a stable compiler site and runtime
instance ID. Repeated widgets with the same label are not merged.

Required counters include recomposed/skipped owners, created/reused/disposed
nodes, layout passes, cycle diagnostics, paint primitives, event queue depth,
and effect count.

### 21.2 Future live UI

`azora-profiler-ui` consumes immutable `ProfilerSnapshot` values on a normal UI
schedule. It does not read producer buffers or collector internals.

The first live overlay should show:

- frame graph with target, p50, p95, and current frame;
- CPU lanes and top systems/jobs;
- GPU frame/pass graph;
- resident memory and allocation rate;
- jobs backlog and worker utilization;
- audio callback deadline and underruns;
- media queues and A/V drift;
- profiler overhead and dropped events.

More detailed timeline exploration belongs in a desktop/offline viewer. The
in-engine overlay must remain bounded and should default to aggregate snapshots
rather than rendering every trace event.

## 22. Flight recorder and triggers

A rolling flight recorder is useful for bugs that cannot be reproduced on
demand. It keeps recent chunks in bounded memory and writes them only after a
trigger.

```azora
variant enum ProfileTrigger {
    Manual
    FrameAbove(nanos: std::Long)
    MemoryAbove(bytes: std::Long)
    CounterAbove(metric: ProfileMetricId, value: std::Double)
    AudioUnderrun
    GpuDeadlineMiss
    ErrorEvent
}

pack ProfileFlightRecorderConfig {
    fin historySecs: std::Int
    fin afterTriggerSecs: std::Int
    fin outputPath: std::String
    fin triggers: std::Array<ProfileTrigger>
}

func profilerTrigger(reason: ProfileStringId)
```

On trigger, the collector freezes the pre-trigger chunk window, records the
configured post-trigger interval, and writes both with one session identity.
Repeated triggers extend only up to a bounded maximum. Producers do not perform
file operations.

Shipping builds default to `Safe` privacy and counters/timeline categories that
have been explicitly approved. User consent is required before sharing a
capture.

## 23. Sinks and future streaming

### 23.1 Collector-side sink contract

```azora
pack ProfileBatch {
    fin id: std::Long
    fin sequence: std::Long
    fin firstNs: std::Long
    fin lastNs: std::Long
    fin bytes: std::Long
}

spec ProfileSink {
    func open[self: Self!](session: ProfilerSession): std::Unit ?! ProfilerError
    func write[self: Self!](batch: ProfileBatch&): std::Unit ?! ProfilerError
    func flush[self: Self!](): std::Unit ?! ProfilerError
    func close[self: Self!](): std::Unit ?! ProfilerError
}
```

Only the collector invokes sinks. A sink is never called from an instrumented
producer. Sink execution is serialized per session unless the sink declares a
future parallel contract.

The first sink is the `.aztrace` file sink. Future sinks may provide a local
socket, development tool connection, or live viewer. Network streaming is not
enabled implicitly and must apply authentication, encryption, backpressure,
privacy filtering, and an independent byte limit.

### 23.2 Sink failure

A failed file sink does not crash the application. The collector records the
error in memory, disables that sink, and follows policy:

- continue a bounded memory capture when configured;
- stop the session when no valid output remains;
- emit one engine diagnostic outside the profiler hot path;
- make `profilerStop` return the sink error with any recoverable snapshot.

Repeated write retries are bounded. Disk-full and permission errors must not
create an infinite retry loop.

## 24. Security and privacy

Profile captures can contain sensitive implementation details. The profiler
must:

- default to `Safe` privacy outside development builds;
- omit source paths, user names, command-line secrets, URLs, and arbitrary
  dynamic strings by default;
- salt hashes per capture so path identities cannot be correlated indefinitely;
- never record file contents, media samples, network payloads, text input, or
  object dumps automatically;
- avoid raw pointers and native object addresses;
- validate output paths through `engine.io` policy;
- create captures with restrictive file permissions;
- bound metadata, event, attribute, stack, and file sizes;
- validate all chunk lengths and checksums when reading an untrusted capture;
- keep symbol maps separate when a shipping build must not reveal them;
- require explicit authorization for remote streaming or upload.

`Explicit` privacy permits selected paths and dynamic strings only when the
application configures them deliberately. It is not an “record everything”
escape from size limits.

## 25. Determinism and testing

The profiler must accept fake providers for clock, CPU counters, process memory,
and GPU timestamps. Deterministic tests use explicit timestamps and one-step
collector drains.

Required tests include:

- nested spans and exclusive/inclusive time;
- all returns and failable exits from an `@Profile` function;
- cross-thread asynchronous spans and flows;
- two same-named symbols remaining distinct;
- context propagation through job submit/resume/cancel;
- track timestamp monotonicity and clock-error reporting;
- producer overflow, gap markers, and both overflow policies;
- collector reordering without violating track order;
- truncated final chunk recovery;
- checksum failure and unknown optional/required chunks;
- file rotation and size bounds;
- counter, gauge, distribution, and percentile aggregation;
- allocation/deallocation token reuse safety;
- privacy redaction and bounded dynamic metadata;
- disabled-category fast path;
- audio-callback recording with allocation/lock instrumentation asserting zero;
- GPU capability fallback without synchronous waits;
- snapshot consistency while recording;
- sink failure without application failure;
- deterministic Chrome JSON and summary export.

Performance tests compare an uninstrumented build, `Off`, `Counters`,
`Timeline`, and `Detailed` using the same workload.

## 26. Command-line workflow

The eventual engine tool should support:

```text
azora profile run --mode timeline --output game.aztrace -- ./game
azora profile inspect game.aztrace
azora profile summary game.aztrace --format json
azora profile export game.aztrace --format chrome-json
azora profile compare baseline.aztrace candidate.aztrace
```

`inspect` validates and prints capabilities, gaps, top consumers, frame
percentiles, memory, I/O, jobs, GPU, and profiler overhead. `compare` requires
compatible build/workload metadata or an explicit override and reports
confidence/sample counts rather than treating one frame as a regression.

CI budgets may be expressed over stable summary metrics:

```text
frame.p95 <= 16.67 ms
frame.p99 <= 25.00 ms
audio.underruns == 0
memory.peak <= 512 MiB
profiler.dropped_events == 0
```

## 27. Implementation phases

### Phase 1: recording core and file capture

- add `azora-profiler` and `engine.profiler`;
- define session, config, IDs, sites, tracks, contexts, spans, metrics, and
  errors;
- add a monotonic platform clock;
- implement preallocated per-thread buffers and one collector;
- implement `.aztrace` header/chunks/checksums and truncated-file recovery;
- add frame markers, manual spans, counters, and instants;
- produce text, summary JSON, and Chrome Trace Event JSON;
- add deterministic fake-clock and overflow tests.

### Phase 2: automatic engine instrumentation

- add compiler-emitted static site/symbol descriptors;
- implement `@Profile` and `@NoProfile` lowering;
- wrap app frames, ECS phases, and `@System` calls;
- propagate contexts and flows through `engine.jobs`;
- instrument `engine.io` and allocator counters;
- add profiler self-overhead metrics.

### Phase 3: renderer, GPU, audio, and media

- instrument render extraction, encoding, submission, and present;
- add Metal GPU timestamp/counter provider and capability fallback;
- add real-time-safe audio callback metrics;
- connect video/audio/media stage contexts defined by `VIDEO.MD` and
  `AUDIO.MD`;
- add asset-to-upload-to-render flows.

### Phase 4: detailed diagnostics

- add per-thread CPU state and process memory providers;
- add allocation lifetime tracking and sampled stacks;
- add flight-recorder triggers and bounded file rotation;
- add direct Perfetto protobuf export;
- add capture comparison and CI budget tooling.

### Phase 5: live visualization

- add `azora-profiler-ui`;
- expose immutable periodic snapshots;
- implement frame, CPU, jobs, memory, GPU, audio, and media graphs;
- add a local authenticated streaming sink for development tools;
- keep the recording protocol and producer API unchanged.

## 28. Acceptance criteria

### Correct attribution

- same-named symbols, sites, jobs, assets, and contexts remain distinct;
- a job's queue wait and execution are connected to its submitting context;
- CPU, wait, and GPU time are not added into one misleading duration;
- inclusive/exclusive time is correct for nested spans;
- incomplete intervals are visibly marked.

### Recording safety

- the disabled hot path performs no allocation, lock, file I/O, or string work;
- a registered producer writes without a shared mutex;
- audio callback recording allocates and blocks zero times;
- a full buffer drops/stops according to policy without waiting;
- sink or disk failure does not crash the application;
- collector work never runs on the measured jobs pool.

### File reliability

- a normal capture reopens with all metadata and events;
- a capture truncated during any chunk retains every previous complete chunk;
- unknown optional chunks are skipped and required-version mismatches fail
  clearly;
- size limits and rotation are deterministic;
- event loss and unclean shutdown are reported.

### Engine coverage

- frames and every enabled ECS system are timed by stable symbol identity;
- jobs expose queue, active, suspended, completion, cancellation, and deadline
  intervals;
- I/O reports bytes, latency, cache status, and resource context;
- memory reports resident/current/peak and allocation rate;
- render reports CPU submission separately from GPU duration;
- audio reports callback deadline and underrun cause evidence;
- media reports decode parallelism, queues, drops, uploads, and A/V drift.

### Overhead

- `Off` is statistically indistinguishable from a build with runtime recording
  disabled in the reference benchmark;
- `Counters` remains below the documented shipping overhead budget;
- `Timeline` remains below the documented development overhead budget under the
  reference event rate;
- overhead, memory, dropped events, and sampling rate are present in every
  capture so the budgets are auditable;
- Detailed mode is labeled and never used as an unqualified performance
  baseline.

The concrete percentage budgets should be fixed only after the Phase 1
benchmark exists. The design target is below 1% CPU for `Counters` and below 3%
for the reference `Timeline` workload, but a measured published budget is more
honest than an untested promise.

## 29. Resolved architecture decisions

1. **Package ownership:** `azora-profiler` owns the neutral recording core and
   canonical types. Platform counters, exporters, and future UI are adapters or
   separate packages.
2. **First product:** file capture is first. Live graphs consume the same
   collector snapshots later; producers are not rewritten for the UI.
3. **Identity:** costs are keyed by stable symbol, site, track, and context IDs.
   Names and paths are labels only and never determine ownership.
4. **Hot-path transport:** each thread writes to a preallocated bounded buffer.
   Producers never block. Overflow creates explicit gaps or stops the capture.
5. **Collector:** one unprofiled infrastructure collector thread drains
   buffers and writes sinks. It is not an application worker pool. Offline
   export may use `engine.jobs` at `Background` priority.
6. **Storage:** `.aztrace` is the canonical append-only, chunked,
   crash-tolerant format. Chrome JSON and summaries are offline exports;
   Perfetto protobuf is a later direct export.
7. **Timing:** all duration math uses an integer monotonic nanosecond clock.
   Wall time and other clock domains are metadata with explicit correlation.
8. **Compiler ergonomics:** `@Profile`, `@NoProfile`, and static site lowering
   provide low-overhead instrumentation without adding language keywords.
9. **Metrics and tracing:** spans, metrics, events, flows, resources, and future
   stack profiles share context and semantic IDs so one resource can be followed
   across ECS, jobs, I/O, CPU, GPU, audio, and media.
10. **Real-time safety:** audio and other deadline callbacks may emit only
    fixed-size events into pre-registered buffers. No allocation, lock, dynamic
    metadata, callback, or file operation is permitted.
11. **GPU timing:** backends use hardware timestamps/counters when supported and
    report reduced capability otherwise. Profiling never adds a synchronous GPU
    wait.
12. **Privacy:** safe redaction is the default, captures are local and bounded,
    and remote transfer always requires explicit authorization.
