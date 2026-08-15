# Azora Serialization — AZON Scenes, Resources, and Runtime State

Status: Proposal building on the implemented `std.serializer`
Primary package: `azora-serialization`
Primary module: `engine.serialization`

## 1. Decision

AZON is the canonical human-readable serialization format for engine source and
interchange data, including Scenes, Prefabs, resources, settings, and inspectable
runtime snapshots. The engine reuses `std.serializer` and its compiler-derived
codecs. `engine.serialization` adds stable schema identity, component/resource
registration, graph references, version migrations, unknown-data preservation,
and bounded decoding. It does not create a competing text parser or reflection
system.

Build may emit a compact target-specific binary cache from the same registered
schemas for startup speed. That cache is derived and disposable; AZON remains
the portable source representation.

## 2. Current language and engine audit

Azora language already provides:

- `std::SerialValue` with null, Boolean, exact-number text, text, array, and
  insertion-ordered object values;
- strict `encodeSerialValue`/`decodeSerialValue` with `:` separators, duplicate
  rejection, exact number preservation, maximum depth, and input-size limits;
- `std::Serializer<T>` and `std::AzonSerializer<T>` extension contracts;
- compiler derivation through `@std::Serializable` and
  `@std::AzonSerializable`;
- `@std::SerialName`, `@std::SerialIgnore`, `@std::SerialRequired`, unknown-field
  policy, and default-field encoding policy.

The current deriver handles primitive fields, nested serializable non-generic
packs, nullable primitives, primitive `List`/`Set` elements, and String-keyed
primitive maps. Engine graphs still need generated support for arrays, enums,
variant enums, nested collections, concrete generic fields, schema descriptors,
field aliases, references, and unknown component payload preservation. The
engine itself has no component/resource serializer registry or migration graph.

## 3. Typed AZON remains ordinary Azora

```azora
import std.serializer

@std::Serializable(ignoreUnknownFields: true, encodeDefaults: false)
pack SceneHeader {
    fin schemaVersion: std::Int = 1
    fin sceneSymbol: std::Long = 0L
    fin displayName: std::String = ""
    fin enabled: std::Bool = true
}
```

The compiler generates `toSerialValue`, `fromSerialValue`, `toAzon`, and
`fromAzon` implementations on the pack. Engine types should use this mechanism
where their fields are value-shaped. Custom graph/resource codecs implement the
same contracts and compose through `SerialValue`.

Canonical AZON output is deterministic and JSON-shaped:

```azon
{
  "schemaVersion": 1,
  "sceneSymbol": 481921,
  "displayName": "Town",
  "enabled": true
}
```

Manifest-style relaxed source syntax, if retained by package tooling, must be
normalized through an explicit parser mode. Save/network/security boundaries use
strict canonical AZON and never guess a dialect.

## 4. Schema identity and registry

```azora
pack SchemaId {
    fin symbol: ContentSymbol
}

pack SchemaVersion {
    fin value: std::Int
}

enum SchemaKind {
    Value
    Component
    Resource
    Scene
    Prefab
    SaveSection
}

pack SchemaDescriptor {
    fin id: SchemaId
    fin version: SchemaVersion
    fin kind: SchemaKind
    fin displayName: std::String
    fin fields: std::Array<FieldDescriptor>
}

spec RegisteredCodec<T> {
    func schema[self: Self&](): SchemaDescriptor
    func encode[self: Self&](value: T&): std::SerialValue ?! SerializationFault
    func decode[self: Self&](value: std::SerialValue&): T ?! SerializationFault
}
```

Public codecs remain statically typed. The compiler/linker generates private
registry thunks for known component/resource storage; arbitrary user-visible
`Any`, raw pointers, and unrestricted runtime reflection are not part of the
wire API. Registrations are generated from stable declaration symbols. Duplicate
Schema IDs, version regressions, and incompatible field-symbol reuse fail at
build/startup.

Field names are wire labels; field symbols are migration and tooling identity.
Renames use aliases/migrations, not permanent duplicate state. Names may be the
same in unrelated schemas without collision.

## 5. Graph encoding and references

Scene, Prefab, and runtime snapshots are object graphs, not recursive copies.
Every serialized object receives a domain-specific stable ID. Records encode
references as typed symbolic IDs. Decode runs in two passes: allocate/validate
all records, then resolve references. Missing soft references remain symbolic;
missing hard references fail the containing transaction.

Cycles are therefore legal where the owning domain permits them, while nesting
and object-count limits prevent hostile graphs. ECS `Entity`, pointer, native
handle, GPU address, array index, and provider object are forbidden wire values.
SceneNodeId, WorldObjectId, AssetId, and other stable domain IDs replace them.

## 6. Components, resources, and runtime state

Serializable ECS components opt in through a registered component schema.
Transient/cache/native fields use `@std::SerialIgnore` with a default or a custom
codec. Components can declare domains such as Scene source, Prefab source,
Save, Replay, Network, editor undo, or debug snapshot; being serializable does
not imply inclusion in every domain.

Resources have explicit ownership and multiplicity. Process-global services,
devices, worker pools, open files, sockets, decoder state, and GPU objects are
reconstructed by providers rather than serialized. Runtime snapshots occur at a
declared schedule boundary or from immutable copy-on-write generations; codecs
never race live component mutation.

## 7. Versioning and migrations

Every root document and registered schema has a monotonic integer version.
Migrations form an acyclic chain over `SerialValue`, allowing a document to be
upgraded before typed decode. A migration is deterministic, bounded, pure with
respect to ambient engine state, and identified by stable symbol/version.

Supported operations include rename with alias, add default, split/merge field,
unit conversion, enum-case mapping, reference-domain conversion, and structural
record rewrite. Destructive or ambiguous migration produces a diagnostic with
the schema, field path, old version, and source location. Build can eagerly
rewrite source; Save upgrades a copied slot transactionally.

Forward compatibility is domain-specific. Scene/Prefab editor loads preserve
unknown fields and unknown component records byte-for-value-tree so plugins can
round trip. Runtime and Save reject unknown required schemas. `ignoreUnknownFields`
is used deliberately, not globally.

## 8. Determinism and canonical form

Canonical writers use stable root/record/schema/field ordering, exact numeric
tokens, normalized string escaping, and documented treatment of negative zero,
non-finite floats, defaults, and nulls. Unordered maps/sets are sorted by their
canonical key representation before writing. Pretty formatting changes
whitespace only.

Deterministic serialization is necessary but not sufficient for deterministic
simulation: snapshots also record clock/tick/content generations and apply at a
schedule boundary. Hashes are computed over canonical bytes plus schema/content
identity.

## 9. Safety, limits, and diagnostics

Each domain configures maximum input bytes, depth, records, fields, collection
elements, string bytes, total decoded allocation, migration steps, and time.
Declared lengths never allocate before validation. Duplicate fields, invalid
UTF escapes, trailing content, unsupported numbers, invalid references, and
schema mismatches are typed failures. Error paths use stable schema/field IDs
with optional display labels and never expose secrets by default.

The inspector can display AZON trees, schema versions, field symbols, unknown
data, references, migrations, encoded/decoded byte sizes, defaults omitted, and
canonical hashes. Profiler counters cover parse, migration, allocation, graph
resolution, encode time, size, failure, and preserved unknown bytes.

## 10. Delivery and acceptance

1. engine schema descriptors/registry, stable field symbols, bounded domain
   options, and component/resource opt-in;
2. extend compiler derivation for engine arrays, enums/variants, nested
   collections, concrete generics, aliases, and schema metadata;
3. graph IDs/two-pass references, Scene/Prefab AZON, unknown payload round trip;
4. migration registry, canonical hashing, runtime snapshots, editor inspection;
5. cooked binary cache generated from the same schemas and cross-version corpus.

Acceptance requires canonical round trips; two unrelated same-named fields
remaining distinct; exact large numbers; rename aliases; migration determinism;
unknown-plugin preservation; graph cycles/reference failures; strict limits;
fuzzing; corrupt/truncated input; Save/Scene/Prefab fixtures from every released
schema; and no native/transient identity in serialized output.
