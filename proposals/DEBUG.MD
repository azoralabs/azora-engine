# Azora Debug — Visual and Remote Engine Diagnostics

Status: Proposal
Primary package: `azora-debug`
Primary module: `engine.debug`
Optional UI package: `azora-debug-ui`

## 1. Decision

Azora Debug is the unified development inspection and control layer for live
engine state. It provides bounded debug drawing, immutable subsystem snapshots,
inspectors, entity/resource selection, pause/step/capture commands, diagnostic
overlays, and an authenticated remote protocol. It explains state; Profiler
measures cost. Neither is gameplay authority.

Core systems expose small debug adapters or generic snapshots and never import
Debug UI. Shipping builds can compile Debug out or retain a minimal authorized
diagnostic subset.

## 2. Current engine audit

There is no unified debug package or visual debugger. Existing proposals each
name useful views—ECS plans/query access, physics contacts, navigation meshes,
render passes, streaming residency, media queues, and so on—but no shared draw
transport, category registry, selection identity, snapshot protocol, remote
transport, pause/step ownership, capture bundle, privacy policy, or overlay UI
exists.

## 3. Debug identity and model

```azora
pack DebugCategoryId {
    fin symbol: ContentSymbol
}

pack DebugObjectId {
    fin domain: ContentSymbol
    fin object: ContentSymbol
    fin generation: std::Long
}

enum DebugDepthMode {
    Tested
    Always
    XRay
}

pack DebugStyle {
    fin color: Color
    fin thickness: std::Double
    fin depth: DebugDepthMode
    fin lifetime: std::Double
}

variant enum DebugPrimitive {
    Point(position: Vec3, style: DebugStyle)
    Line(start: Vec3, end: Vec3, style: DebugStyle)
    Box(bounds: Bounds3, transform: Transform3, style: DebugStyle)
    Sphere(center: Vec3, radius: std::Double, style: DebugStyle)
    Text(position: Vec3, value: std::String, style: DebugStyle)
}

enum DebugRunState {
    Running
    Paused
    SteppingFrame
    SteppingFixedTick
}
```

Objects use domain-specific stable IDs plus generation. Names are labels only.
ECS entities may be selected by a transient runtime key, but persistent bookmarks
require SceneNodeId, WorldObjectId, AssetId, or another stable owner identity.

## 4. Bounded debug drawing

Any thread may enqueue fixed-size primitives into a preallocated per-thread
buffer. Categories, layer masks, lifetime, depth policy, view family, and owner
allow filtering. Dynamic strings use a bounded intern/snapshot path and are
forbidden in real-time audio callbacks.

At frame extraction, Debug merges commands deterministically, expires old
primitives, converts large-world coordinates relative to each view, and submits
one Render adapter pass. Overflow drops lowest-priority/oldest commands by policy
and reports exact gaps. Debug drawing never blocks simulation and never changes
collision, visibility, navigation, or gameplay state.

Persistent primitives are handles owned by a subsystem and updated by generation;
they are not re-enqueued forever. Screen-space overlays and world-space drawing
share categories but use distinct coordinate types.

## 5. Snapshot and adapter model

An inspected subsystem publishes an immutable, versioned snapshot at a safe
boundary. Snapshots are typed, paged, size-bounded, privacy-filtered, and may
degrade detail under budget. Debug UI reads them asynchronously. It never walks
mutable ECS storage, GPU driver objects, physics broadphase memory, or job queues
without the owning subsystem.

Adapters expose:

- capability/schema description;
- summary counters and health;
- paged object enumeration keyed by stable/runtime IDs;
- selected-object details and relationships;
- optional safe commands with authorization and validation;
- optional draw contribution and capture attachment.

Unknown adapter versions remain skippable. One broken inspector cannot stop the
game or corrupt a capture.

## 6. Core inspectors

- ECS: entities, component schemas, archetypes/storages, query plans, access
  conflicts, change revisions, schedules, and command buffers.
- Scene/Prefab: hierarchy, transforms, source/instance mapping, overrides,
  activation, ownership, and unresolved references.
- Assets/Streaming: source/cooked dependency graph, generations, requests,
  residency, fallbacks, leases, bundles, memory, and hot reload.
- Render/GPU: cameras/view families, extracted objects, render graph, resources,
  barriers, pipeline/material state, draw/dispatch lists, shader diagnostics,
  overdraw, wireframe, and resource previews.
- Physics: shapes, AABBs, broadphase pairs, contacts, constraints, sleeping,
  islands, CCD paths, collision layers, and solver error.
- Traverse: navmesh polygons/links, costs, path corridor, queries, crowd agents,
  avoidance velocities, and dynamic obstacles.
- World: cells, anchors, layers, origin, object ownership, transactions, and
  unresolved cross-cell references.
- Input/UI/Accessibility: devices/actions/contexts, focus/hit test/layout,
  semantic tree, contrast, captions, and platform bridge.
- Jobs/Profiler: queues, workers, dependencies, waits, deadlines, and links to
  timeline captures without duplicating Profiler storage.
- Audio/Video/Network: buses/voices/queues, A/V clocks/frames, replication,
  prediction, interpolation, rollback, and packet simulation state.

## 7. Pause, step, and safe commands

App owns the global run state. Debug can request pause, resume, one rendered
frame, one fixed tick, one ECS phase, or capture at a supported boundary. Audio,
network keepalive, platform event pumping, and remote control follow explicit
pause policies rather than freezing arbitrary threads.

Commands such as select, teleport development entity, reload asset, invalidate
shader, toggle collision layer, set time scale, or inject test input are
registered by their owner. Each declares build availability, permission,
argument schema, determinism/replay behavior, required pause state, and undo
policy. Debug cannot write arbitrary memory or set component fields by name.

## 8. Capture bundles

A diagnostic capture contains a canonical manifest plus selected immutable
snapshots, recent logs, asset/build IDs, capability records, optional screenshot,
Profiler trace reference, and gap/redaction report. Large GPU resources, save
data, network payloads, text input, media samples, and user content are excluded
unless explicitly selected and authorized.

Subsystem captures correlate through stable context/resource IDs and one clock
mapping. A capture truncated during writing retains complete previous chunks.
Readers validate size, checksums, schema, and decompression limits.

## 9. Remote debugging

Remote is disabled by default and development-only unless a product explicitly
ships support. The game opens no public listener implicitly. Connections require
user-visible enablement, authenticated pairing, encryption, capability
negotiation, per-command authorization, byte/rate limits, inactivity timeout,
and an audit log.

Snapshots and draw streams apply backpressure and quality reduction. Control
commands use request IDs and committed results; reconnect never repeats a
non-idempotent command by accident. Console/mobile providers may use platform
approved transports without changing the engine protocol.

## 10. Profiler, logs, and error boundary

Profiler answers when and how much; Debug answers what state produced it. Debug
links selected objects/passes/jobs/assets to Profiler site/context IDs. It does
not record high-volume timelines itself. Logs are event summaries and searchable
diagnostics, not a substitute for typed snapshots.

Errors include stable subsystem/site/object identity, severity, lifecycle,
related objects, remediation, and bounded attributes. Repeated equivalent errors
coalesce with counts. Debug UI failure cannot become an engine failure.

## 11. Packaging, performance, and privacy

`azora-debug` contains neutral transport/types and can be retained in
development/profile builds. `azora-debug-ui` depends on UI/Render and remains
optional. Release builds strip source paths, editor commands, remote listener,
shader source, and private symbols by policy. A minimal crash/health adapter may
remain only when explicitly configured.

All queues, snapshots, retained primitives, strings, captures, and remote bytes
are bounded. Disabled categories are nearly free. Debug reports its own CPU/GPU,
memory, bandwidth, dropped records, stale snapshots, and impact on frame time.

## 12. Tests and delivery

Required tests cover stable same-named identities, producer overflow, deep/world
coordinates, pause/step boundaries, immutable snapshot races, paging, stale
generations, malformed remote/capture data, authentication, command permissions,
redaction, owner unload, Render unavailable/headless mode, and disabled overhead.

Delivery:

1. categories/IDs, bounded debug draw, Render adapter, overlay toggles;
2. snapshot/adapter registry and ECS, Scene, Physics, Traverse, World inspectors;
3. Assets/Streaming and Render/GPU inspectors, capture bundles, Profiler links;
4. Input/UI/Accessibility/media/network inspectors and safe command registry;
5. authenticated remote protocol, editor integration, release stripping/audits.
