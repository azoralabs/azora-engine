# Azora Spectrum — Massively Scalable Direct Lighting

Status: Proposal
Primary package: `azora-spectrum`
Primary module: `engine.spectrum`

## 1. Decision

Azora Spectrum is the optional high-scale direct-lighting renderer for scenes
with thousands of dynamic analytic, area, and emissive lights. It replaces
“evaluate every relevant light” with stochastic candidate generation,
importance resampling, temporal/spatial reservoir reuse, one or a few selected
light samples per shading point, and capability-driven visibility evaluation.

Lighting remains the canonical owner of light components, photometric units,
cookies/IES data, emissive registration, probes, baking, and a deterministic
clustered fallback. Spectrum consumes Lighting's immutable light view. Shadows
owns direct-light visibility providers, including virtual/atlas maps and ray
queries. Spectrum owns which light/sample is selected, the Monte Carlo direct
estimator, history, and direct-light denoising. Radiance owns indirect
illumination and reflections.

The baseline target is stable real-time rendering of many thousands of fully
dynamic lights without a fixed “nearest N lights” visual cliff. Higher tiers may
sample millions of emissive primitives after Assets/Shard cooking groups them
into bounded light clusters. These are design targets, not claims about the
current one-directional-light renderer.

## 2. Current engine audit

The renderer currently stores one light direction and one ambient scalar in
`AzGpu`; fixed Metal/GLSL shader strings evaluate that light per draw. There are
no ECS light entities, physical units, Material closures, light tables, screen
clusters, G-buffer, motion vectors, depth pyramid, render graph, ray scene,
acceleration structures, area-light sampling records, reservoirs, stochastic
direct-light estimator, or denoiser.

Lighting, Shadows, Material, Render, GPU, Shaders, Assets, Streaming, and World
are therefore required foundations. Spectrum must not be implemented as another
immediate draw helper or embedded provider shader string.

## 3. Goals and non-goals

Goals:

- thousands of moving point, spot, directional, rectangle, disk, and line lights;
- emissive-triangle and mesh-light clusters with target-compatible sampling data;
- stochastic light selection without looping over every light per pixel;
- ReSTIR-style temporal and spatial reuse with explicit correctness modes;
- ray-traced soft shadows from finite area-light samples;
- hybrid sampled virtual/atlas shadow maps where ray queries are unavailable or
  too expensive;
- stable behavior under light motion, camera cuts, disocclusion, streaming,
  origin rebasing, resolution changes, and dynamic geometry;
- diffuse and specular direct illumination, transparent/volumetric adapters, and
  deterministic quality/capability resolution;
- measurable error, variance, history rejection, ray, memory, and frame budgets.

Non-goals:

- Spectrum does not own light authoring, probes, lightmaps, GI, reflections,
  exposure, tone mapping, or gameplay visibility;
- it does not promise noise-free one-sample lighting without temporal latency;
- ray visibility never becomes a gameplay line-of-sight or Physics query;
- stochastic render output is not used as deterministic simulation authority;
- an `Auto` mode is not serialized—the quality resolver records one concrete
  mode and the reason for it.

## 4. Public configuration

```azora
enum SpectrumMode {
    Disabled
    Clustered
    Stochastic
    Reservoir
    RayTraced
}

enum SpectrumVisibility {
    Unshadowed
    ShadowMaps
    RayQueries
    Hybrid
}

enum SpectrumCorrectness {
    Reference
    Unbiased
    StableBiased
}

@Resource
pack SpectrumSettings {
    var mode: SpectrumMode
    var visibility: SpectrumVisibility
    var correctness: SpectrumCorrectness
    var initialCandidates: std::Int
    var spatialCandidates: std::Int
    var maxHistoryFrames: std::Int
    var shadowRaysPerPixel: std::Int
    var halfResolution: std::Bool
    var maxVisibleLights: std::Int
    var maxReservoirBytes: std::Long
}

@Component
pack SpectrumLightPolicy {
    var enabled: std::Bool
    var samplingScale: std::Double
    var rayVisibility: std::Bool
    var priority: std::Int
}

pack SpectrumCapabilities {
    fin compute: std::Bool
    fin storageBuffers: std::Bool
    fin rayQueries: std::Bool
    fin motionVectors: std::Bool
    fin waveOperations: std::Bool
    fin sampledShadowMaps: std::Bool
}
```

`SpectrumLightPolicy` is an optional renderer hint. It cannot change emitted
physical power or bypass Lighting channels. Lights without it use the selected
quality profile defaults.

`Clustered` selects Lighting's deterministic conventional evaluator.
`Stochastic` samples only current-frame candidates. `Reservoir` adds temporal
and spatial reuse with map/unshadowed visibility. `RayTraced` requires
`RayQueries` or `Hybrid` visibility and adds finite-emitter shadow rays. Invalid
mode/visibility combinations fail profile validation rather than being silently
reinterpreted.

`Reference` evaluates a bounded reference set for tests/captures.
`Unbiased` uses the validated estimator and rejects approximations that alter
expected energy. `StableBiased` may clamp history/sample weights or reuse
visibility for lower variance, but the chosen bias and clamp counters are
visible in captures. Product profiles never silently change correctness mode.

## 5. Canonical light and sample identity

Lighting publishes a structure-of-arrays `LightingView` containing stable light
symbol, generation/revision, kind, transform, emitted power, shape, range,
channels, cookie/IES generation, mobility, bounds, and sampling metadata. Paths
and display names never identify a light.

An analytic-light sample stores the stable light symbol/revision and canonical
shape coordinates. An emissive sample additionally stores mesh-light cluster,
primitive symbol, barycentric coordinates, Material emission generation, and
the complete source probability needed by the estimator. Reservoirs may use
compact frame-local indices internally only while carrying enough generation
data to reject reuse after table reorder or slot reuse.

Light removal creates a tombstone for the active history window. World unload,
Asset hot reload, Material emission changes, animation/deformation, and origin
rebase increment the relevant revisions. A similarly named light can never
inherit another light's reservoir.

## 6. Candidate generation

Spectrum combines several proposal distributions instead of trusting one global
uniform list:

1. screen-cluster candidates from Lighting's coarse geometric culling;
2. global power-weighted analytic-light alias tables;
3. hierarchical light-tree candidates using bounds, cone, power, and distance;
4. emissive mesh clusters cooked by Assets and refined to a surface sample;
5. Aether sun/sky/environment candidates where direct environment sampling is
   enabled;
6. the reprojected temporal reservoir;
7. compatible reservoirs from nearby pixels or tiles;
8. a small exploration proposal that prevents newly relevant lights from being
   starved by old history.

Every proposal reports its source probability. Mixture selection and target
weights are mathematically paired; a heuristic importance score cannot be
substituted as a PDF. Zero/NaN/negative probability, non-finite emitted power,
or mismatched light revision rejects the candidate and increments diagnostics.

Candidate tables rebuild incrementally by Lighting/World revision. Large static
tables use immutable generations; dynamic changes update a bounded delta layer
until background compaction publishes a replacement. Streaming publishes every
light/material dependency before its sampling record becomes visible.

## 7. Reservoir pipeline

For each opaque shading point Spectrum performs:

1. reconstruct and validate surface position, normals, Material closure,
   roughness, motion, depth, channels, and view identity;
2. generate initial candidates from the active proposal mixture;
3. evaluate each candidate's unshadowed target contribution and source PDF;
4. update one bounded reservoir with selected sample, weight sum, represented
   sample count, and source/generation metadata;
5. reproject the previous reservoir and validate surface/light/history identity;
6. combine it with the current reservoir using the selected correctness rule;
7. resample a bounded neighborhood with depth/normal/material compatibility;
8. evaluate visibility only for the final selected sample unless the configured
   estimator requires earlier visibility;
9. shade direct diffuse/specular lobes and write moments/confidence;
10. denoise/reconstruct under strict disocclusion and energy-clamp diagnostics.

The reservoir stores one representative sample, not the accumulated radiance of
every light. Weight normalization, represented sample count, Jacobians for
reused area samples, and visibility treatment follow one documented estimator
version. Shader/compiler tests compare every optimized path against a slow CPU
reference and path-traced images.

Spatial reuse never crosses view, Material discontinuity, incompatible normal,
large depth separation, receiver channel, or world-generation boundaries.
Stereo/XR views maintain independent reservoirs unless a validated cross-view
mapping is explicitly implemented.

## 8. Temporal stability and invalidation

History identity includes view/camera-cut generation, pixel-to-surface symbol,
geometry and Material revisions, previous/current transform, light-table
generation, World origin generation, render resolution, jitter sequence,
Spectrum mode/correctness, and visibility-provider generation.

History is rejected on disocclusion, camera cut, teleport, invalid motion,
surface/channel change, light revision mismatch, missing residency, large
roughness/normal change, or quality transition. A history reset increases noise
temporarily but never reuses stale energy. New lights receive explicit
exploration samples so temporal reuse cannot hide them for many frames.

Fireflies are controlled first through better proposals and robust PDFs. The
stable-biased tier may clamp reservoir age, represented sample count, or
contribution, but reports clamped energy and affected pixels. Temporal denoising
uses direct-light diffuse/specular signals separately and never borrows across
invalid surface boundaries.

## 9. Ray-traced area-light shadows

For a rectangle, disk, line, sphere, or emissive triangle, Spectrum samples an
actual point/direction on the finite emitter. The selected sample defines a
finite shadow segment from an offset receiver point to that emitter point.
Shadows evaluates this request through the shared Render ray scene and returns
opaque/alpha-tested visibility plus optional transmittance when the selected
quality supports it.

Spectrum owns the soft-shadow estimator: different samples across pixels/frames
integrate the emitter's angular extent. Shadows owns caster masks, sidedness,
alpha-test intersection policy, ray epsilon rules, acceleration-resource use,
and typed visibility failure. GPU owns acceleration-structure resources; Render
owns the immutable ray-scene instance view assembled from World, Shard,
Animation, Foliage, Cloth, and Destruction contributors.

One selected light sample normally needs one visibility ray. Higher modes may
trace extra rays for high-variance large/near emitters under a tile/frame budget.
Ray sorting/compaction groups coherent requests. Alpha testing uses bounded
intersection work and resident opacity data; missing alpha data selects an
explicit opaque/fallback policy rather than an unbounded texture wait.

## 10. Hybrid shadow-map path

Ray queries are not mandatory. Spectrum can request visibility from:

- virtual shadow pages for directional and important local lights;
- conventional cascades/atlases on portable targets;
- full-resolution maps selected for the lights currently winning reservoirs;
- low-resolution/imperfect maps for the remaining candidates;
- screen-space contact visibility as a labeled local enhancement, never the
  only off-screen solution.

Reservoir-selected shadow-map allocation is useful when thousands of lights
cannot each own a full map. Spectrum supplies selected-light demand and temporal
importance; Shadows owns map allocation, rendering, caching, invalidation, and
visibility sampling. Missing map detail falls back to a coarser map or declared
unshadowed policy and is counted.

## 11. Rendering integration

Required inputs:

- Lighting light/emissive sampling views and channel masks;
- Material closure parameters and emission;
- depth, geometric/shading normals, roughness, motion vectors, object/surface
  symbols, previous transforms, exposure, and camera-cut generation;
- Render ray-scene view or Shadows map visibility;
- World/Streaming generation and residency data;
- deterministic per-view stochastic sequence.

Outputs:

- direct diffuse and specular radiance;
- selected light/sample identity and hit distance where available;
- first/second moments, variance, confidence, history age, and rejection mask;
- light-demand feedback for Shadows and Streaming;
- optional tile summaries for transparent, volumetric, Fluids, Particles, and
  Foliage adapters.

Spectrum contributes passes after Material/depth/motion preparation and before
Radiance composition/transparency/PostFX. Radiance may consume Spectrum's
selected direct-light samples as candidates, but its reservoirs and indirect
paths remain separate. Spectrum output uses the same exposure/pre-exposure
contract as the rest of Lighting.

## 12. Transparency, particles, and volumetrics

The first release shades opaque surfaces. Transparent surfaces cannot safely use
opaque depth/motion history, so the portable adapter uses per-tile stochastic
light lists or conventional clusters with capped samples. Later per-fragment or
per-layer reservoirs require stable transparent surface identity and bounded
memory.

Particles and Foliage receive compact tile/cluster sample sets and can choose
unshadowed, map-visible, or ray-visible quality. Volumetrics use a separate
froxel reservoir/temporal model because phase functions and transmittance differ
from surfaces. These adapters reuse the Lighting source data but do not pretend
an opaque surface reservoir is universally valid.

## 13. Capability tiers and fallback

- no compute/storage buffers: Lighting's deterministic Forward+/deferred
  clustered evaluation under a declared per-cluster cap;
- compute but no ray queries: stochastic/reservoir sampling with Shadows maps;
- no reliable motion vectors: current-frame candidates plus spatial reuse only;
- no subgroup/wave operations: ordinary compute kernels with lower candidate
  budgets;
- constrained mobile/tile GPU: per-tile reservoirs, half resolution, compact
  light records, sampled atlases, and no acceleration-structure requirement;
- exhausted reservoir memory: reduce resolution/history/candidates in a fixed
  quality ladder, then fall back to clustered lighting;
- headless/server: Spectrum disabled and light authoring remains available for
  tools or non-rendering policy without GPU allocation.

The resolved capability tier is immutable for a frame and recorded in Profiler
and captures. Device loss destroys provider resources, resets histories, and
rebuilds from Lighting/Render generations without changing gameplay lights.

## 14. Budgets and scheduling

Separate budgets cover visible light records, candidate-table updates,
reservoir/history bytes, initial/spatial candidates, shadow rays, acceleration
updates, sampled shadow maps, denoising, and total GPU milliseconds. Adaptive
quality may alter only dimensions allowed by the active product profile and uses
hysteresis; it never changes serialized settings or correctness silently.

GPU work is decomposed into light-table update, initial sampling, temporal
reuse, spatial reuse, visibility compaction/trace, final shading, moments, and
denoising passes. Async compute is used only when Render/GPU hazard analysis and
measured overlap justify it. No pass performs a synchronous GPU readback.

## 15. Diagnostics and testing

Debug views show light bounds/power, proposal source, candidate counts/PDFs,
selected light/sample, reservoirs, represented sample count, temporal/spatial
acceptance, history age/rejection, ray segments/hits, map fallback, direct
diffuse/specular, variance, denoiser footprint, and clamped/biased pixels.

Profiler counters include visible/changed lights, emissive clusters, candidate
table rebuild/compaction, candidates per pixel, proposal acceptance, reservoir
reuse, history rejection cause, rays, ray hits/misses, alpha intersections,
sampled shadow maps, fallback pixels, memory, per-pass GPU time, and estimated
variance/error against reference captures.

Required tests include:

- one-light and small-light scenes matching deterministic Lighting references;
- equal-power symmetry, inverse-square falloff, area-light PDF/Jacobian checks,
  and energy conservation;
- 1,000/10,000/100,000 moving-light stress scenes with bounded memory/time and
  no fixed-index corruption;
- same-named lights with independent symbols and reservoir histories;
- newly appearing, disappearing, moving, occluded, and streaming lights;
- camera cuts, disocclusion, origin rebase, dynamic resolution, and mode change;
- rectangle/disk/line/emissive soft-shadow penumbrae against path-traced images;
- alpha-tested foliage, deforming/skinned casters, thin geometry, and missing
  opacity residency;
- unbiased statistical convergence and explicitly measured stable-biased error;
- Metal, Vulkan, D3D12, Web/mobile fallback, XR multi-view, and device loss;
- fuzzed non-finite light data, capacity overflow, and corrupt cooked tables.

## 16. Delivery

1. LightingView integration, stable light/sample identity, deterministic
   candidate tables, and clustered/reference validation path.
2. current-frame stochastic direct sampling with analytic/area/emissive lights,
   moments, debug views, and shadow-map visibility.
3. temporal/spatial reservoirs, strict invalidation, disocclusion handling,
   diffuse/specular reconstruction, and unbiased reference tests.
4. shared Render/GPU ray scene, ray-query visibility, area-light soft shadows,
   alpha-tested casters, and adaptive ray budgets.
5. reservoir-selected virtual shadow maps, transparent/particle/volumetric
   adapters, mobile/XR tiers, and production performance hardening.

Acceptance requires thousands of fully dynamic lights without cluster truncation
artifacts in Spectrum modes; statistically validated direct energy; ray-traced
area-light penumbrae; bounded queues/memory/rays; explicit portable fallback;
stable motion/streaming behavior; and per-pass Profiler/Debug evidence.

## 17. Technical references

- [Spatiotemporal Reservoir Resampling for Real-time Ray Tracing with Dynamic
  Direct Lighting](https://research.nvidia.com/labs/rtr/publication/bitterli2020spatiotemporal/)
- [Generalized Resampled Importance Sampling: Foundations of ReSTIR](https://research.nvidia.com/labs/rtr/publication/lin2022generalized/)
- [Many-Light Rendering Using ReSTIR-Sampled Shadow Maps](https://research.nvidia.com/labs/rtr/publication/zhang2025many-light/)
- [NVIDIA RTXDI reference implementation](https://github.com/NVIDIA-RTX/RTXDI)
- [Apple Metal ray tracing with acceleration structures](https://developer.apple.com/documentation/metal/ray-tracing-with-acceleration-structures)
