# Azora Accessibility — Inclusive Presentation and Interaction

Status: Proposal
Primary package: `azora-accessibility`
Primary module: `engine.accessibility`

## 1. Decision

Accessibility is a first-class, cross-engine capability, not a collection of UI
toggles. `engine.accessibility` owns user preferences, capability discovery,
semantic accessibility contracts, presets, audits, and coordination. The
subsystem that presents or receives an experience remains responsible for
implementing it: UI exposes semantics, Input remaps controls, Video presents
captions, Audio exposes non-speech cues and description routes, Camera/PostFX
reduce motion, and Platform bridges native assistive technology.

The system follows the useful principles of perceivable, operable,
understandable, and robust design, but the engine does not claim standards or
legal conformance merely because the APIs exist. A shipped product still needs
content review, platform testing, and disabled-player testing.

## 2. Current engine audit

Input already proposes alternate bindings, sticky modifiers, timing scaling,
one-handed layouts, and haptic policy. UI proposes semantic nodes and focus.
Video delegates subtitle styling to UI. Platform lists accessibility as a
provider capability. These are disconnected intentions today: there is no
shared settings resource, semantic bridge, caption contract, color-vision
tooling, accessibility event bus, persistence schema, or automated audit.

## 3. Ownership boundaries

- Accessibility owns preferences, profiles, semantic vocabulary, audits, and
  orchestration.
- UI owns the semantic tree, focus order, labels, roles, values, actions, live
  regions, text scaling, and accessible layout.
- Input owns device state, action mappings, rebinding, interactions, and haptics.
- Media/Video owns timed cue selection; UI owns subtitle/caption rendering.
- Audio owns buses, speech/dialogue routing, description, mono/downmix behavior,
  and semantic sound-event adapters.
- Material/PostFX owns color transforms; content authors own redundant non-color
  cues. A global filter is never treated as a complete color-vision solution.
- Platform owns screen-reader, switch-control, OS preference, and native API
  adapters without exposing native objects.

The primary package contains only neutral settings, semantic vocabulary,
capabilities, and events over Core symbols. UI, Input, Media, PostFX, Audio, and
Platform provide adapter modules that depend on this core; the core never imports
those systems. Authoring/audit UI can live in an optional
`azora-accessibility-tools` package.

## 4. Public model

```azora
enum AccessibilityNeed {
    Vision
    Hearing
    Motor
    Cognitive
    Speech
    Motion
}

enum ColorVisionMode {
    Unmodified
    Protanopia
    Deuteranopia
    Tritanopia
    Achromatopsia
    Custom
}

@Resource
pack AccessibilitySettings {
    var enabled: std::Bool
    var textScale: std::Double
    var interfaceScale: std::Double
    var captionScale: std::Double
    var highContrast: std::Bool
    var colorVisionMode: ColorVisionMode
    var reduceMotion: std::Bool
    var reduceFlashing: std::Bool
    var monoAudio: std::Bool
    var screenReader: std::Bool
    var inputTimingScale: std::Double
}

pack AccessibilityCapabilities {
    fin nativeScreenReader: std::Bool
    fin switchControl: std::Bool
    fin spokenAnnouncements: std::Bool
    fin systemTextScale: std::Bool
    fin reduceMotionPreference: std::Bool
    fin highContrastPreference: std::Bool
}

pack SemanticNodeId {
    fin value: std::Long
    fin generation: std::Int
}

enum LiveUrgency {
    Polite
    Assertive
}

variant enum AccessibilityEvent {
    SettingsChanged(revision: std::Long)
    FocusRequested(node: SemanticNodeId)
    AnnouncementRequested(message: ContentSymbol, urgency: LiveUrgency)
    CapabilityChanged(capabilities: AccessibilityCapabilities)
}
```

Settings use user-visible values and stable symbols. Native accessibility
objects, transient UI indices, localized display strings, and device names are
never persistent identity.

## 5. Semantic UI and screen readers

Every meaningful UI node exposes a stable semantic node ID, role, localized
name, description, value, state, available actions, bounds, reading order, and
relationships. Decorative nodes are explicitly hidden. Virtualized lists expose
logical collection position rather than only the currently rendered children.

UI publishes an immutable semantic snapshot after layout. Platform maps its
roles and actions to VoiceOver, UI Automation, AT-SPI, Android accessibility,
browser accessibility trees, or a console provider. Native action callbacks are
converted into UI commands at a safe frame boundary. Focus changes,
announcements, and live regions are bounded and coalesced so rapidly changing
HUD values do not overwhelm a screen reader.

The role/state/action model should map cleanly to established platform APIs and
WAI-ARIA concepts, but it remains engine-native so non-Web targets are not forced
to emulate a DOM.

## 6. Subtitles, captions, and audio description

Timed text distinguishes dialogue subtitles, captions, speaker labels, sound
effect cues, music cues, lyrics where licensed, and audio-description metadata.
Users can configure size, font family class, foreground/background, opacity,
outline, line width, placement-safe region, speaker labels, and cue density.

Video/Media selects cues by media time and passes semantic cue values to UI.
`engine.videoplayer` composes Video and UI for the complete player. Accessibility
does not make Video depend on UI. In-game dialogue and cinematics use the same
cue contract so settings apply consistently.

Audio-description tracks, dialogue boost, dynamic-range presets, mono audio,
channel-safe downmix, and independent speech/music/effects buses remain Audio
features selected by Accessibility policy.

## 7. Color vision, contrast, flashing, and motion

Authoring tools simulate common color-vision conditions and audit contrast,
small text, focus visibility, transparent overlays, and state communicated only
by hue. Gameplay markers, teams, rarity, damage, road/navigation guidance, and
puzzle state must support shape, pattern, icon, label, position, or sound as a
second channel.

Optional color correction is applied as a calibrated PostFX stage after tone
mapping policy is known. UI theme tokens can choose authored accessible palettes.
Flashing checks measure frequency, affected screen area, luminance change, and
red transitions. Reduced-motion mode replaces or scales camera shake, parallax,
rapid zoom, motion blur, screen-space streaks, looping UI motion, and forced
camera moves while retaining essential state feedback.

## 8. Input accessibility

Input owns full remapping across keyboard, mouse, touch, controller, and assistive
switches. Accessibility contributes presets and preferences for sticky
modifiers, toggle/hold alternatives, repeated-press timing, simultaneous-input
alternatives, one-handed layouts, aim assistance policy, dwell activation,
gesture alternatives, haptic strength, and input-method prompts.

Every gameplay action must be bindable by action symbol unless a platform
security rule forbids it. A UI drag operation has an action-based alternative.
Menus never require pointer hover, precise motion, or color recognition.

## 9. Cognitive and comprehension support

The engine provides consistent focus behavior, pause-safe reading, adjustable
text reveal, tutorial replay, objective/history surfaces, icon-plus-text modes,
plain-language content variants, navigation assistance, and warning durations.
These are capabilities rather than one global “easy” switch. Presets initialize
settings but users can edit every choice independently.

## 10. Persistence, privacy, and profiles

Accessibility settings are stored in the settings/profile domain through Save,
not inside world save games. They load before the first interactive screen and
can follow a signed-in profile. OS preferences can seed settings but never
silently overwrite explicit user choices.

The engine does not record screen-reader use, disability inferences, spoken
content, or accessibility choices in analytics by default. Crash reports and
profiler captures redact announced text and input content.

## 11. Authoring, diagnostics, and testing

The accessibility inspector shows semantic hierarchy, reading/focus order,
names/roles/values, hidden nodes, available actions, touch target size, contrast,
caption safe areas, color simulation, flashing risk, unbound actions, and
platform bridge state. Automated checks find missing labels, duplicate semantic
IDs, focus traps, unreachable controls, action-only-by-color, clipped scaled
text, and captions outside safe regions.

Required tests include keyboard/controller/touch-only traversal, screen-reader
action round trips, 200% text and interface scaling, remapping conflicts,
high-contrast and color-simulation snapshots, subtitle overlap, reduced-motion
substitution, focus restoration after dialogs, and native-provider conformance.
Automated checks supplement, never replace, testing with disabled users.

## 12. Delivery

1. settings/profile schema, capability record, UI semantic snapshot, and audit
   foundation;
2. Platform screen-reader adapters, focus/actions/live regions, and scalable UI;
3. complete Input remapping/presets and pointer/gesture alternatives;
4. subtitle/caption styling, audio-description routing, mono/dialogue controls;
5. color/contrast/flashing/motion tools, CI audits, and full platform matrix.

References: [WCAG 2.2](https://www.w3.org/TR/WCAG22/),
[WAI-ARIA 1.2](https://www.w3.org/TR/wai-aria/), and
[Android accessibility principles](https://developer.android.com/guide/topics/ui/accessibility/principles).
