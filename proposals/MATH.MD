# Azora Math — Vectors, Matrices, Rotations, and Numerical Conventions

Status: Proposal building on substantial generic math
Package: `azora-math`
Module: `engine.math`

## 1. Decision

`azora-math` owns portable numerical primitives and conventions used across the
engine: vectors, matrices, quaternions, transforms, projections, interpolation,
and numerically robust helpers. Physics owns collision/dynamics mathematics;
Render owns camera/render policy; Geometry systems own mesh algorithms.

The package must behave as value mathematics. Public operations cannot rely on
a convention that callers will avoid aliasing mutable pack instances. Either
the compiler provides value semantics for these declarations or Math returns
fresh immutable results and isolates all mutation behind exclusive borrows.

## 2. Current implementation audit

Implemented foundations include:

- generic `Vec<T, N>` for two through four components with generated arithmetic,
  indexing, conversion, length, dot, normalization, perpendicular, and cross;
- generic `Mat<T, R, C, O>` with row/column-major declaration order,
  element-wise operations, square multiplication, transpose, trace, and
  identity;
- aliases for common numeric vector and square-matrix forms;
- `Quat`, axis-angle/Euler construction, normalization, composition, vector
  rotation, matrix conversion, nlerp, and slerp.

Gaps and inconsistencies:

- `engine.math` does not currently re-export the vector/matrix/quaternion
  modules;
- comments promise value behavior while packs are reference-shaped at runtime;
- matrix product only supports same-shape square matrices;
- row/column storage order, vector convention, handedness, depth range, and GPU
  conversion are spread across comments and backend code;
- older engine packages still define overlapping vector/transform helpers;
- quaternion APIs mix methods and properties and do not consistently report
  zero-length input;
- inverse, determinant, affine decomposition, look/projection variants,
  orthonormalization, robust comparisons, and transform packs are missing;
- this package has no local tests despite broad engine dependence.

## 3. Canonical conventions

- right-handed 3D world coordinates;
- `+X` right, `+Y` up, and `-Z` camera-forward unless a subsystem explicitly
  converts at its boundary;
- column vectors for transform semantics;
- one documented matrix composition order independent of storage layout;
- radians for mathematical APIs, with explicit angle wrappers at ergonomic
  boundaries;
- meters as engine world convention, while Math itself remains unit-agnostic;
- no implicit degrees, handedness, or clip-depth conversion.

```azora
pack Radians {
    fin value: std::Double
}

pack Degrees {
    fin value: std::Double
}

pack Transform3 {
    fin translation: Vec3
    fin rotation: Quat
    fin scale: Vec3
}

error TransformFault {
    ZeroLength
    Singular
    NonFinite
    NonDecomposable
}
```

GPU adapters perform explicit storage/clip-space conversion. Serialized assets
record their source coordinate convention and are converted once on import.

## 4. API completion

Vectors add finite checks, min/max/clamp, lerp, reflect/refract, projection,
angle, robust normalization, and mask/select operations. Matrices add general
`R x C` by `C x K` multiplication, determinant/inverse for supported sizes,
affine inverse, basis extraction, look-at, orthographic/perspective variants,
and decomposition. Quaternions add inverse, shortest-arc construction,
log/exp/squad where useful, swing/twist, and robust normalization.

`Transform2` and `Transform3` become canonical shared math values. ECS Render
components may wrap them but do not define a second incompatible transform
representation.

## 5. Precision, SIMD, and determinism

Float is the default GPU/large-array storage. Double is used for long-lived
world coordinates, editor calculations, media/time conversions, and algorithms
that require range. Conversion is explicit.

Compiler intrinsics may vectorize operations while preserving scalar reference
results. Fast-math modes are opt-in capabilities because reassociation and
approximation can change deterministic simulation. Networking/Replay publish a
tested deterministic subset and quantization rules.

Non-finite values propagate through ordinary arithmetic but validation helpers
identify them at subsystem boundaries. Approximate equality always takes an
explicit absolute/relative tolerance.

## 6. Delivery and acceptance

1. make `engine.math` a real facade and document/enforce conventions;
2. resolve value/aliasing semantics and consolidate duplicate transform/vector
   declarations;
3. complete matrix, quaternion, transform, projection, and robust helper APIs;
4. add SIMD/compiler lowering and deterministic/fast profiles;
5. add property, differential, fuzz, and backend-layout tests.

Acceptance requires zero-allocation arithmetic, no shared-mutation surprises,
round-trip transform decomposition within tolerance, CPU/GPU matrix agreement,
randomized algebraic tests, explicit singular/zero failures, and identical
canonical conventions in Animation, Physics, Render, Camera, Tilemap, and XR.
