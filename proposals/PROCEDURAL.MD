# Azora Procedural — Procedural Content Generation

Status: Proposal
Primary package: `azora-procedural`
Primary module: `engine.procedural`

## 1. Decision

Procedural is a deterministic, typed, incremental content graph. It transforms
bounded data sets—points, fields, splines, surfaces, selections, and assets—into
derived placement or build commands. It does not directly mutate arbitrary ECS
state while evaluating. Results commit through explicit World transactions,
which makes cancellation, caching, streaming, networking, and undo reliable.

## 2. Current engine audit

There is no procedural package. Tilemap already has deterministic fills,
neighbors, paths, sparse chunks, and map transforms that can become graph nodes.
Jobs is currently only a placeholder facade over `std.concurrency`, so true
parallel graph execution still needs scheduler work. ECS commands and revisions
provide a foundation for transactional result application.

## 3. Data model

```azora
pack ProceduralGraphId {
    fin value: std::Long
}

pack ProceduralNodeId {
    fin value: std::Long
}

enum ProceduralDomain {
    Points
    Spline
    Surface
    Volume
    Grid
    Entities
}

pack ProceduralSeed {
    fin value: std::Long
}

@Component
pack ProceduralRegion {
    fin graph: ProceduralGraphId
    fin seed: ProceduralSeed
    var enabled: std::Bool
    var generation: std::Long
}

pack ProceduralResult {
    fin generation: std::Long
    fin commands: std::Array<ProceduralCommand>
    fin dependencies: std::Array<ContentSymbol>
}
```

## 4. Graph semantics

Nodes declare typed ports, bounds transformation, determinism, thread safety,
side effects, cost estimate, and cache key. Core nodes include source/query,
sample, filter, map, scatter, relax, cluster, sort, merge, difference, attribute,
noise, field math, spline operations, grammar expansion, select asset, instance,
spawn command, terrain stamp, and validation.

Cycles are rejected except through explicit bounded iteration nodes. Random
values are counter-based from graph, node, region, item symbol, and user seed;
parallel chunk order cannot alter output.

## 5. Incremental execution

Each node output is partitioned by spatial region and keyed by node revision,
input hashes, parameters, seed, and target quality. Changed inputs invalidate only
downstream partitions whose dependency bounds intersect. Jobs are cancellable;
stale generations can finish but cannot publish.

Evaluation produces immutable intermediate chunks and a final command buffer.
World validates ownership/conflicts, then commits all commands for one region
generation. Preview and final quality use compatible symbols so editor selection
survives refinement.

## 6. Integration

- Landscape exposes sampling and accepts named stamp commands.
- Roads accepts spline graphs or emits generated roads.
- Foliage adds species/ecology filtering after generic scatter.
- Voxels accepts deterministic bounded field edits.
- World owns cells and result persistence.
- Streaming predicts dependencies from graph bounds.
- Networking sends seed/inputs when deterministic or authoritative results when not.
- Replay records graph invocation and committed generation.

## 7. Extensibility and safety

```azora
spec ProceduralNode {
    func describe(): ProceduralNodeInfo
    func evaluate(context: ProceduralContext&, output: ProceduralOutput!): std::Unit ?! ProceduralError
}
```

Extension packs register node symbols and schemas at startup. Shipping builds
can restrict native/custom nodes. Every node has an item, memory, recursion,
iteration, and time budget. A graph cannot access filesystem, networking, or
global ECS state unless a declared source capability provides bounded input.

## 8. Tooling and delivery

The editor shows typed ports, spatial bounds, cache hits, item counts, per-node
timings, seeds, rejected points, dependencies, generations, and diffs between
runs. Headless evaluation and golden-result serialization are required.

Delivery:

1. typed DAG, deterministic points/fields, caching, and command results.
2. incremental spatial partitions, cancellation, World transactions, editor.
3. Landscape/Roads/Foliage/Tilemap node packs.
4. Voxels, grammar systems, GPU-accelerated pure nodes, and distributed baking.
5. networking/replay validation, extension SDK, and large-world streaming.

