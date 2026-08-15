# Azora Cognition — Behavior, Perception, Queries, and Utility

Status: Proposal
Primary package: `azora-cognition`
Primary module: `engine.cognition`

## 1. Decision

Cognition is an ECS-native decision framework with four composable layers: perception
creates evidence, queries create bounded world facts, decision models select
intent, and actions execute through gameplay capabilities. It supports behavior
trees, hierarchical state machines, utility scoring, and planners without
forcing every agent into one model.

Cognition does not own navigation, physics, animation, input, or networking. It
coordinates them through explicit symbols and action capabilities.

## 2. Current engine audit

No Cognition package exists. ECS provides entities, typed storage, revisions, events,
deferred commands, and access-aware schedules. Tilemap provides line of sight
over maps. Physics world queries, Traverse, action maps, and spatial World
queries remain proposals. These dictate a staged delivery beginning with pure
decision models and test worlds.

## 3. Identity and memory

```azora
pack CognitionAgentId {
    fin value: std::Long
}

pack CognitionSymbol {
    fin value: std::Long
}

enum CognitionStatus {
    Idle
    Running
    Succeeded
    Failed
    Suspended
}

@Component
pack CognitionAgent {
    fin id: CognitionAgentId
    fin brain: CognitionSymbol
    var enabled: std::Bool
    var lod: std::Int
}

@Component
pack CognitionMemory {
    var facts: CognitionFactStore
    var revision: std::Long
}

pack CognitionFact {
    fin symbol: CognitionSymbol
    fin source: Entity
    fin value: CognitionValue
    fin confidence: std::Double
    fin observedAt: std::Double
    fin expiresAt: std::Double
}
```

All blackboard/fact/action keys are compiler or asset symbols. Two fields named
`target` in different brains are distinct. Runtime never resolves behavior by
string name.

## 4. Perception

Sensors include sight, hearing, damage, proximity, team communication, trigger,
and custom event sources. Sensors run at configurable fixed frequencies and use
batched Physics/World queries. Sight separates broad candidate discovery,
field-of-view, line of sight, visibility score, recognition time, and memory
decay. Hearing consumes authored noise events with position, loudness, spectrum,
source, and propagation policy.

Perception writes evidence; a fusion stage updates facts and emits acquired/lost
events. Raw candidate arrays do not become permanent per-agent allocations.

## 5. Environment queries

An EQS-like query asset generates candidate points/entities, filters them, scores
remaining candidates, and returns stable results. Generators include grid,
circle, navmesh, actor set, cover, path, and custom bounded generators. Tests
include distance, visibility, path cost, cover, slope, occupancy, threat, and
user facts. Queries are asynchronous, cancellable, budgeted, and inspectable.

## 6. Decision models

Behavior trees compile selectors, sequences, parallels, decorators, services,
waits, actions, and subtrees into a compact program. State machines provide
hierarchical states, guarded transitions, and entry/exit actions. Utility models
normalize considerations, combine curves, add inertia, and select actions with
stable tie-breaking. Planners operate only on declared symbolic facts/actions
with hard expansion/time limits.

All models produce action intent; they do not directly mutate arbitrary world
state during evaluation.

## 7. Actions

```azora
spec CognitionAction {
    func begin(context: CognitionContext!): CognitionStatus
    func update(context: CognitionContext!, dt: std::Double): CognitionStatus
    func cancel(context: CognitionContext!)
}
```

Action packs request capabilities such as move through Traverse, play through
Animation, use gameplay ability, aim, interact, or wait. Cancellation is
mandatory and idempotent. An action instance carries agent, node symbol,
generation, and local state; reused action names cannot collide.

## 8. Scheduling and LOD

Agents are partitioned into deterministic cohorts. High importance updates every
Cognition tick; lower tiers reduce perception frequency, decision frequency, query
quality, and animation detail while preserving critical reactions. Work uses
fixed budgets measured in candidates, node steps, query tests, and wall-time
guardrails. Starvation age raises priority.

Network servers run authoritative decisions. Clients may simulate cosmetic or
predicted intent but reconcile from replicated actions/facts. Replay records
inputs, random seeds, selected symbolic transitions/actions, and authoritative
events.

## 9. Diagnostics and delivery

The debugger shows active tree path/state, utility scores, facts with source and
age, sensor cones/rays, EQS candidates/scores, action lifecycle, budgets, LOD,
and reason codes for choices. Profiler counters include agents updated, node
steps, sensor candidates, ray/path queries, EQS tests, action time, budget
deferrals, and memory.

Delivery:

1. symbols, fact store, compiled behavior trees/state machines, action lifecycle.
2. utility scoring, deterministic random/ties, debugger, ECS schedule.
3. perception and bounded environment queries with Tilemap/Physics.
4. Traverse/Animation/gameplay adapters, cohorts, Cognition LOD, networking/replay.
5. planners, squads/shared knowledge, advanced cover/tactical queries, editor.
