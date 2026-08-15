# Azora Engine System Proposal Suite

Status: Suite index
Scope: ownership, implementation baseline, and dependency order for the 45
engine subsystem proposals

## 1. Purpose

This index keeps the subsystem proposals from becoming 45 isolated designs. It
records what exists in the repository now, assigns one owner to every shared
responsibility, and gives an implementation order that can produce a usable
engine continuously.

Every subsystem has its own proposal file. Existing focused documents remain
authoritative for Video, Navigation, and reactive ECS UI.

## 2. Current baseline

| System | Current repository state | Proposal |
|---|---|---|
| Material | color + roughness placeholder in `engine.render` | [MATERIAL.MD](MATERIAL.MD) |
| Radiance | absent; ambient scalar only | [RADIANCE.MD](RADIANCE.MD) |
| Shard | absent; raw vertex-buffer mesh only | [SHARD.MD](SHARD.MD) |
| Landscape | absent | [LANDSCAPE.MD](LANDSCAPE.MD) |
| Roads | absent | [ROADS.MD](ROADS.MD) |
| Physics | tested 2D/3D primitives; no simulation world/solver | [PHYSICS.MD](PHYSICS.MD) |
| Vehicle | absent | [VEHICLE.MD](VEHICLE.MD) |
| Procedural | absent; useful Tilemap operations exist | [PROCEDURAL.MD](PROCEDURAL.MD) |
| Shadows | absent | [SHADOWS.MD](SHADOWS.MD) |
| Voxels | absent; Tilemap has unrelated sparse 2D chunks | [VOXELS.MD](VOXELS.MD) |
| Aether | absent | [AETHER.MD](AETHER.MD) |
| Particles | absent | [PARTICLES.MD](PARTICLES.MD) |
| Animation | substantial clips, 2D, skeleton, skin, blend, IK, morph, root motion | [ANIMATION.MD](ANIMATION.MD) |
| Genesis | no unified creature platform; Animation supplies skeleton/skin/morph foundations | [GENESIS.MD](GENESIS.MD) |
| Traverse | absent; Tilemap has hex/grid geometry and line of sight | [TRAVERSE.MD](TRAVERSE.MD) |
| Cognition | absent | [COGNITION.MD](COGNITION.MD) |
| Audio | AVAudioPlayer compatibility plus new PCM pool/buses/effect contract | [AUDIO.MD](AUDIO.MD) |
| Fluids | absent | [FLUIDS.MD](FLUIDS.MD) |
| Foliage | absent | [FOLIAGE.MD](FOLIAGE.MD) |
| Destruction | absent | [DESTRUCTION.MD](DESTRUCTION.MD) |
| Cloth | absent | [CLOTH.MD](CLOTH.MD) |
| Lighting | hard-coded direction + ambient only | [LIGHTING.MD](LIGHTING.MD) |
| Spectrum | absent; no many-light sampling, reservoirs, or ray-scene visibility | [SPECTRUM.MD](SPECTRUM.MD) |
| PostFX | absent; direct drawable output only | [POSTFX.MD](POSTFX.MD) |
| Decals | absent | [DECALS.MD](DECALS.MD) |
| Camera | minimal fly camera and separate TileCamera | [CAMERA.MD](CAMERA.MD) |
| UI | partial keyed ECS composition/layout/paint/reactive/navigation foundations | [UI.MD](UI.MD) |
| Input | broad typed raw input; no action/remapping/haptics layer | [INPUT.MD](INPUT.MD) |
| Accessibility | disconnected UI/Input/Video/Platform intentions; no shared settings, semantics bridge, or audits | [ACCESSIBILITY.MD](ACCESSIBILITY.MD) |
| Networking | absent | [NETWORKING.MD](NETWORKING.MD) |
| Assets | direct synchronous path loaders; no registry/import/cook/dependency graph | [ASSETS.MD](ASSETS.MD) |
| Serialization | strict AZON and compiler-derived codecs exist in `azora-lang`; engine graph schemas/migrations absent | [SERIALIZATION.MD](SERIALIZATION.MD) |
| Prefab | ECS Boolean marker only | [PREFAB.MD](PREFAB.MD) |
| Scene | ECS names/parent IDs only; no scene asset, lifecycle, or transform graph | [SCENE.MD](SCENE.MD) |
| World | ECS World exists; spatial world/partitioning absent | [WORLD.MD](WORLD.MD) |
| Streaming | synchronous whole-file loads; bounded media/audio pools only | [STREAMING.MD](STREAMING.MD) |
| Save | temporary-file text write exists; no slots, snapshots, manifests, or recovery | [SAVE.MD](SAVE.MD) |
| Cinematics | animation Timeline only | [CINEMATICS.MD](CINEMATICS.MD) |
| Replay | absent | [REPLAY.MD](REPLAY.MD) |
| XR | absent | [XR.MD](XR.MD) |
| ECS | substantial sparse ECS and planner; query lowering/parallel chunks missing | [ECS.MD](ECS.MD) |
| Platform | working Cocoa/Metal-coupled macOS host; portable provider split absent | [PLATFORM.MD](PLATFORM.MD) |
| Build | package resolver and macOS LLVM/clang scripts; no cooked target graph/deployment | [BUILD.MD](BUILD.MD) |
| Profiler | full design exists; recording package/runtime not implemented | [PROFILER.MD](PROFILER.MD) |
| Debug | subsystem-specific proposed views only; no unified visual/remote debugger | [DEBUG.MD](DEBUG.MD) |

## 3. Ownership rules

- Material owns surface closures and layers.
- Lighting owns light authoring, conventional direct evaluation,
  light/irradiance probes, and baking.
- Spectrum owns scalable stochastic direct-light selection, reservoirs, reuse,
  area-light estimation, and direct-light reconstruction.
- Shadows owns direct-light visibility services, including shadow maps and ray
  queries over the shared Render/GPU ray scene.
- Radiance owns indirect light, reflection probes, and reflections.
- Shard owns virtual geometry; Streaming owns its residency.
- Landscape owns terrain data; Roads owns road/lane semantics; World owns cells.
- Physics owns collision/forces; Vehicle, Cloth, Fluids, and Destruction build on it.
- Genesis owns creature semantics, species/DNA, phenotype compilation, body and
  face composition, and creature-specific asset bindings; Animation evaluates
  poses/rigs/morphs/skinning, Material shades them, Cloth simulates grooms,
  Audio plays voices, and Cognition chooses behavior.
- Traverse owns movement connectivity; Cognition owns decisions.
- Input owns actions/remapping; Accessibility owns inclusive profiles, audits,
  and cross-system policy; Camera owns views; UI owns interaction and semantics.
- Networking owns authority/prediction; Replay owns recording/seek.
- Aether owns environment state; consumers implement their own visual/audio response.
- Assets owns source/import/cook/dependencies; Streaming owns runtime residency.
- Serialization owns AZON schemas/migrations; Save owns durable slots/transactions.
- Scene owns bounded object graphs/hierarchy; Prefab owns reusable templates and
  overrides; World owns spatial cells, large coordinates, and cross-cell state.
- ECS owns data access and schedule declarations; Jobs owns worker execution.
- Platform owns OS integration; Build owns offline cooking, packaging, signing,
  and deployment.
- Profiler measures cost; Debug inspects state. Both observe through neutral
  contracts and neither becomes gameplay authority.

## 4. Shared invariants

1. Stable compiler/content symbols are identity; names are display metadata.
2. ECS systems use `@query [...] @with ... @without ...` exactly.
3. `pack`, `enum`, `variant enum`, `error`, `spec`, `impl Name<T>`, and
   `react func` are the proposal vocabulary. Pack and enum members have no commas.
4. GPU acceleration has a capability record and declared portable fallback.
5. Gameplay authority never silently depends on delayed GPU readback.
6. Streaming publication is generation-atomic and cancellation-safe.
7. Fixed-step state, render interpolation, media time, and network time are
   separate clocks connected by explicit conversions.
8. Every bounded queue reports pressure, overflow, and dropped work.
9. Every subsystem defines profiler counters and a visual/debug inspection path.
10. Save, network, replay, and cross-cell references never store transient array,
    entity, pointer, GPU address, or provider-handle identity.
11. AZON is the canonical editable/interchange representation; cooked binary
    artifacts are versioned disposable caches from the same schemas.
12. Source paths and display names are metadata; Asset, schema, node, object, and
    declaration symbols remain identity across rename and recook.
13. Stochastic rendering is never gameplay authority; biased quality modes are
    explicit and expose their clamps, rejected history, and fallback pixels.

## 5. Dependency order

### Foundation

1. stabilize compiler/content symbols and build engine Serialization schemas over
   `std.serializer`/AZON;
2. finish ECS query lowering, hierarchy storage, deterministic command merge;
3. implement Jobs priorities/cancellation, Profiler core, and bounded Debug core;
4. build Assets import/cook/dependency manifests and replace synchronous I/O
   assumptions with Streaming handles/generations;
5. split portable Platform providers and build GPU resources, compute, render
   graph, and shader IR.

### Rendering engine

6. Material, Camera, Lighting, Shadows, PostFX;
7. Spectrum stochastic direct lighting after stable light, Material,
   motion/history, visibility, and ray-scene contracts;
8. Scene/Prefab lifecycle and World partitioning over cooked asset manifests;
9. Shard and large-resource streaming;
10. Landscape, Roads, Decals, Foliage, Fluids, Aether, Particles;
11. Radiance after motion/history, material, lighting, Spectrum, geometry, and
    residency contracts are stable.

### Simulation and gameplay

12. Physics world/solver, Input actions, and Accessibility preference baseline;
13. Animation graph/runtime rendering integration;
14. Genesis core, species/DNA compiler, body/face/skeleton/morph/rig runtime;
15. Traverse and Cognition;
16. Vehicle, Cloth, Destruction, and advanced Fluids interaction;
17. Procedural graph after World transactions and content symbols are reliable.

### Product/runtime

18. complete Audio/Video providers, Genesis voice and groom integration,
    UI/Navigation, and Accessibility adapters;
19. Save over stable Serialization/Scene/Prefab/World state;
20. Networking, Replay, and Cinematics;
21. Build target cooking/packaging/deployment over complete provider and asset
    manifests;
22. XR after view families, frame graph, Input actions, and UI layers exist.

## 6. Existing companion proposals

- [PACKAGE_PROPOSALS.MD](PACKAGE_PROPOSALS.MD) — package-level coverage for
  every package already present in the repository except `azora-tracker`.
- [REACTIVE_ECS_UI.MD](REACTIVE_ECS_UI.MD) — detailed reactive/ECS UI model.
- [NAVIGATION.MD](NAVIGATION.MD) — screen/dialog/transition navigation.
- [VIDEO.MD](VIDEO.MD) — media sessions and video surfaces.
- [ROBOTICS.MD](ROBOTICS.MD) — robotics capability hosted by the engine project.

## 7. Suite acceptance

The suite is coherent when package dependency graphs contain no cycles; each
shared concept has one canonical owner; current implementations have explicit
migration paths; every code example follows current Azora syntax; capability
fallbacks are testable; and the staged order can run demos after every phase
without waiting for all 45 systems to be complete.
