# Azora Cloth — Cloth, Rope, Soft Body, Hair, and Fur Simulation

Status: Proposal
Primary package: `azora-cloth`
Primary module: `engine.cloth`

## 1. Decision

Cloth uses position-based dynamics with extended constraints (XPBD) as the
shared solver foundation for cloth, rope, and selected soft bodies. CPU and GPU
providers implement one asset/constraint contract. CPU mode supports
authoritative interaction and stable replay tiers; GPU mode targets visual
density. Hair and fur build on strand constraints later, not on a separate
incompatible simulation API.

## 2. Current engine audit

No cloth package exists. Physics has primitive math but no world/collision scene.
Animation has skeleton poses and skin matrices suitable for attachment targets.
GPU has no compute/storage-buffer abstraction. Rendering has no dynamic mesh or
motion-vector path. The first milestone can implement a CPU rope/cloth reference
solver independent of final rendering.

## 3. Public model

```azora
pack ClothAssetId {
    fin value: std::Long
}

enum ClothDomain {
    Cpu
    Gpu
}

enum ClothKind {
    Surface
    Rope
    SoftBody
    Hair
    Fur
}

@Component
pack Cloth {
    fin asset: ClothAssetId
    fin kind: ClothKind
    var domain: ClothDomain
    var enabled: std::Bool
    var timeScale: std::Double
}

@Component
pack ClothAttachment {
    fin clothParticle: std::Int
    fin targetBone: BoneId
    var compliance: std::Double
}

@Resource
pack ClothSettings {
    var substeps: std::Int
    var iterations: std::Int
    var cpuParticleBudget: std::Int
    var gpuParticleBudget: std::Int
}
```

## 4. Assets and constraints

Cloth assets contain simulation particles, render binding, inverse masses,
stretch/shear/bend/area/volume constraints, seams, attachments, collision
thickness, damping, drag, pressure, tearing thresholds, material regions, and
LOD maps. Render vertices bind to simulation triangles or tetrahedra so the
simulation mesh can be much coarser than visible geometry.

Constraint symbols remain stable for tear/network/replay records. Display names
are never identity.

## 5. Solver

Each fixed/substep predicts positions, applies external acceleration and Aether
wind, solves attachments, shape/volume constraints, self collision, environment
collision, and velocity update, then computes normals/tangents and render
binding. XPBD compliance makes stiffness less dependent on timestep/iterations.

CPU islands run through Jobs. GPU simulation uses graph-managed buffers and
color-partitioned constraints or atomics by capability. Cross-domain migration
is explicit and may reset high-frequency state.

## 6. Collision and coupling

Animation publishes current/previous bone targets before Cloth. Physics supplies
simple body shapes and a query snapshot; cloth reaction forces back to rigid
bodies are optional and CPU-authoritative. GPU cloth may collide against depth,
signed distance, Voxels, and uploaded primitive fields but cannot silently apply
authoritative rigid-body impulses.

Self collision uses spatial hashing and a strict pair budget. Tunneling-sensitive
attachments/ropes can enable swept tests.

## 7. Tearing, ropes, soft bodies, hair

Tearing breaks authored constraint edges and switches render seams using
precomputed topology variants initially. Fully dynamic mesh cutting is later.
Ropes use distance/bend/twist constraints and optional Physics end constraints.
Soft bodies use volume/tetrahedral shape constraints. Hair uses guide strands,
strand interpolation, root attachments, and group collision; fur may render
procedural follower strands without simulating each one.

## 8. LOD, diagnostics, and delivery

LOD changes solver frequency, particles, constraints, self collision, collision
sources, and render followers. Off-screen cloth can sleep or animate from a
coarse proxy. Critical ropes retain CPU simulation even when invisible.

Debug views show particles, constraints by error, attachments, collision pairs,
self-collision grid, sleeping, LOD, tears, and render binding. Counters include
particles, constraints, iterations, collision pairs, GPU/CPU time, tears,
sleeping instances, and memory.

Delivery:

1. CPU XPBD rope/surface solver, assets, attachments, reference tests.
2. Physics primitive collision, Animation binding, dynamic mesh rendering.
3. GPU provider, self collision, wind, motion vectors, LOD.
4. tearing, soft bodies, rigid-body coupling, networking/replay tiers.
5. hair guide strands, fur followers, advanced collision, editor painting/tools.
