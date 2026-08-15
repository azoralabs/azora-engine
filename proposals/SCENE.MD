# Azora Scene — Scenes, Entities, Hierarchy, and Transforms

Status: Proposal building on the current ECS hierarchy
Primary package: `azora-scene`
Primary module: `engine.scene`

## 1. Decision

A Scene is a versioned, loadable object graph whose nodes describe entities,
components, hierarchy, local transforms, nested Prefab/Scene instances, and
external asset references. Loading a Scene stages and validates the complete
graph, then instantiates it into an ECS world transactionally. Runtime `Entity`
values remain transient; scene node symbols are persistent identity.

Scene owns bounded object graphs and hierarchy. ECS owns entity/component
storage. Prefab owns reusable graph templates and overrides. World owns spatial
cells, large coordinates, and cross-cell activation.

## 2. Current engine audit

`engine.ecs.World` can spawn generational entities, store display names, assign
one parent ID, count children, and mark an entity as a prefab/resource. This is
useful scaffolding but not a scene system: parent assignment has no cycle check,
children are not directly enumerable, names are used for linear lookup, prefab
state is only a Boolean, and there is no scene asset, stable node ID, component
schema, local/world transform propagation, staged loading, nested graph, or
unload ownership.

## 3. Identity and public model

```azora
pack SceneId {
    fin asset: AssetId
}

pack SceneNodeId {
    fin symbol: ContentSymbol
}

pack SceneInstanceId {
    fin value: std::Long
    fin generation: std::Int
}

@Component
pack SceneNode {
    fin scene: SceneInstanceId
    fin source: SceneNodeId
}

@Component
pack Parent {
    var entity: Entity
}

@Component
pack LocalTransform {
    var value: Transform3
}

@Component
pack GlobalTransform {
    var value: Transform3
    var hierarchyRevision: std::Long
}

enum SceneInstanceState {
    Staging
    Ready
    Active
    Inactive
    Unloading
    Failed
}
```

`SceneNodeId` is generated once and survives rename, reorder, reparent, cooking,
and source-control merge. Display paths are diagnostics only. A
`SceneInstanceId + SceneNodeId` mapping resolves to the current generational ECS
entity. Two same-named nodes in one or many scenes are never ambiguous.

## 4. Scene asset schema

A source Scene contains:

- schema and engine feature versions;
- stable scene and node symbols plus display names;
- parent node symbol or root membership;
- local transform and activation policy;
- component records keyed by component schema symbol;
- nested Prefab/Scene instance records and override patches;
- hard, soft, editor-only, and optional asset dependencies;
- tags, layers, bounds hints, and authoring metadata.

AZON is the canonical editable representation. Build validates and cooks it into
a target-specific artifact with compact schema tables and dependency manifests.
The cooked representation is a cache; it cannot become the only readable source
of the scene.

## 5. Loading and lifecycle

Scene loading has explicit phases:

1. resolve the Scene asset and selected variant;
2. read and validate schema, symbols, references, and dependency limits;
3. apply migrations and expand nested Prefabs/Scenes into a staged graph;
4. reserve ECS entities and build node-to-entity mappings;
5. decode components and resolve intra-scene references in two passes;
6. prepare subsystem artifacts and activation commands;
7. publish the entire instance at one schedule boundary;
8. activate lifecycle hooks only after complete publication.

A failure before publication leaves no visible partial graph. Unload first
deactivates and removes discoverability, lets Save/World extract persistent
overlays, waits for leases/jobs/fences, then despawns owned entities. Entities
explicitly transferred to another owner are not silently destroyed.

## 6. Hierarchy and transforms

The hierarchy is a forest with ordered children. Mutation rejects self-parenting,
cycles, stale entities, cross-world parents, and illegal ownership transfers.
Reparenting chooses `KeepLocal` or `KeepGlobal`; the latter computes a new local
transform and reports non-invertible parent transforms.

Transform propagation processes dirty roots in parent-before-child order. Local
changes, hierarchy edits, animation, physics, and World rebasing have explicit
schedule phases. Render extraction reads immutable `GlobalTransform` snapshots.
Physics-driven entities declare whether physics writes global pose or local pose
relative to a parent; mixed authority in one frame is an error.

For large worlds, `WorldTransform` remains the authoritative absolute position
and Scene hierarchy operates on cell-local transforms under a World-owned root.
Scene does not duplicate origin rebasing.

## 7. Activation, layers, and nested scenes

An instance can be loaded but inactive. Node activation inherits by default and
may be overridden by Scene layer, World data layer, platform/quality variant, or
gameplay command. Inactive entities retain identity and data according to policy
but do not run ordinary systems.

Nested Scene instances preserve their own asset identity and can load/unload
independently when declared as soft instances. Inline instances are flattened at
cook time but retain source symbols for debugging and patching. Cyclic hard
nesting is a build error; soft cycles require an explicit runtime break.

## 8. References and commands

Intra-scene references use `SceneNodeId`; runtime resolution uses the instance
mapping. External references use Asset, Prefab, WorldObject, or exported Scene
symbols with explicit hard/soft policy. No serialized component stores an ECS
array index or generation.

Scene mutations are command-buffered. Spawn, despawn, reparent, component patch,
instance load/unload, and activation changes commit deterministically by stable
command site and sequence. Observers receive a committed change set, not
callbacks during half-applied mutation.

## 9. Editor and collaboration

The editor works against stable node/component/property symbols. Undo/redo stores
semantic commands. Multi-user/source-control merges can distinguish rename from
delete-and-create. Missing optional assets remain inspectable placeholders;
unknown component schemas preserve their AZON payload so opening with a reduced
plugin set does not destroy data.

Copy/paste and duplicate generate new node symbols but preserve explicit links
that target nodes inside the copied subgraph. Promote-to-Prefab and unpack-Prefab
are explicit transformations with reviewable patches.

## 10. Diagnostics, testing, and delivery

The Scene inspector shows instances, source assets/generations, node symbols,
runtime entities, hierarchy, transform dirtiness, activation, dependencies,
unknown components, override origins, and pending commands. Counters include
load/decode/instantiate/publish time, nodes/components, dirty transforms,
hierarchy depth, failed references, and unload latency.

Required tests cover same-named nodes, rename stability, cycle rejection,
ordered children, keep-global reparenting, nested graphs, unknown schemas,
two-pass references, rollback before publication, deterministic command merge,
hot reload, Save overlays, World-cell ownership, and deep-hierarchy limits.

Delivery:

1. stable node identity, hierarchy storage, child iteration, cycle-safe commands,
   and transform propagation;
2. AZON Scene schema, registry-driven components, staged instantiation/unload;
3. Prefab/nested Scene instances, overrides, soft references, hot reload;
4. World cells/data layers, Save overlays, editor undo/merge, diagnostics;
5. incremental cooking, collaboration, and large-scene performance hardening.
