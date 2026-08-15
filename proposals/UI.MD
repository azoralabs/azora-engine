# Azora UI — Reactive ECS Runtime UI

Status: Proposal building on partial implementation
Primary package: `azora-ui`
Primary module: `engine.ui`
Detailed companion: `REACTIVE_ECS_UI.MD`
Navigation companion: `NAVIGATION.MD`

## 1. Decision

Azora UI is a reactive, declarative UI whose retained nodes are ECS entities.
`react func` describes content, composition reconciles nodes by key, systems
measure/layout/input/semantics, and render extraction paints through backend
providers. UI state uses Azora reactive ownership; shared application/game state
uses ECS components and resources. There is no parallel widget-object runtime.

This document is the subsystem suite entry. `REACTIVE_ECS_UI.MD` remains the
full composition/ECS contract and `NAVIGATION.MD` remains the full screen,
dialog, transition, nested navigation, deep-link, and back-stack proposal.

## 2. Current implementation audit

Implemented today:

- ECS node components for keys, parent/order, text, button/action, rect, paint,
  ownership/claim, row/column layout, scroll, tags, size, padding, and related data;
- `Composition` with independent typed stores, begin/claim/commit reconciliation,
  key identity, ownership isolation, child ordering, and disposal;
- row/column arrangement, padding/weight/fill, scrolling data, hit testing,
  group tint/query helpers, and deterministic tests;
- paint extraction to GPU rectangles/text with subtree order and clipping;
- reactive `EcsObserver` and `ReactiveResource<T>` revision adapters;
- `NavBackStack<K>` foundations and DOM compatibility API;
- a `ui-compose` template and extensive proposal/TODO documents.

Important gaps:

- `@compose` and typed `@query` compiler lowering;
- intrinsic measurement, constraints, baseline, grids, wrapping, overlays,
  virtualization, nested scrolling, robust clipping/transforms;
- routed pointer/key events, capture, focus graph, IME/text editing, gestures;
- complete semantics/accessibility tree and platform bridge;
- style/theme system, animations/transitions, images/vector paths, rich text;
- render batching/atlas, retained invalidation, multi-window, inspector/testing;
- full Navigation implementation described in `NAVIGATION.MD`.

## 3. Canonical surface

```azora
react func playerHud(state: HudState&) {
    @compose world {
        column(key: "hud") {
            text("Score ${state.score}")
            button("Pause", action: PauseAction)
        }
    }
}
```

`react func` is the reactive owner spelling. Composition calls are proposal
sugar over the existing begin/claim/update/commit functions. Keys establish
identity only among siblings; list data must provide stable keys.

## 4. Node and phase model

UI roles are component sets, not a `kind` enum. A button is an entity with
button, action, layout, paint, and semantics components. The frame phases are:

1. publish input and observable revisions;
2. run eligible reactive owners;
3. reconcile composition into deferred ECS operations;
4. atomically commit structure;
5. update style and animation;
6. measure bottom-up and lay out top-down;
7. build hit/focus/semantics indexes;
8. route input and emit semantic actions;
9. extract clipped render primitives;
10. paint and run post-commit effects/cleanup.

Composition cannot observe a half-committed tree. Input targets the last complete
layout generation.

## 5. Layout and drawing

The constraint layout model supports min/max dimensions, intrinsic measurement,
padding, alignment, arrangement, weight, aspect, transforms, clipping, z-order,
and baseline. Built-ins include row, column, box/overlay, flow/wrap, grid, scroll,
lazy list/grid, constraint/custom layout, canvas, image, text, and controls.

Measure functions are pure over constraints/content/style. Lazy containers own
visible keyed windows and recycle composition state only by item key. Rendering
batches rectangles, glyphs, images, paths, clips, and layers while preserving
semantic order.

## 6. Input, focus, and accessibility

Input routes capture → target → bubble through the semantic parent tree. Pointer
capture, hover, press, drag, scroll, touch gestures, keyboard actions, and
cancellation have explicit lifecycle. Focus uses traversal order, groups, traps,
restore keys, directional search, and Navigation owner scopes.

Every interactive node publishes role, label, value, state, actions, bounds,
language, heading/live-region data, and relationships. Accessibility bridges are
platform providers. Semantics exist in headless tests and never depend on pixels.

## 7. Styling and animation

Themes provide typed tokens for color, typography, shape, spacing, elevation,
motion, density, and accessibility. Styles resolve from role, state, theme, and
local modifiers; selectors remain bounded and cacheable. UI transitions animate
properties or layout under explicit interruption and reduced-motion policy.
Navigation scene transitions use the same animation primitives.

## 8. State, navigation, and persistence

Reactive dependencies are revision symbols. UI-local retained/saved state is
owned by the reactive owner and keyed composition scope. ECS state is read
through typed queries/resources. Navigation entries own lifecycle, saved state,
focus restoration, transitions, dialogs, and nested displays. Back-stack
implementation uses the corrected current generic form `impl NavBackStack<K>`.

## 9. Performance and diagnostics

Recomposition, measure, layout, semantics, hit index, extraction, and paint have
separate invalidation bits. Stable unchanged subtrees skip work. Large lists must
scale with visible items. The inspector shows owner dependencies, node entities,
keys, components, constraints, measured/layout bounds, focus, routed events,
semantics, draw batches, and invalidation reasons.

## 10. Delivery

1. stabilize existing composition/node/system APIs and compiler-lower `@compose`.
2. constraints/intrinsics, complete layout primitives, clipping/transforms.
3. routed input, focus, text/IME, gestures, semantics/accessibility providers.
4. styling/themes, animation, images/paths/rich text, lazy virtualization.
5. Navigation phases, multi-window, inspector, screenshots/semantics tests,
   render batching and platform parity.

