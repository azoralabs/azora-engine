# Existing Package Proposal Coverage

Status: Package-level proposal index
Scope: every package currently present under `packages/`, except
`azora-tracker` as explicitly requested

## 1. Purpose

The engine subsystem suite describes product capabilities such as Animation,
Physics, Material, and World. This index covers a different concern: every
package that already exists in the repository must have an implementation-grounded
proposal describing its current baseline, canonical ownership, gaps, migration,
tests, and acceptance criteria.

Several packages intentionally share one proposal because they are facets of
one subsystem. The fifteen packages that previously lacked dedicated coverage
now have their own proposal files.

## 2. Coverage

| Existing package | Module | Proposal | Coverage |
|---|---|---|---|
| `azora-animation-core` | `engine.animation.core` | [ANIMATION.MD](ANIMATION.MD) | shared Animation proposal |
| `azora-animation-2d` | `engine.animation.d2` | [ANIMATION.MD](ANIMATION.MD) | shared Animation proposal |
| `azora-animation-3d` | `engine.animation.d3` | [ANIMATION.MD](ANIMATION.MD) | shared Animation proposal |
| `azora-app` | `engine.app` | [APP.MD](APP.MD) | new dedicated proposal |
| `azora-audio` | `engine.audio` | [AUDIO.MD](AUDIO.MD) | existing dedicated proposal |
| `azora-core` | `engine.core` | [CORE.MD](CORE.MD) | new dedicated proposal |
| `azora-ecs` | `engine.ecs` | [ECS.MD](ECS.MD) | existing dedicated proposal |
| `azora-engine` | `engine` | [ENGINE.MD](ENGINE.MD) | new dedicated proposal |
| `azora-font` | `engine.font` | [FONT.MD](FONT.MD) | new dedicated proposal |
| `azora-gpu` | `engine.gpu` | [GPU.MD](GPU.MD) | new dedicated proposal |
| `azora-image` | `engine.image` | [IMAGE.MD](IMAGE.MD) | new dedicated proposal |
| `azora-input` | `engine.input` | [INPUT.MD](INPUT.MD) | existing dedicated proposal |
| `azora-io` | `engine.io` | [IO.MD](IO.MD) | new dedicated proposal |
| `azora-jobs` | `engine.jobs` | [JOBS.MD](JOBS.MD) | new dedicated proposal |
| `azora-math` | `engine.math` | [MATH.MD](MATH.MD) | new dedicated proposal |
| `azora-media-core` | `engine.media` | [MEDIA.MD](MEDIA.MD) | new dedicated proposal |
| `azora-objc` | `engine.objc` | [OBJC.MD](OBJC.MD) | new dedicated proposal |
| `azora-physics` | `engine.physics` | [PHYSICS.MD](PHYSICS.MD) | shared Physics proposal |
| `azora-physics-core` | `engine.physics.core` | [PHYSICS.MD](PHYSICS.MD) | shared Physics proposal |
| `azora-physics-2d` | `engine.physics.d2` | [PHYSICS.MD](PHYSICS.MD) | shared Physics proposal |
| `azora-physics-3d` | `engine.physics.d3` | [PHYSICS.MD](PHYSICS.MD) | shared Physics proposal |
| `azora-platform` | `engine.platform` | [PLATFORM.MD](PLATFORM.MD) | new dedicated proposal |
| `azora-render` | `engine.render` | [RENDER.MD](RENDER.MD) | new dedicated proposal |
| `azora-shaders` | `engine.shaders` | [SHADERS.MD](SHADERS.MD) | new dedicated proposal |
| `azora-tilemap` | `engine.tilemap` | [TILEMAP.MD](TILEMAP.MD) | new dedicated proposal |
| `azora-ui` | `engine.ui` | [UI.MD](UI.MD) | existing proposal plus detailed UI documents |
| `azora-video` | `engine.video` | [VIDEO.MD](VIDEO.MD) | existing dedicated proposal |

`azora-tracker` is intentionally excluded from this index and has no new
proposal.

## 3. New proposal files

- [APP.MD](APP.MD) — application modes, frame/fixed schedule, embedding,
  headless operation, and lifecycle.
- [CORE.MD](CORE.MD) — minimal dependency ceiling, symbols, clocks, signals,
  annotations, and application control.
- [ENGINE.MD](ENGINE.MD) — facade profiles, public/internal exports, package
  compatibility, and distribution closure.
- [FONT.MD](FONT.MD) — bitmap compatibility, Unicode shaping, OpenType,
  fallback, glyph caches, and Render/UI boundaries.
- [GPU.MD](GPU.MD) — typed GPU resources, graphics/compute, resource graph,
  capabilities, backends, and device recovery.
- [IMAGE.MD](IMAGE.MD) — checked image data, decoders, color/alpha, KTX,
  transforms, animation, and streaming.
- [IO.MD](IO.MD) — safe buffers/views, files, mounts, async requests, atomic
  storage, pressure, and security.
- [JOBS.MD](JOBS.MD) — bounded work stealing, priorities, dependencies,
  cancellation, affinity, deterministic merge, and profiling.
- [MATH.MD](MATH.MD) — value semantics, conventions, vectors, matrices,
  quaternions, transforms, precision, SIMD, and determinism.
- [MEDIA.MD](MEDIA.MD) — exact time, scoped streams/tracks, sources, providers,
  packets, seeking, clocks, and shared media metadata.
- [OBJC.MD](OBJC.MD) — internal typed Apple interop, ABI-safe messages,
  ownership, generation, and conformance.
- [PLATFORM.MD](PLATFORM.MD) — windows, displays, raw/text events, lifecycle,
  multi-window, headless, and surface targets.
- [RENDER.MD](RENDER.MD) — render ECS, extraction, views, batching, frame graph,
  compatibility drawing, and subsystem pass contributions.
- [SHADERS.MD](SHADERS.MD) — canonical shader IR, artifacts, reflection,
  layouts, backend emission, capability tiers, and hot reload.
- [TILEMAP.MD](TILEMAP.MD) — current lattice/layer strengths plus stable IDs,
  Tiled import, infinite chunks, streaming, transactions, batching, and editor.

## 4. Immediate package-graph findings

The source audit found manifest and layering mismatches that implementation
should address before advanced features:

| Package | Current mismatch | Proposed resolution |
|---|---|---|
| `azora-core` | imports `engine.io` without a manifest dependency | remove the edge; move exit/raw runtime hooks below engine packages |
| `azora-objc` | imports I/O only to reach raw memory helpers | use a minimal runtime FFI boundary and keep Objective-C Apple-only |
| `azora-gpu` | imports undeclared I/O; `gpu.draw` imports Platform while Platform depends on GPU | split GPU core/providers/surface adapter and move draw/text helpers upward |
| `azora-font` | imports Platform and GPU drawing without manifest dependencies | split font/shaping/raster data from Render/GPU atlas adapters |
| `azora-platform` | source imports Objective-C, I/O, and Core beyond its manifest and also owns GPU frames | declare provider dependencies, remove GPU ownership, publish surface targets |
| `azora-render` | source imports Input/Platform beyond its manifest and indirectly consumes GPU handles | use Render extraction plus declared GPU contracts; move controls to Camera/Input |
| `azora-engine` | facade pulls every package/native framework and exposes FFI internals | add profiles and public/internal export classification |

These are proposal findings, not silent manifest edits. They require staged code
migration and package-graph tests.

## 5. Canonical dependency direction

1. Math and Core remain portable, minimal foundations.
2. I/O and internal target FFI provide bounded low-level services.
3. ECS, Jobs, Input, Image, Font Core, and Media Core build on foundations.
4. Platform publishes windows/events/surface targets without importing GPU.
5. Shaders and GPU providers implement portable graphics/compute.
6. Render consumes GPU and extracts ECS data; Font Render and UI build above it.
7. Tilemap, Animation, Physics, Audio, Video, and other systems integrate through
   their canonical contracts.
8. App orchestrates selected providers and schedule phases.
9. The Engine facade re-exports only the selected public profile.

No layer may depend back on App or the facade.

## 6. Planned packages added by this expansion

This expansion also defines these packages before their directories are created:

- [ACCESSIBILITY.MD](ACCESSIBILITY.MD) — accessibility settings, semantics,
  subtitles/captions, color/motion support, remapping coordination, and native
  assistive-technology bridges.
- [ASSETS.MD](ASSETS.MD) — source import, cooking, target variants, dependency
  graph, artifacts, and cache.
- [SERIALIZATION.MD](SERIALIZATION.MD) — engine schemas, AZON graphs, stable
  references, unknown-data preservation, and migrations.
- [PREFAB.MD](PREFAB.MD) and [SCENE.MD](SCENE.MD) — reusable templates and
  loadable entity/hierarchy graphs.
- [SAVE.MD](SAVE.MD) — persistent slots, snapshots, recovery, migration, and
  optional cloud conflict handling.
- [BUILD.MD](BUILD.MD) — target build graph, cooking, packaging, signing, and
  deployment.
- [DEBUG.MD](DEBUG.MD) — bounded visual diagnostics, subsystem inspectors,
  captures, and authenticated remote debugging.
- [SPECTRUM.MD](SPECTRUM.MD) — massively scalable stochastic direct lighting,
  reservoirs, ray-traced area-light shadows, and portable many-light fallbacks.

## 7. Acceptance

Package proposal coverage is complete when:

1. every current non-tracker package appears in the table exactly once;
2. every linked proposal exists and names the package/module it governs;
3. current implementation is distinguished from future work;
4. ownership and dependency direction agree across documents;
5. all Azora examples use current declarations and query grammar;
6. implementation can add package-graph validation without introducing a cycle;
7. `azora-tracker` remains untouched and outside this proposal expansion.
