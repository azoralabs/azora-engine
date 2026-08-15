# Azora Vehicle — Cars, Aircraft, Boats, and General Vehicles

Status: Proposal
Primary package: `azora-vehicle`
Primary module: `engine.vehicle`

## 1. Decision

Vehicle is a modular force-and-control layer on top of Physics. A vehicle is a
chassis plus power, control, contact, and stabilization modules. Cars, tracked
vehicles, aircraft, hovercraft, and boats share input, telemetry, assists,
damage, networking, and replay contracts while using different force providers.
Vehicle does not implement a second collision solver.

## 2. Current engine audit

There is no vehicle package. Physics currently has primitive body math but not a
running world, joints, suspension casts, or tire contacts. Input has typed
keyboard, mouse, touch, and gamepad codes but no action maps. Audio can play and
mix sounds, while Fluids is proposed. The racing template contains game-specific
movement that can become a migration/reference scenario, not core vehicle code.

## 3. Public model

```azora
pack VehicleId {
    fin value: std::Long
}

enum VehicleKind {
    Wheeled
    Tracked
    Aircraft
    Watercraft
    Hover
}

@Component
pack Vehicle {
    fin id: VehicleId
    fin kind: VehicleKind
    var enabled: std::Bool
}

@Component
pack VehicleControl {
    var throttle: std::Double
    var brake: std::Double
    var steer: std::Double
    var pitch: std::Double
    var yaw: std::Double
    var roll: std::Double
    var handbrake: std::Double
}

@Component
pack VehicleTelemetry {
    var speed: std::Double
    var engineRpm: std::Double
    var gear: std::Int
    var slip: std::Double
    var grounded: std::Bool
}
```

Controls are normalized intent. Input mapping, Cognition driving, replay, and network
prediction all write the same component.

## 4. Modules

```azora
spec VehicleForceModule {
    func prepare(context: VehicleContext&, output: VehicleForces!)
    func apply(context: VehicleContext&, output: VehicleForces!)
}
```

Built-in modules include engine/motor, gearbox, differential, brakes, steering,
wheel suspension, tire model, tracks, aerodynamics, propeller/jet thrust,
buoyancy/planing, hover suspension, anti-roll, traction control, ABS, stability
control, damage, and fuel/energy. A vehicle asset validates dependencies and
orders modules once; the hot path does not dynamically search by name.

## 5. Wheeled vehicles

Each wheel has suspension geometry, radius, inertia, steering, drive/brake
ratios, spring/damper, and tire curve. Suspension uses batched sphere/cylinder
casts where available. Contact velocity is resolved at the patch; longitudinal
and lateral slip feed a combined tire force ellipse. Load sensitivity, rolling
resistance, camber, and surface friction are quality features.

The first tier is a ray/sphere-cast wheel vehicle. A later rigid-wheel tier uses
actual colliders and constraints for slow/off-road detail.

## 6. Aircraft and watercraft

Aircraft evaluate lift/drag/moment at authored aerodynamic surfaces using local
air velocity from Aether wind. Engines provide thrust curves; control surfaces
map input to coefficients. Stall and ground effect are explicit models.

Watercraft query Fluids for height, normal, velocity, and depth across hull points or
slices. Fluids owns fluid data and buoyancy; Vehicle owns hull propulsion,
steering, planing, and control assists.

## 7. Fixed-step, networking, and replay

Vehicle forces run in Physics pre-solve at the fixed timestep. Visual wheel,
control-surface, and suspension poses interpolate afterward through Animation.
Rollback state includes controls, module state, wheel angular speed, drivetrain,
and Physics snapshot identity. Cosmetics such as sound and particles regenerate
from confirmed events.

## 8. Diagnostics and delivery

Debug overlays show center of mass, suspension travel, contacts, tire force
vectors, slip curves, drivetrain flow, aero surfaces, lift/drag, buoyancy samples,
and assist intervention. Counters include vehicles, casts, contacts, module time,
solver impulses, prediction corrections, and promoted detail tier.

Delivery:

1. assets, controls, telemetry, force-module contract, simple arcade chassis.
2. wheel suspension, drivetrain, tire forces, assists, and surface materials.
3. aircraft forces and Aether wind.
4. boats/hovercraft and Fluids integration.
5. damage, modular extensions, rollback prediction, editor tuning, and advanced
   rigid-wheel/tracked simulation.
