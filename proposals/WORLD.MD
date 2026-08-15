# Azora World — Large Worlds, Partitioning, and Spatial Ownership

Status: Proposal building on ECS and Tilemap foundations
Primary package: `azora-world`
Primary module: `engine.world`

## 1. Decision

World owns spatial identity and composition above ECS: absolute coordinates,
world cells, partition layers, scene instances, origin rebasing, streaming
anchors, data-layer activation, cross-cell references, and transactional cell
publication. ECS `World` remains the entity/storage runtime; `engine.world`
must use a distinct public name such as `SpatialWorld` to avoid ambiguous APIs.

Streaming owns residency mechanics. World decides what should be resident and
what generation is active.

Scene owns bounded entity graphs and hierarchy; Prefab owns reusable templates;
Assets/Serialization own cooked graph data; Save owns durable overlays. World
places Scene/Prefab instances in spatial cells and gives persistent objects
large-world identity without reimplementing those systems.

## 2. Current engine audit

`engine.ecs.World` already provides generational entities, names, parent IDs,
prefab/resource flags, fixed timestep fields, alive/free tracking, and a global
revision. `Storage<T>` supplies typed sparse component arrays and per-entity
change revisions. Tilemap supplies chunk occupancy and visible tile ranges. No
3D spatial index, cell asset, scene format, absolute coordinate, origin rebase,
streaming source, data layer, cross-cell reference, or transactional loading
exists. Entity names are currently lookup labels and are not stable symbols.

## 3. Public model

```azora
pack WorldCellId {
    fin value: std::Long
}

pack WorldObjectId {
    fin value: std::Long
}

pack WorldPosition {
    fin cellX: std::Long
    fin cellY: std::Long
    fin cellZ: std::Long
    fin local: Vec3
}

@Component
pack WorldObject {
    fin id: WorldObjectId
    fin ownerCell: WorldCellId
    var persistent: std::Bool
}

@Component
pack WorldTransform {
    var absolute: WorldPosition
    var rotation: Quat
    var scale: Vec3
}

@Resource
pack SpatialWorld {
    var origin: WorldPosition
    var originGeneration: std::Long
    var revision: std::Long
}
```

`WorldPosition` uses integer cell coordinates plus local floating coordinates,
avoiding precision loss without forcing every shader/physics operation to use
wide floats. Conversion to camera-relative `Vec3` is explicit.

## 4. Cells and layers

Cells are immutable versioned asset manifests containing Scene/Prefab instance
records, World object records, bounds, dependencies, derived render/physics/nav
content, and content hashes. Hierarchy and component payloads use Scene and
Serialization schemas. Runtime overlays contain spawned, destroyed, moved, and
edited persistent state without rewriting shipped assets.

Data layers independently activate gameplay variants such as day/night,
interiors, quests, editor layers, or platform quality. An object may belong to
multiple layers with an explicit activation expression.

## 5. Spatial indexes and anchors

World maintains indexes for cells and coarse object bounds. Subsystems keep
specialized indexes for lights, physics, navigation, etc. Streaming anchors have
position, velocity, radius/budget profile, priority, and prediction horizon.
Camera, players, remote spectators, audio listeners, and editor views may all be
anchors.

Desired cells combine anchor distance, frustum, velocity prediction, portals,
gameplay pins, network interest, and subsystem needs. World produces priorities;
Streaming performs I/O/decode/upload.

## 6. Transactional publication

A cell stages manifest validation, dependencies, entity allocation, component
decode, and subsystem artifacts off-world. Publication uses a command
transaction at a schedule boundary. Readers see either the previous generation
or the complete new generation, never half a cell. Unload first removes
discoverability, waits for consumers/fences, persists overlays, then releases.

Cross-cell references use `WorldObjectId` and resolve to live entities through a
generation-aware table. Unresolved references remain valid symbolic handles and
emit availability changes; they never reuse a similarly named object.

## 7. Origin rebasing

When anchors exceed a threshold, World selects a snapped new origin and
increments `originGeneration`. ECS absolute `WorldTransform` remains unchanged;
camera-relative render/physics representations shift at a controlled boundary.
Physics, Particles, Audio, Camera, Radiance, Shadows, and Replay receive one
rebase event and must declare whether state shifts, rebuilds, or remains absolute.

## 8. Persistence, networking, and replay

Persistent overlays are keyed by world/object/component symbols and schema
versions, encoded through Serialization, and committed by Save. Networking
relevancy consumes World cells but server authority is independent from client
residency. Replay records cell generation activation, origin changes, and
persistent commands so seeking reconstructs identical spatial state.

## 9. Diagnostics and delivery

Debug tooling shows cells, layers, anchors, desired/resident generations,
object ownership, unresolved references, pins, origin, overlays, and transaction
stages. Counters include cell counts, object counts, load/unload latency,
transaction time, unresolved references, rebase time, overlay bytes, and pins.

Delivery:

1. stable object/cell symbols, scene manifests, component serialization.
2. spatial cells/index, anchors, staged load/unload, transactional publication.
3. Streaming contract, cross-cell references, persistent overlays, data layers.
4. large-coordinate transforms, origin rebasing, subsystem conformance.
5. networking/replay/editor collaboration, portals/HLOD, massive-world tests.
