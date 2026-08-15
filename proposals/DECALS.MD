# Azora Decals — Projected and Mesh-Bound Surface Layers

Status: Proposal
Primary package: `azora-decals`
Primary module: `engine.decals`

## 1. Decision

Decals are bounded Material-layer projections with stable lifetime and receiver
policy. The default deferred path writes decal material channels before
Lighting; a forward receiver path supports transparent/special materials; mesh
decals handle roads and silhouette-sensitive placement. Decals never modify the
underlying material asset or geometry.

## 2. Current engine audit

There is no decal system, G-buffer, off-screen pass, depth reconstruction, or
Material layering. Immediate rendering could draw explicit overlay geometry but
cannot correctly project onto arbitrary surfaces. The first implementation
therefore follows Material and the frame graph.

## 3. Public model

```azora
pack DecalId {
    fin value: std::Long
}

enum DecalProjection {
    Box
    Sphere
    Mesh
}

enum DecalBlend {
    Color
    Normal
    Roughness
    Emissive
    FullMaterial
}

enum DecalPurpose {
    SurfaceDetail
    Dirt
    Damage
    RoadMarking
    Graffiti
    Footprint
    Custom
}

@Component
pack Decal {
    fin id: DecalId
    fin material: MaterialId
    fin projection: DecalProjection
    fin purpose: DecalPurpose
    var blend: DecalBlend
    var opacity: std::Double
    var priority: std::Int
    var fadeDistance: std::Double
}

@Component
pack DecalReceiver {
    var channels: std::Int
    var enabled: std::Bool
}
```

## 4. Projection and blending

Projected decals reconstruct receiver position from depth, transform it into
decal local space, reject outside volume and back-facing surfaces by policy, then
evaluate a restricted decal Material closure. Normal blending uses a defined
tangent or derivative basis. Channel writes are explicit; a color-only decal
cannot accidentally flatten normal or roughness.

Overlaps sort by priority, stable decal symbol, and creation sequence. Blending
is deterministic within a tile. A per-tile cap uses importance/fade ranking and
reports overflow.

## 5. Storage and lifetime

Static decals are compiled into World cells and can be clustered. Dynamic decals
use a pooled component plus lifetime/fade. Persistent gameplay marks store decal
symbols and parameters, not transient render indices. Networking/replay policy
is explicit because cosmetic blood/dirt often need not replicate.

Authored decals live in Scene/Prefab records and reference Material/texture
assets by `AssetId`. Save records only persistent runtime additions/removals and
their stable receiver/object attachment. Streaming owns material/texture
residency; a missing high-detail decal uses its declared fallback rather than
stalling publication of a World cell.

Road markings normally use Roads-owned spline/lane semantics to generate mesh
decals, preventing projection stretching and preserving marking identity across
road recooks. Dirt can be accumulated/erased by gameplay masks without mutating
the base Material. Damage decals may attach to Physics hit records, Destruction
fragments, or skeletal bone symbols and follow their target without copying the
material.

## 6. Rendering paths

- deferred/visibility path: tile-cull decals and write D-buffer channels;
- forward path: receiver samples clustered decal lists during Material evaluation;
- mesh path: generated overlay geometry with depth offset and Material layer;
- low tier: pre-baked static decals plus capped dynamic mesh quads.

Shard instances remain receivers by stable instance/surface symbols. Decals do
not force Shard source geometry to become mutable.

## 7. Diagnostics and delivery

Debug views show bounds, receiver channels, tile lists, sort order, blend
channels, overdraw, clipped/backface rejection, and residency. Counters include
visible decals, tiles touched, overflow, D-buffer memory, material samples,
static/dynamic counts, and GPU time.

Delivery:

1. mesh decals, lifetime, receiver channels, and basic Material blending.
2. projected box decals over depth with color/normal/roughness channels.
3. tiled culling, D-buffer, stable ordering, and World streaming.
4. Shard receivers, skeletal attachment, Roads/Destruction adapters.
5. forward transparent receivers, persistence/network policy, and editor tools.
