# Water, roads and vegetation — plan of 2026-11-24

The owner's request of 2026-11-24: continue `azora-water` (more components,
real ocean simulation, rivers through mountains); make the road system stable
with realistic intersections, lane editing and professional tools (fences,
curbs, sidewalks and crossings, signs, working traffic lights), in the editor
too; and a new `azora-vegetation` (trees, firs, bushes, grass generated from
blueprints, with snow that settles, autumn leaves that turn and fall, and a
response to the scene `Wind` and to local wind zones). Tests live in a new
project, `~/Documents/Azora/Test`, whose files have specific names (no
`main.az`). Everything decoupled, as small ECS components and systems.

Rules for every package (same as the 2026-11-22 plan): Azora only, nothing
hardcoded for a demo, every public declaration documented, the owner's surface
style, no git. Nothing frame-rate dependent: simulations take time from the
fixed step or from absolute time, easings `1 - exp(-k dt)`.

## Owner's architecture rule (2026-11-24, mid-session)

The whole engine works as systems over components: every feature is small
components plus `@System` functions that query them - simulation and
drawing alike - in the feature's own package (weather in azora-weather,
water in azora-water...), never imperative calls from `drawScene` or Studio.
A package's systems ask for what they need by parameter type (`World`,
`Time`, `App`, `SceneView`, `AudioOutput`, `EditorCamera`,
`ParticlePipelines`, queries with `with`/`without`); engine.game provides
them (`fromGame`), so no package depends on the game. Studio's viewport runs
the same systems on the edited scene: those marked `@System(editor: true)`.

## Systems everywhere (S)

- [x] S1 Phases `RenderShadow` (sun cascade) and `RenderOpaque` (with the opaque
  scene); `@System(editor:)`; render.scene's `drawScene` split into
  `prepareSceneDraw`, `beginSunCascade`/`drawSceneCasters`/`endSunCascade`,
  `drawSceneOpaque`, so the game and Studio dispatch systems between them.
  The `@SceneDraw` hook of F2 is gone (replaced by these phases).
- [x] S2 engine.game: system parameter providers, `dispatchEditor`.
- [x] S3 Weather as systems in azora-weather: startWeather/Precipitation/Storm/
  WeatherSound (PreUpdate), easeRain/Snow/Dust, chargeThunder, carryWind,
  soakWeatherGround, hazeWeatherAir, strikeLightning (PostUpdate, editor),
  precipitation/bolts (render) and thunder/weather sound (Audio) moved out of
  engine.game; `previewWeather` removed; Studio runs them.
- Owner (mid-session, again): "update every engine package to @System - many
  are still on the old model: atmosphere, foliage, landscape, material-fusion,
  procedural, vehicles, world-partition etc." Each package below: its per-frame
  work as systems over its components in its own package, `editor: true` where
  the editor previews it, the imperative calls from engine.game, render.scene,
  Studio and the templates removed, tests run through the schedule.
- [ ] S4 azora-particle-effects: scene emitters (simulate/draw) as systems.
- [ ] S5 azora-foliage: foliage drawn by a `RenderOpaque` system (not from
  `drawHeightfields`); tiles made by systems - with V4.
- [ ] S6 azora-roads: network build, render, terrain grading and collision
  sources as systems - with R.
- [ ] S7 azora-atmosphere: sky (aerial perspective, clouds) prepared and drawn
  by systems (RenderSky/RenderVolumes); Studio's `drawPhysicalSky` goes.
- [ ] S8 azora-landscape: sculpted landscapes drawn by a system; colliders kept
  by a system (`syncLandscapeColliders` out of the template).
- [ ] S9 azora-material-fusion: materials prepared by a system (not
  `prepareFusionMaterials` at start).
- [ ] S10 azora-procedural + azora-world-partition: streaming and generation
  as systems (game and editor), Studio's `streamWorldAround` call goes.
- [ ] S11 azora-vehicles: vehicle input/simulation/presentation/sound as
  package systems over Vehicle + driver components (template keeps only its
  key bindings).
- [ ] S12 azora-photon-field + azora-render: Photon Field update, meshes,
  terrain and skinned meshes as systems; `SceneView` out of
  engine.atmosphere.view into a neutral module.
- [ ] S13 Any other package with per-frame calls (audio, animation, physics,
  ui) checked and converted.

## Shared foundation (F)

- [x] F1 Entry files: `tools/build.sh` (and azpm) take the entry named by
  `azora.azon` `project.entry` instead of requiring `src/main.az`.
- [x] F2 (superseded by S1) Render hooks: `@SceneDraw(stage:, order:)` (engine.render.scene). A
  package registers a function that draws its feature in the opaque pass, the
  sun's shadow cascade or after the opaque scene; `drawScene` finds them by
  reflection, so the renderer imports neither water nor vegetation, and the
  game and the Studio viewport draw the same thing. Water moves to it.
- [x] F3 Local wind: `WindZone` component (engine.weather.wind, with `Wind`:
  the owner's call, wind is weather, not scene) — a sphere or box
  with falloff, blowing one way, outward or around (vortex), with its own gusts.
  `windFieldAt(world, point, time)` adds the zones to the scene `Wind`; a GPU
  block of up to 16 zones for shaders (vegetation, water ripples).
- [ ] F4 Test project `~/Documents/Azora/Test`: entry `azoraTest.az`; headless
  checks (`AZORA_TEST_CHECKS=1`, harness.env + expected.txt, run with
  `tools/harness.sh`) in `waterChecks.az`, `roadChecks.az`,
  `vegetationChecks.az`; the same project runs as a game with scenes for each
  area (coast, city, forest) and opens in Studio.

## Water (W) — `azora-water`, module `engine.water.*`

- [x] W1 Spectrum: `OceanSpectrum` (wind speed/bearing or the scene wind,
  fetch, JONSWAP peak sharpening, directional spread, swell, choppiness, three
  cascades with their patch sizes, seed). h0(k) made once on the CPU from a
  seeded Gaussian; dispersion with depth.
- [x] W2 GPU ocean: Metal compute — time evolution h(k,t), Stockham radix-2
  inverse FFT (256² per cascade), displacement (x, y, z), normal/slope and
  Jacobian foam maps (foam that builds and decays).
- [x] W3 CPU ocean for gameplay: the same h0 for the low-frequency 64² of each
  cascade through a CPU FFT once per frame; `waterSurfaceAt(world, x, z)` (height,
  normal, flow velocity) with the horizontal displacement inverted, shared by
  buoyancy, vehicles, foliage and spawners.
- [x] W4 Ocean rendering: camera-centred clipmap rings (no seams, no swimming),
  Fresnel with the sky, sun glitter, subsurface scattering in wave crests,
  depth absorption toward the shore (scene depth), foam, distance fade into the
  horizon; the Photon/standard light and fog of the scene.
- [ ] W5 Rivers: `River` + ordered `RiverPoint`s (width, depth per point),
  surface following the valley downhill (monotone water level), flow along the
  spline (flow-mapped normals, faster in narrows and drops), white water and
  foam on steps and rocks, waterfalls where the bed drops, carving the bed into
  the landscape like road grading. Tool: trace a river downhill from a source
  over the heightfield (priority-flood + steepest descent), as points.
- [ ] W6 Lakes: `Lake` (level, shore from the landscape: flooded area found
  from the level), calm small waves, shore foam.
- [ ] W7 `Buoyancy` (pontoons, density, drag) + system on `FixedUpdate`;
  `WaterVolume` for underwater fog/tint and swimming queries. Boats done as
  `Hull` + `HullControl` (engine.water.hull, see the log); generic `Buoyancy`
  bodies still to do.
- [x] W9 Shore: surf that shoals and breaks, swash and backwash, foam that
  flows, shallow water seen through to the real bed, no water inside a
  `WaterExclusion` box, surf sound per breaking wave (`SurfSound`).
- [x] W10 The ocean without visible tiling (cascades turned and read twice,
  GPU and CPU alike).
- [x] W11 Underwater view per pixel (waterline from the drawn waves, meniscus,
  blur and horizontal waver); the sky no longer breaks at sea level.
- [ ] W8 Studio: Add Ocean / River / Lake, River point placement, Trace River.

## Roads (R) — `azora-roads`, module `engine.roads.*`

- [ ] R1 Lanes: `RoadLane` child entities (kind Driving|Parking|Bike|Bus|
  Shoulder|Median|Sidewalk|Curb|Verge, width, direction, marking at its outer
  edge, height). A road without lanes keeps its forward/reverse fields (made
  into the same lane list), so generated worlds keep working.
- [ ] R2 Cross-section geometry from lanes: raised sidewalks with curb faces
  wherever two neighbours differ in height, markings from each lane boundary
  (solid, dashed, double, solid-dashed), per-lane materials; collision from the
  same triangles (curbs are steps).
- [ ] R3 Realistic intersections: `RoadIntersection` (corner radius, crosswalks,
  stop lines, control None|Priority|Stop|Yield|AllWayStop|Signals). Road ends
  within its reach connect by themselves; arms sorted by angle; each corner a
  fillet tangent to both arms' edges (curb return), sidewalks wrapping the
  corner, the roads trimmed at the mouth, zebra crossings and stop lines on
  every arm. `RoadJunction` (old T/X/roundabout) stays for older scenes.
- [ ] R4 Barriers and fences: `RoadBarrier` on a road (Guardrail|Fence|Wall|
  Jersey|Railing|Bollards, side, offset, height, post spacing, range) and a free
  `SplineFence` over its own points.
- [ ] R5 Signs: `RoadSign` (Stop, Yield, Priority, End of priority, No entry,
  One way, Speed limit n, Pedestrian crossing, Roundabout, No parking, Parking,
  ...): pole and plate, faces drawn by a vector shader (shapes + stroke glyphs),
  placed by the intersection's control or by hand.
- [ ] R6 Traffic signals: `TrafficLight` heads (vehicle 3-aspect, pedestrian,
  arrow; group) on poles or mast arms; `TrafficSignalController` on an
  intersection (fixed-time phases from its arms, amber, all-red, pedestrian
  walk/flash, flashing amber mode) advanced on `FixedUpdate`; lit lamps;
  `signalAspectAt` for drivers/AI.
- [ ] R7 Crossings mid-block (`Crosswalk`), street props along roads
  (`RoadPropLine`: lamp posts, bollards, delineators).
- [ ] R8 Studio: lane editor (cross-section strip, add/insert/remove lanes),
  Place Intersection, Add Barrier/Fence, Place Sign, Place Traffic Light.

## Vegetation (V) — new `azora-vegetation`, module `engine.vegetation.*`

- [ ] V1 Blueprint model: a plant is a graph of generator nodes (Trunk ->
  Branches (levels) -> Twigs -> Leaves | Needles | Fronds | Blades), each with
  Weber–Penn style parameters (length, taper, curve, segment splits, down and
  rotate angles, branch count and distribution, crown shape, gravitropism) and
  its look (bark, leaf shape and size, colours for summer and autumn).
  Saved as `.azplant` (AZON) assets.
- [ ] V2 Generator: deterministic mesh from blueprint + seed: bark tubes with
  UVs, leaf cards (shape drawn in the shader), per-vertex wind data (level,
  pivot, phase, stiffness, branch direction), LOD0..LOD2 and a far impostor.
- [ ] V3 Species library authored with the tool: oak, beech, birch, maple,
  poplar, willow, spruce, fir, pine, larch, bush, fern, grass clump.
- [ ] V4 Placement: `Plant` (a single plant) and `VegetationScatter` (species
  mix, density, altitude/slope bands, clustering noise, avoid roads/water,
  seed) drawn as instanced tiles, culled, LOD'd, budgeted; shadows from near
  plants into the sun's cascade.
- [ ] V5 Wind: trunk sway, branch bend and leaf flutter from `windFieldAt`
  (scene `Wind` + `WindZone`s), per species stiffness.
- [ ] V6 Seasons: `Season` (time of year, advancing or fixed); deciduous
  species turn from their summer to their autumn colours leaf by leaf, drop
  their leaves into bare winter crowns and bud back; `FallingLeaves` near the
  camera drifting with the wind and settling.
- [ ] V7 Snow: `SnowAccumulation` (capacity, settle/melt rates, wind shedding)
  integrated from the scene's `Snow`, on upward-facing bark and needles.
- [ ] V8 Studio: Vegetation Blueprint editor (node graph + 3D preview with
  wind, season and snow sliders), Place Plant, Scatter Vegetation, Add Wind
  Zone, Season.

## Order

F1-F4, then W1-W8, R1-R8, V1-V8 (the owner's order), each with checks in the
Test project and a look in Studio/game before it is ticked.

## Evidence log

### 2026-11-24

- F1: azpm prints `ENTRY <file>` from `project.entry`; build.sh compiles that
  file (`ENTRY_SOURCE`), main.az only when azora.azon names none. Checked with a
  probe whose entry is `probeHooks.az`, and with the Test project.
- F2: `engine.render.hooks` (`@SceneDraw(stage: .Opaque|.Shadow, order:)`,
  `SceneDrawFrame`, `sceneDrawOrder`); `App.drawSceneFeatures` runs them in
  `drawScene` and in the sun's cascade. azora-render no longer depends on
  azora-water: water registers `drawWaterSurfaces`, azora-game (the scene
  game's composition) and the facade import engine.water. Also
  `App.writeSceneUniforms` / `App.bindSceneLighting` (engine.gpu.draw): a
  package's own pipeline gets the standard `U3` block and the scene's lighting
  buffers (Photon Field, baked and cascade shadows, local lights, weather,
  cloud shadow) - drawMeshPipeline uses the same two. Tests render-stages,
  scene-environment, world-driving, local-lights pass; the template builds.
- S1-S3: weather-parts test now runs the real schedule (`dispatchEditor` on a
  windowless `Game` from `appFailed()`; `startStorm`/`startPrecipitation` need
  a GPU and skip without one) - PASS; render-stages, scene-environment,
  particles PASS; template builds; Studio builds (scratch dir) and its
  viewport runs the editor systems on the demo: 120 FPS, the Thunderstorm
  demo's grey sky and haze from the weather systems (screenshot checked).
  `WaterWaves` lost its wind fields (owner: "we already have the Wind
  component"): the sea is raised by the `Wind` on its entity (query
  `[WaterWaves&, Wind&]`) or the scene's (`[WaterWaves&] without Wind`);
  swell is its own `WaterSwell`.
- F3: owner (mid-session): Wind belongs to azora-weather. `Wind`, `windAt`,
  `sceneWind`/`sceneWindEntity` (were in engine.scene / engine.render.scene)
  and the new `WindZone`, `WindField` (`gatherWindField`, `at`),
  `packWindField` + `windFieldMetalSource` live in `engine.weather.wind`,
  exposed by engine.weather. Serialized names unchanged (old scenes load).
  Test project `windChecks.az`: scene wind, directional/outward/vortex zones,
  soft edges, a replacing shelter, a turned box, gust bounds, the GPU block,
  scene round trip - PASS; scene-environment, weather-parts, particles,
  foliage pass.
- W1-W4 (ocean): engine.water.{components, spectrum, seas, waves, ocean,
  oceanshader, query}. Components Ocean, WaterWaves, WaterSwell, WaterOptics,
  WaterFoam (+ Lake, River, RiverPoint, Buoyancy declared for W5-W7). `Sea`
  (runtime) is kept by the systems: the sea's wind eases toward the Wind over
  `development` seconds, a change of 0.2 m/s or 0.03 rad makes the amplitudes
  again, 12k samples a frame (same random draws per sample: waves grow and turn,
  never jump). Swell: its own random phase stream, fixed amplitudes, energy
  normalised on the cascade's grid (H²/16). GPU: `wave_spectrum` + threadgroup
  radix-2 `wave_fft` (rows, columns) + `wave_finalize` (displacement, slopes,
  Jacobian foam that builds and decays by `persistence`), mipmaps; drawn by
  `drawOceans` (RenderOpaque, editor) as a CDLOD-morphed clipmap of rings
  (cells snapped, base cell grown with eye height), lit with the scene's U3
  block + Photon Field/cascade/cloud/local lights/haze; shallows from
  `OceanShore` (256² depth map baked 16 rows a frame from loaded terrain
  meshes): calmer waves, turquoise over a sandy bed, surge foam lines.
  CPU: the central 32² of each cascade (unpaired Nyquist modes dropped),
  evaluated at 20 Hz and blended; `waterSurfaceAt` inverts the choppy shift.
  Checks (Test project, `waterChecks.az`, PASS): JONSWAP Hs at 10 m/s = 3.2 m
  (fetch-limited formula 2.8), 20 m/s 5.9 m, no wind 0, swell alone 1.5 m;
  CPU FFT equals the direct sum of waves; per-cascade periodicity; motion;
  seas raised by own/scene Wind through the real schedule; gradual build-up;
  surface asked at points; scene round trip. Build of 3x256² cascades: 21 ms.
  Seen in Studio (`coast.azscene`, `coastAerial.azscene`): 120 FPS.
- Compiler/engine findings: `reflect<*>.withAnnot<System>` is silently empty
  when a system's parameter types cannot be resolved from the entry; engine.game
  now `exposed import`s weather, water, atmosphere, audio.output, particles,
  gizmos, platform. Studio: opens `AZORA_STUDIO_SCENE` (any scene, `scenePath`),
  reads the entry from azora.azon (`entrySource`, Code tab), no `main.az` needed.
- Not mine, seen at 03:47: packages/azora-physics-3d/src/d3.az does not parse
  (line 176 `.(` on its own line) - world-driving fails to build until it does.


### 2026-11-24, morning (session "Valuri spre țărm și ocean fără repetare")

Start here for the shore/surf/boat work. Test project: `AZORA_TEST_SCENE=<file>` opens
another scene (coastShore, coastSurf, coastAerial, coastDip, coastBoatView), and
`AZORA_TEST_CAMERA=scene` keeps a scene's active Camera3d even with Sam
(`src/sceneCamera.az`); captures with `AZORA_CAPTURE=frame:path`, sound with
`AZORA_AUDIO_CAPTURE=path.wav`.

- Shore maps (engine.water.shore, baked by the system `mapOceanShores`, PostUpdate,
  editor): two RGBA32F 256² maps around the eye (fine 1.2-12 km, far 8x),
  per texel depth, signed distance to the shoreline (chamfer sweeps) and the
  waves' travel time to the shore (weighted chamfer, speed √(g h) capped at
  deep water: its level lines are the crests, so waves refract toward the
  beach). The first map is made at once on load; a map waits for loaded
  terrain meshes and is made again when more load.
- Surf (`SurfSource` -> `SurfState`, shader and CPU alike): two trains of the
  peak period and 1.13x (sets), Green's-law shoaling, breaking at H = 0.78 h,
  bores held at 0.62 h with a sawtooth front, Gerstner lean before breaking,
  swash run-up 0.043 √(H₀ L₀) (Stockdon); the open sea's largest cascade calms
  where the surf takes over. `waterSurfaceAt` / `waterLevelAt` include it.
- Foam: lace from value noise carried by a two-phase flow map along the water's
  motion (no static texture, no tearing); `WaterFoam.surf` (amount) and
  `WaterFoam.opacity` (0.9) are properties. `WaterOptics.shallow` +
  `shallowDepth`: the shallow water's own colour (any colour: red/green water).
- Transparency: the opaque scene captured before the water is drawn shows
  through it, bent by the normal, absorbed along the light's path; the edge
  fades into the ground (no seam).
- No repetition: `cascadeTurn` + a second reading turned 2.4 rad and moved
  (0.37, 0.61) tiles, blended by `tileBlend`, in the shader and in
  `waveDisplacement` (CPU).
- Systems: `simulateSeas` (GPU FFT) and `mapOceanShores` are PostUpdate systems;
  `drawOceans` only draws. `renderUnderwater` (RenderVolumes, editor) replaces the
  Test project's own call.
- Boats: `Hull` (waterline length/beam, keel, sides, fullness, bow, mass,
  centre height, propeller position/thrust/reverse, top speed, turn rate,
  planing, slamming, density) + `HullControl` (throttle, rudder);
  `floatHulls` (FixedUpdate) floats 5x3 bottom points (Archimedes + damping
  against the water's own vertical speed + slamming ½ρCv²), the propeller
  below the centre of mass lifts the bow under acceleration, planing lift;
  `presentHulls` (Update) interpolates by `fixedAccumulator / fixedTimestep`.
  The Test boat uses it; camera jolt and a thump sound on slams.
  `WaterExclusion` boxes (up to 8) keep the sea out of the cockpit.
- Underwater: per pixel, the near-plane point against `seaHeightAt` (same waves
  as the surface); a ray that enters the water before what it strikes (crest
  ahead of the lens, surface closer than the near plane) counts as under water;
  meniscus; blur by distance; horizontal waver. The ocean's underside is chosen
  per fragment (`front_facing`).
- Atmosphere fix: the sky's camera radius never reaches the ground sphere
  (`writeAetherView` clamps altitude to >= 2 m); at sea level the sky showed bands.
- Material Fusion: `fusionWeightsAt` / `fusionDominantAt` evaluate a material's
  masks on the CPU (no noise variation) - what a surface is made of at a point.
  Test project footsteps (`src/footsteps.az`): wet/dry sand, grass, rock,
  shallows, wading, from the terrain's material and the water depth.
- Surf sound (`SurfSound` on the ocean, `soundSurf`, Audio): 80 points around the
  listener; a crash per breaking crest passing, loudness from height x breaking,
  hardness from H / h, panned, plus wash and backwash. 39 s capture: crashes every
  4-8 s, RMS 0.03-0.09.
- Checks (Test project, PASS): shore maps (depth, distance, travel time = the
  integral of dx/√(gh)), shoaling and breaking, swash within its run-up, cascades
  not repeating over a tile, hull floats at its displacement draft / lifts its
  bow / reaches top speed / slams, footsteps ground.
- Cost: at 2560x1440 native the water's fragment shader is ~2.5 ms and its vertex
  ~0.3 ms (coastSurf view, water on the whole screen: 14.2 ms GPU, 7.6 without
  the ocean); the rest is the FFT simulation and the scene copy.
- Open: seagull calls from the owner's two YouTube references (audio cannot be
  taken from YouTube; needs a recording the owner provides or a CC one);
  generic `Buoyancy` bodies; rivers/lakes (W5-W6) are another session's.
