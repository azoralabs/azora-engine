# Azora Audio — Audio Engine and Media Playback

 Status: Proposal
 Scope: real-time playback, mixing, device output, and movie audio
 Initial media requirement: audio tracks embedded in local `.avi` and `.mkv` files
 Primary integration: `engine.audio`, `engine.media`, `engine.video`, `engine.jobs`, `engine.profiler`

 ## 1. Summary

 `azora-audio` already contains a small native `AVAudioPlayer`-based sound
 helper. That is useful for short scene sounds, but it is not enough for a
 media player: movie playback needs timestamped streaming, a real-time-safe
 mixer, resampling, device recovery, audio/video clock ownership, seeking, and
 bounded buffering.

 This proposal evolves `engine.audio` into the engine's audio runtime while
 preserving the existing `Sound`, `loadSound`, `play`, `stop`, and volume APIs
 as compatibility helpers.

 The audio runtime has six layers:

 1. **Source and decoder providers** turn files or media packets into PCM.
 2. **Timestamped audio streams** buffer decoded samples without blocking the
    device callback.
 3. **The mixer graph** combines voices, buses, movie audio, and effects.
 4. **The device backend** converts the final mix to the platform output format.
 5. **The media clock** makes audio the default master for video playback.
 6. **Diagnostics and profiling** show underruns, queue pressure, latency,
    drift, device time, and per-stage cost.

 The public API must not expose `AVAudioPlayer`, Core Audio, AudioUnit,
 FFmpeg, or other native objects. Provider implementations may use them behind
 `spec` contracts.

 ## 1.1 Current implementation audit

 The repository now contains the first implementation slice described by this
 proposal. `engine.media` provides rational `MediaTime`, stable stream/track IDs,
 source and stream metadata, provider capabilities, a `MediaProvider` spec, and
 a deterministic fake provider with tests. `engine.audio.runtime` provides:

 - `AudioFormat` and validated sample formats;
 - a fixed-capacity, generation-checked `AudioBufferPool` with explicit writing,
   ready, reading, and release states;
 - pool pressure statistics and stale-lease rejection;
 - stable built-in bus IDs, a bounded hierarchical `AudioMixer`, gain/mute,
   parent-cycle rejection, and effective inherited gain;
 - an `AudioEffect` spec plus a tested in-place `GainEffect`;
 - tests for pool exhaustion, mixer identity/routing, and effect processing.

 The older `engine.audio` compatibility layer still uses `AVAudioPlayer`, builds
 procedural WAV data in memory, loads whole encoded files synchronously, and
 exposes `Sound` play/loop/volume/release operations. It is useful but is not the
 proposed real-time device/mixer implementation.

 Still missing are the AudioUnit output callback, decoded clip/stream voices,
 actual bus summing, arbitrary effect-chain ownership, spatial audio, device
 enumeration/switching, FFmpeg media audio, sample-accurate A/V attachment,
 job scheduling, profiler adapters, and platform-independent providers. The
 implementation phases below remain valid after treating the completed pool,
 bus graph, effect contract, and shared media types as foundations rather than
 future work.

 ## 2. Goals

 ### 2.1 Required first release

 The first complete player release must:

 - open and inspect audio streams embedded in `.avi` and `.mkv` files;
 - decode the selected track asynchronously;
 - play PCM, MP3, AAC, Vorbis, and Opus tracks when the selected provider
   supports them;
 - expose sample rate, channel count, layout, codec, language, duration, and
   stream identity;
 - feed movie audio into the same mixer as game audio;
 - make audio the master clock when movie audio is enabled;
 - support play, pause, stop, loop, mute, volume, rate, and seek;
 - keep the audio callback free of allocation, file I/O, blocking locks, and
   decoder calls;
 - handle underrun, overrun, device removal, device change, and interruption;
 - resample and remix decoded audio into the active device format;
 - support bus routing, fades, pan, gain, mute, and ducking;
 - provide real-time-safe reverb sends/returns and environmental reverb zones;
 - provide procedural generators through the normal voice and mixer path;
 - report accurate queue duration and audio/video drift;
 - release every decoder, queue, voice, effect, and device resource
   deterministically.

 Opening the AVI/MKV container remains the responsibility of the shared media
 provider. Audio must not infer a codec from a file extension. A container may
 contain several audio tracks or no audio track at all.

 ### 2.2 Product goals

 - A short sound and a two-hour movie use the same mixer safely.
 - A player can mute only its movie audio while game sounds continue.
 - A movie can route to a `Media` bus and be ducked by voice dialogue.
 - Audio output remains smooth when video decoding is using most worker cores.
 - An application can select an output device and inspect its capabilities.
 - A game can use 2D or 3D voices without depending on the movie subsystem.
 - A platform provider can be replaced without changing Azora application code.

 ### 2.3 First-release non-goals

 The first release does not need audio recording, microphone capture, encoding,
 DRM, a digital audio workstation timeline, or a full HRTF laboratory. The
 graph and provider boundaries must leave room for those features later.

 ## 3. Package and module layout

 ```text
 packages/
   azora-audio/            # engine.audio public runtime and compatibility API
   azora-media-core/       # shared sources, stream IDs, timestamps, errors
   azora-media-ffmpeg/     # bundled AVI/MKV demux and audio decoder provider
   azora-audio-native/     # bundled macOS AudioUnit provider
   azora-profiler/         # engine.profiler counters and trace collection
 ```

 Suggested modules:

 ```text
 engine.media       # MediaSource, MediaTime, StreamId, shared errors
 engine.audio       # devices, streams, mixer, buses, voices, effects
 engine.media.ffmpeg
 engine.audio.native
 engine.profiler
 ```

 `azora-media-core` is the canonical home for `MediaSource`, `MediaTime`,
 `StreamId`, provider capability records, and shared media errors. `engine.video`
 and `engine.audio` re-export those declarations, so application code can use
 either package without importing an implementation provider. Providers depend
 on `engine.media`, never on `engine.video` or `engine.audio`.

 `engine.audio` depends on `engine.media` and `engine.profiler` only through
 stable contracts. The FFmpeg provider ships with the desktop engine media
 distribution. The macOS AudioUnit provider is the default low-latency output
 backend; an AVAudioEngine adapter may be added for platform features, but it is
 not the hot-path mixer backend.

 ## 4. Language-conforming public model

 The proposal uses current Azora declarations:

 - `pack` for data and handles;
 - `enum` for payload-free states;
 - `variant enum` for values with payloads;
 - `error` and `?!` for recoverable provider/device errors;
 - `spec` and `impl` for provider capabilities;
 - postfix `&` and `!` for shared and exclusive borrows;
 - `react func`, `remember`, `retain`, `preserve`, and `effect` for UI state;
 - `@System(.Update)` and the current `@query [...] @with ... @without ...`
   form for ECS integration.

 No `struct`, `trait`, `type`, `res`, or `mut res` syntax is used here.

 ## 5. Audio formats and time

 ### 5.1 Sample formats

 ```azora
 enum SampleFormat {
     U8
     S16
     S24
     S32
     F32
     F64
 }

 enum ChannelLayout {
     Mono
     Stereo
     TwoOne
     FiveOne
     SevenOne
     SevenOneTwo
     Ambisonic
     Custom
 }

 pack AudioFormat {
     fin sampleRate: std::Int
     fin channels: std::Int
     fin layout: ChannelLayout
     fin sampleFormat: SampleFormat
     fin interleaved: std::Bool
 }
 ```

 The mixer has one internal format chosen by the engine configuration, normally
 non-interleaved `F32`. Device providers may use another hardware format; the
 device adapter performs the final conversion after mixing.

 ### 5.2 Sample time

 Audio uses integer sample positions for exact seeking and avoids accumulating
 floating-point deltas:

 ```azora
 pack AudioSampleTime {
     fin samples: std::Long
     fin sampleRate: std::Int
 }

 func audioTimeSecs(time: AudioSampleTime): std::Float
 func audioTimeFromSecs(seconds: std::Float, sampleRate: std::Int): AudioSampleTime
 ```

 Movie audio also carries the shared `MediaTime`/`StreamId` contracts from
 `VIDEO.MD`. The decoder retains the original PTS time base until it converts
 it to the audio timeline.

 ### 5.3 PCM buffer

 ```azora
 pack AudioBuffer {
     fin format: AudioFormat
     fin start: AudioSampleTime
     fin frames: std::Int
     fin bytes: std::Int
     fin dataId: std::Long
 }
 ```

 `dataId` represents an engine-owned buffer lease. It is not a raw pointer in
 application code. The lease remains alive until the mixer/device has finished
 consuming it.

 ## 6. Error and state model

 ```azora
 enum AudioState {
     Closed
     Opening
     Ready
     Playing
     Paused
     Buffering
     Ended
     Interrupted
     Error
 }

 error AudioError {
     InvalidSource
     AccessDenied
     ProviderUnavailable
     UnsupportedContainer
     UnsupportedCodec(codec: std::String)
     InvalidFormat
     DecoderFailed
     DeviceUnavailable
     DeviceChanged
     DeviceInterrupted
     MixerFailed
     QueueFull
     QueueEmpty
     Cancelled
     Internal
 }
 ```

 An audio error belongs to the source, stream, voice, or device that caused it.
 It must not crash the engine or invalidate unrelated voices.

 ## 7. Devices and output backends

 ### 7.1 Device model

 ```azora
 pack AudioDeviceId {
     fin value: std::Int
 }

 pack AudioDeviceInfo {
     fin id: AudioDeviceId
     fin name: std::String
     fin isDefault: std::Bool
     fin isOutput: std::Bool
     fin minChannels: std::Int
     fin maxChannels: std::Int
     fin minSampleRate: std::Int
     fin maxSampleRate: std::Int
     fin preferredFormat: AudioFormat
     fin latencyFrames: std::Int
 }

 pack AudioDevice {
     fin id: AudioDeviceId
     fin info: AudioDeviceInfo
 }

 spec AudioBackend {
     func name[self: Self&](): std::String
     func devices[self: Self&](): std::Array<AudioDeviceInfo>
     func open[self: Self&](id: AudioDeviceId?, format: AudioFormat): AudioDevice ?! AudioError
     func close[self: Self!](device: AudioDevice)
 }
 ```

 ### 7.2 macOS backend decision

 The first macOS output backend uses the low-level AudioToolbox Audio Unit
 output path, specifically an `AUHAL`/HAL Output unit behind the platform
 adapter so the engine can select and observe the actual device. The engine
 installs and caches the nonblocking render callback,
 prepares the `AudioBufferList` before the callback, and feeds it from the
 preallocated mixer. This minimizes graph indirection and keeps device latency
 visible to the engine.

 `AVAudioEngine` remains an optional adapter for features it provides more
 conveniently, such as platform-managed node graphs or specialized routing.
 It is not used for the default movie-player hot path, because the engine needs
 direct control over its own mixer, queue deadlines, buffer leases, and clock.

 This choice follows Apple's API contracts: Audio Unit render callbacks are
 explicitly designed for nonblocking real-time rendering, while
 `AVAudioEngine` manages a higher-level node graph and real-time rendering
 lifecycle. See the [Audio Unit render callback documentation](https://developer.apple.com/documentation/audiotoolbox/aurendercallback?language=objc), [Audio Unit render block documentation](https://developer.apple.com/documentation/audiotoolbox/auaudiounit/renderblock?changes=_5_1&language=objc), and [AVAudioEngine documentation](https://developer.apple.com/documentation/avfaudio/avaudioengine).

 A provider reports the actual device format and latency; it must not assume
 that the default device remains available for the whole process.

 ### 7.3 Device lifecycle

 The device manager handles:

 - initial device enumeration;
 - default-device selection;
 - explicit device selection;
 - device addition and removal;
 - sample-rate or channel-layout changes;
 - application interruption and restoration;
 - graceful stop and restart.

 When a device disappears, the mixer keeps advancing the media clock only if a
 replacement clock is available. Otherwise movie playback enters `Buffering` or
 `Interrupted`, and the application receives a typed event.

 ```azora
 func audioDevices(): std::Array<AudioDeviceInfo>
 func audioOpenDevice(id: AudioDeviceId?): AudioDevice ?! AudioError
 func audioCloseDevice(device: AudioDevice)
 func audioDevice(): AudioDevice?
 func audioSetDevice(id: AudioDeviceId?): std::Unit ?! AudioError
 ```

 ### 7.4 Real-time callback rules

 The platform callback may run at a high priority and must do only bounded
 work:

 - read already prepared mixer commands;
 - mix active voices into a preallocated output buffer;
 - apply bounded, real-time-safe effects;
 - write the output format expected by the device;
 - publish counters through lock-free or per-thread storage.

 The callback must never allocate, open a file, call a decoder, wait on a
 general mutex, call UI/ECS code, or synchronously invoke arbitrary Azora
 callbacks. Control changes are queued from the application/jobs side and
 become visible at a sample boundary.

 ### 7.5 Dedicated audio buffer pool

 `AudioBuffer` storage uses a dedicated `engine.audio` pool, not an
 `engine.io` `Blob` lease. File blobs have the wrong lifetime and allocation
 behavior for the audio callback. The pool owns fixed-size PCM blocks and a
 bounded set of larger blocks for long decoder frames.

 ```azora
 pack AudioBufferPool {
     fin id: std::Long
     fin format: AudioFormat
     fin blockFrames: std::Int
     fin blockCount: std::Int
     fin maxBytes: std::Long
 }

 pack AudioBufferPoolStats {
     fin capacity: std::Int
     fin available: std::Int
     fin inUse: std::Int
     fin highWater: std::Int
     fin exhausted: std::Long
 }

 func audioCreateBufferPool(format: AudioFormat, blockFrames: std::Int, blockCount: std::Int): AudioBufferPool ?! AudioError
 func audioDestroyBufferPool(pool: AudioBufferPool)
 func audioBufferPoolStats(pool: AudioBufferPool): AudioBufferPoolStats
 ```

 Decoder workers acquire a block, fill it, attach its media timestamp, and
 publish it to the stream queue. The mixer releases it after consumption. Pool
 exhaustion is a measured `QueueFull`/buffering condition, never an emergency
 allocation on the callback thread. `engine.io` remains the source/asset read
 boundary; it copies or decodes into the audio pool before playback.

 ## 8. Sources, clips, and streams

 ### 8.1 Source values

 ```azora
 import engine.io

 variant enum AudioSource {
     Path(std::String)
     Bytes(Blob)
     Movie(VideoPlayer, StreamId)
 }

 enum AudioLoadMode {
     DecodeAll
     Stream
     Auto
 }

 pack AudioLoadOptions {
     fin mode: AudioLoadMode
     fin targetFormat: AudioFormat?
     fin bufferSecs: std::Float
     fin provider: std::String?
 }
 ```

 `Path` is required for the first movie-player release. `Bytes` is useful for
 packed assets. `Movie` is the shared path from a `VideoPlayer` selected audio
 stream into the mixer.

 ### 8.2 Clip and stream handles

 ```azora
 pack AudioClipId {
     fin value: std::Long
 }

 pack AudioStreamId {
     fin value: std::Long
 }

 pack AudioClip {
     fin id: AudioClipId
     fin format: AudioFormat
     fin duration: AudioSampleTime
 }

 pack AudioStream {
     fin id: AudioStreamId
     fin format: AudioFormat
     fin duration: AudioSampleTime?
     fin state: AudioState
 }
 ```

 Clips are finite decoded assets suitable for sound effects. Streams are
 decoded incrementally and are required for movies, long music, and large
 voice files.

 ### 8.3 Decoder provider

 ```azora
 pack AudioDecoderInfo {
     fin provider: std::String
     fin container: std::String
     fin codec: std::String
     fin format: AudioFormat
     fin duration: AudioSampleTime?
     fin seekable: std::Bool
 }

 spec AudioDecoder {
     func info[self: Self&](): AudioDecoderInfo
     func read[self: Self!](target: AudioBuffer!): std::Int ?! AudioError
     func seek[self: Self!](target: AudioSampleTime): AudioSampleTime ?! AudioError
     func flush[self: Self!]()
     func close[self: Self!]()
 }
 ```

 The decoder is never called by the device callback. `read` is a worker-side
 operation that fills an engine-owned buffer. The stream queue then presents
 those buffers to the mixer.

 ## 9. AVI/MKV movie audio

 ### 9.1 Provider choice

 The first provider is `engine.media.ffmpeg`. It uses the shared container
 session to enumerate audio streams and an audio decoder to produce timestamped
 PCM. AVI/MKV support is based on actual probing and codec capability, not the
 filename extension.

 A native provider may handle platform-supported formats, but it is not a
 substitute for the FFmpeg provider for arbitrary AVI/MKV files. The provider
 must report which stream and codec failed so video can continue silently when
 only the audio track is unsupported.

 ### 9.2 Supported initial profile

 The first acceptance fixtures should cover:

 - AVI with PCM and MP3 audio;
 - MKV with AAC, Vorbis, or Opus audio;
 - multiple audio tracks with language metadata;
 - non-zero start timestamps;
 - variable packet duration;
 - a file with no audio track;
 - a file with a damaged packet;
 - unsupported codec reporting.

 The same decoder contract can later add FLAC, AC-3, ALAC, and platform codec
 providers without changing the player API.

 ### 9.3 Media stream attachment

 ```azora
 pack MediaAudioOptions {
     var enabled: std::Bool
     var stream: StreamId?
     var bus: AudioBusId
     var volume: std::Float
     var muted: std::Bool
 }

 func audioAttachMovie(player: VideoPlayer, options: MediaAudioOptions): AudioStreamId ?! AudioError
 func audioDetachMovie(player: VideoPlayer)
 func audioSetMovieOptions(player: VideoPlayer, options: MediaAudioOptions)
 ```

 A movie stream is a normal mixer source after attachment. It can be muted,
 faded, routed, ducked, or stopped independently from its video surface.

 ## 10. Mixer graph

 ### 10.1 Buses

 ```azora
 pack AudioBusId {
     fin value: std::Int
 }

 pack AudioBus {
     fin id: AudioBusId
     fin parent: AudioBusId?
     var gain: std::Float
     var pan: std::Float
     var muted: std::Bool
     var solo: std::Bool
 }

 func audioCreateBus(parent: AudioBusId?): AudioBusId
 func audioDestroyBus(bus: AudioBusId)
 func audioSetBusGain(bus: AudioBusId, gain: std::Float)
 func audioSetBusPan(bus: AudioBusId, pan: std::Float)
 func audioSetBusMuted(bus: AudioBusId, muted: std::Bool)
 func audioSetBusSolo(bus: AudioBusId, solo: std::Bool)
 ```

 The default graph contains `Master`, `Music`, `Media`, `Effects`, `Voice`,
 and `UI`. Buses form a bounded acyclic tree. A bus may not route to itself or
 to one of its descendants.

 ### 10.2 Voices

 ```azora
 enum AudioVoiceState {
     Stopped
     Starting
     Playing
     Paused
     Fading
     Ended
 }

 pack AudioVoiceId {
     fin value: std::Long
 }

 pack AudioVoice {
     fin id: AudioVoiceId
     var source: AudioClipId?
     var stream: AudioStreamId?
     var bus: AudioBusId
     var state: AudioVoiceState
     var gain: std::Float
     var pan: std::Float
     var loop: std::Bool
     var rate: std::Float
 }

 func audioPlayClip(clip: AudioClipId, bus: AudioBusId): AudioVoiceId ?! AudioError
 func audioPlayStream(stream: AudioStreamId, bus: AudioBusId): AudioVoiceId ?! AudioError
 func audioPauseVoice(voice: AudioVoiceId)
 func audioResumeVoice(voice: AudioVoiceId)
 func audioStopVoice(voice: AudioVoiceId)
 func audioSetVoiceGain(voice: AudioVoiceId, gain: std::Float)
 func audioSetVoicePan(voice: AudioVoiceId, pan: std::Float)
 func audioSetVoiceRate(voice: AudioVoiceId, rate: std::Float)
 func audioSetVoiceLoop(voice: AudioVoiceId, loop: std::Bool)
 ```

 A voice owns only a reference to a clip or stream. It does not own decoder
 thread state. Releasing a voice decrements the source lease and schedules
 cleanup outside the device callback.

 ### 10.3 Loading and compatibility API

 ```azora
 func audioLoadClip(path: std::String, options: AudioLoadOptions): AudioClip ?! AudioError
 func audioOpenStream(path: std::String, options: AudioLoadOptions): AudioStream ?! AudioError
 func audioReleaseClip(clip: AudioClipId)
 func audioCloseStream(stream: AudioStreamId)

 // Compatibility wrappers retained from the current azora-audio package.
 func loadSound(path: std::String): Sound
 func playSound(sound: Sound): AudioVoiceId ?! AudioError
 func stopSound(sound: Sound)
 ```

 Existing short sound code remains valid while new code can opt into typed
 errors and streaming. The compatibility layer must route through the mixer,
 not create a second unmanaged device path.

 ## 11. Effects and processing

 ### 11.1 Effect contract

 ```azora
 spec AudioEffect {
     func process[self: Self!](buffer: AudioBuffer!, format: AudioFormat&)
     func reset[self: Self!]()
     func latency[self: Self&](): std::Int
 }
 ```

 Effects are instantiated and configured outside the callback. The callback
 invokes only prevalidated, real-time-safe implementations.

 `spec AudioEffect` is the extensibility boundary from the first mixer
 release. Built-in gain, pan, filters, compressor, limiter, and delay are
 ordinary `pack` implementations of that spec, so a project can replace or
 extend them without a second plugin mechanism. The engine validates that an
 effect is real-time safe before it is attached to a live bus.

 ```azora
 pack GainEffect {
     var gain: std::Float
 }

 impl AudioEffect for GainEffect {
     func process[self: Self!](buffer: AudioBuffer!, format: AudioFormat&) {
     }

     func reset[self: Self!]() {
     }

     func latency[self: Self&](): std::Int {
         return 0
     }
 }
 ```

 ### 11.2 First effects

 The first release should include:

 - gain;
 - equal-power pan;
 - mute and fade;
 - one-pole low-pass and high-pass filters;
 - compressor;
 - limiter on the master bus;
 - delay/echo with a bounded ring buffer;
 - bounded algorithmic reverb with send/return routing.

 Convolution reverb and HRTF use optional providers over the same effect and
 spatializer contracts. Every effect reports latency so movie synchronization
 and voice alignment can account for it.

 ```azora
 pack AudioEffectId {
     fin value: std::Int
 }

 pack AudioParameterId {
     fin value: std::Long
 }

 func audioAttachEffect(bus: AudioBusId, effect: AudioEffectId): std::Unit ?! AudioError
 func audioDetachEffect(bus: AudioBusId, effect: AudioEffectId)
 func audioSetEffectParameter(effect: AudioEffectId, parameter: AudioParameterId, value: std::Float)
 ```

 Effect parameters resolve to stable symbols when the effect pack is compiled
 or registered. Their names are editable diagnostics and may repeat in different
 effects without aliasing.

 ### 11.3 Procedural audio

 Procedural sources generate bounded PCM directly into a caller-owned pool lease.
 They use the same voice, bus, spatialization, effect, clock, and profiler paths
 as clips and streams; procedural sound is not a separate output engine.

 ```azora
 spec AudioGenerator {
     func prepare[self: Self!](format: AudioFormat&, maxFrames: std::Int)
     func generate[self: Self!](buffer: AudioBuffer!, frames: std::Int, time: AudioSampleTime&): std::Int
     func reset[self: Self!]()
 }

 pack Oscillator {
     var frequency: std::Double
     var phase: std::Double
     var gain: std::Double
 }

 impl AudioGenerator for Oscillator {
     func prepare[self: Self!](format: AudioFormat&, maxFrames: std::Int) {
     }

     func generate[self: Self!](buffer: AudioBuffer!, frames: std::Int, time: AudioSampleTime&): std::Int {
         return frames
     }

     func reset[self: Self!]() {
         self.phase = 0.0
     }
 }
 ```

 Built-in generators include oscillators, noise, envelopes, wavetable playback,
 filters, modulation, granular playback, and a bounded node graph. Randomness is
 seeded from generator and voice symbols so offline tests and Replay can reproduce
 it. Graph topology and memory are prepared outside the callback; the real-time
 `generate` call cannot allocate, lock, load files, or invoke user UI/game code.

 ### 11.4 Reverb and acoustic environments

 Reverb is bus-based. Emitters send to one or more reverb buses; zones and portal
 geometry determine send level, early-reflection profile, occlusion, and wet/dry
 transition. The listener blends overlapping zones by priority and weight.

 ```azora
 pack AudioEnvironmentId {
     fin value: std::Long
 }

 @Component
 pack AudioReverbZone {
     fin environment: AudioEnvironmentId
     var priority: std::Int
     var blendDistance: std::Double
     var send: std::Double
 }
 ```

 The built-in algorithmic reverb has bounded delay lines allocated during
 preparation and is required in the first complete engine release. Convolution
 providers stream/partition impulse responses on workers and publish a prepared
 effect generation; they never decode or allocate in the device callback.

 ## 12. Spatial audio

 Spatial audio is useful for games and engine screens, but movie playback must
 default to a stable 2D route. A source opts into spatialization explicitly.

 ```azora
 pack AudioListener {
     var x: std::Float
     var y: std::Float
     var z: std::Float
     var forwardX: std::Float
     var forwardY: std::Float
     var forwardZ: std::Float
     var upX: std::Float
     var upY: std::Float
     var upZ: std::Float
 }

 pack AudioEmitter {
     var x: std::Float
     var y: std::Float
     var z: std::Float
     var minDistance: std::Float
     var maxDistance: std::Float
     var rolloff: std::Float
     var spatial: std::Bool
 }

 func audioSetListener(listener: AudioListener)
 func audioSetEmitter(voice: AudioVoiceId, emitter: AudioEmitter)
 ```

 The first spatial implementation may use equal-power pan and distance
 attenuation. HRTF and room simulation remain opt-in provider features.

 ## 13. Audio/video clock and synchronization

 ### 13.1 Clock ownership

 ```azora
 enum AudioClockMode {
     Device
     Media
     Engine
     External
 }

 pack AudioClock {
     fin mode: AudioClockMode
     fin sampleRate: std::Int
     fin position: AudioSampleTime
     fin rate: std::Float
     fin paused: std::Bool
 }

 func audioClock(): AudioClock
 func audioClockPosition(): AudioSampleTime
 ```

 When a movie has enabled audio, the device presentation position is the master
 clock. Video compares its frame PTS with that clock. For a muted or silent
 movie, video may become the master. An explicit engine or external clock is
 available for deterministic simulation and synchronized installations.

 ### 13.2 Stream queue

 ```azora
 pack AudioBufferPolicy {
     fin minBufferedSecs: std::Float
     fin targetBufferedSecs: std::Float
     fin maxBufferedSecs: std::Float
     fin maxBytes: std::Long
 }

 pack AudioStreamStats {
     fin queuedSecs: std::Float
     fin queuedBytes: std::Long
     fin decodedFrames: std::Long
     fin consumedFrames: std::Long
     fin underruns: std::Long
     fin overruns: std::Long
     fin droppedFrames: std::Long
     fin ptsDriftSecs: std::Float
 }

 func audioStreamStats(stream: AudioStreamId): AudioStreamStats
 func audioSetBufferPolicy(stream: AudioStreamId, policy: AudioBufferPolicy)
 ```

 The queue is bounded by both time and bytes. Audio is not dropped during
 normal playback. If it cannot be produced before the device deadline, the
 stream enters buffering and the media session decides whether video should
 pause, repeat its last frame, or continue under a configured policy.

 ### 13.3 Drift correction

 The audio/video session measures drift continuously:

 - small long-term drift is corrected by tiny resampling changes;
 - a short audio queue gap enters buffering rather than emitting silence
   without a diagnostic;
 - video frames may be dropped when they are already late;
 - a seek flushes packet, decoder, PCM, subtitle, and presentation queues as
   one generation;
 - a device change rebuilds the output converter and resets the clock anchor;
 - all corrections are visible in profiler counters.

 Audio must never seek the video decoder from the device callback. It publishes
 a clock/event; the media session handles the control operation asynchronously.

 ## 14. Seeking, rate, and loop

 ```azora
 enum AudioSeekMode {
     Fast
     Exact
 }

 pack AudioSeekRequest {
     fin target: AudioSampleTime
     fin mode: AudioSeekMode
     fin resume: std::Bool
 }

 func audioSeekStream(stream: AudioStreamId, request: AudioSeekRequest): AudioSampleTime ?! AudioError
 func audioSetStreamRate(stream: AudioStreamId, rate: std::Float): std::Unit ?! AudioError
 func audioSetStreamLoop(stream: AudioStreamId, loop: std::Bool)
 ```

 A seek is serialized by the stream generation:

 1. stop consuming the old generation;
 2. pause or detach the voice;
 3. flush decoded PCM and pending mixer commands;
 4. seek the provider to a valid packet boundary;
 5. decode until the requested sample time;
 6. reset the audio clock anchor;
 7. resume only when requested.

 Rate changes must preserve the current media position and keep the device
 output format stable. Time stretching is optional in the first release; a
 simple resample-rate change is acceptable for `0.5` through `2.0`.

 ## 15. Ducking and focus

 ```azora
 enum AudioFocus {
     Gain
     Duck
     Pause
     Ignore
 }

 pack AudioFocusRule {
     fin trigger: AudioBusId
     fin target: AudioBusId
     fin mode: AudioFocus
     fin gain: std::Float
     fin attackSecs: std::Float
     fin releaseSecs: std::Float
 }

 func audioSetFocusRule(rule: AudioFocusRule)
 func audioRemoveFocusRule(trigger: AudioBusId, target: AudioBusId)
 ```

 Voice dialogue can duck `Music` and `Media`; a movie can remain audible at a
 reduced gain while the application speaks. Focus rules are evaluated outside
 the callback and compiled into sample-safe ramp commands.

 ## 16. ECS and reactive UI integration

 Audio handles are resources owned by the audio runtime. ECS components hold
 references or declarative intent, not decoder pointers.

 ```azora
 @Component
 pack AudioPlayback {
     voice: AudioVoiceId
     autoplay: std::Bool
     active: std::Bool
 }

 @System(.Update)
 func updateAudioPlayback(
     query: @query [AudioPlayback!, Transform!] @with AudioEnabled @without Disabled
 ) {
     for entity in query {
         audioUpdateVoice(entity.0.voice, entity.1)
     }
 }
 ```

 The query is intentionally written in the current accepted form. A video
 entity may carry both `VideoPlayback` and `AudioPlayback`; ownership remains
 in the respective runtime resources.

 A reactive control surface follows the current reactive syntax:

 ```azora
 react func MovieAudioControls(player: VideoPlayer) {
     remember var muted: std::Bool = false
     remember var volume: std::Float = 1.0

     effect muted {
         videoSetMuted(player, muted)
     }

     @compose world {
         slider(volume, 0.0, 1.0) {
             volume = it
             videoSetVolume(player, volume)
         }
         button(onClick: [&muted] { muted = !muted }) {
             text("Mute")
         }
     }
 }
 ```

 UI code observes `Signal`/revision changes and does not access the device
 callback directly.

 ## 17. Threading and job scheduling

 ### 17.1 Worker roles

 - demux workers read packets from the media source;
 - decoder workers turn packets into PCM;
 - conversion workers resample/remix into the engine format;
 - mixer control workers publish bounded commands;
 - the device callback consumes only prepared audio;
 - profiler collectors merge per-worker buffers off the callback.

 `engine.jobs` owns worker scheduling. One movie must not create an unlimited
 private pool. Movie audio and video share a fair global budget and use session
 generation tokens to cancel stale decode work after seek or close.

 ### 17.2 Global job API decision

 `engine.jobs` owns one global worker pool for the process. The media packages
 do not create threads and do not expose scheduler internals. This is the most
 ergonomic arrangement for applications: the engine can reserve capacity for
 render, audio, input, and simulation once, while every movie shares the same
 cancellation and profiling model.

 The public priority names are:

 ```azora
 import engine.jobs

 enum JobPriority {
     Urgent
     Interactive
     Normal
     Background
 }

 pack JobToken {
     fin id: std::Long
     fin generation: std::Long
 }

 func jobsCancel(token: JobToken)
 func jobsIsCancelled(token: JobToken): std::Bool
 ```

 `Urgent` is for a near presentation deadline or an interactive seek.
 `Interactive` is normal live decode and conversion. `Normal` is general
 engine work. `Background` is metadata, thumbnails, and prefetch work.
 There is deliberately no `Realtime` job priority: the audio device callback
 is not a job and must remain independent of the worker pool.

 Cancellation uses `JobToken` and is cooperative. `engine.jobs` marks the token
 canceled; workers check it before starting a packet, after a provider call,
 and before publishing a frame or PCM block. A media session also increments
 its generation on seek, close, or provider replacement, so stale jobs cannot
 publish into a newer session. Forced thread termination is not part of the
 API.

 Media submits work with an optional deadline and a priority. `engine.jobs`
 schedules it fairly across the global pool, and `engine.profiler` records
 queue wait, worker time, cancellation, and deadline misses.

 ### 17.3 Real-time safety

 The audio callback has a stricter contract than ordinary engine systems:

 - no `async`, `await`, `delay`, or provider call;
 - no memory allocation or deallocation;
 - no general mutex or condition wait;
 - no filesystem, network, Objective-C object creation, or UI call;
 - no mutation of ECS/world state;
 - no unbounded loop depending on a queue that may grow;
 - no direct call into a video decoder.

 The mixer uses preallocated voice/effect slots, lock-free or single-producer
 command queues, bounded ring buffers, and sample-accurate parameter ramps.

 ## 18. Profiler integration

 The audio runtime emits to the canonical `engine.profiler` event, context,
 metric, and trace model defined by `PROFILER.MD`. Media-specific sites and
 context metadata remain shared with `VIDEO.MD`.

 Required audio counters:

 - device sample rate, channel layout, buffer size, and measured latency;
 - callback duration, p95/max callback duration, and deadline misses;
 - active voices, active streams, active effects, and bus count;
 - decoded frames, mixed frames, consumed frames, underruns, and overruns;
 - decoder time, conversion/resampling time, mixing time, and device write time;
 - queue seconds/bytes per stream;
 - current audio clock and audio/video drift;
 - device changes, interruptions, recovery attempts, and failed opens;
 - peak mixer memory and buffer-lease count;
 - per-bus gain, mute, solo, ducking, and effect latency.

 The profiler must show callback starvation separately from decoder starvation:
 a healthy decoder queue with missed device deadlines is an output/mixer issue,
 while an empty decoder queue is a source/provider issue.

 ## 19. Events and lifecycle

 ```azora
 @Event
 variant enum AudioEvent {
     DeviceOpened(AudioDevice)
     DeviceClosed(AudioDeviceId)
     DeviceChanged(AudioDeviceInfo)
     StreamReady(AudioStreamId)
     StreamBuffering(AudioStreamId)
     StreamEnded(AudioStreamId)
     VoiceStarted(AudioVoiceId)
     VoiceStopped(AudioVoiceId)
     Underrun(AudioStreamId)
     Error(AudioError)
 }
 ```

 Events are delivered through the engine's bounded event mechanism. The audio
 callback publishes counters or a compact notification token; the regular
 engine schedule converts that token into `AudioEvent` values.

 Closing a stream detaches all voices, cancels worker jobs, drains provider
 leases, releases effects, and waits for the device-safe boundary before
 recycling PCM buffers. `audioCloseStream` is idempotent.

 ## 20. Security and resource limits

 Audio decoders consume untrusted files. The provider boundary must:

 - cap metadata, packet, attachment, and decoded-buffer memory;
 - reject impossible sample rates, channel counts, layouts, and durations;
 - bound codec delay and resampler state;
 - cancel I/O and decoding on close;
 - avoid arbitrary external subtitle/resource loading through media metadata;
 - keep native handles private to the provider;
 - report malformed media without affecting unrelated voices;
 - prevent a file from requesting an unbounded number of channels or effects.

 ## 21. Implementation phases

 ### Phase 1: mixer and device contract

 - define `AudioFormat`, `AudioBuffer`, clock, error, and state values;
 - create the device/backend spec and a fake deterministic backend;
 - implement a preallocated F32 mixer and Master bus;
 - route the current `Sound` API through the mixer;
 - add callback deadline and underrun tests.

 ### Phase 2: clips and streaming

 - implement `AudioClip` and `AudioStream` ownership;
 - add worker-side decoder queues and buffer policies;
 - add resampling, channel remixing, fades, pan, mute, and looping;
 - implement device enumeration/change/recovery;
 - add compatibility tests for existing `loadSound` behavior.

 ### Phase 3: AVI/MKV movie audio

 - connect `engine.media.ffmpeg` stream selection to `engine.audio`;
 - support the initial PCM/MP3/AAC/Vorbis/Opus fixture profile;
 - implement language/track selection and disabled-audio fallback;
 - make audio the default movie clock;
 - implement synchronized pause, seek, loop, rate, and close.

 ### Phase 4: graph and effects

 - add Music, Media, Effects, Voice, and UI buses;
 - add ducking/focus rules;
 - add gain, pan, filters, compressor, limiter, and delay;
 - add 2D/3D emitter routing and effect latency accounting.

 ### Phase 5: profiling and performance

 - emit shared media spans and audio counters;
 - add callback deadline overlay and trace export;
 - benchmark one movie, several movies, and movie plus game audio;
 - tune worker fair sharing and queue targets;
 - add long-duration, device-change, seek-storm, and damaged-file fixtures.

 ## 22. Acceptance criteria

 ### Device and real-time behavior

 - the fake backend can run deterministic tests without a physical device;
 - the callback performs no allocation, I/O, blocking lock, decoder call, or UI
   work;
 - a device removal produces an event and recovers or enters `Interrupted`;
 - callback p95 and maximum duration remain below the device deadline in the
   reference configuration;
 - a blocked decoder cannot block unrelated sound effects.

 ### AVI/MKV playback

 - an AVI fixture with supported audio opens and plays;
 - an MKV fixture with supported audio opens and plays;
 - multiple tracks can be listed and one selected by `StreamId`;
 - unsupported movie audio is reported while silent video remains playable;
 - audio/video drift remains within the documented tolerance;
 - seek flushes and reanchors audio and video together;
 - pause/resume and loop do not reuse stale PCM.

 ### Mixer and graph

 - a movie voice, sound effect, music stream, and voice bus mix together;
 - gain, pan, mute, fade, loop, rate, ducking, and bus routing work;
 - master limiting prevents configured output clipping;
 - effect latency is reported and included in synchronization diagnostics;
 - closing a voice or stream eventually releases every buffer lease.

 ### Profiling

 - decoder starvation and device callback starvation are distinguishable;
 - profiler counters report queue depth, underruns, callback cost, drift, and
   device changes;
 - per-stage spans can be exported without stopping playback;
 - profiler overhead is bounded and disabled cleanly in `Off` mode;
 - a benchmark identifies whether additional CPU workers improve useful audio
   decode time or only increase queue wait/overhead.

 ## 23. Resolved architecture decisions

 1. **macOS output:** use the low-level AudioToolbox Audio Unit output path for
    the default backend. It gives the engine direct control over the nonblocking
    render callback, device format, latency, and clock. Keep an AVAudioEngine
    adapter for higher-level routing features, not the movie-player hot path.
 2. **PCM storage:** use a dedicated preallocated `engine.audio` buffer pool.
    `engine.io` reads sources and assets, but its blob leases never cross into
    the real-time callback.
 3. **Effects:** expose arbitrary effect packs through `spec AudioEffect` from
    the first mixer release. Built-in effects implement that same spec and are
    validated for real-time safety before attachment.
 4. **Jobs:** `engine.jobs` owns the single global worker pool. Public priorities
    are `Urgent`, `Interactive`, `Normal`, and `Background`; cancellation uses
    cooperative `JobToken` generation checks. The audio callback is outside the
    job pool and never waits on it.
 5. **Shared contracts:** `azora-media-core` owns the neutral media contracts.
    `engine.video` and `engine.audio` re-export them for ergonomic imports, while
    providers depend only on the neutral module.
