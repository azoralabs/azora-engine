# Remaining tasks

Written at the end of the session that landed `@query`, world-owned storages,
resources, provided spec methods, associated types, `for … in` over iterators,
and real `inline` callables. Everything below is what was asked for and is *not*
done. Ordered so that each item unblocks the ones under it.

Baseline, re-measured 2026-08-15: **93 failed** (was 94 at `e8ef407`; the
spec-inheritance fix below took one). Compare the failing *set*, not the count -
the total drifts between runs at identical source.

`templates/ui-compose` now **builds natively and runs** (`./build.sh build`,
then `.azora-build/ui-compose`). Getting there took five fixes, all of them
pre-existing breakage rather than anything §1 introduced:

1. `World` declared `resources` **twice** - `Array<Bool>` at index 6 and
   `MutableList<Any>` at index 14 - so every `world.resources` silently bound to
   the first, with its type and its offset. The per-entity flag is now
   `resourceMarks`, and `SymbolCollector` refuses a pack that declares a name
   twice, which is what let this sit.
2. `IrGenerator.registerName` mangled a shadowing name to `__<name><n>`, which
   for a name already starting `__` put a `__` mid-symbol; canonicalization
   collapsed it back out, so a lambda's inherited contextual receiver was
   declared as `____ctx0_1_70` and read as `___ctx0_1_70` - an undefined global.
3. `__isolated` (the copy a `Copy` value gets, and a derived `clone`) had no
   LLVM lowering at all. It now allocates and copies one level deep.
4. `panic` had no LLVM lowering: `__panic` was called and never defined.
5. A spec's dispatch table carried only its *own* signatures, so
   `MutableList<T> : List<T>` had no `size` and no indexing - ten "not lowered"
   sites in the engine. Tables are now built across `specAndAncestors`.

6. The iterator walk behind `for … in` was never bound to the functions that
   implement it, so every query loop was dead in a native build. See §3, which
   is done.

`templates/ui-compose` now compiles with **zero** `not lowered` sites.

---

## 1. Computed decorator field defaults, with `seal` - DONE

The declaration is back in `packages/azora-core/src/core.az` and the template
type-checks with it:

```azora
fin interval: SystemInterval = when phase {
    .Startup -> seal .Once
    else -> .EveryFrame
}
```

What landed, against the four parts this was broken into:

1. **Expression forms of `when` and `if`/`else`** already existed - the note
   that started this was wrong. `Parser.parseWhenExpr` desugars a `when`
   expression to a chain of `Expr.IfExpr`, and `parseIfExpr` already required
   its `else`. What was actually missing was the *type* the arms are read in,
   which the desugaring drops: a pattern becomes an equality against the
   scrutinee, and nothing told the `.Name` on the far side what it belonged to.
   `TypeResolver.seedExpectedValue` now carries an expected type through the
   forms that pass a value along (if-expression arms, `catch`, `??`,
   parentheses), and an `==`/`!=` states the type of whichever side is a bare
   `.Name`. Statement `when` seeds its patterns from the scrutinee, and a
   `.Name` pattern now counts towards exhaustiveness - it did not before, so an
   exhaustive `when` written the short way was called non-exhaustive.
2. **`seal` as a prefix on a branch value** - `seal .Once`, an `Expr.Seal`
   marker, contextual so a binding may still be named `seal`. Rejected anywhere
   but an `annot` field's default, where it is the only thing it could govern.
3. **The default folds at application.** `DecoratorMetadata.fieldValue` binds
   the earlier fields to what the application passed and takes the branch they
   select; `chosenDefault` decides equality and `||`/`&&` chains over constants
   and leaves anything else undecided rather than guessing.
4. **The seal is enforced** in `DecoratorResolver.validateApplication`, which is
   where the arguments are already known - and it is the arguments that decide
   which branch's seal applies.

Also landed on the way: a pack field default may now be written in terms of the
fields before it and is folded *per construction*
(`IrGenerator.loweredFieldValues`), where before it failed to lower at all.
One wart: a supplied argument that a later default reads is emitted again where
the default reads it, so an argument with side effects would run once per
reader.

Left alone: `runner.az`'s `dispatch` still short-circuits with
`phase == SystemPhase.Startup || ui.due(…)`. That guard predates the seal and is
now redundant - `annotMeta<F>.interval` folds to `.Once` for a startup system -
but removing it is a behaviour change worth making deliberately.

## 2. Filters must actually filter - DONE

Verified, and now guarded. `tests/query_filters.az` builds a world of four
entities and checks `with`, `without` and a nested `with … without …` against
counts that have one right answer, then walks one of them. `tests/run.sh` runs
every test **twice** - interpreted and native - and fails if either disagrees or
if the generated IR contains a single `not lowered` site.

That double run is the point: the query walk was dead in native builds for a
long time while `azora run` was perfectly happy (see §3). One backend proves
nothing.

The crash this item recorded (`List index out of bounds`) was the duplicate
`resources` field and the missing `MutableList` dispatch, both fixed.

## 3. The iterator walk was never bound to its functions - DONE

This was what stopped the shapes rendering, and the cause was not
specialization at all. `for row in query` and `loop query { … }` are lowered in
`IrGenerator`, and they *synthesized* their three steps:

```kotlin
IrStmt.ExprStmt(IrExpr.MethodCall(iterable, "reset", …))
IrExpr.MethodCall(iterable, "hasNext", …)
IrExpr.MethodCall(iterable, "next", …)
```

Nothing downstream resolves a synthesized node, so those stayed unresolved
`MethodCall`s all the way to the backend. The interpreter looks a method up by
name at runtime and so was unaffected - which is exactly why this never showed
up in the test suite. LLVM has no such lookup: it emitted
`; method .hasNext - not lowered` and a default value, so the condition was
always false, the loop never ran, and every query silently yielded nothing.

`IrGenerator.iteratorCall` now binds each step through
`table.lookupMethod`, falling back to the old unresolved form when the receiver
has no such method. The specialized `__QueryOf_UiTag_UiPaint_hasNext` and its
siblings were being emitted correctly the whole time; only the call sites were
adrift.

Two more fixed alongside it:

- `hasNext`/`next` are now `prop` on `QueryOf`, `QueryWith` and `QueryWithout`,
  matching what `spec Iterator` declares. They were `func` against a `prop`
  spec - a latent mismatch. `templates/game-ecs` call sites became
  `query.hasNext` / `query.next`.
- `Array.remove(index)` had no LLVM lowering (`freeIds.remove(id)` in
  `World::spawn`). It now shifts down and shrinks. Note it removes *by index*,
  not by value - that is what the interpreter does, so the backends now agree;
  the interpreter also threw a raw JVM `IndexOutOfBoundsException` on an
  out-of-range index and now removes nothing, as the native path does.

`templates/ui-compose` compiles with **zero** `not lowered` sites.

## 4. Fetch projection - DONE

A query hands back the components, borrowed. `&` is a shared borrow, `!` an
exclusive one, and the row is a `std::Tuple` with the **entity first**:

```azora
@System(phase: .Update, interval: .Every(5.seconds))
react func changeColorEach5Secs(shapes: @query [UiTag&, UiPaint!]) {
    shapes.unpack { entity, tag, paint ->
        if entity.isValid && tag.group == swatchGroup {
            paint.r = …
        }
    }
}
```

No `world` parameter, no `storageOf`, no `storageInsert`. Assigning through a
`!` term *is* the store: an aggregate is a reference in both backends, so the
fetched component is the stored one.

Four ways to take a row apart, all covered by `tests/query_projection.az`,
which runs interpreted and native:

- `for row in q { … }` - `row.0` is the entity, components follow.
- `for [entity, tag, paint] in q { … }` - the row taken apart in the header,
  each name bound to the element at its position.
- `q.forEach { row -> … }` - the same row, handed over whole.
- `q.unpack { entity, tag, paint -> … }` - the row spread across parameters.
  Separate from `forEach` because the two differ only in the block's arity, and
  a call is not resolved on that.

### Two things to know before touching this

`forEach` is written out on `impl QueryOf<...T>` rather than inherited from
`spec Iterator`. A **provided** spec member's copy keeps the spec's `Item`
unspecialized in a callable parameter, so the block is offered a bare `Tuple`
and the concrete row does not match it. `SpecDefaults` still has that hole for
every other provided member; it resisted a long series of isolation attempts
(variadic and concrete `Item`, several impls with differing `Item`s, the stdlib
spec, `react` callers, receiver in parameter position) and only shows up in the
engine.

Borrows do not parse in a call's explicit type arguments -
`std::tupleOf<Ent&, Ent!>(…)` fails. The engine writes `<Entity, ...T>`, so it
is not on this path.

### Still open here

- `Or<…>`, `Option<&T>`, `AnyOf<…>`, `Entity` as an explicit fetch term.
- **Change detection.** `Added`/`Changed`/`Removed` are marker packs that nothing
  reads. `Storage<T>` already carries `added` and `changed` arrays plus a
  `revision`; there is no removal log.
- **Access conflicts** (`&` vs `!`) - what makes parallel scheduling safe, and
  what the borrow markers exist to feed.

## 5. Storage ownership

The world holds a per-frame **copy**: `Composition.publish()` registers the
composition's storages before systems run, `Composition.adopt()` takes back what
they wrote. The composition is still the owner. Making the world the real owner
means moving `azora-ui`'s sixteen `Storage<T>` fields onto it, and the registry
holds values, so every mutation is get/modify/put (or the registry gains
reference semantics).

## 6. Systems that still take `Ui!` - DONE

Every system in `templates/ui-compose` now declares what it touches, Bevy-style:

```azora
@System(phase: .Update)
react func ui(
    world: World&
    input: Res<UiInput>
    viewport: Res<Viewport>
) {
    @compose world { Column(…) }
}
```

Three pieces made that possible:

- **`Viewport`** - a resource carrying the drawable size, so a system laying out
  against the window needs nothing of `Ui` but its dimensions.
- **`Scope` as a resource.** A `Scope` holds an exclusive borrow of the
  composition, so putting one in the world shares the composition rather than
  copying it. `composeIn(world)` reads it back.
- **`@compose world { … }`** - a fragment macro, `macro @compose $w => inline
  "with composeIn($w)"`. Fragment macros took no argument before; they now take
  one hole, and are spliced in statement position as well as in expressions.

Still to do here: the user wants resources and queries to be reachable **only**
as parameters, never fetched inside a body, so a future scheduler can see what a
system touches and run systems in parallel. Today nothing stops
`resource<T>(world)` mid-body. That needs a general mechanism - the compiler must
not know engine names - so probably a marker the engine puts on those functions
and a check that refuses them inside an annotated system.

## 7. `Parent<>` / `Child<>` relationships

Never started.

## 8. `main.az` at ~3 lines

The original goal. Blocked by 5 and 6.

---

## Smaller items

- **`T.typeName` fallback.** `TypeResolver.typeMetaMember` reads `impl Type` from
  the program, but stdlib injection is reference-driven and never pulls it in, so
  a one-line fallback names `typeName`. Fix the injector, delete the fallback.
- **`inline func` in statement position.** `registerStorage<T>(world, store)`
  only folds `T.typeName` when its result is *bound* (`fin ok = …`); called as a
  bare statement the body is not folded and it fails with `undefined variable
  'T'`. That is why it returns a `Bool`. The CTFE inline path should fold calls
  whose value is discarded.
- **`ReflectedField.value: Any`** should be `ActualType`, the same erasure that
  was fixed for `ReflectedParam.defaultValue`. Left alone to avoid disturbing the
  tuple/serializer paths in the same pass.
- **`hasNext`/`next` as `prop`** rather than `func` - reads better (`if q.hasNext`)
  and the spec parser already accepts `prop` members. Changing them touches every
  implementor at once.
- **`bridge prop name[Receiver&]: T`** - a member declared on a type from outside
  it. Implemented and parsing; nothing uses it. Keep or remove.
- **`forEach` on a shared borrow.** `forEach[self: Self!]` needs `Self!` because
  walking mutates the cursor. A `Self&` form needs the collection separated from
  its cursor (Rust's `IntoIterator` split); until then nested iteration over one
  query resets the outer walk.
- **8 stale templates** that do not compile (pre-existing: removed `{ self& -> }`
  receivers, `@Query` tuples, tuple literals, old macro syntax).
- **76 failing compiler tests** (pre-existing: stale sources, harness stdlib
  injection).
