# Azora Engine — Facade, Profiles, and Distribution Contract

Status: Proposal building on the existing facade
Package: `azora-engine`
Module: `engine`

## 1. Decision

`azora-engine` is an ergonomic import and distribution facade. It re-exports
stable public APIs, selects coherent package profiles, and verifies compatible
versions. It contains no second implementation, runtime registry, hidden
initialization, or dynamic plugin list.

The facade must stop forcing every application to link every native framework
and subsystem. `import engine` selects a configurable default profile;
specialized facades support minimal, 2D, 3D, media, headless, and editor builds.

## 2. Current implementation audit

The package currently contains one file with exposed imports for nearly every
workspace package. This is pleasantly transparent, but it also:

- pulls Objective-C, Metal/Cocoa-facing packages, media, UI, physics, tilemap,
  animation, and App into one dependency closure;
- exposes `engine.objc`, an internal FFI mechanism, as application API;
- cannot express headless or server distributions;
- does not validate that re-exported package versions and feature assumptions
  agree;
- treats compatibility helpers and production APIs identically;
- depends on and re-exports `azora-tracker` today. Tracker is intentionally
  outside the scope of this proposal set and receives no new proposal.

## 3. Facade profiles

```azora
enum EngineProfile {
    Minimal
    TwoD
    ThreeD
    Media
    Headless
    Editor
    Full
}
```

Profiles are manifest/compiler selections, not runtime branches. A package that
is absent from the selected profile contributes no code, native framework, or
startup work.

- **Minimal:** Math, Core, I/O, ECS, and Jobs.
- **TwoD:** Minimal plus Image, Font, Input, Platform, GPU, Render, UI, Tilemap,
  Physics 2D, and Animation 2D.
- **ThreeD:** Minimal plus Platform, GPU, Render, Input, Physics 3D, Animation
  3D, and selected world/render systems.
- **Media:** App, Platform, GPU, Render, UI, Media, Audio, and Video.
- **Headless:** Core, I/O, ECS, Jobs, Physics, Networking, Replay, and App with a
  headless frame driver.
- **Editor:** Full plus authoring, import, diagnostics, and hot-reload providers.

Applications may still import individual packages directly.

## 4. Public versus internal modules

The facade re-exports application contracts, not implementation bridges.
`engine.objc`, backend-specific GPU modules, raw allocator bridges, native codec
objects, and platform ABI helpers stay internal. Their packages remain usable
by engine providers but are not part of `engine` source compatibility.

The facade publishes an API manifest containing package versions, language
edition, enabled profile/capabilities, target backends, and ABI revision. Tools
can explain why a package was included and which dependency introduced it.

## 5. Initialization and providers

Importing the facade has no side effects. App configuration selects available
Platform, GPU, Audio, Media, and I/O providers through compile-time/default
composition. Provider selection errors are explicit at startup. The facade may
offer convenience constructors, but ownership remains in the package that
defines each service.

The facade does not flatten namespaces into conflicting names. Re-export
collisions are compile-time errors with a suggested qualified import. Stable
symbols preserve their defining package identity through re-export.

## 6. Compatibility policy

- Package versions follow one tested engine release matrix.
- Experimental APIs retain their annotation and may change only under the
  documented engine-version policy.
- Deprecated facade paths point to canonical package declarations and do not
  fork implementation.
- Native framework requirements are emitted from selected provider packages,
  not copied into the facade.
- Example templates pin a profile and capability floor so builds are
  reproducible.

## 7. Delivery and acceptance

Delivery:

1. classify every exported module as public, compatibility, provider, or
   internal;
2. remove internal FFI/backend modules from the default public namespace;
3. introduce manifest-level profiles and dependency explanations;
4. add release-matrix validation and headless/media/2D/3D build tests;
5. migrate templates to explicit profiles while preserving `import engine`.

Acceptance requires a minimal program to avoid graphics/media frameworks, a
headless server to run without a window, all profile closures to be cycle-free,
and every public declaration to have exactly one canonical owner. No work in
this proposal changes or redesigns `azora-tracker`.
