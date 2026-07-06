# Azora Engine

A native game engine & app framework written in the **Azora language** —
including its platform layer and Metal renderer. Engine and application code
compile to machine code through the Azora compiler's LLVM backend; the OS is
driven directly from Azora via the Objective-C runtime and C framework APIs.

```
┌──────────────────────────────────────────────────┐
│  your project (src/*.az)                         │
│  engine core (engine/*.az)                       │   Azora language
│   ├─ az_platform.az   Cocoa window, events, input│   (all of it)
│   ├─ az_gpu.az        Metal pipelines, CoreText  │
│   ├─ az_objc.az       objc_msgSend FFI bridge    │
│   └─ az_math/ui/render/shaders/input             │
├──────────────────────────────────────────────────┤
│  azora compiler → LLVM IR → clang → binary       │
├──────────────────────────────────────────────────┤
│  libazora_runtime — ~150-line C ABI shim only:   │
│  msgSend trampolines (double/struct shapes),     │
│  raw memory peek/poke, dlsym                     │
└──────────────────────────────────────────────────┘
```

There is **no platform logic in native code**: windows, event pumping, Metal
device/pipelines/draw calls and CoreText text rasterization are Azora source
(`bridge C` + `objc_msgSend`). The only C file (`runtime/src/ffi/az_ffi.c`)
exists because arm64 requires exact C function types for objc_msgSend
signatures involving doubles or by-value structs. Vulkan (a plain C API) will
bind the same way for Windows/Linux.

## Layout

| Path                | Contents                                                         |
|---------------------|------------------------------------------------------------------|
| `engine/`           | Engine in Azora: platform, GPU, math, camera, input, UI, shaders |
| `runtime/`          | FFI plumbing shim (`src/ffi/az_ffi.c`)                           |
| `templates/app`     | "App" template — window + two buttons                            |
| `templates/game`    | "Game · Empty" — cube scene with WASD fly camera                 |
| `templates/game-tetris` | "Game · Tetris (2D)" — complete falling-blocks game          |
| `templates/game-runner` | "Game · Temple Run (3D)" — three-lane endless runner         |
| `templates/game-shapes` | "Game · Shape Examples" — guided API tour with colored shapes|
| `tools/build.sh`    | Compiles+links an engine project to a native executable          |
| `tools/package.sh`  | Assembles the installable library bundle (`dist/*.azlib`)        |
| `library.json`      | Library manifest read by Azora Studio (templates + variants)     |

## Application shape

```azora
func main() {
    var app = appInit("My Game", 1280, 720)
    if !app.ok {
        return
    }
    fin cube = app.meshCube(1.0)
    var cam = cameraDefault()

    while app.frame() {
        cam.update(app, app.deltaTime(), 5.0, 1.8)
        app.applyCamera(cam)
        app.drawMesh(cube, mat4RotationY(app.timeNow()), 0.9, 0.5, 0.2)
        if app.button("Quit", 16.0, 16.0, 90.0, 32.0) {
            app.quit()
        }
        app.present()
    }
    app.shutdown()
}
```

## Building the library bundle

```sh
tools/package.sh        # → dist/azora-engine-<version>/ and .azlib zip
```

The bundle embeds the Azora compiler CLI (built from the sibling `azora-lang`
repository, override with `--azora-lang <path>`), the FFI shim, the engine
sources and all project templates.

## Using with Azora Studio

Install the bundle from **Project Browser → Libraries** (or copy it to
`~/.azora/libraries/<id>/<version>`). The library contributes the **App** and
**Game** templates to the create-project dialog; Game offers a dropdown of
starting points (Tetris, Temple Run, Shape Examples, Empty). Created projects
build & run through the Studio's Run/Play button (`run.sh` → `tools/build.sh`).

## Requirements

- macOS with the Xcode Command Line Tools (`clang`)
- A JDK 17+ (runs the bundled Azora compiler)

## Roadmap

- Vulkan platform layer for Windows/Linux (C API — binds directly from Azora)
- Scene format (`.azn` Azora Nodes) editable inside Azora Studio
- Text texture caching, textures/materials, custom meshes, audio
