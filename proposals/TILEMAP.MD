# Azora Tilemap — Lattices, Layers, Streaming, and 2D World Authoring

Status: Proposal building on a substantial tested implementation
Package: `azora-tilemap`
Module: `engine.tilemap`

## 1. Decision

Preserve Tilemap's central design: dense layer planes are authoritative for
ordinary cells, while ECS entities are opt-in for cells with behavior. Extend
that design with stable asset/layer symbols, infinite chunked maps, Tiled import,
transactional editing, batched GPU rendering, World/Streaming integration,
autotiling, and editor tooling.

Tilemap owns discrete 2D lattice content. Landscape owns continuous/geometric
3D terrain, Voxels owns sparse 3D fields, World owns spatial partition cells,
Traverse owns navigation, and Physics owns collision primitives/solving.

## 2. Current implementation audit

The package is already one of the engine's most complete subsystems. It includes
and tests:

- square, diamond/staggered isometric, and six axial/offset hex coordinate
  systems with anchors, bounds, picking, culling, and round trips;
- axial/cube hex conversion, neighbors, distance, lines, rings, spirals,
  rotation, and reflection;
- dense tile-index planes, lazily allocated flag/tint planes, 16x16 chunk
  occupancy, revisions, bulk fill/copy/replace/resize, and used bounds;
- atlas sheets/sets with margin/spacing and global tile IDs;
- tilesets with per-tile traits and draw-time animation;
- layered maps with opacity, tint, parallax, offset, order, and resize;
- overlap, swept-box, move/slide, grounded/ceiling, ray, and line-of-sight
  queries built on Physics 2D;
- CSV and packed layer loading plus Tiled-style global ID mirror bits;
- immediate culling/drawing, a tile camera, grid/highlight helpers;
- opt-in tile entities and synchronization into authoritative layer data;
- extensive unit tests across geometry, storage, collision, import, and drawing.

Important gaps:

- map/layer/tileset identity still relies on display names or local indices;
- finite dense maps are the only storage mode;
- chunk counts accelerate emptiness but chunks are not independently resident,
  compressed, serialized, generated, or streamed;
- only CSV/packed layers load; no complete Tiled JSON/TMX maps, tileset metadata,
  object layers, templates, properties, wang/terrain sets, or infinite chunks;
- atlases contain raw GPU handles and map/tileset modules import App/GPU;
- drawing emits per-tile immediate quads rather than bounded batches/instances;
- `TileCamera` overlaps the Camera system;
- no tilemap asset format, generation publication, undo transaction, hot reload,
  editor, networking/replay policy, Jobs, or Profiler;
- the current `TilemapFault` declaration still carries old member commas and
  must be normalized to current Azora declaration syntax.

## 3. Stable asset model

```azora
pack TilemapAssetId {
    fin symbol: ContentSymbol
}

pack TileLayerId {
    fin symbol: ContentSymbol
}

pack TileSetId {
    fin symbol: ContentSymbol
}

pack TileChunkId {
    fin map: TilemapAssetId
    fin layer: TileLayerId
    fin x: std::Int
    fin y: std::Int
    fin generation: std::Long
}

enum TileStorageMode {
    Dense
    Chunked
    Infinite
}

@Component
pack TilemapInstance {
    fin asset: TilemapAssetId
    var generation: std::Long
    var visible: std::Bool
}
```

Display names remain searchable metadata. Saved cells reference stable tile
symbols compiled to local dense indices per tileset generation. Layer reordering
does not change `TileLayerId`.

## 4. Storage and transactions

Finite small maps keep the current contiguous planes. Chunked/infinite maps use
independent fixed-size chunks with compressed backing, occupancy, used bounds,
revision, content hash, and optional flag/tint/custom planes. Chunk size is an
asset policy and converts cleanly to World/Streaming cells.

All writes occur through `TilemapEdit` transactions. A transaction records
changed rectangles/chunks, validates tile symbols and layer generations,
supports undo/redo, updates occupancy/revisions once, emits change events, and
publishes atomically. Bulk operations and procedural generation can build
private chunks in Jobs and commit one generation.

Dense layers remain the fast renderer/collision representation. ECS tile
entities remain sparse behavioral overlays and write back through the same
transaction path, preventing unsynchronized parallel mutation.

## 5. Tilesets, tags, animation, and autotiling

Per-tile integer traits migrate to stable tag symbols compiled into fast local
bitsets. Built-in compatibility helpers for solid, one-way, ladder, fluid,
hazard, destructible, slope, and animation remain. Gameplay packages can add
tags without consuming global hard-coded bit positions.

Animation supports arbitrary frame symbols, per-frame durations, random phase,
ping-pong/repeat/once, synchronized groups, and shader/atlas animation. Authored
base cells remain unchanged as in the current design.

Autotiling includes bitmask/terrain/wang rules, priorities, random weighted
variants, transforms, constraints, and deterministic seeds. Rules compile to
neighbor lookup tables and update only the changed cell neighborhood.

## 6. Import and asset pipeline

The initial complete importer targets the official
[Tiled JSON map format](https://doc.mapeditor.org/en/stable/reference/json-map-format/),
including finite/infinite tile layers, external/embedded tilesets, image and
collection tilesets, object/image/group layers, properties, templates,
animations, transformations, collision objects, parallax/origin, and terrain/
wang data. TMX is an optional sibling provider.

Import maps source IDs/names to stable content symbols, preserves unsupported
namespaced properties, resolves asset paths through I/O mounts, and emits a
loss/diagnostic report. Runtime consumes a compiled binary asset with chunk
tables, local tile indices, atlas references, tags, animation, collision,
autotile rules, and streaming manifest.

## 7. Rendering and camera integration

Tilemap extraction submits visible chunk/layer batches to Render. Each batch
uses atlas/material generation, instance buffer, transform, tint, flip,
animation data, depth key, and clipping. GPU instancing or generated quads
replace one draw per tile. Empty chunks submit nothing.

Isometric depth order is retained through stable keys or sorted instances.
Pixel-art mode controls integer camera placement, nearest sampling, atlas
padding, half-texel policy, and snap behavior. Camera owns views; Tilemap offers
2D lattice helpers and a compatibility adapter for `TileCamera`.

Atlases reference Image/Texture assets, never raw GPU handles. Palette cycling,
animated tiles, hot-reloaded images, and streamed atlas pages publish by
generation.

## 8. Collision, navigation, and world integration

Tilemap supplies candidate cells, shapes/tags, and static chunk collision data;
Physics 2D owns contact/sweep/ray math and simulation. Collision shapes extend
beyond full tile AABBs to polygons, circles, capsules, slopes, one-way edges,
and tileset-authored object groups.

Chunk collision meshes/proxies rebuild asynchronously from changed regions.
Traverse consumes walkability/cost/link exports rather than reinterpreting tile
names. World/Streaming publish chunk generations around active views/agents.
Procedural may generate chunks but Tilemap validates and owns their format.

## 9. Networking, replay, and determinism

Replicated edits carry map/layer/tile symbols, coordinates/rectangles,
transaction sequence, authority, and expected generation. Large initial maps
use content-addressed assets/chunks rather than per-cell replication. Conflicts
are explicit and server-validated.

Autotiling, animation phase, procedural selection, and edit merge use stable
seeds/order. Replay records authoritative edit transactions and entity behavior,
not every derived atlas index or render batch.

## 10. Diagnostics, testing, and delivery

Debug views show lattice coordinates, anchors, chunk residency/occupancy,
revisions, layers, tags, autotile matches, collision shapes, navigation cost,
entity bindings, culling, depth keys, draw batches, and streaming fallbacks.
Profiler records visible/visited/drawn tiles, chunks, batch counts, uploads,
collision rebuilds, transactions, import, autotile work, residency, and memory.

Delivery:

1. stable IDs/tile symbols, syntax cleanup, asset serialization, and transactions;
2. Render/Image asset integration, instanced batching, Camera adapter, Profiler;
3. complete Tiled JSON import and compiled runtime format;
4. chunked/infinite storage, World/Streaming, async collision/navigation export;
5. autotiling, editor/undo, networking/replay, procedural and advanced layers.

Acceptance preserves all current tests and APIs through adapters, imports
representative Tiled projects without silent loss, streams an infinite map with
bounded memory, batches visible tiles without per-cell allocations, keeps
behavioral entities sparse, and reproduces authoritative edits deterministically.
