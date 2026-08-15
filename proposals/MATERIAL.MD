# Azora Material — Layered Material System

Status: Proposal
Primary package: `azora-material`
Primary module: `engine.material`

## 1. Decision

Azora Material is the renderer-independent description of how a surface looks.
It owns physically based surface models, reusable layers, parameters, texture
bindings, graph compilation, instances, and shader permutation policy. It does
not own lights, shadows, indirect illumination, mesh residency, or draw
scheduling.

The ergonomic center is a material asset plus cheap instances. Artists build a
layered graph once; gameplay changes typed parameters without cloning shaders.
The renderer compiles only static topology and switches, while ordinary values
remain data.

## 2. Current engine audit

The current `engine.render` package has a `Material` containing only `Color` and
`roughness`; `drawMeshMaterial` forwards only RGB to the immediate renderer.
`engine.shaders` embeds fixed MSL, Vulkan, and WebGL shader strings. There is no
material asset identity, texture parameter, metalness, normal map, layering,
graph compiler, reflection metadata, or pipeline cache. This proposal replaces
that placeholder without breaking `materialColor`, which becomes convenience
sugar for an unlit or standard material instance.

## 3. Scope

Required capabilities:

- metallic/roughness and specular/gloss PBR workflows;
- unlit, clear-coat, subsurface, cloth, hair, eye, water, foliage, and decal
  surface models through bounded extensions;
- any number of authoring layers, compiled to a backend-supported runtime plan;
- height, weight, vertex-color, texture, slope, and procedural layer masks;
- scalar, vector, color, texture, sampler, buffer, and curve parameters;
- static switches with explicit permutation cost;
- material functions and reusable subgraphs;
- transparent, masked, additive, premultiplied, and opaque modes;
- double-sided and thin-surface policy;
- virtual-texture and bindless-capable bindings with conventional fallbacks;
- deterministic graph hashing, derived-data caching, and hot reload;
- CPU reference evaluation for thumbnails and tests.

Material does not define a general-purpose visual scripting language. Graph
nodes are pure surface functions with known effects and bounded resource use.

## 4. Package boundaries

```text
azora-material       -> azora-core, azora-math, azora-image, azora-shaders
azora-material-gpu   -> azora-material, azora-gpu
azora-render         -> azora-material-gpu

azora-lighting ----reads----> compiled material lighting contract
azora-radiance ----reads-----> material albedo/emissive/roughness
azora-decals ------composes---> material layers
```

`engine.material` owns portable assets and compilation IR.
`engine.material.gpu` owns descriptor layouts and backend pipelines. GPU handles
never appear in serialized material assets.

## 5. Public model

```azora
module engine.material

pack MaterialId {
    fin value: std::Long
}

enum SurfaceModel {
    Standard
    Unlit
    ClearCoat
    Subsurface
    Cloth
    Hair
    Eye
    Fluid
    Foliage
}

enum BlendMode {
    Opaque
    Masked
    Alpha
    Premultiplied
    Additive
}

variant enum MaterialValue {
    Real(std::Double)
    Vec2Value(Vec2)
    Vec3Value(Vec3)
    Vec4Value(Vec4)
    ColorValue(Color)
    Texture(TextureId)
    Boolean(std::Bool)
}

pack MaterialParameter {
    fin symbol: MaterialParameterId
    fin name: std::String
    fin defaultValue: MaterialValue
}

pack MaterialLayer {
    fin material: MaterialId
    fin mask: MaterialNodeId
    fin heightBlend: std::Bool
}

pack MaterialAsset {
    fin id: MaterialId
    fin model: SurfaceModel
    fin blend: BlendMode
    fin graph: MaterialGraph
    fin layers: std::Array<MaterialLayer>
    fin parameters: std::Array<MaterialParameter>
}

@Component
pack MaterialRef {
    fin instance: MaterialInstanceId
}
```

Parameter lookup is by stable `MaterialParameterId`, never by display name.
Names may repeat in different functions or layers without aliasing. Authoring
tools resolve names to symbols when assets are compiled.

```azora
impl MaterialInstance {
    func set(symbol: MaterialParameterId, value: MaterialValue): std::Unit ?! MaterialError
    func reset(symbol: MaterialParameterId): std::Unit ?! MaterialError
}
```

## 6. Graph and compilation model

The graph is a typed DAG. Nodes declare input/output value domains, derivative
requirements, texture access, and shader-stage legality. Compilation performs:

1. symbol resolution and cycle rejection;
2. type and color-space checking;
3. constant folding and dead-node removal;
4. layer flattening subject to backend limits;
5. derivative and tangent-space validation;
6. static-switch specialization;
7. common-subexpression elimination;
8. portable shader IR generation;
9. backend shader and reflection generation;
10. pipeline-key and cache artifact generation.

Runtime compilation is allowed in editor builds. Shipping builds load signed,
precompiled variants and may compile only explicitly permitted user content.
Every permutation reports its source switches and estimated cost.

## 7. Layering

Layers blend semantic channels rather than final shaded colors: base color,
normal, metalness, roughness, occlusion, emissive, thickness, and custom model
channels. Normals use reoriented normal mapping. Height blending uses a bounded
neighborhood and must not silently turn into unbounded parallax work.

Landscape and Road materials may request many authoring layers. The compiler
packs visible layers per terrain tile and emits a deterministic overflow
diagnostic when the selected quality tier cannot evaluate all of them.

## 8. Rendering contract

A compiled material publishes:

- pass participation: depth, visibility, G-buffer, forward, shadow, velocity;
- required vertex attributes;
- resource layout and immutable samplers;
- opacity and displacement classification;
- two-sided and culling policy;
- material feature bits;
- lighting closure inputs;
- ray-hit and software-fallback entry points where supported.

Material never calls Lighting or Radiance. It emits a surface closure; those
systems consume it. Emissive output is visible even when Radiance is disabled,
but indirect emissive contribution is Radiance policy.

## 9. Performance policy

- Material instances are compact parameter blocks allocated from frame-safe
  pools; changing one value must not allocate or compile.
- Textures use stable descriptor indices where supported.
- Pipeline creation is asynchronous and warmed from scene manifests.
- Missing variants render a visible fallback material and emit one deduplicated
  diagnostic rather than stalling the frame.
- Transparent materials are separately budgeted and sorted; they never enter
  opaque virtual-geometry paths accidentally.
- Graph complexity, sample count, dynamic branches, and register estimates are
  visible in the editor and profiler.

## 10. Tooling and diagnostics

The material editor provides graph validation, per-node previews, layer soloing,
channel visualization, shader source/IR inspection, permutation analysis, and a
material complexity view. Runtime counters include visible instances, unique
parameter blocks, texture misses, pipeline misses, layer overflow, shader
compile time, and fallback draws.

## 11. Delivery

1. Replace the color-only placeholder with Standard and Unlit assets, instances,
   typed parameters, textures, and offline compilation.
2. Add normal/metalness/roughness/emissive and render-pass reflection.
3. Add material functions, layers, decals, landscape layer packing, and hot reload.
4. Add specialized closures and ray-hit variants.
5. Add virtual textures, bindless tables, and advanced displacement integration.

Acceptance requires identical graph hashes across machines, no runtime compile
on a warmed shipping scene, validated color spaces, stable parameter symbols,
and a CPU reference test for every standard node.
