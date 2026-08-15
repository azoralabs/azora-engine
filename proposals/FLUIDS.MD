# Azora Fluids — Oceans, Rivers, Lakes, and Buoyancy

Status: Proposal
Primary package: `azora-fluids`
Primary module: `engine.fluids`

## 1. Decision

Fluids separates surface description, visual simulation, and gameplay queries.
Oceans use spectral waves and camera-centered geometry; rivers use spline flow
and shallow-water data; lakes use bounded surfaces with optional local
simulation. All expose one versioned water-query contract for height, normal,
velocity, depth, and body identity.

## 2. Current engine audit

No water package exists. Roads can establish the spline approach, Landscape the
shore/terrain contract, Material the water closure, and Physics the future force
world. Current rendering cannot render reflection/refraction targets or compute
waves. An initial CPU Gerstner-wave ocean can be built before FFT compute.

## 3. Public model

```azora
pack FluidBodyId {
    fin value: std::Long
}

enum FluidBodyKind {
    Ocean
    River
    Lake
    Pool
}

@Component
pack FluidBody {
    fin id: FluidBodyId
    fin kind: FluidBodyKind
    var level: std::Double
    var density: std::Double
    var enabled: std::Bool
}

@Component
pack Buoyant {
    var volume: std::Double
    var drag: std::Double
    var angularDrag: std::Double
    var sampleCount: std::Int
}

pack FluidSample {
    fin valid: std::Bool
    fin body: FluidBodyId
    fin position: Vec3
    fin normal: Vec3
    fin velocity: Vec3
    fin depth: std::Double
    fin generation: std::Long
}
```

## 4. Surface systems

Ocean waves use deterministic spectral seeds, directional spectra, multiple
cascades, inverse FFT displacement, normals, foam, and velocity. Low tiers use
a finite analytic wave set. The rendering mesh is camera-relative rings or
Shard-compatible patches with horizon-safe precision.

Rivers are spline networks with width, depth, bank, discharge, and flow curves.
Junctions conserve flow approximately and generate stable surface patches.
Lakes are polygons or Landscape-defined basins with a level and optional shallow
water grid.

## 5. Rendering

Material supplies absorption, scattering, roughness, foam, caustic, and surface
parameters. Radiance provides reflections when available; screen-space and
probe fallbacks remain valid. Refraction uses scene color/depth with explicit
order in the render graph. Aether supplies sky and wind. PostFX receives an
underwater mask, depth, and reactive motion data.

Underwater rendering has separate fog/scattering, surface underside, caustics,
audio environment, and camera transition policy. Camera crossing uses hysteresis
to prevent one-frame toggling on waves.

## 6. Gameplay and physics

Fluid queries run against the same generation used for visual waves. Analytic
waves are sampled exactly on CPU; spectral waves publish compact query spectra
or delayed readback chosen by quality. Buoyancy samples displaced volume points,
applies Archimedes force, relative-flow drag, and torque through Physics.

Large vessels may request hull slices or hydrostatic integration. Vehicle owns
boat controls and propulsion; Fluids owns fluid samples and buoyancy forces.

## 7. Shore and interaction

Landscape provides depth/shore distance fields. Foam combines wave breaking,
shore distance, curvature, and object interaction. Dynamic wakes enter bounded
local simulation tiles keyed by water body and World cell. Rain and objects add
impulses; tiles decay and stream independently.

## 8. Diagnostics and delivery

Debug views show bodies, spline flow, wave cascades, displacement, velocity,
shore distance, foam, reflection source, underwater state, buoyancy samples,
and local interaction tiles. Counters include FFT time, triangles, reflection
time, query count, buoyant bodies, interaction tiles, memory, and fallbacks.

Delivery:

1. water bodies, analytic waves, queries, basic Material, and buoyancy adapter.
2. river/lake geometry, shore data, foam, refraction, and underwater rendering.
3. spectral ocean compute, cascades, velocity, and Radiance integration.
4. local wakes/ripples, shallow water, river junctions, and Aether precipitation.
5. advanced vessels, networking/replay policy, and large-world streaming.
