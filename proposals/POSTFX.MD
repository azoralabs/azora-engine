# Azora PostFX — HDR Post-Processing Pipeline

Status: Proposal
Primary package: `azora-postfx`
Primary module: `engine.postfx`

## 1. Decision

PostFX owns the camera-image pipeline after scene lighting: exposure, temporal
reconstruction/upscaling, anti-aliasing, bloom, tone mapping, color grading,
depth of field, motion blur, lens effects, and output transforms. Effects form
a validated render-graph stack with explicit color spaces and history contracts,
not an arbitrary list of full-screen callbacks.

## 2. Current engine audit

The renderer writes directly to a BGRA drawable with fixed shaders. There are no
HDR scene targets, render graph, history textures, velocity buffer, exposure,
tone mapping, off-screen passes, compute pipeline, or color-management records.
PostFX therefore starts with HDR output and graph infrastructure.

## 3. Public model

```azora
enum AntiAliasing {
    None
    Fxaa
    Taa
    TemporalUpscale
}

enum ToneMapper {
    Neutral
    Filmic
    Aces
}

@Component
pack PostProcessVolume {
    var priority: std::Int
    var weight: std::Double
    var unbounded: std::Bool
    var profile: PostProcessProfileId
}

@Resource
pack PostFxSettings {
    var antiAliasing: AntiAliasing
    var toneMapper: ToneMapper
    var renderScale: std::Double
    var hdrOutput: std::Bool
}
```

Profiles contain typed, blendable settings. Boolean/discrete fields choose by
priority; numeric/color fields blend with declared semantics. Camera overrides
are applied after spatial volumes.

## 4. Canonical order

1. resolve scene lighting and transparency into linear HDR;
2. classify exposure from luminance history;
3. reconstruct/upscale with depth, velocity, reactive, and transparency masks;
4. motion blur in scene-linear space;
5. depth of field with physically meaningful focus/aperture;
6. bloom and lens scattering;
7. local/global color grading;
8. tone map to output-referred values;
9. chromatic aberration, vignette, grain, and UI-safe lens effects;
10. convert to SDR or HDR display color space and composite UI by policy.

Effects can request a different legal insertion point, but the graph validates
domain and color space. UI defaults to after tone mapping for readability.

## 5. Temporal contract

Camera publishes jitter, previous/current view transforms, cut generation, and
exposure. Renderers publish motion vectors and reactive masks. Every history
resource keys camera symbol, dimensions, render scale, effect revision, color
space, and cut generation. Resize, cut, teleport, or incompatible setting
changes reset only affected histories.

Dynamic resolution has hysteresis and profiler-driven policy outside the
recording hot path. Upscaling has native, platform, and portable providers behind
one capability contract; provider brand types do not leak into gameplay.

## 6. Effect requirements

- Exposure uses percentile/histogram adaptation with separate up/down speeds.
- Bloom is energy-aware and resolution-pyramidal.
- Tone mapping handles negative/over-range working values robustly.
- Color grading supports lift/gamma/gain, curves, white balance, and 3D LUTs.
- DOF distinguishes foreground/background and controls scatter cost.
- Motion blur uses velocity/depth tile maxima and excludes UI.
- Chromatic aberration and grain are opt-in and accessibility-disableable.

## 7. Diagnostics and delivery

Debug views show every input/output, HDR histogram, exposure, velocities, depth,
reactive mask, temporal confidence, bloom levels, CoC, grading LUT, gamut clips,
and output nits. Counters include pass time, transient/history memory, render
scale, history acceptance, luminance percentiles, and fallback provider.

Delivery:

1. HDR scene target, render graph, exposure, neutral/filmic tone mapping.
2. bloom, grading, FXAA, color-space validation, and volume blending.
3. motion vectors, TAA, dynamic resolution, and temporal upscaling contract.
4. DOF, motion blur, lens effects, HDR output, and platform providers.
5. editor graph inspection, custom validated effects, and cinematic quality.

