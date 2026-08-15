# Azora Physics — Unified 2D and 3D Simulation

Status: Proposal building on partial implementation
Packages: `azora-physics-core`, `azora-physics-2d`, `azora-physics-3d`
Modules: `engine.physics.core`, `engine.physics.d2`, `engine.physics.d3`

## 1. Decision

Keep the existing dimension-neutral core plus independent 2D and 3D worlds.
Both worlds share lifecycle, layers, materials, sleeping, fixed-step policy,
events, query semantics, determinism controls, and profiling, but use
dimension-appropriate broad phases, narrow phases, inertia, constraints, and
data layouts. The legacy `azora-physics` package becomes compatibility sugar and
must not evolve into a second engine.

## 2. Current implementation audit

Implemented and tested today:

- common `RigidBodyKind`, `ForceMode`, `PhysicsMaterial`, `CollisionLayers`,
  `Damping`, `Sleeping`, `Sensor`, `GravityScale`, and `PhysicsSettings`;
- layer interaction, inverse-mass, force scaling, sleeping, timestep helpers;
- 2D box/circle/capsule descriptors, transforms, velocities, forces, rigid body
  mass/inertia, AABBs, box/circle overlap, box sweep, ray-box, slide/bounce, and
  penetration helpers;
- 3D box/sphere/capsule descriptors, transforms, linear/angular velocity,
  inertia vectors, AABBs, box/sphere overlap, box sweep, box/sphere rays, and
  penetration helpers;
- deterministic unit tests for those mathematical primitives.

Not implemented as a physics world:

- collider registry or spatial broad phase;
- automatic integration ECS systems;
- pair cache, manifolds, persistent contacts, iterative impulses, friction, or
  restitution solving;
- capsule narrow phase in all combinations, convex hulls, polygons, triangle
  meshes, heightfields, compounds, joints, character controllers, or CCD;
- collision start/stay/end events and batched scene queries;
- multithreaded islands, snapshots, rollback, or backend providers.

The proposal preserves the tested primitives and fills those gaps.

## 3. Package model

```text
azora-physics-core  -> core, ecs, math
azora-physics-2d    -> physics-core
azora-physics-3d    -> physics-core
azora-physics       -> compatibility re-exports only
```

Optional adapters (`physics-landscape`, `physics-voxels`, `physics-shard`) depend
on both sides and keep heavyweight geometry out of the core packages.

## 4. Public world model

```azora
@Resource
pack PhysicsWorld2D {
    var generation: std::Long
    var settings: PhysicsSettings
    var gravity: Gravity2D
    var stats: PhysicsStats
}

@Resource
pack PhysicsWorld3D {
    var generation: std::Long
    var settings: PhysicsSettings
    var gravity: Gravity3D
    var stats: PhysicsStats
}

@Component
pack PhysicsHandle2D {
    fin id: std::Int
    fin generation: std::Int
}

@Component
pack PhysicsHandle3D {
    fin id: std::Int
    fin generation: std::Int
}

variant enum CollisionEvent2D {
    Began(Contact2D)
    Persisted(Contact2D)
    Ended(ContactPair2D)
}

variant enum CollisionEvent3D {
    Began(Contact3D)
    Persisted(Contact3D)
    Ended(ContactPair3D)
}
```

ECS components remain the authoring/gameplay interface. Private world handles
map entities to dense solver bodies; they are invalidated by generation and are
never serialized.

## 5. Fixed-step schedule

1. apply deferred body/collider changes;
2. copy authoritative kinematic transforms into the physics world;
3. accumulate forces and controllers;
4. update broad-phase proxies and candidate pairs;
5. generate/refresh narrow-phase manifolds;
6. build independent constraint islands;
7. integrate velocity and solve velocity constraints;
8. integrate position and solve penetration constraints;
9. run CCD/TOI corrections;
10. update sleeping and publish events;
11. write dynamic transforms/velocities back to ECS;
12. preserve previous transforms for render interpolation.

Large frame deltas clamp and run bounded substeps using the existing settings.
The engine reports dropped simulation time; it never hides an unbounded catch-up.

## 6. Broad and narrow phase

The default dynamic broad phase is a fat-AABB tree; static geometry uses a
separate BVH. A sweep-and-prune provider may be selected for dense axis-aligned
2D scenes. Pair keys are sorted body/collider symbols for stable cache order.

2D adds oriented boxes, convex polygons, chains, compounds, and SAT/GJK support.
3D adds oriented boxes, capsules, convex hulls, compounds, triangle meshes, and
heightfields using GJK/EPA or specialized pairs. Dynamic triangle meshes are
rejected initially; callers use convex decomposition or kinematic compounds.

Manifolds persist feature IDs and warm-start impulses across fixed steps.

## 7. Solver and constraints

The default solver is sequential impulse with split penetration correction,
static/dynamic friction, restitution threshold, warm starting, island sleeping,
and configurable velocity/position iterations. Constraints include distance,
spring, revolute/hinge, prismatic, fixed, cone-twist, gear, and motors where
dimensionally meaningful.

Constraint order is stable in deterministic mode. Parallel mode executes
independent islands concurrently through `engine.jobs`.

## 8. Queries

Ray, shape cast, overlap, point, and nearest queries accept collision layers,
sensor policy, exclusions, maximum hits, and stable sort policy. Immediate
queries read the last committed world. Scheduled batched queries execute between
simulation stages and return tickets, avoiding arbitrary locks.

Results contain entity, collider symbol, feature, position, normal, distance,
material, and world generation. Display names are never used for identity.

## 9. Determinism and rollback

`Fast` permits parallel islands and platform floating-point variation.
`Stable` fixes ordering and math mode for replay on the same target family.
`Rollback` additionally supports bounded snapshots, deterministic allocation,
fixed configuration, and checksums. Cross-architecture bit identity is a
separate tested capability, not an implicit promise.

Networking owns rollback orchestration; Physics exposes snapshots and resimulate.

## 10. Diagnostics and delivery

Debug draw covers colliders, AABBs, tree depth, pairs, manifolds, impulses,
joints, sleeping, CCD sweeps, islands, and query rays. Profiler counters include
bodies, colliders, pairs, manifolds, islands, iterations, sleeping, query counts,
CCD events, broad/narrow/solver time, and snapshot bytes.

Delivery:

1. ECS synchronization, body registries, fixed-step integration, broad phases.
2. persistent contacts and impulse solver for currently supported shapes.
3. events, queries, joints, capsules/convexes, compounds, static mesh/heightfield.
4. CCD, character controller, multithreaded islands, Landscape/Voxel adapters.
5. snapshot/rollback tiers, backend conformance suite, and editor inspection.
