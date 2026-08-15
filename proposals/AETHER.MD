# Azora Aether — Sky, Atmosphere, Clouds, and Weather

Status: Proposal
Primary package: `azora-aether`
Primary module: `engine.aether`

## 1. Decision

Aether owns atmospheric scattering, sky radiance, sun/moon ephemeris, volumetric
clouds, weather state, precipitation intent, wind fields, and environmental
exposure inputs. It publishes neutral environment data consumed by Lighting,
Radiance, Fluids, Foliage, Particles, Audio, and gameplay. It does not directly
spawn rain particles, mix thunder audio, or move foliage.

## 2. Current engine audit

The engine has a hard-coded directional light and ambient scalar but no sky,
atmosphere, volumetric rendering, weather, wind, world coordinates, or exposure
pipeline. Aether therefore depends on the proposed render graph and Lighting,
while its weather simulation can begin as a renderer-independent package.

## 3. Public model

```azora
enum WeatherKind {
    Clear
    Cloudy
    Rain
    Storm
    Snow
    Fog
}

pack AtmosphereProfile {
    var planetRadius: std::Double
    var atmosphereHeight: std::Double
    var rayleighScaleHeight: std::Double
    var mieScaleHeight: std::Double
    var ozoneAmount: std::Double
    var groundAlbedo: Vec3
}

pack WeatherState {
    var kind: WeatherKind
    var coverage: std::Double
    var precipitation: std::Double
    var humidity: std::Double
    var temperature: std::Double
    var wind: Vec3
    var lightningProbability: std::Double
}

@Resource
pack AetherClock {
    var latitude: std::Double
    var longitude: std::Double
    var day: std::Int
    var seconds: std::Double
    var timeScale: std::Double
}

@Resource
pack AetherSettings {
    var atmosphereQuality: std::Int
    var cloudSteps: std::Int
    var cloudShadowResolution: std::Int
    var weatherCellSize: std::Double
}
```

## 4. Atmosphere

The physical sky uses precomputed transmittance, multi-scattering, sky-view, and
aerial-perspective lookup tables. LUT invalidation depends on atmosphere and sun
parameters, not camera motion. Camera-height and view-dependent tables update
incrementally. Space views, ground views, and below-sea-level clamps have
explicit policies.

The environment contract publishes sun direction/radiance, moon direction,
sky irradiance, specular sky map, aerial perspective, and atmospheric
transmittance. Lighting creates corresponding direct lights; Radiance samples
the sky distribution.

## 5. Clouds

Clouds use sparse weather fields and multi-resolution density volumes. A low-
frequency weather map controls coverage/type; procedural detail adds erosion
without changing large-scale identity. Ray marching uses empty-space skipping,
temporal reprojection, blue-noise sampling, and separate cloud-shadow maps.

History validates wind advection, camera cuts, weather generation, exposure,
and depth. A coarse cloud layer remains available on low tiers; a static cubemap
is the final fallback.

## 6. Weather simulation

Weather is a deterministic cell field updated at a low fixed frequency. Cells
hold pressure, humidity, temperature, wind, cloud water, and precipitation.
Applications may use authored fronts, procedural evolution, or an authoritative
network stream. The rendered cloud field and gameplay `WeatherState` come from
the same generation.

Weather events publish stable cell/event symbols. Particles maps precipitation
to local emitters, Audio maps events to ambiences/thunder, Fluids consumes rain
and wind, Foliage consumes wind, and Cognition may query visibility or noise. These are
adapter packages to avoid Aether importing every consumer.

## 7. Wind

Wind is sampled as a layered field: prevailing vector, altitude profile,
weather-cell contribution, terrain/obstacle modifiers, and bounded gusts.
Consumers request position, scale, and time; they do not read Aether internals.

```azora
func windAt(position: WorldPosition, scale: std::Double): Vec3
func weatherAt(position: WorldPosition): WeatherState
func skyAt(direction: Vec3): Vec3
```

## 8. Performance and diagnostics

Budgets cover LUT updates, cloud ray steps, weather cells, cloud shadow updates,
history buffers, and environment-map filtering. Debug views expose LUTs, cloud
density/steps/history confidence, weather cells, wind vectors, precipitation,
lightning probability, and fallback tier.

Profiler counters include atmosphere update time, cloud samples, empty-space
skips, history acceptance, weather cells updated, shadow latency, environment
filter time, and GPU memory.

## 9. Delivery

1. deterministic clock, sun/moon, weather state, and wind queries.
2. physical atmosphere LUTs and Lighting/Radiance environment contract.
3. volumetric clouds, temporal reconstruction, and cloud shadows.
4. weather cells, precipitation/lightning events, and consumer adapters.
5. planetary views, local fog volumes, advanced cloud types, and networked
   authoritative weather.

Acceptance uses reference transmittance tests, stable day/night cycles, camera
cuts, origin rebasing, fast time scale, streaming weather cells, and strict GPU
step/memory budgets.
