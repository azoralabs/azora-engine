# Azora XR — Virtual, Augmented, and Mixed Reality

Status: Proposal
Primary package: `azora-xr`
Primary module: `engine.xr`

## 1. Decision

XR uses OpenXR 1.1 as the primary runtime boundary. Azora owns portable session,
space, view, action, hand, haptic, composition-layer, passthrough, and capability
types; platform/runtime handles remain private provider data. Camera, Input,
GPU, UI, Audio, and World integrate through adapters rather than duplicating XR
versions of their APIs.

## 2. Current engine audit

No XR package, OpenXR loader, stereo view family, predicted display timing, pose
space, tracked controller action, hand tracking, foveation, compositor layer, or
passthrough exists. Input has typed gamepads/touch and Camera/GPU currently assume
one view and one drawable. XR requires the proposed Camera view-family and GPU
frame-graph contracts before rendering; headless capability/session work can be
implemented earlier.

## 3. Public model

```azora
pack XrSessionId {
    fin value: std::Long
}

pack XrSpaceId {
    fin value: std::Long
}

enum XrSessionState {
    Idle
    Ready
    Running
    Visible
    Focused
    Stopping
    Lost
}

enum XrReferenceSpace {
    View
    Local
    Stage
    Unbounded
}

@Resource
pack XrSession {
    fin id: XrSessionId
    var state: XrSessionState
    var predictedDisplayTime: std::Long
    var shouldRender: std::Bool
}

@Component
pack XrTrackedPose {
    fin space: XrSpaceId
    var position: Vec3
    var orientation: Quat
    var linearVelocity: Vec3
    var angularVelocity: Vec3
    var valid: std::Bool
}
```

## 4. Frame loop and spaces

The runtime controls frame cadence: wait frame, begin frame, locate views at the
predicted display time, acquire swapchain images, render view family, release
images, and end frame with composition layers. The engine never substitutes its
desktop frame loop while an XR session runs.

All poses are located between explicit spaces at a time. World maps Stage/Local
space to an absolute origin and handles recenter/origin rebasing without mixing
meters and engine coordinates. Late pose update can patch camera/controller
transforms after simulation, but gameplay uses the fixed-step sampled pose.

## 5. Input, hands, and haptics

OpenXR actions map into `engine.input` action symbols. Suggested bindings are
profiles, not hard-coded controller names. Pose, boolean, scalar, vector, and
haptic actions support subaction paths for left/right or custom users.

Hand tracking publishes joints, radii, validity, confidence, and motion. Gesture
recognition is a higher-level input adapter. Controller models, eye gaze, face/
body tracking, anchors, and scene understanding are capability-gated extensions.

## 6. Rendering

Camera emits stereo/multiview projections with independent view poses and shared
culling where safe. GPU supports swapchain formats, array/multiview rendering,
MSAA, depth layers, visibility masks, late latching, and runtime-specific image
ownership. PostFX effects declare stereo/history compatibility.

Foveation uses fixed, eye-tracked, or provider upscaling tiers behind a capability
record. Dynamic resolution observes GPU deadlines. UI can render as world-space
surfaces or compositor quad/cylinder layers with focus/accessibility semantics.

## 7. AR/MR and composition

Composition layers include projection, quad, cylinder, cube, passthrough, and
depth where supported. Passthrough and environment meshing require explicit
permission and privacy policy. Anchors use stable app symbols mapped to runtime
handles and survive loss only when provider persistence says so.

## 8. Comfort, audio, and networking

Built-in comfort policies include snap/smooth turn, vignette, teleport, seated/
standing calibration, height adjustment, handedness, recenter, boundary warning,
and motion-reduction settings. Spatial Audio uses the head pose/listener and
must not wait on the render thread. Networking replicates avatar/body intent,
not raw provider handles; Replay records normalized action/pose samples by tick.

## 9. Diagnostics and delivery

Debug tooling shows runtime/extensions, session states, spaces, predicted/actual
timing, view frusta, swapchains, actions/bindings, hand joints, foveation regions,
late-update delta, dropped frames, and compositor layers. Counters include CPU/
GPU frame time, prediction error, missed deadlines, resolution, views, action
latency, and tracking validity.

Delivery:

1. OpenXR loader/provider, capabilities, session/state/space/action tests.
2. stereo frame loop, Camera/GPU swapchains, controller poses/actions/haptics.
3. UI layers, spatial Audio, hands, foveation, performance tooling.
4. passthrough, anchors, depth/scene understanding, eye tracking.
5. body/face extensions, multi-user tools, editor simulator, conformance matrix.

Normative reference: [Khronos OpenXR 1.1 registry](https://registry.khronos.org/OpenXR/).
