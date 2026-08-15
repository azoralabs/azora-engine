# Azora Font — Unicode Shaping, Glyph Caches, and Bitmap Typography

Status: Proposal expanding an implemented bitmap-font path
Package: `azora-font`
Module: `engine.font`

## 1. Decision

`azora-font` owns font assets, fallback, Unicode shaping, glyph metrics,
line-breaking inputs, glyph rasterization providers, and glyph-atlas caches. UI
owns paragraph/layout policy and accessibility semantics. Render/GPU own draw
submission and texture resources.

The existing bitmap strip remains a first-class pixel-art font source. It
becomes one provider beside OpenType outline, color, variable, and system-font
providers rather than the universal representation.

## 2. Current implementation audit

The package currently loads a legacy `*key: value` manifest and a palettized BMP
glyph strip. It maps 128 character codes to fixed cells, supports ASCII
case-folding, measures by `character count * cell width`, draws regions through
`App`, and releases its image/texture explicitly.

This is useful and tested indirectly by applications, but it lacks:

- Unicode code points, grapheme clusters, scripts, direction, language,
  shaping, kerning, ligatures, marks, fallback, and font variations;
- proportional metrics, baselines, line metrics, wrapping, vertical text, and
  rich spans;
- OpenType/TrueType loading and scalable glyph rasterization;
- persistent glyph atlases, eviction, async preparation, and batching;
- backend-neutral render data;
- explicit decode/load faults and malformed-font budgets;
- declared manifest dependencies for the Platform/GPU modules it imports.

## 3. Public asset and shaping model

```azora
pack FontFaceId {
    fin symbol: ContentSymbol
}

pack FontFamilyId {
    fin symbol: ContentSymbol
}

enum TextDirection {
    Auto
    LeftToRight
    RightToLeft
    TopToBottom
}

pack FontStyle {
    fin family: FontFamilyId
    fin size: std::Double
    fin weight: std::Int
    fin width: std::Int
    fin slant: std::Double
}

pack TextSpan {
    fin text: std::String
    fin style: FontStyle
    fin language: std::String
    fin direction: TextDirection
}
```

Shaping transforms text spans into immutable `GlyphRun` values containing
glyph IDs, advances, offsets, clusters, face IDs, direction, and bounds. Glyph
IDs are always scoped by `FontFaceId`; glyph display names are never identity.
Cluster mapping preserves cursor movement, selection, hit testing, and assistive
technology positions.

## 4. Provider layers

- **Font source provider:** opens package, memory, system, or application fonts.
- **Shaping provider:** maps Unicode text to positioned glyph runs.
- **Raster provider:** produces bitmap, signed-distance, multi-channel distance,
  vector path, or color glyph payloads.
- **Atlas provider:** places glyph payloads in generation-checked GPU pages.
- **Bitmap-strip provider:** adapts the existing fixed-cell manifests exactly,
  including palette color-key behavior and legacy byte ordering.

Core font/shaping packages do not import Platform, App, or GPU. Optional native
providers may use CoreText; portable distributions may bundle HarfBuzz-compatible
shaping and an outline rasterizer. Render consumes shaped runs and atlas
bindings through stable contracts.

## 5. Layout boundary

Font supplies glyph runs, grapheme/word/line boundary opportunities, metrics,
and hit-test data. UI chooses width constraints, wrapping, alignment,
justification, truncation, selection, editing, and accessibility. This keeps the
same shaping cache usable by HUD, world labels, subtitles, editor text, and
reactive UI.

Shaping cache keys include text bytes/hash, face generations, variations,
features, language, script, direction, size policy, and normalization policy.
No cache key uses a display family name alone.

## 6. Glyph caches and rendering

Atlas pages are format-specific, bounded, and generation-checked. Eviction
cannot invalidate in-flight frames; old pages retire after GPU completion.
Raster requests are asynchronous and coalesced. Missing glyphs use a declared
fallback chain and visible replacement glyph.

Small bitmap fonts use nearest sampling and integer placement. Scalable text can
select grayscale, signed-distance, vector, or color rendering by size and
backend capability. LCD subpixel rendering is optional and disabled when the
surface/color pipeline cannot guarantee correct composition.

## 7. International text and standards

The implementation follows [Unicode text segmentation](https://unicode.org/reports/tr29/)
for user-perceived boundaries, uses the
[OpenType specification](https://learn.microsoft.com/en-us/typography/opentype/spec/overview)
for font tables/layout features, and adopts a shaping contract compatible with
[HarfBuzz shaping concepts](https://harfbuzz.github.io/shaping-concepts.html).
Provider conformance, not a hard dependency on one library, is the public rule.

## 8. Safety, diagnostics, and delivery

Font parsing is untrusted input and obeys table-count, glyph-count, recursion,
allocation, decompression, outline, and raster-time budgets. The inspector
shows fallback decisions, script/language/direction, clusters, glyph positions,
atlas pages, cache hits, missing glyphs, and provider diagnostics.

Delivery:

1. split bitmap data from App/GPU drawing and correct package dependencies;
2. add stable face/family IDs, glyph runs, proportional metrics, and fallback;
3. add OpenType source/raster provider and Unicode shaping/segmentation;
4. add bounded atlas caches, async generation, Render/UI integration;
5. add variable/color fonts, vertical text, editor diagnostics, and fuzzing.

Acceptance includes multilingual shaping fixtures, grapheme-correct cursor/hit
tests, stable fallback, pixel-perfect legacy bitmap fonts, bounded hostile-font
parsing, and no Platform/GPU dependency in the core font package.
