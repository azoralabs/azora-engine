# Azora Input — Actions, Remapping, Touch, and Haptics

Status: Proposal building on partial implementation
Primary package: `azora-input`
Primary module: `engine.input`

## 1. Decision

Preserve the current typed raw-device layer and add an action layer above it.
Gameplay and UI bind stable action symbols to composite controls, contexts,
processors, interactions, and devices. Raw input remains available for tools and
specialized code, but templates and engine systems consume actions by default.

Input owns the mechanisms for remapping and alternate control. Accessibility
owns user-facing accessibility profiles, persisted preferences, audits, and
cross-system policy. Platform owns native device/event and assistive-control
bridges.

## 2. Current implementation audit

Implemented today:

- stable integer constants and typed enums for keyboard keys, mouse buttons,
  pointer kinds, touch phases, gamepad buttons, and axes;
- `ButtonInput<KeyCode>` with held, pressed, and released semantics;
- platform input snapshots covering keyboard, mouse, pointer, wheel, text,
  touch, pen, and GameController-backed pads;
- mappings are tested for total/stable host values.

Current gaps:

- generic `ButtonInput<T>` behavior for every typed control;
- action maps, contexts, chords, sequences, processors, interactions, rebinding;
- player/device pairing, hotplug events, controller profiles, dead zones;
- IME composition, clipboard policy, accessibility alternatives;
- haptic clips/mixing and platform capability records;
- deterministic input frame records for Networking/Replay.

## 3. Raw event model

Platform collects timestamped device events, normalizes coordinates/axes, and
commits one immutable `InputFrame` at the engine frame boundary. Held state
persists; edge state, pointer delta, wheel, text, and touch transitions belong to
one frame. Fixed-step simulation consumes a sampled/quantized input command
derived from these frames.

```azora
pack InputDeviceId {
    fin value: std::Long
}

pack InputFrameId {
    fin value: std::Long
}

variant enum InputEvent {
    KeyChanged(KeyEvent)
    PointerMoved(PointerEvent)
    TouchChanged(TouchEvent)
    GamepadChanged(GamepadEvent)
    TextEntered(TextEvent)
    DeviceChanged(DeviceEvent)
}
```

## 4. Action model

```azora
pack InputActionId {
    fin value: std::Long
}

enum ActionValueKind {
    Button
    Axis1
    Axis2
    Axis3
}

enum ActionPhase {
    Waiting
    Started
    Performed
    Cancelled
}

pack InputAction {
    fin id: InputActionId
    fin kind: ActionValueKind
    fin bindings: std::Array<InputBinding>
}

@Resource
pack InputActions {
    var activeContexts: std::Array<InputContextId>
    var frame: InputFrameId
}
```

Bindings support controls, composites (WASD/2D stick), modifiers/chords,
sequences, tap/hold/multitap, dead zone, normalize, scale, invert, curve, and
device/player filters. Context priority and consume policy resolve conflicts.
Action IDs are symbols; duplicate display names are safe.

## 5. Remapping and accessibility

Rebinding listens for candidate controls under device and exclusion policy,
detects conflicts, then writes a user override separate from shipped assets.
Overrides are versioned by action/binding symbols and survive asset reordering.

The action layer supports alternate bindings, sticky modifiers, hold-to-toggle,
timing scaling, one-handed layouts, haptic strength/policy, and input-method
hints. `engine.accessibility` supplies profiles and preferences over these
mechanisms. UI navigation and gameplay contexts coordinate ownership so a dialog
can consume Confirm/Back without disabling unrelated devices globally.

## 6. Text, touch, and pointers

Text input separates physical keys, Unicode text commits, and IME composition.
Pointer capture, confinement, relative mode, pressure, tilt, hover, and primary
pointer selection are explicit. Gesture recognition (tap, drag, pinch, rotate,
long press) is an adapter over touch/pointer streams and supports cancellation.

## 7. Haptics

Haptics uses capability-negotiated channels and clips. Effects have amplitude,
frequency where available, duration, envelope, priority, and player/device
route. A bounded mixer combines effects and stops them on disconnect/focus loss.
Gameplay emits semantic haptic events; platform providers translate them.

## 8. Networking, replay, and diagnostics

Networking serializes quantized action commands at simulation ticks, not raw OS
events. Replay can store raw normalized frames for UI reproduction and action
commands for deterministic gameplay. Every command records map revision and
player identity.

Debug tooling shows devices, raw controls, action phases/values, active contexts,
binding resolution, consumption, processors, latency, and haptic routes.
Counters include events, action evaluations, device changes, queue drops, and
input-to-simulation latency.

## 9. Delivery

1. complete typed raw snapshots, device IDs/hotplug, immutable frame API.
2. action maps, contexts, composites, processors, interactions, ECS resource.
3. rebinding/persistence, player pairing, templates, UI focus and Accessibility
   profile integration.
4. IME/clipboard, gestures, haptic clips/mixer, platform providers.
5. networking/replay commands, accessibility suite, latency tooling.
