# Azora Core — Engine Metadata, Time, Signals, and Global Control

Status: Proposal building on implemented foundations
Package: `azora-core`
Module: `engine.core`

## 1. Decision

`azora-core` is the smallest portable engine dependency. It owns engine
annotations, schedule vocabulary, clocks, revisioned signals, stable engine
symbols, and process-independent control messages. It owns no filesystem,
window, renderer, ECS storage, native object bridge, or worker scheduler.

Every engine package may depend on Core; Core must therefore depend only on the
Azora standard library and compiler/runtime primitives. This rule is enforced by
the package graph.

## 2. Current implementation audit

Already implemented:

- `SystemPhase` and the `@Component`, `@System`, `@Event`, `@Relation`,
  `@Resource`, and `@Query` annotations;
- variable/fixed `Time` with delta clamping;
- generic revisioned `Signal<T>`;
- `EngineRegistry`, `EngineClock`, and the `AzEngine` dependency graph;
- application-wide `exit()` and `exitRequested()`.

Gaps and inconsistencies:

- Core imports `engine.io`, but its manifest declares no dependency and a core
  metadata package should not acquire filesystem/raw-buffer ownership;
- annotation ordering fields are comma-separated display strings rather than
  stable compiler symbols;
- annotation documentation still describes obsolete system parameters;
- one `Time` value mixes real, game, fixed, and presentation concerns;
- `Signal<T>` has no subscription/invalidation boundary or write batching;
- process-wide exit state lives in a low-level C bridge reached through I/O;
- global registries expose counters but no lifecycle or ownership contract.

## 3. Stable symbols and metadata

System, set, component, event, resource, and relation identity uses compiler
symbols. Names remain diagnostics only. Compile-time schedule metadata stores
resolved symbol arrays and rejects unknown, ambiguous, and cyclic constraints
before runtime.

```azora
pack EngineSymbol {
    fin value: std::Long
}

pack SystemOrdering {
    fin before: std::Array<EngineSymbol>
    fin after: std::Array<EngineSymbol>
    fin sets: std::Array<EngineSymbol>
    fin order: std::Int
}
```

String annotation arguments remain source ergonomics only when the compiler can
resolve them lexically to symbols. Compiled metadata never reparses a
comma-separated list.

## 4. Clock model

Core separates clocks while keeping `Time` as a compatibility view:

```azora
pack ClockSnapshot {
    fin realSeconds: std::Double
    fin gameSeconds: std::Double
    fin deltaSeconds: std::Double
    fin fixedSeconds: std::Double
    fin interpolation: std::Double
    fin frame: std::Long
    fin fixedTick: std::Long
}
```

Real time never pauses or scales. Game time may pause and scale. Fixed time
advances only by exact ticks. Presentation time may interpolate or predict.
Media and network clocks remain owned by their subsystems and use explicit
conversion/synchronization contracts.

## 5. Signals and control

`Signal<T>` remains a lightweight revisioned cell. Writes are explicit and may
be grouped in a transaction that increments revision once. Reactive ownership,
retention, and UI dependency tracking remain defined by the reactive UI model;
Core supplies only the observable revision contract.

Application control is represented as an engine message rather than a direct
dependency on I/O or Platform:

```azora
enum AppControlKind {
    None
    Exit
    Restart
    Suspend
    Resume
}

@Resource
pack AppControl {
    var requested: AppControlKind
    var revision: std::Long
}
```

The App host consumes control requests and Platform implements OS interaction.
A minimal runtime hook may back the earliest bootstrap, but it is not imported
through `engine.io`.

## 6. Compatibility and layering

- Existing annotations and `Time` remain source-compatible through the first
  migration phase.
- Core annotations use only current Azora declarations and query grammar.
- `EngineRegistry` becomes diagnostic installation state, not a service lookup.
- `EngineClock` delegates to App's clock service instead of becoming a second
  authoritative clock.
- No Core API exposes pointers, file paths, native handles, GPU objects, entity
  IDs, or provider objects.

## 7. Testing and delivery

Tests cover delta clamping, pause/scale, exact fixed ticks, interpolation,
revision batching, symbol resolution, schedule-cycle diagnostics, event
lifetime metadata, and Core builds for native and WebAssembly without engine
packages.

Delivery:

1. remove the undeclared I/O edge and update annotation documentation;
2. add compiler-resolved system/set symbols and schedule validation;
3. split clock domains while retaining the `Time` compatibility view;
4. add signal transactions and App control messages;
5. enforce Core's dependency ceiling in package-graph tests.

Acceptance requires Core to compile alone, contain no platform/allocator/filesystem
bridge, resolve schedule ordering by symbol, and expose one coherent clock and
signal contract to every higher package.
