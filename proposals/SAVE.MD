# Azora Save — Save Games and Persistent State

Status: Proposal
Primary package: `azora-save`
Primary module: `engine.save`

## 1. Decision

Save owns durable user state: settings, profiles, save slots, checkpoints,
autosaves, manifests, atomic commits, compatibility checks, migrations, optional
cloud synchronization, and retention. Serialization owns AZON/schema mechanics.
Scene, World, ECS components, and gameplay systems contribute state through
registered save sections. Platform/I/O owns filesystem and secure-key access.

A save is a consistent logical snapshot assembled at a schedule boundary. It is
never a dump of process memory or live ECS arrays.

## 2. Current engine audit

`engine.io` can read a whole file and write text using a temporary-file pattern
suitable for simple settings metadata. ECS has transient generational entities;
World, Scene, Serialization, and Assets are proposals. There is no slot model,
snapshot protocol, component persistence policy, version/content manifest,
journal, checksum, backup, corruption recovery, retention, cloud conflict, or
save-load transaction.

## 3. Save domains and identity

```azora
pack SaveSlotId {
    fin symbol: ContentSymbol
}

pack SaveRevision {
    fin value: std::Long
}

enum SaveDomain {
    Settings
    Profile
    Campaign
    Checkpoint
    Autosave
    QuickSave
}

enum SaveState {
    Empty
    Reading
    Ready
    Writing
    Corrupt
    Incompatible
    Conflict
}

pack SaveManifest {
    fin slot: SaveSlotId
    fin revision: SaveRevision
    fin domain: SaveDomain
    fin schemaVersion: std::Int
    fin buildId: ContentSymbol
    fin contentSet: ContentSymbol
    fin playTicks: std::Long
    fin checksum: std::String
}

error SaveFault {
    SlotNotFound
    Busy
    IncompatibleContent
    MigrationFailed
    CorruptData
    StorageUnavailable
    QuotaExceeded
    PermissionDenied
    Conflict
    Cancelled
}
```

Slot IDs and section/object symbols remain stable. User-facing names, timestamps,
screenshots, play time, location, and difficulty are manifest metadata, not slot
identity.

## 4. Section contribution model

Each subsystem registers one or more stable Save section schemas and a provider
with three operations: capture immutable state at a declared schedule phase,
restore into a staged load transaction, and validate before publication. Section
dependencies form a DAG. World/Scene identity restores before component
references; gameplay state restores before presentation caches.

Components opt in to Save independently from Network, Replay, or Scene source
serialization. Transient presentation state, devices, jobs, file handles, GPU
objects, decoder queues, and caches are reconstructed. Persistent references use
AssetId, SceneNodeId, WorldObjectId, Prefab instance symbols, or gameplay IDs,
never `Entity`.

## 5. Snapshot and write pipeline

1. queue a save request with slot, reason, deadline, and retention policy;
2. at a safe schedule boundary, freeze/copy registered state into immutable
   section snapshots and record tick/content generations;
3. release gameplay immediately and serialize/compress/checksum in background;
4. write a new revision in a temporary staging directory;
5. fsync files and directory where the platform supports it;
6. atomically replace the current revision pointer;
7. retain the previous known-good revision and apply retention policy;
8. publish success/failure on the main command boundary.

Only the short capture step may pause simulation. A late autosave is skipped or
rescheduled by policy rather than blocking a frame unpredictably. One slot has a
serialized writer; reads use complete immutable revisions.

## 6. File layout and AZON

Small saves may be one strict AZON document. Larger saves use a directory or
container with a canonical AZON manifest and independently checksummed section
payloads. Sections may use canonical AZON directly or a cooked binary cache
derived from the same registered schema. Screenshots are optional assets and are
excluded from logical checksums.

Large World saves use shipped base content plus sparse persistent overlays and
periodic compacted checkpoints. Journals contain idempotent semantic commands
with sequence/tick, not memory deltas. Loading chooses the newest valid
checkpoint and replays complete journal entries, stopping safely at a truncated
tail.

## 7. Load transaction

Load never mutates the active game while parsing. It selects and validates a
revision, checks build/content compatibility, verifies checksums and limits,
migrates copied `SerialValue` sections, resolves required assets, stages
World/Scene/Prefab/ECS state, validates cross-section references, then swaps at a
controlled app state boundary. Failure leaves the current game intact.

Post-load hooks run only after full publication and cannot observe half-restored
state. Unknown optional sections are preserved when resaving if policy permits;
unknown required sections make the save incompatible, not partially loaded.

## 8. Compatibility and migrations

The manifest records engine/game build, schema set, content/DLC/mod set,
platform-independent data version, locale-neutral IDs, and optional gameplay
compatibility range. A newer executable may migrate an older save through the
Serialization migration graph. The original revision is kept until the migrated
save loads and commits successfully.

Missing optional content produces placeholders or disabled sections. Missing
required content explains the exact package/Asset IDs. Downgrade loading is not
assumed. Mods receive namespaces and explicit persistence policy so identical
display names cannot collide.

## 9. Autosave, retention, and storage pressure

Requests coalesce by reason and slot. Policies define minimum interval, safe
gameplay points, maximum capture time, maximum revisions, total quota, and
priority. Manual saves are never evicted to satisfy an autosave quota without
explicit product policy. Storage estimates happen before capture when possible.

Cancellation before commit removes staging data; cancellation after atomic
publication reports success. Low-storage failure retains all known-good
revisions and emits a recoverable UI action.

## 10. Cloud and conflicts

Cloud synchronization is an optional provider above local committed revisions.
It uploads immutable revisions and a manifest using revision ancestry/device
identity. Settings can merge by field policy; world/campaign saves normally
require choosing local, remote, or duplicate-to-new-slot unless the game provides
a semantic merger. “Latest timestamp wins” is not a safe universal rule.

The UI shows device, play time, progress metadata, content compatibility, and
both backups before destructive conflict resolution. Network outages never block
local save completion.

## 11. Security and privacy

Checksums detect corruption, not malicious modification. Optional authenticated
encryption uses a Platform secure-key provider and per-revision nonces; no key is
stored beside the save. Games may sign authoritative progression sections but
must not treat client storage as an unbreakable trust boundary.

Decoders enforce byte/depth/object/allocation/migration limits. File names are
derived from validated slot IDs under a Save root. Personal metadata, text input,
analytics IDs, and profiler details are excluded unless a product explicitly
defines them as user state.

## 12. Diagnostics, tests, and delivery

The Save inspector shows slots/revisions, section schemas/sizes, capture/write
time, checksums, content requirements, migration path, backups, retention,
pending requests, and cloud ancestry without revealing encrypted content.

Required tests include crash/truncation at every write phase, disk full,
permission loss, concurrent requests, cancellation boundaries, deterministic
snapshots, unknown sections, migration failure rollback, same-named stable IDs,
missing content, journal recovery, backup selection, cloud forks, encryption key
loss, and hostile declared sizes.

Delivery:

1. local slots/manifests, section registry, immutable capture, atomic AZON write;
2. staged load, compatibility/migrations, checksums, backup and retention;
3. Scene/Prefab/World overlays, component persistence, journal/checkpoint model;
4. screenshots/metadata UI, storage pressure, platform directories/encryption;
5. cloud provider/conflict UX, mod namespaces, long-term compatibility corpus.
