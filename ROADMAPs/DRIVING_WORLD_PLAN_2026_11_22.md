# Driving world, Studio and content tools — plan of 2026-11-22

The owner's request of 2026-11-22, broken into ordered work packages. Each
package ends in something that runs; the evidence (what was measured, what was
seen) goes under it when it is done. Bugs first, then speed, then the ECS
reshaping, then new modules.

Rules that hold for every package: Azora only (no third-party code), nothing
hardcoded for a demo, ECS where it fits (small components + systems that work
together), every public declaration documented, the owner's surface style
(`then` one-liners, `for i: Int in` ranges, `when`, `.()`/`[]`, contracts,
multi-line arguments without commas). No git.

## A. Bugs the owner hit

- [x] A1 (fix in place, owner to confirm) The car will not drive until the game window loses and regains focus.
  Evidence (input traces in the demo's `.azora-build/input-trace-*.log`): AppKit
  reports the game active with its window key from frame 31 on, yet no key event
  reaches the event pump until the owner switched away and back. The game is an
  unbundled executable fork/exec'd by Studio; such a process is not given the
  keyboard by the window server on its first activation.
- [~] A2 Studio "crashes": its own log shows the peak resident size climbing to
  10-15 GB over a session (about 20 MB/s), and one ASan run stopped in
  `drawFusionGraph` (strcmp on a freed string).
- [x] A3 The car loses balance quickly and rolls over.
- [x] A4 The motorcycle keeps jumping.
- [x] A5 Switching between motorcycle and car leaves the engine sound loud and distorted.
- [x] A6 Roads: parts sink under the landscape; far roads flicker / break up. (owner to confirm in the distance)
- [x] A7 Components panel scrolls only with the pointer at its edge.
- [~] A8 Game memory growth, low FPS, freezes and crashes while driving. (memory flat, startup 10 s -> 2.3 s, 120 FPS full screen; no crash reproduced yet)

## B. Editor

- [x] B1 Editor camera like Unreal's: speed setting, wheel-while-flying changes speed, shown in the viewport.
- [ ] B2 Every editor tool works and is easy to use (landscape, foliage, roads, gizmos).
- [x] B3 Run button works; Play In Editor runs the game inside Studio's viewport.

## C. Performance

- [x] C1 Foliage: grass and fir trees are foliage types, with view distance and density settings; instanced, culled, LOD'd.
- [x] C2 120 FPS full screen with foliage, rain, thunder and lightning. (3456x2234, temporal upscaling, now the default)

## D. ECS reshaping

- [x] D1 Weather as small components that systems combine: Rain, Snow, Wind, Clouds, Fog, Thunder (lightning), Wetness, WeatherAudio...
- [~] D2 Lightning lights the world (flash in the scene light and the sky), thunder heard, wind heard softly. (flash in Fusion, standard and now foliage shading and in the clouds; thunder and wind are mixed - levels for the owner to judge by ear)
- [ ] D3 Roads as components and systems (road, junction, surface, markings, collision), same for other world features.

## E. World

- [x] E1 `azora-world-partition`: a streamed grid of cells (terrain, foliage, roads, props) loaded around the player, bounded memory. (game and Studio editor; a cell crossing still hitches ~150 ms, see open items)
- [x] E2 A landscape ten times larger on the diagonal, populated: road network with junctions, forest, towns, mountains and valleys at the edges. (116 x 108 km generated; apartment blocks are boxes, houses box + gable roof)

## F. Content tools

- [ ] F1 `azora-modeling` (engine): node-based procedural modelling like geometry nodes, evaluated to meshes; Studio modelling tools to build houses and blocks with it, edited like materials.
- [ ] F2 `azora-procedural` (engine): rule graphs that generate roads, buildings and foliage over a region; Studio tools to run and tweak them.

## G. Leftovers from earlier plans

- [ ] G1 Aether Sphere plan 5: Studio panel for components beyond AZON text, snow capture review, 60 s full-screen frame gate.
- [ ] G2 Remove the temporary input diagnostics (`App.diagnose`, `traceInput`, `traceEvents`) once A1 is confirmed.

## Evidence log

### 2026-11-22 (session "driving experience overhaul")

- A1: `tools/build.sh run` now wraps the game in `<name>.app` and starts it with
  `open -W -n -F` (LaunchServices), forwarding every `AZORA_*` variable and the
  project folder (`AZORA_WORKING_DIRECTORY`, entered by `enterWorkingDirectory()`
  in `runSceneGame`); output goes to `.azora-build/run.log` and is printed when
  the game ends. Studio's Cancel also ends the game (`stopGame`). A launch from a
  shell showed the game active with its window key from frame 1. Keys can only
  be confirmed by the owner; the input diagnostics stay until then (G2).
- A2 (memory): measured with `heap`/`leaks` (MallocStackLogging, frame-pointer
  relink). Game and Studio both grew ~12 MB/s idle. Causes and fixes:
  - compiler: a function that may `return ::invalid` (a `Copy` `fin`) was not
    counted as returning a new value, so callers never freed it - World's
    `getParent` (3.6 M Entity copies in 30 s, from `roadLayout` every frame).
    `OwnershipCleanup.freshResults` now counts returned `Copy` places.
  - compiler: `owner.field = new value` never freed the old value
    (`motion.velocity = motion.velocity.add(..)` in the vehicle step). The old
    value is now dropped after the new one is made, unless a local in scope
    may share it. Tests `FieldReplacementOwnershipExecTest` (leaks + ASan),
    full suite 3199 tests, 0 failures.
  - compiler: `return for … else { statements; value }` accepted (the Engine's
    `ecs.az` was written that way and no longer parsed).
  - Engine: foliage keyed its caches with text formatted every frame (text is
    never freed by the LLVM backend: string literals have no header, so heap
    strings are not freed at all - a language-level gap still open). Replaced
    by `engine.io` `Fingerprint`. Material Fusion validated every drawn
    material's path with `substring` every draw; now only new paths, in place.
  - After: the game stays flat at ~248 MB; Studio grows ~0.8 MB/s (was 12).
- A3/A4: new harness `tests/vehicle-stability` (flat ground asserts; with
  `AZORA_STABILITY_SCENE=scene.azscene` from the demo folder it drives the real
  landscape; `AZORA_STABILITY_ROAD=1` follows the roads with an autopilot).
  Bike hop = the rear drive force's pitch moment feeding the suspension's pitch
  mode (0.6 s); fixed with anti-squat 1.0 for the bike (`antiDive`/`antiSquat`
  replace `antiPitch`), analytic anti-wheelie, damped bike suspension. Tyres:
  lateral peak 17.5° -> 8°, longitudinal 17 % -> 10 % (TCS/ABS aim at 10 %);
  steering assist limits the front angle to the grip available at the speed.
  Flat: 0 airborne steps and 0 rollovers in launch/weave/lock for both; roads
  60/90/120 km/h for 60 s: 0 rollovers, 0 off-road for both.
- A5: switching reset the gearbox to first and the wheels to still at speed -
  the engine screamed on its limiter. Now the wheels roll at road speed and the
  gear is the cruising one; the old engine fades out over 0.25 s under the new
  one (`VehicleSound.handOver`). Test `tests/vehicle-switch-sound`.
- Owner request (mid-session): reverse and brake. S/↓ brakes all the way to a
  stop then reverses (it used to coast below 3.6 km/h for seconds first);
  `DriveInput.footBrake` (B) brakes without reversing; Space/Shift handbrake;
  V switches vehicle. 100 -> 0 km/h in 2.3 s, reverse 0.16 s later.
- A7: `arrange` put a Scroll on every Column, so each card in a scrolled list
  was a scroll target that could not scroll. Only scroll containers get it now.
- B1: `EditorCamera.speed` (m/s) + `changeSpeed`; the wheel while flying (RMB)
  changes it, the Scene bar has a speed field, saved in rendering.azon.
- Studio: the viewport bar's Hour field read SkyEnvironment on a physical-sky
  entity (index -1): fixed (`viewportSkyHour`).
- A6: the renderer is reversed-Z (`mat4Perspective`, EditorCamera ortho, depth
  states Greater/GreaterEqual, clear `farDepth` = 0; the sun's shadow map keeps
  Less through `gpu.depthLess`; TAA nearest = max depth; aerial perspective,
  particles and lightning read reversed depth). Precision at 2 km went from ~1 m
  to millimetres. Terrain LOD is road-aware: `gradeRoadTerrain(..., paved)` marks
  samples under the pavement, `buildTerrainMesh(..., paved)` weighs a level's
  rise over them `terrainRoadStrictness` (8) times. Not yet checked in Studio
  from far away by eye.
- A8: CPU profile (sample + frame pointers): `fusionSourceKey` and the std
  serial reader were O(n^2) (`charAt`/`stringLength` per character) - now O(n)
  (`toChars` once; `_SerialReader.chars`); `Fingerprint.addText`, `roadKeyMaterial`
  too. First frame 10.4 s -> 2.3 s. Steady state: ~3 ms CPU, the rest waits for
  the drawable. GPU at 3456x2234: 12 ms native, 6.5 ms temporal -> 120 FPS.
- Judder ("the car one frame back, one forward", worst when FPS dips): the chase
  camera eased once per frame by the frame's dt while the car was drawn between
  fixed physics steps. Camera now steps with the physics (FixedUpdate, after
  `driveVehicle`), with `1 - exp(-rate dt)` easings, and is drawn between its
  last two steps by `frame.interpolation` like the car (template camera.az).
  Physics stays fixed-rate + interpolation (owner's choice, as Unreal):
  `GameConfig.physicsRate` (default 120), `AZORA_PHYSICS_RATE` from Studio
  Preferences "Physics steps per second" (rendering.azon `physicsRate`).
  Measured at 83 FPS (alternating 8.3/16.7 ms frames): car-to-camera distance now
  monotonic (was +-3 cm every frame).

### 2026-11-22 evening (session "partitioning and culling for the generator")

- E2 generator (`azora-procedural`, written by the previous session): 64
  settlements, 678 roads (1668 km), 3000 junctions, 45,736 buildings on
  116 x 108 km; cells of 2 km generated on first use and cached in the
  project's `.azora-build` under a name made of every recipe field and
  `worldGeneratorRevision` (`worldCacheName`), so a changed seed or generator
  never reads stale cells. Junctions now carry the asphalt material (they were
  drawn as black stars).
- E1 in the game: `startWorldPartition` (Startup) loads the cells around the
  Player Start before `spawnDriver`; `keepCourse` (PreUpdate, after
  `streamWorldPartition`) keeps the vehicle's colliders matched to the loaded
  cells (`syncLandscapeColliders`, storage revisions); chase camera far 60 km.
  A partition switched off or deleted unloads what it streamed
  (`unloadPartition`, `despawnStreamed`); a changed recipe is planned again.
  Test `world-partition` covers plan determinism, stream in/out, switch-off and
  recipe change.
- E1 in Studio: the viewport streams around the editor camera
  (`streamWorldAround`, shared with the game system); streamed entities are not
  listed in the Scene Tree, not picked and have no markers; a scene with a World
  Partition opens framed by its active camera. `makeFolders` moved from Studio
  into `engine.io` (the partition creates its cache folder). Screenshot check:
  Valley Overlook shows road, forest and the overview's snowy ranges, 120 FPS.
- Frame time in the generated world (1600x900 window, 3200x1800 px, temporal
  upscaling, GPU timing on): 101.8 ms -> 9.2 ms (GPU 9.6 -> 4.3 ms); in the
  city 107-109 FPS with timing (it waits for the GPU each frame).
  Causes and fixes, from `sample` on frame-pointer builds:
  - ECS: `QueryOf.provide` walked every entity of the world for each query (and
    queries run per fixed step): it now starts from the smallest storage and
    keeps entity order (`queryStorageRows`, heapsort when ids are out of order).
  - Render: `SceneMeshCache` (engine.gpu) - the frame's mesh list, gathered once
    and shared by the Photon Field, the sun's cascade and the camera; per-entity
    slots keep Transform values, local and world matrices across frames and
    remake them only when values change (values compared, so a Transform changed
    in place through a query is seen). Frustum culling (`sphereInClip`) and
    screen-size culling (< 0.75 pt, camera only) per mesh; whole-terrain box
    culling (`boxInClip`) before chunks and foliage; Photon Field casters only
    over the field's pages (static bake still takes everything).
  - `roadLayout` was O(roads x knots) per frame: one pass over the knots, and
    checked once a frame (`RoadRenderCache.checkedFrame/checkedStamp`).
  - Foliage: a landscape farther than its trees reach is neither refreshed nor
    drawn (it re-read every grove's world position per landscape per frame).
  - Road network build (on every cell with roads): 73 -> 40 ms for 244k
    triangles - flat bucket grid (counting sort, no list per bucket),
    `RoadTriangle` corners as nine numbers (one allocation, not four),
    `roadKnotTable` (one pass over knots), junction grid for paint gaps.
- C1 foliage types: `FoliageType` component (engine.foliage; shape Grass|Fir,
  density and height multipliers, view distance + fade share, budget, max
  slope, road margin, tile size). The first enabled type of each shape draws
  it; without one, `defaultFoliageType` keeps what older scenes drew at their
  FoliagePaint distances. Tiles are found by cell (`grassSlots/firSlots`, was a
  linear search per tile per frame), dropped by distance with hysteresis
  (`foliageKeepBeyond` 1.3 x view distance; turning the camera no longer
  remakes them), made at most `foliageTilesPerFrame` (8) a frame, and drawn
  nearest first (heapsort by distance; far tiles no longer eat the budget).
  Trees and grass shrink away over the type's fade share (shader `u.shape`).
  Template + demo scenes have "Grass" and "Firs" type entities; Studio shows the
  card (icons `trees`, `sprout` added to the Lucide atlas). Test `foliage`
  covers defaults, the enabled type winning, and a round trip. Game: 117 FPS at
  the highway start with grass and forests (GPU timing on).
- D1 weather parts (engine.weather.components): `AetherWeather` ("Weather")
  keeps the preset, transition, random walk and the preset wind's bearing;
  `Rain` (intensity, splash distance, splashes), `Snow`, `Fog`, `Thunder`
  (strikes a minute) and `Wetness` (wetness, snow cover, soak and dry seconds)
  are components of their own beside it; `Wind` and `AetherClouds` already
  were. Negative values follow the preset, a part switched off stops; a sky
  with parts and no preset starts from Clear. `previewWeather` combines them in
  order: `advancePreset`, `applyRain/Snow/Fog/Thunder`, `blowWind`,
  `soakGround`, then the storm and the renderer's conditions. Game systems and
  Studio run for any part (`hasWeather`); splash settings come from Rain.
  Older scenes: the old fields stay hidden on Weather and `splitLegacyWeather`
  moves them into the parts (a hand-set wind becomes a `Wind`) and clears them.
  Template and demo scenes converted. Test `weather-parts`. Foliage now darkens
  when wet and is lit by lightning (environment buffer 6). Lucide atlas: the
  missing component icons (cloud, cloud-fog, cloud-rain, cloud-sun, droplets,
  route, snowflake, volume-2, wind, zap) added. Game: Thunderstorm + Thunder +
  Fog parts, 118 FPS.
- B3 Run: two causes it seemed not to work. Studio's background source check
  (`inspect`, about 2 minutes on the demo) marked Studio busy, so the button
  read "Cancel" and Run waited behind it; the check no longer marks Studio busy,
  and Run, Build and Play cancel it quietly (`makeWayForTool`). And `open -W`
  started from Studio failed at once ("Unable to block on applications
  (kqueue() failed: Result too large)"); tools/build.sh now opens the bundle and
  waits for the game's process itself (its errors go to run.log). `runningGame`
  compares symlink-resolved paths on both sides (resolving drops /private), so
  Cancel ends the game in every project folder. Checked: Run from Studio starts
  the game (26 s with the build), it keeps running, Cancel ends it.
- B3 Play In Editor (engine.platform.embed + studio.play): Play builds the game
  and runs it in a process of its own with AZORA_EMBED naming a link file in
  `.azora-build` - a 16 KB header and three frame slots mapped into both
  processes. The game has no window (activation policy prohibited); it draws
  straight into the slot after the last published one (a linear texture over a
  no-copy Metal buffer on the mapping), publishes a frame once the GPU finished
  it, and paces itself on the screen's beat. Studio shows the newest slot in
  the Scene viewport (no copy either), asks for the viewport's pixel size, and
  while the game has focus writes keys held, press counts (no press lost
  between frames), buttons, clicks, wheel and pointer into the header. Play
  gives it focus, a click in the view gives it back, Shift+F1 or a click
  elsewhere frees Studio's keyboard; Pause holds the game (no time passes),
  Stop asks it to end and ends it outright after 1.5 s; a crash ends only the
  game. Studio hotkeys are off while the game has focus (Cmd chords stay).
  Checked: a Python stand-in editor got 121 frames/s, the frame pixels, and W
  held through the header drove the car to 78 km/h; Studio played the demo in
  its viewport at 120 FPS, paused it, stopped it (link marked ended, no process
  left). Studio script shots are now read back from the GPU (they failed with
  the display asleep). Not done: sound follows the game process as before; the
  game's text input is not forwarded.
- Bounded memory: a walk of 78 km across the world in 2 km steps keeps 21
  cells loaded, at most 28,049 entity ids (reused), RSS 175-196 MB.
- Tests: all 12 harness tests pass (`world-driving` now reads
  `dolomites.azscene`; the template's `scene.azscene` is the generated world).
  Pre-existing failures in `tests/run.sh` (not from this session, same with the
  old ECS): `component_ctor` (index -1), `query_filters` (expects `storageOf`
  to register a storage), `query_projection` (old `for [a, b]` syntax). The
  `QueryWith/QueryWithout.provide` ownership (`take base.cursor`) was fixed.

## State at the end of the 2026-11-22 session - start here

Read this file first, then `azora-studio/native/HANDOFF_2026-10-07.md` only if
touching the launcher. Memory notes in `~/.claude/projects/-Users-milkybit-azora/memory/`
(MEMORY.md) hold the tooling (build, harness, leaks/sample profiling).

Toolchain after this session:
- Native compiler rebuilt (`azora-lang/compiler/build/bin/macosArm64/releaseExecutable/azora.kexe`)
  with: return-for block else, fresh Copy-place returns, field-replacement drop.
  Full suite 3199/0 (+ `FieldReplacementOwnershipExecTest`). std serializer
  change (linear reader) was tested with `*Serial*`/`StdlibSelfTest` only - run
  the full suite once at the start of the next session.
- Studio and the demo (`azora-studio/native/build/demo-project`, a copy of the
  `dolomites-drive` template - keep the two in sync, template is canonical)
  are built with everything above.
- Engine tests passing: vehicle-stability (new), vehicle-switch-sound (new),
  sport-vehicles, world-driving, particles, scene-environment, render-stages.

Open bugs / checks:
- A1 keyboard: confirm with the owner, then remove the diagnostics (G2):
  `App.diagnose/traceInput/traceEvents/traceText/tracePath` (platform.az) and
  the `diagnose` lines in the template's driving.az.
- A2 Studio memory: ~0.8 MB/s left (profile with `leaks` on a frame-pointer
  build of studio.ll as for the game; likely per-frame text: the LLVM backend
  never frees heap strings - a language gap: literals have no header, so
  strings are never freed; a real fix is string ownership in the compiler).
  The ASan crash in `drawFusionGraph` (a Double's bits read as `node.kind`)
  did not reproduce in the ASan run of this session (still running at handoff;
  log in the session scratchpad, not kept).
- Foliage types (C1): done in the evening session (see its evidence). Not in
  it: altitude limits, more than one type per shape (stamps and groves name a
  shape, not a type).
- Weather ECS split (D1) and Play In Editor (B3): done in the evening session;
  D2 needs the owner's ear. azora-modeling (F1): not started. World partition + 10x world (E1/E2): done in the evening session (see
  its evidence). azora-procedural (F2) exists as the world generator (recipe ->
  plan -> cells); its Studio tools (run and tweak rule graphs) are not started.

Next session order (owner, 2026-11-22): the 10x world with many roads,
junctions, apartment blocks and houses first; then foliage, weather, PIE.

Open items after the evening session (E1/E2 done):
- Streaming hitch when a cell with roads comes in: city cell parse ~80 ms
  (6.7k entities from 1.3 MB of AZON), road network rebuilt twice (collision
  40 ms + render 40 ms + 26 ms upload). Next step: a road network per cell
  (pieces are already split per cell) or one shared, time-sliced rebuild.
- `sel("...")` selector lookups by name on every Metal call cost ~8% of a frame.
- Studio Scene Tree walks every entity per expanded node (O(N) each).
