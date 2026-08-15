# Azora ECS — Entity Component System and Scheduler

Status: Proposal building on substantial implementation
Primary package: `azora-ecs`
Primary module: `engine.ecs`

## 1. Decision

ECS remains Azora Engine’s authoritative data and scheduling substrate. Preserve
the current generational `Entity`, typed `Storage<T>`, revisions, deferred
commands, resources, events, and schedule planning, then add compiler-lowered
typed queries, stable component symbols, chunk/archetype-capable storage,
parallel execution, relationships, snapshots, reflection, and tooling behind
the existing value-level API.

The accepted query surface is exactly:

```azora
q: @query [Transform!, Velocity&] @with Player @without Disabled
```

No alternate `with`/`without` spelling is part of this proposal.

## 2. Current implementation audit

Implemented today:

- generational entity allocation/reuse, liveness, names, parent/child counts,
  prefab/resource flags, fixed-step clock fields, and world revision;
- typed sparse `Storage<T>` with insert/get/remove, entity lists, revision,
  added/changed tracking, and query cursor intersections/subtractions;
- `QueryAccess` read/write/with/without/added/changed sets and conflict checks;
- resources, two event-queue implementations, deferred `CommandBuffer`;
- `SystemPlan` declarations, phases, before/after/set constraints, deterministic
  order, conflict metadata, and phase execution;
- tests for identity, storage changes, event readers, ordering, and access
  conflict/disjointness.

Known gaps:

- the typed `@query [...] @with ... @without ...` syntax is documented in source
  but not lowered by the compiler; old placeholder macros were correctly removed
  because they discarded filters;
- systems are not yet invoked through generated typed parameter adapters;
- sparse storage uses linear searches/arrays and is not an archetype/chunk engine;
- scheduler access is represented by component names instead of stable symbols;
- no actual parallel executor, command ordering contract across workers, or jobs;
- parent relation is IDs/counts, not a general cycle-safe relationship graph;
- resource/event APIs overlap and need one canonical implementation;
- no serialization, snapshots, rollback, replication metadata, or inspector.

## 3. Identity

```azora
pack ComponentId {
    fin value: std::Long
}

pack ResourceId {
    fin value: std::Long
}

pack SystemId {
    fin value: std::Long
}

pack EventId {
    fin value: std::Long
}
```

The compiler emits symbols from declaration identity plus package/schema
versioning. Names remain diagnostics only. Query access, snapshots, networking,
profiler sites, and IDE navigation all use symbols.

## 4. Query semantics

`T&` is shared access, `T!` is exclusive access, and bare marker components in
filters carry no row value. `@with T` requires presence; `@without T` excludes
presence. Added/changed filters compare per-storage ticks against the system’s
last successful run. A query borrows storages for its iteration scope and may
not structurally mutate them. Commands defer structural changes.

```azora
@System(.Update)
func integrate(
    q: @query [Transform!, Velocity&] @with Render @without Disabled,
    time: Time&,
) {
    for [transform!, velocity&] in q {
        transform.translation += velocity.linear * time.deltaSecs
    }
}
```

The compiler lowers the declaration to a query plan with component symbols,
borrow modes, filters, change ticks, cursor/archetype matches, and scheduler
access. The runtime never parses the source spelling or type names.

## 5. Storage evolution

The public `Storage<T>` remains valid. The runtime may initially accelerate its
sparse set with entity-to-dense indices, then introduce archetype chunks for
common query shapes. A component registry selects storage strategy per component:
table/chunk, sparse, marker, external, or pinned. Moving an entity between
archetypes is structural and deferred.

Chunk layout aligns columns, batches change ticks, supports vectorized iteration,
and exposes no raw addresses outside a borrow. Stable `Entity` identity survives
moves. Large external resources such as meshes/audio remain handles, not inline
component payloads.

## 6. Schedule and parallelism

Systems declare phase, explicit before/after/set constraints, and compiler-
generated access. The planner builds a deterministic DAG, detects unknown/cyclic
constraints, partitions conflict-free batches, and submits them to Jobs. Ties use
stable `SystemId`, not registration timing.

Deferred commands carry system, worker, and local sequence symbols. The commit
order is deterministic. Exclusive world systems form explicit barriers.
Failures publish diagnostics and follow phase policy; partial structural commits
are not allowed.

## 7. Events, resources, and relationships

One canonical multi-reader `Events<T>` survives for current/previous frame
windows, sequence cursors, lag reporting, bounded growth, and explicit clear.
Resources are typed singleton cells with borrow/change ticks and optional
initialization. Neither uses `res` or `mut res` surface types.

Relationships store stable source/target entities plus a relation component.
Built-in Parent enforces one parent and no cycles, maintains ordered children,
and handles despawn policy. Queries can traverse relationships through explicit
APIs; ordinary component queries remain flat and cacheable.

## 8. Snapshots and integration

Schema reflection identifies serializable fields, defaults, migrations, and
authority. Snapshots map entities to stable World/Network/Replay symbols rather
than local IDs. Physics and other external worlds contribute adapters. Reactive
UI observes component/storage/world revisions and composes entities through
deferred structural commits as defined in `REACTIVE_ECS_UI.MD`.

## 9. Diagnostics and delivery

The inspector shows entities, archetypes/storages, component values/revisions,
query plans, system DAG/batches, borrow conflicts, commands, events/readers,
resources, relationships, and memory fragmentation. Profiler counters include
entities, archetypes, moves, query rows, skipped systems, batch parallelism,
command counts, event lag, commit time, and bytes by component.

Delivery:

1. stable symbols, fast sparse indices, canonical Events/Resource APIs.
2. compiler-lowered accepted query syntax and typed system adapters.
3. deterministic command merge, real parallel batches through Jobs, diagnostics.
4. archetype/chunk storage strategies, relationships, query cache, inspector.
5. snapshots/migrations, Networking/Replay, hot reload, large-scale benchmarks.

