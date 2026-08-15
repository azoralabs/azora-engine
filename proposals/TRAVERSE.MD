# Azora Traverse — Navigation, Pathfinding, and Crowds

Status: Proposal
Primary package: `azora-traverse`
Primary module: `engine.traverse`

## 1. Decision

Traverse owns navigation representations and movement planning: tiled navmeshes,
path queries, off-mesh links, hierarchical routing, dynamic obstacle updates,
local avoidance, crowd simulation, and debug tooling. It does not decide goals
or behavior; Azora Cognition requests paths and steering targets.

The default 3D implementation follows the proven Recast/Detour division:
voxelized navmesh building, runtime polygon queries, tiled streaming, tile-cache
obstacles, and crowd steering. Public APIs remain Azora-owned so providers can
be replaced and 2D/grid navigation can share query semantics.

## 2. Current engine audit

No navigation package exists. Tilemap already implements square/hex neighbors,
hex distance, lines/rings/ranges, collision traits, and line of sight, but not a
general A* query or agent/crowd system. Physics has rays/overlaps over individual
primitives but no world. World, Landscape, Roads, and Voxels are proposed
navigation geometry sources.

## 3. Public model

```azora
pack NavWorldId {
    fin value: std::Long
}

pack NavAgentKindId {
    fin value: std::Long
}

pack NavPathId {
    fin value: std::Long
}

enum NavQueryState {
    Pending
    Running
    Complete
    Partial
    Failed
    Cancelled
}

@Component
pack NavAgent {
    fin kind: NavAgentKindId
    var radius: std::Double
    var height: std::Double
    var maxSpeed: std::Double
    var maxAcceleration: std::Double
}

@Component
pack NavDestination {
    var target: WorldPosition
    var acceptanceRadius: std::Double
    var requestGeneration: std::Long
}

@Component
pack NavObstacle {
    var dynamic: std::Bool
    var area: NavAreaId
    var enabled: std::Bool
}
```

## 4. Build pipeline

Navigation source adapters emit triangles, bounds, area IDs, costs, exclusions,
and off-mesh links by World cell. For each agent kind the builder voxelizes
walkable geometry, filters by slope/clearance/step, partitions regions,
generates polygon/detail meshes, and writes border links. Builds are deterministic
for the same geometry, settings, and builder version.

Landscape, Roads, static Physics colliders, Shard proxies, and Voxels publish
source generations. Traverse does not inspect renderer-private buffers.

## 5. Runtime queries

```azora
pack NavQueryOptions {
    fin agent: NavAgentKindId
    fin areas: std::Int
    fin allowPartial: std::Bool
    fin maxNodes: std::Int
}

func findPath(
    world: NavWorldId,
    from: WorldPosition,
    to: WorldPosition,
    options: NavQueryOptions,
): NavPathTicket
```

Tickets are cancellable and generation-bound. Results contain stable polygon or
grid symbols, a corridor, straight path corners, total cost, partial endpoint,
and source generation. Query names are diagnostics only.

Hierarchical routing first chooses cell/region portals, then refines visible
path sections. A path keeps a corridor so local movement can repair it after
small changes without issuing a full global query.

## 6. Dynamic obstacles and links

Small temporary box/cylinder obstacles update a tile cache and rebuild bounded
tiles. Large/topology-changing edits invalidate source tiles asynchronously.
Agents retain the previous generation until a replacement tile publishes, with
an optional immediate avoidance obstacle for safety.

Off-mesh links represent jump, climb, door, ladder, elevator, teleport, and
custom traversal. Links use stable symbols and activation/cost state. Cognition owns
the behavior required to traverse a link; Traverse owns connectivity.

## 7. Crowds and avoidance

Crowd simulation uses fixed-step preferred velocities, corridor following,
neighbor queries, reciprocal local avoidance, separation, acceleration limits,
and path-boundary constraints. Large crowds use spatial grids and update LOD:
full local avoidance near observers, corridor-only midrange, aggregate flow far
away. Deterministic mode stabilizes neighbor and constraint order.

Physics remains authoritative for final collision. Crowd velocity is desired
motion and integrates through a character/vehicle controller.

## 8. 2D and grid modes

Traverse exposes providers for tile/grid, navmesh 2D, and 3D navmesh. Tilemap
providers reuse square/hex coordinate and tile-property APIs, adding hierarchical A*,
weighted areas, dynamic occupancy, flow fields, and shared ticket semantics.

## 9. Diagnostics and delivery

Debug views show source triangles, voxels, regions, polygons, portals, tile
generations, dynamic obstacles, query open/closed sets, corridors, corners,
avoidance neighbors, velocities, and stuck reasons. Counters include tile builds,
query nodes/time, partial paths, repairs, crowd neighbors, avoidance time,
stream misses, and memory.

Delivery:

1. Tilemap A*/flow provider and common async query model.
2. 3D tiled navmesh build, polygon queries, paths, and off-mesh links.
3. dynamic tile cache, World streaming, Landscape/Roads/Physics sources.
4. crowds, avoidance, path repair, update LOD, and Vehicle lane adapter.
5. Voxels/runtime rebuilds, deterministic replay, editor builder/debugger.

Reference implementation concepts: [Recast Navigation](https://github.com/recastnavigation/recastnavigation).
