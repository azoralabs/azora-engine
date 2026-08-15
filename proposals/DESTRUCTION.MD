# Azora Destruction — Fracture and Runtime Breakage

Status: Proposal
Primary package: `azora-destruction`
Primary module: `engine.destruction`

## 1. Decision

Destruction uses precomputed fracture collections for predictable high-quality
breakage and bounded runtime fracture for selected geometry. A destruction asset
stores a hierarchy of pieces, bonds, support, collision proxies, render pages,
material interiors, and event metadata. Runtime simulation breaks bonds and
activates only relevant pieces; it does not spawn every fragment as a permanent
entity at load.

## 2. Current engine audit

No destruction package exists. Physics has no world or joints, rendering has no
mesh asset/streaming system, and ECS can provide entity promotion and events.
Shard, Particles, Audio, Decals, World, and Streaming proposals define the
required adapters.

## 3. Public model

```azora
pack DestructionAssetId {
    fin value: std::Long
}

pack DestructionPieceId {
    fin value: std::Long
}

@Component
pack Destructible {
    fin asset: DestructionAssetId
    var health: std::Double
    var damageThreshold: std::Double
    var generation: std::Long
}

@Component
pack DestructionPiece {
    fin root: Entity
    fin piece: DestructionPieceId
    var active: std::Bool
}

@Event
pack FractureEvent {
    fin root: Entity
    fin generation: std::Long
    fin position: Vec3
    fin energy: std::Double
    fin brokenBonds: std::Int
}
```

## 4. Asset build

Offline tools perform Voronoi, radial, planar, clustered, or authored fracture;
generate interior surfaces/material coordinates; build a piece hierarchy;
compute bonds from shared area/material; identify supports; simplify collision;
and package render/collision LODs. Piece and bond symbols derive from build
topology and remain stable while compatible edits preserve them.

Runtime fracture is restricted to bounded convex or voxel-assisted regions and
may produce a non-deterministic authoritative snapshot rather than pretending
all platforms generated identical cuts.

## 5. Runtime lifecycle

Intact objects render as one conventional or Shard representation. Damage maps
to bonds by impulse, radius, direction, material toughness, and propagation.
Disconnected hierarchy nodes become active clusters; only visible/nearby
clusters are promoted to Physics bodies and ECS entities. Tiny debris remains a
GPU Particles effect or merges into aggregate rubble.

Sleeping, distant, or settled pieces can freeze into a static rubble instance,
merge collision, or expire by policy. Persistent structural pieces retain stable
state through World streaming.

## 6. Integration

Physics supplies contact impulses and simulates active pieces. Material supplies
interior/exterior layers. Shard renders static/intact pieces and immutable
fragments. Particles and Audio consume `FractureEvent`; Decals consumes impact
events. Traverse and World receive coarse obstacle/nav invalidation with
generation-atomic updates.

Networking sends authoritative damage/bond-break events for deterministic
prefractures and state snapshots for runtime fracture. Replay records the same.

## 7. Budgets and delivery

Budgets cap active bodies, promoted entities, broken bonds per step, generated
triangles, collision rebuilds, particles, audio events, and persistent state.
Importance ranking freezes or aggregates low-value debris before dropping
structural pieces.

Debug views show hierarchy, bonds, support graph, damage, active clusters,
collision proxies, sleeping/frozen pieces, and nav dirtiness. Counters include
damage events, bonds tested/broken, active pieces, bodies, generated triangles,
promotion/freeze time, memory, and network bytes.

Delivery:

1. prefractured assets, damage/bond graph, intact-to-piece rendering.
2. Physics activation, hierarchy clustering, events, pooling, debris budgets.
3. Shard/Material/Particles/Audio/Decals adapters and persistent World state.
4. nav/collision rebuilding, networking, replay, editor fracture tools.
5. bounded runtime fracture, voxel cuts, structural stress, and rubble merging.
