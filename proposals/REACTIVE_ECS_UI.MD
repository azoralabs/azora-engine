```azora
@System(.Startup)
react func mainMenu(world: World&) {
    remember var mustClose = false

    effect mustClose == true { // we have to add effect cond, when this cond first became true, then it executes
        azora::engine::exit()
    }

    @compose world {
        column(
            modifier: .fillMaxSize()
            verticalArrangement: .Center
            horizontalAlignment: .CenterHorizontally
        ) {
            button {
                text("Play")
            }
            button {
                text("Settings")
            }
            button(
                onClick: [&mustClose] {
                    mustClose = true
                }
            ) {
                text("Quit")
            }
        }
    }
}

@System(.Update)
func changeAllButtonText(
    query: @query [Button!, Child<Text!>]
) {
    for e in query { // change all
        e.1.text = "--------"
    }

    loop query { // only change play
        if query.current.child.text == "Play" {
            e.1.text = "--------"
        }
    }
}
```

@compose - a macro to do world.instert or other stuff
column(() -> Unit) - a react func widget
@query - i remember we had this with @with, @without and so on
Button - is a component and it gets insterted in ecs when we call button {}

---

# Full proposal

## 1. Thesis

Azora Engine uses one state-to-output pipeline for gameplay, tools, and user
interfaces:

```text
owned state -> observed revisions -> scheduled systems -> committed changes
             -> reactive composition -> layout/input -> render commands
```

The pipeline is unified, but the storage responsibilities are not collapsed:

- the ECS world owns high-volume entity state and structural relationships;
- reactive owners own subscriptions, derived values, and UI-local state;
- the UI tree owns presentation identity, layout, focus, and semantics;
- the renderer owns provider resources and submitted draw work.

The same revision and owner rules connect these layers without making every
value an ECS component or every UI node a hidden global.

The proposal has four required properties:

1. `@compose world { ... }` is a deterministic world-construction and
   reconciliation macro, not an arbitrary side-effect escape hatch.
2. `@query` describes typed ECS access and is checked by the compiler/engine
   boundary rather than being a name-based loop convention.
3. Reactive effects run from committed state and schedule world mutations for a
   later boundary; they cannot recursively mutate the world during publication.
4. Every UI node has stable identity, owner lifetime, input semantics, and a
   renderer-neutral representation before a provider draws it.

## 2. Scope and non-goals

### 2.1 In scope

- ECS entities, components, resources, relationships, events, and queries;
- `@System` scheduling, phases, access conflicts, and change detection;
- reactive owner identity and `remember`/`retain`/`preserve` state;
- conditional effects and deterministic cleanup;
- `@compose` expansion into ECS operations and retained UI identity;
- UI components such as `Button`, `Text`, `Column`, and `Child<T>`;
- layout, modifiers, input routing, focus, accessibility, and navigation;
- immutable render extraction and provider boundaries;
- frame, fixed-step, transaction, replay, and disposal semantics;
- diagnostics and IDE navigation for all of the above.

### 2.2 Out of scope

- requiring one renderer, window system, GPU API, browser DOM, or font engine;
- making `@compose` a general macro for arbitrary hidden mutation;
- making every UI node an entity or every entity visible in the UI tree;
- making every component reactive;
- allowing a reactive effect to bypass authority, safety, or transaction rules;
- claiming that rendering or simulation success proves application correctness;
- replacing `DIPs/REACTIVE_DIP.MD` or the language ownership/effects model.

## 3. Existing engine decisions

The proposal builds on the current engine packages and names:

| Existing surface | Role in this proposal |
|---|---|
| `engine.core` | `SystemPhase`, `@Component`, `@System`, `@Event`, `@Resource`, `@Query`, `Time`, `Signal<T>` |
| `engine.ecs` | `World`, `Entity`, `Storage<T>`, query access, system plan, relations, structural state |
| `engine.ecs.events` | bounded double-buffered events and independent readers |
| `engine.ui.reactive` | `EcsObserver`, `ReactiveResource<T>`, revision-based host invalidation |
| `engine.ui.dom` | immutable `DomNode` tree, keyed reconciliation, stored event handlers, WebAssembly mount |
| `engine.ui.navigation` | typed bounded `NavBackStack<K>`, `NavDisplay`, lifecycle and revisions |
| `engine.ui` | immediate-mode compatibility helpers such as `button`, `uiText`, and `uiRect` |
| `engine.app` | `Engine`, clock advancement, world ownership, and phase driving |

The current implementation is intentionally simpler than the target design.
This document identifies the semantic target without pretending that every
annotation, query expansion, or renderer backend already exists.

## 4. Canonical syntax

The engine proposal uses the existing Azora reactive syntax directly. These are
the normative spellings for this design:

```azora
react func mainMenu(world: World&) {
    remember var mustClose = false
    effect mustClose {
        if mustClose {
            azora::engine::exit()
        }
    }
}
```

The state lifetime and binding mutability remain separate:

| Lifetime | Meaning |
|---|---|
| `remember` | survives reruns of the current reactive owner |
| `retain` | survives recreation of the owner in the current process |
| `preserve` | participates in explicit snapshot and restoration |

The ordinary binding still controls rebinding and mutation. For example,
`remember var` may be reassigned and mutated, while `remember fin` is stable
after initialization. The parser, compiler, engine, and IDE must use one owner
and invalidation model for these forms.

## 5. The unified revision model

Every observable engine value exposes a monotonically increasing revision:

```azora
spec Observable {
    prop revision: std::Long
}
```

The first implementations are:

- `Signal<T>` for owned reactive values;
- `World.revision` for structural entity changes;
- `Storage<T>.revision` for inserts, removals, and writes;
- `NavBackStack<K>.version` for navigation mutations;
- `ReactiveResource<T>.version` for application state;
- event sequence numbers for event streams.

The engine may add an `Observable` spec once generic spec bounds and property
access are sufficient. Until then, adapters may use the existing concrete
revision fields. The observable contract is not a license to expose every
component write to every observer.

### 5.1 Recorded reads

A reactive owner records the revisions it reads while evaluating a view or
derived value. A system records the component/resource access described by its
query and parameters. Both use the same invalidation predicate:

```text
rerun when a recorded dependency has advanced since the last successful run
```

The difference is scheduling:

- a system reruns in its declared engine phase;
- a view recomposes in the UI phase;
- an effect reruns under its owner after publication;
- a provider callback runs only on its declared affinity.

### 5.2 Revision granularity

The engine supports three levels of observation:

| Level | Use |
|---|---|
| world revision | entity creation, destruction, relationship, or global structural change |
| storage revision | any change in one component type or resource storage |
| row/change tick | a particular entity/component row changed |

An observer must request the narrowest level it needs. A HUD that reads one
player's `Health` should not invalidate from every `Health` component in the
world unless it explicitly requests a storage-wide aggregate.

## 6. ECS data model

### 6.1 Components

Components remain ordinary packs or enums marked by the engine annotation:

```azora
@Component
pack Button {
    fin label: std::String
    var enabled: std::Bool
}

@Component
pack Text {
    var value: std::String
}

@Component
pack Child<T> {
    fin parent: Entity
}
```

`@Component` provides engine metadata for storage, serialization, inspection,
change tracking, and query validation. It does not make a type reactive, UI,
renderable, or copyable.

Component identity is symbolic and module-qualified. The engine must not match
components by display name alone: two packages may declare different `Text`
types with different meanings.

### 6.2 Entities

An entity is a stable logical identity with a generation:

```azora
pack Entity {
    var id: std::Int
    var generation: std::Int
}
```

An entity handle is invalid after despawn or generation replacement. A stale
handle must produce a typed failure or a checked diagnostic; it must never
silently refer to a later entity that reused the same slot.

### 6.3 Resources

Resources are world- or application-scoped values:

```azora
@Resource
pack UiTheme {
    fin accent: Color
    fin cornerRadius: std::Double
}
```

`@res& T` is a shared read. `@res! T` is an exclusive write. Resource access is
part of the system access set and may be used by a reactive projection only
through an owned snapshot or a read-only reactive resource.

### 6.4 Relationships

`Child<T>` is a relationship component, not a convention hidden in a string.
The engine should provide indexed relationship metadata so parent/child
queries do not scan all entities. A relationship mutation is structural and
is staged through the same command/compose boundary as component insertion.

The following invariants are required:

- a child has at most one parent for a tree relationship;
- inserting a second parent either replaces the first through an explicit
  operation or returns a typed conflict;
- destroying a parent applies an explicit child policy;
- cycles are rejected for tree relationships;
- relationship updates advance the world revision;
- UI composition preserves source identity and does not infer parentage from
  an arbitrary component name.

## 7. `@query` and access semantics

### 7.1 Query shape

The query macro accepts yielded component terms followed by membership filters:

```azora
q: @query [Transform!, Velocity&] @with Player @without Disabled
```

This bracketed form is the only accepted query grammar. The macro expands it
to a typed query plan and access descriptor; there is no unbracketed shorthand
and no alternate runtime string-filter form.

| Term         | Meaning |
|--------------|---|
| `T&`         | shared borrow of component `T` |
| `T!`         | exclusive mutable borrow of component `T` |
| `T&?`        | optional shared component |
| `@with T`    | require `T` without yielding it |
| `@without T` | exclude entities containing `T` |
| `Changed<T>` | row changed since the selected tick |
| `Added<T>`   | row inserted since the selected tick |
| `Removed<T>` | row removed in the selected commit window |

`with Button` is symbolic component membership. It does not mean a type or
field whose text happens to be named `Button`.

### 7.2 Query iteration

The query is an owned cursor over borrowed rows:

```azora
for [transform!, player&] in q {
    transform.translation.x += player.speed * time.deltaSecs
}
```

If a callback form is preferred, the engine may provide:

```azora
q.each { row ->
    row.transform.translation.x += row.player.speed * time.deltaSecs
}
```

The following operations are invalid while a row borrow is live:

- `await` or task suspension;
- structural spawn/despawn/component insertion/removal;
- committing a world attempt;
- resetting or advancing the same cursor;
- disposing the world or scene owner.

The compiler diagnostic must identify the exact row borrow and invalidating
operation, not merely say “query cannot be used here”.

### 7.3 Query access and scheduling

`T!` contributes `Write<T>`, `T&` contributes `Read<T>`, and structural
operations contribute `StructuralWrite`. `with` and `without` contribute
membership dependencies but not a data read unless the query yields the value.

The scheduler may run systems in parallel only when their resolved access sets,
effects, provider affinities, and event merge policies are compatible.

## 8. `@System` and schedule phases

`@System` is engine metadata over an ordinary function:

```azora
@System(.Update, order: 20, runAfter: "input")
func changeAllButtonText(
    query: @query [Button!, Child<Text!>]
) {
    for [button!, child!] in query {
        if button.enabled {
            child.value = button.label
        }
    }
}
```

The exact parameter decoration may be expanded by the query macro. The
semantic rules are fixed:

- system discovery uses symbolic decorator metadata;
- phase and ordering are resolved before execution;
- access conflicts create schedule edges or prevent parallel execution;
- an update system cannot retain a query borrow across `await`;
- a frame system does not become reactive merely because a UI component is in
  its query;
- long-lived asynchronous work belongs to an explicit scene/entity/UI owner.

The current engine phases are:

```text
Startup -> PreUpdate -> Update -> PostUpdate -> FixedUpdate -> Render -> Last
```

The reactive/UI profile adds logical subphases without requiring a new runtime
phase in every backend:

```text
input collection
  -> input systems
  -> fixed/update systems
  -> structural commit
  -> reactive publication
  -> UI composition
  -> layout/input focus
  -> render extraction
  -> render
  -> cleanup
```

## 9. `@compose` semantics

### 9.1 Purpose

`@compose world { ... }` is a contextual macro that turns a declarative body
into a deterministic sequence of engine operations. It is not a second
imperative runtime and it must not hide arbitrary side effects.

The expansion has two modes:

| Mode | Purpose |
|---|---|
| initial composition | create entities/components/relationships for missing keyed nodes |
| recomposition | update matching nodes, create new nodes, remove absent nodes, dispose owners |

The macro receives an explicit world/view context. It cannot silently select a
global world, renderer, scene, or resource registry.

### 9.2 Expansion model

This source:

```azora
@compose world {
    column(key: "main") {
        button(key: "play") {
            text("Play")
        }
    }
}
```

conceptually produces:

```text
begin composition(owner, world)
  claim node key "main" under owner
  ensure Entity + Column + UiKey("main")
  claim node key "play" under "main"
  ensure Entity + Button + UiKey("play") + Child(parent: main)
  claim generated text child under "play"
  ensure Entity + Text(value: "Play") + Child(parent: play)
  mark unclaimed previous children for disposal
commit composition
```

The generated operations are staged. A failed composition does not leave a
half-created UI tree. The macro may use `attempt` internally, but the public
semantics are the same whether the backend uses a command buffer, entity
transaction, or retained provider tree.

### 9.3 `@compose` is not arbitrary mutation

The body may:

- construct component values;
- read resources and reactive values;
- call pure builders and approved UI constructors;
- attach event actions to owned nodes;
- issue declared navigation or state actions;
- use stable keys and explicit modifiers.

The body may not directly:

- call `world.spawn()` outside the composition context;
- despawn an entity owned by another composition;
- mutate unrelated gameplay components;
- perform blocking I/O or GPU submission;
- retain a query borrow across composition;
- call `exit()` except through an explicit effect/action as in the starter.

The engine may provide an explicit `compose::command` escape hatch for advanced
cases, but it must require a capability and produce an audit/debug record.

### 9.4 Composition identity

Every composition has an owner and a path. A child identity is:

```text
(composition owner, parent path, explicit key or source slot, node type)
```

Explicit keys are required for dynamic lists and recommended for all stateful
controls. Source position is only a fallback identity for static children.

Changing a key destroys the old node owner and creates a new one. Moving a
keyed child preserves its local state, focus, event handlers, and animation
state.

## 10. UI components and retained nodes

### 10.1 ECS-backed UI

The starter correctly treats `Button` as a component inserted by `button {}`.
The proposal makes the split explicit:

| Layer | Owns |
|---|---|
| UI ECS world | entity identity, semantic components, parent/child relationships |
| composition owner | key/path identity, reactive state, subscriptions, handlers |
| layout tree | constraints, measured size, arranged rectangle |
| render tree | immutable draw data and provider resource references |

An entity may have `Button`, `Text`, `Child<Text>`, `Layout`, and `Semantics`
components. The render provider must not infer accessibility or behavior from
the mere presence of `Button`.

### 10.2 Core UI component roles

The engine package defines these roles; applications can add components:

```azora
@Component pack UiKey { fin value: std::String }
@Component pack Layout { var constraints: Constraints }
@Component pack Rect { var x: Real; var y: Real; var w: Real; var h: Real }
@Component pack Text { var value: String }
@Component pack Button { var enabled: Bool }
@Component pack Image { fin asset: AssetId }
@Component pack Semantics { var role: UiRole; var label: String }
@Component pack Focusable { var tabIndex: Int }
@Component pack PointerTarget { var hitTest: HitTestPolicy }
```

These are not all required on every node. A node's role is the set of symbols
it carries, and a modifier adds or updates components in a typed way.

### 10.3 `Child<T>` and tree invariants

`Child<T>` is a relationship that records parent identity. The UI tree must
maintain:

- one parent per node unless a portal explicitly opts out;
- no cycles;
- sibling keys unique within one parent;
- children disposed before their parent;
- entity membership and retained provider identity updated atomically;
- semantic tree order matching the committed UI tree, not incidental storage
  order.

## 11. Reactive owners and effects

### 11.1 Conditional effects

The starter asks for:

```azora
effect mustClose == true {
    azora::engine::exit()
}
```

This is an effect with a condition expression. Its semantics are:

1. evaluate the condition in the current reactive owner;
2. record every reactive/ECS dependency read by the condition;
3. run the body once when the condition changes from false to true;
4. do not repeat while it remains true;
5. if it becomes false and later true again, run it again;
6. dispose it with the owner.

The condition must not be treated as a polling loop. An explicit dependency
form remains available:

```azora
effect [mustClose] {
    if mustClose {
        azora::engine::exit()
    }
}
```

The engine should lower conditional effects to a predicate cell plus a rising-
edge trigger. `effect [mustClose]` with an `if` is equivalent but more
expressive for multiple conditions.

### 11.2 Effect timing

Effects never run in the middle of composition. The ordering is:

```text
compose -> commit view state -> dispose obsolete effects -> run newly eligible effects
```

An effect that wants to mutate ECS writes an action or command buffer for a
declared future phase. It must not directly mutate a component that is being
iterated by the current system batch.

### 11.3 Effect cleanup

`effect defer` executes at owner disposal in LIFO order. Removing a keyed UI
node disposes its owner and therefore its subscriptions, handlers, tasks, and
provider resources. A handler must not survive the node that created it unless
it is explicitly transferred to a longer-lived owner.

## 12. UI layout and modifiers

### 12.1 Modifier design

Modifiers are immutable, ordered bundles:

```azora
column(
    modifier: Modifier
        .fillMaxSize()
        .padding(16.0)
        .verticalArrangement(.Center)
        .horizontalAlignment(.CenterHorizontally)
) { ... }
```

Modifier order is significant. A later operation may override an earlier
operation only where the modifier contract says it may. Modifiers do not
directly call a renderer; they produce layout, paint, input, focus, or
semantics metadata.

### 12.2 Layout passes

Each layout node participates in:

```text
measure(constraints) -> desired size
arrange(rectangle) -> child rectangles
```

The engine distinguishes logical units from device pixels, supports safe-area
insets and writing direction, and gives text providers an explicit measurement
effect. A layout cycle or non-converging intrinsic measurement is a diagnostic
with the node path and iteration count.

### 12.3 Invalidation kinds

The engine tracks invalidation narrowly:

```azora
enum UiInvalidation {
    Measure
    Arrange
    Paint
    HitTest
    Semantics
}
```

A text value may invalidate measure, arrange, paint, hit testing, and
semantics. A color change generally invalidates paint only. Navigation changes
invalidate the active root, not every hidden route.

## 13. Input, focus, and accessibility

### 13.1 Routed input

Input is converted by `engine.input` into typed events and routed through the
UI tree:

```text
provider -> capture target -> hit path -> focused target -> bubble path
```

Handlers may mark an event handled, request pointer capture, release capture,
or enqueue an action. Input is not broadcast to every reactive observer.

### 13.2 Button behavior

`Button` has semantic state and an action handler. Hover, pressed, focused,
disabled, and visited state are distinct values. A button must not infer
authorization from `enabled`; the action checks authorization again.

The current immediate-mode `App.button(...)` remains a compatibility adapter.
It creates a transient interaction node for one frame and returns the click
result. The retained `button {}` builder is the preferred path for reactive UI.

### 13.3 Focus

Focus belongs to the UI root and is identified by stable node key. Removing a
focused node applies an explicit fallback policy: next tab stop, previous tab
stop, parent, or root. Focus changes are committed before render extraction.

### 13.4 Accessibility

Visual nodes and semantic nodes are separate projections. Interactive nodes
must expose role, label, value/state, actions, and stable test ID where
applicable. A custom GPU-drawn control still needs a semantic representation.

## 14. Navigation and owner scopes

`NavBackStack<K>` remains typed and bounded. A navigation entry owns:

- its route key;
- its reactive owner;
- its composition root;
- its input/focus registrations;
- its child tasks and provider handles.

The lifecycle is:

```text
Created -> Active -> Suspended -> Destroyed
```

Suspended routes retain only the state explicitly marked `retain`/`preserve` or
the navigation policy declares retained. Destroyed routes dispose all local
effects and tasks.

A navigation mutation increments the stack revision. The active `NavDisplay`
recomposes only the affected route and transition overlay.

Scene transitions are transactional:

```text
prepare destination -> load/validate -> compose destination
-> switch active root -> dispose old route
```

If preparation fails, the old route remains active.

## 15. Render extraction

Composition and layout produce an engine-owned render representation. The
provider receives no `World!`, query row, mutable component, or reactive cell.

```azora
pack UiRenderFrame {
    fin frame: std::Long
    fin draw: std::Array<DrawCommand>
    fin text: std::Array<TextCommand>
    fin clips: std::Array<ClipRect>
    fin resources: std::Array<AssetId>
}
```

The renderer may be Metal, Vulkan, WebGL, WebGPU, a browser DOM host, a TUI,
or a test collector. All providers consume the same semantic extraction
contract but may lower the commands differently.

Render resources have generation identity and owner scope. Device loss, surface
resize, unavailable fonts, missing assets, and backpressure are typed provider
outcomes; they do not crash the ECS world by default.

## 16. ECS/reactive/UI frame contract

The normative per-frame contract is:

```text
1. collect provider input
2. publish input resources/signals
3. run PreUpdate systems
4. drain fixed-step accumulator and run FixedUpdate systems
5. run Update/PostUpdate systems
6. commit structural commands and attempts
7. rotate/deliver bounded event queues
8. publish ECS projections and revision tokens
9. run reactive recomposition and conditional effects
10. reconcile `@compose` trees
11. measure, arrange, resolve focus and semantics
12. extract immutable render commands
13. submit to the provider
14. run Last cleanup and dispose expired owners
```

The existing `engine.app.Engine` may implement this incrementally. The current
`runPhase` calls remain valid; the new composition, publication, and UI steps
are inserted at explicit boundaries rather than hidden inside `runPhase`.

### 16.1 Structural commit

Entity spawn/despawn, component insertion/removal, and relationship changes are
staged. A system can write existing component fields through its borrow, but
structural mutations become visible only after the current schedule batch has
ended.

### 16.2 Reactive publication

The UI observes owned snapshots or revision tokens, never a live ECS borrow:

```text
world writes -> commit -> revision advance -> projection/snapshot -> compose
```

An observer that needs only “something changed” uses a revision. An observer
that needs data reads an owned projection. The engine must not clone every
component for every UI owner.

## 17. Transactions and failure

The engine may implement the language/stdlib `attempt` contract for worlds.
An attempt journals component writes, structural commands, and events:

```azora
fin outcome = attempt world {
    fin button = world.get<Button!>(buttonEntity)
    if !button.enabled {
        fail Disabled
    }
    world.emit(PlayRequested())
}
```

Rules:

- success publishes once;
- typed failure rolls back writes and events;
- `defer` always runs;
- `await`, external I/O, and unjournaled provider mutation are forbidden;
- provisional entities become stable only after commit;
- nested attempts require savepoints or fail before execution;
- journal capacity is bounded and reported.

An effect condition such as `mustClose == true` is not a transaction failure. It
is an edge-triggered action predicate. `assert` remains a programmer contract,
not a user-visible event branch.

## 18. Concurrency and ownership

Systems may run in parallel if their query access and effects do not conflict.
UI composition may remain on the main thread initially, but it still operates
on owned immutable snapshots so a future backend can move layout or extraction
without changing source semantics.

Async handlers capture owned values and stable entity/key handles only. They
cannot capture:

- `Transform!`, `Button!`, or any mutable query borrow;
- a live query cursor;
- a frame-local render command;
- an owner-scoped provider pointer without transfer permission.

When an async task completes, the engine verifies its owner generation before
applying the result. A late completion is cancelled, ignored, or reported as
`StaleOwner`; it cannot update a replaced screen accidentally.

## 19. ECS and UI package responsibilities

The current package structure should evolve toward:

```text
packages/
  azora-core/        shared annotations, time, signals, engine metadata
  azora-ecs/         world, storage, query, relations, schedule, events
  azora-ui/          composition, UI components, layout, input, navigation
  azora-render/      extraction and renderer-neutral command types
  azora-platform/    window, event pump, device lifecycle
  azora-gpu/         GPU provider contracts and backend implementations
  azora-input/       typed keyboard, pointer, controller input
  azora-app/         frame host and application lifecycle
```

`engine.ui.reactive` remains the bridge between `std.reactive`, ECS revisions,
and UI owners. `engine.ui.dom` remains a browser provider/adapter; its
`DomNode` is one render target, not the universal UI node.

The immediate-mode helpers on `App` remain available for compatibility and
headless/simple applications. They should lower into the same interaction and
render command contracts where possible.

## 20. Example: complete reactive ECS UI

The starter example becomes a complete design when the ownership and phase
rules are made explicit:

```azora
@Component
pack Button {
    fin label: std::String
    var enabled: std::Bool
}

@Component
pack Text {
    var value: std::String
}

@Component
pack Child<T> {
    fin parent: Entity
}

@System(.Startup)
react func mainMenu(world: World&) {
    remember var mustClose = false

    effect mustClose == true {
        azora::engine::exit()
    }

    @compose world {
        column(
            key: "main-menu",
            modifier: .fillMaxSize()
                .verticalArrangement(.Center)
                .horizontalAlignment(.CenterHorizontally)
        ) {
            button(key: "play", onClick: {
                // enqueue PlayRequested; do not mutate unrelated world state
            }) {
                text(key: "label", "Play")
            }
            button(key: "settings", onClick: {
                // typed navigation action
            }) {
                text(key: "label", "Settings")
            }
            button(key: "quit", onClick: {
                mustClose = true
            }) {
                text(key: "label", "Quit")
            }
        }
    }
}

@System(.Update, runAfter: "input")
func changeAllButtonText(
    query: @query [Button!, Child<Text!>]
) {
    for [button!, child!] in query {
        if button.enabled {
            child.value = button.label
        }
    }
}
```

The compiler/engine expands this as:

1. discover `mainMenu` as a scheduled startup system;
2. allocate a reactive owner for the system/composition instance;
3. run composition against an explicit world context;
4. resolve keys and create or update entities/components/relationships;
5. retain the `mustClose` cell and conditional effect under that owner;
6. stage the composition commit;
7. run `changeAllButtonText` only when its query dependencies permit it;
8. publish committed UI revisions;
9. reconcile layout, input, and render output;
10. dispose the owner and all children when the startup screen is removed.

`changeAllButtonText` is intentionally an ECS system, not a reactive UI
effect. It may update component data in its query and the next UI publication
will observe the committed revision. This keeps simulation and presentation
work separate even when both target the same UI components.

## 21. Performance requirements

The first implementation may use simple arrays and linear storage, but the
contracts must allow the following optimizations:

- archetype/chunk or sparse-set component storage;
- cached query plans and access descriptors;
- row change ticks instead of whole-storage invalidation;
- revision coalescing during one frame;
- keyed UI subtree skipping;
- layout invalidation by category;
- pooled command/event buffers;
- render extraction on another thread;
- bounded snapshot/projection caches;
- provider resource generation reuse.

No optimization may change:

- stable component/entity symbols;
- owner/key identity;
- commit visibility;
- effect edge semantics;
- event delivery order within the declared merge policy;
- query borrow validity;
- focus or accessibility identity.

## 22. Diagnostics and IDE support

The IDE should navigate by resolved symbol identity, not matching names. It
must support:

- `Button` component declaration to every `button {}` insertion and query;
- `Child<Text>` relationship declaration to parent/child composition sites;
- a query term to its access mode, filters, and conflicting systems;
- a system to phase, order constraints, and schedule batch;
- a reactive cell to its owner, effects, and observed revisions;
- a UI key to its retained node, source view, focus, and accessibility node;
- a handler to the action/capability it enqueues;
- an asset to its provider, generation, and release owner;
- a render command to its source component or UI node.

Diagnostics should include:

- duplicate sibling keys;
- dynamic list without stable key;
- relationship cycle or multiple parent;
- query borrow crossing `await` or composition commit;
- structural world mutation during query iteration;
- reactive effect trying to mutate the current world batch;
- conditional effect that can never become true;
- effect with external I/O during composition;
- async result targeting a disposed owner;
- layout cycle or unbounded intrinsic measurement;
- inaccessible interactive node;
- provider call on the wrong thread/affinity;
- event or state publication before transaction commit.

The IDE should expose separate linked graphs for:

```text
ECS schedule | reactive dependency graph | UI composition tree
             | semantic/accessibility tree | render extraction graph
```

These graphs share symbol identity but must not be flattened into one graph
that hides the ownership and phase boundaries.

## 23. Determinism, replay, and testing

Deterministic mode fixes:

- system order and schedule version;
- fixed timestep and frame sequence;
- random seeds and provider responses;
- command-buffer and event merge order;
- reactive publication order;
- navigation and composition key decisions;
- asset/resource generations.

Replay records inputs, external outcomes, system schedule identity, revisions,
commands, events, and checkpoint state hashes. A divergence report names the
first differing phase, system, entity/component, owner, or UI key.

Required tests include:

- `@compose` initial creation and recomposition;
- stable keyed reordering and state preservation;
- key replacement and owner disposal;
- `@with`/`@without` query filtering;
- query access conflict and borrow diagnostics;
- structural command commit and rollback;
- conditional effect rising-edge behavior;
- event queue ordering and bounded retention;
- ECS revision publication and UI skipping;
- layout invalidation and cycle detection;
- input routing, focus transfer, and accessibility projection;
- navigation retention/destruction;
- render extraction without a GPU;
- late async completion after owner disposal;
- deterministic replay and provider failure.

Headless UI tests must inspect the semantic tree and committed component state
without opening a window. Pixel tests are provider tests, not the only UI test
layer.

## 24. Security and authority

The UI must not treat presentation state as authorization. A disabled button is
only a visual state; the action handler and the receiving system validate the
capability again.

The engine composes with `std.security`:

- composition receives only the world/resource capabilities it declares;
- UI handlers cannot obtain filesystem, network, process, or device authority
  merely because they are handlers;
- remote or untrusted UI descriptions cannot inject arbitrary components or
  render commands;
- debug inspectors require an explicit capability and audit policy;
- assets and serialized snapshots are version- and integrity-checked;
- accessibility, telemetry, and replay output can redact classified data;
- `azora::engine::exit()` is an explicit application capability, not a generic
  effect available to every widget.

## 25. Implementation roadmap

### Phase A: stabilize the current substrate

- document `react func`, `remember`, `retain`, and `preserve` as the reactive
  syntax used by the engine;
- preserve `World.revision`, `Storage<T>.revision`, `Signal<T>`, and
  `EcsObserver` as the initial revision ABI;
- add explicit `Child<T>` relationship metadata and validation;
- expose query access and system metadata to tooling.

### Phase B: formalize query and schedule lowering

- finalize `@query [A!, B&] @with P @without Q` as the only query grammar;
- add typed row destructuring;
- reject conflicting access and borrow escape;
- resolve system phase/order constraints symbolically;
- make event/resource access contribute scheduler metadata.

### Phase C: implement `@compose`

- define `ComposeContext`, owner/path identity, and command-buffer expansion;
- add `UiKey`, `Child<T>`, and core UI components;
- implement initial composition, keyed reconciliation, and disposal;
- make composition failure atomic.

### Phase D: reactive publication and conditional effects

- connect committed storage revisions to UI owners;
- add conditional effect edge triggers;
- prevent reentrant world mutation during publication;
- implement owner generation checks for async handlers;
- add snapshot/projection APIs for aggregate UI state.

### Phase E: layout, input, and semantics

- implement constraints, measure/arrange, and invalidation categories;
- route pointer/keyboard/controller input through the retained tree;
- implement focus and semantic/accessibility projections;
- integrate `NavBackStack` with composition roots.

### Phase F: render/provider convergence

- lower the current immediate-mode `App` helpers into render commands;
- share immutable extraction with DOM and GPU providers;
- implement asset generation/device-loss handling;
- add headless render and semantic-tree tests.

### Phase G: determinism and optimization

- add fixed-step replay and phase traces;
- optimize query storage, change ticks, composition skipping, and layout;
- add parallel extraction where provider/thread ownership permits;
- publish conformance requirements for external engine packages.

## 26. Acceptance criteria

The proposal is ready for implementation when all of the following are true:

1. `@compose world {}` creates a keyed UI tree without direct user calls to
   `world.spawn()` for ordinary widgets.
2. Recomposition updates matching entities and disposes removed keyed owners.
3. `@query [A!, B&] @with P @without Q` resolves component symbols and rejects
   incompatible access.
4. A `Child<T>` relationship cannot create a cycle or stale parent.
5. ECS writes become UI-visible only after a documented commit/publication
   boundary.
6. Conditional effects run on false-to-true transitions and clean up with the
   owner.
7. Query borrows cannot cross `await`, structural commit, or owner disposal.
8. The same view can target a headless collector and at least one renderer
   provider.
9. Focus, input handling, and accessibility identity survive keyed reorder.
10. A disposed screen cannot be mutated by a late async completion.
11. A replay can identify the first ECS/reactive/UI divergence.
12. The IDE can navigate from a UI component use to its declaration and from a
    system/query use to its access and schedule metadata.

## 27. Open decisions

1. Whether the UI builder returns a retained node value, writes through a
   builder, or supports both forms with one normalized intermediate tree.
2. Whether `@compose` emits UI ECS entities by default or uses a retained UI
   store with an ECS adapter for selected nodes.
3. Whether the first layout engine belongs in `azora-ui` or a separate
   `azora-layout` package.
4. Whether `@query` uses a cursor API, destructured iterator, or both.
5. How aggregate projections select row-level versus storage-level revisions.
6. The exact typed action contract for button handlers and navigation.
7. How UI state migrates when hot reload changes a keyed view's type or fields.
8. Which render commands are shared by DOM, Metal, WebGL, and headless tests.
9. Whether parallel system batches are enabled in the first native runtime.
10. The serialization format for reactive snapshots and replay checkpoints.

## 28. Principles

1. Reactive state, ECS state, UI state, and render state are connected but not
   conflated.
2. `@compose` is explicit, keyed, staged, and owner-scoped.
3. Component and relationship identity is symbolic, never name-similar.
4. Query borrows are short-lived and compiler-checked.
5. Revisions are cheap invalidation tokens, not a reason to clone the world.
6. Effects observe committed state and schedule future mutation.
7. UI identity is a stable key, not a list index or memory address.
8. Accessibility and authorization are independent of visual appearance.
9. Providers render owned immutable output and report failure explicitly.
10. The compiler boundary is generic; engine meaning comes from package
    metadata, macros, specs, and reflection.
