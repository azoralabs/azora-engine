# Azora Platform — Desktop, Mobile, Console, Web, and Host Integration

Status: Proposal extracting a portable platform layer from a working macOS host
Package: `azora-platform`
Module: `engine.platform`

## 1. Decision

`azora-platform` owns operating-system windows, displays, event pumping,
application lifecycle, clipboard, cursor, text/IME input events, drag/drop,
file dialogs, power/focus state, timing primitives, and native surface targets.
Input owns device state and action mapping. GPU owns devices and presentation.
App owns the frame loop.

Platform must not contain draw calls, GPU frame encoding, game camera logic, or
an application host pack that merges every service.

## 2. Current implementation audit

The macOS implementation successfully creates a Cocoa application/window,
attaches a Metal layer, pumps keyboard and mouse events, polls GameController,
tracks frame time, exposes window bounds and pointer state, starts/ends Metal
frames, manages an autorelease pool, and supports quit/shutdown.

Gaps and coupling:

- the package is macOS-only and the manifest links only Cocoa despite runtime
  use of GameController/QuartzCore through dependencies;
- `App` owns Platform, GPU, raw input, clock, clear color, and frame lifecycle;
- Platform depends directly on GPU and contains render-pass creation;
- raw input uses fixed byte offsets and only a small key/mouse vocabulary;
- no text input, IME, key location, wheel, pointer IDs, touch, pen, controller
  hotplug, haptics, clipboard, cursor, drag/drop, dialogs, monitor, fullscreen,
  HDR, accessibility, or multiple windows;
- close/focus/resize/scale events are inferred or polled rather than published;
- native handles and Objective-C details leak through public packs.

## 3. Public model

```azora
pack WindowId {
    fin value: std::Long
    fin generation: std::Int
}

pack DisplayId {
    fin value: std::Long
    fin generation: std::Int
}

pack SurfaceTargetId {
    fin value: std::Long
    fin generation: std::Int
}

enum WindowMode {
    Windowed
    Borderless
    ExclusiveFullscreen
}

enum PlatformLifecycle {
    Starting
    Active
    Suspended
    Background
    Terminating
}

variant enum PlatformEvent {
    WindowCreated(window: WindowId)
    WindowClosed(window: WindowId)
    WindowResized(window: WindowId, width: std::Int, height: std::Int)
    ScaleChanged(window: WindowId, scale: std::Double)
    FocusChanged(window: WindowId, focused: std::Bool)
    Input(event: RawInputEvent)
    Text(event: TextInputEvent)
    Lifecycle(state: PlatformLifecycle)
}

error PlatformFault {
    ProviderUnavailable
    WindowCreationFailed
    InvalidWindow
    UnsupportedOperation
    PermissionDenied
    NativeFailure
}
```

Native objects stay in provider tables. IDs are process-local and never stored
in save/network/replay data.

## 4. Provider architecture

`PlatformProvider` implementations cover macOS, Windows, Linux/Wayland/X11,
Android, iOS, WebAssembly/browser, consoles through separately installed
provider packages, and headless. Providers advertise windows or screens,
displays, clipboard, IME, touch, pen, gamepad, haptics, dialogs, accessibility,
HDR, exclusive fullscreen, safe areas, orientation, virtual keyboard, lifecycle,
thermal/power state, and event-wait capabilities.

App selects one provider and drives `poll` or `wait` according to frame policy.
Embedded builds can inject events. Mobile providers model foreground/background,
surface loss, orientation, safe areas, permissions, and low-memory/thermal
events without pretending every target has desktop windows. Console providers
implement the public contract without exposing proprietary SDK objects. Headless
emits lifecycle/time events without linking a window stack.

## 5. Windows, displays, and surfaces

Window descriptors cover logical size, minimum/maximum size, title, mode,
decorations, transparency, resizability, visibility, position policy, display,
scale policy, and presentation preferences. Logical points and physical pixels
are explicit and conversion is per window.

Platform exposes a backend-neutral native surface target. GPU consumes that
target to create a presentation surface; Platform never imports GPU. Resize,
occlusion, color/HDR, display migration, and scale changes are events.

Multi-window operations are command-based and applied on the required OS
thread. Closing one window is distinct from application exit.

## 6. Input and text boundary

Platform translates native events into stable physical key, logical key, text,
composition, pointer, wheel, touch, pen, controller, and device-change events.
Input owns held/pressed/released state, action maps, dead zones, remapping, and
haptics policy.

Text input carries composition range, selection, replacement range, committed
text, locale, and candidate-window geometry. Key presses are never treated as a
substitute for text. Clipboard and drag/drop data use I/O byte/source leases.

## 7. Timing, lifecycle, and power

Platform supplies a monotonic clock and optional display timing. App converts
these into engine clock domains. Suspend/background events pause presentation,
flush input edges, notify media/network policy, and preserve deterministic fixed
time. Event waiting can sleep until the next timer/event rather than busy-loop.

## 8. Diagnostics and delivery

Profiler records event latency/counts, pump/wait time, window operations,
display/scale changes, IME, controller hotplug, clipboard/drop bytes, focus,
sleep/wake, and native failures without capturing private text by default.

Delivery:

1. extract GPU frame work and App lifetime from Platform;
2. add typed IDs, events, window commands, scale/resize/focus/close handling;
3. route raw/text/controller events into Input and add multi-window support;
4. create Web/headless and Windows/Linux providers;
5. add Android/iOS lifecycle, screen, touch/IME, safe-area, permission, thermal,
   and device conformance;
6. add the access-controlled console provider contract plus clipboard, haptics,
   dialogs, HDR, and accessibility coverage by capability.

Acceptance requires Platform to compile without GPU, multi-window event tests,
correct logical/physical/safe-area conversions, Unicode IME fixtures,
suspend/background/surface-loss recovery, mobile and headless conformance,
console-provider contract tests, and no native object in public state.
