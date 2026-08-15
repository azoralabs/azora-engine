# Azora Voxels — Sparse Volumetric Voxel Technology

Status: Proposal
Primary package: `azora-voxels`
Primary module: `engine.voxels`

## 1. Decision

Voxels provides sparse scalar/material volumes, editable brick storage, volume
queries, surface extraction, ray traversal, and GPU volume rendering. It uses a
brick pool indexed by a sparse hierarchy rather than allocating a dense world
grid. The canonical source is a versioned field; meshes, collision, navigation,
distance fields, and radiance proxies are derived products.

## 2. Current engine audit

No 3D voxel package exists. `engine.tilemap.storage.TileChunks` demonstrates
sparse occupancy at 2D chunk granularity but stores tile planes, not volumetric
fields. GPU has no 3D/sparse texture abstraction, World has no spatial cells,
and Physics/Traverse lack rebuildable worlds. Those become prerequisites for
large voxel scenes; a CPU brick prototype can precede them.

## 3. Storage model

```azora
pack VoxelVolumeId {
    fin value: std::Long
}

pack VoxelBrickId {
    fin value: std::Long
}

enum VoxelFieldKind {
    Occupancy
    SignedDistance
    Density
}

@Component
pack VoxelVolume {
    fin id: VoxelVolumeId
    fin kind: VoxelFieldKind
    var voxelSize: std::Double
    var editable: std::Bool
}

pack VoxelSample {
    fin valid: std::Bool
    fin value: std::Double
    fin material: MaterialId
    fin generation: std::Long
}

@Resource
pack VoxelSettings {
    var brickEdge: std::Int
    var cpuBudgetBytes: std::Long
    var gpuBudgetBytes: std::Long
    var rebuildBudgetMillis: std::Double
}
```

The default brick has a small fixed edge and border samples for filtering and
surface extraction. Empty, constant, and homogeneous bricks are compressed or
represented directly in hierarchy nodes.

## 4. Hierarchy and residency

A sparse octree or page table maps absolute brick coordinates to content-derived
brick symbols. CPU metadata keeps bounds, min/max values, material summary,
generation, and derived-artifact status. Streaming independently manages source
bricks, GPU bricks, extracted meshes, and collision/nav artifacts.

Parents provide conservative coarse values and remain resident while children
are requested, preventing holes. GPU sparse textures may accelerate brick
storage, but the public model does not require them.

## 5. Editing

Edits are pure bounded operators: union, subtract, intersect, smooth, paint,
noise, stamp, erode, and custom deterministic field function. An edit records
operator symbol, bounds, parameters, author, sequence, and base generation.

Touched bricks use copy-on-write. A transaction publishes a new field generation
immediately at coarse quality, then replaces derived meshes/collision/nav data
atomically per region. Undo stores operations or changed compressed bricks.

## 6. Rendering

Three paths coexist:

- extracted surfaces via dual contouring or marching cubes, preferably compiled
  into Shard pages for mostly solid worlds;
- direct volume ray marching for density, fog, clouds, and translucent fields;
- signed-distance sphere tracing for specialized effects and debug.

Surface extraction preserves sharp features where Hermite data is available,
uses shared border samples to prevent cracks, and outputs stable material
regions. Mesh generation is budgeted and cancellable.

## 7. Queries and integration

```azora
func voxelSample(volume: VoxelVolumeId, at: WorldPosition): VoxelSample
func voxelRay(volume: VoxelVolumeId, ray: Ray, maxDistance: std::Double): VoxelHit
func voxelEdit(volume: VoxelVolumeId, edit: VoxelEdit): VoxelEditTicket ?! VoxelError
```

Landscape may include VoxelSurface layers but does not own volume storage.
Radiance may use coarse voxel opacity/emissive proxies. Physics and Traverse
consume versioned derived regions. Destruction can stamp fracture volumes.
Networking replicates ordered operations when deterministic and snapshots when
not.

## 8. Budgets and diagnostics

Separate budgets cover hierarchy metadata, compressed source bricks, mutable
working bricks, GPU bricks, extraction queues, collision, and history. Debug
views show hierarchy depth, brick residency, field range, material IDs,
generations, dirty derived regions, extraction error, and ray-step count.

Profiler counters include resident/requested/dirty bricks, compression ratio,
edit latency, bytes streamed, mesh triangles, extraction time, ray steps,
collision/nav lag, and parent-fallback samples.

## 9. Delivery

1. CPU sparse brick field, sampling, rays, serialization, and deterministic edits.
2. surface extraction with seam tests and Material regions.
3. GPU brick pool, volume ray rendering, and Streaming budgets.
4. Shard, Physics, Traverse, Landscape, and Radiance adapters.
5. collaborative edits, procedural generation, large worlds, and advanced
   feature-preserving extraction.
