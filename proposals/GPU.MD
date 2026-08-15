# Azora GPU — Portable Graphics and Compute Device Layer

Status: Proposal replacing a Metal-specific immediate foundation
Package: `azora-gpu`
Module: `engine.gpu`

## 1. Decision

`azora-gpu` owns portable GPU devices, queues, resources, synchronization,
graphics/compute pipelines, command recording, copies, queries, capability
discovery, memory budgeting, and backend providers. Render owns scene extraction
and pass policy. Shaders owns shader compilation, interfaces, and artifacts.
Platform supplies native surface targets but does not own the GPU device.

The API follows three principles:

1. resources use generation-checked handles rather than raw native addresses;
2. hazards and transitions are derived from declared pass/resource use;
3. every advanced feature is capability-gated with a declared fallback.

## 2. Current implementation audit

The native implementation currently creates a Metal device, command queue,
CAMetalLayer, fixed 2D/3D pipelines, depth states, sampler, depth texture, one
view-projection buffer, and one scratch block. `engine.gpu.draw` adds cube,
cylinder and grid creation, mesh drawing, simple directional light, immediate
rect/sprite/text draws, raw texture upload, and CoreText rasterization through
methods on Platform's `App`.

This proves end-to-end Metal rendering, but it has major gaps:

- `AzGpu`, `Mesh`, textures, pipelines, encoders, and native objects expose raw
  `Long` handles and implicit ownership;
- one monolithic device state supports only fixed vertex layouts and pipelines;
- no compute, storage buffers, indexed/indirect drawing, mipmaps, arrays,
  cubemaps, render targets, multisampling, queries, fences, async readback, or
  resource-state model;
- allocation and upload are synchronous and unbudgeted;
- one global scratch allocation is shared by unrelated operations;
- GPU core imports I/O without declaring it;
- `engine.gpu.draw` imports Platform while Platform depends on GPU, creating a
  conceptual cycle even though comments intend a higher adapter;
- WebGL rendering lives under Render rather than the GPU provider boundary;
- text rasterization and primitive mesh generation are not device concerns.

## 3. Package architecture

```text
azora-gpu-core       engine.gpu          # contracts, handles, capabilities
azora-gpu-metal      engine.gpu.metal    # Apple provider
azora-gpu-vulkan     engine.gpu.vulkan   # Vulkan provider
azora-gpu-web        engine.gpu.web      # WebGPU, WebGL compatibility fallback
azora-gpu-tools      engine.gpu.tools    # capture, validation, shader diagnostics
```

The current package can host these modules during migration, but dependency
direction is enforced immediately: Core has no Platform/App dependency; a
surface adapter may depend on both.

## 4. Handles and capabilities

```azora
pack GpuDeviceId {
    fin value: std::Long
    fin generation: std::Int
}

pack GpuBufferId {
    fin value: std::Long
    fin generation: std::Int
}

pack GpuTextureId {
    fin value: std::Long
    fin generation: std::Int
}

pack GpuPipelineId {
    fin value: std::Long
    fin generation: std::Int
}

pack GpuAccelerationStructureId {
    fin value: std::Long
    fin generation: std::Int
}

enum GpuQueueKind {
    Graphics
    Compute
    Transfer
}

enum GpuFeature {
    Compute
    Indirect
    Bindless
    MeshShader
    RayQuery
    RayTracing
    SparseResources
    TimelineSync
    Subgroups
}

error GpuFault {
    ProviderUnavailable
    DeviceCreationFailed
    SurfaceLost
    DeviceLost
    UnsupportedFeature
    InvalidDescriptor
    InvalidHandle
    OutOfMemory
    PipelineFailed
    MappingFailed
    Timeout
}
```

Capabilities include limits, formats, queue topology, memory heaps, shader
features, synchronization, sparse residency, timestamp support, and presentation
modes. Applications request required and preferred capabilities and receive a
selection trace.

## 5. Resources and memory

Descriptors define size/extent, format, usage, memory class, mapping policy,
initial data, label, and owner symbol. Buffers, textures, samplers, pipelines,
layouts, query sets, acceleration structures, and surfaces are immutable handles
to provider records.

Uploads use staging rings and batched copies. Dynamic uniform/storage data uses
frame arenas with alignment from device limits. Persistent assets use allocator
suballocation. Readback is asynchronous. Resource destruction is deferred until
all referencing submissions complete.

Memory budgets distinguish resident, allocated, pending, evictable, transient,
and external bytes. Streaming cooperates with budget pressure; GPU never
silently overcommits an unlimited cache.

## 6. Command and pass model

Commands are recorded into explicit render, compute, and transfer passes. A
pass declares every resource access, stage, range/subresource, and read/write
mode. The compiler/runtime derives barriers, encoder boundaries, queue transfers,
and transient aliasing. Invalid simultaneous use is reported before submission.

Render owns the high-level frame graph and supplies pass callbacks/data. GPU
owns backend-neutral validation and execution of the resulting resource graph.
Immediate compatibility drawing records into the active graph rather than
submitting hidden command buffers.

Graphics supports vertex/index buffers, instancing, indirect/multi-draw,
multiple render targets, depth/stencil, blending, multisampling, viewports,
scissors, push/small constants, descriptor groups, and pipeline statistics.
Compute supports dispatch, indirect dispatch, storage resources, atomics,
subgroups, and explicit workgroup limits.

Ray-capable providers support acceleration-structure build, refit, compaction,
instance generations, bounded scratch allocation, and ray-query/tracing command
resources. Render owns scene-instance policy; GPU owns native structures,
barriers, memory, build execution, and device-loss recovery. Spectrum, Shadows,
and Radiance consume Render's shared ray-scene view rather than native handles.

## 7. Shader and pipeline integration

Shaders supplies compiled modules plus reflected entry points, bindings, vertex
inputs, outputs, constants, capabilities, and layout hash. GPU validates a
pipeline descriptor against that reflection before backend creation.

Pipeline compilation is asynchronous and cached by shader artifact, layout,
render-target formats, fixed state, specialization values, device identity, and
driver/provider revision. Missing pipelines use an explicit fallback or skip
policy; they never block a real-time frame unexpectedly.

## 8. Surfaces, backends, and recovery

Platform creates a `SurfaceTarget` from a window/canvas. GPU chooses a device
and creates one or more presentable surfaces with color/HDR, depth, frame
latency, vsync, and presentation policy. Resize and scale changes are surface
events, not device recreation.

Metal, Vulkan, and WebGPU are first-class providers. WebGL remains a constrained
compatibility provider and reports missing compute/storage features. The
[WebGPU specification](https://www.w3.org/TR/webgpu/all/) informs the portable
safety baseline; Vulkan artifacts align with the official
[SPIR-V registry](https://registry.khronos.org/SPIR-V/).

Device loss freezes publication, preserves CPU asset descriptions, recreates
the provider/device where policy permits, and republishes resource generations.
Stale handles fail cleanly.

## 9. Diagnostics, testing, and delivery

Validation labels every object and pass. Profiler records CPU recording, GPU
timestamps, queue overlap, barriers, pipeline/cache events, draws, dispatches,
primitives, bandwidth, residency, transient aliasing, upload/readback, surface
latency, and device-loss recovery.

Delivery:

1. typed handles/descriptors, ownership, validation, and Metal compatibility;
2. buffers/textures/samplers/pipelines, staging, fences, and resource graph;
3. compute, async pipeline cache, timestamps, queries, and GPU Profiler;
4. Vulkan and WebGPU providers with a shared conformance suite;
5. indirect/bindless/sparse/mesh capability tiers, acceleration structures,
   ray queries/tracing, and recovery.

Acceptance requires zero public raw handles, no GPU-to-Platform dependency,
validated resource hazards, bounded memory, async pipeline/readback behavior,
device-loss tests, and identical reference output across available backends.
