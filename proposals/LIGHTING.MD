# Azora Lighting — Light Authoring, Conventional Direct Light, Probes, and Baking

Status: Proposal
Primary package: `azora-lighting`
Primary module: `engine.lighting`

## 1. Decision

Azora Lighting owns canonical light components, physically meaningful units,
cookies/IES data, emissive-source registration, conventional clustered direct
lighting, irradiance/light probes, and static light baking. Azora Spectrum is an
optional high-scale direct-light evaluator that consumes Lighting's immutable
light view for stochastic/reservoir sampling. Azora Shadows owns direct-light
visibility. Azora Radiance owns real-time global illumination, reflection probes,
and reflections. Keeping these boundaries explicit allows any evaluator to be
disabled or replaced without changing authored lights.

## 2. Current engine audit

`AzGpu` currently stores one direction vector and one ambient scalar. The fixed
3D shader evaluates that light directly. `engine.render.Material` exposes only
color and roughness. There are no light entities, units, clusters, cookies,
IES profiles, probes, lightmaps, or bake artifacts. The current directional
light becomes the default `DirectionalLight` created by the compatibility layer.

## 3. Goals

- directional, point, spot, rectangle, disk, line, and environment lights;
- lumens, candela, lux, nits, EV100, color temperature, and explicit legacy
  unitless conversion;
- Forward+ and deferred clustered selection with one shared light database;
- one stable `LightingView` consumed by Spectrum, Shadows, Radiance, Fluids,
  Particles, and other adapters;
- physically based attenuation and area-light approximations;
- light cookies, IES profiles, channels, volumetrics, and mobility;
- irradiance/light probes and baked lightmaps;
- mixed static/dynamic lighting and stationary-light validation;
- emissive mesh registration without making every emissive triangle a CPU light;
- deterministic culling and stable GPU light indices for temporal systems.

## 4. Public model

```azora
module engine.lighting

enum LightMobility {
    Static
    Stationary
    Movable
}

enum LightKind {
    Directional
    Point
    Spot
    Rectangle
    Disk
    Line
}

@Component
pack Light {
    fin kind: LightKind
    var color: Vec3
    var intensity: std::Double
    var range: std::Double
    var mobility: LightMobility
    var channels: std::Int
}

@Component
pack SpotShape {
    var innerRadians: std::Double
    var outerRadians: std::Double
}

@Component
pack AreaShape {
    var width: std::Double
    var height: std::Double
}

@Component
pack LightShadow {
    var enabled: std::Bool
    var quality: ShadowQuality
    var bias: std::Double
}

@Resource
pack LightingSettings {
    var maxVisibleLights: std::Int
    var clusterPixelSize: std::Int
    var depthSlices: std::Int
    var exposureCompensation: std::Double
}
```

Light selection is ECS-native:

```azora
@System(.Render)
func gatherLights(
    q: @query [Transform&, Light&] @without Disabled
) {
    // Build the frame light table from symbols and component data.
}
```

## 5. Frame pipeline

1. Extract changed lights and stable identities from ECS.
2. Compute bounds and importance on workers.
3. Upload a compact structure-of-arrays light table.
4. Build screen-space clusters on GPU.
5. Evaluate Material closures against cluster light lists when the conventional
   path is active, or publish the view for Spectrum's stochastic evaluator.
6. Ask Shadows for visibility only when a light requests it.
7. Publish direct-light buffers for transparent, volumetric, and Radiance passes.

Cluster overflow uses deterministic importance ranking and records the rejected
light count. It never corrupts a cluster or silently wraps an index.

## 6. Probes and baking

Light probes store irradiance or directional basis coefficients. Their influence
blending is stable under overlap and respects priority. Runtime light-probe
capture is scheduled under a strict face/time budget. Reflection capture,
prefiltering, and parallax volumes belong to Radiance.

The baker consumes the same Material closures and light definitions as runtime.
Artifacts contain geometry/material/light hashes, texel charts, validity masks,
and versioned compression. A changed movable light does not invalidate a bake;
a changed static emissive surface does.

Radiance may consume baked probes as fallback or initialization, but Lighting
does not depend on Radiance.

## 7. Emissive surfaces

Material publishes emissive classification. Lighting registers emissive
surfaces and builds compact mesh-light sampling records for surfaces selected by
policy. Spectrum owns scalable stochastic direct sampling of those records;
Radiance separately decides whether emitted energy bounces. Tiny or low-power
emitters are grouped or culled by solid angle and luminance, not merely by object
count.

## 8. Performance and quality

Quality tiers set cluster dimensions, maximum lights, area-light method, probe
resolution, and bake encoding. CPU work is incremental by change revision. GPU
buffers are double or triple buffered. The system exposes light count, lights
per cluster, overflow, shadow requests, probe captures, bake texels, and direct
lighting GPU time to `engine.profiler`.

The clustered evaluator is the deterministic portable fallback and reference
for small light sets. Spectrum owns many-light reservoir/history/ray budgets and
reports those separately.

## 9. Integration contracts

- Material supplies surface closure data.
- Spectrum consumes the immutable light/emissive view and returns scalable
  stochastic direct illumination.
- Shadows returns visibility for a light/surface sample.
- Aether supplies sun, sky radiance, and atmospheric transmittance.
- Radiance consumes direct-light and emissive sampling tables.
- Fluids and Particles consume the same clustered light buffers.
- World supplies cell visibility and streaming ownership.

No subsystem reaches into the private light table. Extensions use a versioned
`LightingView` read contract.

## 10. Delivery

1. ECS directional/point/spot lights, physical units, and Forward+ clusters.
2. Shadow request interface, cookies, channels, and transparent lighting.
3. Area lights, emissive registration, and shape-correct sampling metadata.
4. irradiance probes and offline lightmap baking.
5. volumetric integration, Spectrum/Radiance adapters, and bake/runtime parity.

Acceptance includes photometric reference scenes, stable light-table identity,
stable cluster overflow, bake reproducibility, Spectrum handoff, and explicit
fallback on targets without compute or storage-buffer support.
