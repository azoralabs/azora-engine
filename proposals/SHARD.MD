# Azora Shard — Virtualized Micro-Polygon Geometry

Status: Proposal
Primary package: `azora-shard`
Primary module: `engine.shard`

## 1. Decision

Azora Shard is a GPU-driven geometry virtualization system. Imported meshes are
partitioned into bounded clusters, simplified into an error hierarchy, paged in
compressed form, culled at instance and cluster granularity, and rasterized at
approximately pixel-scale geometric detail. It is not a new mesh file format
for user code and it does not replace ordinary meshes for sprites, UI,
transparent surfaces, particles, or highly deforming characters.

## 2. Current engine audit

`engine.gpu.Mesh` is a raw vertex-buffer handle plus vertex count. The Metal
path uploads interleaved position/normal vertices and issues immediate draws.
There are no indices, mesh assets, meshlets, indirect command buffers, compute
culling, occlusion hierarchy, derived-data pipeline, resource residency, or
streaming pages. `engine.animation.d3.Skin` performs CPU reference skinning but
is not connected to rendering. Shard begins after the GPU resource and Streaming
contracts exist.

## 3. Goals and non-goals

Goals:

- artist-scale source geometry without manually authored LOD chains;
- stable geometric error measured in screen space;
- GPU-driven frustum, backface-cone, instance, and hierarchical occlusion culling;
- compressed cluster pages streamed under explicit CPU/GPU budgets;
- no cracks between selected hierarchy nodes;
- material-range preservation and bounded material diversity per cluster;
- precision compatible with large-world origin rebasing;
- conventional mesh and CPU fallback paths.

Initial non-goals: arbitrary runtime topology edits, transparent Shard
materials, full-quality skeletal deformation, and claiming one algorithm works
best on every GPU. Destruction and Voxels generate immutable Shard fragments or
use conventional dynamic meshes until an incremental builder exists.

## 4. Asset model

```azora
pack ShardMeshId {
    fin value: std::Long
}

pack ShardPageId {
    fin value: std::Long
}

pack ShardGeometricError {
    fin objectSpace: std::Double
    fin parentSpace: std::Double
}

@Component
pack ShardMesh {
    fin mesh: ShardMeshId
    var materialSet: MaterialSetId
    var errorScale: std::Double
    var enabled: std::Bool
}

@Resource
pack ShardSettings {
    var targetPixels: std::Double
    var pageBudgetBytes: std::Long
    var decodeBudgetBytes: std::Long
    var maxVisibleClusters: std::Int
    var occlusionEnabled: std::Bool
}
```

Stable IDs are content-derived symbols. Runtime page slots and cluster indices
are transient implementation details and may never enter save files or network
state.

## 5. Offline build

The importer validates topology and attributes, welds only when semantically
safe, partitions triangles into meshlet-sized leaf clusters, computes bounds and
normal cones, builds adjacency, simplifies groups into parent clusters, and
packages independently decompressible pages. Every hierarchy node records a
conservative geometric error and dependency list.

Material boundaries, UV seams, hard normals, skin partitions, and displacement
bounds constrain simplification. Derived data is keyed by source hash, importer
version, Material layout, quantization profile, and target family.

## 6. Runtime pipeline

1. World extracts visible Shard instances in camera-relative coordinates.
2. GPU instance culling rejects frustum and coarse occlusion misses.
3. Hierarchy traversal selects nodes whose projected error meets the target.
4. Missing pages emit prioritized Streaming requests and select resident parents.
5. Cluster culling applies cones, fine frusta, and previous/current depth pyramids.
6. Visible clusters feed mesh shaders or a compute-expanded index/vertex path.
7. Material bins are emitted without readback.
8. Feedback updates page heat and geometric error diagnostics.

The resident-parent invariant guarantees a drawable coarse representation before
children are evicted. A missing fine page degrades detail, never object identity.

## 7. Backend paths

- Metal mesh/object shaders: direct cluster expansion on supported Apple GPUs.
- Vulkan mesh shaders: equivalent object/mesh task path when capability exists.
- Compute fallback: decode visible clusters into bounded transient buffers and
  issue indirect indexed draws.
- CPU fallback: imported conventional LODs, required for WebGL-class targets.

Backend selection is a capability record, not a platform-name conditional.
Apple documents object/mesh stages as a way to cull meshlets and select LOD
before rasterization; Shard uses that model but retains the compute fallback.

## 8. Deformation

Rigid instances are first-class. Skeletal meshes initially use the conventional
Animation rendering path. A later deformable Shard tier stores conservative
deformation bounds and skins selected leaf clusters; it may not simplify across
incompatible bone influence sets. Morph targets follow the same restriction.
Cloth remains dynamic conventional geometry unless frozen into a Shard asset.

## 9. Budgets and diagnostics

Budgets cover disk cache, compressed CPU pages, upload staging, resident GPU
pages, visible-cluster lists, and transient decoded geometry. Streaming priority
combines projected error, visibility, camera velocity, and starvation age.

Debug views expose hierarchy level, projected error, cluster bounds, normal
cones, occlusion result, page residency, parent fallback, material bins, and
overdraw. Profiler counters include clusters tested/visible, triangles emitted,
page faults, bytes read/decompressed/uploaded, cache hit rate, traversal time,
raster time, and fallback draws.

## 10. Delivery

1. Indexed mesh asset pipeline, meshlets, bounds, and CPU selection validator.
2. GPU cluster culling and conventional indirect rasterization.
3. simplification hierarchy, error selection, and crack-free transitions.
4. paged compression, Streaming integration, and resident-parent fallback.
5. mesh-shader backends, displacement bounds, and optional deformable clusters.

Acceptance includes deterministic builds, no visible holes under forced page
loss, bounded memory during fly-through, hierarchy/reference image comparisons,
and graceful fallback on devices without mesh shaders.

## 11. Technical references

- [Apple: Transform your geometry with Metal mesh shaders](https://developer.apple.com/videos/play/wwdc2022/10162/)
- [Khronos Vulkan registry](https://registry.khronos.org/vulkan/)
