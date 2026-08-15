# Azora Prefab — Reusable Entity and Object Graphs

Status: Proposal replacing the ECS prefab Boolean marker
Primary package: `azora-prefab`
Primary module: `engine.prefab`

## 1. Decision

A Prefab is a versioned reusable graph of nodes, components, hierarchy, nested
Prefab instances, exposed parameters, and stable-symbol overrides. A Prefab
instance retains a link to its source and a sparse override patch, allowing
source updates, inspection, Save overlays, and deterministic unpacking.

Prefab is not an ECS entity flag and not a copied Scene with name-based patching.
It owns templates and instance/source correspondence; Scene owns placement and
lifecycle; ECS owns instantiated storage.

## 2. Current engine audit

ECS stores one Boolean `prefabs[id]`, with `markPrefab` and `isPrefab`. It does
not record a prefab asset, node mapping, nested graph, source generation,
overrides, parameters, variants, ownership, propagation, or unpack semantics.
The flag cannot distinguish the prefab root from children and is reset on entity
reuse.

## 3. Identity and model

```azora
pack PrefabId {
    fin asset: AssetId
}

pack PrefabNodeId {
    fin symbol: ContentSymbol
}

pack PrefabInstanceId {
    fin value: std::Long
    fin generation: std::Int
}

@Component
pack PrefabLink {
    fin instance: PrefabInstanceId
    fin prefab: PrefabId
    fin sourceNode: PrefabNodeId
    var sourceGeneration: std::Long
}

enum PrefabOverrideKind {
    SetValue
    AddComponent
    RemoveComponent
    AddNode
    RemoveNode
    ReparentNode
    ReorderNode
}

pack PrefabPropertyPath {
    fin node: PrefabNodeId
    fin component: ContentSymbol
    fin property: ContentSymbol
}
```

Property paths and structural targets use symbols emitted by schemas. Display
names and field positions are not identity. Instance-added nodes receive stable
instance-local symbols so saves and editor undo can address them.

## 4. Source graph and exposed parameters

A Prefab source contains stable nodes, parent order, local transforms, component
records, nested instance records, asset dependencies, default activation, and
optional exposed parameters. Parameters map a public symbol and validation rule
to one or more internal property paths. They are authoring ergonomics, not a
second component system.

AZON is the editable source. Build expands schemas, validates references and
override paths, and cooks a compact immutable graph. A Prefab can be instantiated
without loading an editor Scene.

## 5. Overrides

An instance is evaluated as:

```text
source generation -> nested sources -> variant patch -> instance patch -> runtime overlay
```

Patches are sparse, ordered operations. Setting a property equal to the current
source removes the redundant override. Removing a source node/component creates
a tombstone override so later source changes do not resurrect it silently.
Overrides that target deleted or migrated symbols become explicit conflicts with
the old payload preserved for repair.

The first design permits one optional base Prefab plus nested composition. Deep
multi-parent inheritance is excluded: it creates unclear ordering and fragile
diamonds. Variants are named patch assets over one base and can themselves be
instantiated normally.

## 6. Nested Prefabs and cycles

Nested instances retain a distinct Prefab identity and node-symbol namespace.
The parent may override only fields exposed by policy or address the nested path
explicitly in editor tooling. Hard nesting cycles are build errors. Runtime soft
references may be cyclic only when they do not participate in graph expansion.

Unpacking materializes evaluated nodes into Scene-owned nodes, assigns new Scene
symbols, rewrites internal references, removes `PrefabLink`, and records one
undoable transaction. It never leaves half-linked descendants.

## 7. Instantiation and publication

Instantiation resolves and validates the complete source/variant dependency
closure, evaluates patches into a staged graph, reserves ECS entities, decodes
components, resolves references in two passes, and publishes one command
transaction. Callers receive a `PrefabInstanceId` immediately as a pending
handle and observe `Ready` or typed failure later.

Batch instantiation shares immutable evaluated templates and allocates ECS
storage by component archetype/chunk where available. Per-instance mutable state
is never shared accidentally. Despawn uses the instance ownership table rather
than walking by names or current hierarchy.

## 8. Source updates and hot reload

When Assets publishes a new Prefab generation, the runtime computes correspondence
by source symbols, validates every override, stages changed components/nodes, and
commits at a schedule boundary. Runtime-authored state follows component policy:
preserve, reset from source, merge field patches, or reject live update.

Editor preview updates automatically. Shipping builds enable live patching only
through an authenticated development capability. A failed migration leaves the
old generation active and lists conflicts.

## 9. Scene, World, Save, and Networking

Scene stores placement plus instance overrides, not a duplicated expanded graph.
World cells can contain Prefab instances and cook frequently repeated immutable
template data once. Save records Prefab ID/generation compatibility, instance
identity, persistent overrides, added/removed nodes, and component runtime state.
It never stores live ECS entities.

Network replication chooses whether to replicate a Prefab spawn command plus
overrides or ordinary component state. Clients validate the same content symbol
and cooked content hash before accepting compact spawn commands.

## 10. Editor, diagnostics, and tests

The inspector shows source asset/generation, source-to-instance node mapping,
nested instances, inherited/effective values, override origin, redundant or
orphaned patches, added/tombstoned nodes, and hot-reload conflicts. The editor
supports apply override to source, revert property/component/node, create
variant, select source, unpack, and compare generation.

Required tests include rename/reparent stability, same-named nodes, nested
instances, cycle rejection, structural overrides, removed-symbol conflicts,
parameter validation, deterministic patch order, batched instantiation,
transaction rollback, hot reload with runtime state, unpack reference rewrite,
Save round trip, and World-cell unload/reload.

## 11. Delivery

1. Prefab asset/node/instance IDs, source graph, link component, staged spawn;
2. property and structural override patches, variants, nested instances;
3. Scene authoring, apply/revert/unpack, hot reload and conflict UI;
4. Save/World/Networking integration, batch templates and cook optimization;
5. collaboration merge, authenticated live patching, large-prefab stress tests.
