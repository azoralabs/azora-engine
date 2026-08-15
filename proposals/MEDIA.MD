# Azora Media Core — Sources, Time, Tracks, and Provider Selection

Status: Proposal building on an implemented shared media contract
Package: `azora-media-core`
Module: `engine.media`

## 1. Decision

`azora-media-core` is the container-neutral contract shared by Audio, Video,
subtitles, and media-player composition. It owns exact media time, source
descriptions, container/stream/track metadata, packet/frame timing vocabulary,
provider capabilities and selection, chapters, attachments, cancellation, and
session clock synchronization.

It does not own audio mixing, video rendering, subtitle UI styling, filesystem
storage, network policy, or a particular FFmpeg/platform decoder.

## 2. Current implementation audit

Already implemented and tested:

- stable `StreamId` and `TrackId` wrappers;
- rational `MediaTime`, conversion, rescale, add/subtract, compare, and clamp;
- path, borrowed bytes, and URI source variants;
- stream/container metadata and stream counting;
- `MediaError`, provider capability records, and `MediaProvider` probing;
- deterministic fake-provider tests with video/audio/subtitle streams.

Gaps:

- rational operations can overflow and do not normalize fractions;
- IDs are local integers without source/session scope or generations;
- source ownership and lifetime for byte blobs are ambiguous;
- provider selection, priority, fallback, and diagnostics are not defined;
- probe is synchronous and the provider contract stops before open/demux;
- packets, decoded-frame timing, discontinuities, chapters, attachments,
  metadata dictionaries, track groups, and subtitle cues are absent;
- cancellation, seek generations, live windows, buffering, DRM policy, and
  network-source policy are absent.

## 3. Identity and exact time

```azora
pack MediaSessionId {
    fin value: std::Long
    fin generation: std::Int
}

pack MediaStreamId {
    fin session: MediaSessionId
    fin value: std::Int
}

pack MediaTime {
    fin ticks: std::Long
    fin timeBaseNum: std::Int
    fin timeBaseDen: std::Int
}

enum MediaDiscontinuity {
    None
    Seek
    TimelineReset
    SourceChange
    Gap
}
```

Time construction validates positive bases and normalizes common factors.
Arithmetic uses checked reduction before multiplication and reports overflow.
Unknown duration, positive/negative infinity, and invalid timestamps are tagged
states rather than magic tick values.

Stream and track identity is scoped by an opened session generation. Display
titles, codec names, and language tags remain metadata.

## 4. Source and provider contract

Media sources reference I/O sources or owned byte leases rather than embedding
an ambiguously owned `Blob`. URI use is capability and policy controlled.
Providers advertise containers, codecs, software/hardware decode, zero-copy
surfaces, seek modes, live input, subtitles, attachments, thread safety, and
platform constraints.

Selection scores providers against required capabilities and explicit caller
preference, then returns a trace explaining every rejection/fallback. Bundled
FFmpeg and platform hardware providers implement the same open/demux contract.

Opening creates a generation-scoped session. Probe/open/read/seek/close are
cancellable and asynchronous where they can block. No decoder call occurs on
the audio callback or render submission thread.

## 5. Packets, tracks, and timeline

Core packet metadata includes stream ID, decode/presentation timestamps,
duration, byte lease, key/discard flags, and discontinuity generation. Audio
and Video own decoded payloads but use shared timing and source identity.

Tracks can group alternate streams by role, language, accessibility, angle, or
quality. Chapters, global/container metadata, cover art, fonts, and attachments
use stable IDs and bounded byte leases. Subtitle cues carry timing, text/markup,
regions, and attachment references; `engine.videoplayer` maps them into UI.

Seek increments a generation. Packets, decoded frames, cues, and jobs from an
old generation are discarded before publication. Live sessions expose a moving
seekable window and timeline discontinuities explicitly.

## 6. Clocks and buffering

Media Core defines clock snapshots and drift measurements. Audio is the normal
master when active; an external/monotonic clock leads silent video; live and
networked applications may supply another master. Audio and Video implement
their own queues but report duration, pressure, underrun, and generation using
the shared contract.

## 7. Diagnostics and delivery

Diagnostics expose selected provider, rejection trace, source policy, stream
and track metadata, packet timing, queue duration, seek generation, live window,
clock master, drift, discontinuities, bytes, cancellation, and errors.

Delivery:

1. harden rational time and source ownership while preserving current APIs;
2. add scoped identities, provider selection traces, async open, and sessions;
3. add packet/track/chapter/attachment/subtitle contracts and seek generations;
4. integrate bundled FFmpeg and hardware providers with Audio/Video;
5. add live sources, network policy, clocks, fuzzing, and conformance suites.

Acceptance requires exact long-playback ordering, checked overflow, stale seek
work rejection, deterministic provider selection, bounded untrusted metadata,
and no dependency from Media Core to Audio, Video, UI, GPU, or a decoder
implementation.
