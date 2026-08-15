 # Video Playback and Media Surfaces for Azora Engine

 Status: Proposal
 Scope: local movie playback first; extensible media playback later
 Initial containers: `.avi` and `.mkv`
 Primary integration: `engine.video`, `engine.audio`, `engine.gpu`, `engine.render`, `engine.videoplayer`

 ## 1. Summary

 Azora Engine needs a first-class media layer instead of treating a movie as a sequence of images and sound effects. The engine should be able to open a local AVI or Matroska file, inspect its streams, decode audio and video asynchronously, keep both streams synchronized, upload frames to the GPU, and present the result in a render or reactive UI surface.

 The proposal separates four concerns:

 1. **Container and codec providers** demux packets and decode compressed data.
 2. **Media sessions** own queues, stream selection, seeking, clocks, and lifecycle.
 3. **`engine.audio`** owns timestamped PCM delivery, device output, mixing, and audio focus.
 4. **`engine.video`** owns decoded frames, color conversion, GPU surfaces, presentation, and subtitle cues.
 5. **`engine.videoplayer`** composes `engine.video`, `engine.audio`, and `engine.ui` into a player screen, controls, and subtitle presentation.

 The public Azora API must not expose FFmpeg, AVFoundation, VideoToolbox, or Metal types. Providers may use those implementations internally, but application code sees stable Azora handles and value types.

 The initial implementation should use an FFmpeg-backed provider for AVI and MKV. FFmpeg's `libavformat` is the appropriate demuxing boundary because container support and codec support are separate concerns; the provider must report the actual streams and codecs instead of assuming that a file extension describes the contents. See the [FFmpeg formats documentation](https://ffmpeg.org/ffmpeg-formats.html).

 ## 2. Goals

 ### 2.1 Required first release

 The first usable release must:

 - open a local `.avi` file;
 - open a local `.mkv` file;
 - identify all audio, video, subtitle, attachment, chapter, and metadata streams that the provider can inspect;
 - select a video stream and an audio stream independently;
 - decode video on worker threads without blocking the render loop;
 - decode audio into the real-time `engine.audio` pipeline;
 - play, pause, stop, restart, and loop;
 - seek by timestamp and report when the seek has taken effect;
 - preserve presentation timestamps, including files with B-frames, variable frame rate, or non-zero start time;
 - keep video synchronized to audio when an audible track exists;
 - render frames into an `engine.gpu` texture or a CPU fallback surface;
 - handle aspect ratio, pixel aspect ratio, rotation metadata, color range, and common YUV formats;
 - expose loading, buffering, ready, playing, paused, ended, and error states;
 - release all demuxer, decoder, queue, texture, and audio resources deterministically.

 AVI/MKV **container opening** is a release requirement. No proposal should promise that every codec found in every AVI/MKV file is decodable. Unsupported codecs must produce a typed error with the stream index, codec identifier, and provider name.

 ### 2.2 Product goals

 - A small player can be written in ordinary Azora code.
 - The same player can be mounted in a game view, a reactive UI view, or a custom render pass.
 - A movie can be muted, have its audio routed to a selected bus, or use an alternate audio track.
 - The engine remains responsive while a large file is opened, sought, or decoded.
 - A provider can be replaced without changing application code.
 - A movie can be used as a texture source, a background, an in-world screen, or a UI element.
 - A future network provider can reuse the session and presentation layers.

 ### 2.3 Explicit non-goals for the first release

 The first release does not need to encode or export movies, edit media, record a camera, implement DRM, or provide a full non-linear editing timeline. Those features should not distort the playback API.

 ## 3. Package and module layout

 The following layout fits the current engine package structure while keeping
 the low-level media packages independent from the player UI:

 ```text
 packages/
   azora-media-core/       # shared time, stream, source, error, and provider contracts
   azora-video/            # engine.video public session and presentation API
   azora-audio/            # engine.audio device, mixer, PCM stream, and audio clock
   azora-profiler/         # engine.profiler counters, spans, traces, and exporters
   azora-media-ffmpeg/     # bundled AVI/MKV demuxer and codec provider
   azora-media-native/     # optional platform provider, e.g. VideoToolbox
   azora-video-player/     # engine.videoplayer; UI player and subtitle widgets
 ```

 The engine ships the FFmpeg provider with the media distribution. It may still
 be enabled or disabled at build time for targets that cannot use native FFmpeg,
 but a normal desktop engine installation must not require a separate FFmpeg
 installation. `azora-engine` may re-export `engine.video`, `engine.audio`, and
 `engine.videoplayer` for the normal application facade.

 Suggested modules:

 ```text
 engine.media       # source, stream, timestamps, errors, provider registry
 engine.video       # video sessions, frames, surfaces, subtitle cues, presentation
 engine.audio       # audio devices, mixer, streams, clocks, output
 engine.videoplayer  # player UI, controls, subtitle widgets, media composition
 engine.media.ffmpeg
 engine.media.native
 ```

 `engine.video` and `engine.audio` depend on `engine.media`. `engine.videoplayer`
 depends on `engine.video`, `engine.audio`, and `engine.ui`; the lower-level
 packages never import it. The bundled FFmpeg provider depends on the shared
 media contracts and ships its native FFmpeg libraries. The native provider
 depends on the platform backend. Neither provider leaks implementation handles
 into the public API.

 ## 4. Media model

 ### 4.1 Source and probing

 A source is not just a path string. It carries identity, access policy, and optional hints:

 ```azora
 import engine.io

 variant enum MediaSource {
     Path(std::String)
     Bytes(Blob)
     Uri(std::String)
 }

 pack MediaOpenOptions {
     provider: std::String?
     probeBytes: std::Int
     timeoutSecs: std::Float
     videoStream: std::Int?
     audioStream: std::Int?
     subtitleStream: std::Int?
     hardwareDecode: std::Bool
 }
 ```

 For the first release, `path` is required and `bytes` is optional. `uri` may return `UnsupportedSource` until a network provider exists. Paths must be passed through the engine's normal I/O sandbox and canonicalization rules.

 The provider must probe by content as well as extension. `.mkv` is a Matroska container, and `.avi` is an RIFF/AVI container; either may contain many different codecs. `MediaSource.Path("movie.mkv")` therefore means “open this file,” not “assume a codec.”

 ### 4.2 Time and stream identity

 All media timestamps use an integer time base and avoid floating-point accumulation:

 ```azora
 pack StreamId {
     fin value: std::Int
 }

 pack TrackId {
     fin value: std::Int
 }

 pack MediaTime {
     ticks: std::Long
     timeBaseNum: std::Int
     timeBaseDen: std::Int
 }

 func mediaTimeSecs(time: MediaTime): std::Float
 func mediaTimeFromSecs(secs: std::Float, timeBaseNum: std::Int, timeBaseDen: std::Int): MediaTime
 ```

 Internally, providers retain demuxer PTS/DTS values until they cross the public boundary. The session normalizes timestamps to a presentation timeline while retaining the original time base for diagnostics.

 A `StreamId` is stable for the lifetime of a session. It is never inferred from a stream name. Track names are labels only; stream selection always uses the symbol/handle returned by metadata.

 ### 4.3 Metadata

 ```azora
 enum MediaStreamKind {
     Video
     Audio
     Subtitle
     Attachment
     Data
 }

 pack VideoTrackInfo {
     stream: StreamId
     codec: std::String
     codecProfile: std::String?
     width: std::Int
     height: std::Int
     pixelAspectNum: std::Int
     pixelAspectDen: std::Int
     frameRateNum: std::Int
     frameRateDen: std::Int
     variableFrameRate: std::Bool
     rotationDegrees: std::Int
     duration: MediaTime?
     hardwareDecodeAvailable: std::Bool
 }

 pack AudioTrackInfo {
     stream: StreamId
     codec: std::String
     sampleRate: std::Int
     channels: std::Int
     channelLayout: std::String
     duration: MediaTime?
     language: std::String?
 }

 pack SubtitleTrackInfo {
     stream: StreamId
     codec: std::String
     language: std::String?
     forced: std::Bool
     defaultTrack: std::Bool
 }

 pack MediaInfo {
     source: MediaSource
     format: std::String
     duration: MediaTime?
     startTime: MediaTime?
     seekable: std::Bool
     byteSize: std::Long?
     videos: std::Array<VideoTrackInfo>
     audios: std::Array<AudioTrackInfo>
     subtitles: std::Array<SubtitleTrackInfo>
     chapters: std::Array<MediaChapter>
     metadata: std::Map<std::String, std::String>
 }
 ```

 Metadata is available before playback whenever the provider can probe it. A file with no video track is valid media but cannot be opened as a `VideoPlayer`; a file with no audio track is a valid silent video.

 ## 5. Provider architecture

 ### 5.1 Provider contract

 ```azora
 spec MediaProvider {
     func name[self: Self&](): std::String
     func canOpen[self: Self&](source: MediaSource): std::Bool
     func open[self: Self&](source: MediaSource, options: MediaOpenOptions): MediaDecoder ?! MediaError
 }

 spec MediaDecoder {
     func info[self: Self&](): MediaInfo
     func nextPacket[self: Self&](): MediaPacket?
     func seek[self: Self&](target: MediaTime, mode: SeekMode): MediaTime
     func flush[self: Self!]()
     func close[self: Self!]()
 }
 ```

 The provider registry chooses a provider by explicit option first, then capability and probe score. It must not choose by filename extension alone.

 ### 5.2 FFmpeg provider

 `engine.media.ffmpeg` is the bundled baseline provider for local AVI/MKV playback. It uses the FFmpeg libraries behind an Azora adapter:

 - `libavformat` for probing, demuxing, stream metadata, chapters, and seeking;
 - `libavcodec` for packet decode and frame reordering;
 - `libavutil` for timestamps, pixel formats, channel layouts, and side data;
 - `libswscale` for CPU pixel conversion when a GPU-native path is unavailable;
 - `libswresample` for audio format conversion when the audio backend requires it.

 The FFmpeg command-line documentation describes hardware acceleration as device- and backend-dependent, so hardware decode is an optional capability negotiated at runtime rather than a compile-time promise. See the [FFmpeg hardware acceleration documentation](https://www.ffmpeg.org/ffmpeg.html).

 The provider must expose a capability report:

 ```azora
 pack MediaProviderCapabilities {
     provider: std::String
     containers: std::Array<std::String>
     videoCodecs: std::Array<std::String>
     audioCodecs: std::Array<std::String>
     subtitleCodecs: std::Array<std::String>
     hardwareBackends: std::Array<std::String>
     supportsExactSeek: std::Bool
     supportsBytesSource: std::Bool
     supportsUriSource: std::Bool
 }
 ```

 Initial acceptance profiles should include common files containing H.264/AVC, MPEG-4 Part 2, MPEG-2, or MJPEG video and PCM, MP3, AAC, Vorbis, or Opus audio. The provider may support more codecs, but every unsupported stream must fail clearly and leave the rest of the engine usable.

 ### 5.3 Native provider and performance policy

 On macOS the native video provider uses VideoToolbox when the actual codec,
 profile, dimensions, pixel format, and current hardware support pass its
 capability probe. VideoToolbox provides direct hardware encode/decode access,
 reports whether a codec is hardware-decodable, and can expose shared pixel
 buffer pools. The provider passes those buffers to `engine.gpu` without a CPU
 copy when possible.

 The selected path is a runtime performance decision:

 1. FFmpeg probes the container and streams.
 2. VideoToolbox capability probing checks the selected video stream.
 3. If VideoToolbox plus a GPU surface is supported, use the hardware path.
 4. Otherwise use bundled FFmpeg software decode and GPU upload.
 5. If profiling shows that software decode is faster for a particular stream,
    `Automatic` may choose software.
 6. `Hardware` requires the hardware path and reports an error when it cannot
    be created. `Software` disables VideoToolbox.

 A live session does not silently switch decoder families. It may reopen at a
 controlled boundary after a measured failure or an explicit policy change.

 This follows Apple's VideoToolbox model: hardware decode support is checked
 per codec, hardware use can be enabled or required, and the framework exposes
 pixel-buffer pools for decoder output. See the [VideoToolbox documentation](https://developer.apple.com/documentation/videotoolbox), [hardware decode support](https://developer.apple.com/documentation/videotoolbox/2887343-vtishardwaredecodesupported?changes=_2_1__8&language=objc), and [decompression properties](https://developer.apple.com/documentation/videotoolbox/decompression-properties).

 ### 5.4 Provider selection and fallback

 ```azora
 variant enum ProviderPreference {
     Automatic
     Named(std::String)
     Software
     Hardware
 }

 func mediaRegisterProvider(provider: MediaProvider): std::Unit ?! MediaError
 func mediaCapabilities(): std::Array<MediaProviderCapabilities>
 func videoOpen(source: MediaSource, options: VideoOpenOptions): VideoPlayer ?! MediaError
 ```

 Fallback is allowed only before playback has committed to a decoder. After a session starts, changing providers silently would invalidate timestamps and decoded state; an application may explicitly reopen with another provider.

 ## 6. Video session lifecycle

 ### 6.1 State machine

 ```text
 Closed -> Opening -> Ready -> Playing -> Paused -> Playing
                         |        |          |
                         |        v          |
                         +----> Buffering <--+
                         |
                         +----> Ended -> Playing (replay)
 Any live state -> Seeking -> Ready/Playing
 Any live state -> Error -> Closed
 ```

 `Opening`, `Seeking`, and `Buffering` are observable states. The render loop must never wait for a decoder to leave one of these states.

 ```azora
 enum VideoState {
     Closed
     Opening
     Ready
     Playing
     Paused
     Buffering
     Seeking
     Ended
     Error
 }

 variant error MediaError {
     InvalidSource
     AccessDenied
     ProviderUnavailable
     UnsupportedContainer
     UnsupportedCodec(stream: StreamId, codec: std::String)
     MalformedMedia
     DecoderFailed
     AudioDeviceFailed
     GpuSurfaceFailed
     SeekFailed
     Cancelled
     Internal
 }
 ```

 ### 6.2 Player handle

 The player is a resource-owning handle, not a component that embeds decoder pointers inside an entity. This keeps native state out of ECS snapshots and prevents accidental copying.

 ```azora
 pack VideoOpenOptions {
     providerPreference: ProviderPreference
     hardwareDecode: std::Bool
     audioEnabled: std::Bool
     loop: std::Bool
     sync: SyncPolicy
     buffering: BufferingPolicy
 }

 pack VideoPlayer {
     id: std::Long
 }

 func videoOpen(source: MediaSource, options: VideoOpenOptions): VideoPlayer ?! MediaError
 func videoInfo(player: VideoPlayer): MediaInfo ?! MediaError
 func videoState(player: VideoPlayer): VideoState
 func videoPlay(player: VideoPlayer): std::Unit ?! MediaError
 func videoPause(player: VideoPlayer): std::Unit ?! MediaError
 func videoStop(player: VideoPlayer): std::Unit ?! MediaError
 func videoReplay(player: VideoPlayer): std::Unit ?! MediaError
 func videoClose(player: VideoPlayer)
 ```

 `videoClose` is idempotent. A reactive UI cleanup hook or a deferred scope should close the player when the screen leaves the tree.

 ### 6.3 Reactive UI usage

 The exact implementation can evolve with the UI package, but the intended usage follows the current `react func`, `remember`, `retain`, and `preserve` model:

 ```azora
 react func MovieScreen(player: VideoPlayer) {
     effect defer {
         videoClose(player)
     }

     @compose world {
         if player.isReady() {
             videoView(player)
         } else {
             loadingView(player.state())
         }
         playerControls(player)
     }
 }
 ```

 The view observes player state and frame revisions through `Signal`/`ReactiveResource`; it does not poll the decoder from layout code. A frame revision invalidates the video surface, while a state revision updates controls and error UI.

 ### 6.4 ECS usage

 A world-facing wrapper may attach a stable player reference to an entity:

 ```azora
 @Component
 pack VideoPlayback {
     player: VideoPlayer
     autoplay: std::Bool
     visible: std::Bool
 }

 @System(.Update)
 func updateVideoPlayback(
     query: @query [VideoPlayback!, Transform!] @with Visible @without Disabled
 ) {
     for entity in query {
         entity.0.player.update()
     }
 }
 ```

 Queries that operate on media entities must use the current query form, for example:

 ```azora
 @query [VideoPlayback!, Transform!] @with Visible @without Disabled
 ```

 Player ownership remains in `VideoPlayers` or a resource. Entity destruction sends a release command; it does not directly free a decoder from an arbitrary system.

 ## 7. Decode and buffering pipeline

 ### 7.1 Pipeline

 ```text
 source
   -> probe/open
   -> demux packet queue
   -> audio decoder -> PCM conversion -> audio stream queue -> mixer/device
   -> video decoder -> frame queue -> color conversion/upload -> video surface
   -> presentation clock -> render pass
   -> subtitle decoder -> cue queue -> UI/world overlay
 ```

 Demuxing and decoding are asynchronous. The session owns bounded queues for packets, decoded audio, decoded video, and subtitles. Queue capacity is expressed in seconds and memory limits, not only item count, because one 4K frame is not equivalent to one small audio packet.

 ```azora
 pack BufferingPolicy {
     minBufferedSecs: std::Float
     targetBufferedSecs: std::Float
     maxBufferedSecs: std::Float
     maxVideoBytes: std::Long
     maxAudioBytes: std::Long
 }
 ```

 The default policy should target enough buffered media to avoid normal disk jitter without holding an unbounded movie in memory. When a queue is full, demuxing pauses. When a queue is empty, the session enters `buffering` and emits a reason.

 ### 7.2 Packet and frame ownership

 Provider-owned packet and frame memory is reference-counted or copied into an engine-owned pool before crossing a thread boundary. No public API may expose a pointer whose lifetime depends on the next decoder call.

 A frame is immutable after it enters the presentation queue. GPU upload may retain the frame until the command buffer completes; the session must not recycle that storage early.

 ### 7.3 Backpressure

 The session must apply different policies by stream:

 - audio is never dropped during normal playback; underrun produces `buffering`;
 - video frames that are already late may be dropped up to the next usable frame;
 - subtitle cues are retained until their end time or seek flush;
 - packets are dropped only during an explicit recovery policy and are reported in diagnostics.

 ## 8. Timing and audio/video synchronization

 ### 8.1 Presentation rules

 Decoding order is not presentation order. The video decoder must reorder frames using PTS and duration. The renderer presents a frame only when its presentation timestamp is due according to the selected clock.

 ```azora
 enum SyncPolicy {
     AudioMaster
     VideoMaster
     EngineMaster
 }

 enum ClockMode {
     Media
     Engine
     External
 }

 pack VideoClock {
     mode: ClockMode
     position: MediaTime
     rate: std::Float
     paused: std::Bool
 }
 ```

 Default policy:

 - audio track enabled: audio is master;
 - muted or audio-less video: video is master;
 - engine-integrated playback with an explicit simulation clock: engine is master.

 The engine clock is never allowed to advance a movie faster than the audio device can consume audio unless the application explicitly chooses `engineMaster`.

 ### 8.2 Drift correction

 The session continuously measures `videoPts - masterClock`. It should:

 - present early frames at their due time;
 - drop a late frame when the next frame is closer to the clock;
 - repeat the last frame for a short video gap;
 - apply small audio resampling corrections for long-running drift;
 - never visibly seek or jump for a correction below the configured threshold.

 Large drift, a device interruption, or a queue flush emits a synchronization event. All synchronization decisions are recorded in diagnostics so playback bugs can be reproduced.

 ### 8.3 Pause, rate, and seek

 Pause freezes the presentation clock and stops audio consumption without destroying decoder state. Rate changes affect both streams and preserve the current media position. The first release may restrict rates to a safe range such as `0.25` through `4.0`.

 ```azora
 enum SeekMode {
     Fast
     Keyframe
     Exact
 }

 pack SeekRequest {
     target: MediaTime
     mode: SeekMode
     resume: std::Bool
 }

 func videoSeek(player: VideoPlayer, request: SeekRequest): MediaTime ?! MediaError
 func videoPosition(player: VideoPlayer): MediaTime
 func videoSetRate(player: VideoPlayer, rate: std::Float): std::Unit ?! MediaError
 ```

 A seek must atomically:

 1. stop presenting new decoded frames;
 2. pause audio output for the session;
 3. flush packet and decoder queues;
 4. seek to a provider keyframe at or before the requested target;
 5. decode forward until the requested presentation point;
 6. discard frames before the target for `exact` mode;
 7. reset subtitle cues and the audio clock;
 8. resume only when `resume` is true.

 The result reports the actual first presentation timestamp, not merely the requested timestamp.

 ## 9. Video frame and GPU surface design

 ### 9.1 Frame formats

 ```azora
 enum VideoPixelFormat {
     Rgba8
     Bgra8
     Rgb10a2
     Nv12
     I420
     P010
 }

 enum ColorRange {
     Limited
     Full
 }

 pack VideoColorInfo {
     primaries: std::String
     transfer: std::String
     matrix: std::String
     range: ColorRange
 }

 pack VideoFrame {
     id: std::Long
     pts: MediaTime
     duration: MediaTime?
     width: std::Int
     height: std::Int
     format: VideoPixelFormat
     color: VideoColorInfo
     rotationDegrees: std::Int
     surface: VideoFrameSurface
 }
 ```

 The public frame describes a frame and owns its lifetime. It must not force every provider to convert to RGBA. NV12/P010 and planar YUV are preferred when the GPU backend can sample them directly; conversion must apply the frame's matrix and range metadata.

 ### 9.2 Surface types

 ```azora
 enum VideoSurfaceKind {
     GpuTexture
     CpuImage
 }

 pack VideoFrameSurface {
     kind: VideoSurfaceKind
     id: std::Long
 }

 pack VideoSurface {
     id: std::Long
     width: std::Int
     height: std::Int
     format: VideoPixelFormat
     revision: std::Long
 }

 func videoSurface(player: VideoPlayer): VideoSurface ?! MediaError
 func videoPollFrame(player: VideoPlayer): VideoFrame?
 func videoPresentFrame(player: VideoPlayer, frame: VideoFrame): std::Unit ?! MediaError
 ```

 `videoPollFrame` is called by the presentation system, not arbitrary UI layout code. The surface revision changes only when a new frame is ready. The renderer may cache the surface between frames.

 ### 9.3 Metal path

 On the current macOS backend:

 - the native provider may decode into VideoToolbox-backed Core Video pixel buffers backed by IOSurface;
 - `engine.gpu` imports those surfaces without an unnecessary CPU round trip;
 - the bundled FFmpeg provider uploads converted RGBA/NV12 data through a staging buffer;
 - the render pass samples the frame using a video material/shader that handles YUV conversion, range, transfer, and rotation;
 - the presentation surface is synchronized with the command buffer that consumes it.

 If direct hardware surfaces are unavailable, the provider falls back to software decode and a bounded upload pool. The fallback must remain correct even if it is less power-efficient.

 ### 9.4 Rendering API

 ```azora
 enum VideoFit {
     Contain
     Cover
     Stretch
     None
 }

 pack VideoDrawOptions {
     fit: VideoFit
     tint: Color
     opacity: std::Float
     crop: Rect?
     rotation: std::Float?
     flipX: std::Bool
     flipY: std::Bool
 }

 func drawVideo(surface: VideoSurface, rect: Rect, options: VideoDrawOptions)
 ```

 The default is aspect-ratio-preserving `contain`. `cover` crops after pixel aspect ratio and rotation are applied. The API is usable from `engine.render` and can also be wrapped by a UI `VideoView`.

 ### 9.5 In-world screens

 A video surface can be referenced by a render material without coupling an entity to the decoder:

 ```azora
 @Component
 pack VideoMaterial {
     surface: VideoSurface
     fit: VideoFit
 }

 @query [VideoMaterial!, Transform!] @with Render @without Disabled
 ```

 `engine.gpu` owns the actual texture/resource lifetime. `engine.video` owns
 only the semantic frame/surface handle and metadata. This gives rendering and
 media code one texture ownership model while keeping applications from
 handling raw Metal pointers. `engine.videoplayer` consumes the handle through
 `engine.ui` or `engine.render`; `engine.video` never imports `engine.ui`.

 `VideoMaterial` is a presentation reference. It does not own the player and is safe to remove when an entity leaves the world.

 ## 10. Subtitles and text tracks

 The media session exposes subtitles as timed cues. Rendering is an application concern so a game can place subtitles in UI, in world space, or in a custom overlay.

 ```azora
 pack SubtitleCue {
     stream: StreamId
     start: MediaTime
     end: MediaTime
     text: std::String
     markup: std::String?
     style: SubtitleStyle
 }

 pack SubtitleStyle {
     language: std::String?
     align: TextAlign
     fontSize: std::Float
     color: Color
     outline: Color
     background: Color?
 }

 func videoSubtitleCues(player: VideoPlayer): std::Array<SubtitleCue>
 func videoSelectSubtitle(player: VideoPlayer, stream: StreamId?): std::Unit ?! MediaError
 ```

 The first provider should support common text subtitle streams exposed by the container, especially SRT/SubRip and ASS/SSA where the underlying decoder can provide them. Styling must be sanitized; subtitle markup is data, not executable code. Bitmap subtitles may be exposed as a future surface type.

 Sidecar subtitles are a later extension, but the source model should permit them without changing `VideoPlayer`.

 `engine.video` stops at timed `SubtitleCue` values. `engine.videoplayer`
 provides `VideoSubtitleView` and maps cue style to `engine.ui` text styles.
 This keeps subtitles usable in a game HUD, a desktop player, or an in-world
 overlay without making the lower-level decoder depend on UI.

 ## 11. Audio integration

 Video playback never writes directly to an audio device. It submits a timestamped `AudioStream` to `engine.audio` and receives a shared media clock from the audio output. The audio proposal defines the mixer and device behavior in detail.

 ```azora
 pack VideoAudioOptions {
     enabled: std::Bool
     stream: StreamId?
     bus: AudioBusId
     volume: std::Float
     muted: std::Bool
 }

 func videoSetAudioOptions(player: VideoPlayer, options: VideoAudioOptions)
 ```

 A movie's audio is one mixer source. It can be muted without stopping video, routed to a `media` bus, ducked when voice dialogue plays, or mixed with game sound. The movie session must stop feeding the stream on close and relinquish its clock registration.

 ## 12. Threading and ownership

 ### 12.1 Thread roles

 - **Application thread:** creates and controls players; receives state events.
 - **Demux/decode workers:** read packets, decode streams, and fill bounded queues.
 - **Audio callback thread:** consumes prepared PCM only; never allocates, locks, performs file I/O, or calls into UI/ECS.
 - **Render thread:** acquires the due video surface and records GPU commands.
 - **GPU completion callbacks:** return staging/surface leases after the command buffer is safe.

 These roles are submitted to `engine.jobs`; the media contract is semantic and
 does not expose thread creation or decoder-context internals.

 ### 12.2 Parallel real-time video decoding

 Video decoding should use the engine's `engine.jobs` worker runtime and may use all available CPU cores when the codec and workload can use them. It must not create one uncontrolled thread per core or one private thread pool per player. A demuxer is usually ordered, individual decoder contexts have thread-safety rules, and the render and audio paths need predictable deadlines.

 The scheduler maximizes useful parallelism subject to those deadlines:

 ```text
 one ordered demux task
       |
       +--> packet queues per selected stream
                 |
                 +--> decoder tasks on engine.jobs workers
                             |
                             +--> timestamp reorder queue
                                         |
                                         +--> conversion/upload tasks
 ```

 #### Decoder parallelism modes

 Each provider reports what kind of parallelism its decoder supports:

 ```azora
 enum DecodeParallelism {
     Serial
     Frame
     Slice
     Tile
     Segment
 }

 pack DecoderCapabilities {
     parallelism: DecodeParallelism
     maxWorkers: std::Int
     hardwareAccelerated: std::Bool
     supportsLowLatency: std::Bool
     requiresOrderedPackets: std::Bool
 }
 ```

 The provider must never call one non-thread-safe decoder context concurrently just to increase CPU usage. It may use one of these safe strategies:

 - configure the codec's internal frame/slice threading when the codec supports it;
 - create a bounded set of independent decoder contexts for independently decodable segments;
 - run color conversion, upload preparation, subtitle parsing, and other independent stages in parallel;
 - keep serial codecs on one worker and spend spare capacity on other streams or players;
 - use a hardware decoder when it provides better deadline behavior and lower CPU cost.

 The session preserves presentation order after parallel decode. A frame that finishes early waits in a bounded reorder queue; a frame that cannot meet its deadline causes a measured drop or buffering transition rather than an unbounded queue.

 #### Worker budget

 The global media scheduler owns a worker budget instead of allowing every player to create its own threads:

 ```azora
 import engine.jobs

 pack VideoDecodePolicy {
     mode: DecodeParallelism
     workers: std::Int?
     useAllAvailableCores: std::Bool
     reserveCoresForRender: std::Int
     reserveCoresForAudio: std::Int
     priority: JobPriority
     maxAheadSecs: std::Float
 }
 ```

 `useAllAvailableCores` means “make all non-reserved worker capacity available to eligible decode jobs,” not “starve the application.” The default policy is:

 ```text
 usable workers = max(1, logical CPU count - render reserve - audio reserve)
 per-player workers = min(codec max, provider max, fair-share budget)
 ```

 The scheduler must reserve enough capacity for the render loop, audio callback support, input, and engine systems. On a small machine it may use one worker. On a large machine, several movie sessions can share the pool without multiplying thread count by the number of players.

 `workers` is a cap, not a promise. Thermal pressure, background load, hardware decode, and queue fullness may reduce it. The profiler reports requested, active, and useful workers separately.

 #### Scheduling policy

 Media jobs are deadline-aware:

 - decode work needed for the next presentation deadline has highest media priority;
 - work that fills a healthy buffer runs at normal priority;
 - thumbnail, exact-seek, and metadata work yields to live playback;
 - a player cannot monopolize the pool when several players are active;
 - a paused player stops normal decode work, except for an explicit prefetch request;
 - a closing or seeking player cancels queued work using a session generation token;
 - canceled jobs release packet/frame leases even if they never start.

 The decoder must buffer enough work to hide disk jitter and scheduling jitter, but it must not decode an entire movie ahead of the presentation clock. `maxAheadSecs` and memory limits are hard bounds.

 #### Real-time deadline behavior

 The scheduler measures the decode cost of recent frames against their presentation deadlines. If a stream cannot keep up:

 1. drop late video frames according to the configured policy;
 2. reduce conversion/upload work where a lower-cost surface is available;
 3. switch from hardware to software or software to hardware only at a controlled reopen boundary;
 4. enter `buffering` if the next usable frame cannot be produced safely;
 5. report the cause and missed-deadline count through diagnostics.

 Audio remains the master when audio is enabled. Video decode may use every usable worker while the audio callback continues to receive predecoded buffers on schedule.

 #### API

 ```azora
 func videoSetDecodePolicy(player: VideoPlayer, policy: VideoDecodePolicy)
 func videoDecodePolicy(player: VideoPlayer): VideoDecodePolicy
 func videoDecoderCapabilities(player: VideoPlayer): DecoderCapabilities
 ```

 The policy is applied at a session boundary or at the next safe decoder reconfiguration point. Changing the worker cap must not invalidate decoded frame ownership or reorder timestamps.

 ### 12.3 Commands and events

 Controls are serialized as session commands. State changes are published as events/signals:

 ```azora
 @Event
 variant enum VideoEvent {
     opened(VideoPlayer)
     ready(VideoPlayer)
     started(VideoPlayer)
     paused(VideoPlayer)
     buffering(VideoPlayer, BufferingReason)
     seeked(VideoPlayer, MediaTime)
     ended(VideoPlayer)
     droppedFrames(VideoPlayer, std::Int)
     error(VideoPlayer, MediaError)
     closed(VideoPlayer)
 }
 ```

 Event payloads contain stable IDs and values, never raw provider pointers. `Events<T>` can provide the bounded double-buffered delivery already used by the engine ECS package.

 ### 12.4 Shutdown

 Closing a player is a two-phase operation internally: stop accepting commands, then drain/release provider, audio, frame, subtitle, and GPU resources. The public `videoClose` may return before worker teardown completes, but `videoClosed` must not be reported until all external surface leases are safe to release.

 ## 13. Diagnostics and observability

 Each player exposes counters and the last provider error:

 ```azora
 pack VideoDiagnostics {
     provider: std::String
     decodedFrames: std::Long
     presentedFrames: std::Long
     droppedFrames: std::Long
     audioUnderruns: std::Long
     videoQueueSecs: std::Float
     audioQueueSecs: std::Float
     avDriftSecs: std::Float
     lastPts: MediaTime?
     lastError: MediaError?
 }

 func videoDiagnostics(player: VideoPlayer): VideoDiagnostics
 ```

 Diagnostics must identify whether a failure occurred while probing, demuxing, decoding, converting, uploading, or presenting. This is essential for distinguishing “MKV cannot be opened” from “MKV opened but contains an unsupported codec.”

 ## 14. Media profiler

 A profiler is part of the media feature, not an afterthought. “Uses all CPU cores” is only useful if the engine can show whether cores were doing decode work, waiting on I/O, blocked behind a serial decoder, or idle because the buffer was already full.

 The profiler is proposed as a reusable `engine.profiler` package. Video and audio emit media-specific events into it; the profiler itself must not depend on `engine.video` or `engine.audio`.

 ### 14.1 Runtime modes

 `PROFILER.MD` is the canonical definition of `ProfilerMode`,
 `ProfilerConfig`, sessions, snapshots, file capture, overflow behavior, and
 exporters. Media does not redeclare those types. `Counters` is suitable for
 shipping diagnostics, `Timeline` records bounded spans and flows, and
 `Detailed` adds provider calls, allocations, samples, and GPU counters when
 supported.

 ### 14.2 Media spans

 Every media stage uses a stable player/session ID and stream ID:

 ```azora
 enum MediaProfileStage {
     Probe
     Read
     Demux
     PacketQueue
     Decode
     Reorder
     ColorConvert
     GpuUpload
     Present
     AudioDecode
     AudioMix
     AudioDevice
     Subtitle
     Seek
     Close
 }

 pack MediaProfileContext {
     fin player: VideoPlayer
     fin stream: StreamId?
     fin stage: MediaProfileStage
     fin frameId: std::Long?
     fin pts: MediaTime?
     fin bytes: std::Long
     fin deadlineNs: std::Long?
 }
 ```

 `MediaProfileContext` is metadata attached to the generic profiler context;
 timestamps, tracks, workers, CPU samples, flows, and deadline-miss events use
 the common contracts from `PROFILER.MD`. Worker threads write to their own
 preallocated profiler buffer. No media worker or audio callback locks a global
 profiler mutex.

 ### 14.3 Required counters

 The video profiler must expose at least:

 - active and requested decode workers;
 - logical/physical CPU count and reserved worker capacity;
 - useful decode time per worker and per core;
 - worker idle time, queue wait time, and I/O wait time;
 - packets read, packets queued, frames decoded, frames reordered, frames presented, and frames dropped;
 - average, p95, and maximum decode time;
 - average work-ahead and reorder queue depth;
 - video queue seconds and bytes;
 - audio queue seconds and underruns;
 - upload bytes, upload time, GPU surface count, and GPU wait time;
 - audio/video drift and synchronization corrections;
 - seeks, seek latency, and frames discarded during seek;
 - provider, container, codec, pixel format, hardware path, and fallback reason;
 - allocations and peak memory owned by the session.

 The profiler must distinguish **CPU utilization** from **decoder parallel
 efficiency**. Eight active workers that spend most of their time waiting on a
 serial codec are not eight useful decode workers.

 ### 14.4 Trace and live overlay

 The first profiler product is an `.aztrace` file plus text/JSON exports. The
 future `azora-profiler-ui` overlay should show:

 ```text
 movie.mkv | Playing | H.264 + Opus | 1920x1080
 decode: 6/8 workers | 73% useful CPU | 0.8 ms p95 frame
 queues: video 1.7 s / audio 2.1 s | A/V drift +0.4 ms
 presented: 60 fps | dropped: 0 | upload: 2.4 ms
 ```

 The generic exporter maps media tracks, contexts, counters, and flows to Chrome
 Trace Event JSON. The future native overlay consumes the same
 `ProfilerSnapshot` as every other subsystem.

 ### 14.5 Profiling API boundary

 Video code uses generic profiler calls rather than importing a UI or platform
 profiler:

 ```azora
 fin span = profilerBegin(profileSite("media.video", "decode"))
 defer profilerEnd(span)
 profilerGaugeSet(videoQueueMetric, videoQueueSecs, sessionContext)
 profilerInstant(profileSite("media.video", "frame-drop"))
 ```

 The current media session context is installed on the worker before this code
 runs, so the generic events retain player, stream, frame, and job ownership.
 The implementation must preserve the boundary: media emits structured facts;
 visualization and export are separate consumers.

 ## 15. Security and resource limits

 Media is untrusted input. The provider boundary must:

 - enforce maximum probe and metadata sizes;
 - enforce packet, frame, subtitle, and attachment memory limits;
 - reject impossible dimensions, sample rates, channel counts, and time bases;
 - sanitize subtitle text and metadata before UI display;
 - disable arbitrary external resource loading from subtitle formats by default;
 - cancel all I/O and decoder work when a player closes;
 - avoid exposing native library pointers to Azora code;
 - report malformed media as a recoverable player error.

 Embedded attachments may be listed as metadata but must not be extracted to disk implicitly. The application explicitly opts in to attachment extraction.

 ## 16. Error and fallback behavior

 A player must fail locally, not bring down the engine. Examples:

 - no provider can probe the file: `unsupportedContainer`;
 - the container opens but no video stream exists: `unsupportedCodec` or `invalidSource` with a “no video stream” detail;
 - one audio track is unsupported but video is playable: video remains playable, audio is disabled, and an audio-track error is emitted;
 - hardware decode fails: retry software decode if enabled;
 - GPU surface creation fails: use CPU image upload if supported;
 - audio device disappears: pause/buffer and recover on device restoration;
 - a damaged packet is encountered: skip it when safe and increment a corruption diagnostic.

 ## 17. Example player

 The following is illustrative Azora syntax and should be reconciled with the final package naming during implementation:

 ```azora
 import engine.videoplayer

 func openMovie(path: std::String): VideoPlayer ?! MediaError {
     return try videoOpen(
         MediaSource.Path(path),
         VideoOpenOptions(
             providerPreference: .Automatic,
             hardwareDecode: true,
             audioEnabled: true,
             loop: false,
             sync: .AudioMaster,
             buffering: .Full
         )
     )
 }

 react func MoviePlayer(player: VideoPlayer) {

     effect defer {
         videoClose(player)
     }

     @compose world {
         videoView(player, fit: .Contain)

         row {
             button("Play") { videoPlay(player) }
             button("Pause") { videoPause(player) }
             button("Stop") { videoStop(player) }
             button("Mute") { videoSetMuted(player, true) }
             slider(videoPosition(player), videoDuration(player)) {
                 videoSeek(player, SeekRequest(it, .Keyframe, true))
             }
         }
     }
 }

 func main(): std::Unit ?! MediaError {
     try mediaRegisterProvider(ffmpegProvider())
     try mediaRegisterProvider(nativeProvider())
     fin player = try openMovie("movies/demo.mkv")
     app.mount(MoviePlayer(player))
     app.run()
 }
 ```

 The same player may be used without UI:

 ```azora
 func playMovie(world: World, path: std::String): std::Unit ?! MediaError {
     fin player = try videoOpen(
         MediaSource.Path(path),
         VideoOpenOptions.default()
     )
     try videoPlay(player)
     world.resources().insert(player)
 }
 ```

 ## 18. Implementation phases

 ### Phase 1: contracts and a silent video

 - create shared media time/source/error/provider types;
 - create `engine.video` session lifecycle;
 - add a fake provider and deterministic test clock;
 - open/probe files asynchronously;
 - decode one selected video stream into CPU frames;
 - render RGBA frames through an `engine.gpu` surface;
 - implement pause, stop, close, and state events.

 ### Phase 2: AVI/MKV FFmpeg provider

 - add FFmpeg native dependency discovery and packaging;
 - implement AVI and Matroska probing/demuxing;
 - implement stream selection and metadata;
 - support initial software video profiles;
 - implement keyframe and exact seek;
 - add malformed-file and truncated-file handling.

 ### Phase 3: audio and synchronization

 - connect decoded audio to `engine.audio` timestamped streams;
 - make audio the default master clock;
 - implement queue backpressure, buffering, drift correction, and rate changes;
 - add mute, volume, bus routing, alternate audio tracks, and device recovery.

 ### Phase 4: GPU-native and presentation features

 - add NV12/P010/I420 GPU sampling;
 - add VideoToolbox/IOSurface interop where available;
 - add aspect fit/fill, rotation, crop, in-world materials, and UI `VideoView`;
 - add subtitle cues and overlay adapters;
 - add frame statistics and playback diagnostics.

 ### Phase 5: provider and source expansion

 - add native platform provider;
 - add bytes and stream sources;
 - add network provider with cache/range requests;
 - add adaptive buffering and optional hardware policy;
 - add media thumbnails and poster-frame extraction.

 ## 19. Acceptance criteria

 ### File opening

 - `videoOpen(MediaSource.Path("sample.avi"), ...)` succeeds for the checked-in AVI fixture when its selected codecs are in the supported profile.
 - `videoOpen(MediaSource.Path("sample.mkv"), ...)` succeeds for the checked-in Matroska fixture under the same condition.
 - probing reports container, duration, dimensions, stream IDs, codecs, language, and seekability.
 - a misleading extension is handled by content probing or returns a useful format error.

 ### Playback

 - first frame and first audible sample arrive without blocking the app frame loop;
 - a 30-minute fixture does not grow memory without bound;
 - audio/video drift stays within the configured tolerance during normal playback;
 - late video frames are dropped according to policy and never cause audio starvation;
 - pause/resume does not reset position;
 - loop returns to the first presentation timestamp without stale frames or stale subtitles.

 ### Seeking

 - fast and keyframe seek complete on AVI and MKV fixtures;
 - exact seek presents a frame at or after the target within documented tolerance;
 - audio, video, and subtitle queues are flushed together;
 - seek during opening, buffering, and playback is race-safe.

 ### Rendering

 - CPU RGBA fallback renders correctly;
 - YUV-to-RGB conversion respects limited/full range and color matrix;
 - non-square pixel aspect ratio and rotation are correct;
 - a frame can be drawn both in a UI surface and on an in-world render material;
 - surfaces are not reused until GPU work is complete.

 ### Failure and lifecycle

 - unsupported codecs produce typed diagnostics;
 - unsupported audio does not prevent silent video playback;
 - closing a player releases all native and GPU resources;
 - device loss, provider failure, and cancellation do not crash the engine;
 - tests run with a fake provider without requiring FFmpeg or a physical audio device.

 ## 20. Resolved architecture decisions

 1. **FFmpeg distribution:** FFmpeg is bundled with the engine's desktop media
    distribution. Applications do not install or discover a separate FFmpeg
    package. The build may omit it for targets that cannot ship native FFmpeg,
    but that target must report the missing provider clearly.
 2. **macOS performance path:** probe with bundled FFmpeg, then use VideoToolbox
    hardware decode plus IOSurface/Metal when the actual stream and device
    support it. Use bundled FFmpeg software decode plus GPU upload otherwise.
    `Automatic` chooses the measured best supported path; `Hardware` and
    `Software` are explicit overrides. See the [VideoToolbox hardware decode documentation](https://developer.apple.com/documentation/videotoolbox/2887343-vtishardwaredecodesupported?changes=_2_1__8&language=objc).
 3. **Worker ownership:** `engine.jobs` owns the single global worker pool.
    `engine.video` and `engine.audio` submit deadline-aware jobs to it but do
    not create private pools. Media owns only its bounded queues and fair-share
    policy.
 4. **GPU ownership:** `engine.gpu` owns the actual texture/resource and
    release fence. `engine.video` exposes the semantic `VideoSurface` handle;
    `engine.render` consumes it. This avoids duplicate texture abstractions and
    keeps raw Metal handles out of application code.
 5. **Subtitle presentation:** `engine.video` emits timed cues only.
    `engine.videoplayer` imports `engine.video`, `engine.audio`, and `engine.ui`
    and provides the player screen, controls, and subtitle widgets. `engine.video`
    never imports `engine.ui`.
 6. **Shared contracts:** `azora-media-core` owns source, stream, timestamp,
    provider, and media-error contracts. `engine.video` and `engine.audio`
    re-export them, so applications can import one package ergonomically while
    providers depend on the neutral core.
