# Azora Landscape — Fully Geometric Terrain

Status: Proposal
Primary package: `azora-landscape`
Primary module: `engine.landscape`

## 1. Decision

Landscape is a geometric, layered terrain system for bounded levels and
planet-scale worlds. A landscape is authored as non-destructive elevation,
surface, hole, biome, and spline layers; compiled into World cells; rendered
through Shard or a portable clipmap path; and queried through stable terrain
symbols. Runtime edits produce local patches and asynchronous rebuilds rather
than mutating a monolithic height texture.

“Fully geometric” means silhouettes, overhang-capable mesh patches, caves and
vertical cuts can be represented by geometry. Heightfields remain a fast source
layer, not the only runtime representation.

## 2. Current engine audit

There is no terrain package. `engine.tilemap` already demonstrates sparse chunk
occupancy, coordinate conversion, visible-range calculation, layered storage,
collision queries, and deterministic resizing for 2D maps. Those patterns are
useful but are not a 3D terrain representation. Current rendering has no mesh
asset streaming or LOD hierarchy, and physics has no broad-phase world.

## 3. Ownership

Landscape owns terrain source layers, compiled terrain geometry, terrain
surface weights, editing, collision/nav extraction, and terrain queries.

- World owns cells, absolute coordinates, and streaming anchors.
- Streaming owns file/GPU residency.
- Shard owns virtual geometric detail.
- Material owns surface evaluation and layer blending.
- Roads owns road spline semantics and requests landscape stamps.
- Fluids owns water simulation and shore interaction.
- Traverse owns navmesh tiles generated from landscape geometry.

## 4. Public model

```azora
pack LandscapeId {
    fin value: std::Long
}

pack LandscapePatchId {
    fin value: std::Long
}

enum LandscapeSourceKind {
    Heightfield
    Mesh
    VoxelSurface
    Procedural
}

@Component
pack Landscape {
    fin id: LandscapeId
    var enabled: std::Bool
    var collision: std::Bool
    var navigation: std::Bool
}

pack LandscapeSample {
    fin valid: std::Bool
    fin position: Vec3
    fin normal: Vec3
    fin material: MaterialId
    fin patch: LandscapePatchId
}

@Resource
pack LandscapeSettings {
    var cellSize: std::Double
    var targetPixels: std::Double
    var editBudgetMillis: std::Double
    var collisionRadius: std::Double
}
```

Queries use world positions and stable patch IDs:

```azora
func landscapeSurfaceAt(world: WorldPosition): LandscapeSample
func landscapeRay(ray: Ray): LandscapeHit
func landscapeMaterialWeights(at: WorldPosition): SurfaceWeights
```

## 5. Authoring layers

Layers are immutable operations ordered in a stack: import elevation, sculpt,
flatten, terrace, erosion, visibility holes, mesh insertions, material paint,
biome paint, procedural masks, and spline stamps. Each operation has a stable
symbol, bounds, revision, and blend policy. Editing one layer invalidates only
intersecting derived cells.

Roads and rivers write named stamp layers so artists can reorder or disable
them. Destructive flattening of source data is never required.

## 6. Derived representation

Each World cell contains:

- a coarse always-resident surface proxy;
- Shard cluster pages or portable clipmap meshes;
- hole and topology metadata;
- compressed material weights and biome IDs;
- collision tiles at physics-specific resolution;
- Traverse source geometry and area annotations;
- edit dependencies and content hashes.

Cell borders are compiled together or constrained by shared edge samples to
prevent cracks. Skirts may hide temporary streaming transitions but are not the
primary seam solution.

## 7. Runtime rendering

Shard mode uses geometric error hierarchy and page residency. Portable mode
uses nested camera-relative clip rings with geomorphing and a resident coarse
mesh. Surface weights select a bounded set of Material layers per patch.

Landscape culling is GPU-driven where available. Horizon/occlusion tests reject
whole cells before cluster traversal. Origin rebasing updates camera-relative
transforms without rebuilding absolute terrain data.

## 8. Runtime edits

Edits enter a transaction with bounds and generation. A low-resolution visual
patch appears immediately; jobs rebuild full geometry, collision, material
weights, and nav inputs. Readers keep the previous generation until all required
artifacts for the new generation commit together. Cancellation discards
unpublished work.

Networking replicates edit operations or authoritative derived patches by
symbol and generation. Replay records the same operations. Save files never
store transient GPU page addresses.

## 9. Performance and diagnostics

Budgets separately cap visible geometry, resident geometry, material weights,
collision radius, nav rebuilds, and edit jobs. Debug views show cells, geometric
LOD, patch IDs, layer influence, material count, holes, collision resolution,
nav dirtiness, page residency, and seam validation.

Profiler counters include visible cells/patches, selected triangles, page
faults, material-layer overflow, edit queue age, rebuild time, collision memory,
nav invalidation, and fallback coverage.

## 10. Delivery

1. heightfield import, cell compilation, portable clipmap renderer, queries.
2. Material layers, holes, collision extraction, and World streaming.
3. Shard-backed geometry and geometric silhouettes.
4. non-destructive sculpt/paint layers and transactional runtime edits.
5. mesh/voxel source layers, erosion/procedural tools, Roads/Fluids/Traverse
   adapters, and large-world validation.

Acceptance requires crack-free cell borders, bounded fly-through memory, exact
query/render generation agreement, deterministic derived data, safe origin
rebasing, and visible coarse fallback under forced streaming loss.
