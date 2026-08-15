# Reactive ECS UI - Implementation TODO

> Status: **the substrate exists; the authored surface is starting to.** Keyed
> composition, reconciliation and disposal work and are verified, and the
> starter's two lifetime lines - `effect mustClose == true { … }` and
> `azora::engine::exit()` - now compile and close a real window. Builders nest
> as blocks and key themselves by position, modifiers drive layout and paint,
> and `templates/ui-compose` runs. `@query`, `@System` scheduling, `@compose`
> and relationships do not exist. This is the ordered path from here to the
> starter in `REACTIVE_ECS_UI.MD` compiling and running.
>
> The demo is the thing to look at: it is the authored surface as far as it
> goes.

The target is the starter, unchanged:

```azora
@System(.Startup)
react func mainMenu(world: World&) {
    remember var mustClose = false
    effect mustClose == true { azora::engine::exit() }
    @compose world {
        column(modifier: .fillMaxSize()) {
            button { text("Play") }
            button(onClick: [&mustClose] { mustClose = true }) { text("Quit") }
        }
    }
}

@System(.Update)
func changeAllButtonText(query: @query [Button!, Child<Text!>]) {
    for e in query { e.1.text = "--------" }
}
```

---

## 1. Where the line is today

Measured, not assumed. Each row was run.

| Construct | State |
|---|---|
| `react func f(world: World&)` | ✅ works |
| `remember var` / `retain` / `preserve` | ✅ works, native and interpreted |
| `lazy fin` derived values | ✅ works, both backends |
| named arguments + trailing lambda | ✅ `column(spacing: 8.0) { … }` |
| nested trailing-lambda builders | ✅ `column { button { text(…) } }` nests correctly |
| capture-list lambda, **trailing** | ✅ `button("Quit") [; v.!] { v = true }` mutates through |
| `effect <expr> { }` | ✅ rising edge, both backends (§3.3 of the reactive DIP) |
| scoped builders `it.column { it.button(…) }` | ✅ same tree as flat, identity preserved |
| positional keys (`button#0`), `key:` override | ✅ both backends |
| named args + defaults + trailing block | ✅ fixed; `ArgumentBindingTest` |
| `@System(.Startup)` | 🟨 annot exists in `engine.core`; nothing discovers or schedules it |
| capture-list lambda, **argument position** | ❌ `onClick: [&v] { … }` does not parse |
| `@compose world { }` | ❌ does not exist |
| `@query [T!, U&]` as a parameter | ❌ does not exist |
| `Modifier` / `.fillMaxSize()` | ✅ ordered chain, drives layout and paint |
| `Arrangement` / `Alignment` | ✅ six arrangements, three alignments |
| weights, fills, fixed sizes | ✅ honoured by `arrange` |
| captures across nested blocks | ✅ fixed; `NestedCaptureTest` |
| `Child<T>` relationship | ❌ does not exist (a flat `UiChild` does) |
| tuple literal `(a, b)` and `e.1` | ❌ literals rejected; `std::tupleOf` required |
| `azora::engine::exit()` | ✅ closes a real window, native |

### What is already built and verified

`engine.ui.node` - 12 components (`UiKey`, `UiChild`, `UiOrder`, `UiText`,
`UiButton`, `UiAction`, `UiRect`, `UiPaint`, `UiOwned`, `UiLayout`, `UiScroll`,
`UiTag`).

`engine.ui.compose` - `beginComposition` / `claim` / `commitComposition`, which
is §9.2's expansion written as functions. Verified:

```text
first pass: 4 nodes
recompose:  4 nodes, play kept identity, quit label updated in place
drop one:   3 nodes, settings removed, play unchanged
```

`engine.ui.systems` - `arrange`, `hit`, `scrollBy`, and `tintGroup` (the query
of §7 written out as the macro would expand it).

`engine.ui.paint` - the only module that touches `App`.

---

## 2. Order of work

Each step is independently verifiable and leaves the tree building. Nothing
later depends on a step that has not landed.

### Step 0 - a running baseline ✅

The demo at `templates/ui-compose` builds and links but exits at launch:
`frame()` takes its window-visibility branch. A minimal engine app in the same
directory runs, so the fault is in the demo, not the environment.

*Acceptance*: `templates/ui-compose` stays up and draws. **Done** - it compiles,
links, and is still running when a five-second watchdog fires. It is now written
in the authored surface: modifiers, arrangements, alignments and nested blocks,
with no `pass`/`parent`/`key` threading.

Two compiler bugs stood between the demo and a native build, both about captures
crossing more than one closure boundary - which is what a builder DSL does on
every line:

- **The resolver recorded `[; &]` on the innermost frame only.** `checkCapture`
  walked the frame stack inwards and returned at the first match, so an outer
  closure never learned it had to take a binding its nested block read
- **The LLVM backend's free-variable scan skipped nested lambda bodies**
  (`is IrExpr.Lambda -> {}`), so the outer environment was built without them

Either alone leaves the inner environment naming a binding nothing supplied.
Natively that lowered to a read of an undefined module global - a link error
(`use of undefined value '@height'`) when the name survived, and *silently
nothing* when it did not. The interpreter resolves names dynamically and was
unaffected, which is why it only appeared in a native build. Pinned by
`NestedCaptureTest` (5 tests).

Two smaller ones, both mine: `Array::fill` does not carry its element type into
a `var`, so the local needs an annotation or every write fails; and a `Modifier`
must be passed `Modifier&`, since it is not `Copy` and a builder only reads it.

### Step 1 - `effect cond { }` rising edge ✅

The gap the starter's own comment names. Currently the condition is stored as a
*dependency* and the body runs on every owner invocation - measured firing at
steps 0 and 1 while the condition was false.

Semantics from §11.1: evaluate in the owner, record the condition's reads, run
the body when it goes false→true, do not repeat while true, re-arm when it goes
false, dispose with the owner.

*Touches*: `Parser.parseEffect` (distinguish a bare identifier - a dependency -
from any other expression - a condition), `Stmt.Effect`, `IrStmt.Effect`,
`IrGenerator`, `IrInterpreter.runReactiveEffect`, then LLVM.

*Acceptance*: the gate test fires exactly once, on the transition, on both
backends. **Done.** A bare name stays a dependency; any other unbracketed
expression is a condition. The edge is stored per owner - keyed like a
`remember` cell in the interpreter, and as a module global in LLVM - because a
fresh effect record is built on every invocation and an edge kept there would
reset each time. Covered by `ConditionalEffectTest` (5 tests); interpreter and
native agree. Documented as `REACTIVE_DIP.MD` §3.3.

### Step 2 - `azora::engine::exit()` ✅

The starter's effect body. A function that sets the app's closing flag, so an
effect can end the program without reaching into `App`.

*Acceptance*: `effect mustClose == true { exit() }` closes the window. **Done.**
Measured on a real window - the flag is set by an effect, the frame loop stops,
and `shutdown()` still runs:

```text
effect fired at frame 61
frame loop ended after 62 frames
clean shutdown
```

*Where the flag lives.* Not in Azora, because Azora has no mutable global to put
it in: a top-level `var` is rejected as unsafe to share, and `fin` is *deeply*
immutable, so a `fin` array's contents cannot stand in for one either. Both are
deliberate rules, so the bit lives in `az_ffi.c` as an atomic - which is exactly
that file's stated remit, "what a C ABI cannot express by itself". `engine.io`
declares the two foreign functions; `engine.core` wraps them as
`azora::engine::exit()` / `exitRequested()`; `Window.frame()` stops on either
its own `closing` flag or the application-wide request.

New edges: `engine.core → engine.io` and `engine.platform → engine.core`. No
cycle is possible - `engine.io` imports only std. The whole engine tree
type-checks.

*Naming tension, unresolved.* The starter spells this `azora::engine::exit()`
and that is what shipped, since the target is the starter unchanged. But every
other engine realm is `engine::*` (`engine::input`, `engine::audio`,
`engine::physics`), so `azora::engine` is a second root for the same thing.
Either the proposal or the engine should give way before more lands under it.
Not aliased - two names for one function would be worse than one wrong one.

### Step 3 - composition context for builders ✅

Nested trailing-lambda builders already work; what is missing is threading the
`Composition` into the block so `column { button { … } }` can claim nodes.
Either an ambient current-composition or a captured context.

*Acceptance*: builds the same entity tree the flat calls build today, and
recomposes with identity preserved. **Done**, on both backends:

```text
scoped pass 1: nodes=3 removed=0
flat   pass 1: nodes=3            ← same tree
keys resolve: column=true play=true quit=true
scoped pass 2: nodes=3 removed=0
identity kept: column=true play=true quit=true
label updated in place: Exit
scoped pass 3: nodes=2 removed=1
survivor kept identity: true
```

**Captured context, not ambient.** An ambient current-composition is not
expressible: it needs a mutable global, and Azora has none (step 2). So a
`Scope` - the pass plus the parent to build under - is passed to each block as
the lambda's implicit `it`:

```azora
compose(pass) {
    it.column(spacing: 8.0) {
        it.button("Play")
        it.button("Quit")
    }
}
```

That `it.` is the whole remaining distance to the starter, and step 4's macro is
now a purely syntactic rewrite - which is the property §9.2 asks for.

**Keys are positional.** `it.button("Play")` is keyed `button#0` by its position
under its parent, counted by a `UiCursor` component on the parent (the root's
count lives on the pass, having no entity). The role is part of the key so a
block that changes shape rebuilds loudly instead of reusing a column's entity
for a button. An explicit `key:` overrides, and must be used where a list can
reorder - positional identity follows the position, not the item.

**Four compiler defects were in the way**, all fixed and pinned by
`ArgumentBindingTest` (6 tests):

- **A named argument slid into an earlier gap.** `f(b: 5)` against
  `f(a: Int = 1, b: Int = 2)` ran as `f(5, 2)` - it produced `52` where `15` was
  written. Nothing failed; it silently computed with the wrong arguments. The
  named-argument slots were built correctly and then compacted, dropping the
  gaps the defaults were meant to fill
- **Methods ignored defaults entirely** - `defaults` and `paramNames` were never
  recorded for `impl` methods, so every argument had to be positional
- **A trailing block bound to the leftmost free parameter**, not the last one,
  so `k { … }` filled `a` and then reported `body` missing
- **A method's own type parameters were not in scope** - only the *type's* were,
  so `func each<R>[self: Self&]` resolved `R` as an unknown named type

Documented as `FUNCTIONS_DIP.MD` §1.3, "How arguments reach parameters".

### Step 4 - `@compose world { }` ⬜

Sugar over step 3. A macro that wraps the body in
`beginComposition` / `commitComposition` and supplies the context. Because step
3 already works, the macro cannot mean anything the functions cannot do.

Concretely, now that step 3 has landed, the macro's whole job is to drop the
`it.` - rewrite a bare `column(…) { … }` inside the block to `it.column(…) { … }`
- and to supply `compose(pass) { … }` around it.

*Acceptance*: the starter's `@compose` block compiles and produces the step-3
tree.

### Step 5 - `Modifier` bundles ✅ (mostly)

Immutable ordered bundles (§12.1): `.fillMaxSize()`, `.padding()`,
`.verticalArrangement()`, `.horizontalAlignment()`. Modifiers produce layout,
paint, input, focus and semantics metadata - they never call a renderer.

*Acceptance*: `column(modifier: …)` arranges as described, and modifier order is
observable. **Done** for `fillMaxWidth/Height/Size`, `width`, `height`, `size`,
`padding`, `background` and `weight`, applied in order into `UiSize`,
`UiPadding` and `UiPaint`, with `arrange` distributing weights and leftover
space and aligning across the axis.

*Deviation*: Compose writes `Modifier.fillMaxSize()` - an associated function on
the type. Azora has no associated functions on a pack (`Mod::none()` and
`Mod.none()` both fail to resolve), so the chain root is the free function
`modifier()`. If associated functions land, this should become `Modifier`.

*Not yet*: input and focus modifiers (`clickable`, `focusable`) - those belong
with step 12's routing rather than with layout.

### Step 6 - capture lists in argument position ⬜

`onClick: [&mustClose] { mustClose = true }` does not parse; only the trailing
form does. Needed for the starter's `button(onClick:)`.

*Touches*: the parser's argument-position lambda path.

*Acceptance*: the starter's `button(onClick:)` line parses and mutates.

### Step 7 - `Child<T>` and tree invariants ⬜

Replace the flat `UiChild` with the relationship of §10.3: one parent per node,
no cycles, sibling keys unique within a parent, children disposed before
parents.

*Acceptance*: a cycle and a duplicate sibling key are both diagnosed.

### Step 8 - query rows as tuples ⬜

Blocked on tuples: literals are rejected and `std::Tuple` is recorded as
unconstructible in `VARIADICS_DIP.MD` §7. Fix that first, then a `Query` cursor
yielding rows so `e.1.text` works.

*Acceptance*: `for e in query { e.1.text = "…" }` compiles and mutates the
component through the row.

### Step 9 - `@query [T!, U&] @with X @without Y` ⬜

The parameter macro of §7.1, expanding to a typed query plan and access
descriptor. `T!` contributes `Write<T>`, `T&` contributes `Read<T>`.

*Acceptance*: the starter's `changeAllButtonText` signature compiles, and a
borrow conflict is diagnosed.

### Step 10 - `@System` discovery, phases and ordering ⬜

`Startup → PreUpdate → Update → PostUpdate → FixedUpdate → Render → Last`, with
`order:` and `runAfter:`, resolved before execution. Access sets from step 9
decide what may run in parallel.

*Acceptance*: `@System(.Startup) react func mainMenu` runs once at startup and
`@System(.Update)` runs every frame, in declared order.

### Step 11 - measure/arrange layout ⬜

The two-pass layout of §12.2 replacing the single arrange pass: `measure
(constraints) -> desired size`, then `arrange(rectangle) -> child rectangles`,
with logical units and a diagnostic for non-converging measurement.

### Step 12 - input routing, focus, semantics ⬜

§13: routed input rather than a flat hit test, focus order, and semantics that a
provider does not infer from component presence.

### Step 13 - render extraction ⬜

§15: an immutable render tree between the UI world and the provider, so drawing
never reads live components.

---

## 3. Defects in the way

Found while building the substrate. Each blocks or distorts a step above.

- ⬜ **An `impl` does not cross a transitive import.** A member reaches a module
  that imports its type directly, not one that sees it only through another
  module. Forced `liveEntity()` and free `spawnEntity`/`despawnEntity` instead
  of `Entity.isValid()` and `World.spawn()`. Distorts every engine API
- ⬜ **`std::Tuple` cannot be constructed**, and tuple literals are rejected -
  blocks step 8
- ⬜ **Per-call-site reactive owners do not exist.** `remember` is one slot per
  callable: `slot() slot() slot()` yields `1 2 3`, one counter, on both
  backends (`REACTIVE_DIP.MD` §7.2). Until keyed owners land, state cannot live
  inside a reusable widget - it belongs to the composition root
- ⬜ **`MutableList` is not lowered by the LLVM backend**, so a native UI must
  use `Array`-backed storage
- ⬜ **A field generator accepts duplicate field names silently.** `inline for Ty
  in ...T { value: Ty }` declares `value` on every iteration: the specialized
  pack still takes one argument per type, but only the *last* field is reachable
  by name and every earlier one is unreadable. `Single<Int, String>(1, 42, "x")`
  compiles and `.value` reads `"x"`. The documented form splices the name -
  `inline for Ty in ...T with index { inline "value$index: $Ty" }` - which is
  what `with index` and the string fragment exist for. `ecs.az` is fixed;
  the compiler should reject the collision rather than accept it
- ⬜ **`(...T).size` vs `(...T).length`** - `ecs.az` writes the first,
  `VARIADICS_DIP.MD` §2 the second. One of them is wrong
- ✅ **`@with` / `@without` were a placeholder that lied.** Declared as
  `macro $Base @with $Filter => $Base`, discarding the filter, so both spellings
  were the same rewrite and `@without X` meant "no filter" - the opposite of its
  documentation. Also uninvocable in either position. Removed; the runtime
  narrowing (`queryWith` / `queryWithout`) was always the real mechanism, and the
  typed surface waits for the query plan (step 9)
- ⬜ **`std::arrayOf` is not resolved in a top-level initializer.** `fin xs =
  std::arrayOf(false)` at module level fails with `Undefined function:
  __std_arrayOf`; the identical call inside a function body works. Narrowed and
  *not* explained: user-defined generic, variadic, and generic-variadic
  functions all work at top level, as do other std functions with bodies
  (`std::abs`) and `std::Array::fill`. Specific to `arrayOf`
- ⬜ **Test count drifts 96 → 97** between incremental and `--rerun-tasks` runs;
  the sampled failures are pre-existing stale goldens, but the difference is
  unexplained

## 4. Deliberately not now

Navigation scopes (§14), transactions and replay (§16), accessibility beyond
semantics components, provider affinity, and parallel scheduling. All are in the
proposal; none block the starter compiling and running.
