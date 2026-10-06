# Native Engine migration — 2026-10-04

Updated 2026-10-05. This records execution evidence and remaining work. F06 stays
open until the shipping game template and its bounded native execution pass.

## Implemented

- Applied the saved migration to real package and template sources: qualified
  receivers, imports, reflection, numeric widths, casts and default constructors.
- Repaired the real generic vector arithmetic and matrix construction,
  multiplication and projection used by the native camera.
- Added `GameSystem.shutdown`, idempotent mesh release, and `Engine.runFrames`.
  The bounded and unbounded loops use the same host, renderer and shutdown.
- Transferred owned App window/GPU members explicitly. Host shutdown releases
  native retained objects, closes the window and frees input/render buffers.
- Storage reads return borrows; clone reads require `Clone`. Replacement and
  removal destroy owned components, and despawn removes all registered rows.
  Entity insertion/getter/command buffering use independent scalar snapshots.
- Added real contextual `Column`, `Row`, `ScrollColumn`, `Shape`, `Button` and
  `Text` constructors returning `Entity`, with synchronous reactive child blocks.
  Ordinary `Text` construction outside a composition still creates a component.
- Added keyed retained composition, dependency-stamp skipping, explicit
  invalidation, postorder unclaimed-subtree removal and owner disposal.
- Fixed startup description invalidation so sibling descriptions rebuild
  together before the shared owner is committed.
- Native build/qualification accepts `AZORA_COMPILER_BIN`; clang selection
  accepts `AZORA_CLANG` and defaults to Apple clang on macOS.

## Reproducible native qualification

From the Engine checkout:

```sh
tests/qualify-native.sh headless
tests/qualify-native.sh foundation
tests/qualify-native.sh game
```

The qualification script defaults to the current native compiler checkout at
`../azora-lang/compiler/build/bin/macosArm64/debugExecutable/azora.kexe`.
An explicit `AZORA_COMPILER_BIN` overrides it. It rebuilds the real runtime,
compiles actual projects, links their LLVM and requires exact success output.

The following gates currently pass with the native compiler:

- `headless-ecs`: scalar insert/replace/remove, the same Entity across independent
  Int/String stores, an independent indexed Entity snapshot, stale-handle
  rejection, slot reuse and generation change. Output: `headless ecs passed`.
- `scheduled-ecs`: reflected `@System` discovery, dependency order, Update and
  Render phases, and fixed timestep accumulation/consumption. Output:
  `scheduled ecs passed`.

`foundation` also requires `owned-ecs` and `constructor-ui`, and therefore stays
failing until all three executables pass. `constructor-ui` exercises real nested
constructor descriptions, keyed identity, updates, dynamic subtree removal,
layout, skipped recomposition, explicit invalidation and disposal.

`game` first builds the unchanged shipping game template, then stages its
complete source with only the entry point bounded to three frames. It requires
successful host initialization, three rendered frames and completed shutdown.
There are no unavailable-target skips.

## 2026-10-06 update

- `qualify-native.sh headless` and `qualify-native.sh game` pass with the native
  compiler: the unchanged shipping game template builds and runs its bounded
  frames. The generic `T: Clone` erased-pointer blocker is repaired in the
  compiler (Clone witness), as are by-value aliasing and exclusive borrows; see
  `azora-lang/ROADMAPs/FOUNDATION_REPAIR_2026_10_04.md`.
- `foundation` still fails one check: a `World` leaving scope does not destroy
  the components in its registered storages.
- UI: Row/Column `fill` children now share leftover space (they were counted as
  weighted but given zero extent). New modifiers `rounded`, `border`, `hover`,
  `textColor`, `fontSize`, `textAlign`, `semibold`, `monospace`; nodes without
  a `Paint` no longer paint opaque black. `recordTree`/`replayPaint` record a
  tree once per layout and replay it per frame.
- GPU/text: an SDF shape mode draws antialiased rounded rectangles and borders;
  text uses the system interface font (or Menlo) and a runtime text cache keeps
  rasterised strings as textures, retiring ones unused for 120 frames.
- Input: key repeats, Command/Control/Option tracking, Home/End/Delete/Page keys,
  per-frame UTF-8 text input (`App.textInput`) and the system clipboard.

## Current blockers

- Owned storage registration currently reaches a native compiler inline
  `T.typeName` lowering failure. A compiler repair is awaiting qualification.
- A generic `T: Clone` call currently returns the original erased pointer in
  native LLVM. Retained UI therefore releases component aliases as snapshots;
  sanitizer execution fails. This is a compiler blocker, and the Engine gate
  remains failing rather than bypassing component ownership.
- The game currently fails imported Int range witness resolution in
  `std__container__list___arrayListOf`. Ordinary Int ranges and the native
  scheduling probe pass; the complete renderer dependency closure still fails.
- Nonempty obsolete `Array::fill` capacity factories remain in advanced
  packages. Those need initialized dynamic storage, including changes to their
  indexed writes. Most advanced templates have not yet passed native execution.
- Dynamic resource registries, escaping query rows, closure lifetimes, atomic
  composition rollback and language-level reactive dependency tracking remain
  unqualified. Explicit stamp invalidation does not close those requirements.

Parser migration, individual passing probes and a linked constructor executable
do not qualify release readiness. The foundation inventory remains authoritative.
