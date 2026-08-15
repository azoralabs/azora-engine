# Azora Shadows — Virtualized High-Resolution Shadows

Status: Proposal
Primary package: `azora-shadows`
Primary module: `engine.shadows`

## 1. Decision

Azora Shadows is a virtual page-based shadow system with capability fallbacks.
It allocates physical shadow pages only where visible pixels request them,
caches static pages across frames, invalidates pages by caster/light revision,
and supports directional clipmaps plus local-light virtual maps. Conventional
cascades and atlas maps remain portable fallbacks.

Lighting owns lights; Spectrum owns scalable stochastic light/sample selection
and the direct estimator; Shadows owns their visibility representation. Spectrum
may request ray visibility for a selected area-light sample, and Radiance may
trace separate indirect/reflection visibility, but neither owns shadow-map
residency.

## 2. Current engine audit

The current renderer has one unshadowed directional light embedded in `AzGpu`.
There are no depth-only passes, shadow casters, atlases, depth pyramids, render
graph, light entities, or cache invalidation. The first milestone must establish
those basics before virtual paging.

## 3. Public model

```azora
enum ShadowMethod {
    Disabled
    Atlas
    Cascades
    Virtual
    RayQuery
}

enum ShadowQuality {
    Low
    Medium
    High
    Cinematic
}

@Component
pack ShadowCaster {
    var enabled: std::Bool
    var twoSided: std::Bool
    var invalidateOnMove: std::Bool
}

@Resource
pack ShadowSettings {
    var method: ShadowMethod
    var quality: ShadowQuality
    var physicalPages: std::Int
    var pageSize: std::Int
    var maxUpdatesPerFrame: std::Int
    var contactDistance: std::Double
}
```

Material publishes masked-opacity and displacement shadow variants. Lighting
requests a `ShadowView` by stable light symbol. Mesh names are never identities.

## 4. Virtual map design

Each light has virtual coordinates mapped through a page table to a shared
physical depth pool. The frame pipeline is:

1. project receiver samples and mark requested pages;
2. merge requests with cached residency;
3. prioritize missing/dirty pages by visibility and projected error;
4. allocate or evict physical pages under budget;
5. cull casters to page frusta;
6. render dirty pages using GPU-driven commands;
7. update page tables and sample with receiver-plane bias/filtering.

Directional lights use concentric world-space clip levels snapped to page-sized
increments. Local lights use perspective or cube/octahedral virtual spaces.

## 5. Invalidation

A page key includes light symbol/revision, world cell, clip level, material
shadow revision, and caster geometry revision. Static pages survive camera
movement. A moving caster dirties only overlapping pages. World unload revokes
those pages after the last GPU fence. Origin rebasing changes transforms without
invalidating geometry that remains in the same absolute world region.

## 6. Quality and filtering

The initial filter is percentage-closer filtering with normal and slope-aware
bias. Higher tiers add contact hardening and ray-query contact shadows. Thin
alpha-tested foliage uses a specialized material variant and stochastic or
coverage-aware sampling. Translucent colored shadows are a later extension and
must not overload the opaque depth format.

### 6.1 Ray visibility contract

Spectrum supplies a finite receiver-to-emitter segment, stable light/sample
identity, channel/caster mask, and requested transparency policy. Shadows traces
that segment through Render's immutable ray-scene view and returns visibility,
hit identity/distance where authorized, and typed fallback status. Spectrum owns
area-light integration, reservoir weights, temporal reuse, and direct denoising.

GPU owns acceleration-structure resources and Render owns ray-scene instances;
Shadows owns direct caster filtering, alpha-test intersection policy, epsilon,
sidedness, and visibility execution. This prevents Shadows, Spectrum, and
Radiance from constructing three competing scene acceleration structures.

## 7. Fallbacks

- no compute/storage buffers: fixed atlases and directional cascades;
- no sparse resources: software page table over a texture array;
- no indirect drawing: CPU-generated page draw lists under a lower caster cap;
- no depth compare: encoded depth with explicit compare;
- exhausted budget: retain coarse levels first and report missing fine pages.

Spectrum may prioritize full-resolution maps for reservoir-winning lights while
the rest use coarse/imperfect maps. Spectrum provides demand; Shadows remains the
only allocator and cache owner.

## 8. Diagnostics and tests

Debug views show requested, resident, dirty, rendered, cached, and missing pages;
clip levels; caster counts; and per-light allocation. Profiler counters cover
page requests, hit rate, evictions, invalidation causes, rendered triangles,
allocation bytes, CPU build time, GPU page time, and fallback pixels.

Acceptance scenes include camera fly-through, moving sun, thousands of local
lights, deforming foliage, world streaming, origin rebasing, thin geometry, and
rapid caster motion. Cached output must be equivalent to fully redrawn output
within the selected filter tolerance.

## 9. Delivery

1. light-owned depth passes, caster components, cascades, and local atlases.
2. shared physical page pool and software virtual page table.
3. receiver feedback, cached invalidation, and directional clipmaps.
4. Shard-aware GPU culling and local-light virtual maps.
5. Spectrum-selected map demand, contact hardening, foliage policy, and
   ray-query hybrid visibility.
