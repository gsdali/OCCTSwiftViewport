# Spike — directly rendering B-Rep solids (skip the interstitial mesh body)

**Branch:** `spike/direct-brep-rendering` · **Status:** investigation only (no code changes) · 2026-06-21

> Question: can we render B-Rep solids "directly" without the interstitial step of building a
> `ViewportBody` mesh? How hard would it be?

## TL;DR

**It depends entirely on what "directly" means, and the two readings are wildly different in cost.**

A GPU never renders a B-Rep — it rasterizes **triangles** or traces rays. A B-Rep is analytic
surfaces (planes, cylinders, NURBS…) bounded by trimmed curves; **there is always a tessellation
step.** OCCT already does that step (`BRepMesh` → `Poly_Triangulation` per face, stored on the shape).
So "no mesh at all" is not a thing at the GPU. What *is* removable:

| Reading | What it removes | Difficulty | Worth it? |
|---|---|---|---|
| **A. Skip the redundant repack** — render straight from OCCT's existing triangulation | the `ViewportBody` interleave + `NormalSmoothing` + extra copy | **Low–Med (~2–4 days)** | Yes, as a perf/memory win |
| **B. True analytic GPU rendering** — tessellate trimmed NURBS on-GPU / ray-trace surfaces, no triangle mesh | the triangle mesh itself | **Very High (research-grade, weeks–months)** | Only with a hard driver |

**Recommendation:** pursue **A** as a bounded optimization if mesh-build cost or memory is the pain.
Treat **B** as a separate research epic — and note it structurally conflicts with this library's
"no B-Rep knowledge" design. If the real pain is *faceted-looking curves*, the existing GPU
PN-tessellation path already smooths silhouettes without any of this (see "Already shipped").

---

## Current pipeline (what actually happens today)

```
OCCT Shape (B-Rep: analytic faces + trim loops)
  │
  │  shape.mesh(...)                         ← OCCT BRepMesh_IncrementalMesh
  ▼
Poly_Triangulation per face   (stored ON the shape; this IS the mesh, computed once by OCCT)
  │
  │  OCCTSwift `Mesh` exposes .vertices / .normals / .indices (DE-interleaved)
  │  and even .metalBufferData() -> (positions: Data, normals: Data, indices: Data)
  ▼
OCCTSwiftTools.CADFileLoader.shapeToBodyAndMetadata(...)
  │   • loops every vertex, builds INTERLEAVED [px,py,pz,nx,ny,nz] (stride 6)   ← the "interstitial" repack
  │   • runs NormalSmoothing.smoothNormals(...)
  │   • packs faceIndices, edge polylines, pick verts
  ▼
ViewportBody  (vertexData:[Float], indices:[UInt32], …)   ← the "mesh body"
  │
  │  ViewportRenderer.ensureBuffers(for:) → MTLBuffer (vertex descriptor: stride-6 interleaved, buffer 0)
  ▼
GPU draws triangles
```

Two things are true at once:
1. The triangulation (the real "mesh") is **already computed by OCCT** and lives on the shape — it is
   not the viewport's doing, and it is unavoidable for raster rendering.
2. The **`ViewportBody` is a re-packaging** of data OCCT already has: it interleaves OCCT's separate
   position/normal arrays, re-smooths normals, and holds a second copy. *That* is the "interstitial
   mesh body" — and it is the only part genuinely removable without changing how GPUs work.

---

## The architectural constraint (the thing that shapes every answer)

`OCCTSwiftViewport` has **zero dependency on OCCT / B-Rep** — by design (CLAUDE.md: "the two
libraries are fully independent; OCCTSwiftViewport has no knowledge of OCCT or B-Rep topology").
`ViewportBody` is deliberately geometry-source-agnostic interleaved triangles; the kernel↔viewport
bridge lives in the consuming app / `OCCTSwiftTools`.

Any path where the **viewport itself** ingests B-Rep (analytic surfaces, trim loops) to render it
"directly" **breaks that layering**. This doesn't kill option B, but it means B is not just "hard
graphics" — it's also "re-architect the library's core contract." Option A can be done while keeping
the viewport OCCT-free (it's a buffer hand-off, not B-Rep knowledge).

---

## Option A — render from OCCT's existing triangulation (the achievable win)

**Idea:** stop rebuilding a `ViewportBody` from scratch. OCCT's `Mesh` already holds Metal-ready,
de-interleaved position/normal/index buffers (`Mesh.metalBufferData()`). Hand those to the renderer
directly.

**What it removes:** the per-vertex interleave loop, the `NormalSmoothing` pass (OCCT normals from a
fine mesh are already good for most faces), and one full CPU copy + its resident memory. **It does
NOT remove triangulation** — OCCT still meshes; you're cutting the *interstitial repack*, not the mesh.

**What would need to change (small, and layer-clean):**
- **Renderer:** add a vertex path that reads position and normal from **two separate buffers**
  (de-interleaved) instead of the stride-6 interleaved buffer. This is a second `MTLVertexDescriptor`
  (attribute 0 ← buffer 0 positions, attribute 1 ← buffer 1 normals) + a sibling pipeline. ~Half a
  day; the shaders are otherwise unchanged.
- **`ViewportBody`:** a new construction route that carries de-interleaved buffers (or wraps
  caller-provided `MTLBuffer`s) instead of `vertexData:[Float]`. Keep the existing interleaved init
  for hand-built/primitive bodies. The body stays geometry-source-agnostic — it just learns to hold
  "separate pos/normal/index" as an alternative to "interleaved."
- **Bridge (`OCCTSwiftTools`):** a thinner `shapeToBody` that forwards `mesh.metalBufferData()`
  straight through, skipping the interleave + smoothing.

**Cost/benefit:** Low–Medium effort (~2–4 days incl. tests). Benefit is CPU time on load and memory
for large/many-body scenes (relevant to the #42 scaling work) — **not** a visual change. Pick/edge/
measurement paths are unaffected (they already key off indices/faceIndices, which OCCT still provides).

**Caveats:** `NormalSmoothing` exists because OCCT's per-face normals are flat across a face boundary
on coarse meshes — dropping it can make low-deflection meshes look faceted. Gate smoothing on
deflection, or keep it as an opt-in. Interleaved-vs-separate buffers is a minor cache-locality
trade-off (negligible at these vertex counts).

---

## Option B — true "direct" analytic rendering (no triangle mesh)

Two sub-approaches, both hard:

### B1 — GPU tessellation of the (trimmed) parametric faces
Upload each face's surface control net + trim loops; tessellate the parametric domain on the GPU
(Metal tessellation or mesh shaders) and **discard fragments outside the trim loops**.

- OCCTSwift *does* expose the needed data: `Face.surfaceType` / `Surface` (bspline/bezier/analytic),
  `Surface.poles`, uv bounds, and `Face.outerWire` for trim. So it's *feedable*.
- **The trim is the killer.** Untrimmed-NURBS GPU tessellation is textbook; *trimmed* NURBS is a
  specialized research problem (trim-texture / pre-image point classification per fragment, robust
  seam handling, watertight edges between faces). This is a real "direct trimmed-NURBS rendering"
  research area, not a feature you bolt on.
- Plus: the viewport's existing GPU tessellation (`compute_pn_patches` / hardware tessellation) is
  **PN-triangle Phong tessellation — it refines an existing triangle mesh's silhouette**; it is *not*
  analytic-surface tessellation and gives no path to B1.

**Difficulty: Very High (weeks–months, research-grade). Also breaks the no-B-Rep layering.**

### B2 — analytic ray-traced primitives
Ray-march/intersect canonical surfaces (plane, sphere, cylinder, cone, torus) analytically in a
fragment shader.

- Only covers the handful of canonical analytic faces — **general B-spline faces still need
  tessellation**, so you end up with a hybrid renderer.
- Trimming still required; lighting/picking/clipping paths all need analytic variants.

**Difficulty: High, partial coverage. Niche** (e.g. perfect spheres/cylinders at infinite zoom).

---

## Already shipped (likely the real fix if the goal is "smoother curves")

If the motivation is "meshed curves look faceted," that's already addressed without any B-Rep
renderer: **adaptive PN-triangle Phong tessellation** refines a coarse mesh's silhouette on the GPU
(screen-space + curvature adaptive), exposed via `ViewportConfiguration.cadHighQuality` /
`renderingQuality == .enhanced`, plus `autoSmoothNormals` for crease-aware normals, and analytic
`ViewportArc` edges for true round edges. That gets ~90% of the "looks like a real B-Rep" benefit at
a tiny fraction of option B's cost.

---

## Recommendation

1. **If the pain is load time / memory** on big assemblies → do **Option A** (direct triangulation
   hand-off). Bounded, layer-clean, ~2–4 days. Frame it honestly as "render from OCCT's existing
   triangulation," not "no mesh."
2. **If the pain is visual smoothness** → lean on the **already-shipped** PN tessellation +
   `cadHighQuality` + analytic arcs; no new work.
3. **Option B (true analytic/trimmed-NURBS GPU rendering)** → only if there's a concrete driver that
   A and the shipped tessellation can't meet (e.g. exact-precision CAD zoom, or mesh memory is a hard
   ceiling). It's a research epic and a deliberate break from the viewport's OCCT-free design — scope
   it as its own project, not a tweak.

## Pointers (for whoever picks this up)
- Repack to remove: `OCCTSwiftTools/Sources/OCCTSwiftTools/CADFileLoader.swift` → `shapeToBodyAndMetadata` (the interleave loop + `NormalSmoothing`).
- Metal-ready source buffers already exist: `OCCTSwift/Sources/OCCTSwift/Mesh.swift` → `metalBufferData()` / `.vertices` / `.normals` / `.indices`.
- Renderer upload + vertex descriptor: `Sources/OCCTSwiftViewport/Renderer/ViewportRenderer.swift` → `ensureBuffers(for:)` (~L2467) and the stride-6 `MTLVertexDescriptor` (~L342).
- Existing GPU tessellation (NOT a B-Rep path): `Sources/OCCTSwiftViewport/Renderer/TessellationManager.swift` + `Shaders.metal` `compute_pn_patches` / `compute_tess_factors`.
- Analytic surface/trim data on the kernel side (for B1): `OCCTSwift/Sources/OCCTSwift/Face.swift` (`surfaceType`, `outerWire`), `Surface.swift` (`poles`, `trimmed`, uv bounds).
