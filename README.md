# Azora Engine

A native game engine & app framework written in the **Azora language**.
Engine and application code compile to machine code through the Azora
compiler's LLVM backend and link against a small native platform runtime
(Metal on macOS; a Vulkan backend for Windows/Linux is planned).

```
┌─────────────────────────────────────────────┐
│  your project (src/*.az)                    │
│  engine core (engine/*.az)                  │   Azora language
├─────────────────────────────────────────────┤
│  azora compiler → LLVM IR → clang → binary  │
├─────────────────────────────────────────────┤
│  libazora_runtime  (C ABI, azora_runtime.h) │   Cocoa + Metal / stub
└─────────────────────────────────────────────┘
```

## Layout

| Path                | Contents                                                        |
|---------------------|-----------------------------------------------------------------|
| `engine/`           | Engine core in Azora: math, camera, renderer, input, UI, app    |
| `runtime/`          | Native platform runtime (C ABI in `include/azora_runtime.h`)    |
| `templates/app`     | "App" project template — window + two buttons                   |
| `templates/game`    | "Game" project template — 3D cube scene with WASD fly camera    |
| `tools/build.sh`    | Compiles+links an engine project to a native executable         |
| `tools/package.sh`  | Assembles the installable library bundle (`dist/*.azlib`)       |
| `library.json`      | Library manifest read by Azora Studio (id, version, templates)  |

## Engine modules (Azora language)

- `az_bridge.az` — `bridge C` declarations of the native runtime ABI
- `az_math.az` — `Vec3`, `Mat4` (row-major), perspective/rotation/translation
- `az_render.az` — mesh handles, `Camera` (fly camera with WASD/QE/arrows)
- `az_input.az` — key/mouse state, `KEY_*` constants
- `az_ui.az` — immediate-mode UI: rects, text, buttons
- `az_app.az` — app lifecycle: `appInit / appFrame / appPresent / appShutdown`

## Building the library bundle

```sh
tools/package.sh                # → dist/azora-engine-<version>/ and .azlib zip
```

The bundle embeds the Azora compiler CLI (built from the sibling
`azora-lang` repository, override with `--azora-lang <path>`), the compiled
native runtime, the engine sources and both project templates.

## Using with Azora Studio

Install the bundle from **Project Browser → Libraries** (or copy it to
`~/.azora/libraries/<id>/<version>`). The library contributes the **App**
and **Game** project templates to the create-project dialog; created
projects build & run through the Studio's Run button (`run.sh` →
`tools/build.sh`).

Projects created from the templates are plain directories:

```
MyGame/
  src/main.az      # your code (engine sources come from the library)
  run.sh           # sh run.sh [build|run]
  .azora-build/    # build output (LLVM IR + native executable)
```

## Requirements

- macOS with the Xcode Command Line Tools (`clang`)
- A JDK 17+ (runs the bundled Azora compiler)

## Roadmap

- Vulkan runtime backend (Windows/Linux)
- Scene format (`.azn` Azora Nodes) editable inside Azora Studio
- Textures, materials, custom meshes, audio
