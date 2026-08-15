# Azora Roads — Road, Junction, and Lane System

Status: Proposal
Primary package: `azora-roads`
Primary module: `engine.roads`

## 1. Decision

Roads is a spline-graph system that generates road geometry, intersections,
terrain stamps, markings, collision, lane topology, traffic metadata, and
streamable derived assets from one semantic source. A road is not merely a
decal or stretched mesh: its lanes and junction movements remain queryable by
vehicles, Cognition, navigation, editor tools, and networking.

## 2. Current engine audit

There is no road or spline package. `engine.tilemap` has grid/hex paths and
neighbors, while `engine.math` provides vectors and matrices. Physics offers
primitive collision tests but no world. Rendering can draw immediate meshes.
Roads therefore starts with a portable spline graph and CPU geometry builder,
then integrates Landscape, Shard, Decals, Vehicle, and Traverse.

## 3. Public model

```azora
pack RoadId {
    fin value: std::Long
}

pack RoadNodeId {
    fin value: std::Long
}

pack RoadEdgeId {
    fin value: std::Long
}

pack LaneId {
    fin value: std::Long
}

enum LaneDirection {
    Forward
    Reverse
    Bidirectional
}

pack RoadProfile {
    var laneWidth: std::Double
    var shoulderWidth: std::Double
    var curbHeight: std::Double
    var crown: std::Double
    var material: MaterialId
}

@Component
pack RoadNetwork {
    fin id: RoadId
    var enabled: std::Bool
}

pack LaneSample {
    fin lane: LaneId
    fin distance: std::Double
    fin position: Vec3
    fin tangent: Vec3
    fin lateral: Vec3
    fin speedLimit: std::Double
}
```

## 4. Semantic graph

Nodes represent endpoints, control anchors, and junctions. Directed edges own a
centerline curve, profile, lane sections, elevation policy, banking, speed
rules, and tags. Lanes are stable symbols with predecessor/successor links.
Junctions explicitly list permitted lane-to-lane movements, priorities, stop
rules, signals, and conflict regions.

Curve evaluation uses arc-length tables so sampling, vehicle progress, markings,
and speed planning agree. Editing a curve preserves lane symbols where topology
is unchanged and emits a remap when it is not.

## 5. Geometry generation

The builder adaptively samples by curvature, grade, banking, and projected error;
constructs pavement, shoulders, curbs, barriers, sidewalks, medians, tunnels,
and bridge surfaces; resolves junction patches; emits Shard clusters or normal
meshes; and generates UV/marking coordinates. It validates self-intersection,
excess grade, impossible banking, and degenerate lane widths.

Markings use Decals for ordinary paint and geometry for raised or silhouette-
relevant markings. Repeated props use Foliage/instancing contracts rather than
duplicated entities.

## 6. Landscape and structures

Each edge requests a named Landscape stamp containing cut/fill, smooth falloff,
retaining-wall needs, and drainage hints. Bridges and tunnels are structure
segments that suppress ordinary terrain conforming. Generated stamps remain
non-destructive layers and can be reordered by artists.

Roads can exist without Landscape; in that case elevation is absolute or
provided by another surface query.

## 7. Runtime consumers

- Vehicle queries lane frames, curvature, surface type, speed, and junctions.
- Traverse receives pedestrian/vehicle off-mesh and lane graph links.
- Cognition receives conflict regions, traffic signals, and route costs.
- Physics receives simplified collision strips and barriers.
- World/Streaming owns road cell residency and cross-cell references.
- Networking replicates semantic edits by stable IDs and generation.

Consumers never infer topology from generated triangle names.

## 8. Runtime editing

An edit transaction changes graph topology or control points, computes affected
edges/cells, generates low-cost preview geometry, then asynchronously rebuilds
geometry, collision, stamps, and navigation. Publication is generation-atomic.
Vehicles on replaced lanes receive deterministic remap, safe stop, or despawn
policy selected by the application.

## 9. Diagnostics and delivery

Debug views show control tangents, arc-length error, lane directions, successors,
junction movements, conflicts, banking, grade, cell ownership, generated patch
bounds, collision, and landscape stamps. Counters include edges, samples,
triangles, junction build time, invalid profiles, edit queue age, streamed cells,
and lane-query time.

Delivery:

1. spline graph, profiles, adaptive mesh generation, and lane sampling;
2. junctions, markings, collision, and serialized assets;
3. Landscape stamps, Shard geometry, Decals, and World streaming;
4. lane routing, Vehicle/Traverse/Cognition contracts, signals, bridges, and tunnels;
5. transactional runtime editing, networking, and procedural road generation.
