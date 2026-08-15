# Azora Particles — CPU and GPU Particle System

Status: Proposal
Primary package: `azora-particles`
Primary module: `engine.particles`

## 1. Decision

Particles provides one authored effect graph with two execution domains: a
deterministic CPU runtime for gameplay-significant particles and a high-volume
GPU runtime for visual particles. Domains may exchange explicit events, but a
GPU particle never silently becomes authoritative gameplay state.

## 2. Current engine audit

No particle package exists. Current GPU code has immediate triangles, meshes,
rectangles, and text but no compute abstraction, indirect draws, storage
buffers, render graph, sorting, or transient resource allocator. ECS and events
can already host CPU emitters. Physics exposes primitive queries but no batched
world query. The first release can therefore ship CPU particles before GPU
simulation is available.

## 3. Public model

```azora
pack ParticleEffectId {
    fin value: std::Long
}

enum ParticleDomain {
    Cpu
    Gpu
}

enum ParticleRenderer {
    Sprite
    Mesh
    Ribbon
    Beam
    Volume
}

@Component
pack ParticleEmitter {
    fin effect: ParticleEffectId
    var rate: std::Double
    var seed: std::Long
    var enabled: std::Bool
    var timeScale: std::Double
}

@Resource
pack ParticleSettings {
    var maxCpuParticles: std::Int
    var maxGpuParticles: std::Int
    var simulationSteps: std::Int
    var sortBudget: std::Int
}

@Event
pack ParticleEvent {
    fin emitter: Entity
    fin code: std::Int
    fin position: Vec3
    fin generation: std::Long
}
```

## 4. Effect graph

An effect contains typed stages: spawn, initialize, update, event, render, and
bounds. Nodes are pure kernels over channels such as position, velocity, age,
lifetime, color, size, rotation, custom values, and stable particle ID. The
compiler validates stage legality and can produce CPU vector code or GPU shader
IR from supported nodes.

Effect parameters use stable symbols. Names are labels and may repeat in nested
modules. Randomness is counter-based from effect, emitter, spawn sequence, and
particle IDs so CPU runs are reproducible independent of worker scheduling.

## 5. CPU simulation

CPU particles use structure-of-arrays chunks and a fixed simulation timestep.
Systems process emitters in parallel while preserving deterministic event order
by emitter symbol and spawn sequence. CPU particles can run collision queries,
emit ECS events, damage actors, and replicate through Networking when explicitly
marked authoritative.

## 6. GPU simulation

The GPU path uses free/dead lists, append/consume counters, bounded spawn
requests, indirect draw arguments, and frame-graph resources. It supports forces,
noise, vector fields, depth/normal collision, signed-distance/voxel collision,
curl fields, events copied to a bounded readback queue, and optional sorting.

Overflow follows effect policy: drop newest, drop oldest, reduce emission, or
replace low-importance particles. Every choice is counted. GPU readback events
are delayed and never appropriate for frame-exact gameplay.

## 7. Rendering

Sprite particles support camera-facing, axis-locked, velocity-aligned, and world
oriented modes. Ribbons retain stable trail IDs and discontinuity markers. Mesh
particles integrate Material and conventional or Shard meshes. Transparent
sorting may be per-particle, per-tile, approximate, or disabled by effect.

Lighting uses the shared clustered light buffers. Particle lights are a bounded
output list consumed by Lighting next frame. Shadows are opt-in and budgeted.
Motion vectors and reactive masks are provided to PostFX.

## 8. Integration

- Aether adapters create precipitation and wind fields.
- Destruction adapters create debris/dust events.
- Fluids supplies surface and underwater collision fields.
- Physics provides batched CPU queries; GPU depth/voxel collision is visual.
- Audio consumes explicit effect events, not individual visual particles.
- Streaming prewarms effects and referenced materials/textures.

## 9. Diagnostics and delivery

Debug views show bounds, emitter states, channel values, alive/dead lists,
collision fields, sort tiles, and overdraw. Profiler counters include spawns,
alive count, overflow, simulation time, render time, sorting, readbacks, events,
memory, and culled effects.

Delivery:

1. deterministic CPU emitters, sprite renderer, curves, events, pooling.
2. graph compiler and CPU vector execution.
3. GPU simulation, indirect sprite/mesh rendering, and bounded overflow.
4. ribbons, beams, depth/field collision, Lighting/PostFX integration.
5. vector fields, effect scalability, editor debugger, and network/replay policy.
