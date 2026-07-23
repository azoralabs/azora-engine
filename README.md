# Azora Engine

A native game engine & app framework written in the **Azora language** —
including its platform layer and Metal renderer. Engine and application code
compile to machine code through the Azora compiler's LLVM backend; browser
projects run task-owned loops through Engine WASM and use Azora-provided WebGL shaders. The OS is
driven directly from Azora via the Objective-C runtime and C framework APIs.

The engine is a **Bevy-style workspace of packages** (crates). Every subsystem is
its own package under `packages/`, each with a `package.azon` manifest declaring
its dependencies and the native frameworks it links. The `azora-engine` facade
re-exports them all, so a game just writes `import engine`.

```
┌──────────────────────────────────────────────────┐
│  your project (src/*.az)     import engine        │
│                                                   │
│  packages/azora-engine  (facade + DefaultPlugins) │   Azora language
│  packages/azora-app     Plugin / GameSystem / App │   (all of it)
│    ├─ azora-core/ecs/jobs   ECS, jobs, decorators │
│    ├─ azora-platform/       Cocoa window + events │
│    ├─ azora-gpu/            Metal pipelines, text │
│    ├─ azora-objc/           objc_msgSend FFI      │
│    └─ azora-math/ui/render/shaders/input/…        │
├──────────────────────────────────────────────────┤
│  azpm resolves .azon → azora compiler → LLVM IR   │
│                       → clang → native binary     │
├──────────────────────────────────────────────────┤
│  libazora_runtime — ~150-line C ABI shim only:    │
│  msgSend trampolines (double/struct shapes),      │
│  raw memory peek/poke, dlsym                       │
└──────────────────────────────────────────────────┘
```

There is **no platform logic in native code**: windows, event pumping, Metal
device/pipelines/draw calls and CoreText text rasterization are Azora source
(`bridge C` + `objc_msgSend`). The only C file (`runtime/src/ffi/az_ffi.c`)
exists because arm64 requires exact C function types for objc_msgSend
signatures involving doubles or by-value structs. Vulkan (a plain C API) will
bind the same way for Windows/Linux.

## Layout

| Path                       | Contents                                                    |
|----------------------------|-------------------------------------------------------------|
| `workspace.azon`           | Package workspace manifest (members, version)               |
| `packages/azora-engine/`   | Facade: re-exports every package + `DefaultPlugins`         |
| `packages/azora-app/`      | `Plugin` / `PluginGroup` / `GameSystem` specs + the `Engine` builder |
| `packages/azora-platform/` | Cocoa window, event pump, input, frame lifecycle            |
| `packages/azora-gpu/`      | Metal device/pipelines/draw + CoreText text                 |
| `packages/azora-render/`   | Cameras, meshes, materials, render queues (+ WebGL)         |
| `packages/azora-{ui,input,audio,physics,ecs,jobs}/` | UI/text, input, audio, physics, ECS, jobs |
| `packages/azora-{objc,math,shaders,core}/` | objc FFI, math, shader sources, ECS/decorator core |
| `packages/<pkg>/package.azon` | Per-package manifest: dependencies + native frameworks   |
| `runtime/`                 | FFI plumbing shim (`src/ffi/az_ffi.c`)                       |
| `templates/*`              | Project templates (app, game, tetris, runner, …)            |
| `tools/azpm.py`            | Package resolver: reads `.azon`, computes the dep closure + link set |
| `tools/azon.py`            | AZON (Azora Object Notation) reader used by azpm            |
| `tools/build.sh`           | Compiles+links a project to a native executable (via azpm)  |
| `tools/package.sh`         | Assembles the installable library bundle (`dist/*.azlib`)   |
| `library.json`             | Library manifest read by Azora Studio (templates + variants)|

## Application shape (Bevy-style)

`import engine` pulls in the whole engine. A game builds an `Engine`, adds the
standard `defaultPlugins()` (window + input + render + UI) plus its own `Plugin`,
and runs. A `Plugin.build` registers `GameSystem`s that run each frame; systems
dispatch dynamically through Azora `spec` trait objects.

```azora
import engine

// A system carries its own state; run() is called every frame.
pack Scene {
    var cam: Camera
    var cube: Mesh
    var ready: Bool
}
impl GameSystem for Scene {
    func run(app: mut ref App) {
        mut ref self ->
        if !self.ready { self.cube = app.meshCube(1.0); self.ready = true }
        self.cam.update(app, app.deltaTime(), 5.0, 1.8)
        app.applyCamera(self.cam)
        app.drawMesh(self.cube, mat4RotationY(app.timeNow()), 0.9, 0.5, 0.2)
    }
}

pack GamePlugin
impl Plugin for GamePlugin {
    func name(): String { ref self -> return "GamePlugin" }
    func build(engine: mut ref Engine) {
        mut ref self ->
        engine.addUpdateSystem(Scene(cameraDefault(), Mesh(0L, 0), false) as GameSystem)
    }
}

func main() {
    var e = engine("My Game", 1280, 720)
    e.addPlugins(defaultPlugins())
    e.addPlugin(GamePlugin() as Plugin)
    e.run()
}
```

## Packages & `.azon`

Each package is a crate with a manifest. `azpm` reads a project's
`import engine[.x]` statements, resolves the transitive package closure from the
manifests, stages exactly those sources, and unions the native frameworks/libs to
link — replacing any hard-coded dependency graph.

```azon
// packages/azora-render/package.azon
package: {
    name: "azora-render"
    version: "0.1.0"
    module: "engine.render"
    kind: "core"
}
dependencies: {
    azora-ui:      { path: "../azora-ui" }
    azora-math:    { path: "../azora-math" }
    azora-shaders: { path: "../azora-shaders" }
}
```

```sh
tools/azpm.py graph                 # print the package dependency graph
tools/azpm.py resolve templates/game   # packages to stage + frameworks to link
```

A simulation-only project that imports only `engine.ecs` links no renderer;
`import engine` (via the facade) pulls in everything.

## Building the library bundle

```sh
tools/package.sh        # → dist/azora-engine-<version>/ and .azlib zip
```

The bundle embeds the Azora compiler CLI (built from the sibling `azora-lang`
repository, override with `--azora-lang <path>`), the FFI shim, the engine
packages + `workspace.azon`, the `azpm` resolver and all project templates.

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
