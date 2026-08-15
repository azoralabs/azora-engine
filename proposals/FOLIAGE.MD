# Azora Foliage — Procedural Vegetation and Interaction

Status: Proposal
Primary package: `azora-foliage`
Primary module: `engine.foliage`

## 1. Decision

Foliage owns biome-driven placement, persistent instance identity, GPU culling,
wind deformation, interaction, seasonal variants, and harvesting/regrowth
state. It uses Shard or hardware instancing for geometry and Material for
foliage shading. Procedural computes placement candidates; Foliage applies
species ecology and runtime lifecycle.

## 2. Current engine audit

No foliage or generic instance package exists. Tilemap has sparse layers and
traits that can inform a future 2D foliage adapter, but the 3D renderer only has
individual immediate mesh draws. Animation has skeletal and 2D flipbook data,
yet no vertex wind deformation path. Foliage depends on GPU-driven rendering,
Landscape queries, World cells, and Streaming.

## 3. Public model

```azora
pack SpeciesId {
    fin value: std::Long
}

pack FoliageInstanceId {
    fin value: std::Long
}

pack Species {
    fin id: SpeciesId
    fin mesh: MeshAssetId
    fin material: MaterialId
    var minScale: std::Double
    var maxScale: std::Double
    var slopeLimit: std::Double
    var density: std::Double
}

@Component
pack FoliageRegion {
    fin seed: std::Long
    fin biome: BiomeId
    var densityScale: std::Double
    var enabled: std::Bool
}

@Component
pack FoliageActor {
    fin instance: FoliageInstanceId
    var health: std::Double
    var harvested: std::Bool
}
```

Ordinary visual instances live in compact cell buffers, not one ECS entity each.
An instance is promoted to an entity only while gameplay state, close-range
physics, or individual interaction requires it. Demotion writes persistent state
back to the cell record.

## 4. Placement

Placement is deterministic from world cell, species symbol, biome revision, and
seed. Rules sample Landscape material, slope, altitude, moisture, curvature,
distance fields, exclusion volumes, and neighboring species. Blue-noise or
Poisson candidates avoid obvious repetition. World cell borders use shared seed
domains so density does not seam.

Authored instances and procedural instances share IDs and rendering. Exclusion
and override layers are non-destructive and stream with the owning cell.

## 5. Rendering and wind

GPU culling groups instances by species/material/LOD or Shard hierarchy. Near
vegetation uses geometry; middle tiers simplify; far tiers use impostors where
they beat geometry. Grass may use procedural blades or cards by capability.

Aether supplies a multiscale wind field. Species assets contain branch hierarchy,
bend stiffness, leaf flutter, and phase data. Deformation writes correct motion
vectors and expanded culling bounds. Shadows uses a cheaper compatible wind
evaluation to prevent detached silhouettes.

## 6. Interaction

Characters and vehicles publish bounded interaction primitives. GPU deformation
bends nearby visual foliage; promoted actors receive Physics forces and damage.
Cutting/felling uses Destruction assets or a procedural fracture policy. Regrowth
is deterministic and belongs to persistent World state.

## 7. Streaming and budgets

Each cell stores compressed transforms, species indices, variation seeds, and a
sparse state override table. Coarse clusters become resident before individual
instances. Budgets cap visible instances, promoted actors, wind work, shadow
casters, collision proxies, and upload bytes.

## 8. Diagnostics and delivery

Debug views show biome/rule acceptance, seeds, density, culling, LOD, impostors,
wind bounds, interaction fields, promoted actors, and cell residency. Counters
include candidates, accepted/visible instances, draw clusters, promotions,
shadow casters, wind time, memory, and streaming misses.

Delivery:

1. species assets, deterministic placement, instanced rendering, and cells.
2. Landscape/biome rules, GPU culling, LOD, and impostors.
3. Aether wind, Material foliage closure, Shadows, and motion vectors.
4. promotion/demotion, interaction, harvesting, Physics, and Destruction.
5. seasonal ecology, regrowth, procedural tooling, networking, and replay.

