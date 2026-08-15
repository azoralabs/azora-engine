# Azora I/O — Buffers, Files, Virtual Sources, and Atomic Storage

Status: Proposal building on a byte-level implementation
Package: `azora-io`
Module: `engine.io`

## 1. Decision

`azora-io` owns safe byte storage, synchronous low-level file primitives,
virtual mounts, random-access streams, atomic writes, and provider contracts for
asynchronous reads. Streaming owns asset residency and lookahead; Jobs executes
background work; Media owns network/media semantics.

Raw addresses and C file handles remain private implementation details. Public
buffers carry ownership, bounds, generation, and release state.

## 2. Current implementation audit

Already implemented:

- whole-file reads into an owned `Blob`;
- bounds checks and little-endian scalar/text access;
- explicit release;
- atomic-ish UTF-8 text replacement through a sibling temporary file;
- the engine's shared raw allocation/peek/poke/copy bridge;
- application exit runtime hooks used by Core.

Important gaps:

- failed reads and empty files are both represented by an empty blob;
- out-of-range scalar access returns zero, which can hide malformed assets;
- only whole-file synchronous reads exist;
- no write bytes, directories, metadata, canonical paths, mounts, streams,
  mapping, URI/provider contract, async I/O, cancellation, or budgets;
- `Blob` exposes a raw address and manual release without generation checks;
- the write fallback removes the destination before a second rename and can
  lose the old file;
- raw memory and process-exit bridges make I/O a dependency for unrelated FFI
  packages.

## 3. Safe storage model

```azora
pack BufferId {
    fin value: std::Long
    fin generation: std::Int
}

pack ByteBuffer {
    fin id: BufferId
    fin size: std::Long
    fin capacity: std::Long
}

pack ByteView {
    fin buffer: BufferId
    fin offset: std::Long
    fin size: std::Long
}

error IoFault {
    NotFound
    PermissionDenied
    InvalidPath
    InvalidRange
    EndOfFile
    Unsupported
    Busy
    Cancelled
    OutOfMemory
    ReadFailed
    WriteFailed
    SyncFailed
}
```

Fallible checked reads return `?! IoFault`. Explicit `readOrZero` helpers exist
only for formats that define zero padding. Views retain or lease their backing
buffer and cannot outlive it. Double release and stale generations are rejected.
`Blob` remains a compatibility wrapper until consumers migrate.

## 4. Files, sources, and mounts

`FileSource` supports size/metadata, bounded reads at offsets, sequential cursors,
and optional mapping. `FileSink` supports bounded writes, flush, durable sync,
and commit/abort. Capabilities tell callers what is available before use.

The virtual filesystem mounts directories, package assets, memory, archives,
save data, temporary data, and provider-defined sources under normalized logical
paths. Logical asset paths never expose platform separators. Canonicalization
cannot escape a mount root.

HTTP is not a mandatory I/O backend. Network providers may implement URI
sources, but cache, authentication, redirects, and policy remain explicit.

## 5. Asynchronous I/O and pressure

Async reads are cancellable requests executed by a platform async provider or
Jobs fallback. Requests declare byte range, priority, deadline hint, owner
symbol, and maximum allocation. Completion publishes one buffer generation.

Every provider bounds open files, mapped bytes, queued operations, in-flight
bytes, and completion records. Pressure is returned to Streaming rather than
hidden in unbounded queues.

## 6. Atomic and durable writes

Atomic replacement writes a uniquely named sibling, flushes data, optionally
syncs the file and directory, then performs one provider-supported replace. If
atomic replace is unavailable, the API reports that capability instead of
deleting the destination. Save systems may keep previous generations and
checksums.

## 7. Security and diagnostics

Providers reject path traversal, integer overflow, oversized allocations,
invalid ranges, archive bombs, unsupported links, and mount escape. Untrusted
formats receive caller-specified byte/decompression/time limits.

Profiler reports open/read/write latency, bytes, cache hits, mappings, queue
pressure, cancellations, short reads, sync cost, allocation, and errors by owner
symbol without logging private path contents by default.

## 8. Delivery and acceptance

1. checked buffer/view ownership and explicit I/O errors;
2. random-access files, byte writes, metadata, and safe atomic replace;
3. virtual mounts and package/save/temp roots;
4. cancellable async providers, budgets, mappings, and Profiler;
5. migrate Image, Font, Tilemap, Media, Streaming, and FFI memory support.

Acceptance requires fuzzed bounds safety, no destination loss on failed atomic
write, mount-escape tests, stale-handle rejection, bounded async pressure, and
successful native/WebAssembly provider conformance.
