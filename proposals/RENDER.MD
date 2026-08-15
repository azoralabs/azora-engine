# Azora Render — Scene Extraction, Frame Graph, and Draw Submission

Status: Proposal replacing split immediate render paths
Package: `azora-render`
Module: `engine.render`

## 1. Decision

`azora-render` owns renderable ECS vocabulary, scene extraction, visibility,
view families, render phases, draw preparation, batching, frame-graph policy,
and submission through GPU. GPU owns device resources and command execution.
Material, Lighting, Spectrum, Shadows, Radiance, PostFX, Camera, UI, Shard, and
other systems contribute data and passes through explicit contracts.

One renderer serves native and web backends. The current immediate APIs remain a
compatibility layer that records commands into the same frame.

## 2. Current implementation audit

The package currently provides a fly `Camera`, color, placeholder
color/roughness `Material`, two transform packs, `RenderItem`, a growable
`RenderQueue`, matrix construction, camera controls, and methods that draw the
queue through Platform `App`. A separate `engine.render.webgl` realm exposes an
async WebAssembly frame loop and immediate rect/circle/cube calls.

Gaps and inconsistencies:

- native and WebGL paths have different lifetimes, features, data, shaders, and
  APIs;
- Render imports Input and Platform but its manifest does not declare them;
- `Transform`, `Transform3d`, Math/Physics transforms, and camera transforms
  overlap;
- `Mesh` arrives indirectly and GPU handles are embedded in render items;
- queue growth allocates during frame work and lacks visibility, sorting,
  batching, instancing, phases, views, render targets, or motion history;
- no ECS extraction/preparation boundary or render-world snapshot;
- no frame graph, resource declaration, temporal history, device loss, LOD,
  Streaming, Jobs, or Profiler integration;
- Material and lighting placeholders conflict with their dedicated systems.

## 3. Public ECS vocabulary

```azora
pack MeshAssetId {
    fin symbol: ContentSymbol
}

pack MaterialAssetId {
    fin symbol: ContentSymbol
}

@Component
pack Render {
    var enabled: std::Bool
    var layerMask: std::Long
    var visibilityClass: std::Int
}

@Component
pack MeshRender {
    fin mesh: MeshAssetId
    fin material: MaterialAssetId
    var lodBias: std::Double
}

@Component
pack PreviousTransform {
    var value: Transform3
}
```

`Transform3` from Math is canonical. Render components reference stable assets,
not GPU handles. Extracted instances resolve asset generations and provider
resources in the render world.

```azora
@System(.Render)
func extractVisibleMeshes(
    q: @query [Transform&, MeshRender&, Render&] @with Render @without Disabled
) {
    for [transform&, mesh&, render&] in q {
        if render.enabled {
            submitMeshInstance(transform, mesh)
        }
    }
}
```

The marker and accessed `Render&` component intentionally share the user-chosen
name `Render`; no `Renderable` declaration is introduced.

## 4. Render-world pipeline

1. **Extract:** copy changed render-relevant ECS data into a frame snapshot.
2. **Resolve:** bind asset generations and choose declared fallbacks.
3. **View:** build camera/view families, culling volumes, jitter, and history.
4. **Cull/LOD:** World/Shard/Streaming visibility, CPU/GPU culling, LOD policy.
5. **Prepare:** allocate bounded instance, material, light, skin, and draw data.
6. **Queue:** assign items to opaque, masked, transparent, shadow, UI, debug,
   custom, and provider phases.
7. **Sort/batch:** pipeline/material/mesh/depth order and instancing.
8. **Graph:** declare passes/resources and let GPU validate/execute hazards.
9. **Submit/present:** queue work and retire completed frame generations.

Extraction isolates gameplay mutation from render parallelism and interpolation.
The render world is transient and cannot become gameplay authority.

## 5. Frame graph and extension model

Render defines named pass symbols, view scope, phase, dependencies, resource
descriptions, temporal history, and fallback behavior. GPU compiles resource
access into backend barriers and transient allocations.

Subsystems register compile-time pass contributions through stable symbols:
Shadows, depth/visibility, G-buffer or forward lighting, Spectrum stochastic
direct lighting, Radiance, transparencies, volumetrics, particles, UI, PostFX,
debug, capture, and presentation. Pass names are diagnostics; symbol uses define
ordering.

Render also owns the immutable ray-scene instance view assembled from World,
Shard, Animation, Foliage, Cloth, and Destruction contributors. GPU owns native
acceleration-structure resources. Spectrum, Shadows, and Radiance consume this
one view with distinct traversal/estimator policy instead of duplicating scene
ownership.

Custom packages may contribute typed render features without reaching native
encoders. Backend-specific escape hatches are explicitly non-portable and
capability-gated.

## 6. Visibility, batching, and streaming

CPU coarse culling uses World cells and view volumes. GPU fine culling/indirect
drawing is optional. Occlusion results are delayed hints and never gameplay
authority. LOD decisions account for screen size, importance, residency,
animation, shadows, and hysteresis.

Draw/instance buffers are pre-sized from budgets and report overflow. Streaming
publishes assets generation-atomically; missing pages select proxy geometry or
material fallbacks. Pipeline preparation occurs ahead of visibility when
possible.

## 7. Compatibility and ownership migrations

- current `Camera` controls migrate to Camera/Input proposals;
- current `Material` becomes a compatibility wrapper over Material assets;
- `RenderQueue` records into a bounded compatibility phase;
- native `App.draw*` and web immediate functions share one command adapter;
- primitive mesh creation moves to a geometry/assets package or Procedural;
- CoreText rasterization moves to Font;
- WebGL device code moves under GPU's web provider.

## 8. Diagnostics and delivery

Render inspector shows views, culling reasons, LOD/residency, phases, sorted
items, batches, instances, pipelines, passes, resources, history, fallbacks, and
per-object symbols. Profiler records extraction, culling, preparation, sorting,
draw/dispatch counts, triangles, overdraw estimates, pass CPU/GPU time, uploads,
pipeline misses, memory, and presentation latency.

Delivery:

1. canonical transform/assets/components and render-world extraction;
2. typed GPU resources, bounded phases, batching, instancing, and native path;
3. frame graph, views, culling/LOD, Streaming, and Profiler;
4. unify web provider and retire divergent immediate implementation;
5. integrate the advanced rendering subsystem proposals and editor tooling.

Acceptance requires backend-identical scene semantics, no public GPU/native
handles, exact query syntax, no frame-loop unbounded allocation, stable pass
symbols, recoverable missing assets/device loss, and traceable ownership for
every render contribution.
