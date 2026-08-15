# Azora Image — Image Data, Decoding, Color, and Texture Preparation

Status: Proposal expanding a working BMP decoder
Package: `azora-image`
Module: `engine.image`

## 1. Decision

`azora-image` owns decoded image data, format detection, decoder/encoder
providers, color and alpha metadata, pixel transforms, mip preparation, and
palette animation data. GPU owns texture resources and uploads; Streaming owns
residency; I/O owns bytes and sources.

Decoding never performs a GPU call and never requires a file path. It consumes a
bounded byte view and returns an owned image generation or an explicit fault.

## 2. Current implementation audit

The current package sniffs magic bytes and decodes uncompressed BMP images in
8-bit palettized, 24-bit BGR, and 32-bit BGRA forms. It handles row padding,
bottom-up/top-down storage, retains palette/index planes, supports palette
editing and color keys, produces top-down RGBA8, and explicitly releases raw
buffers.

Gaps:

- only BMP is supported;
- malformed/truncated sources often become a plausible partially zero image;
- empty images and decode failures are indistinguishable;
- raw pointers and manual release are public;
- dimensions and multiplication are not protected by configurable decode
  budgets;
- color space, transfer function, alpha mode, orientation, row pitch, channel
  layout, precision, layers, faces, depth, and mip levels are absent;
- decode, transform, transcode, and texture upload cannot be scheduled or
  streamed independently.

## 3. Public model

```azora
enum PixelFormat {
    R8
    Rg8
    Rgba8
    Rgba16
    Rgba16Float
    Rgba32Float
    Indexed8
    Compressed
}

enum AlphaMode {
    Opaque
    Straight
    Premultiplied
}

enum ColorSpace {
    LinearSrgb
    Srgb
    DisplayP3
    Rec2020
    SceneLinear
    Embedded
}

pack ImageExtent {
    fin width: std::Int
    fin height: std::Int
    fin depth: std::Int
    fin layers: std::Int
    fin faces: std::Int
    fin levels: std::Int
}

pack ImageData {
    fin extent: ImageExtent
    fin format: PixelFormat
    fin alpha: AlphaMode
    fin colorSpace: ColorSpace
    fin planes: std::Array<ImagePlane>
    fin generation: std::Long
}

error ImageFault {
    UnknownFormat
    UnsupportedFormat
    MalformedSource
    TruncatedSource
    InvalidDimensions
    BudgetExceeded
    DecodeFailed
    EncodeFailed
    Cancelled
}
```

Planes carry buffer views, dimensions, row/slice pitch, subsampling, mip, layer,
and face. Images can preserve indexed palettes without also forcing an expanded
copy; expansion becomes an explicit transform or GPU palette path.

## 4. Format and provider strategy

Initial providers cover BMP compatibility, PNG, JPEG, WebP, HDR, and QOI.
Production texture ingestion adds KTX 2 with platform transcode targets. AVIF,
EXR, TIFF, SVG rasterization, camera/raw formats, and encoders remain optional
providers rather than mandatory dependencies.

Magic/signature detection is authoritative. File extensions are hints only.
Providers advertise formats, bit depths, animation, metadata, region decode,
progressive decode, encode, and thread-safety capabilities.

KTX alignment follows the official
[KTX 2 specification](https://registry.khronos.org/KTX/specs/2.0/ktxspec.v2.html)
so precomputed mip chains and GPU-ready/transcodable payloads can stream without
an RGBA expansion.

## 5. Color, alpha, orientation, and transforms

Every decoder records source color/transfer metadata and orientation. A caller
chooses whether to preserve, convert, or reject unknown profiles. Alpha
premultiplication is explicit and performed in a declared color space.

Transforms include crop, resize, flip/rotate, swizzle, format conversion,
palette application, mip generation, normal-map renormalization, and color-space
conversion. They are pure over owned input/output generations and can run
through Jobs. Production compression/transcoding is usually offline; runtime
fallback is capability and budget controlled.

## 6. Animation and streaming

Animated image containers expose frame timing, disposal, blend mode, and frame
regions instead of silently returning frame zero. Media may adapt long or
audio-bearing animated sources, but Image owns ordinary animated-image decode.

Header probing returns dimensions and format before full allocation. Region,
mip, and progressive requests cooperate with Streaming. Publication is
generation-atomic, and cancellation releases all partial planes.

## 7. Safety and diagnostics

Decode limits cover source bytes, dimensions, pixels, planes, frames, metadata,
profile size, decompressed bytes, recursion, and CPU time. Arithmetic uses
checked products before allocation. Decoders never read implicit zero padding
unless their format defines it.

Diagnostics expose provider, detected format, source/decoded sizes, color and
alpha decisions, transforms, decode/transcode time, allocations, cancellation,
and rejected-budget reason.

## 8. Delivery and acceptance

1. checked `ImageData`/planes and explicit faults around the BMP decoder;
2. PNG/JPEG/WebP providers, color/alpha/orientation metadata, and transforms;
3. KTX 2, mip/layer/face support, GPU upload descriptors, and Streaming;
4. animated images, async/region decode, encoders, and Profiler;
5. advanced HDR/color/provider conformance and hostile-input fuzzing.

Acceptance preserves indexed BMP animation, rejects truncated/oversized input,
round-trips declared color/alpha metadata, streams mips without full expansion,
and exposes no GPU/native decoder handle in public image data.
