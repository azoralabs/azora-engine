# Azora Genesis — Universal Digital Creature System

Status: Proposal building on Animation foundations
Primary package: `azora-genesis`
Primary module: `engine.genesis`
Domains: Body, Face, Skeleton, Skin, Hair, Fur, Eyes, Voice, DNA, Species,
Morph, and Rig

## 1. Decision

Azora Genesis is the engine's universal, data-driven creature platform. It
represents humans, animals, monsters, aliens, fantasy peoples, robots,
synthetic beings, and user-defined forms through one composable model instead
of separate humanoid, animal, and robot runtimes.

The twelve Genesis domains are public module contracts within one coordinated
platform. They are not twelve isolated packages or twelve competing asset
formats. A creature is compiled from species rules, a body plan, digital DNA,
authored overrides, and environmental state into an immutable phenotype asset.
Runtime entities reference that compiled asset and keep only changing pose,
expression, voice, damage, simulation, and customization state.

Genesis is not a second Animation, Material, Cloth, Audio, Physics, or
Cognition system:

- Genesis owns creature semantics, composition, compatibility, phenotype
  compilation, and creature-specific authoring.
- Animation owns pose evaluation, clip playback, IK execution, morph-curve
  evaluation, skin matrices, and retarget execution.
- Material owns surface shading and layered material graphs.
- Cloth owns simulated hair guides, fur guides, flesh accessories, and other
  secondary-motion constraints.
- Audio owns decoded/generated samples, voices, spatialization, effects, buses,
  and device output.
- Physics owns colliders, mass, ragdolls, contacts, and forces.
- Cognition owns perception, decisions, memory, and behavior.

This boundary allows Genesis creatures to use every engine subsystem without
turning Genesis into a monolithic replacement for the engine.

## 2. Current repository audit

There is no Genesis package or unified creature asset today. The strongest
foundation is `azora-animation-3d`, which already implements and tests:

- bone transforms, hierarchical skeletons, bind poses, world poses, and skin
  matrices;
- skeletal tracks and clips, pose blending, subtree masks, and root motion;
- morph-target animation;
- a first `AnimationRig`, two-input blend tree, and two-bone IK solver;
- skin influence normalization and CPU reference linear-blend skinning.

Those capabilities are reusable execution primitives, but they are currently
indexed largely by local array positions or display names. They do not yet
define semantic body regions, species, body-plan compatibility, DNA,
phenotypes, facial channels, eyes, grooms, fur, voice identity, or a control-rig
authoring contract. Stable symbols and import-time mappings must replace
name-based identity before Genesis builds on them.

Related engine state:

- Material is still a rendering placeholder, with a full layered-material
  proposal ready to host skin, eye, hair, and fur closures.
- Cloth has no implementation yet; its proposal already reserves guide-strand
  and follower-strand simulation for hair and fur.
- Audio has a PCM pool, buses, and effect contract, but no general procedural
  voice source or speech provider yet.
- Physics has tested 2D/3D primitives but no complete simulation world,
  articulated body, or ragdoll.
- Shard, Streaming, Cognition, Destruction, Decals, and XR are proposals rather
  than complete consumers.

The first Genesis milestone can therefore compile and inspect creature assets,
instantiate static or CPU-skinned creatures, and drive the existing Animation
runtime. High-density rendering and secondary simulation arrive incrementally.

## 3. Goals and non-goals

### 3.1 Goals

- One creature document for biological, fantastical, mechanical, hybrid, and
  entirely custom beings.
- Data-defined body plans rather than a humanoid-only class hierarchy.
- Stable semantic symbols for every body region, joint, morph, rig control,
  material region, voice, gene, and attachment.
- Deterministic DNA-to-phenotype compilation with reproducible random seeds.
- Non-destructive customization and safe hot publication of new generations.
- Shared animation, face, gaze, lip-sync, hair, fur, physics, audio, and render
  integration across all supported body plans.
- Scalable LOD for a hero face, a gameplay character, and a large crowd.
- Import from useful interchange formats without reducing the internal model to
  any one format's limitations.
- Explicit provenance, permissions, and consent for likeness and voice assets.
- Editor tools that expose compatibility failures before runtime.

### 3.2 Non-goals

Genesis does not own general animation clips, material graphs, cloth solving,
audio output, behavior trees, garment simulation, world population generation,
or game-specific character statistics. It does not claim that its digital DNA
is biological truth, ancestry inference, or medical genetics. It does not
require every species to have a face, skeleton, skin, hair, fur, eyes, voice,
sex category, age model, or bilateral symmetry.

## 4. Package and module layout

The platform begins as a small number of dependency-oriented packages:

```text
packages/
  azora-genesis-core/       # symbols, species, DNA, body plans, phenotype schema
  azora-genesis-runtime/    # ECS assembly, generations, LOD, customization
  azora-genesis-render/     # body/skin/eye/groom render bindings
  azora-genesis-animation/  # skeleton/morph/face/rig adapters to Animation
  azora-genesis-voice/      # optional voice and viseme provider contracts
  azora-genesis-editor/     # compiler, inspectors, sculpt/groom/rig tools
```

Public modules remain ergonomic and domain-oriented:

```text
engine.genesis
engine.genesis.body
engine.genesis.face
engine.genesis.skeleton
engine.genesis.skin
engine.genesis.hair
engine.genesis.fur
engine.genesis.eyes
engine.genesis.voice
engine.genesis.dna
engine.genesis.species
engine.genesis.morph
engine.genesis.rig
engine.genesis.editor
```

Applications normally import `engine.genesis`; the domain modules support
specialized tools and providers. The package split follows runtime dependency
and deployment needs, not marketing names.

## 5. Universal creature model

Genesis models a creature as a graph of semantic regions and capabilities. A
body plan may describe one or many roots, limbs, wings, fins, tails, tentacles,
shells, wheels, tracks, rigid modules, replaceable parts, or no conventional
skeleton at all.

Built-in topology families are convenience profiles, not closed classes:

```azora
enum GenesisKind {
    Human
    Animal
    Monster
    Alien
    Fantasy
    Synthetic
    Hybrid
    Custom
}

enum GenesisTopology {
    Humanoid
    Quadruped
    Avian
    Serpentine
    Aquatic
    Arthropod
    Tentacled
    Modular
    Amorphous
    Custom
}
```

A monster may use a humanoid topology with four arms; an alien may use a
quadruped skeleton and radial face; a synthetic being may mix rigid actuators,
soft skin, optical eyes, fur, and a generated voice. `GenesisKind` is browsing
metadata. Body-plan capabilities and stable symbols determine compatibility.

## 6. Stable identity and public runtime model

Display names are never identity. Every public relationship resolves through a
stable content symbol and is compiled into compact local indices for runtime
use. The same display name may legally identify different joints, genes,
morphs, or controls in different species and namespaces.

```azora
pack GenesisCreatureId {
    fin value: std::Long
}

pack GenesisSpeciesId {
    fin symbol: ContentSymbol
}

pack GenesisBodyPlanId {
    fin symbol: ContentSymbol
}

pack GenesisDnaId {
    fin symbol: ContentSymbol
}

pack GenesisPhenotypeId {
    fin symbol: ContentSymbol
}

pack GenesisRigId {
    fin symbol: ContentSymbol
}

@Component
pack GenesisCreature {
    fin id: GenesisCreatureId
    fin species: GenesisSpeciesId
    var phenotype: GenesisPhenotypeId
    var generation: std::Long
    var enabled: std::Bool
}

@Component
pack GenesisPhenotype {
    fin asset: GenesisPhenotypeId
    var lod: std::Int
    var visible: std::Bool
    var pendingGeneration: std::Long
}

@Component
pack GenesisExpressionState {
    var channels: GenesisChannelBlock
    var generation: std::Long
}
```

`GenesisCreatureId` identifies a runtime or saved individual.
`GenesisPhenotypeId` identifies shareable compiled appearance and deformation
data. Many crowd entities can share one phenotype while keeping independent
pose, expression, voice, damage, and behavior state.

## 7. Genesis Body

Genesis Body owns body-plan topology, semantic regions, proportions, attachment
sites, geometric variants, physical hints, and the compatibility envelope for
body morphs.

A body-plan asset contains:

- a directed region graph with one or more roots;
- semantic roles such as core, head, jaw, limb, digit, wing, tail, tentacle,
  wheel, sensor, actuator, and custom roles;
- side, radial-sector, ordinal, and parent relationships without encoding them
  in display names;
- topology families and seam-compatible mesh partitions;
- reference dimensions, proportion constraints, symmetry groups, and allowed
  asymmetry;
- render sections, material regions, collision proxies, sockets, garment
  anchors, camera anchors, and first-person visibility groups;
- capability tags for locomotion, manipulation, gaze, speech, breathing,
  modular replacement, and custom interactions.

Body geometry is compiled to ordinary render geometry owned by Render/Shard.
Genesis retains semantic region bindings and deformation metadata. Arbitrary
mesh topology is accepted for static creatures, but continuous morphing is only
guaranteed inside an explicitly compatible topology family.

## 8. Genesis Face

Genesis Face is a semantic expression layer that can drive morphs, bones,
material parameters, texture coordinates, eye controls, mechanical actuators,
or provider-defined outputs.

The face asset defines:

- semantic channels for brows, lids, gaze, cheeks, nose, jaw, lips, tongue,
  ears, antennae, mandibles, panels, lights, and custom regions;
- expression poses, additive action units, masks, priorities, exclusivity, and
  physically valid ranges;
- viseme sets mapped from phonemes and language profiles;
- blink, saccade, breathing, idle, emotion, speech, capture, and cinematic
  layers;
- asymmetry and per-side channels;
- capture profiles that map external channels to stable Genesis symbols.

The mixer combines authored animation, Cognition intent, gaze, lip sync,
capture, and gameplay overrides in a documented priority order. It emits a
semantic channel block; Genesis Morph and Genesis Rig translate that block to
the creature's actual controls. A creature with no conventional face can map
the same intent to emissive panels, antennae, or sound.

## 9. Genesis Skeleton

Genesis Skeleton adds creature semantics and compatibility metadata around the
Animation skeleton asset. Animation remains the owner of bone transforms,
poses, hierarchy evaluation, and skin matrices.

A Genesis skeleton profile provides:

- stable joint symbols and semantic roles independent of display names;
- parent graph, reference pose, bind pose, local axes, limits, preferred bend,
  twist distribution, scale policy, and mirror/radial relationships;
- locomotion and manipulation chains;
- optional, required, repeated, and provider-defined joints;
- rigid-module and synthetic-actuator metadata;
- LOD joint-remap tables and bounds;
- mapping to one concrete Animation `SkeletonId`.

No API assumes one root, two legs, five fingers, a neck, or human proportions.
Humanoid conveniences are profiles layered over the universal graph.

## 10. Genesis Skin

Genesis Skin owns creature skin appearance and its binding to body regions. It
does not replace Animation's existing `Skin`, which owns vertex-to-joint
influences for deformation.

The public creature asset is named `GenesisSkinProfile` to keep that distinction
clear. It composes:

- Animation skin-weight bindings and corrective deformation references;
- Material instances for epidermal, scaled, chitinous, translucent, wet,
  damaged, synthetic, painted, and custom surfaces;
- regional pigmentation, masks, scars, freckles, tattoos, seams, pores, veins,
  wear, damage, and age/environment overlays;
- thickness, subsurface, micro-normal, oil/wetness, temperature, and blood-flow
  channels where the selected Material provider supports them;
- stretch and wrinkle maps driven by pose, morph, expression, and contact.

Material is authoritative for the shading model. Genesis supplies semantic
parameters and region maps. Decals and Destruction supply transient damage;
those changes do not silently rewrite DNA.

## 11. Genesis Hair

Genesis Hair owns groom intent and authoring data:

- scalp or surface growth regions;
- guide curves, clumps, partings, braids, curls, length, density, width,
  melanin/color, wetness, and style layers;
- roots bound to body regions, skin triangles, or rigid modules;
- collision groups, simulation importance, cut/style masks, and LOD recipes;
- cards, shells, strands, or provider-defined rendering representations.

Cloth simulates selected guide strands. The renderer generates follower strands
or lower-cost cards. Material shades fibers. A short-hair creature may use no
simulation; a cinematic groom may use dense GPU followers. Style operations
are non-destructive layers over the base groom.

## 12. Genesis Fur

Genesis Fur uses the same groom infrastructure but adds body-wide, region-aware
coverage:

- density, length, direction, undercoat, guard hair, clumping, shedding,
  seasonal coat, wetness, dirt, and damage fields;
- pattern and color bindings from DNA and skin regions;
- sparse simulated guides with procedural followers;
- shell/card/strand fallback representations per LOD;
- contact flattening, wind, motion, and optional grooming state.

Hair and fur share low-level assets but remain separate semantic modules because
authoring, coverage, LOD, and gameplay operations differ. Fur does not require
every strand to be an ECS entity or a physics particle.

## 13. Genesis Eyes

Genesis Eyes supports biological eyes, compound eyes, cameras, optical sensors,
emissive lenses, and custom gaze organs. An eye profile contains:

- semantic eye/sensor symbols and pairing or radial-group relationships;
- geometry for globe, cornea/lens, iris, pupil, sclera, lids, tear line, and
  provider-defined parts;
- optical/material parameters, pupil response, focus hints, wetness, and
  dilation limits;
- gaze origin, forward axis, convergence, dominance, limits, saccades, blink
  binding, and occlusion behavior;
- first-person camera and XR visibility policy;
- accessibility overrides that never require simulated biological behavior.

Gaze intent is semantic. Genesis Rig chooses bone, morph, UV, mechanical, or
material controls for each creature. Lighting and Material own illumination and
shading; Cognition and Camera may request targets.

## 14. Genesis Voice

Genesis Voice describes a creature's voice identity and speech-performance
mapping without owning the audio mixer or device:

- phoneme inventory, language profiles, viseme map, pitch/range, timbre,
  prosody, breath/noise layers, effort, emotion, and synthetic modulation;
- captured-voice, sample-bank, procedural, speech-synthesis, and custom
  provider capabilities;
- deterministic timing markers for phonemes, words, visemes, breaths, and
  events;
- routing to an Audio source and voice bus;
- provenance, consent, allowed uses, expiration, and redistribution policy.

```azora
pack GenesisVoiceId {
    fin symbol: ContentSymbol
}

pack GenesisSpeechRequest {
    fin voice: GenesisVoiceId
    fin text: std::String
    fin language: ContentSymbol
    fin emotion: ContentSymbol
    fin seed: std::Long
}

enum GenesisSpeechMarkKind {
    Phoneme
    Word
    Viseme
    Breath
    Event
}

pack GenesisSpeechMark {
    fin kind: GenesisSpeechMarkKind
    fin symbol: ContentSymbol
    fin start: MediaTime
    fin duration: MediaTime
}

pack GenesisSpeechResult {
    fin audio: AudioSource
    fin marks: std::Array<GenesisSpeechMark>
    fin duration: MediaTime
}

spec GenesisVoiceProvider {
    func supports[self: Self&](voice: GenesisVoiceId&): std::Bool
    func synthesize[self: Self!](request: GenesisSpeechRequest&): GenesisSpeechResult ?! GenesisFault
}
```

Generation runs off the real-time audio thread. Completed samples enter Audio's
normal bounded voice path. Lip sync consumes returned marks or an Audio analysis
provider. Genesis never clones a person's voice merely because an audio sample
is available.

## 15. Genesis DNA

Genesis DNA is a deterministic digital parameter graph. It is a creative and
technical representation, not a claim about real genetics, ancestry, health,
or identity.

```azora
enum GenesisGeneSource {
    Inherited
    Authored
    Mutated
    Generated
    Imported
}

variant enum GenesisGeneValue {
    Scalar(value: std::Double)
    Integer(value: std::Int)
    Toggle(value: std::Bool)
    Choice(value: ContentSymbol)
    Vector(value: Vec4)
}

pack GenesisGene {
    fin locus: ContentSymbol
    fin value: GenesisGeneValue
    fin source: GenesisGeneSource
}

pack GenesisDna {
    fin id: GenesisDnaId
    fin species: GenesisSpeciesId
    fin seed: std::Long
    fin schemaRevision: std::Int
    fin genes: std::Array<GenesisGene>
}
```

Each species defines loci, ranges, distributions, dependencies, dominance or
blend policy, mutation policy, compatibility constraints, and phenotype
outputs. The compiler resolves the graph in stable symbol order and records the
source of every result for inspection.

Age, nutrition, injury, expression, clothing, dirt, styling, and temporary
gameplay effects are phenotype/environment layers, not genes. Synthetic beings
use the same mechanism as a design genome: chassis dimensions, actuator count,
sensor layout, finish, firmware-visible expression controls, and modular parts
can all be loci without pretending to be biology.

Inheritance and mutation are optional library operations. Applications choose
whether they exist and whether they are authoritative. No default algorithm
hard-codes human social categories or stereotypes into appearance or behavior.

## 16. Genesis Species

A species asset is a versioned rule set, not a hard-coded language class. It
declares:

- kind, body-plan profiles, supported topology families, units, and scale;
- DNA schema and phenotype graph;
- required and optional body regions, joint roles, face channels, eyes,
  appendages, grooms, voice capabilities, and synthetic modules;
- compatible meshes, morph sets, skeletons, rigs, skins, materials, and LODs;
- legal ranges and cross-domain constraints;
- default assets, fallback assets, migration rules, and content provenance;
- capability tags used by Animation, Traverse, Cognition, Physics, Camera, XR,
  UI, and gameplay.

Species may derive from templates and compose reusable capability packs, but
compiled assets flatten inheritance and reject ambiguous overrides. The Foliage
system's vegetation species remain owned by Foliage; Genesis IDs are distinct
and cannot collide by display name.

Subspecies, breeds, fantasy peoples, product lines, and cast-specific bases are
content-defined variation profiles. The runtime does not assign social meaning
or behavior from an appearance category.

## 17. Genesis Morph

Genesis Morph owns semantic shape intent, compatibility, and corrective
relationships. Animation owns time-varying morph weights and the renderer owns
the deformation pass.

A morph asset provides:

- a stable symbol, semantic region, compatible topology family, value range,
  default, and symmetry policy;
- sparse position, normal, tangent, UV, material, or provider-defined deltas;
- body, face, muscle, corrective, phoneme, damage, age, and synthetic actuator
  categories;
- dependencies, exclusions, driven correctives, normalization groups, and
  collision/bounds deltas;
- LOD remaps and a bake policy.

The phenotype compiler solves constrained morph values before generating final
bounds and simulation proxies. It rejects impossible topology mixtures instead
of producing torn or self-intersecting geometry silently. Runtime expression
morphs remain sparse and bounded; static body morph combinations may be baked
into a shared phenotype mesh.

## 18. Genesis Rig

Genesis Rig is the semantic control layer between intent and Animation's
execution graph. It defines:

- control symbols, spaces, shapes, ranges, defaults, grouping, and UI metadata;
- control-to-joint, morph, material, eye, groom, and synthetic-actuator
  mappings;
- FK/IK switches, goals, poles, constraints, limits, twist, stretch, contact,
  look-at, facial, and full-body relationships;
- source/target retarget profiles expressed through semantic chains;
- motion-capture and facial-capture mappings;
- rig LOD and bake rules.

Animation compiles and evaluates the resulting control/constraint graph. A
Genesis rig never performs string lookup in the frame loop. Import maps names
and paths once to stable symbols, reports ambiguity, and stores resolved symbol
uses. This permits identical names in different rigs or scopes without sending
motion to the wrong control.

## 19. Phenotype compilation

The compiler transforms authored inputs into a runtime-safe generation:

1. resolve the species revision, body plan, DNA schema, and content symbols;
2. validate requested genes and authored overrides;
3. evaluate deterministic gene and constraint graphs;
4. select one compatible topology family and body-part set;
5. solve static body/face morphs and driven correctives;
6. map the semantic skeleton and rig to Animation assets;
7. bind Animation skin weights and generate deformation bounds;
8. compile skin, eye, hair, fur, and material region bindings;
9. generate Physics proxies, Cloth attachments, sockets, and visibility groups;
10. compile voice/viseme and expression mappings;
11. derive all LOD tiers and streaming manifests;
12. validate provenance and usage policy;
13. publish one immutable, content-addressed phenotype generation.

Compilation is asynchronous, cancellable, cacheable, and transactional. A
failed build leaves the currently published phenotype untouched. The result
records source asset revisions, compiler version, seed, dependency symbols,
diagnostics, and a reproducibility hash.

## 20. Runtime schedule and ECS integration

The frame schedule is explicit:

1. publish completed phenotype generations at a frame boundary;
2. resolve LOD and resident data;
3. update Animation clocks and sample base poses;
4. evaluate Genesis Rig controls, retargeting, IK, and constraints;
5. mix face, gaze, blink, capture, expression, and speech visemes;
6. apply runtime morphs and pose correctives;
7. exchange authoritative targets with Physics and apply ragdoll blending;
8. update Cloth hair/fur guides and other secondary motion;
9. build final skin matrices, morph buffers, bounds, and motion vectors;
10. submit body, eye, skin, hair, and fur render instances.

```azora
@System(.Update)
func updateGenesisCreatures(
    q: @query [GenesisCreature!, GenesisPhenotype!] @with Render @without Disabled
) {
    for [creature!, phenotype!] in q {
        if creature.enabled {
            phenotype.pendingGeneration = creature.generation
        }
    }
}
```

Systems query only the components they access. Jobs receive immutable phenotype
assets and disjoint instance-state ranges. Publication uses generations so no
job observes half of an updated creature.

## 21. Customization and editor ergonomics

Customization uses a transaction over DNA, phenotype layers, and authored
overrides. A transaction can preview at low LOD, report constraints immediately,
compile expensive outputs asynchronously, compare before/after, undo, redo, and
commit only a valid generation.

Editor surfaces include:

- body and face sculpt controls generated from stable morph metadata;
- DNA inspector with ranges, dependency explanations, locks, seeds, and result
  provenance;
- body-plan graph, skeleton mapper, skin-weight painter, and rig graph;
- expression/viseme mixer and live capture monitor;
- hair/fur groom editor with guide, density, flow, clump, and LOD tools;
- eye and gaze calibration;
- voice audition and timing/viseme inspection;
- topology, bounds, collision, deformation, material, and streaming validation;
- side-by-side LOD and platform-provider previews.

The editor labels unsupported combinations before compilation and offers
compatible alternatives. It never silently drops body parts, controls, genes,
or licensing metadata.

## 22. Import, export, and interchange

Import is adapter-based and preserves the source document plus a diagnostic
mapping report. Initial profiles are:

- glTF 2.0 for meshes, skins, joint animation, and morph-target deltas;
- VRM 1.0 for runtime-loadable humanoid avatars, expressions, gaze, humanoid
  mappings, first-person metadata, and spring-bone conversion;
- OpenUSD/UsdSkel for production skeleton, skinning, animation, blend-shape,
  hierarchy, instancing, and scene-pipeline interchange;
- MaterialX bindings for portable material networks where Material supports
  the represented nodes;
- provider adapters for DCC-specific rigs, capture formats, grooms, and voice
  metadata.

VRM is an important humanoid profile, not the Genesis data model: its humanoid
bone assumptions cannot represent every animal, alien, monster, synthetic, or
custom body plan. Imported spring bones map to Cloth guide constraints where
possible. Unmapped source data remains attached as namespaced metadata and is
reported rather than discarded.

Export declares its loss model. A target that cannot represent DNA graphs,
semantic regions, licenses, custom controls, materials, or procedural grooms
must either bake them, preserve an extension, or require explicit approval for
loss.

## 23. Engine integrations

- **Animation:** skeleton assets, poses, clips, graphs, skin matrices, morph
  curves, IK/constraint execution, retarget execution, and root motion.
- **Material:** skin, eye, tooth, horn, shell, hair, fur, synthetic, wetness,
  damage, and emissive surface graphs.
- **Shard and Streaming:** geometry pages, phenotype generations, textures,
  clips, grooms, and LOD residency.
- **Cloth:** guide strands, fur guides, loose tissue/accessories, and collision.
- **Physics:** colliders, mass properties, articulated ragdolls, contacts, and
  physical pose blending.
- **Cognition:** gaze, expression, speech, locomotion, and action intent; never
  species-derived personality defaults.
- **Traverse:** locomotion capabilities, dimensions, stance, links, and dynamic
  traversal constraints.
- **Audio:** generated/captured voice playback, spatialization, effects, and
  analysis for lip sync.
- **Aether and Fluids:** wind, wetness, temperature, buoyancy, breathing, coat,
  and environmental response inputs.
- **Destruction and Decals:** detachable synthetic/creature parts, wounds,
  scars, dirt, and temporary appearance layers.
- **Networking and Replay:** authoritative customization, pose/intent policy,
  phenotype hashes, and deterministic event records.
- **XR and Camera:** gaze targets, first-person visibility, eye height, tracked
  rig mapping, and avatar embodiment.
- **Cinematics:** high-quality face, voice, groom, morph, and rig tracks.
- **Procedural:** population and cast generation from Genesis constraints;
  Genesis remains owner of individual creature validity.

## 24. LOD, streaming, and performance

Every phenotype compiles coordinated LOD tiers rather than allowing each domain
to switch independently and tear the creature apart. A tier may reduce:

- mesh and Shard detail;
- active bones, rig constraints, IK chains, pose frequency, and skin influences;
- body/face morph count and corrective complexity;
- eye geometry, refraction, gaze, blink, and tear detail;
- hair/fur guide count, followers, simulation, shadows, and material complexity;
- skin layers, wrinkles, subsurface quality, and decals;
- voice procedural layers and analysis detail;
- Physics bodies and Cloth collision shapes.

Hero tiers preserve facial timing and silhouette. Crowd tiers share phenotype
assets, batch Animation evaluation, instance materials, use palette/morph
atlases, and update off-screen state at reduced rates. Gameplay-authoritative
colliders, root motion, interaction anchors, and network state never silently
change with visual LOD.

Streaming keeps a small creature header resident: IDs, bounds, fallback mesh,
skeleton/rig header, material fallback, and dependency manifest. Publication is
generation-atomic. Missing high-detail pages render a declared lower tier;
missing authoritative data blocks activation with a visible diagnostic.

## 25. Determinism, save, networking, and replay

Save data stores stable symbols, species/schema revisions, DNA values, authored
overrides, phenotype hash, seeds, and explicit runtime layers. It never stores
transient entity IDs, array offsets, GPU addresses, job handles, provider
objects, or display names as identity.

Networking can choose among three policies:

1. replicate DNA and overrides, then compile locally against an exact content
   manifest;
2. distribute an approved compiled phenotype generation;
3. replicate a stable phenotype reference already present on every peer.

Servers validate content policy, ranges, budgets, and compatibility before
accepting customization. Replay records authoritative intent, state-machine
symbols, DNA/customization transactions, root motion, expression events, and
voice event identity according to the selected determinism tier. It does not
require recording every skinned vertex or hair strand.

## 26. Safety, identity, provenance, and privacy

Creature tools can process likeness, facial capture, motion, and voice—data that
may be personal, sensitive, licensed, or dangerous to misuse. Genesis therefore
makes provenance and permissions executable asset metadata.

Each imported or generated asset can declare creator/source, license, allowed
contexts, modification permission, redistribution permission, attribution,
commercial policy, synthetic-media disclosure, personification restrictions,
expiration, and revocation reference. Build and export policy can reject an
incompatible use.

The platform also requires:

- explicit consent for identifiable likeness and voice cloning;
- local/private processing modes and retention controls for capture data;
- no automatic ethnicity, health, disability, personality, intelligence, or
  behavior inference from appearance or voice;
- content moderation hooks without hard-coding one application's policy into
  the asset format;
- audit trails for imports, generated assets, edits, and exports;
- visible disclosure metadata for synthetic people where required by product
  policy or law.

These fields complement rather than replace legal review. Unknown provenance is
a first-class state, not implicit permission.

## 27. Errors and capability fallback

```azora
error GenesisFault {
    UnknownSpecies(symbol: ContentSymbol)
    SchemaMismatch(expected: std::Int, actual: std::Int)
    UnknownSymbol(symbol: ContentSymbol)
    AmbiguousMapping(symbol: ContentSymbol)
    IncompatibleBodyPlan(bodyPlan: GenesisBodyPlanId)
    IncompatibleTopology(symbol: ContentSymbol)
    ConstraintViolation(symbol: ContentSymbol)
    MissingRequiredAsset(symbol: ContentSymbol)
    ProviderUnavailable(symbol: ContentSymbol)
    BudgetExceeded(symbol: ContentSymbol)
    ProvenanceRejected(symbol: ContentSymbol)
    CompilationCancelled
}
```

Capabilities are queried for renderer, GPU deformation, strand simulation,
voice generation, capture, material features, Physics articulation, and import
formats. Every optional provider has a declared fallback: lower LOD, baked
asset, CPU reference, static pose, sample-bank voice, or explicit unsupported
error. Genesis never silently changes creature identity to satisfy a provider.

## 28. Diagnostics and profiler integration

The Genesis inspector shows:

- species/body-plan graph and stable symbols;
- DNA source values, solved values, constraints, and phenotype outputs;
- topology family, body regions, mesh sections, materials, and attachments;
- skeleton roles, unmapped joints, rig controls, IK errors, retarget chains,
  morph weights, and corrective activation;
- face layers, gaze targets, visemes, capture mappings, and voice marks;
- skin regions, eye setup, hair/fur guides, Cloth/Physics bindings, and bounds;
- current/desired LOD, resident pages, generation, fallbacks, and compile hash;
- provenance and export-loss warnings.

Profiler counters include active creatures, shared phenotypes, compile/cache
hits, compile latency, DNA nodes, active bones, morphs, correctives, rig solve
time, face solve time, skinning CPU/GPU time, groom guides/followers, Cloth time,
voice generation latency, eye/gaze cost, draw/instance counts, streamed bytes,
LOD transitions, fallback frames, and per-domain memory.

## 29. Testing strategy

The conformance suite covers:

- stable-symbol resolution with duplicate display names in different scopes;
- single-root, multi-root, limbed, radial, serpentine, modular, amorphous, and
  skeleton-free body plans;
- deterministic DNA compilation and migration across schema revisions;
- constraint failures, cancellation, cache keys, and atomic publication;
- topology/morph compatibility and corrective activation;
- skeleton semantics, skin bindings, retargeting, rig solving, and LOD remaps;
- face mixing, gaze, blink, phoneme/viseme alignment, and non-facial expression;
- hair/fur root binding, simulation fallbacks, and coordinated LOD;
- Material, Animation, Cloth, Physics, Audio, Streaming, Networking, Replay, XR,
  and Cinematics integration contracts;
- import round trips, preserved unknown data, explicit export loss, and
  provenance enforcement;
- fuzzing of malformed graphs, invalid indices, cycles, extreme dimensions,
  hostile asset sizes, and decompression budgets;
- golden phenotype hashes and visual/deformation regression scenes.

Reference creatures must include a human, quadruped animal, winged creature,
serpentine monster, radial alien, fantasy humanoid, rigid robot, soft synthetic,
hybrid creature, and a custom non-skeletal organism.

## 30. Delivery plan

### Phase 1 — Creature foundation

- stable symbols, species/body-plan schemas, DNA values, phenotype compiler;
- static mesh/material assembly and ECS components;
- current Animation skeleton/skin/morph adapter;
- deterministic tests, inspector, serialization, and glTF import baseline.

### Phase 2 — Animation-ready creatures

- semantic skeletons, rig controls, retarget profiles, face channels, eyes,
  expressions, gaze, visemes, and runtime morph correctives;
- compiled Animation integration, GPU skin/morph path, bounds, and coordinated
  LOD;
- humanoid conveniences and VRM import profile.

### Phase 3 — Appearance and simulation

- layered Genesis skin bindings, eye materials, hair/fur groom assets;
- Cloth guides/followers, Physics ragdolls/colliders, Aether/Fluids response;
- Shard/Streaming residency, crowd sharing/instancing, editor sculpt/groom/paint
  tools.

### Phase 4 — Voice and connected runtime

- voice provider contract, procedural/sample/speech sources, Audio routing,
  phoneme marks, lip sync, capture adapters, and consent/provenance enforcement;
- Cognition, Traverse, XR, Networking, Replay, and Cinematics integration;
- OpenUSD/UsdSkel and MaterialX pipeline adapters.

### Phase 5 — Production platform

- advanced full-body and non-humanoid rigs, muscle/flesh correctives, dense
  cinematic grooms, modular synthetic beings, destructive body layers;
- distributed phenotype build cache, platform quality certification, content
  migration tools, and cross-DCC validation.

## 31. Acceptance criteria

Genesis is production-ready when:

1. all ten reference creatures compile through the same public model;
2. duplicate names cannot misbind joints, genes, morphs, controls, or uses;
3. a DNA/customization transaction either publishes one valid generation or
   leaves the previous generation untouched;
4. Animation drives semantic skeleton, rig, morph, face, and eye outputs without
   frame-loop string lookup;
5. visual LOD never changes authoritative gameplay state;
6. a crowd shares phenotype data while preserving individual runtime state;
7. absent optional features and providers use explicit, testable fallbacks;
8. import/export reports every unsupported or lossy mapping;
9. likeness and voice assets carry enforceable provenance/permission metadata;
10. every domain exposes debug views, counters, budgets, and conformance tests.

## 32. Standards alignment

Genesis uses standards as interchange contracts, not as its universal internal
schema:

- [glTF 2.0](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html) defines
  portable mesh, skin, joint, animation, and morph-target foundations.
- [VRM features](https://vrm.dev/en/vrm/vrm_features/) define a useful humanoid
  avatar profile covering pose, expression, gaze, first-person setup, and
  spring bones.
- [OpenUSD UsdSkel](https://openusd.org/release/api/usd_skel_page_front.html)
  provides production interchange for skeletons, skinning, animation, blend
  shapes, bindings, and instancing.
- [MaterialX](https://materialx.org/Specification.html) provides a portable
  material-network interchange target for supported skin, eye, hair, fur, and
  synthetic surface nodes.

Azora extensions carry universal body-plan semantics, DNA, species,
provenance, voice, rig controls, coordinated LOD, and any source data those
formats cannot represent.
