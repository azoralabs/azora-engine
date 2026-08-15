# Azora Cinematics — Sequencer and Timeline System

Status: Proposal
Primary package: `azora-cinematics`
Primary module: `engine.cinematics`

## 1. Decision

Cinematics is a non-linear sequencer that evaluates versioned timeline assets
into reversible property, animation, camera, audio, event, media, visibility,
spawn, and custom track commands. It orchestrates subsystem APIs but never
reimplements Animation, Camera, Audio, Video, PostFX, or World.

The same evaluation core supports editor scrubbing, runtime playback, nested
sequences, deterministic event crossing, offline rendering, networking, and
Replay integration.

## 2. Current engine audit

`engine.animation.core.Timeline` can group animation players, advance them,
normalize weights, and evaluate events. Video has a session clock/frame queue;
Audio has media time, buses, and PCM foundations. Camera is currently only a
fly camera. There is no general sequence asset, track binding, property system,
nested time transform, camera cuts, audio/video clips, editor, or reversible
evaluation. The existing animation timeline remains a lower-level timing tool.

## 3. Public model

```azora
pack SequenceId {
    fin value: std::Long
}

pack TrackId {
    fin value: std::Long
}

pack BindingId {
    fin value: std::Long
}

enum SequenceState {
    Stopped
    Playing
    Paused
    Scrubbing
    Finished
}

@Component
pack SequencePlayer {
    fin sequence: SequenceId
    var state: SequenceState
    var time: MediaTime
    var rate: std::Double
    var loop: std::Bool
    var generation: std::Long
}

pack SequenceBinding {
    fin id: BindingId
    fin target: WorldObjectId
    fin role: ContentSymbol
}
```

Track, section, channel, binding, property, and event identities are stable
symbols. Display names may repeat freely.

## 4. Time and evaluation

All sequence time is rational/integer `MediaTime`. A playback context defines
previous/current time, direction, status, discontinuity/cut generation, root-to-
local transform, and evaluation purpose. Scrubbing evaluates absolute state;
playing additionally crosses event ranges. Reverse and loop crossing have
defined inclusive/exclusive endpoints to prevent duplicate events.

Evaluation produces a sorted command buffer. Commands blend by property symbol,
track priority, section weight, and stable symbol order. Applying commands is a
separate schedule phase, enabling headless tests and conflict diagnostics.

## 5. Built-in tracks

- Transform/property tracks with typed channels and interpolation.
- Animation tracks with clip trims, blends, sync, root-motion policy.
- Camera cuts, rig parameters, lens, focus, and blend tracks.
- Audio clips, bus routing, gain/pan, fades, and sample-accurate scheduling.
- Video clips/surfaces and subtitle/metadata events.
- PostFX volume/profile parameters and exposure cuts.
- Event/signal tracks with payload schema and authority policy.
- Visibility, material parameter, particle, spawn/despawn, and data-layer tracks.
- Nested sequence tracks with time scale, offset, loop, and hierarchical bias.

## 6. Spawn and restoration

Possessable bindings resolve existing `WorldObjectId` values. Spawnable bindings
create sequence-owned entities from prefabs and destroy or retain them by
completion policy. Before first write, Cinematics captures the pre-animated
value through a typed property adapter. Stop/cancel restores, keeps, or commits
as selected; restoration is stack-aware for overlapping sequences.

## 7. Async preparation

Sequence manifests declare referenced clips, materials, media ranges, and cells.
Streaming prefetches by lookahead and playback rate. Missing content uses
section policy: hold, skip, fallback, pause-and-buffer, or fail. Audio deadlines
outrank visual refinement. Seeking cancels stale generations across Video/Audio
and invalidates Camera/PostFX/Radiance histories as required.

## 8. Networking and replay

Authoritative playback replicates sequence symbol, binding map, start tick/time,
rate, generation, and decisions; clients evaluate visual tracks locally against
the network clock. Gameplay events fire only on the authority unless marked
predicted. Replay can either record the sequence command or bake resulting
authoritative events when nondeterministic custom tracks are involved.

## 9. Tooling and delivery

The sequencer shows hierarchy, tracks/sections/channels, bindings, evaluation
field, blend weights, event crossings, content residency, and subsystem commands.
It supports ripple/trim/slip, snapping, markers, multi-select, nested sequence
drill-down, waveform/thumbnail caches, undo, and headless validation.

Delivery:

1. sequence assets, rational time, property/transform/event tracks, command evaluation.
2. Animation and Camera tracks, nested sequences, restoration, editor basics.
3. Audio/Video/PostFX/Material/Particles tracks and Streaming lookahead.
4. networking, Replay, offline rendering, collaborative editor workflow.
5. advanced blending, control rigs, live recording, virtual production/XR tracks.

