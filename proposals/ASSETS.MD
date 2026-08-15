# Azora Assets — Import, Cooking, and Dependency Management

Status: Proposal replacing direct-path runtime loading
Primary package: `azora-assets`
Primary module: `engine.assets`
Tooling package: `azora-assets-tools`

## 1. Decision

Assets owns stable content identity, source import, processing/cooking,
target variants, dependency graphs, artifact metadata, and the local build cache.
Source paths are authoring metadata; runtime code addresses assets by `AssetId`
and obtains generations through Streaming. Build invokes cooking and packages the
result. Individual subsystems own the semantic compiler for their asset kind.

The same asset graph drives editor hot reload, command-line builds, incremental
cooking, package distribution, and runtime dependency expansion.

## 2. Current engine audit

The engine currently loads whole files synchronously by path. Image decodes BMP,
Font combines a manifest path with an image path, Tilemap reads CSV/image paths,
Tracker parses a file directly, Audio reads a blob, GPU creates resources from
immediate values, and `azpm.py` resolves source package dependencies. There is no
asset database, stable subasset identity, importer registry, cooked artifact,
target variant, content hash, dependency invalidation, cache, or missing-asset
diagnostic chain.

## 3. Canonical model

```azora
pack AssetId {
    fin symbol: ContentSymbol
}

pack AssetKindId {
    fin symbol: ContentSymbol
}

pack ArtifactId {
    fin contentHash: std::String
}

enum AssetDependencyKind {
    Hard
    Soft
    BuildOnly
    EditorOnly
    Optional
}

pack AssetDependency {
    fin asset: AssetId
    fin kind: AssetDependencyKind
}

pack AssetRecord {
    fin id: AssetId
    fin kind: AssetKindId
    fin displayName: std::String
    fin importer: ContentSymbol
    fin importerVersion: std::Int
    fin dependencies: std::Array<AssetDependency>
}

pack CookVariant {
    fin platform: ContentSymbol
    fin graphicsTier: ContentSymbol
    fin locale: ContentSymbol
    fin quality: std::Int
}
```

Asset and subasset symbols are stored in sidecar/source metadata and survive
rename or move. A content hash identifies immutable cooked bytes, not semantic
identity: editing an asset changes its `ArtifactId` generation while preserving
its `AssetId`.

## 4. Source, imported document, and artifact

The pipeline has three deliberately distinct representations:

1. source files are author-owned inputs such as PNG, glTF, WAV, shader source,
   AZON Scene, or a procedural recipe;
2. an imported document is normalized, typed, platform-neutral data with stable
   subasset symbols and diagnostics;
3. cooked artifacts are immutable target variants optimized for runtime loading.

Runtime packages contain artifacts and manifests, not arbitrary editor source.
The editor can retain source for inspection but must never make a shipping game
depend on a host application or source codec accidentally.

## 5. Importers, processors, and cookers

An importer is selected by explicit asset kind first and extension/magic only as
an authoring convenience. It declares its stable symbol, version, supported
source signatures, settings schema, output kinds, deterministic dependency
scanner, and sandbox requirements. Processors build semantic products such as
mesh LODs, texture mip chains, animation clips, Material graphs, navmesh input,
audio seek tables, or font atlases. Cookers emit target artifacts.

Each stage receives immutable input and returns output plus structured
diagnostics and dependencies. It cannot mutate the registry during execution.
Nondeterministic stages declare and record their seed/tool/environment inputs.

## 6. Dependency graph and invalidation

Hard dependencies must be valid and cooked before publication. Soft dependencies
produce symbolic handles and declared fallbacks. Build-only dependencies affect
cooking but are not shipped. Editor-only dependencies never enter a runtime
manifest. Optional dependencies may be absent without changing schema validity.

The graph is keyed by symbols. Cyclic hard dependencies are errors except for
formats represented by a validated two-pass reference group. Invalidation walks
reverse dependencies by changed source hash, importer/cooker version, settings,
target profile, compiler ABI, or transitive artifact. Rebuilds publish a new
immutable generation atomically.

## 7. Variants and subassets

Variants cover platform, GPU family, compression format, quality tier, locale,
accessibility content, server/client role, and feature capabilities. Selection is
deterministic against a Build target and runtime capability record. Every asset
declares a fallback chain; silently selecting an unrelated source file is not a
fallback.

One source may produce stable subassets such as mesh primitives, animations,
materials, audio tracks, or sprite regions. Reimport matches embedded source IDs
or explicit sidecar IDs, never display names alone. Removed subassets become
tombstones long enough to produce useful reference diagnostics.

## 8. Registry, cache, and manifests

The authoring registry maps Asset IDs to source records and settings. The cooked
manifest maps `(AssetId, CookVariant)` to an artifact, dependencies, byte ranges,
compression/checksum, estimated memory, schema, and fallback. Streaming consumes
only this runtime manifest.

The artifact cache is content-addressed, bounded, checksummed, and safe for
concurrent readers. Local and remote cache entries are accepted only after all
declared build inputs and tool identities match. Cache eviction cannot delete
source data. Garbage collection traces manifests and active builds before
retiring unreferenced artifacts.

## 9. Hot reload and editor workflow

File watching queues a debounced import request; it never reloads on the watcher
thread. A successful cook publishes a new artifact generation. Scene, Prefab,
Material, and other owners decide how to patch live state. A failed import keeps
the previous good generation and surfaces diagnostics.

Move/rename, duplicate, reimport, change importer, delete, restore, and fix-up
references are explicit transactions. Deleting an asset reports reverse
dependencies before creating a tombstone. Generated asset IDs are never inferred
again from the new path.

## 10. Build and Streaming boundary

Build selects target variants, invokes the asset graph, verifies closure, strips
editor/debug data by policy, groups artifacts into bundles, and signs/packages
them. Assets does not deploy applications.

Streaming accepts cooked manifest demand and manages reads, decode, upload,
leases, residency, generation publication, and eviction. Assets does not own
frame deadlines or GPU memory. Subsystems consume typed handles rather than
looking up raw bytes by filename.

## 11. Security and reproducibility

Importers process untrusted files with byte, depth, object-count, decompression,
time, and path limits. External tools run in a declared sandbox with no ambient
network by default. Paths are normalized under allowed roots; archives cannot
escape their destination. Artifacts include checksums and schema/tool versions.
Secrets, signing keys, absolute user paths, and nondeterministic timestamps never
enter cache keys or shipped metadata.

## 12. Diagnostics, tests, and delivery

The asset inspector shows source/subasset IDs, importer/settings, target
variants, dependencies/reverse dependencies, hashes, cache hits, artifacts,
bundle placement, last diagnostics, and live generations. Profiler flows connect
import/cook and runtime read/decode/upload by Asset ID.

Required tests cover move/rename stability, same-named subassets, deterministic
recook, importer-version invalidation, dependency cycles, soft fallback, target
selection, cache corruption, hostile files, failed-hot-reload rollback, deleted
tombstones, and reproducible manifests.

Delivery:

1. Asset/Artifact IDs, source registry, importer API, diagnostics, local cache;
2. dependency/reverse graph, incremental cook, target variants, runtime manifest;
3. Image/Font/Shader/Audio/Scene importers and direct-path migration;
4. Streaming handles, hot reload, editor transactions, bundle planning;
5. remote cache, distributed cooking, package assets, and full reproducibility.
