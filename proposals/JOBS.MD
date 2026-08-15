# Azora Jobs — Bounded Parallel Work Scheduler

Status: Proposal replacing a compiler-smoke-test implementation
Package: `azora-jobs`
Module: `engine.jobs`

## 1. Decision

`azora-jobs` owns CPU worker scheduling, job dependencies, cancellation,
priorities, parallel ranges, and completion synchronization. ECS owns conflict
analysis and system batching; Jobs executes the batches. App owns frame phases;
Profiler observes Jobs. Audio's real-time callback and OS event threads never
run arbitrary jobs.

The default scheduler is a bounded work-stealing pool with one worker per useful
CPU core after reserving configured main/render/audio capacity. It must remain
ergonomic for small tasks without hiding unbounded allocation or thread
creation.

## 2. Current implementation audit

The package currently contains only `azNoopJob` and `azIntJob`. They prove that
basic `async func` lowering links, but there is no scheduler API, pool, worker,
queue, cancellation, priority, dependency, range partitioning, shutdown,
diagnostic, or test.

## 3. Public vocabulary

```azora
enum JobPriority {
    Critical
    Interactive
    Normal
    Background
}

enum JobState {
    Waiting
    Ready
    Running
    Completed
    Cancelled
    Failed
}

pack JobId {
    fin value: std::Long
    fin generation: std::Int
}

pack CancelToken {
    fin id: std::Long
    fin generation: std::Int
}

pack JobBudget {
    fin maxQueued: std::Int
    fin maxWorkers: std::Int
    fin grainSize: std::Int
}

error JobFault {
    QueueFull
    InvalidDependency
    DependencyCycle
    Cancelled
    SchedulerStopping
    WorkerFailed
}
```

Priority is urgency, not permission to starve lower queues. `Critical` is for
short frame-unblocking work, never long decode or compilation. `Interactive`
serves visible frame work, `Normal` serves ordinary simulation, and
`Background` serves import, cache, and lookahead work. Audio/video decoding can
use Interactive or Normal jobs but the audio device callback cannot wait on
them.

## 4. Job groups and dependencies

A `JobGroup` owns child jobs, cancellation, completion, and error aggregation.
Submitting a group is transactional: invalid dependencies or insufficient queue
capacity do not publish half a graph. Dependencies are stable `JobId` values,
not task names.

Parallel range helpers divide arrays, ECS chunks, animation instances, decoder
packets, and procedural regions by an explicit grain. Nested parallel work joins
cooperatively so a worker waiting for children executes other ready work rather
than blocking an operating-system thread.

## 5. Cancellation and shutdown

`CancelToken` is the public primitive. Cancellation is monotonic, idempotent,
generation-checked, and inherited by child groups. Running work observes it at
documented safe points. Cancellation does not kill a thread or unwind through
foreign code.

Shutdown stops admission, cancels optional work, drains required teardown jobs,
joins workers, and reports jobs that ignored cancellation. App owns when this
happens; provider packages own cleanup of their resources.

## 6. Determinism and affinity

The scheduler may execute independent work in any order. Deterministic systems
write to disjoint ranges or command buffers and merge by stable system/chunk
symbol afterward. Jobs never promises deterministic wall-clock ordering.

Affinity supports Main, AnyWorker, Render, and provider-defined serial lanes.
Affinity is exceptional and visible in Profiler. GPU submission and Platform
event pumping remain on their owning threads.

## 7. Pressure and diagnostics

All queues are bounded. Submission returns pressure instead of allocating an
unlimited backlog. Metrics include ready/running jobs, queue high-water marks,
steals, worker utilization, wait time, run time, cancellation latency, failed
jobs, dependency fan-out, main-thread assists, starvation prevention, and idle
sleep.

The inspector renders the dependency graph, critical path, lane, priority,
owner symbol, state, parent group, cancellation source, and captured stack when
available.

## 8. Delivery and acceptance

1. fixed worker pool, bounded queues, IDs/generations, groups, and joins;
2. priorities, fair stealing, cancellation, shutdown, and deterministic tests;
3. parallel ranges and ECS schedule-batch execution;
4. profiler traces, affinity lanes, pressure policy, and oversubscription tests;
5. decoder/import/procedural integrations and WebAssembly capability fallback.

Acceptance requires no thread creation per job, no unbounded queue, cooperative
nested joins, bounded cancellation latency, clean shutdown, race/stress tests,
and deterministic ECS merge results under randomized execution order.
