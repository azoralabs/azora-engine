# Azora Streaming — Async Asset and Resource Residency

Status: Proposal
Primary package: `azora-streaming`
Primary module: `engine.streaming`

## 1. Decision

Streaming is a unified residency scheduler for file ranges, decoded CPU assets,
GPU resources, media buffers, and World cells. It accepts dependency-aware
requests with importance, deadline, quality, and cancellation; enforces separate
I/O, CPU, upload, and memory budgets; and publishes immutable generations only
when dependencies are ready. It does not decide game-level spatial relevance—
World and subsystem policies submit that demand.

## 2. Current engine audit

`engine.io` can synchronously read a whole file into `Blob`; Image decodes BMP;
Font and Tracker synchronously load assets; GPU creates resources directly;
Video has bounded frame queues; Audio has a dedicated real-time PCM pool;
Tilemap has sparse chunks. There is no async range I/O, asset registry, content
symbol, dependency graph, cache, residency budget, GPU upload queue, cancellation,
or generation publication. `engine.jobs` currently exposes concurrency names but
does not yet implement the scheduler described by Audio/Video proposals.

`engine.assets` will own canonical `AssetId`, import/cooking, target variants,
and cooked manifests. Streaming consumes those manifests and must not become an
editor asset database.

## 3. Public model

```azora
pack StreamTicketId {
    fin value: std::Long
}

enum ResidencyState {
    Missing
    Requested
    Reading
    Decoding
    Uploading
    Resident
    Evicting
    Failed
}

enum StreamPriority {
    Background
    Soon
    Visible
    Critical
}

pack StreamRequest {
    fin asset: AssetId
    fin priority: StreamPriority
    fin quality: std::Int
    fin deadline: std::Double
    fin owner: ContentSymbol
}

@Resource
pack StreamingBudgets {
    var ioBytesPerSecond: std::Long
    var decodeMillisPerFrame: std::Double
    var uploadBytesPerFrame: std::Long
    var cpuResidentBytes: std::Long
    var gpuResidentBytes: std::Long
}
```

## 4. Cooked manifests and dependencies

Streaming consumes Assets-owned versioned manifests: kind, source ranges,
selected variant, dependencies, compression, checksums, estimated costs, and
fallback chain. Paths are source metadata, never runtime identity. Bundles group
small ranges for efficient reads without making every member share residency.

Dependencies form a DAG; cycles are build errors except explicit weak references.
A request expands dependencies and selects a target-compatible variant before
work begins.

## 5. Pipeline

1. merge requests and owner pins;
2. select variant/quality and expand dependencies;
3. schedule cancellable range reads;
4. verify, decrypt where authorized, and decompress;
5. decode/compile into immutable CPU generation;
6. stage GPU uploads or subsystem-specific publication;
7. fence GPU availability;
8. atomically publish handle generation;
9. feed access/importance telemetry to eviction;
10. retire old generations after all leases/fences release.

Work is deduplicated by asset, variant, and generation. Priority inheritance
raises dependencies. Starvation age prevents endless background postponement.

## 6. Handles and fallbacks

Callers hold stable asset handles that resolve to a current generation or
declared fallback. Missing detail uses lower mip/LOD/coarse parent/default asset.
Hot reload publishes a new generation and retires the old one safely. A handle
never exposes raw mapped pointers or GPU addresses beyond a lease scope.

Media streaming remains queue/deadline specialized, but uses shared I/O and job
budgets. Audio callback memory never enters general eviction.

## 7. Eviction and GPU residency

Eviction considers pin count, visibility, deadline, recency, cost to reload,
fallback coverage, dependency sharing, and subsystem policy. It first lowers
quality, then removes cold detail, and only finally removes the base asset.
In-flight GPU generations retire after fences.

On Metal-capable systems, residency sets and sparse resources can reduce binding
and memory overhead; portable providers emulate the same public policy with
heaps, texture arrays, or ordinary allocations.

## 8. Failure and security

Checksums, size/ratio limits, schema validation, path sandboxing, cancellation,
timeouts, retry/backoff, and typed errors apply before publication. Corrupt or
hostile data cannot allocate from untrusted declared sizes. Failure resolves to
fallback where legal and remains observable by asset symbol.

## 9. Diagnostics and delivery

The inspector shows request owners, priorities, dependencies, stages, queue age,
I/O ranges, compression, residency, leases, fallbacks, evictions, and memory
heaps. Counters include bytes/read latency, decode/upload time, cache hit rate,
queue age, cancellations, fallback frames, resident bytes, and thrashing.

Delivery:

1. consume Asset IDs/manifests, add async range I/O, tickets, cancellation,
   memory cache.
2. dependency scheduler, Jobs priorities, decode budgets, generation handles.
3. GPU uploads/fences, CPU/GPU budgets, LOD/mip fallback, hot reload.
4. World/Shard/Material/Landscape/media integration and sparse resources.
5. package/CDN distribution, predictive streaming, remote sources, tooling.

Metal references: [residency sets](https://developer.apple.com/documentation/metal/simplifying-gpu-resource-management-with-residency-sets) and [sparse textures](https://developer.apple.com/documentation/metal/reading-and-writing-to-sparse-textures).
