# Azora Engine — Unified Application & Game Architecture

> **Thesis.** One world. One reactive substrate. One schedule. One frame graph.
>
> Azora Engine unifies the two proven models of interactive software — **Bevy**
> (ECS-first, data-oriented, plugin-composed gameplay) and **Jetpack Compose**
> (declarative, state-hoisted, recomposing UI) — into a *single* runtime where
> **gameplay, UI, and rendering are the same kind of thing**: pure functions of
> observable state, scheduled as systems, producing immutable command trees that
> backends draw.
>
> The two models already agree on the hard part — *derive the view from state and
> recompute only what changed*. Bevy calls it **change detection**; Compose calls
> it **recomposition**. Azora makes them the **same mechanism**: a monotonic
> **revision** on every observable, and reactive owners / systems that re-run only
> when a revision they read advances. A gameplay system skipping because no
> component changed and a UI subtree skipping because no state it read changed are
> one idea with one implementation.

This is the north-star design. It is written entirely in Azora constructs that
already exist in the language (`@Reactive`, `mem`/`rem`/`ret`, `effect`,
`res`/`query`/`with`/`without`, `solo`/`wrap`/`inject`, `attempt`/`guard`,
`@Component`/`@System`/`@Resource`/`@Event`, `zone alloc`) and the engine
(`World`, `Storage<T>`, `ResourceCell<T>`, `EventQueue<T>`, `Signal<T>`,
`EcsObserver`, `ReactiveResource<T>`, `NavBackStack<K>`, `DomNode`, `Schedule`).
Where a construct is a **proposed addition**, it is marked **(proposed)**.

---

## 0. Canonical syntax (already decided)

These snippets are the ground truth for the surface language. The unified design
below is expressed *in this exact style*.

Game example:

```
@Component
pack Player {
    var speed = 8.0
}

@Component
pack Enemy

@Component
pack Health {
    var level = 5
}

@Component
enum Ability {
    Walk
    Swim
    Fly
    Climb
}

@System(.Update)
func move(
    keyboard: res ButtonInput<KeyCode> // res to be a macro type. write "res T" instead of "Res<T>" and "mut res T" instead of "MutRes<T>"
    time: res Time
    player!: Single<Transform!> with Player // maybe using "with" and "without" infx, azora style
) {
    var direction = Vector3::Zero
    
    if keyboard.pressed(KeyCode.W) {
        direction.y += 1.0
    }
    
    if keyboard.pressed(KeyCode::S) {
        direction.y -= 1.0
    }
    
    player.translation += direction.normalized * 300.0 * time.deltaSecs
}

@System(.Update)
func move_players(
    time: res Time
    q!: query [Transform!, Player&] // query is a macro instead of "Query<...T>"
) {
    for [transform!, player&] in q { // we already have destructoring syntax, use [] instead of () for this
        transform.translation.x += player.speed * time.deltaSecs
    }
}

```

Future syntax for return fails
```
! instead of mut ref

& instead of ref
func foo(): Int ?! [Error1, Error2]
func foo(): Int& ?! [Error1, Error2]
func foo(): Int! ?! [Error1, Error2]
```

---

## 1. The language substrate this design rests on

Every capability below is an existing Azora construct. The engine composes them;
it does not invent parallel mechanisms.

| Concern | Azora construct | Where |
|--------|-----------------|-------|
| Reactive owner | `@Reactive func` / `task` / `infx` | `std.reactive` |
| Reactive state | `mem` (recomputed with owner) · `rem` (save/restore) · `ret` (owner-lifetime) | `std.reactive` |
| Effects | `effect { }` · `effect x { }` · `effect [a, b] { }` · `effect defer { }` | `std.reactive` |
| Change tokens | `Signal<T>` · `*.revision` · `EcsObserver` · `ReactiveResource<T>` | `engine.core`, `engine.ui.reactive` |
| ECS data | `@Component pack/enum` · `Storage<T>` · `Entity` · `World` | `engine.ecs` |
| Resources | `@Resource` · `ResourceCell<T>` · `res T` / `mut res T` | `engine.core`, `engine.ecs` |
| Selection | `query [A!, B&] with P without Q` · `Single<T!>` · `QueryCursor` · `QueryAccess` | `engine.ecs` |
| Systems | `@System(.Phase, order)` · `Schedule` · `SystemPhase` | `engine.core`, `engine.ecs` |
| Events | `@Event` · `Event<T>` · `EventQueue<T>` | `engine.ecs` (+ proposed sugar) |
| Services / plugins | `solo` · `wrap` · `inject` · `DefaultEnginePlugins` | `engine.app` |
| Failure | `fail ErrSet` · `: T ?! [E]` · `guard` · `x?` · `try`/`catch` | language |
| Transactions | `attempt { } else { }` · `decides` · `transacts` | language (roadmap C/D) |
| Concurrency / timelines | `task` · `await` · `launch` · `spawn` · `race` · `sync` · `sleep` · `1.frames` | `std.concurrency`, `engine.jobs` |
| Effect lattice | `effects computes varies reads writes allocates decides transacts suspends` | language (roadmap C) |
| Memory | `alloc` · `drop` · `isolated` · `zone alloc` (escape-safe arena) · pointers | language |
| Lambdas / receivers | `Func[Recv](Args) -> Ret` · `Task<…>` · `with recv { }` | `std.functional` |
| Zones / paths | `zone x { }` · `use x` · `with y::z { }` · `friend zone` · `::` | language |

**Reference: the reactive owner (already in `std.reactive`).**

```
@Reactive
func counter(): Int {
    rem value = 1          // survives host save/restore
    ret hits  = 0          // lives for the owner's whole lifetime
    mem doubled = value * 2 // recomputed when the owner recomputes

    var observed = 0
    effect [value] {        // re-runs when `value` changes
        observed = value
        hits = hits + 1
    }

    effect defer {          // cleanup when the owner is disposed
        // release resources
    }

    value = 7
    return observed
}
```

`@Reactive` + `mem`/`rem`/`ret` + `effect` **is** Compose (owner = composable,
`mem` = `remember`, `rem` = `rememberSaveable`, `ret` = retained state,
`effect` = `LaunchedEffect`/`SideEffect`, `effect defer` = `DisposableEffect`
`onDispose`) — but it is a *language* feature, rendering-agnostic, usable by a
server, a data pipeline, or a game just as well as a UI.

---

## 2. The reactive keystone: revisions

One primitive underlies change detection *and* recomposition: the **revision**, a
monotonically increasing `Long` on every observable.

Present today:

- `engine.core` — `Signal<T>` (`signalVersion`, `signalChangedSince`), `Time`,
  the `@Component`/`@System`/`@Resource`/`@Query` decorators, `SystemPhase`.
- `engine.ecs` — `World.revision`, `Storage<T>.revision`, per-entity
  `storageWasAdded`/`storageWasChanged`, and `QueryAccess` (typed read/write/
  with/without sets that the scheduler uses for conflict-free parallelism).
- `engine.ui.reactive` — `EcsObserver` (observes world/storage/navigation
  revisions, fires once per distinct revision) and `ReactiveResource<T>` (wraps a
  `Signal<T>`; `consumeChange()` publishes each write exactly once).
- `engine.ui.navigation` — `NavBackStack<K>` exposing `prop version = revision`.

**(proposed) The `Observable` spec** unifies these so a reactive owner or system
can track heterogeneous dependencies uniformly:

```
/// Anything whose change advances a revision.
spec Observable {
    prop revision: Long
}
// Signal<T>, World, Storage<T>, ResourceCell<T>, NavBackStack<K>,
// ReactiveResource<T> all satisfy Observable.
```

**The unification, stated precisely.** A `@Reactive` owner records the revisions
it read (via `mem`/`rem`/`ret`/`effect` dependency tracking). A `@System` records
its `QueryAccess`. Both re-run under the same predicate: *some revision I read
last pass has since advanced.* Bevy's "run this system because a component
changed" and Compose's "recompose because state changed" become one check over
one kind of token.

`ReactiveResource<T>.consumeChange()` and `EcsObserver.observeStorage(...)` are
already exactly this predicate for resources and component storages.

---

## 3. The state ladder — one hoisting story

The rule that makes UI and gameplay the same kind of code: **UI owns no private
mutable state.** UI-local state uses the language's reactive declarations, which
are host-inspectable and serializable; shared state lives in the ECS World. There
is one ladder, from most local to most global:

| Scope | Azora spelling | Bevy | Compose |
|------|----------------|------|---------|
| Owner-local, recomputed | `mem x = …` | — | `remember { … }` |
| Owner-local, savable | `rem x = …` | — | `rememberSaveable` |
| Owner-lifetime | `ret x = …` | — | retained state |
| Per entity | `@Component` + `Storage<T>` | component | (hoisted model) |
| App-global | `@Resource` + `ResourceCell<T>`, read via `res T` | `Res`/`ResMut` | `CompositionLocal` / ViewModel |
| Derived | `mem d = f(a, b)` or `prop` | — | `derivedStateOf` |

Because `mem`/`rem`/`ret` carry serializable `ReactiveSnapshot<T>` metadata
(`std.reactive`), UI-local state is inspectable, persistable, and hot-reloadable
exactly like ECS data — there is no opaque widget state anywhere in the system.

---

## 4. UI is a reactive function that returns a View

A UI builder is an ordinary `@Reactive func` whose result is an immutable `View`
tree. It reads state through the same accessors as a system (`res`, `query`,
`mem`, …) and recomposes under the §2 predicate.

```
/// (proposed) Immutable UI node — the cross-backend generalization of
/// engine.ui.dom.DomNode. The Web backend lowers View → DomNode; the GPU backend
/// lowers View → draw commands; the TUI backend lowers View → cells.
@Experimental(sinceAzora: "0.0.5")
pack View {
    fin kind: ViewKind            // Text | Box | Row | Column | Image | Canvas | Host
    fin modifier: Modifier
    fin attrs: Array<ViewAttr>
    fin events: Array<DomEvent>   // retained first-class handlers (engine.ui.dom.DomEvent)
    fin children: Array<View>
    fin key: String               // sibling identity for reconciliation
}
```

A reactive HUD, driven purely by resource + ECS state:

```
@Reactive
func Hud(
    score:  res ReactiveResource<Int>      // hoisted game state (Signal-backed)
    player&: Single<Health&> with Player   // read straight from ECS
): View {
    return Column(Modifier.pad(12).gap(6)) [
        Text("Score {score.value}").font(28).color(Palette.Ink),
        HealthBar(current: player.level, max: 5),
    ]
}
```

**Recomposition contract** (Compose skipping ⨝ Bevy change detection):

- `Hud` re-runs **only** when `score`'s `Signal` revision advances **or** the
  `Health` storage row it read is `storageWasChanged`. Both are recorded reads.
- `HealthBar(current:, max:)` is *skippable*: called with stable value inputs, an
  unchanged `(current, max)` reuses last frame's `View` node verbatim.
- The result is an immutable `View`; the **Recomposer (proposed, `.Compose`
  phase)** diffs it against the retained tree and emits a minimal patch for the
  active backend. The keyed browser reconciler in `engine.ui.dom` is the first
  such backend and defines the diff semantics.

### 4.1 Modifiers are bundles for the view world

Compose's `Modifier` chain and Bevy's component **bundles** are the same idea:
ordered, composable data attached to a node. Azora spells the UI side `Modifier`
and the entity side a component bundle.

```
pack Modifier { fin ops: Array<ModifierOp> }   // pad, size, gap, color, onClick, weight, focus, testTag …

impl Modifier {
    func pad(all: Real): Modifier
    func size(w: Real, h: Real): Modifier
    func onClick(handler: Func() -> Unit): Modifier   // lowers to a View.events DomEvent
    func weight(w: Real): Modifier
    // immutable, chainable, order-significant — exactly like Compose.
}
```

Today's immediate-mode API on `App` (`uiText`, `button`, `uiRect`, `uiTitle`,
`hovered`) becomes **one lowering** of `View` for the GPU backend; nothing about a
game that uses it changes, but it gains skipping and cross-backend portability.

---

## 5. Effects & lifecycle (the real `effect` family)

Side effects never run *during* composition; they are declared with the
language's `effect` forms and executed against the owner's lifecycle. There is no
`launchedEffect`/`disposableEffect` — those are the Compose names; Azora already
has the primitives:

```
@Reactive
func PlayerCard(id: Entity): View {
    rem hovered = false

    // Re-runs whenever `id` changes; the prior run is cancelled first.
    effect id {
        prefetchAvatar(id)
    }

    // Automatic dependency capture: re-runs when any reactive value it reads moves.
    effect {
        analytics.mark("card-visible")
    }

    // Cleanup bound to the owner leaving composition (see NavLifecycle).
    effect defer {
        releaseAvatar(id)
    }

    return Card(Modifier.onClick({ hovered = !hovered })) [ /* … */ ]
}
```

- **Long-running / suspending work** uses the concurrency layer: an `effect` body
  may `launch`/`spawn` a `task` (`engine.jobs`, `std.concurrency`) whose lifetime
  is bound to the effect; `effect defer` (or leaving the `NavBackStack`) cancels
  it deterministically through structured concurrency scopes. Timelines compose:
  `race { … } else { … }`, `sync`, `sleep(1.frames)`, `sleep(0.5.seconds)`.
- **Per-composition / per-frame scratch memory** uses `zone alloc { }`. The arena
  is **escape-safe**: values stored into longer-lived state (a component, a
  resource, the retained `View` tree) are detached from the arena and survive;
  only true frame-locals are reclaimed at scope exit. Composition can therefore
  allocate layout/diff temporaries freely without churning the general allocator
  or leaking.

---

## 6. Navigation & app state — one back stack for screens *and* scenes

`engine.ui.navigation` already provides a Compose-Navigation-style typed back
stack: `NavBackStack<K>` (`push`, `pop`, `replace`, `popToRoot`, `at`, `prop
current`, `prop version = revision`, `prop lastDirection`), `NavEntryProvider`
(`NavContent<K> = Func(ref K) -> Unit`), `NavDisplay` (`sync`/`suspend`/
`destroy`), and `NavLifecycle`/`NavDirection`.

Azora elevates this single stack to route **both** UI screens **and** ECS
scenes/game-states:

```
enum Route { Menu, Playing, Paused, GameOver }

@Reactive
func App(nav: mut res NavBackStack<Route>): View {
    return NavHost(nav) { route ->                 // NavContent<Route>
        when route {
            .Menu     -> MenuScreen(onPlay: { nav.replace(.Playing) })
            .Playing  -> GameScreen()               // hosts the ECS viewport + HUD
            .Paused   -> PauseOverlay(onResume: { nav.pop() })
            .GameOver -> GameOverScreen(onRetry: { nav.replace(.Playing) })
        }
    }
}
```

- A route may **own a Scene** — a sub-World / archetype subset whose systems are
  active only while the route is on top. The game-state machine (the
  sidescroller's `GameRoute`) and the UI router are then the **same stack**, so
  pause/resume, transitions, and back handling are unified.
- `NavBackStack.version` is an `Observable`, so a navigation change invalidates
  exactly the `NavHost` owner (via `EcsObserver.observeRevision`) — not the world,
  not the rest of the UI.

---

## 7. Events & messaging

Bevy events and Verse-style awaitable signals unify on `engine.ecs`'s
`EventQueue<T>` (`eventSend`, `eventNext`, `eventHasNext`, `eventPeek`) plus the
roadmap `@Event` / `Event<T>` sugar.

```
@Event pack PlayerScored { var by: Entity, var points: Int }

@System(.Update)
func award(
    mut scored: mut res EventQueue<PlayerScored>
    mut score:  mut res Score
) {
    while scored.hasNext() {
        fin ev = scored.next()
        score.value += ev.points
    }
}

// Gameplay may also await an event on a timeline (roadmap F):
//   fin ev = await world.playerScored
```

Because `EventQueue<T>` carries a revision, a `@Reactive` UI can observe "an event
occurred this frame" as just another dependency — e.g. flashing a score popup —
without polling or callbacks.

---

## 8. Gameplay: systems, effect lattice, transactions, timelines

Gameplay is Bevy-shaped ECS systems, extended with Azora's failure/effect model.

**Systems** declare access with `res`/`query`/`with`/`without`; parameter lowering
builds `QueryAccess`, so the scheduler knows read/write conflicts *before*
codegen (no runtime discovery):

```
@System(.FixedUpdate)
func integrate(time: res Time, q!: query [Transform!, Player&]) {
    for [transform!, player&] in q {
        transform.translation.x += player.speed * time.fixedDeltaSecs
    }
}
```

**Effect lattice (roadmap C).** Systems and functions may annotate an `effects`
clause so the compiler can verify purity, schedule safely, and journal:

```
@System(.Update)
func capture(
    points!: query [CapturePoint!] without Disabled
    time: res Time
) effects reads writes decides transacts {
    for point! in points! {
        attempt {                          // opens a rollback transaction
            guard anyAttackerOn(point)     // silent fail → discard this attempt
            point.progress += time.deltaSecs / 5.0
            guard point.progress >= 1.0
            world.pointCaptured.emit(PointCaptured(point))
        } else {
            point.progress = 0.0           // journaled writes roll back here
        }
    }
}
```

The lattice — `computes`, `varies`, `reads`, `writes`, `allocates`, `decides`,
`transacts`, `suspends`, `no_rollback` — lets the engine prove which systems may
run in parallel (disjoint `writes`), which may fail (`decides`), and which are
rollback-safe (`transacts` vs `no_rollback`).

**Timelines (roadmap E).** Long-lived agent behavior reads as rules over time,
cancelled structurally:

```
task patrol(agent: Entity) effects suspends writes {
    loop {
        moveTo(agent, nextPoint())
        sleep(0.5.seconds)
    }
}
```

Failure (`fail ErrSet` / `: T ?! [E]`) stays separate from silent transactional
failure (`decides` + `attempt`), so typed errors and gameplay "this rule didn't
apply" are never conflated.

---

## 9. Scheduling: one frame graph for sim, UI, and rendering

All work — gameplay, composition, layout, extract, render — is a `@System` on the
single `Schedule`, ordered by `SystemPhase` and parallelized by `QueryAccess`
disjointness (`Schedule.canRunParallel` already answers this via
`queryAccessConflicts`).

**Today** (`engine.core.SystemPhase`, `engine.app.Engine.run`): `Startup`,
`PreUpdate`, `Update`, `PostUpdate`, `FixedUpdate`, `Render`, `Last`.

**Proposed extension** inserts the UI/render pipeline as ordinary phases:

```
enum SystemPhase {              // engine.core — Compose/Layout/Extract added
    Startup                     // once
    PreUpdate                   // ingest platform input → resources
    FixedUpdate                 // deterministic simulation (accumulator-driven)
    Update                      // variable-step gameplay
    PostUpdate                  // transform propagation, spatial, animation
    Compose                     // (proposed) recompose invalid @Reactive owners → View tree
    Layout                      // (proposed) measure/arrange changed subtrees
    Extract                     // (proposed) World snapshot → RenderQueue; View → draw cmds
    Render                      // backends replay immutable command lists
    Last                        // frame++, arena reclaim, deferred despawns
}
```

The unified frame (extending the real `Engine.run` loop):

```
Startup*                (once)
loop while app.frame():
    advance Time · world.progress · inject EngineClock/Registry
    PreUpdate           platform → Time, ButtonInput<KeyCode>, Pointer, resize
    Update              gameplay systems mutate World
    PostUpdate          transforms, animation, spatial index
    FixedUpdate × N     world.consumeFixedStep(): deterministic sim substeps
    ── barrier: structural changes applied, revisions advanced ──
    Compose             recompose only invalid @Reactive owners        (proposed)
    Layout              solve layout for changed subtrees              (proposed)
    Extract             read-only: World → RenderQueue, View → cmds     (proposed)
    Render              Metal 3D pass → GPU-UI pass
    present
    Last                bump frame, free per-frame zone arenas
```

Guarantees:

- **Deterministic order** among conflicting systems via `QueryAccess` overlap;
  disjoint systems run concurrently on `engine.jobs`.
- **Extract is read-only** — 3D extraction, UI draw-command generation, and audio
  mixing parallelize safely against each other (Bevy's render-extract discipline,
  generalized to include UI).
- **Compose/Extract skip by revision** — unchanged owners and archetypes cost
  ~O(0); a static HUD over a busy world does no UI work.

---

## 10. Rendering: two backends, one extract discipline

3D and UI rendering share the extract → command-list → backend shape.

- **3D:** `Extract` walks `query [Transform&, Material&, Mesh&]` into a
  `RenderQueue` (`engine.render`) sorted by pipeline/material; the Metal backend
  replays it. `Camera`, lights, and materials are ECS data.
- **UI:** `Compose`+`Layout` produce a laid-out `View`; `Extract` lowers it per
  backend:
  - **GPU-UI** — immediate/retained Metal quads + text atlas (`engine.gpu`;
    today's `App.uiText`/`button`/`uiRect` become this lowering).
  - **Web** — `View → DomNode` VDOM through the existing keyed reconciler in
    `engine.ui.dom` (retained first-class event handlers).
  - **TUI / headless** — `View → cells` / no-op, for tests and tools.

Because both paths flow through `Extract`, one frame can draw a 3D scene *and* a
reactive UI overlay under one scheduling model and one snapshot.

> **Tracked backend cleanup (independent of the reactive model).** The current GPU
> text path (`engine.gpu` `uiTextColored`) allocates a fresh Metal texture per
> HUD glyph-run every frame. The unified `Extract` must **cache/pool glyph-run
> textures keyed by `(text, size)`** so the UI backend does not leak per frame.

---

## 11. Plugins & DI: composition of capabilities

Bevy plugins ⨝ Compose providers ⨝ Azora `solo`/`wrap`/`inject` (already in
`engine.app`). A plugin bundles resources, systems, and backend services;
`DefaultEnginePlugins` wires the standard set at compile time.

```
wrap DefaultEnginePlugins {           // engine.app (existing)
    solo EngineRegistry
    solo EngineClock
    solo WindowPlugin
    solo InputPlugin
    solo RenderPlugin
    solo UiPlugin                      // hosts the Recomposer + Layout + selected backend
}

func main() {
    engine("Azora", 1280, 720)
        .addPlugins(defaultPlugins())
        .addUpdateSystem(movePlayers)         // existing builder API
        .setContent { App() }                 // (proposed) root @Reactive owner
        .run()
}
```

- **(proposed) `UiPlugin`** installs the **Recomposer** (a `.Compose`-phase system
  that walks invalid `@Reactive` owners), the **Layout** solver, and the selected
  UI backend — all as ordinary systems/services. Choosing GPU ↔ Web ↔ TUI is
  choosing a different `solo`; nothing else changes.
- **(proposed) `setContent { … }`** registers the root `@Reactive` owner, exactly
  as `addUpdateSystem`/`addStartupSystem` register systems today.
- Third-party plugins contribute phases-worth of systems and their own resources
  identically to first-party ones; the app author composes them in one `wrap`.

---

## 12. End-to-end worked example

Deterministic ECS gameplay, a reactive HUD, an event-driven popup, and unified
navigation — one framework, in the §0 syntax and real language constructs.

```
@Component pack Player { var speed = 8.0 }
@Component pack Health { var level = 5 }
@Resource  pack Score  { var value = 0 }
@Event     pack Scored { var points: Int }

// ── Gameplay: ECS systems with declared access + effect lattice ──────
@System(.FixedUpdate)
@Effects(.Reads, .Writes, .Decides)
func integrate(time: res Time, q!: query [Transform!, Player&]) {
    for [transform!, player&] in q {
        transform.translation.x += player.speed * time.fixedDeltaSecs
    }
}

@System(.Update)
@Effects(.Reads, .Writes, .Decides)
func collectCoins(
    score!: res! Score
    scored!: event! Scored
    coins!: query [Transform&, Coin&] without Collected
) {
    for [t&, _] in coins! {
        attempt {
            guard overlapsPlayer(t)
            score.value += 10
            scored.send(Scored(10))
        }
    }
}

// ── UI: reactive owners; state hoisted into ECS / resources ──────────
@Reactive
func GameScreen(score: res Score, player&: Single<Health&> with Player): View {
    return Box(Modifier.fill()) {
        Viewport()                                 // hosts the 3D extract/render
        Hud(score: score.value, health: player.level)
        ScorePopup()
    }
}

@Reactive
func Hud(score: Int, health: Int): View {           // stable inputs ⇒ skippable
    return Column(Modifier.pad(12).gap(6)) {
        Text("Score {score}").font(28),
        HealthBar(current: health, max: 5),
    }
}

@Reactive
func ScorePopup(scored: res EventQueue<Scored>): View {
    rem visibleFor = 0.0
    effect scored.revision {                        // fires the frame a Scored event lands
        visibleFor = 1.2
    }
    return if visibleFor > 0.0 { Toast("+10") } else { Empty() }
}

// ── Navigation: screens and game-state share one back stack ──────────
@Reactive
func App(nav: mut res NavBackStack<Route>): View {
    return NavHost(nav) { route ->
        when route {
            .Menu     -> MenuScreen(onPlay: { nav.replace(.Playing) })
            .Playing  -> GameScreen()
            .Paused   -> PauseOverlay(onResume: { nav.pop() })
            .GameOver -> GameOverScreen(onRetry: { nav.replace(.Playing) })
        }
    }
}

func main() {
    engine("Azora Sidescroller", 1280, 720)
        .addPlugins(defaultPlugins())
        .addUpdateSystem(collect_coins)
        .setContent { App() }
        .run()
}
```

What the runtime does each frame, precisely:

1. `PreUpdate` fills `Time`, `ButtonInput<KeyCode>`, pointer.
2. `Update` runs `collect_coins` (bumps `Score`, sends `Scored`); `FixedUpdate`
   runs `integrate` deterministically.
3. `Compose` finds `Hud` invalid (read `Score`/`Health`) and `ScorePopup` invalid
   (read the `Scored` queue revision); it recomposes **only** those owners.
   `MenuScreen`/`PauseOverlay` are not mounted; `Box`/`Viewport` are reused.
4. `Layout` re-solves only the changed subtrees.
5. `Extract` snapshots the World → 3D `RenderQueue` and lowers the `View` tree →
   UI draw commands, in parallel (both read-only).
6. `Render` draws 3D then the UI overlay; `Last` frees the frame's `zone alloc`
   arenas.

---

## 13. Bevy ⨝ Compose ⨝ Azora mapping (reference)

| Concern | Bevy | Jetpack Compose | **Azora (real spelling)** |
|--------|------|-----------------|---------------------------|
| Source of truth | ECS World | hoisted state / ViewModel | `World` + `ResourceCell<T>` (`engine.ecs`) |
| Reactivity | change detection | recomposition | revisions + `@Reactive` (`Signal`, `*.revision`, `EcsObserver`) |
| Global state | `Res`/`ResMut` | `CompositionLocal` | `res T` / `mut res T` over `@Resource` |
| Per-entity state | Component | (hoisted model) | `@Component` + `Storage<T>` |
| Local UI state | — | `remember` / `rememberSaveable` | `mem` / `rem` / `ret` (`std.reactive`) |
| Derived state | — | `derivedStateOf` | `mem d = f(…)` / `prop` |
| Selection | Query | (model reads) | `query [A!, B&] with/without`, `Single<T!>` |
| Behavior unit | System | Composable / effect | `@System` / `@Reactive` (+ `effect`) |
| Node styling | Bundle | Modifier | `Modifier` (views) / component bundle (entities) |
| Effects | tasks/commands | `LaunchedEffect`/`DisposableEffect` | `effect` / `effect [d]` / `effect defer` |
| Concurrency | tasks | coroutines | `task` · `launch` · `spawn` · `race` · `sleep` |
| Events | `Events<T>` | (callbacks) | `@Event` · `EventQueue<T>` |
| Navigation | states/`NextState` | Navigation back stack | `NavBackStack<K>` (screens *and* scenes) |
| Failure | — | — | `: T ?! [E]` · `guard` · `attempt`/`decides` |
| Composition | plugins | DI / providers | `solo` / `wrap` / `inject` (`engine.app`) |
| Scheduling | schedules/sets | recomposer/frame clock | one `Schedule` + `SystemPhase` + `QueryAccess` |
| Output | render extract | slot-table diff | `Extract` → `RenderQueue` / `View` → `DomNode` |
| Scratch memory | — | slot table | `zone alloc` (escape-safe arena) |

---

## 14. Roadmap (how we get here from today's packages)

The primitives largely exist; the work is elevating and connecting them.

1. **Reactive substrate.** Formalize `Observable`; make `res`/`query`/`mem`/`rem`/
   `ret`/`effect` reads record revisions into the running owner/system. Reuse
   `Signal`, `EcsObserver`, `ReactiveResource`, `*.revision`. *(engine.core,
   engine.ecs, engine.ui.reactive, std.reactive)*
2. **Reactive UI runtime.** `View` node (generalize `engine.ui.dom.DomNode`), the
   **Recomposer** as a `.Compose`-phase system driven by `@Reactive` owners,
   `Modifier`. *(engine.ui)*
3. **Layout + backends.** Constraint layout over `View`; lower `View` → GPU-UI
   commands, → `DomNode` VDOM (exists), → TUI; pool glyph-run textures.
   *(engine.ui, engine.gpu, engine.render)*
4. **Unified schedule.** Add `Compose`/`Layout`/`Extract` phases; drive parallel
   read-only extract off `QueryAccess`. *(engine.core, engine.app, engine.jobs)*
5. **Unified navigation.** Bind `NavBackStack` to scene activation so game-state
   and screen routing are one stack. *(engine.ui.navigation, engine.ecs)*
6. **Events & timelines.** `@Event`/`Event<T>` sugar over `EventQueue<T>`;
   awaitable events; `effect`-scoped tasks (`race`/`sync`/`sleep`). *(engine.ecs,
   engine.jobs, std.concurrency)*
7. **Effect lattice & transactions.** `effects` clauses, `attempt`/`decides`/
   `transacts` journaling, parallel scheduling from disjoint `writes`. *(language
   roadmap C–E, engine scheduler)*

**The invariant to preserve at every step:** *UI is a pure, skippable function of
World state; the World is the only thing that mutates; one schedule runs it all.*
```
