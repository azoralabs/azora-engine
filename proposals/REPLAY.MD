# Azora Replay — Recording, Playback, Rewind, and Demos

Status: Proposal
Primary package: `azora-replay`
Primary module: `engine.replay`

## 1. Decision

Replay supports two complementary formats: deterministic command replay for
small, exact simulation captures, and state-stream replay for robust playback of
networked or nondeterministic sessions. Both use the same chunked container,
schema symbols, timeline, snapshots, seek index, validation, and inspection API.
Games may combine them per subsystem.

## 2. Current engine audit

No replay package or world serializer exists. ECS has generational entities,
storages, revisions, events, fixed timestep fields, and deferred commands but no
stable cross-session entity symbols or snapshot API. Input lacks action command
frames. Animation/Physics/Networking proposals define deterministic tiers and
snapshots. Profiler has a separate `.aztrace` design; replay references trace
contexts but must not embed profiler implementation records as gameplay state.

## 3. Public model

```azora
pack ReplayId {
    fin value: std::Long
}

pack ReplayFrame {
    fin tick: std::Long
    fin time: MediaTime
}

enum ReplayMode {
    Commands
    States
    Hybrid
}

enum ReplayState {
    Idle
    Recording
    Playing
    Seeking
    Paused
    Finished
    Failed
}

@Resource
pack ReplaySession {
    fin id: ReplayId
    var mode: ReplayMode
    var state: ReplayState
    var frame: ReplayFrame
    var generation: std::Long
}
```

## 4. File format

The chunked format stores header/version, schema/content/build hashes, session
metadata, initial manifests, snapshots, command/event/state chunks, World cell
events, origin rebases, seek index, checksums, and optional annotations. Chunks
are independently compressed and length/checksum guarded so a truncated capture
remains readable through its last complete chunk.

Sensitive fields and player identifiers have redaction policy. Captures never
upload automatically.

## 5. Command replay

Command mode records quantized Input actions, deterministic seeds, authoritative
commands/events, cell generations, and configuration. Playback restores an
initial snapshot and runs the normal fixed-step schedule. Periodic checksums over
declared authoritative state detect divergence and identify the first subsystem/
symbol mismatch.

Only systems that declare replay-safe effects run during resimulation. Audio,
particles, haptics, and similar cosmetics regenerate from confirmed semantic
events and suppress duplicate side effects while seeking.

## 6. State replay

State mode records schema-generated entity/component snapshots and deltas keyed
by stable network/world symbols. Playback interpolates visual states and applies
events without requiring the original simulation to be deterministic. It is the
default for multiplayer demos and user bug captures. Authority-only fields can
be omitted or encrypted by capture policy.

## 7. Seeking and rewind

Seeking chooses the nearest prior snapshot, stages required World/Streaming
content, restores subsystem states, then applies chunks or resimulates to target.
A generation token cancels stale seeks. Camera, PostFX, Radiance, Video, Audio,
Animation, Particles, Physics, Cognition, and Cinematics receive explicit seek/reset
contracts.

Gameplay rewind uses an in-memory ring of compact snapshots plus commands. It
has strict memory/time bounds and is independent from disk recording.

## 8. Networking and spectators

Network servers can record the same snapshots/deltas sent to clients plus
authoritative hidden state selected by policy. Kill-cam and instant replay use a
bounded server/client history with delayed spectator playback. Replay files can
be streamed progressively once header/index segments are available.

## 9. Diagnostics and delivery

Inspector tooling shows tracks, entities/components, commands, events, snapshots,
cell residency, checksums, divergence, bytes by schema symbol, and seek cost.
Counters include capture bytes/rate, compression, dropped optional records,
snapshot time, seek/resimulation time, divergence, and ring pressure.

Delivery:

1. chunk format, schema symbols, fake-clock tests, basic event/command recording.
2. ECS snapshots/deltas, stable object mapping, seek index, state playback.
3. Input command replay, checksums, Physics/Animation reset contracts.
4. Networking demos, rewind ring, World/Streaming/Cinematics/media integration.
5. editor inspector, crash-safe flight recorder, sharing/redaction tools.
