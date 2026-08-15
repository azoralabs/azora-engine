# Azora Networking — Replication, RPC, Prediction, and Servers

Status: Proposal
Primary package: `azora-networking`
Primary module: `engine.networking`

## 1. Decision

Networking is an authoritative simulation and replication framework over a
transport-provider boundary. It offers schema-generated messages, entity and
component replication, RPC/events, relevancy, snapshots, interpolation, client
prediction, server reconciliation, rollback, host migration policy, and
dedicated servers. Transport details do not leak into replicated gameplay APIs.

## 2. Current engine audit

No networking package, sockets, serializer schema, dedicated-server target,
rollback loop, or replicated component metadata exists. ECS has generational
entities, typed storages, revisions, events, commands, and a schedule—useful
foundations but local entity IDs cannot be sent directly. Input lacks action
commands and Physics lacks snapshots. Initial work must establish wire symbols,
schema compatibility, transport, and headless scheduling.

## 3. Package boundaries

```text
azora-networking-core      # schemas, packets, clocks, replication contracts
azora-networking-transport # UDP/QUIC/WebRTC providers
azora-networking-ecs       # entity/component replication and interest
azora-networking-rollback  # prediction snapshots and resimulation
```

The core depends on Engine Core/IO, not UI, rendering, Physics, or Cognition. Adapters
depend inward toward core.

## 4. Identity and schema

```azora
pack NetEntityId {
    fin value: std::Long
}

pack ConnectionId {
    fin value: std::Long
}

pack NetworkTick {
    fin value: std::Long
}

enum NetworkRole {
    Server
    Authority
    AutonomousProxy
    SimulatedProxy
}

@Component
pack Replicated {
    fin id: NetEntityId
    var owner: ConnectionId
    var role: NetworkRole
}

@Resource
pack NetworkClock {
    var localTick: NetworkTick
    var serverTick: NetworkTick
    var roundTripMillis: std::Double
    var jitterMillis: std::Double
}
```

Compiler-generated schemas assign stable symbols to packs, fields, variants,
RPCs, and events. Wire identity never uses source name alone or declaration
order. Handshakes exchange protocol, schema, content, build, and feature hashes.
Compatible optional fields can negotiate; incompatible authoritative schemas
fail before gameplay.

## 5. Transport channels

The public layer exposes message properties: reliable/unreliable, ordered/
sequenced/unordered, priority, deadline, congestion class, and maximum size.
Providers map these to UDP reliability, QUIC streams/datagrams, WebRTC data
channels, or platform services. Real-time state does not share an ordered stream
with bulk asset transfer because head-of-line delay is harmful.

Encryption, authentication, anti-replay, key rotation, path migration, MTU,
fragmentation, congestion control, and denial-of-service limits belong to the
provider/core boundary. QUIC is one provider option, not the gameplay API.

## 6. Replication

The server maps local entities to `NetEntityId`, computes relevancy per
connection, serializes baselines/deltas by component revision, quantizes fields,
and sends snapshots under a byte budget. Clients create/update/despawn replicas
through deferred commands and retain interpolation history.

Replication policy is field-specific: condition, owner-only, initial-only,
frequency, priority, quantization, interpolation, prediction, and reconciliation.
Collections use bounded delta formats. References use network symbols and resolve
late without confusing reused local entity generations.

## 7. Prediction, interpolation, rollback

Autonomous clients send quantized Input action commands by simulation tick,
predict selected components, retain bounded state/input history, and reconcile
against authoritative snapshots. Small errors smooth visually; simulation state
is corrected exactly. Resimulation executes only rollback-safe systems.

Simulated proxies interpolate buffered snapshots and may extrapolate under a
strict time/error cap. Camera/render interpolation is independent from network
authority. Physics/Vehicle expose snapshot and deterministic tiers; Networking
owns when to restore and resimulate.

## 8. RPC and authority

RPCs are schema symbols with direction, reliability, rate, payload, permission,
and validation. Client requests never imply authority. The server validates
ownership, state, cooldown, spatial plausibility, payload bounds, and rate before
creating gameplay commands. Cosmetic multicast is separate from replicated state.

## 9. Relevancy and large worlds

World supplies spatial cells, ownership, visibility layers, and streaming state.
Interest combines distance, cell subscription, team, owner, always-relevant,
dormancy, and application rules. Enter/leave hysteresis prevents churn. A client
receives required World/asset manifests before entities that depend on them.

## 10. Dedicated servers and observability

Headless builds omit GPU/UI/audio packages, use fixed simulation ticks, expose
graceful shutdown and health state, and produce Profiler traces. Metrics include
connections, packet/byte rates, RTT/jitter/loss, resend, queue age, snapshot
size, relevant entities, baseline hit rate, prediction error, rollback frames,
RPC rejects, and bandwidth per schema symbol.

## 11. Delivery

1. schema compiler, bit serializer, loopback/fake transport, ticks, handshakes.
2. encrypted UDP/QUIC-class provider, connections, channels, dedicated server.
3. ECS spawn/despawn/component replication, relevancy, snapshots/interpolation.
4. Input commands, prediction/reconciliation, Physics/Vehicle rollback adapters.
5. WebRTC/browser provider, replay capture, migration policy, security/fuzz suite.

Transport reference: [IETF QUIC RFC 9000](https://www.rfc-editor.org/rfc/rfc9000.html).
