# Azora Engine Robotics and Autonomous Systems - Proposal

> Status: **proposal.** `azora-engine` provides the first backend-neutral
> robotics contracts. The `robot`, `sensor`, `actuator`, `topic`, `service`,
> `action`, `frame`, and safety syntax described here is contextual proposal
> syntax until the parser, type checker, runtime, and hardware adapters agree
> on the semantics.

Azora should make robotics software readable from the physical boundary inward:
frames, timestamps, sensor provenance, actuator limits, lifecycle, safety mode,
and authority should be visible in the program. Hardware and middleware must be
replaceable, but physical assumptions must not be hidden behind untyped strings
or arbitrary callbacks.

Robotics is an engine subsystem, not a general-purpose standard-library
facility. The target source package is `azora-engine/robotics`, exposed through
the `azora.engine.robotics` module. It provides ordinary Azora values for
geometry, joint limits, commands, trajectories, safety limits, and sensor
samples. Hardware, transports, real-time clocks, and safety-rated controllers
remain explicit bridge implementations or separate packages.

The standard library remains focused on generally reusable facilities such as
math, time, containers, I/O, and concurrency. This DIP does not introduce
`std.spatial` or `std.measurement`; robotics-specific spatial and measurement
contracts belong to the engine.

```azora
import azora.engine.robotics

func inspectPose() {
    fin base = azora::engine::robotics::identityPose()
    fin point = azora::engine::robotics::transformPoint(
        base,
        azora::engine::robotics::vector3(1.0, 0.0, 0.0),
    )
    return point
}
```

The design uses ROS 2's established communication distinction: topics carry
continuous streams, services handle short request/response work, and actions
represent long-running work with feedback and cancellation. See the [ROS 2
interface documentation](https://docs.ros.org/en/rolling/Concepts/Basic/Interfaces-Topics-Services-Actions.html)
and [action semantics](https://docs.ros.org/en/rolling/Concepts/Basic/About-Actions.html).

This DIP is for defensive, safety-conscious robotics development. A software
API cannot replace a safety-rated controller, risk assessment, emergency-stop
circuit, commissioning procedure, or applicable regulation.

## 1. Design basis

The design is informed by:

- ROS 2 nodes, topics, services, actions, QoS, discovery, and managed lifecycle;
- micro-ROS for resource-constrained, RTOS-connected devices and embedded
  participation in a larger ROS 2 system;
- REP-105-style frame conventions and explicit transform trees;
- [ISO 10218-2:2025](https://www.iso.org/standard/73934.html) for industrial
  robot application and cell integration safety;
- [ISO 13482:2014](https://www.iso.org/standard/53820.html?browse=ics) for
  personal-care robot hazards and protective measures.

The standards define system and application responsibilities. Azora's role is
to make the contracts, limits, authority, and evidence explicit and testable.

## 2. Goals and non-goals

### Goals

- Represent positions, orientations, twists, wrenches, frames, and timestamps
  with named types rather than ad-hoc arrays.
- Keep coordinate-frame identity attached to transforms and sensor samples.
- Make sensor and actuator types generic and middleware-independent.
- Separate topics, services, and cancellable actions in the type system.
- Validate joint limits, trajectory dimensions, deadlines, and safety bounds
  before a command crosses into a hardware bridge.
- Provide managed lifecycle and independent safety-state transitions.
- Support deterministic simulation and replay with injectable clocks and fake
  hardware providers.
- Make ownership, capabilities, secret handling, and audit requirements from
  the corresponding Azora DIPs composable with robotics code.
- Interoperate with ROS 2, micro-ROS, DDS, CAN, EtherCAT, serial, simulation,
  GPU perception, and remote robot adapters through bridges.
- Give the IDE symbol-based navigation from a command to its limit, actuator,
  frame, capability, and safety policy.

### Non-goals for the first version

- Implementing a safety-rated real-time kernel or safety-rated controller in
  Azora itself.
- Claiming that a successful type check proves a robot is safe to deploy.
- Choosing one middleware, robot vendor, fieldbus, kinematics library, or
  simulator as the language runtime.
- Hiding network latency, clock drift, dropped messages, stale observations, or
  actuator faults behind ordinary pure functions.
- Treating a topic as a service or a long-running motion as an un-cancellable
  synchronous function.
- Providing autonomous weapons, harmful control logic, or unauthorized control
  of a robot.

## 3. System model

Azora robotics is layered:

```text
hardware/safety PLC -> driver bridge -> typed sensor/actuator contracts
                                      -> node/topic/service/action graph
                                      -> planning/control/application logic
                                      -> simulation/replay/test provider
```

The compiler and runtime must preserve the difference between:

- a measurement and a prediction;
- a command and an acknowledgement;
- a desired state and a measured state;
- a frame transform and a point in a frame;
- application stop, protective stop, and emergency stop;
- a service result and an action result;
- simulated time and wall-clock time.

These distinctions prevent an API from making a plausible value look more
authoritative than it is.

### 3.1 Ownership and package boundaries

The robotics boundary is intentionally divided into three layers:

```text
std -> azora-engine -> robotics provider packages
```

`std` supplies generic language facilities. `azora-engine` owns the stable
robotics model and runtime contracts. Provider packages own middleware,
hardware, algorithms, simulators, and vendor-specific behavior.

The target engine layout is:

```text
azora-engine/
  robotics/
    core
    geometry
    frames
    measurements
    sensors
    actuators
    motion
    trajectories
    lifecycle
    safety
    messaging
    runtime
```

The first implementation may expose these through one
`azora.engine.robotics` module. They may later become submodules without
moving the contracts back into `std`.

The following capabilities belong in separate packages outside the engine:

- ROS 2, micro-ROS, DDS, CAN, EtherCAT, serial, and vendor drivers;
- deterministic simulation, replay, virtual clocks, and hardware-in-the-loop;
- PID, MPC, kinematics, dynamics, collision checking, and motion planning;
- navigation, SLAM, perception, sensor fusion, and robot-specific models;
- URDF/SDF, visualization, telemetry, and deployment tooling.

The engine may define provider interfaces for these capabilities, but it must
not embed one middleware, hardware vendor, simulator, or algorithm stack.

## 4. Geometry and frames

### 4.1 Core values

`azora.engine.robotics` defines:

| Type | Meaning |
|---|---|
| `Vector3` | Three-dimensional vector |
| `Quaternion` | Scalar-first unit rotation quaternion |
| `Pose` | Position plus orientation |
| `FrameTransform` | Rigid transform from parent frame to child frame |
| `Twist` | Linear and angular velocity |
| `Wrench` | Force and torque |

The library normalizes quaternions at pose construction and rejects a zero
quaternion. A transform must state both `parent` and `child` frame identities;
the names are not decorative and must not be discarded during serialization.

### 4.2 Frame graph rules

A runtime frame tree should enforce:

- each frame has at most one active parent in a tree view;
- a transform lookup reports missing, stale, disconnected, or cyclic paths;
- timestamps are attached to dynamic transforms;
- static transforms are immutable after activation unless a lifecycle change
  explicitly replaces them;
- transform composition verifies the intermediate frame symbolically;
- a point, vector, twist, or wrench cannot be combined across frames without
  an explicit transform;
- frame names are canonicalized at the middleware boundary, not matched by
  informal string similarity.

The first library surface uses strings for compatibility with today's compiler.
The future type checker should offer a frame-parameterized form:

```text
Point3<CameraFrame>
Pose<BaseFrame, WorldFrame>
Twist<BodyFrame>
```

This is a type-safety feature, not merely a unit convenience. A camera point
and a world point may both contain three doubles while having different
meanings.

### 4.3 Units

Robotics values should carry units in a later dimension/units DIP:

```text
Length<Meter>
Angle<Radian>
Velocity<MeterPerSecond>
AngularVelocity<RadianPerSecond>
Torque<NewtonMeter>
Time<Second>
```

Until that DIP exists, field documentation and adapter contracts must state SI
units. Numeric conversion must be explicit at the boundary.

## 5. Sensors and provenance

A sensor sample is more than a value. `SensorSample<T>` includes:

- source timestamp in a declared clock domain;
- monotonically increasing sequence identity where supported;
- frame identity;
- typed measurement value.

Adapters should additionally expose:

- acquisition time versus publication time;
- calibration and covariance metadata;
- device identity and firmware version;
- quality, validity, saturation, and diagnostic flags;
- synchronization uncertainty and dropped-sample counts.

The runtime must distinguish “no sample yet,” “sample stale,” “sensor fault,”
and “valid sample whose value is zero.” A default-constructed numeric value must
never silently stand in for a missing measurement.

Sensor streams should support both pull and push patterns:

```azora
fin imu: std::Sensor<std::ImuSample> = std::sensor(robot, "imu", std::SensorKind.Imu)
fin reading = std::read(imu)
```

The bridge supplies the concrete sample type and timing semantics. Blocking
read, bounded read, latest-value read, and subscription APIs must be distinct.

## 6. Actuators, commands, and limits

An actuator command is an intent that still needs admission by a controller.
Before it crosses the bridge, the system should check:

- actuator identity and control mode;
- joint/axis position, velocity, acceleration, jerk, effort, and temperature;
- command deadline and source timestamp;
- current lifecycle and safety mode;
- capability/authority of the caller;
- collision, workspace, and interlock policy where available;
- whether the command is stale, duplicated, or out of sequence.

`JointLimit` and `SafetyLimits` provide the first source-level contracts.
`boundedPositionCommand` clamps a requested position to a declared limit, but
clamping is not always safe: a rejected command may be preferable when the
caller needs to know that its plan was invalid. Production controllers should
offer both reject and explicitly requested clamp policies.

The safe default is fail closed: a missing limit, stale state, unknown frame,
expired deadline, or safety fault prevents actuation. An adapter must not turn a
failed validation into a best-effort motion.

## 7. Trajectories and control loops

`Trajectory` has a stable joint-name order and time-ordered points. The
validator must reject:

- empty joint names or point lists;
- position dimensions that do not match the joint list;
- velocity dimensions that are neither zero nor the joint count;
- negative or non-monotonic point times;
- non-finite values;
- limits that cannot be met between points;
- trajectories whose deadline has expired.

The future motion-planning layer should model interpolation policy explicitly:
linear, cubic, quintic, time-optimal, jerk-limited, or controller-native. A
trajectory is not safe merely because its endpoints satisfy joint limits.

Control loops need timing contracts:

- fixed-period loops declare their target period and allowable jitter;
- a loop must detect missed deadlines and stale sensor data;
- the control clock is monotonic and injectable in simulation;
- allocation, blocking I/O, unbounded logging, and garbage-producing work are
  forbidden or diagnosed in a hard real-time loop;
- watchdog ownership and fallback behavior are explicit;
- a controller must specify what happens when its input stream stops.

## 8. Communication model

The first bridge types mirror the useful ROS 2 communication shapes:

| Type | Semantics | Required behavior |
|---|---|---|
| `Topic<T>` | Continuous many-to-many stream | QoS, depth, timestamp, drop/backpressure policy |
| `Service<Request,Response>` | Short request/response | Bounded execution and explicit failure |
| `Action<Goal,Feedback,Result>` | Long-running behavior | Feedback, cancellation, preemption, final result |

`Action` is the default abstraction for navigation, manipulation, docking,
calibration, and other operations that may take time or need cancellation. A
goal returns a `GoalHandle`; feedback and final result are separate operations.
Cancellation is not assumed to be instantaneous: the provider must report
whether it accepted the request and the safety controller owns the final stop.

Transport concerns belong in explicit options and provider metadata:

- reliable versus best-effort delivery;
- queue depth and backpressure;
- deadlines and liveliness;
- transient-local or durable state;
- serialization schema/version;
- authentication, authorization, and encryption;
- discovery domain and namespace.

The engine contract layer does not make DDS the only valid transport. ROS 2/DDS,
micro-ROS/DDS-XRCE, CAN, EtherCAT, serial, shared memory, and simulation can
implement the same typed contracts where their semantics permit.

## 9. Lifecycle and safety

### 9.1 Independent state machines

Lifecycle and safety are separate state machines:

```text
lifecycle: Created -> Configured -> Inactive -> Active -> Faulted -> Shutdown
safety:    Normal <-> ReducedSpeed <-> ProtectiveStop <-> Recovery
                                      \-> EmergencyStop
```

An `Active` node can still be in `ReducedSpeed` or `ProtectiveStop`. Clearing a
stop is not equivalent to activating a node. The adapter must reject illegal
transitions and expose the reason, source, timestamp, and reset conditions.

### 9.2 Safety boundary

`SafetyController` is intentionally separate from an ordinary `Actuator`. It
may be backed by a safety PLC, certified controller, hardware E-stop chain,
robot vendor safety API, or a simulation model. `protectiveStop` and
`emergencyStop` are requests into that system, not claims that a process-level
function can guarantee physical removal of energy.

The language/runtime should support:

- independent watchdogs;
- dead-man and enable devices;
- speed/force/separation limits;
- collision and workspace interlocks;
- safe torque off and power isolation state;
- two-channel or redundant safety inputs;
- explicit recovery and human acknowledgement;
- audit of every stop, reset, override, and rejected command.

No application-level “ignore safety” flag should bypass the safety controller.
Simulation may model an override, but production adapters must require a
separate authenticated and auditable maintenance capability.

## 10. Deterministic simulation and replay

Every robotics provider should be replaceable with a deterministic simulator or
log-replay provider. The simulation contract should control:

- monotonic simulation clock;
- sensor noise and latency;
- actuator dynamics and saturation;
- dropped, delayed, duplicated, and reordered messages;
- collision and contact outcomes;
- random seed and scenario identity;
- lifecycle and safety faults.

Recorded data must retain timestamp, frame, schema, calibration, and provider
metadata. Replay must not silently use wall-clock time or current hardware
calibration. A test that passes only because a real robot responded quickly is
not deterministic.

## 11. Security and authority

Robotics code composes with `std.security`:

- commands require explicit capabilities or an adapter-defined authority;
- robot credentials, calibration secrets, signing keys, and remote-provider
  tokens are `Secret<T>`, never ordinary strings;
- command, stop, reset, firmware, calibration, and configuration operations are
  separately auditable;
- a child process, plugin, AI tool, GPU kernel, or remote action receives only
  attenuated authority;
- telemetry and recordings carry classification and redaction policy;
- safety overrides require stronger authentication, shorter leases, and a
  distinct audit event.

The robotics module should never log raw credentials, full camera frames,
personal data, or unrestricted actuator payloads by default.

## 12. AI, GPU, and quantum interoperation

### AI/ML

Perception and planning models consume sensor data and produce proposals, not
authority. An AI-generated trajectory must pass the same frame, timing, joint,
collision, capability, and safety checks as a human-authored trajectory. Model
confidence is evidence for a policy, not an emergency-stop mechanism.

`std.ml.Tensor` can be converted to a robotics tensor view with explicit frame,
layout, timestamp, and classification metadata. A model tool must not directly
command an actuator without a typed safety gate.

### GPU

GPU perception and planning are asynchronous. A `GpuEvent` must carry the
sensor sequence and timestamp used by the computation, and readback must reject
stale results when the controller's deadline has passed. Debug captures and
buffers may contain restricted imagery or calibration data and therefore follow
`std.security` policy.

### Quantum

Quantum providers may be useful for research optimization, but a remote or
probabilistic quantum result cannot bypass deterministic command validation,
watchdogs, or safety controllers. Circuit execution and provider credentials
remain explicit audited effects.

## 13. Contextual robotics vocabulary

These terms should remain ordinary identifiers outside a robotics declaration:

| Word | Context | Meaning |
|---|---|---|
| `robot` | declaration/type | Hardware graph or robot application |
| `sensor` | declaration/type | Typed measurement source |
| `actuator` | declaration/type | Typed command destination |
| `frame` | type/parameter | Coordinate-frame identity |
| `transform` | expression | Rigid frame conversion |
| `joint` | declaration/type | Articulated degree of freedom |
| `trajectory` | value/declaration | Time-parameterized motion |
| `topic` | communication | Continuous stream |
| `service` | communication | Short request/response endpoint |
| `action` | communication | Cancellable long-running operation |
| `watchdog` | safety | Deadline/freshness monitor |
| `protectiveStop` | safety effect | Controlled stop pending recovery |
| `emergencyStop` | safety effect | Safety-system emergency stop request |
| `calibrate` | lifecycle/effect | Establish sensor or actuator calibration |

The compiler should recognize these forms only after an explicit robotics
context is established. No existing program should break because it has a
function named `frame` or `action`.

## 14. `azora.engine.robotics` initial surface

The initial engine module is `azora.engine.robotics`, implemented at
`azora-engine/robotics.az` in the engine source tree:

| API | Purpose |
|---|---|
| `Vector3`, `Quaternion`, `Pose`, `FrameTransform` | Typed spatial geometry |
| `Twist`, `Wrench` | Motion and force representation |
| `JointLimit`, `JointState`, `JointCommand` | Joint contracts |
| `Trajectory`, `TrajectoryPoint` | Time-ordered motion plans |
| `SafetyLimits`, `SensorSample<T>` | Admission and provenance metadata |
| `vector3`, `quaternion`, `identityPose`, `pose` | Geometry construction |
| `normalizeQuaternion`, `transformPoint` | Safe spatial helpers |
| `withinLimit`, `clampToLimit`, `boundedPositionCommand` | Limit enforcement helpers |
| `validTrajectory` | Dimension and time validation |
| `Robot`, `Sensor<T>`, `Actuator<T>` | Hardware/provider handles |
| `Topic<T>`, `Service<...>`, `Action<...>` | Middleware-neutral communication |
| `GoalHandle<...>` | Feedback/result/cancellation identity |
| `SafetyController` | Separate physical-safety boundary |

None of these APIs should be imported from `std`. The engine surface is
backend-neutral, but it is still robotics-specific and therefore belongs to
the engine distribution.

The bridge surface includes connection, lifecycle, sensor, actuator, topics,
services, actions, and stop/recovery operations. It intentionally does not
provide a fake real-hardware implementation.

## 15. Diagnostics and IDE support

The language server should provide:

- go-to-definition from a sensor reading to its frame, calibration, driver, and
  provider identity;
- go-to-definition from an actuator command to its joint limit, safety policy,
  controller, and capability origin;
- warnings for frame mismatch, stale timestamps, missing deadlines, unchecked
  trajectory dimensions, and commands issued outside `Active` lifecycle;
- action feedback/result/cancellation flow visualization;
- detection of blocking I/O, allocation, logging, or unbounded work in a
  real-time loop;
- safe fixes for missing bounds, missing frame transforms, missing capability,
  and missing audit metadata;
- generated ROS/interface schemas and symbol maps from the same declarations.

Diagnostics must name the symbol and contract, not merely compare strings in
generated middleware code. Renaming a joint or frame must update all references
through symbol resolution.

## 16. Testing and verification

Robotics support requires tests at several levels:

- quaternion, transform, frame-tree, unit, and layout property tests;
- joint limit, trajectory, deadline, stale-sensor, and NaN/finite-value tests;
- lifecycle transition and fault-recovery tests;
- actuator admission tests proving invalid or stale commands never reach the
  provider;
- topic QoS, service timeout, action feedback, preemption, and cancellation
  tests;
- deterministic simulation and log replay with dropped/reordered messages;
- watchdog, protective-stop, emergency-stop, reset, and override tests;
- capability, secret, audit, and telemetry-redaction tests;
- hardware-in-the-loop tests with a physically isolated safety boundary;
- fault injection for disconnected sensors, stuck actuators, clock drift,
  driver crashes, network partitions, and corrupted calibration;
- generated schema compatibility tests across middleware adapters.

Passing simulation tests is not evidence that a physical robot is safe to
operate. Deployment requires system-level validation, qualified integration,
and the applicable safety process.

## 17. Implementation roadmap

1. **Engine contract layer:** maintain `azora.engine.robotics` in the
   `azora-engine` source tree, exposing typed geometry, joint limits,
   trajectories, sensor samples, lifecycle, and safety contracts there.
2. **Provider packages:** implement deterministic simulation, fake sensors,
   bounded actuators, replay, and fault injection.
3. **Middleware adapters:** add ROS 2/DDS, micro-ROS, shared memory, serial,
   CAN, and simulator bridges with generated interface metadata.
4. **Units and frames:** add type-parameterized frames and SI units, then make
   mismatched transforms and units compile-time diagnostics.
5. **Real-time contract:** add loop annotations, allocation/blocking checks,
   watchdogs, priorities, deadline effects, and executor integration.
6. **Safety integration:** connect certified controllers, interlocks, stop
   chains, authenticated recovery, audit, and commissioning evidence.
7. **Planning/control packages:** add kinematics, dynamics, interpolation,
   collision contracts, optimization, and typed `std.ai`/`std.ml`/`std.gpu`
   adapters without placing those systems in the engine contract layer.
8. **Tooling:** add frame graph visualization, trace/replay inspection,
   trajectory preview, action lifecycle views, and hardware diagnostics.

## 18. Principles

1. Frame identity is data, not a comment.
2. Measurements carry provenance, timestamps, and quality.
3. Desired state is not measured state.
4. Commands are admitted by limits and safety policy before hardware.
5. Long-running motion is cancellable and preemptible.
6. Lifecycle and safety state are separate.
7. Application code cannot replace the safety controller.
8. Simulation is deterministic by contract, not by hope.
9. Authority, secrets, and audit compose with `std.security`.
10. Robotics syntax remains contextual until the compiler can prove these
    contracts rather than merely color the keywords.
