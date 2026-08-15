# Azora Navigation Proposal

Status: Full design proposal

Primary package: `engine.ui.navigation`

Related packages: `engine.ui`, `engine.ui.compose`, `engine.ui.reactive`,
`engine.input`, `engine.platform`, `engine.profiler`, `std.serializer`

## 1. Thesis

Azora navigation is application-owned typed state rendered by a reactive
`NavDisplay`.

The engine does not own a hidden controller, a global route registry, or a
string graph. Applications own one or more `NavBackStack<K>` values and mutate
them directly. The navigation package supplies the semantics around those
values:

- stable identity for each occurrence of a route on a stack;
- conversion from route keys to retained navigation entries;
- entry-scoped reactive state, tasks, focus, and disposal;
- scene selection for one-pane, multi-pane, nested, and overlay layouts;
- dialogs, sheets, menus, and other modal or non-modal overlays;
- forward, pop, replace, shared-element, and predictive-back transitions;
- hierarchical back dispatch across overlays and nested displays;
- explicit preservation, restoration, deep-link construction, and results;
- deterministic headless testing and profiler/IDE visibility.

The central data flow is:

```text
navigation event
  -> application mutates typed stack transactionally
  -> stack revision changes once
  -> keys resolve to stable NavEntry instances
  -> decorators establish entry owners and retained state
  -> ordered scene strategies select visible entries
  -> scene decorators add shared chrome
  -> NavDisplay composes and transitions the scene set
  -> layout/input/render providers consume committed UI output
```

This follows the most useful principles of Jetpack Compose Navigation 3:
application ownership of the back stack, keys rather than content in that
stack, key-to-entry resolution, retained state scoped to entries, and scenes
that may display more than one entry. Azora adapts those principles to its own
ownership model, `react func`, `remember`/`retain`/`preserve`, ECS UI, native
and WebAssembly targets, and deterministic engine runtime.

## 2. Goals

The design must support all of the following without changing its core model:

1. A game menu moving between title, settings, play, pause, and game-over
   screens.
2. A desktop tool with tabs, split panes, inspectors, nested editors, dialogs,
   popovers, and several independent histories.
3. A media player with a full-screen movie, controls overlay, subtitle/audio
   dialogs, and picture-in-picture or supporting panes.
4. A phone interface that shows one entry at a time and a wide interface that
   shows list and detail entries together.
5. Keyboard, mouse, touch, controller, accessibility, browser-history, and
   platform back integration.
6. Repeated instances of the same parameterized route with independent state.
7. Explicit snapshots and restoration without serializing UI trees, native
   handles, tasks, or borrowed values.
8. Headless tests that verify stack, scene, lifecycle, focus, and transition
   behavior without opening a window.

## 3. Non-goals

Navigation does not:

- own application business state;
- make a route key an authority or authentication decision;
- require every application to define a static graph;
- infer routes from similar names or string conventions;
- place decoder, GPU, file, socket, or ECS borrows in snapshots;
- require every screen to be an ECS entity;
- require nested navigation where a plain state value is sufficient;
- force dialogs and sheets into the same native-window implementation;
- make every transient tooltip or context menu a back-stack entry;
- keep a popped entry alive merely because an exit animation is running.

## 4. Relationship to Navigation 3

Navigation 3 establishes several important conventions that Azora adopts:

- the application owns the back stack;
- the stack contains serializable keys, not rendered content;
- an entry provider resolves keys to `NavEntry` content and metadata;
- `NavDisplay` observes entries and renders scenes;
- ordered scene strategies select single-pane, adaptive, or overlay scenes;
- entry decorators retain state and perform cleanup when entries are popped;
- scene decorators add shared UI such as bars and rails;
- dialog destinations are overlay scenes selected by metadata;
- transitions distinguish forward, pop, and predictive pop;
- an entry is rendered by at most one active scene at a time.

Azora deliberately differs in these areas:

- metadata is typed rather than a `Map<String, Any>`;
- retained state uses Azora reactive owners and ownership rules;
- stack mutation publishes at an explicit transaction boundary;
- fixed capacities and memory policies are available for deterministic builds;
- back input is platform-neutral and includes keyboard/controller routing;
- snapshots use explicit Azora serializers and migrations;
- scene output can target ECS UI, GPU UI, DOM, native windows, or headless tests;
- no Android lifecycle, ViewModel, Activity, or Compose runtime leaks into the
  public contract.

The official Navigation 3 documentation describes the inspiration, not an ABI
Azora has to mirror. See the references in section 47.

## 5. What exists today

`packages/azora-ui/src/navigation.az` already provides a small working kernel.

### 5.1 Implemented

- `NavBackStack<K>` with typed, bounded storage;
- a root entry that cannot be popped;
- `push`, `pop`, `replace`, `popToRoot`, `current`, and indexed reads;
- monotonically increasing `version` after stack mutation;
- `NavDirection` values for push, pop, and replace;
- `NavEntry<K>` holding a key and callable content;
- `NavEntryProvider<K>` with custom equality and exact-key registration;
- `NavDisplay.sync` observing each revision once;
- display-wide `Created`, `Active`, `Suspended`, and `Destroyed` lifecycle;
- tests for typed history and revision observation;
- re-export through `engine.ui`;
- actual use in `game-sidescroller-3d` for menu/play/pause/game-over state.

### 5.2 Current limitations

| Area | Current behavior | Required target |
|---|---|---|
| Stack identity | Stores only `K` | Each pushed occurrence has stable `NavEntryId` |
| Parameterized routes | Provider matches whole values | Provider resolves route variants/types and payloads |
| Duplicate routes | Ambiguous retained identity | Independent owners for repeated equal keys |
| Failure | Capacity/root errors assert | Typed `NavError` or explicit `try*` operation |
| Mutation | One operation at a time | Atomic multi-operation transaction and change record |
| Entry metadata | None | Typed presentation, transition, pane, focus, state, and test metadata |
| Entry lifetime | One lifecycle on display | Lifecycle and owner per entry instance |
| Retained state | None | `remember`, `retain`, `preserve` scoped by entry ID |
| Decorators | None | Ordered entry and scene decorators with cleanup |
| Display | Only observes revisions | Resolves, owns, lays out, and transitions scenes |
| Scenes | None | Single-pane, adaptive, custom, and overlay scenes |
| Dialogs | None | Modal/non-modal overlay strategy and dismissal policy |
| Transitions | Direction only | Executable push/pop/replace/predictive/shared transitions |
| Back | Caller polls input | Hierarchical dispatcher with predictive phases |
| Nesting | None | Child displays/stacks with deterministic back priority |
| Multiple stacks | Manual unrelated values | First-class stack set recipe and retained top-level flows |
| Results | None | Typed result channels scoped by entry identity |
| Persistence | None | Versioned key/stack/owner snapshot contracts |
| Deep links | None | Typed URI-to-stack plans applied atomically |
| Focus/accessibility | None | Focus trap/restore, semantic routes, announcements |
| Tooling | Revision only | Stack/scene/owner inspector, traces, source navigation |
| Tests | Two unit tests | Full state, scene, overlay, transition, restore, and UI suite |

The existing API remains a compatibility layer while the implementation grows.
Its types are not discarded; their responsibilities are made precise.

## 6. Terminology

The proposal uses these terms consistently:

- **Route key**: typed application data describing requested content, such as
  `Product(id)`.
- **Stack item**: one occurrence of a route key plus stable `NavEntryId`.
- **Entry**: resolved content, metadata, and owner for one stack item.
- **Screen**: application-authored UI content of an entry. It is not a special
  storage type.
- **Scene**: a visual arrangement of one or more entries.
- **Overlay scene**: a scene drawn above scenes calculated from the entries
  below it.
- **Display**: the host that resolves entries, selects scenes, manages
  transitions, and composes visible output.
- **Strategy**: an ordered policy that may select a scene from the current
  entries and environment.
- **Decorator**: ordered logic wrapping entries or scenes with state, context,
  cleanup, diagnostics, or shared chrome.
- **Navigator**: optional application-owned helper that performs mutations. It
  is not the owner of navigation state.
- **Nested display**: a display owned by an entry and participating in the same
  back-dispatch hierarchy.

## 7. Package and module layout

The initial implementation remains in `azora-ui`, because navigation needs the
reactive owner and composition host but must not depend on a particular
renderer.

```text
azora-ui/
  engine.ui.navigation          # stack, entries, display, lifecycle
  engine.ui.navigation.scene    # scenes and scene strategies
  engine.ui.navigation.overlay  # dialogs, sheets, menus, overlays
  engine.ui.navigation.motion   # transition and predictive-back state
  engine.ui.navigation.state    # decorators, owner state, snapshots
  engine.ui.navigation.link     # URI/deep-link parsing and stack plans
  engine.ui.navigation.test     # headless display and deterministic drivers
```

The package dependencies remain one-directional:

```text
engine.core / engine.ecs / engine.input / engine.platform / std.serializer
                -> engine.ui.navigation
                -> engine.ui.compose and provider adapters
```

`engine.ui.navigation` must not import `engine.video`, `engine.audio`, gameplay
packages, or platform-native UI frameworks. An application screen may import
those packages normally.

If the module grows enough to slow unrelated UI builds, it may become
`azora-navigation` later while retaining the `engine.ui.navigation` module
name.

## 8. Canonical route model

Routes are ordinary typed Azora values. A `variant enum` is the ergonomic
default because each case can carry exactly the data its screen requires:

```azora
variant enum AppRoute {
    Home
    Search(query: std::String)
    Product(id: std::String)
    Settings(section: SettingsSection)
    ConfirmDelete(id: std::String)
}

enum SettingsSection {
    General
    Audio
    Video
    Privacy
}
```

There are no string route templates such as `"product/{id}"`. `Product("42")`
is a value with a symbol-resolved variant and a typed payload. Two variants with
similar names in different route enums remain different symbols.

Route keys should contain identifiers and display parameters, not repositories,
world borrows, native handles, or large mutable models. Screens resolve domain
state using their normal application dependencies.

Applications may use packs when they want an open route family:

```azora
pack DocumentRoute {
    fin workspace: WorkspaceId
    fin document: DocumentId
    fin mode: DocumentMode
}
```

The navigation package requires an equality function for in-memory lookup and a
codec only when a stack participates in preservation, external links, or
browser history.

## 9. Stable entry identity

A route key is not sufficient identity. The same route may be pushed twice and
each occurrence must own independent scroll position, form state, tasks, and
results.

```azora
pack NavEntryId {
    fin value: std::Long
    fin generation: std::Long
}

pack NavContentKey {
    fin value: std::Long
    fin generation: std::Long
}

pack NavStackItem<K> {
    fin id: NavEntryId
    fin key: K
}
```

`NavBackStack<K>` stores `NavStackItem<K>` internally. `push(key)` allocates a
new ID even when `key` equals an existing key. `replace(key)` also allocates a
new ID because replacement destroys the previous entry owner.

An operation that intentionally reuses an existing entry says so explicitly:

```azora
enum NavReuse {
    Never
    TopIfEqual
    ExistingNearest
    ExistingRootmost
}
```

IDs are monotonic within a navigation session. A restored snapshot carries its
saved IDs and moves the allocator beyond their maximum. IDs are never inferred
from key hashes, stack index, route names, or memory addresses.

## 10. Back-stack contract

The target stack keeps the existing typed and bounded design while exposing
stable items and typed failures.

```azora
error NavError {
    CapacityExceeded
    CannotPopRoot
    EntryNotFound
    RouteNotRegistered
    DuplicateRegistration
    InvalidMutation
    InvalidScene
    InvalidOverlay
    SnapshotVersion
    SnapshotMalformed
    LinkRejected
    TransitionRejected
}

pack NavBackStack<K> {
    var _items: std::Array<NavStackItem<K>>
    var _size: std::Int
    var _revision: std::Long
    var _nextId: std::Long
    var _lastChange: NavChange
}
```

The public surface is:

```azora
func navBackStack<K>(root: K, capacity: std::Int = 32): NavBackStack<K>

impl NavBackStack<K> {
    prop count[self: Self&]: std::Int
    prop canPop[self: Self&]: std::Bool
    prop version[self: Self&]: std::Long
    prop current[self: Self&]: K
    prop currentItem[self: Self&]: NavStackItem<K>

    func push(key: K): NavEntryId ?! NavError
    func pop(): K ?! NavError
    func replace(key: K): NavEntryId ?! NavError
    func popTo(id: NavEntryId, inclusive: std::Bool = false): std::Int ?! NavError
    func popToRoot(): std::Int
    func reset(root: K): NavEntryId
    func at(index: std::Int): K
    func itemAt(index: std::Int): NavStackItem<K>
    func indexOf(id: NavEntryId&): std::Int
}
```

The current assert-based methods may remain during migration. New application
code should be able to handle full stacks and invalid targets without turning a
recoverable navigation event into a process failure.

The root invariant remains strict: a live stack is never empty. Closing an
entire display destroys the stack owner; it does not pop the root.

## 11. Atomic mutation and navigation options

One user action often means several stack operations. Deep links, authentication
redirects, and top-level navigation must not expose intermediate screens.

```azora
enum NavDirection {
    None
    Push
    Pop
    Replace
    Reset
    Restore
}

pack NavChange {
    fin revision: std::Long
    fin direction: NavDirection
    fin from: NavEntryId
    fin to: NavEntryId
    fin added: std::Int
    fin removed: std::Int
}

pack NavOptions {
    fin reuse: NavReuse
    fin popTo: NavEntryId?
    fin inclusive: std::Bool
    fin restoreOwner: std::Bool
    fin transition: NavTransitionOverride
}
```

A navigation transaction stages operations, validates capacity and targets,
then commits once:

```azora
func navTransaction<K>(stack: NavBackStack<K>!, block: (NavMutation<K>!) -> std::Unit): NavChange ?! NavError
```

Required semantics:

1. No observer sees the staged state.
2. Validation failure leaves the original stack and owners untouched.
3. Commit increments `version` exactly once.
4. Removed entry IDs are delivered to decorators in top-to-bottom order.
5. Added entries are resolved before the visual transition starts.
6. A transaction records enough information to choose forward/pop/replace
   motion without comparing route names.

An optional `Navigator<K>` is a thin application-owned wrapper around a mutable
stack and policy callbacks. Screens should normally receive focused callbacks
such as `openProduct` or `goBack`, not a global navigator with authority over
the entire application.

## 12. Entry resolution

The current `NavEntryProvider<K>.add(key, content)` is useful for singleton
routes but cannot represent all `Product(id)` values unless every product is
registered separately. The target provider resolves a stack item by route
symbol/variant and payload.

```azora
typealias NavContent<K> = (NavEntryContext<K>!) -> std::Unit
typealias NavResolver<K> = (NavStackItem<K>&) -> NavEntry<K> ?! NavError

pack NavEntry<K> {
    fin item: NavStackItem<K>
    fin contentKey: NavContentKey
    fin metadata: NavEntryMetadata
    fin content: NavContent<K>
}

pack NavEntryContext<K> {
    fin item: NavStackItem<K>
    fin owner: NavOwnerId
    fin navigator: NavActions<K>
    fin results: NavResultScope
    fin environment: NavEnvironment
}
```

`NavActions<K>` is a capability narrowed to the containing display. It contains
callables for push, replace, back, and targeted pop; it does not expose
unrelated stacks or a global registry:

```azora
pack NavActions<K> {
    fin push: (K) -> std::Unit
    fin replace: (K) -> std::Unit
    fin back: () -> std::Unit
    fin popTo: (NavEntryId, std::Bool) -> std::Unit
}
```

The simplest provider is one resolver with an exhaustive `when`:

```azora
func appEntry(item: NavStackItem<AppRoute>&): NavEntry<AppRoute> ?! NavError {
    return when item.key {
        AppRoute.Home -> navEntry(item) { context -> HomeScreen(context) }
        AppRoute.Search(query) -> navEntry(item) { context -> SearchScreen(query, context) }
        AppRoute.Product(id) -> navEntry(item) { context -> ProductScreen(id, context) }
        AppRoute.Settings(section) -> navEntry(item) { context -> SettingsScreen(section, context) }
        AppRoute.ConfirmDelete(id) -> navEntry(
            item,
            metadata: navMetadata().dialog(dialogProperties())
        ) { context -> ConfirmDeleteDialog(id, context) }
    }
}
```

An `entryProvider { entry ... }` DSL may lower to the same resolver, but it must
match route symbols or patterns rather than string names. The compiler must
diagnose duplicate and unreachable route patterns.

`contentKey` defaults to `item.id`. A provider may use another stable key only
for an explicit shared-owner policy. Equal route keys do not imply equal content
keys.

Unknown routes produce a typed error entry or fail display preparation according
to host policy. They never silently render nothing.

## 13. Typed metadata

Entries communicate presentation intent to scene strategies through typed
metadata. Built-in metadata is explicit:

```azora
enum NavPaneRole {
    Automatic
    Primary
    Detail
    Supporting
    Extra
}

variant enum NavPresentation {
    Screen
    Dialog(properties: DialogProperties)
    BottomSheet(properties: SheetProperties)
    SideSheet(properties: SheetProperties)
    Popover(anchor: NavAnchor, properties: PopoverProperties)
    FullscreenOverlay
    Custom(value: NavPresentationValue)
}

spec NavPresentationValue {
    func symbol[self: Self&](): std::String
    func modality[self: Self&](): NavModality
}

pack NavEntryMetadata {
    var presentation: NavPresentation
    var pane: NavPaneRole
    var transitions: NavTransitionSet
    var statePolicy: NavStatePolicy
    var focusPolicy: NavFocusPolicy
    var backPolicy: NavBackPolicy
    var chrome: NavChromePolicy
    var title: std::String
    var testId: std::String
    var custom: std::Array<NavMetadataValue>
}
```

The built-in policies are values rather than hidden display flags:

```azora
pack NavStatePolicy {
    fin retainWhileSuspended: std::Bool
    fin preserveSnapshot: std::Bool
    fin evictableUnderPressure: std::Bool
}

variant enum NavFocusPolicy {
    Restore
    Default(key: std::String)
    FirstEligible
    DisplayRoot
}

enum NavBackPolicy {
    Pop
    Dismiss
    Intercept
    Disabled
}

enum NavChromePolicy {
    Inherit
    Show
    Hide
}

variant enum NavTransitionOverride {
    Inherit
    Use(transitions: NavTransitionSet)
    Disabled
}
```

Presentation dimensions and anchors are provider-neutral:

```azora
variant enum NavDimension {
    Content
    Fill
    Points(value: std::Double)
    Fraction(value: std::Double)
}

variant enum NavAnchor {
    Node(key: std::String)
    Point(x: std::Double, y: std::Double)
    Pointer
}

enum NavModality {
    Modal
    NonModal
}

pack SheetProperties {
    fin modal: std::Bool
    fin dismissOnBack: std::Bool
    fin dismissOnOutsidePress: std::Bool
    fin extent: NavDimension
    fin scrimAlpha: std::Double
}

pack PopoverProperties {
    fin modal: std::Bool
    fin dismissOnBack: std::Bool
    fin dismissOnOutsidePress: std::Bool
    fin keepInsideWindow: std::Bool
}
```

Custom metadata implements a nominal contract:

```azora
spec NavMetadataValue {
    func symbol[self: Self&](): std::String
}
```

Strategies request a specific metadata symbol and cast only through an
implementation registered for that symbol. Similar strings do not grant type
compatibility. The IDE resolves a metadata constructor and consumer by symbol.

Metadata is immutable for one resolved entry revision. Changing metadata
requires resolving a new entry revision so scene and transition selection do
not change halfway through a frame.

## 14. Entry owners and lifecycle

Each `NavEntryId` owns one reactive/navigation scope:

```azora
pack NavOwnerId {
    fin value: std::Long
    fin generation: std::Long
}

enum NavLifecycle {
    Created
    Active
    Suspended
    Destroyed
}

pack NavEntryOwner {
    fin id: NavOwnerId
    fin entry: NavEntryId
    fin parent: NavOwnerId?
    var lifecycle: NavLifecycle
    var revision: std::Long
}
```

Lifecycle meaning is precise:

- `Created`: resolved and owned, but never committed as a visible scene.
- `Active`: visible and eligible for focus/input according to scene policy.
- `Suspended`: retained on a stack but not currently interactive. A multi-pane
  scene may keep more than one entry active.
- `Destroyed`: removed from every owning stack; effects, tasks, result
  subscriptions, focus registrations, and native/provider leases are disposed.

Transition presence is separate from owner lifecycle:

```azora
enum NavPresence {
    Hidden
    Entering
    Present
    Exiting
    Predictive
}
```

An exiting scene may still be drawn after its entry owner becomes non-active,
but it cannot receive ordinary input or launch new owner work. Resources needed
for exit rendering live in a transition snapshot, not in an accidentally live
screen.

## 15. Reactive state retention

Entry content runs under its `NavEntryOwner`. Azora state lifetimes apply
directly:

```azora
react func ProductScreen(id: std::String, context: NavEntryContext<AppRoute>&) {
    remember var menuOpen = false
    retain var scroll = 0.0
    preserve var selectedTab = 0

    effect defer {
        // cancel entry-local observation or release entry-local capability
    }

    productContent(id, selectedTab, scroll)
}
```

- `remember` survives recomposition while the current owner exists.
- `retain` survives temporary scene/layout recreation in the process.
- `preserve` is included in explicit owner snapshots when a serializer exists.
- popping the entry destroys all three lifetimes after transition-safe cleanup.
- switching from single-pane to list-detail does not recreate entry owners.
- an equal route pushed again receives a new owner and independent state.

State must never be keyed only by route equality. It is keyed by
`NavEntryId`/`contentKey` and verified against owner generation.

## 16. Entry decorators

Entry decorators apply ordered cross-cutting behavior around every resolved
entry while it remains on the stack.

```azora
spec NavEntryDecorator<K> {
    func attach[self: Self!](entry: NavEntry<K>&, owner: NavEntryOwner!): std::Unit ?! NavError
    func present[self: Self!](entry: NavEntry<K>&, context: NavEntryContext<K>!, next: () -> std::Unit)
    func onPop[self: Self!](entry: NavEntry<K>&, owner: NavEntryOwner!)
}
```

The default order is:

1. owner/state decorator;
2. preserved-state decorator;
3. result-scope decorator;
4. focus/input decorator;
5. profiler/diagnostic decorator;
6. application decorators;
7. entry content.

Decorators may:

- create owner-scoped dependencies;
- install a state store or result channel;
- provide navigation context;
- trace composition and cleanup;
- wrap content with a shared UI boundary;
- clean state when an entry is popped.

Decorators must not:

- change stack order during entry resolution;
- capture mutable stack borrows beyond the call;
- keep an owner alive after `onPop`;
- replace modal scene policy that belongs in metadata/scene strategies;
- provide dependencies broader than the stack or entry scope.

`onPop` runs exactly once per entry ID even when a transition is cancelled,
restarted, or the containing display is destroyed.

## 17. NavDisplay responsibilities

The current `NavDisplay.sync` is the seed of a full renderer-neutral host.

```azora
pack NavDisplay<K> {
    var observedRevision: std::Long
    var entries: std::Array<NavEntry<K>>
    var sceneState: NavSceneState<K>
    var transition: NavTransitionState<K>
    var lifecycle: NavLifecycle
    var owner: NavOwnerId
}

pack NavSceneState<K> {
    var current: NavScene<K>
    var previous: std::Array<NavScene<K>>
    var overlays: std::Array<NavScene<K>>
    var revision: std::Long
}
```

Scene selection reads a provider-neutral environment. Platform adapters publish
a new revision only when a relevant value changes:

```azora
enum NavWindowClass {
    Compact
    Medium
    Expanded
}

pack NavEnvironment {
    fin width: std::Double
    fin height: std::Double
    fin scale: std::Double
    fin windowClass: NavWindowClass
    fin safeStart: std::Double
    fin safeTop: std::Double
    fin safeEnd: std::Double
    fin safeBottom: std::Double
    fin keyboardVisible: std::Bool
    fin pointerAvailable: std::Bool
    fin controllerAvailable: std::Bool
    fin reducedMotion: std::Bool
    fin revision: std::Long
}
```

On a committed stack revision the display:

1. computes added, retained, moved, and removed entry IDs;
2. resolves only new or invalidated entries;
3. attaches decorators and owner state;
4. calls `onPop` for entries that truly left the stack;
5. invokes scene strategies in declared order;
6. validates that each visible entry has one rendering owner;
7. applies scene decorators to non-overlay scenes;
8. chooses transition metadata and creates immutable transition state;
9. commits lifecycle, focus, semantics, and back-handler changes together;
10. publishes one display revision to reactive UI.

The display does not mutate the application's stack on its own. `onBack` and
dismissal policies call application-provided actions.

An unchanged stack, environment, strategy revision, and transition clock causes
no entry resolution or recomposition.

## 18. Scenes

A scene is the visual unit animated by `NavDisplay`. It may render one or more
entries.

```azora
pack NavSceneKey {
    fin kind: std::String
    fin value: std::Long
}

pack NavScene<K> {
    fin key: NavSceneKey
    fin entries: std::Array<NavEntry<K>>
    fin previousEntries: std::Array<NavEntry<K>>
    fin metadata: NavSceneMetadata
    fin content: (NavSceneContext<K>!) -> std::Unit
}

pack NavSceneContext<K> {
    fin entries: std::Array<NavEntry<K>>
    fin environment: NavEnvironment
    fin direction: NavDirection
    fin transitionProgress: std::Double
}

pack NavSceneMetadata {
    var transitions: NavTransitionSet
    var forceTransitions: std::Bool
    var title: std::String
    var semanticRole: std::String
}

pack NavSceneScope<K> {
    fin entries: std::Array<NavEntry<K>>
    fin previousEntries: std::Array<NavEntry<K>>
    fin environment: NavEnvironment
    fin direction: NavDirection
}

variant enum NavSceneResult<K> {
    Use(scene: NavScene<K>)
    Pass
}

spec NavSceneStrategy<K> {
    func calculate[self: Self&](scope: NavSceneScope<K>&): NavSceneResult<K>
}
```

Strategies are evaluated in order. The first non-overlay strategy returning a
scene owns the relevant entries. If no strategy accepts them,
`SinglePaneSceneStrategy` renders the top entry.

A scene key includes both strategy/scene kind and logical identity. Animation
must restart when the scene kind changes even if its top route remains equal.

The display enforces unique entry rendering. During a scene-to-scene transition
an entry eligible for both old and new scenes is composed in the target scene;
the source scene receives a transition snapshot or shared-element projection.
Its content callable is never invoked twice in one committed frame.

## 19. Built-in screen and adaptive scene strategies

### 19.1 Single pane

`SinglePaneSceneStrategy` displays the top non-overlay entry. This is the
default for games, phones, and simple tools.

### 19.2 List-detail

`ListDetailSceneStrategy` finds a nearest primary/list entry followed by a
detail entry. In compact windows it displays only the detail. In expanded
windows it displays both, preserving the same entry owners while changing
scene layout.

```azora
entryMetadata.pane = NavPaneRole.Primary
entryMetadata.pane = NavPaneRole.Detail
```

Back from the detail removes the detail route in either layout. Resizing from
wide to narrow does not mutate the stack.

### 19.3 Supporting pane

`SupportingPaneSceneStrategy` may display primary, detail, and supporting
entries together. Examples include a video plus playlist, editor plus preview,
or game plus inventory inspector.

### 19.4 Custom scenes

Applications can implement strategies for dashboards, split editors, world/UI
hybrids, foldable layouts, VR panels, or multi-window workspaces. A strategy
receives:

- decorated entries in stack order;
- window dimensions, scale, safe areas, and posture;
- input capabilities;
- active nested-display information;
- transition/predictive-back candidate state;
- a read-only strategy environment.

It cannot mutate navigation while calculating a scene.

### 19.5 Screens are ordinary content

`Screen` is a design term, not an Azora keyword and not a required base type.
An entry content callable may invoke a `react func`, compose ECS UI, draw an
engine world, mount DOM content, or bridge a native view. The scene owns how it
is arranged and clipped.

## 20. Scene decorators and shared chrome

Scene decorators add UI around a calculated non-overlay scene:

```azora
spec NavSceneDecorator<K> {
    func decorate[self: Self&](scene: NavScene<K>&, environment: NavEnvironment&): NavScene<K>
}
```

Uses include:

- top bars and breadcrumbs;
- bottom navigation or side rails;
- desktop title/tab bars;
- safe-area padding;
- debug navigation inspector;
- global loading/error banners;
- accessibility landmarks.

Each decorated scene derives its key from the input scene kind and key, so
decorating a scene does not accidentally suppress transitions.

Overlay scenes are not wrapped by ordinary scene decorators because they may
render in another layer or native window. An explicit overlay decorator handles
dialog frames, scrims, sheet handles, and overlay-specific semantics.

Shared chrome is composed once during transitions. It is not duplicated in
both source and destination scenes.

## 21. Dialogs and overlay scenes

Dialogs are navigation entries with overlay presentation metadata. They are not
special global booleans and not hidden children of whichever screen happened to
open them.

```azora
pack DialogProperties {
    fin modal: std::Bool
    fin dismissOnBack: std::Bool
    fin dismissOnOutsidePress: std::Bool
    fin dismissOnEscape: std::Bool
    fin trapFocus: std::Bool
    fin restoreFocus: std::Bool
    fin width: NavDimension
    fin height: NavDimension
    fin scrimAlpha: std::Double
}

enum NavDismissReason {
    Accepted
    Cancelled
    Back
    Escape
    OutsidePress
    OwnerClosed
    Replaced
}
```

`DialogSceneStrategy` runs before non-overlay strategies. It consumes the top
dialog entry and exposes lower entries as `overlaidEntries`; scene strategy
evaluation then restarts from the first strategy for those lower entries. This
supports a dialog over a list-detail scene and multiple stacked dialogs without
flattening the background.

An overlay scene contains:

```azora
pack NavOverlayScene<K> {
    fin scene: NavScene<K>
    fin overlaidEntries: std::Array<NavEntry<K>>
    fin modality: NavModality
    fin layer: std::Int
    fin dismiss: (NavDismissReason) -> std::Unit
}
```

Rules:

1. Modal overlays prevent pointer, keyboard, controller, and accessibility
   actions from reaching covered scenes.
2. Non-modal overlays may pass unhandled input according to explicit policy.
3. The topmost eligible overlay receives back first.
4. Focus is trapped when requested and restored to the opening node/entry after
   dismissal when that target still exists.
5. Outside-press dismissal tests the committed dialog bounds, not stale layout.
6. Pop removes the dialog entry and reports its dismissal reason/result.
7. Exit motion completes from a transition snapshot; it does not delay stack
   truth or owner cleanup indefinitely.
8. Destroying the parent display dismisses every owned overlay top-down.

### 21.1 Other overlays

Built-in overlay strategies include:

- bottom and side sheets;
- context menus and popovers that should participate in back/history;
- full-screen modal overlays;
- command palettes;
- platform-native modal windows where supported.

Tooltips, transient toasts, drag previews, and purely visual hover cards should
normally use transient UI state rather than navigation entries. The criterion
is whether the user expects back/dismissal, retained state, results, or history.

### 21.2 Dialog content with nested screens

A dialog may contain a nested display for a wizard or multi-page settings flow.
Back first pops the dialog's child stack; only its root dismisses the dialog.
The dialog remains one parent-stack entry and one overlay scene.

## 22. Transition model

Transitions animate scenes, not route-name comparisons.

```azora
enum NavEdge {
    Start
    End
    Top
    Bottom
}

variant enum NavMotion {
    None
    Fade
    Slide(edge: NavEdge, distance: std::Double)
    Scale(from: std::Double)
    Shared(group: std::String)
    Custom(animation: NavAnimation)
}

pack NavMotionFrame {
    fin opacity: std::Double
    fin offsetX: std::Double
    fin offsetY: std::Double
    fin scaleX: std::Double
    fin scaleY: std::Double
}

spec NavAnimation {
    func name[self: Self&](): std::String
    func sample[self: Self&](progress: std::Double, entering: std::Bool): NavMotionFrame
}

variant enum NavSizeTransform {
    Snap
    Interpolate
    Clip
    Custom(animation: NavAnimation)
}

pack NavContentTransform {
    fin entering: NavMotion
    fin exiting: NavMotion
    fin durationSeconds: std::Double
    fin size: NavSizeTransform
    fin clip: std::Bool
}

pack NavTransitionSet {
    fin forward: NavContentTransform
    fin pop: NavContentTransform
    fin replace: NavContentTransform
    fin predictivePop: NavContentTransform
}
```

Transition selection precedence is deterministic:

1. explicit `NavOptions.transition` for the committed mutation;
2. target entry metadata for forward/replace;
3. departing entry metadata for pop;
4. selected scene metadata;
5. display defaults;

A scene may mark a transition override as `forced` when its layout cannot
support an entry-level motion, such as switching between one and three panes.
The inspector records which level won.

Transition state is explicit:

```azora
enum NavTransitionPhase {
    Idle
    Preparing
    Running
    Completing
    Cancelling
}

pack NavTransitionState<K> {
    var phase: NavTransitionPhase
    var direction: NavDirection
    var from: NavScene<K>
    var to: NavScene<K>
    var progress: std::Double
    var interactive: std::Bool
    var revision: std::Long
}
```

### 22.1 Interruption

When another navigation transaction commits during a transition:

- the engine samples the current visual state;
- chooses merge, finish, or cancel according to transition policy;
- never invokes entry content twice;
- never revives a popped owner;
- starts the next transition from a stable snapshot;
- reports interruption to profiler diagnostics.

Reduced-motion preferences replace nonessential movement with fade or no
motion while preserving lifecycle and timing boundaries.

### 22.2 Shared elements

Shared elements are identified by `(entry contentKey, element key, group)`, not
display text or tree position. Source and target layout publish immutable bounds
and render projections. The transition layer moves the projection while each
entry remains uniquely composed.

Missing source/target elements degrade to the ordinary scene transition.
Duplicate shared keys in one entry are a diagnostic error.

## 23. Predictive back

Predictive back previews the result of back without committing stack mutation.

```azora
enum NavBackPhase {
    Idle
    Started
    Progressed
    Cancelled
    Completed
}

pack NavBackGesture {
    var phase: NavBackPhase
    var progress: std::Double
    var edge: NavEdge
    var pointer: std::Int
    var target: NavEntryId
}
```

Sequence:

1. `Started`: resolve the back target and candidate scene state without popping.
2. `Progressed`: clamp progress to `0 .. 1` and render the predictive transform.
3. `Cancelled`: animate or snap back to the current scene; stack and owners are
   unchanged.
4. `Completed`: commit the previously validated pop transaction exactly once,
   continue from current visual progress, then clean removed owners.

The candidate may be:

- dismissal of the top overlay;
- a pop in the deepest active nested display;
- a pop in the current top-level stack;
- switching to the starting top-level stack under an exit-through-home policy;
- platform exit when no navigation handler consumes back.

If navigation changes independently during a gesture, the candidate generation
no longer matches. The gesture cancels safely and must not pop a different
entry.

Keyboard Escape and controller Back are non-progressive completions through the
same dispatcher, not separate stack logic.

## 24. Hierarchical back dispatch

Back is routed by visible hierarchy and priority:

```azora
enum NavBackPriority {
    Overlay
    Nested
    Screen
    Display
    PlatformExit
}

spec NavBackHandler {
    func enabled[self: Self&](): std::Bool
    func begin[self: Self!](event: NavBackGesture&): std::Bool
    func progress[self: Self!](event: NavBackGesture&)
    func cancel[self: Self!]()
    func complete[self: Self!]()
}
```

Ordering is priority first, then visual depth, then most recent registration.
Only active owners register handlers. Covered modal scenes are ineligible.

A screen may intercept back for UI logic such as an unsaved-edit confirmation,
but it does not perform business authorization in a back callback. The normal
pattern pushes a confirmation dialog and completes the original navigation only
after the typed result accepts it.

The dispatcher is scoped. A nested display receives a child dispatcher whose
unhandled event bubbles to the parent. Removing the owner removes all its
handlers automatically.

## 25. Nested screens and nested displays

Nested navigation is used when a screen contains an independent flow whose
history and lifetime belong to that screen.

```azora
variant enum SettingsRoute {
    Overview
    Audio
    Video
    Advanced
}

react func SettingsScreen(context: NavEntryContext<AppRoute>&) {
    preserve var stack = navBackStack<SettingsRoute>(SettingsRoute.Overview)

    navDisplay(
        stack: stack,
        parent: context.owner,
        entryProvider: settingsEntryProvider(),
        backDispatcher: context.environment.back.child()
    )
}
```

Rules:

1. The child stack owner is the parent entry owner.
2. Suspending the parent suspends its child display without destroying history.
3. Popping the parent destroys child overlays, child entries, and child stack
   state in top-down order.
4. Back operates on the deepest active child that can handle it.
5. Child route keys do not enter the parent stack unless a deep-link codec
   explicitly maps a path through both levels.
6. Parent and child transitions may coordinate, but only one layer owns an input
   gesture.
7. A nested display has its own scene strategies and may be multi-pane inside a
   pane or dialog.
8. Cyclic owner/display parentage is rejected.

Nested screens are not implemented by concatenating route strings or searching
for names. Parentage is stable owner identity.

For a simple two-state child panel, ordinary reactive state is preferable to a
nested stack. Use nested navigation when child history, back, preservation,
deep links, or overlays are real requirements.

## 26. Multiple top-level back stacks

Tabs, bottom navigation, and workspace roots often keep independent histories.
The application still owns those stacks.

```azora
enum TopLevelRoute {
    Home
    Library
    Settings
}

pack AppNavigation {
    var selected: TopLevelRoute
    var home: NavBackStack<AppRoute>
    var library: NavBackStack<AppRoute>
    var settings: NavBackStack<AppRoute>
    var revision: std::Long
}
```

`NavStackSet<T, K>` may provide a reusable bounded implementation when every
top-level root uses one route type. It retains entry decorators and owners per
stack while only the selected stack is active.

Policies include:

- **Preserve history**: selecting a root resumes its existing top entry.
- **Reselect pops to root**: selecting the active tab again clears its history.
- **Exit through home**: back from another root switches to the starting root;
  back from the starting root exits.
- **Global chronological back**: optional desktop policy following most recent
  root usage.

Switching roots is a scene transition, not necessarily a push or pop. It does
not merge independent histories or recreate suspended owners.

Shared bars/rails belong in a scene decorator so they are composed once while
the selected stack changes.

## 27. Typed results

Screens and dialogs often return values. Results are addressed to an entry
instance, not the nearest route with a matching name.

```azora
pack NavResultKey<T> {
    fin symbol: std::String
}

pack NavResultChannel<T> {
    fin key: NavResultKey<T>
    fin sender: NavEntryId
    fin receiver: NavEntryId
    var revision: std::Long
}

pack NavResultScope {
    fin owner: NavOwnerId
    fin entry: NavEntryId
    fin generation: std::Long
}
```

Example:

```azora
fin fileResult = NavResultKey<FileId>("editor.file-selected")

func openFilePicker(context: NavEntryContext<AppRoute>!) {
    context.navigator.push(AppRoute.FilePicker)
    context.results.expect(fileResult, context.item.id)
}

func chooseFile(context: NavEntryContext<AppRoute>!, file: FileId) {
    context.results.send(fileResult, file)
    context.navigator.back()
}
```

Required behavior:

- the sender can emit at most according to channel policy: once, conflated, or
  stream;
- the receiver subscription belongs to its owner and is cancelled on pop;
- a result cannot be delivered to a reused ID generation;
- result delivery publishes after the navigation transaction commits;
- values obey ordinary ownership and cannot smuggle a short-lived borrow;
- preserved result channels require an explicit serializer;
- cancellation/dismissal may be a typed result rather than a magic null.

Direct callbacks remain preferable when the child content is not independently
navigated or restored.

## 28. Preservation and restoration

Navigation state is explicitly preservable; it is not assumed that every route
can be serialized.

```azora
spec NavRouteCodec<K> {
    func version[self: Self&](): std::Int
    func encode[self: Self&](key: K&): std::SerialValue ?! NavError
    func decode[self: Self&](value: std::SerialValue&): K ?! NavError
}

pack NavStackSnapshot {
    fin formatVersion: std::Int
    fin routeVersion: std::Int
    fin stackId: std::Long
    fin items: std::Array<NavItemSnapshot>
    fin selected: std::Int
    fin owners: std::Array<NavOwnerSnapshot>
}

pack NavItemSnapshot {
    fin id: std::Long
    fin generation: std::Long
    fin key: std::SerialValue
}

pack NavPreservedValue {
    fin owner: std::Long
    fin symbol: std::String
    fin value: std::SerialValue
}

pack NavOwnerSnapshot {
    fin id: std::Long
    fin generation: std::Long
    fin entry: std::Long
    fin parent: std::Long
    fin values: std::Array<NavPreservedValue>
}
```

Snapshots contain:

- route keys through their codec;
- stable entry IDs/generations;
- selected top-level stack and nested stack structure;
- values declared `preserve` with serializers;
- pending result state only when its policy permits preservation;
- enough schema/version information to migrate or reject safely.

Snapshots never contain:

- rendered UI/ECS node trees;
- `remember` or non-preserved `retain` values;
- tasks, closures, borrows, world/query references;
- GPU/audio/video/native handles;
- focus node pointers rather than stable focus keys;
- a transition's transient render snapshots.

Restoration is transactional:

1. decode and migrate all route keys;
2. validate capacity, parentage, IDs, and registered destinations;
3. create entry owners in suspended state;
4. restore preserved cells;
5. select scenes for the current environment;
6. activate visible owners and publish one revision.

Failure leaves the existing navigation state untouched. The host chooses a
fallback such as a clean root stack or an error screen.

## 29. Deep links, browser history, and external navigation

A deep link produces a typed stack plan rather than mutating a stack while it
parses.

```azora
pack NavUri {
    fin scheme: std::String
    fin host: std::String
    fin path: std::Array<std::String>
    fin query: std::Array<NavQueryValue>
}

pack NavQueryValue {
    fin name: std::String
    fin value: std::String
}

pack NavNestedPlan {
    fin parent: NavEntryId
    fin slot: std::String
    fin snapshot: std::SerialValue
}

pack NavStackPlan<K> {
    fin root: K
    fin pushes: std::Array<K>
    fin nested: std::Array<NavNestedPlan>
    fin replaceCurrent: std::Bool
}

spec NavLinkResolver<K> {
    func resolve[self: Self&](uri: NavUri&): NavStackPlan<K> ?! NavError
}
```

The resolver validates scheme, host, path grammar, payload sizes, identifiers,
and allowed destinations. Applying a plan is one navigation transaction.

External links never bypass application authorization. A link may construct
`AdminPanel`, but the screen/domain layer still verifies the user's capability
and redirects or reports failure.

Browser integration maps committed navigation transactions to history entries:

- push -> `pushState`;
- replace/reset/restore -> `replaceState` according to policy;
- browser pop -> validated stack transaction;
- nested changes may remain internal or encode into the URL by codec policy;
- predictive browser back is used only where the platform exposes a safe
  progress contract.

Opening an external URI is a platform effect and not implicit navigation.

## 30. Asynchronous preparation and loading

Navigation must remain responsive when a destination needs assets or data.

The default model commits the route immediately and lets its screen render
loading/error/content state. This preserves application ownership and permits
back while loading.

For destinations that must validate before becoming visible, an optional
preparation contract runs before transaction commit:

```azora
variant enum NavPreparation<K> {
    Ready
    Redirect(key: K)
}

spec NavEntryPreparation<K> {
    async func prepare[self: Self!](item: NavStackItem<K>&, owner: NavOwnerId): NavPreparation<K> ?! NavError
    func cancel[self: Self!]()
}
```

Preparation rules:

- it receives an owner token but no mutable display/stack borrow;
- cancellation occurs if the initiating owner dies or a newer transaction wins;
- success is generation-checked before commit;
- failure leaves the previous scene active unless policy pushes an error entry;
- preparation time and cancellation are profiler-visible;
- no entry owner becomes active before validated commit.

Prefetch may resolve metadata or load immutable assets for nearby entries, but
it cannot run entry effects, acquire focus, or claim input.

## 31. Error and fallback behavior

Failures are visible and recoverable:

- unknown route: `RouteNotRegistered` with route symbol and entry ID;
- invalid scene: strategy name, selected entries, and violated invariant;
- capacity exceeded: requested count and configured capacity;
- snapshot failure: format/schema path and migration availability;
- transition failure: fall back to no motion while preserving committed state;
- overlay provider unavailable: render engine overlay unless native-only was
  explicitly required;
- missing deep-link destination: reject plan before stack mutation;
- stale async/result/back generation: ignore safely and trace it.

Production hosts may map a resolution error to an application-provided error
entry. Debug builds should preserve the original diagnostic and stack trace.

## 32. Integration with `react func` and `@compose`

The intended high-level use is:

```azora
react func Application(world: World&) {
    preserve var stack = navBackStack<AppRoute>(AppRoute.Home)

    @compose world {
        navDisplay(
            stack: stack,
            entryProvider: appEntryProvider(),
            sceneStrategies: [
                dialogSceneStrategy(),
                listDetailSceneStrategy(),
                singlePaneSceneStrategy()
            ],
            sceneDecorators: [appChromeDecorator()],
            onBack: [&stack] {
                if stack.canPop {
                    stack.pop() catch { }
                }
            }
        )
    }
}
```

`navDisplay` is a retained keyed UI node. Recomposition with the same key keeps
display state, entry owners, transition state, and focus identity. Removing it
destroys the display and all owned entries.

Stack mutation from a click handler is queued for the UI transaction boundary.
The active composition pass is never structurally modified halfway through.

For immediate-mode compatibility, a host may call `display.sync(stack)` and
switch on `stack.current`, as the current side-scroller template does. That path
does not receive automatic scenes, owners, dialogs, or transitions until it
adopts the full display host.

## 33. ECS and world integration

Navigation state is normally an application resource, not a component copied
onto every screen entity.

World-facing games may store a stable navigation resource:

```azora
@Resource
pack GameNavigation {
    var stack: NavBackStack<GameRoute>
    var display: NavDisplay<GameRoute>
}

@System(.Update)
func pauseOnRequest(
    navigation: GameNavigation!,
    requests: @query [PauseRequested&] @with Player @without Disabled
) {
    loop requests {
        navigation.stack.push(GameRoute.Paused) catch { }
    }
}
```

Navigation mutations obey the normal ECS publication boundary. A system must
not retain a mutable resource/query borrow in entry content or across `await`.

An entry owner may own a composition root whose UI nodes are ECS entities. Pop
disposes that root through the same keyed ownership mechanism described in
`REACTIVE_ECS_UI.MD`. Gameplay entities do not disappear merely because a UI
screen is popped unless an explicit game command says so.

## 34. Focus, input, and accessibility

### 34.1 Focus

Each scene publishes focus scopes and a default focus target. On scene change:

1. capture the stable focus key in the departing active entry;
2. activate target scene focus scopes;
3. restore a saved target when valid;
4. otherwise select scene default, first eligible target, or display root;
5. announce the scene change to accessibility providers.

Modal dialogs trap focus. Dismissal restores the opener when still live, then
falls back through the underlying scene policy.

### 34.2 Input

Navigation recognizes platform-neutral actions:

- `NavigateBack`;
- `NavigateForward` where history policy permits;
- `Dismiss`;
- directional focus/pane movement;
- pointer/touch edge back gesture;
- keyboard Escape/Alt-Left;
- controller Back/B;
- accessibility dismiss/back actions.

Actions enter the hierarchical dispatcher after capture handlers and before
ordinary bubbling according to UI input policy. A covered scene cannot receive
click-through on the frame an overlay appears.

### 34.3 Accessibility

Entries and scenes expose:

- title and semantic route role;
- dialog/modal state;
- pane role and relationship;
- back/dismiss availability;
- stable test/accessibility ID;
- transition/reduced-motion state where providers need it.

Screen changes announce the new title once. Predictive back previews do not
announce a destination until completion. Suspended entries are absent from the
active accessibility tree unless a multi-pane scene displays them.

## 35. Platform behavior

The core semantics are identical across providers; integration differs:

### Desktop

- Escape and platform back shortcuts enter the dispatcher;
- dialogs may be engine overlays or native child windows by policy;
- multi-window displays own separate focus/back roots;
- window close can be intercepted by the same confirmation flow;
- keyboard traversal and menu commands expose navigation actions.

### WebAssembly/browser

- URL/history mapping uses the route codec and link resolver;
- browser pop is reconciled transactionally;
- page refresh restores only preserved serializable state;
- overlays default to DOM/engine layers rather than new browser windows;
- invalid external history state falls back safely.

### Mobile/touch

- edge gestures drive predictive back;
- safe areas and keyboard insets enter `NavEnvironment`;
- list-detail strategy reacts to size/posture without stack mutation;
- platform modal surfaces may be used when they preserve focus and lifecycle
  semantics.

### Game/console

- controller Back participates in hierarchy;
- pause is usually an overlay route over the playing scene;
- navigation can continue while world simulation uses a separate pause policy;
- transitions use engine time configured to continue when gameplay time stops.

## 36. Time and scheduling

Navigation transition time comes from a UI/presentation clock, not fixed-step
simulation time. A paused game can still animate its pause menu.

The frame order is:

```text
platform input
-> navigation back/gesture update
-> application and ECS navigation commands
-> commit navigation transactions
-> resolve entries and scene state
-> advance transitions
-> compose visible scene/overlay roots
-> layout, focus, semantics, hit testing
-> render extraction
```

A command emitted during composition is committed at the next permitted
boundary, preventing recursive display mutation.

Transition completion schedules cleanup but does not decide stack truth. Stack
truth changes at navigation transaction commit.

## 37. Determinism and performance

The runtime must guarantee:

- scene strategies run in declared order;
- decorators run in declared order and clean up in reverse where applicable;
- one entry content invocation per frame;
- one stack revision per committed transaction;
- stable IDs independent of allocation addresses;
- bounded overlay, entry, transition, and snapshot storage where configured;
- no route or metadata lookup by similar names;
- no full entry recreation for an unchanged stack revision;
- no retained owner lookup by linear route-name scans;
- no per-frame serialization;
- no input to suspended/covered owners.

The display caches resolved entries by `(NavEntryId, provider revision)`, scene
selection by `(entry revisions, environment revision, strategy revisions)`, and
composition by owner/read revisions.

Recommended profiler counters/spans:

- stack depth and high-water mark;
- active/suspended owner counts;
- entry resolve/decorator time;
- scene-strategy time and selected strategy;
- compose/layout time per scene;
- transition duration, interruption, dropped frames;
- overlay count and dismissal reason;
- stale task/result/back completions;
- snapshot bytes and restore/migration time.

## 38. Testing

### 38.1 Stack tests

- root invariants and capacity failure;
- push/pop/replace/reset directions;
- duplicate equal keys receive different IDs;
- `popTo` inclusive/exclusive semantics;
- transaction rollback and single revision;
- restoration continues ID allocation safely.

### 38.2 Entry and owner tests

- variant payload resolution;
- duplicate/unhandled provider patterns;
- owner state survives suspension and adaptive scene changes;
- popped owner disposes effects/tasks/results once;
- stale generations cannot update a replacement entry;
- decorator order and cleanup.

### 38.3 Scene tests

- single-pane fallback;
- list-detail and supporting-pane selection by environment;
- unique entry rendering across scene transitions;
- decorator key derivation;
- invalid scene rejection;
- resizing changes scenes without mutating stacks.

### 38.4 Overlay tests

- dialog over single- and multi-pane scenes;
- several stacked dialogs;
- back/Escape/outside-press policy;
- focus trap and restoration;
- modal input blocking in the same committed frame;
- nested wizard pop before dialog dismissal;
- overlay cleanup when parent display closes.

### 38.5 Transition/back tests

- forward/pop/replace selection precedence;
- interruption without duplicate content;
- predictive start/progress/cancel/complete;
- generation invalidation during a gesture;
- reduced-motion fallback;
- shared-element duplicate/missing behavior.

### 38.6 Persistence/link/result tests

- route and owner snapshot round trip;
- schema migration and malformed snapshot rollback;
- deep-link plan validation and atomic application;
- browser history reconciliation;
- typed result delivery, cancellation, and stale receiver rejection.

### 38.7 Headless UI tests

`engine.ui.navigation.test` supplies a `TestNavDisplay<K>` with fixed window
metrics, clock, input, and transition driver. Tests inspect:

- visible scenes and entries;
- active/suspended/destroyed owners;
- semantic/focus tree;
- transition phase and progress;
- back-handler winner;
- emitted navigation changes and profiler records.

Pixel tests belong to provider adapters. Core navigation correctness must not
require a GPU, browser, native dialog, or real clock.

## 39. Tooling and IDE support

The runtime and AZLS expose a navigation inspector:

```text
Display Main
  Scene ListDetail(home#1, product#4)
  Overlay Dialog(confirm-delete#7)
  Stack [Home#1, Product("42")#4, ConfirmDelete("42")#7]
  Owners Active: #1 #4 #7
  Back winner: Dialog#7
  Transition: Pop 0.38
```

Required IDE behavior:

- go to definition from route variant use to its symbol;
- go from `entry` route pattern to its content declaration;
- find all route pushes/replacements and provider handlers symbolically;
- diagnose unhandled route variants where provider exhaustiveness is known;
- diagnose duplicate provider patterns and metadata symbols;
- show entry/scene/decorator lifecycle in debugger views;
- inspect transition precedence and chosen strategy;
- preview deep-link stack plans;
- never connect routes because names happen to be similar.

Profiler navigation spans link stack transaction, entry resolution, scene
selection, composition, transition, and render frames by stable IDs.

## 40. Security and authority

Navigation is presentation state, not permission.

- A deep link or restored route cannot grant access to protected content.
- Route codecs enforce length/count limits before allocation.
- External URIs use allowlisted schemes/hosts and canonical decoding.
- Snapshots are schema-checked and may require integrity/authenticity policy.
- Entry metadata cannot inject arbitrary renderer commands.
- Custom strategies/decorators receive only declared capabilities.
- Debug stack inspection redacts route payloads marked sensitive.
- Results obey ownership and cannot transfer undeclared device/file/network
  authority.
- Dialog dismissal cannot bypass a domain transaction already in progress.

Applications validate capabilities when actions execute, even when a button or
route is hidden or disabled.

## 41. Compatibility and migration

The current implementation can evolve incrementally:

1. Add internal `NavStackItem<K>` while preserving `current`, `at`, and
   `push(key)` source shape.
2. Add typed failure variants or `tryPush`/`tryPop` before changing assert-based
   methods.
3. Extend `NavEntry<K>` with item ID and default metadata.
4. Add resolver providers alongside exact-key providers.
5. Make `NavDisplay` generic while retaining `navDisplay()` inference.
6. Move display-wide lifecycle to entry owners; keep display lifecycle as host
   lifecycle.
7. Implement single-pane scenes first so existing visual behavior remains.
8. Add dialog strategy and transition state without requiring adaptive scenes.
9. Add reactive/ECS `navDisplay` builder while retaining manual `sync`.
10. Update templates from `switch current` rendering to entry providers when
    the retained UI host is ready.

Existing code such as:

```azora
var route = navBackStack<GameRoute>(GameRoute.Menu, 8)
var display = navDisplay()
display.sync(route)
```

continues to work during migration. It receives the compatibility single-pane
model and can adopt richer behavior explicitly.

## 42. Implementation roadmap and missing gaps

### Phase A — stack identity and errors

- store `NavStackItem<K>` and allocate stable IDs;
- add `NavChange` and transaction commit;
- add typed stack failures while preserving compatibility methods;
- cover duplicate equal routes and rollback in tests.

### Phase B — resolver entries and owners

- replace exact-value-only resolution with resolver/pattern providers;
- add metadata and `NavEntryContext`;
- create one reactive owner per entry ID;
- implement state/result/focus decorators and deterministic cleanup;
- expose owner revisions to `EcsObserver`.

### Phase C — real NavDisplay and single-pane scenes

- make display resolve decorated entries;
- implement scene state, strategy ordering, and fallback;
- compose one visible entry under a retained keyed UI root;
- activate/suspend owners correctly;
- provide headless display tests.

### Phase D — transitions and back

- implement immutable scene transition snapshots;
- add push/pop/replace transition precedence;
- integrate keyboard/controller/platform back dispatcher;
- add predictive back phases and cancellation;
- integrate reduced-motion policy and profiler spans.

### Phase E — dialogs and overlays

- implement ordered overlay strategy evaluation;
- add engine-rendered dialog, sheet, popover, and full-screen overlay scenes;
- block underlying input and manage focus trap/restore;
- add typed dismissal reasons and dialog results;
- provide optional native-dialog adapter with identical semantics.

### Phase F — adaptive and nested navigation

- implement list-detail and supporting-pane strategies;
- add scene decorators for bars/rails/shared chrome;
- implement parent/child display ownership and back dispatch;
- add multiple top-level stack helpers and policies;
- validate unique entry rendering during layout changes.

### Phase G — persistence and links

- define route codecs and stack/owner snapshot schema;
- serialize `preserve` entry state and migration metadata;
- implement typed deep-link stack plans;
- add browser history provider;
- add malformed/untrusted input limits.

### Phase H — tooling and polish

- add navigation inspector and profiler integration;
- add AZLS route/provider/decorator symbol links and exhaustiveness diagnostics;
- add shared-element projections and transition previews;
- update game/tool/media templates;
- publish conformance tests for external scene strategies and decorators.

The immediate missing gap is not another convenience method on the current
stack. It is stable per-occurrence identity and owner lifetime; scenes,
dialogs, transitions, restoration, and correct nested behavior all depend on
that foundation.

## 43. Acceptance criteria

The complete navigation implementation is accepted when:

1. Applications own typed stacks and no hidden global controller is required.
2. Equal route values can appear more than once with independent owner state.
3. Parameterized route variants resolve without registering every value.
4. A stack transaction publishes once or rolls back completely.
5. Popped owners dispose effects, tasks, results, focus, and providers once.
6. `NavDisplay` renders a single-pane fallback and custom ordered scenes.
7. A wide list-detail scene can become single-pane without stack mutation or
   entry-state loss.
8. Dialogs are overlay entries with back, outside press, Escape, focus trap,
   dismissal reason, result, and nested-flow behavior.
9. Every entry is composed by at most one scene per committed frame.
10. Forward, pop, replace, predictive, interrupted, shared, and reduced-motion
    transitions obey documented precedence.
11. Predictive-back cancellation leaves stack and owners unchanged; completion
    commits exactly once.
12. Nested displays consume back deepest-first and are destroyed with parents.
13. Multiple top-level histories retain state and follow explicit back policy.
14. Snapshots restore typed routes and `preserve` state transactionally.
15. Deep links create validated stack plans without granting authority.
16. Typed results cannot reach stale or unrelated entry instances.
17. Focus, semantics, and modal input behavior are correct in headless tests.
18. Navigation works through ECS UI, GPU/native UI, DOM, and headless adapters
    without changing core state semantics.
19. The profiler identifies stack transaction, strategy, transition, and stale
    completion costs by stable identity.
20. AZLS navigation and references are symbol-based, never name-similarity-based.

## 44. Resolved design decisions

1. The application owns navigation state; `NavDisplay` is an observer/renderer.
2. Route values are typed keys, and stack occurrences have separate stable IDs.
3. The root cannot be popped; closing a display destroys its owner.
4. Provider resolution is by route symbol/pattern, not exact-value registration
   alone and never string similarity.
5. Metadata is typed.
6. Entry owner lifecycle is separate from transition presence.
7. Scene strategies are ordered, with single-pane fallback.
8. Dialogs and sheets are overlay scenes selected before base scenes.
9. Scene decorators do not automatically wrap overlays.
10. Nested navigation uses parent owner identity and hierarchical back dispatch.
11. Adaptive layout changes scene selection, not stack history.
12. Results are typed and addressed by entry ID.
13. Preservation is explicit through route codecs and `preserve` state.
14. Platform providers may change rendering but not navigation semantics.
15. UI transition time is independent of paused gameplay simulation time.

## 45. Open implementation choices

These choices do not alter the model and can be benchmarked during execution:

1. Whether default stack storage grows outside deterministic mode or always
   requires an explicit capacity.
2. Whether compatibility methods retain asserts or become failable in the next
   breaking engine release.
3. The exact entry-provider DSL syntax after resolver semantics compile.
4. Whether custom typed metadata uses nominal spec objects, generated metadata
   slots, or both.
5. Whether entry transition snapshots store render commands or provider-neutral
   retained UI projections.
6. Which native platforms initially use native modal windows versus engine
   overlay windows.
7. The first persistent snapshot encoding and migration registry format.
8. Whether browser history includes nested stack changes by default.
9. The default multiple-stack back policy per game, desktop, and mobile
   templates.
10. Whether shared-element support ships with Phase D or after adaptive scenes.

## 46. Principles

1. Navigation is typed application state.
2. Keys describe content; entry IDs own content occurrences.
3. Back-stack truth changes transactionally.
4. Screens are ordinary reactive content, not controller-owned objects.
5. Entries own state; scenes own presentation.
6. Adaptive layout does not rewrite history.
7. Overlays preserve the scene beneath them and own dismissal semantics.
8. Back is hierarchical, progressive when available, and generation-checked.
9. Popped means destroyed even when pixels are still finishing an exit motion.
10. State preservation is explicit and serializable.
11. Focus, accessibility, input, and cleanup are navigation correctness.
12. Symbols and stable IDs decide identity; names are labels only.
13. Core behavior is provider-neutral and headlessly testable.
14. Tooling must explain which stack, owner, strategy, and transition produced
    what the user sees.

## 47. References

The design was compared against the current official Android Navigation 3
documentation, especially:

- [Navigation 3 overview](https://developer.android.com/guide/navigation/navigation-3)
- [Navigation 3 basics](https://developer.android.com/guide/navigation/navigation-3/basics)
- [Navigation entries and decorators](https://developer.android.com/guide/navigation/navigation-3/naventrydecorators)
- [Scenes and scene strategies](https://developer.android.com/guide/navigation/navigation-3/scenes)
- [Scene decorators](https://developer.android.com/guide/navigation/navigation-3/scenes/scene-decorators)
- [Destination transitions](https://developer.android.com/guide/navigation/navigation-3/animate-destinations)
- [Saving navigation state](https://developer.android.com/guide/navigation/navigation-3/save-state)
- [Dialog scene strategy](https://developer.android.com/reference/kotlin/androidx/navigation3/scene/DialogSceneStrategy)
- [Overlay scenes](https://developer.android.com/reference/kotlin/androidx/navigation3/scene/OverlayScene)
- [Multiple back stacks recipe](https://developer.android.com/guide/navigation/navigation-3/recipes/multiple-backstacks)

Azora adopts the architectural lessons while defining its own API, ownership,
serialization, platform, and runtime behavior.
