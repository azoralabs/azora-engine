# Azora Shaders — Compiler IR, Reflection, and Portable Shader Artifacts

Status: Proposal replacing embedded hand-maintained backend source strings
Package: `azora-shaders`
Module: `engine.shaders`

## 1. Decision

`azora-shaders` owns the engine-facing shader artifact model, entry points,
resource interfaces, reflection, specialization, validation, source mapping,
and backend compilation adapters. Azora language/compiler work defines shader
syntax and lowers it into a canonical shader IR. GPU creates pipelines from
validated artifacts; Material builds shader graphs against this contract.

One shader implementation produces all supported backends. Parallel hand-written
MSL, Vulkan GLSL, and WebGL GLSL strings are compatibility assets only.

## 2. Current implementation audit

The package returns concatenated source strings for one 3D directional-Lambert
shader and one 2D colored/textured shader in Metal, Vulkan GLSL 4.50, and WebGL
GLSL ES 3.00 forms. This proves portable intent but the variants already differ
in binding names, texture modes, vertex interfaces, matrix conventions, and
image-color behavior.

Missing:

- parsed/typed shader source and shared IR;
- compute and advanced graphics stages;
- reflection, binding layouts, vertex formats, specialization, capabilities,
  source diagnostics, validation, caching, packaging, and hot reload;
- generated backend code and conformance tests;
- material-node integration;
- offline compilation and production binary artifacts;
- stable entry/binding symbols independent of backend spelling.

## 3. Shader artifact model

```azora
pack ShaderModuleId {
    fin symbol: ContentSymbol
    fin generation: std::Long
}

pack ShaderEntryId {
    fin module: ShaderModuleId
    fin symbol: ContentSymbol
}

enum ShaderStage {
    Vertex
    Fragment
    Compute
    Task
    Mesh
    RayGeneration
    ClosestHit
    AnyHit
    Miss
}

enum ShaderResourceKind {
    UniformBuffer
    StorageBuffer
    Texture
    StorageTexture
    Sampler
    AccelerationStructure
}

pack ShaderArtifact {
    fin id: ShaderModuleId
    fin entries: std::Array<ShaderEntry>
    fin resources: std::Array<ShaderResource>
    fin capabilities: std::Array<ShaderCapability>
    fin layoutHash: std::Long
    fin sourceMap: ShaderSourceMap
}

error ShaderFault {
    ParseFailed
    InvalidStage
    InvalidInterface
    UnsupportedCapability
    LayoutMismatch
    ValidationFailed
    BackendCompilationFailed
}
```

Resource and entry identity uses content/compiler symbols. Backend binding
numbers and generated names are derived layout, never authored identity.

## 4. Canonical IR and compilation

The shader IR represents scalar/vector/matrix values, aggregates, control flow,
functions, stage IO, resource access, derivatives, atomics, barriers,
workgroups, sampling, subgroup operations, and capability requirements. It has
defined layout and numerical semantics rather than inheriting whichever backend
source was generated first.

Compilation performs:

1. language semantic analysis and shader-safe effect checking;
2. specialization and dead-code elimination;
3. interface/resource layout;
4. capability validation against a target profile;
5. IR validation and optimization;
6. backend emission to Metal, SPIR-V/Vulkan, WGSL/WebGPU, or GLSL fallback;
7. backend validation and reflection cross-check;
8. content-addressed artifact/cache publication.

SPIR-V emission follows the official
[SPIR-V specification](https://registry.khronos.org/SPIR-V/specs/unified1/SPIRV.html).
WebGPU output follows its declared WGSL/device validation environment rather
than assuming Vulkan capabilities transfer unchanged.

## 5. Interfaces and layouts

Shader entry interfaces declare stage inputs/outputs, resource groups, access,
array bounds, formats, address spaces, workgroup size, push/small constants, and
specialization values. CPU-side packs used as uniforms/storage require a
compiler-verified shader layout view; reflection reports offsets, alignment,
stride, and matrix convention.

Pipeline creation compares layout hashes and reports the exact mismatched
symbol/member. There is no string lookup or silently guessed binding location.

## 6. Portability and capability tiers

The portable baseline covers vertex/fragment, compute, uniform/storage buffers,
sampled/storage textures, atomics, derivatives where legal, and explicit
numeric precision. Optional tiers cover subgroups, bindless access, mesh stages,
ray queries/tracing, sparse resources, and provider-specific extensions.

Every module declares required capabilities. Material and Render compile a
fallback permutation or mark the feature unsupported. Backend-specific source
blocks are permitted only behind explicit target/capability gates and cannot
change shared public interfaces silently.

## 7. Tooling, hot reload, and security

Diagnostics map backend errors through IR to Azora source locations and symbols.
Tools show entry call graphs, resource layouts, capabilities, generated code,
instruction counts, register/occupancy reports when available, and pipeline
consumers.

Development hot reload compiles a new immutable generation and publishes it
only after all target validation succeeds. In-flight frames keep the old
generation. Production packages use offline-validated artifacts and may disable
runtime source compilation.

Untrusted shader packages obey instruction, loop, resource, workgroup, compile
time, and generated-size limits. Provider escape hatches are disabled by
default for untrusted content.

## 8. Delivery and acceptance

1. artifact/reflection/layout model around current compatibility shaders;
2. canonical IR and generated Metal plus SPIR-V paths;
3. WGSL/WebGPU and GLSL compatibility emission with conformance fixtures;
4. compute, specialization, hot reload, pipeline cache, and Material integration;
5. advanced capability tiers, optimization, security limits, and editor tools.

Acceptance requires one source/IR per shader, matching reflection across
backends, compiler-verified CPU/GPU layouts, no string-based binding at runtime,
source-mapped diagnostics, atomic hot reload, and image-conformance tests for
every supported provider.
