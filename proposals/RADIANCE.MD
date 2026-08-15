# Azora Radiance — Real-Time Global Illumination and Reflections

Status: Proposal
Primary package: `azora-radiance`
Primary module: `engine.radiance`

## 1. Decision

Radiance owns indirect diffuse illumination and specular reflections. It is a
hybrid, capability-driven system: hardware ray tracing uses reservoir-guided
sampling and ray queries; the portable path combines screen traces, signed
distance/voxel representations, and scrolling probe volumes. Both paths share
history validation, denoising, material response, diagnostics, and fallbacks.

Direct-light definitions remain in Lighting, scalable direct evaluation remains
in Spectrum, and shadow maps/direct visibility remain in Shadows. Radiance may
consume Spectrum outputs/sampling records and trace indirect/reflection
visibility, but it does not become the owner of direct lights or reservoirs.

## 2. Current engine audit

There is no GI, reflection, ray-tracing, probe-volume, temporal history, motion
vector, depth pyramid, normal/roughness buffer, or render graph today. The
current ambient scalar is a fixed approximation and becomes the lowest fallback
tier. Implementing Radiance therefore requires the proposed GPU resource model,
Material closure, Lighting table, motion vectors, and World/Streaming contracts.

## 3. Quality modes

```azora
enum RadianceMode {
    Disabled
    Ambient
    Probe
    Hybrid
    RayTraced
    PathTraced
}

@Resource
pack RadianceSettings {
    var mode: RadianceMode
    var diffuseRaysPerPixel: std::Int
    var reflectionRaysPerPixel: std::Int
    var historyFrames: std::Int
    var maxTraceDistance: std::Double
    var probeSpacing: std::Double
    var updateBudget: std::Int
}

@Component
pack RadianceVolume {
    var priority: std::Int
    var diffuseScale: std::Double
    var reflectionScale: std::Double
    var historyWeight: std::Double
}
```

`Auto` is deliberately absent from the serializable mode enum. Device policy
resolves an application quality profile to one concrete mode and records why.

## 4. Required inputs and outputs

Inputs: depth, geometric and shading normals, roughness, base color, emissive,
motion vectors, exposure, direct-light sampling records, sky radiance, world
instance bounds, and residency information.

Outputs:

- diffuse indirect radiance;
- prefiltered specular reflection radiance and hit distance;
- confidence, variance, and disocclusion masks;
- optional irradiance probe state for gameplay preview and fallback;
- debug reservoirs, rays, probe classifications, and rejection reasons.

Missing inputs select a declared fallback. For example, missing motion vectors
disable temporal reuse for the affected pixels rather than reprojecting stale
light.

## 5. Hardware path

The hardware path consumes Render's shared immutable ray-scene view, whose GPU
provider owns top- and bottom-level acceleration-structure resources. World and
Shard contribute stable instances/geometry proxies; deforming Animation/Cloth
geometry chooses refit, skinned proxy, or exclusion by quality tier. Radiance
owns its traversal/path state, not a duplicate scene acceleration hierarchy.

The sampling sequence is:

1. generate candidates from lights, emissives, sky, and prior reservoirs;
2. trace visibility and short indirect paths;
3. temporal reservoir reuse with strict surface validation;
4. spatial reuse with material/depth/normal compatibility;
5. evaluate selected paths;
6. demodulate, denoise, and remodulate;
7. prefilter reflections by roughness and hit distance.

Reservoir identity contains stable light/surface symbols, never object names or
transient array positions.

## 6. Portable path

The portable path combines:

- hierarchical screen-space traces for visible detail;
- scrolling world-aligned irradiance probes for off-screen diffuse light;
- optional sparse voxel or distance-field traces for off-screen occlusion;
- reflection probes for rough and unresolved specular rays;
- sky fallback when no representation is resident.

Probe updates are prioritized by camera distance, lighting change, invalidity,
and visible influence. Classification moves probes away from walls and marks
unreliable samples. World-cell unload invalidates only affected probe pages.

## 7. Temporal stability

History keys include camera cut generation, surface symbol, geometry revision,
material revision, world-origin generation, and resolution. History is rejected
on disocclusion, large normal/roughness change, residency loss, teleport, or
camera cut. Rejected history is visible in debug overlays.

The denoiser separates diffuse and specular signals, tracks moments, preserves
thin geometry, and avoids borrowing across material boundaries. PostFX owns
upscaling; Radiance publishes native and confidence resolutions.

## 8. Streaming and memory

Radiance has an explicit budget for acceleration structures, probe bricks,
history textures, reservoirs, and distance fields. Streaming publishes residency
before a representation is sampled and fence-completes eviction. A coarse
always-resident fallback prevents black flashes during cell transitions.

## 9. Failure and observability

```azora
error RadianceError {
    UnsupportedMode
    MissingInput
    BudgetExceeded
    AccelerationBuildFailed
    ShaderUnavailable
}
```

Profiler counters include rays, candidates, temporal/spatial acceptance,
disocclusions, probe updates, invalid probes, acceleration build/refit time,
history memory, traversal time, denoiser time, and fallback pixels.

## 10. Delivery

1. Required G-buffer/motion/history contracts and ambient/probe fallback.
2. scrolling diffuse probe volumes plus screen-space reflections.
3. sparse off-screen representation and robust temporal denoising.
4. hardware ray-traced reflections and one-bounce diffuse GI.
5. reservoir-guided multi-bounce path mode and offline reference validation.

Radiance quality is tested against path-traced reference scenes, camera cuts,
origin rebases, streaming churn, emissive motion, glossy-to-rough materials, and
thin geometry. Frame time and memory budgets are hard acceptance criteria.

## 11. Technical references

- [ReSTIR GI research paper](https://research.nvidia.com/publication/2021-06_restir-gi-path-resampling-real-time-path-tracing)
- [Apple Metal feature-set tables](https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf)
