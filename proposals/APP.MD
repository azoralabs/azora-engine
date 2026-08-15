# Azora App — Application Host and Schedule Orchestration

Status: Proposal building on a working host loop
Package: `azora-app`
Module: `engine.app`

## 1. Decision

`azora-app` owns application lifetime and orchestration: startup, frame timing,
fixed-step accumulation, schedule phases, presentation, suspension, and orderly
shutdown. It does not become a service locator or dynamic plugin registry.
Subsystems remain ordinary packages whose systems are discovered and ordered at
compile time.

The host must support three equally valid modes:

- windowed, where Platform supplies windows and GPU presentation surfaces;
- embedded, where another host calls `start`, `frame`, and `shutdown`;
- headless, where simulation, networking, tests, and servers run without GPU or
  window dependencies.

## 2. Current implementation audit

The package already provides `GameSystem`, an `Engine` pack, configuration for
one window and clear color, startup/update callback lists, an ECS `World`,
`Time`, `SystemPlan`, and a complete loop over the current schedule phases. It
advances variable time, progresses the world, drains fixed steps, presents, and
shuts Platform down.

Important gaps:

- initialization failure is silently converted into an early return;
- window creation and rendering are mandatory and hidden inside `run`;
- only one window and one frame driver are possible;
- callbacks and reflected ECS systems form two scheduling paths;
- fixed updates run after variable update and have no catch-up budget;
- interpolation alpha, suspend/resume, focus, low-power, and device-loss events
  are absent;
- teardown ordering and exit reasons are not observable;
- Jobs and Profiler have no host integration.

## 3. Public model

```azora
enum AppRunMode {
    Windowed
    Embedded
    Headless
}

pack FixedStepPolicy {
    fin seconds: std::Double
    fin maxStepsPerFrame: std::Int
    fin discardExcess: std::Bool
}

pack AppConfig {
    fin title: std::String
    fin width: std::Int
    fin height: std::Int
    fin mode: AppRunMode
    fin fixedStep: FixedStepPolicy
}

error AppFault {
    InvalidConfiguration
    PlatformUnavailable
    WindowCreationFailed
    SurfaceCreationFailed
    DeviceLost
    StartupFailed
    ScheduleFailed
}

enum AppExitReason {
    Requested
    WindowClosed
    HostStopped
    DeviceLost
    StartupFailed
}
```

`AppHost` replaces the ambiguous public `Engine` name while `Engine` remains a
compatibility alias during migration. Configuration is immutable after startup;
runtime changes use explicit window, timing, and quality commands.

## 4. Canonical frame schedule

One rendered frame executes:

1. pump Platform events and publish Input state;
2. update real, game, and presentation clocks;
3. run `PreUpdate` once;
4. run zero or more bounded `FixedUpdate` steps;
5. publish interpolation alpha;
6. run `Update` and `PostUpdate` once;
7. extract and prepare render state;
8. run `Render`, submit, and present when a surface exists;
9. run `Last`, merge deferred commands, and process exit/suspend requests.

`Startup` runs once before the first frame. Shutdown runs in reverse dependency
order even after a recoverable startup failure. A catch-up cap prevents a slow
frame from creating an endless fixed-step spiral; discarded time is measured
and visible in Profiler.

## 5. Scheduling and jobs

Reflected `@System` functions are the canonical gameplay path. `GameSystem`
callbacks remain a compact compatibility and embedding boundary, but compile to
ordinary schedule nodes rather than running in a hidden second list.

The host asks ECS for access-aware batches and Jobs executes those batches. The
host itself does not know worker details. Main-thread, render-thread, audio
real-time, and platform-affine work are explicit constraints. Deterministic
fixed-step command merging uses stable system symbols, never registration order
or display names.

## 6. Multi-window, headless, and embedding

Windows are identified by stable `WindowId` values and may attach zero or more
GPU surfaces. Closing a secondary window does not terminate the application
unless policy says so. Headless mode excludes Platform and GPU providers from
the runtime dependency closure and can advance from an injected clock.

Embedded hosts can drive one frame, supply external events and time, request a
render only when needed, and inspect `AppExitReason`. No embedded call blocks in
an internal loop.

## 7. Diagnostics and delivery

Profiler records frame phases, fixed-step count, discarded simulation time,
system batches, command merge, event pump, extraction, presentation, sleep,
startup, and shutdown. The host inspector shows clocks, windows, surfaces,
active mode, pause/suspend state, exit reason, and schedule graph.

Delivery:

1. introduce `AppConfig`, `AppHost`, explicit faults, and deterministic teardown;
2. unify callbacks with schedule nodes and reorder fixed-step execution;
3. add bounded catch-up, interpolation, injected clocks, and headless mode;
4. add multi-window surfaces, suspend/resume, device-loss recovery, and Profiler;
5. remove mandatory Platform/GPU closure from embedded and server builds.

Acceptance requires identical fixed-step results across render rates, no hidden
second scheduler, successful headless tests, recoverable initialization errors,
and complete teardown after every partial-startup failure.
