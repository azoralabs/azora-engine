# Azora Camera — Gameplay and Cinematic Camera Rigs

Status: Proposal building on minimal implementation
Primary package: `azora-camera`
Primary module: `engine.camera`

## 1. Decision

Camera owns camera entities, lenses, view families, gameplay rigs, constraints,
spring arms, blending, shake, camera cuts, and render history identity. Render
consumes evaluated views; Cinematics drives rigs through the same public model.
PostFX owns image effects and exposure implementation, while Camera owns their
per-view profile selection.

## 2. Current engine audit

`engine.render.Camera` currently contains position, yaw, pitch, and FOV. It can
compute a perspective view-projection matrix and directly reads WASD/QE/arrow
keys for a fly camera. Near/far planes are fixed, rotation is Euler-based, and
there is one view. Tilemap separately has a `TileCamera` with center, zoom, view
size, screen/world conversion, map clamping, and pointer picking. There are no
ECS camera components, projection variants, rigs, priorities, blends, cuts,
spring arms, collision, shake, split screen, stereo, or history generations.

The existing fly and tile cameras become ready-made rigs, not the core camera
representation.

## 3. Public model

```azora
pack CameraId {
    fin value: std::Long
}

enum ProjectionKind {
    Perspective
    Orthographic
    Physical
}

@Component
pack Camera {
    fin id: CameraId
    var projection: ProjectionKind
    var nearPlane: std::Double
    var farPlane: std::Double
    var priority: std::Int
    var enabled: std::Bool
}

@Component
pack CameraLens {
    var verticalFovRadians: std::Double
    var focalLengthMm: std::Double
    var sensorWidthMm: std::Double
    var aperture: std::Double
    var focusDistance: std::Double
}

@Component
pack CameraOutput {
    var viewport: Rect
    var layerMask: std::Int
    var postProcess: PostProcessProfileId
}

@Resource
pack ActiveCamera {
    var camera: Entity
    var cutGeneration: std::Long
}
```

## 4. Rig model

A rig evaluates a target view from inputs without touching the renderer.

```azora
spec CameraRig {
    func evaluate(context: CameraContext&, output: CameraPose!)
}
```

Built-ins: fixed, fly, orbit, first-person, third-person follow, spring arm,
side-scroller, top-down, rail/spline, framing/group, handheld, vehicle chase,
look-at, and XR head pose. Rigs compose through constraints rather than one giant
mode enum.

Spring arms sweep a sphere through Physics, retract quickly, recover with
damping, and ignore the followed entity. Framing rigs solve position/FOV to keep
targets inside safe bounds. Camera-local noise never changes authoritative
gameplay transforms.

## 5. Blending and cuts

Camera selection is stable by priority then camera symbol. A transition blends
position, orientation, lens, focus, and PostFX profile with separately authored
curves. Quaternion shortest-path interpolation avoids Euler flips. Interruptions
start from the currently rendered pose, not the abandoned source pose.

A cut increments `cutGeneration`. Radiance, Shadows, PostFX, occlusion, motion
blur, and Streaming use this generation to reject history or raise priority.
Large teleports may request a cut even when the camera entity is unchanged.

## 6. View families

One camera can emit a view family: mono, stereo XR, cubemap/probe, shadow-like
capture, split-screen, editor views, or portals. Family members share culling
when valid but retain separate projection/history identities. Camera-relative
matrices use World origin generation and preserve absolute transforms for
streaming queries.

## 7. Input, animation, and cinematics

Camera rigs consume Input actions, never raw key constants. Animation may drive
rig parameters and shake envelopes. Cinematics owns timeline tracks and chooses
cameras; Camera owns evaluated pose, blend/cut semantics, and renderer contract.
Networking normally replicates targets/rig parameters rather than every visual
shake sample. Replay records authoritative selection and seeds.

## 8. Diagnostics and delivery

Debug views show source/target/blended poses, frusta, safe frames, follow target,
spring-arm sweep, collision, damping velocity, shake layers, active priority,
view family, and cut generation. Counters include rigs evaluated, sweeps, active
views, blend time, culling reuse, and history resets.

Delivery:

1. ECS camera/lens/output, active selection, perspective/orthographic views.
2. fly/orbit/follow/spring-arm rigs and Input actions.
3. blends, cuts, shake, framing, split screen, render history contract.
4. physical lens, Cinematics tracks, vehicle rigs, probe/capture families.
5. XR stereo/foveation integration, portals, editor tools, replay validation.

