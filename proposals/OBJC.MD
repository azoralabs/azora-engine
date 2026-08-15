# Azora Objective-C Bridge — Typed Apple Runtime Interop

Status: Proposal hardening an implemented FFI bridge
Package: `azora-objc`
Module: `engine.objc`

## 1. Decision

`azora-objc` is an internal Apple-provider foundation. It owns Objective-C
runtime lookup, selector/class caching, typed message trampolines, object
ownership helpers, autorelease scopes, exported-symbol lookup, and ABI tests.
It is not re-exported by the public `engine` facade.

Public Platform, GPU, Audio, Video, Font, and XR APIs never expose Objective-C
handles or selectors. Provider packages translate native failures and lifetime
into engine-owned contracts.

## 2. Current implementation audit

The package already bridges class/selector lookup, generic `objc_msgSend`,
autorelease pools, double/float and by-value pair/quad/region trampolines,
exported symbols, simple `send0` through `send4`, object construction,
`NSString` conversion, and exported object constants.

Current risks and gaps:

- objects, selectors, classes, pointers, and integers are all raw `Long`;
- ownership is implicit and retain/release/autorelease balance is caller policy;
- arbitrary generic message sends can use the wrong ABI signature;
- class and selector lookup repeats and has no typed cache;
- `NSString` conversion relies on raw casts and borrowed lifetime assumptions;
- errors/exceptions and nullable results are not represented explicitly;
- source imports raw memory helpers through `engine.io` without declaring that
  dependency;
- only current arm64/macOS paths are exercised and there are no package tests.

## 3. Internal typed handles

```azora
enum ObjcOwnership {
    Borrowed
    Retained
    Autoreleased
}

pack ObjcClass {
    fin handle: std::Long
}

pack ObjcSelector {
    fin handle: std::Long
}

pack ObjcObject {
    fin handle: std::Long
    fin ownership: ObjcOwnership
}

error ObjcFault {
    MissingClass
    MissingSelector
    MissingSymbol
    NullObject
    InvalidSignature
    NativeFailure
}
```

These declarations remain internal. Distinct wrappers stop accidental use of a
selector as an object or an integer as a pointer. Owned wrappers have explicit
retain, transfer, autorelease, and release operations; borrowed wrappers cannot
be released.

## 4. Message signatures and generation

Engine source calls named typed helpers generated from a small signature
description. Each helper chooses the exact ABI trampoline for return and
argument layout. The unrestricted raw `objc_msgSend` bridge remains private to
generated code.

Selector/class caches are immutable after insertion and keyed by stable string
content. Framework bindings can be generated from reviewed declarations,
including nullability, ownership conventions, enum constants, structures, and
availability. Generated bindings remain thin and keep engine policy in provider
packages.

## 5. Lifetime, errors, and threading

Every engine-created Apple thread enters an autorelease scope. Frame scopes,
worker scopes, and long-lived retained objects are distinct. GPU completion and
media decode callbacks keep objects alive until the native operation finishes.

Objective-C exceptions do not cross Azora frames. Provider boundaries convert
recoverable native errors to engine faults and treat programmer/ABI exceptions
as fatal diagnostics. Main-thread-only APIs are annotated and asserted in
debug builds.

## 6. Layering and portability

Raw allocation/peek/poke primitives move to a minimal runtime FFI module or
become declared low-level dependencies; Objective-C does not import filesystem
I/O for memory access. The package compiles only for compatible Apple targets.
Other platform builds exclude it completely.

## 7. Testing and delivery

Tests cover every trampoline signature, 32/64-bit integer and float returns,
pair/quad/region passing, nullable values, UTF-8 conversion, retain/release,
autorelease scopes, missing symbols, selector caches, thread affinity, and
framework availability on supported architectures.

Delivery:

1. introduce internal typed wrappers and explicit ownership;
2. isolate raw message send and generate signature-correct helpers;
3. split raw runtime memory from I/O and fix package dependencies;
4. add caches, availability/nullability, diagnostics, and conformance tests;
5. migrate Platform/GPU/Audio/Video/Font providers and remove public re-export.

Acceptance requires no raw Objective-C handle in application APIs, no
signature-ambiguous call site, balanced ownership under stress, architecture
conformance, and zero Objective-C dependency in non-Apple builds.
