# Azora Build — Cooking, Packaging, and Deployment

Status: Proposal evolving the current shell/Python build tools
Primary tool package: `azora-build`
Primary module: `tools.build`

## 1. Decision

Azora Build is a deterministic incremental build graph that compiles Azora code,
cooks the Assets dependency closure, compiles shaders for target capabilities,
links native providers, packages application/content bundles, signs where
required, and deploys to selected devices or servers. It is a host tool, not a
runtime engine dependency.

Platform defines runtime provider contracts. Build defines target profiles and
selects their implementations. Assets owns artifact cooking. Streaming consumes
the packaged manifests at runtime.

## 2. Current toolchain audit

`tools/azpm.py` reads `.azon` manifests, resolves package dependency closure from
imports, and reports source staging plus native frameworks/libraries.
`tools/build.sh` copies resolved Azora source into `.azora-build`, invokes the
bundled compiler to LLVM IR, and uses clang to link one macOS executable.
`tools/package.sh` builds a macOS runtime, bundles packages/compiler/templates,
and creates an `.azlib` zip.

This is a useful bootstrap but currently deletes/recreates staging, discovers
host tools ambiently, supports only macOS application linking, has no build DAG
or cache, target manifest, asset/shader cooking, application bundle/resource
layout, Windows/Linux/mobile/console packaging, signing, symbols, patching,
deployment, reproducibility record, or structured diagnostics.

## 3. Target model

```azora
variant enum BuildPlatform {
    Windows
    macOS
    Linux
    Android
    iOS
    Web
    Console(provider: ContentSymbol)
    Headless(provider: ContentSymbol)
}

enum BuildMode {
    Debug
    Development
    Profile
    Release
}

pack BuildTarget {
    fin id: ContentSymbol
    fin platform: BuildPlatform
    fin architecture: ContentSymbol
    fin mode: BuildMode
    fin graphics: ContentSymbol
    fin capabilities: std::Array<ContentSymbol>
    fin assetQuality: std::Int
    fin locales: std::Array<ContentSymbol>
}

pack BuildIdentity {
    fin product: ContentSymbol
    fin version: std::String
    fin buildNumber: std::Long
    fin sourceRevision: std::String
}
```

Targets are declared in AZON and can inherit one named profile with explicit
overrides. The fully resolved target is stored in build output. Platform names,
architectures, graphics APIs, SDK/toolchain versions, min OS, ABI, feature flags,
and content tiers are inputs to cache keys.

## 4. Build graph

Every operation is a typed node with declared input artifacts, output artifacts,
tool identity, environment whitelist, resource class, determinism policy, and
diagnostic stream. The initial graph is:

1. resolve package/source and plugin closure;
2. validate target/provider capabilities and licenses;
3. compile Azora modules to target objects and metadata;
4. import/cook Assets and transitive dependencies;
5. compile shader variants and pipeline archives;
6. link native engine/application/provider binaries;
7. assemble runtime/content bundles and Streaming manifests;
8. strip or split debug symbols according to mode;
9. sign/notarize/package using a target provider;
10. produce provenance, checksums, SBOM/license report, and patch metadata;
11. deploy/run/test when requested.

Nodes execute in parallel through a build scheduler distinct from the runtime
Jobs package. CPU, memory, I/O, GPU/tool licenses, and exclusive SDK resources
are bounded. Cancellation stops descendants and keeps complete cache artifacts.

## 5. Incrementality, cache, and reproducibility

Cache keys hash normalized declared inputs, compiler/tool versions, resolved
target, environment whitelist, and dependency artifact hashes. Absolute checkout
paths, wall-clock time, random iteration, and undeclared host environment do not
affect output. Archives and manifests have stable ordering and normalized
timestamps/permissions.

Local cache is content-addressed and checksummed. A remote cache is optional and
authenticated; outputs are accepted only for the exact toolchain/target key.
Secret-dependent signing nodes are intentionally not shared. Build can explain
why a node rebuilt by diffing input fingerprints.

Reproducibility is verified by clean double-build comparison for unsigned
artifacts. Platform signing/notarization timestamps are isolated in final
envelopes so deterministic payloads remain comparable.

## 6. Code compilation and package closure

The compiler consumes modules directly from resolved package roots rather than
flattening same-named source files into one staging directory. Module identity,
compiler symbols, generated serialization schemas, exports, native imports, and
ABI metadata become explicit artifacts. Incremental compilation invalidates by
semantic interface where safe and by implementation for dependent optimization.

Package manifests declare runtime, editor, build-only, test, and provider
dependencies separately. A build fails on cycles, duplicate module ownership,
missing native ABI, unsupported target features, or undeclared native libraries.
The facade package does not force unused systems into a minimal application.

## 7. Asset and shader cooking

Build asks Assets for the reachable closure from entry Scenes/Prefabs/resources
and always-include groups. It selects target/quality/locale/accessibility variants,
deduplicates content-addressed artifacts, validates hard dependencies, and emits
bundle placement plus Streaming ranges. Editor-only/source data is stripped by
policy.

Shader compilation begins from Azora shader IR, specializes declared variants,
validates Material layouts, produces backend binaries/reflection, and builds
pipeline caches where supported. Missing portable fallback or unbounded variant
explosion is a build diagnostic, not a runtime surprise.

## 8. Packaging by platform

- Windows emits architecture-correct executables/DLLs, resources, runtime
  dependencies, symbols, installer/archive, and optional code signing.
- macOS emits `.app` bundles, frameworks/dylibs, entitlements, universal slices
  where requested, symbols, code signing, notarization, and distributable image.
- Linux emits ELF binaries, declared shared libraries or portable bundle,
  desktop metadata where applicable, and debug symbols.
- Android emits ABI splits or app bundles/APKs, native libraries, manifest,
  resources, permissions, signing, and device install/run support.
- iOS emits application/framework bundles, provisioning/entitlements, device or
  simulator slices, assets, symbols, signing, and install/archive support.
- Web emits Wasm/JS loader, content chunks, cache manifest, compression metadata,
  and local serve/test support.
- Consoles use separately installed, access-controlled provider packages. Public
  engine code defines the contract but never fabricates proprietary SDK details.
- Headless emits server binaries and excludes graphics/audio/UI providers unless
  requested.

## 9. Deployment, patches, and CI

`azora build`, `cook`, `package`, `deploy`, `run`, `test`, `profile`, and
`explain` operate on one graph and target model. Deployment providers enumerate
authorized devices, install immutable packages, forward logs, launch with a
declared profile, and retrieve crash/profiler artifacts. They never choose a
device silently when several match.

Patch generation compares signed manifests by Asset/Artifact ID and code bundle.
It emits new immutable chunks plus a transactional manifest switch and rollback.
Live development deploy uses authenticated generation publication and remains
separate from a shipping update mechanism.

CI output includes structured diagnostics, test/cook reports, artifact hashes,
cache statistics, timings, symbols, provenance, licenses, and deployment result.
Build matrices share graph/cache work where target inputs match.

## 10. Security and secrets

Build tools run with least privilege and no ambient network unless a node
declares it. Importers and third-party tools are sandboxed. Response files and
logs redact secrets. Signing credentials come from OS keychains, CI secret
providers, or hardware tokens and are passed only to signing nodes. Generated
packages are checksummed before signing; dependency and license policies can fail
the build.

The graph rejects path traversal, symlink escapes, poisoned cache artifacts,
undeclared outputs, tool substitution, and target/provider mismatch. Remote
deployment requires explicit authorization and device identity.

## 11. Diagnostics, tests, and delivery

The build UI/CLI shows the critical path, node state, cache key/reason, target,
inputs/outputs, CPU/memory/I/O use, diagnostics, dependency graph, bundle size,
shader variants, asset closure, signing state, and reproducibility comparison.

Required tests include dependency cycles, same-named modules, incremental
interface changes, clean/cache equivalence, cancelled nodes, corrupt remote
cache, deterministic manifests/archives, cross-target variant selection, missing
SDK, signing redaction, bundle closure, patch rollback, and provider conformance.

Delivery:

1. typed target manifest, direct module compilation, graph executor, local cache,
   structured diagnostics, macOS parity;
2. Assets/shader cooking, bundle manifests, reproducibility/explain, symbols;
3. Windows/Linux/Web providers, package/archive layouts, CI matrices;
4. Android/iOS providers, device deployment, signing/provisioning adapters;
5. console provider contract, remote cache/build, patches, provenance hardening.
