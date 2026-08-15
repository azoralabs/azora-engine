# Azora Animation — Skeletal, Graph, IK, and Morph Animation

Status: Proposal building on substantial implementation
Packages: `azora-animation-core`, `azora-animation-2d`, `azora-animation-3d`
Modules: `engine.animation.core`, `engine.animation.d2`, `engine.animation.d3`

## 1. Decision

Preserve the current three-package split. The core owns time, curves, clips,
players, events, and timelines. The 2D package owns sprite and layer animation.
The 3D package owns skeletons, poses, skinning, blend graphs, morph targets, root
motion, IK, retargeting, and animation-driven constraints. Runtime evaluation
becomes a compiled graph over immutable assets and per-entity instance state.

## 2. Current implementation audit

Already implemented and tested:

- generic and scalar keyframe tracks, interpolation modes, clips, loop modes,
  playback state/direction, events, players, timelines, and normalized weights;
- sprite sheets, frame runs, variable-hold flipbooks, animated sprite components,
  tint/transform/color tracks, layer sampling, and blend helpers;
- bone transforms, hierarchy validation, bind/world poses, skin matrices, pose
  blending and subtree masks;
- skeletal tracks/clips, morph weight tracks, `AnimationRig`, a two-input blend
  tree, two-bone IK, root-motion extraction, skin influence normalization, and a
  CPU reference skinning function;
- tests for clock behavior, event windows, hierarchy, blending, morph clamping,
  IK chain validation, root motion, and rig advancement.

Important gaps:

- asset import/serialization and stable symbol mapping;
- compiled state machines and general animation graphs;
- blend spaces, additive layers, sync groups, inertialization, pose caches;
- robust retargeting profiles and runtime retargeting;
- CCD/FABRIK/full-body IK, constraints, foot locking, motion warping;
- GPU skinning/render integration, bounds, LOD, streaming, jobs, ECS systems;
- animation-notify routing with stable event identity;
- graph debugger, profiler integration, networking/replay policy.

## 3. Asset and instance model

```azora
pack SkeletonId {
    fin value: std::Long
}

pack AnimationClipId {
    fin value: std::Long
}

pack AnimationGraphId {
    fin value: std::Long
}

@Component
pack Animator {
    fin graph: AnimationGraphId
    var speed: std::Double
    var enabled: std::Bool
    var lod: std::Int
}

@Component
pack AnimationParameters {
    var values: AnimationParameterBlock
}

@Component
pack AnimationPose {
    var current: PoseHandle
    var previous: PoseHandle
    var generation: std::Long
}
```

Bones, clips, graph nodes, states, parameters, morph targets, and notify sites
use stable symbols. Human-readable names are metadata and may repeat in nested
machines or different skeletons.

## 4. Compiled graph

Authoring nodes include clip, state machine, 1D/2D blend space, layered blend,
masked blend, additive pose, sync group, pose cache, inertial transition,
parameter curve, IK, aim/look, constraint, retarget, motion warp, and output.

Compilation resolves symbols, validates skeleton compatibility and cycles,
calculates pose lifetimes, allocates a compact instance-state block, schedules
independent branches, and emits an evaluation program. Runtime evaluation does
not walk strings or allocate graph nodes.

State transitions have priority, interruption, exit-time, duration, easing,
sync-marker, and inertialization policy. Multiple valid transitions resolve by
stable compiled order and report ambiguity in authoring tools.

## 5. Retargeting and IK

A retarget profile maps source and target bone symbols, reference poses, chains,
translation modes, scale compensation, twist distribution, and root policy.
Missing optional bones degrade by chain; missing required chains fail validation.

The solver suite adds CCD and FABRIK chains, look/aim, pole constraints, foot
planting, and full-body goals. Physics constraints consume a post-animation
target; ragdoll blending consumes physics poses after simulation. Order is
explicit in the schedule.

## 6. Evaluation schedule

1. resolve graph parameters and active transitions;
2. advance clocks and sync groups at fixed/game time policy;
3. request resident clips and choose fallback poses;
4. sample clips and morph curves in parallel;
5. blend/cache local poses;
6. retarget and apply procedural constraints/IK;
7. extract root motion and events;
8. hand root motion to gameplay/Physics;
9. build world and skinning matrices;
10. upload current/previous palettes for rendering and motion vectors.

## 7. Streaming, LOD, and determinism

Skeleton and graph headers remain resident; compressed clip segments stream by
lookahead. Missing segments hold or blend to a declared fallback pose. Animation
LOD reduces update rate, bone set, IK, morph count, and skinning quality without
changing authoritative root motion unexpectedly.

Events use interval crossing as the existing implementation does. Replay stores
parameters, graph/state symbols, clock generations, and authoritative root
motion—not transient pose-buffer handles.

## 8. Diagnostics and delivery

The debugger shows active states/transitions, node weights, sync phase, pose
cache, bone transforms, retarget chains, IK errors, morph values, root motion,
events, clip residency, and LOD. Counters include animators, sampled bones,
active nodes, cache hits, decompression, CPU/GPU skinning, IK time, and misses.

Delivery:

1. asset symbols/import, serialization, ECS schedule, pooled pose buffers.
2. compiled graphs, state machines, blend spaces, additive/masked layers.
3. GPU skinning, morph rendering, clip streaming, LOD, motion vectors.
4. retarget profiles, CCD/FABRIK, foot locking, motion warping, ragdoll blending.
5. editor graph/debugger, networking/replay conformance, advanced full-body IK.

glTF import must follow its defined skin hierarchy and morph-target delta model:
[glTF 2.0 specification](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html).
