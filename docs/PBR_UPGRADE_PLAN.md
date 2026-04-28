# PBR Upgrade Plan — OCCTSwiftViewport

Inspiration: [CADRays](https://github.com/Open-Cascade-SAS/CADRays). The plan goes beyond CADRays by anchoring on current state-of-the-art rather than porting OCCT's GLSL path tracer.

## State-of-the-Art Research Summary

Four BRDF specifications evaluated. Disney/Burley 2012 (UE5) has 11 parameters and is implementation-heavy; sheen/anisotropy/subsurface aren't useful for CAD. Pixar/MaterialX OpenPBR (2024) is the most physically accurate but requires an MX-shader graph evaluator; overkill for engineering visualization. Filament's "Standard" model is excellent and well-documented (Romain Guy's *Physically Based Rendering in Filament*, 2018-2024) but is its own dialect, not an interop standard. **glTF 2.0 PBR Metallic-Roughness + KHR_materials_clearcoat + KHR_materials_emissive_strength + KHR_materials_ior** is the right pick: industry interop spec, identical math to what's already in `Shaders.metal` (Cook-Torrance with GGX/Smith correlated/Schlick) — clearcoat is the only new lobe.

For TAA + idle accumulation: Karis 2014 ("High Quality Temporal Supersampling", SIGGRAPH course), Salvi 2016 ("An Excursion in Temporal Supersampling", GDC), and the practical Filament/Eevee/Marmoset accumulator pattern. Right strategy for a CAD viewport is *two-mode TAA*: standard 0.9-blend TAA while moving, unbounded sample-count progressive accumulator (1/N blend) with deeper jitter while idle, plus optional ray-traced AO via `MTLAccelerationStructure` (macOS 12+ / iOS 15+ — universal at our iOS 18/macOS 15 minimum).

For materials editor UX: Sketchfab's web editor and Substance Painter converge on the same pattern — per-body assignment, sphere preview at the top, sliders below, presets across the top. SwiftUI `Form`+`Slider`+`ColorPicker` is the Apple-native equivalent.

For HDR loading: Apple's `MTKTextureLoader` doesn't read Radiance `.hdr`. Ship a tiny RGBE parser (~80 lines of Swift) plus optional `.exr` via `Image I/O`'s OpenEXR support (macOS 14+/iOS 17+ via `kCGImageTypeOpenEXR`). Pre-converted `.ktx2` is overkill for a CAD viewport since this is a "set once" choice.

## Existing Codebase — Critical Findings

- TAA scaffolding already exists (`taa_resolve_fragment`, `TAAParamsSwift`, `enableTAA`, halton jitter, `lastCameraState`) **but jitter is not applied to `viewProjectionMatrix`** — only sampled history-relative. Half-built and ghost-prone.
- IBL infrastructure with split-sum: `equirect_to_cubemap`, `prefilter_environment`, `irradiance_convolution`, `brdf_integration` compute kernels exist and are correct. Background isn't drawn, no rotation, environmentMapData is raw `[w][h][rgba32f bytes]` — no `.hdr` parser.
- `BodyUniforms` has only roughness/metallic — no clearcoat, IOR, emissive, normal map.
- Shaders use Cook-Torrance correctly (GGX/Smith/Schlick) — clearcoat is purely additive, not a rewrite.
- iOS 18 / macOS 15 minimum means `MTLAccelerationStructure` is universal (Simulator excepted).

---

## Area 1 — Layered BSDF Material Model

**Technique chosen.** glTF 2.0 metallic-roughness as base lobe + KHR_materials_clearcoat as second layer. Base lobe: Cook-Torrance with GGX/Trowbridge-Reitz NDF (Walter et al. 2007), Smith-correlated visibility (Heitz 2014, "Understanding the Masking-Shadowing Function"), Schlick Fresnel (Schlick 1994). Clearcoat lobe: same formulation but with `coatNDF = GGX(N, H, coatRoughness)`, fixed F0=0.04 (polyurethane n=1.5), base lobe energy-attenuated by `(1 - F_coat)` per Filament's clearcoat derivation (Section 4.8.4). Schlick Fresnel: `F0 = mix(((ior-1)/(ior+1))^2, baseColor, metallic)` so configurable IOR drives dielectric reflectance (default 1.5 → 0.04, gemstones 1.7+, water 1.33). Emissive added post-tonemapping-input as `emissive * emissiveStrength`.

Per-material parameter set: `baseColor`, `metallic`, `roughness`, `ior`, `clearcoat`, `clearcoatRoughness`, `emissive`, `emissiveStrength`, `opacity`. Normal maps deferred to Phase 2 (`ViewportBody` has no UVs).

**Why over alternatives.** glTF is the only spec where every modern CAD/DCC tool (Fusion 360, SolidWorks Visualize, Rhino, Blender) imports/exports identically. Disney's sheen/anisotropy/subsurface lobes don't help for engineering renders, and `specularTint`/`specular` parameterization breaks round-trip with glTF. Filament uses different remapping (linear vs perceptual roughness). OpenPBR requires a node graph evaluator. Clearcoat alone gets us 90% of CADRays' "two-layer" intent at a fraction of complexity.

**New / changed Swift types.**

- New file: `Sources/OCCTSwiftViewport/Configuration/PBRMaterial.swift`
  - `public struct PBRMaterial: Sendable, Codable, Hashable` with all fields above
  - `public static let presets: [String: PBRMaterial]` — `.steel`, `.brushedAluminum`, `.brass`, `.copper`, `.chromedSteel`, `.plasticGlossy`, `.plasticMatte`, `.paintedAutomotive`, `.glass`, `.rubber`, `.gold`, `.titanium`
- Modified: `ViewportBody`
  - Add `public var material: PBRMaterial?` (nil → use legacy fields for backward compat)
- Modified: `Renderer/ViewportRenderer.swift`
  - `BodyUniforms` Swift struct grows: append `clearcoat`, `clearcoatRoughness`, `ior`, `emissive`, `emissiveStrength` plus padding for 16-byte alignment
  - Document the Swift↔Metal sync block at the struct definition

**Shader changes (`Shaders.metal`).**

- `BodyUniforms` Metal struct mirrors Swift growth (clearcoat, clearcoatRoughness, ior, emissive, emissiveStrength + pad).
- New helpers near `distributionGGX`:
  - `inline float V_SmithGGXCorrelated(float NdotV, float NdotL, float a)` — replaces separable G with correlated form (visibility = G / (4·NdotV·NdotL); fold the denominator)
  - `inline float3 evaluateClearcoat(float3 N, float3 V, float3 L, float3 H, float coat, float coatRoughness, thread float3 &Fc)` — returns coat specular, writes Fc out for base attenuation
  - `inline float F0FromIOR(float ior)` → `((ior-1)/(ior+1))²`
- `shaded_fragment`: in per-light loop after base specular, evaluate clearcoat and attenuate base by `(1 - Fc)`. After loop, add `emissive * emissiveStrength`. IBL block needs same coat treatment — sample `iblSpecular` at coat-roughness mip, attenuate diffuse/specular IBL by `(1-Fc_ibl)`.

**Demo app integration.**

- New file `Sources/OCCTSwiftMetalDemo/MaterialEditorPanel.swift`. SwiftUI panel slotted into `sidebar` `List` in `SpikeView.swift` as `DisclosureGroup("Materials")`. Shows selected body, preset picker, 10 sliders/color-pickers. 96×96 sphere preview at top via `OffscreenRenderer.swift`, 100ms debounce on slider change.

**Risks / open questions.**

- `BodyUniforms` size change is wire-protocol break — every offscreen test snapshot may shift due to slightly different IBL coat math. Re-baseline `Tests/` snapshot images.
- Energy conservation between coat and base under IBL is approximate without multiscatter compensation (Fdez-Agüera 2019). Acceptable for a viewport; document.
- IOR slider on metallic surfaces is meaningless — UI greys out when `metallic > 0.5`.

**Acceptance criteria.**

- Chrome sphere matches Sketchfab's reference render of `MetalRoughSpheres.glb` within perceptual tolerance.
- Clearcoat=1, baseRoughness=0.8, coatRoughness=0.05 produces "wet paint" look (rough underneath, sharp coat highlight) — CADRays' main visual goal.
- Performance: <0.4 ms additional GPU time on M1 Pro at 2560×1440. Total shaded pass stays <3 ms.

---

## Area 2 — HDR Environment Lighting Workflow

**Technique chosen.** Karis 2013 split-sum approximation (already in use): `∫L(l)f(l,v) ≈ prefilteredEnvMap(roughness) × BRDFLUT(NdotV, roughness)`. Pieces already in place: GGX-importance-sampled prefiltered specular cubemap (8 mips, 128px), Lambertian-cosine irradiance cubemap (32px), 2D BRDF LUT (256×256, RG16Float). Missing: HDR file loader, sky/background draw pass, separate background-vs-lighting exposure, environment Y-rotation, EXR support.

Asset format: ship parser for `.hdr` (Radiance RGBE — Greg Ward's format, ~80 lines of Swift) and use `CGImageSourceCreateWithData` for `.exr` on supported OS (returns 32-bit float CGImage when you pass `kCGImageSourceShouldAllowFloat`). Pre-converted `.ktx2` is overkill — load times of 1-2 seconds for a 2K HDR are acceptable since this is a "set once" choice.

**Why over alternatives.** Filament's offline `cmgen` is great for static asset pipelines but a CAD viewport must accept user-supplied HDRIs at runtime. Realtime convolution (no prefilter) was rejected — >32 samples per fragment per frame is infeasible at 60 fps on integrated GPUs. RGBE format is trivial enough that pulling in a third-party dependency is unjustified. Split-sum is the universal industry standard (UE4/5, Unity HDRP, Filament, three.js).

**New / changed Swift types.**

- New file: `Sources/OCCTSwiftViewport/Renderer/HDRLoader.swift`
  - `enum HDRLoader { static func loadRGBE(_ data: Data) throws -> (width: Int, height: Int, pixels: [Float]) }` — RGBE→linear-RGBA32F decoder
  - `static func loadEXR(_ data: Data) throws -> ...` — uses `CGImageSourceCreateWithData` with float pixel format (macOS 14+/iOS 17+; throws on unsupported)
  - `static func loadFromURL(_ url: URL) throws -> ...` — dispatch by extension
- Modified: `Renderer/EnvironmentMapManager.swift`
  - Pass rotation as a uniform (rotate sample direction in shader) — `iblParams.y` (currently unused) = rotation in radians, `iblParams.z` = backgroundExposure
  - Add separate `lightingExposure: Float` (multiplies `iblIntensity` already in `iblParams.x`)
  - Add background draw support: new method `drawSkybox(into encoder:, viewProjection:)` rendering fullscreen-triangle skybox with new `skybox_vertex`/`skybox_fragment`
- Modified: `Display/LightingConfiguration.swift`
  - New fields: `environmentRotationY`, `backgroundExposure`, `lightingExposure`, `drawBackground`, `environmentBlur` (samples skybox at coarser mip — separate from prefilteredSpecular: a "blur visible background" knob common in product viz)
  - Replace `environmentMapData: Data?` with `environmentURL: URL?` (keep Data variant for Bundle resources)
- Modified: `Renderer/ViewportRenderer.swift`
  - New `skyboxPipeline: MTLRenderPipelineState`, skybox pass added before shaded pass (writes depth=1, depth test = lessEqual)
  - `iblParams.y/z` wiring

**Shader changes.**

- `iblParams.y` becomes `environmentRotationY`. Apply to sampled direction in `shaded_fragment` IBL block by Y-rotation matrix or `R.xz = float2(R.x*c - R.z*s, R.x*s + R.z*c)`. Same for irradiance lookup direction `N`.
- `iblParams.z` becomes `backgroundExposure` (skybox only).
- New skybox functions: vertex generates fullscreen triangle, computes ray direction by inverse-projecting NDC corner. Fragment samples cube at `level = environmentBlur * 7`, applies rotation, multiplies by `backgroundExposure`.
- Update `iblParams` semantics comment in both Swift `Uniforms` and Metal `Uniforms`.

**Demo app integration.**

- File-picker button "Load HDRI…" with `.fileImporter` for `.hdr`/`.exr`. Horizontal scroll of bundled HDRI thumbnails (3-4 in `Sources/OCCTSwiftViewport/Resources/HDRIs/`: studio, outdoor, sunset, neutral). Sliders: rotation (0–2π), background exposure, lighting exposure, background blur. Toggle: draw background.

**Risks / open questions.**

- `.exr` via `Image I/O`: macOS 14+ added native EXR; older OSes need `tinyexr` or rejection. Decision: support `.hdr` everywhere, `.exr` macOS 14+/iOS 17+ best-effort.
- 4K HDRI is ~50 MB raw. Either downscale equirect to 2048×1024 before cube conversion, or accept the one-time load cost.
- TBDR: prefilter pass already runs per-mip with `waitUntilCompleted` (slow). On Apple Silicon should be <400 ms total on M1 for 1K HDRI. Wrap in progress indicator.

**Acceptance criteria.**

- Loading `studio.hdr` (4K) on M1 Pro: <500 ms file picker → fully prefiltered. iPhone 15 Pro: <1.5 s.
- Polished gold sphere with window-lit studio HDRI shows recognizable window reflection at roughness=0.1, smooth color cast at roughness=0.7.
- Rotating environment with slider rotates only reflection/lighting, not geometry — verifies decoupling.
- Background exposure → 0 (black background, lighting unaffected) — common product-shot config.

---

## Area 3 — Progressive Temporal Accumulation When Idle

**Technique chosen.** Hybrid TAA: while moving, current TAA with neighborhood AABB clamp (already in `taa_resolve_fragment`) and 0.9 history weight. While still >100ms, switch to **progressive accumulation**: `blend = N / (N + 1)` so frame N has weight 1/(N+1), running unbounded N up to ~256, no neighborhood clamp (no ghosting risk on static scene), Halton(2,3) sub-pixel jitter applied to projection matrix's m20/m21 entries (so rasterizer actually shifts), optional MPS ray-traced AO accumulation pass that fires only in idle mode.

The jitter-on-projection step is what's currently *missing* — existing scaffolding samples a jittered history but doesn't actually jitter the geometry, which is why TAA only does mild softening rather than supersampling. Karis's "tone-map for TAA" trick (tonemap before AABB clamp, inverse-tonemap after — `weight = 1/(1 + luma)`) suppresses fireflies under sharp HDRI specular. Apple Silicon TBDR: history texture must be `.private` and read in a separate render pass from where it's written.

For RTAO: `MTLAccelerationStructure` (universal at our minimum). Build BLAS per `ViewportBody`, TLAS once. AO ray query: 8 cosine-weighted hemisphere rays of length 0.5×sceneRadius from each pixel's worldPos, accumulated only in idle mode, blended at 1/N rate. Use `intersector<>` API in compute. Separate compute pass writes single-channel R16Float AO texture that the next frame's resolve multiplies into the lit color.

**Why over alternatives.** Pure brute-force re-rendering with N MSAA samples is wrong — MSAA only helps geometric edges, not shading aliasing under high-frequency HDRI specular. Progressive accumulation gets supersampling for free across all signals. RTAO over SSAO is meaningful: SSAO can't see occluders behind/outside screen — RTAO does. Limiting RT to idle keeps moving-camera frames at 60 fps; idle accumulator is where users zoom in and look closely. Marmoset Toolbag's preview viewport uses essentially this design.

**New / changed Swift types.**

- Modified: `Renderer/ViewportRenderer.swift`
  - `private var idleFrameCount: UInt32 = 0`, `private var idleStartTime: CFTimeInterval = 0`
  - Existing `lastCameraState` comparison becomes one trigger; reset also on body-mutation, light changes, body picking, displayMode flips. Add `private var lastSceneRevision: UInt64 = 0` summing body generations.
  - Apply jitter to projection matrix in `buildUniforms`: jitter offset `(jx, jy)` in pixels → matrix nudge `m[2][0] += 2·jx/w; m[2][1] += 2·jy/h` for perspective; equivalent on column 3 for ortho.
- New file: `Sources/OCCTSwiftViewport/Renderer/RayTracingAOManager.swift`
  - `@MainActor final class RayTracingAOManager`
  - Builds primitive acceleration structures from `ViewportBody.vertexData/indices`; rebuilds when `bodyGeneration` changes
  - `func encodeAOPass(into commandBuffer:, worldPositionTex:, normalTex:, output:, frameIndex:, ...)`
  - World-pos reconstructed from depth+inverse-VP in AO compute kernel (saves bandwidth — preferred over MRT)

**Shader changes.**

- New compute kernel `rtao_kernel` using `intersector<triangle_data>`:
  - Reconstructs world position from depth+inverseVP, builds TBN from depth derivatives, casts 8 cosine-weighted hemisphere rays, accumulates `(visibility / N)`
  - Frame-jittered with golden-ratio sequence on cosine sample direction (frame index from CPU)
- New `progressive_resolve_fragment` (variant of TAA resolve): no neighborhood clamp, blend = `min(idleFrame / (idleFrame+1), 0.99)`, reads history+current+aoTex (multiplies AO term into result).
- `Uniforms` Swift struct: jitter is *not* a uniform — already baked into `viewProjectionMatrix`. New dedicated `RTAOParamsSwift` ↔ `RTAOParams` struct.

**Demo app integration.**

- Sidebar `DisclosureGroup("Render Quality")`: "Progressive accumulation: idle / always / off" segmented control, "Ray-traced AO" toggle (gated on `device.supportsRaytracing`), "Idle delay (ms)" slider. Lower-right overlay: "Refining… 12/256" while accumulating, fades when N > 64.

**Risks / open questions.**

- Building accel structures from ~200K-tri models takes 100-500 ms — must be off main render path. `MTLAccelerationStructureCommandEncoder` async with completion handler. Add "preparing ray tracing…" status while it builds.
- Some MTLDevices report `supportsRaytracing == false` (older Intel Macs, iOS Simulator). Gate UI off `supportsRaytracing`.
- Idle detection collides with subtle camera animation easings — `isAnimating` from `CameraController` should be a reset trigger.
- Reverse-Z depth: confirm projection matrix jitter doesn't break the existing reverse-Z setup.

**Acceptance criteria.**

- Sit still on complex scene: visible aliasing on HDRI specular highlights converges to clean within ~32 frames (~0.5 s).
- RTAO produces visible occlusion in interior corners SSAO misses (e.g., inside a pocket where bottom is occluded by rim).
- Moving camera: 60 fps on M1 Pro at 2560×1440 (RTAO disabled while moving).
- Idle frame budget: <8 ms total on M1 Pro (raster ~3 ms + RTAO 8-ray ~4 ms + resolve <1 ms).

---

## Area 4 — Materials Editor UX

**Technique chosen.** Per-body material assignment stored on `ViewportBody.material`, with separate `MaterialLibrary` registry (`@MainActor` ObservableObject) that holds named user materials and bundled presets, persists to disk as JSON (Application Support), supports drag-and-drop assignment from swatch grid via existing selection. SwiftUI side panel adapted from Sketchfab/Substance Painter: top is 96×96 live sphere preview rendered with `OffscreenRenderer`, middle is preset swatches in `LazyVGrid`, bottom is `Form`-based parameter sliders. Live preview updates with 100ms debounce.

Multi-body selection: edit applies to all selected bodies; sliders show "Multiple Values" placeholder when params differ (Xcode inspector convention). Sphere preview reuses main renderer's environment map and lighting config so previews match actual viewport — critical for trust.

**Why over alternatives.** Fully node-based material editor (Substance Designer style) is way out of scope for engineering visualization where "make it look like brass" is the goal. Material as registry vs on-body: registry pattern enables "save this material and reapply elsewhere" — table-stakes. Both: registry holds named definitions (UI convenience), body holds inline value (Sendable). Settled on: `ViewportBody.material: PBRMaterial?` is inline; `MaterialLibrary` is `@MainActor` registry for naming/saving.

**New / changed Swift types.**

- New file: `Sources/OCCTSwiftViewport/Configuration/MaterialLibrary.swift`
  - `@MainActor public final class MaterialLibrary: ObservableObject` with `@Published var materials: [NamedMaterial]`
  - `public struct NamedMaterial: Sendable, Codable, Identifiable { public let id: UUID; public var name: String; public var material: PBRMaterial }`
  - `public func saveToDisk() throws`, `public static func loadFromDisk() -> MaterialLibrary`
  - `public func bundledPresets() -> [NamedMaterial]` — wraps static `PBRMaterial.presets`
- New file: `Sources/OCCTSwiftMetalDemo/MaterialEditorPanel.swift`
  - `struct MaterialEditorPanel: View` taking body bindings, controller, library
  - Subview `MaterialSpherePreview` (96×96 via `OffscreenRenderer` on every change with debounce)
  - Subview `MaterialParameterSliders` — `Slider`/`ColorPicker`/disabled-states for IOR-on-metal etc.
- New file: `Sources/OCCTSwiftMetalDemo/MaterialPresetGrid.swift` — swatch grid with drag-and-drop
- Modified: `Sources/OCCTSwiftMetalDemo/SpikeView.swift`
  - `@StateObject private var materialLibrary = MaterialLibrary.loadFromDisk()`
  - Add `DisclosureGroup("Materials")` to sidebar
- New: `Sources/OCCTSwiftViewport/Resources/material-presets.json` — same data as `PBRMaterial.presets` for round-trip testing

**Shader changes.** None — pure UI on top of area 1's uniform pipeline.

**Demo app integration.**

- Sidebar `DisclosureGroup("Materials")` after `File & Tools`. Hidden when no body selected; shows "Select a body to edit materials" placeholder otherwise.
- Small "Material" badge on status overlay showing assigned material name when one body selected.
- Save/load: "Save material…" button captures current edit as `NamedMaterial` with name prompt, persists to disk; swatch grid grows.

**Risks / open questions.**

- Sphere preview rendering at 100ms debounce on every slider drag may stutter main view if both share command queue. Decision: give preview own `MTLCommandQueue` at lower priority.
- "Multiple values" semantics for color picker is ugly in SwiftUI — `Toggle` next to "Apply color to selection" workaround.
- Material library disk schema versioning: include `schemaVersion: Int = 1` in JSON root.
- Drag-and-drop on iOS doesn't work the same as macOS — fall back to tap-to-assign on iOS.

**Acceptance criteria.**

- Selecting a body and dragging "Brushed Aluminum" preset onto it changes appearance immediately, matches sphere preview.
- Editing roughness with slider produces visible specular tightening within one frame.
- Save → restart app → material library loads with all user-saved materials.
- Multi-select chrome ball + brass ring, click "Plastic Glossy" — both update.

---

## Sequencing

1. **`PBRMaterial` type only (S, ~½ day).** Just struct, presets, `ViewportBody.material` field. Wire-compatible: legacy roughness/metallic still works; if `material == nil` renderer reads legacy fields. Unblocks 1.
2. **Layered BSDF (M, 2-3 days).** Cook-Torrance already in place; work is clearcoat lobe, IOR-driven F0, emissive, Smith correlated visibility upgrade, expand `BodyUniforms` on both sides of Swift↔Metal divide. Snapshot test rebaseline.
3. **HDR environment workflow (M, 2-3 days).** RGBE parser, EXR-via-CGImageSource path, skybox draw pass, rotation/exposure plumbing, bundled HDRI assets. IBL compute kernels exist and are correct. Build on area 1 because new clearcoat lobe also needs IBL coat lookup.
4. **Materials editor UI (M, 2 days).** `MaterialLibrary`, panel, sphere preview, persistence. Builds on areas 1+2 because preview should show real environment lighting. Drag-and-drop is riskiest UI bit.
5. **Progressive accumulation + RTAO (L, 4-5 days).** Last because (a) benefits most from PBR + IBL being correct (otherwise accumulating ugly), (b) `MTLAccelerationStructure` plumbing and world-position reconstruction in AO compute kernel are most novel code, (c) tuning idle thresholds and reset triggers needs many user-feel iterations.

Total: ~12 days focused work. Areas 1+4-partial = smallest shippable improvement; 1+2+4 = coherent "PBR + HDR + materials editor" milestone; area 3 = polish capstone.

## Critical Files

- `Sources/OCCTSwiftViewport/Renderer/Shaders.metal`
- `Sources/OCCTSwiftViewport/Renderer/ViewportRenderer.swift`
- `Sources/OCCTSwiftViewport/Renderer/EnvironmentMapManager.swift`
- `Sources/OCCTSwiftViewport/Types/ViewportBody.swift`
- `Sources/OCCTSwiftViewport/Display/LightingConfiguration.swift`

## Implementation Status

- [x] **Milestone 1 — `PBRMaterial` type + presets + `ViewportBody` field** (backward-compat via `effectiveMaterial`)
- [x] **Milestone 2 — Layered BSDF (clearcoat + IOR + emissive)** (`evaluateClearcoat`, `F0FromIOR`, IBL coat lookup)
- [x] **Milestone 3 — HDR environment workflow** (`HDRLoader` RGBE parser, `loadHDR(url:)`, skybox draw pass, env rotation, separate background/lighting exposure)
- [x] **Milestone 4 — Materials editor SwiftUI panel** (`MaterialLibrary` + `NamedMaterial` registry, persistent JSON, sphere preview via `OffscreenRenderer`, preset swatches, parameter sliders)
- [x] **Milestone 5 (partial) — Progressive accumulation** (Halton(2,3) projection-matrix jitter, `disableClamp` flag for static scenes, `N/(N+1)` blend up to 256 samples, idle reset on `isAnimating`)

### Deferred Work

- **EXR support in `HDRLoader`** — `.hdr` (RGBE) ships now; `.exr` via `CGImageSourceCreateWithData` is straightforward to add when needed (macOS 14+/iOS 17+).
- **Bundled HDRI assets** — the materials editor accepts URLs but the demo doesn't yet ship presets in `Resources/HDRIs/`. Add when the user has a curated set.
- **Smith correlated visibility** — current shader uses separable Smith G; correlated form (Heitz 2014) is a known small upgrade. Would shift every snapshot test slightly — defer to a focused commit with snapshot rebaseline.
- **Ray-traced AO (RTAO)** — `MTLAccelerationStructure` + `RayTracingAOManager` + `rtao_kernel` compute shader. Significant standalone work (BLAS/TLAS lifecycle, async build with progress UI, world-pos reconstruction, frame-jittered hemisphere sampling, gating on `device.supportsRaytracing`). Best as its own focused commit after the progressive accumulator has been used in anger.
- **Frontend file picker for HDRIs** — the public API is in place (`viewport.loadEnvironmentMap(url:)`); the demo sidebar should grow a "Load HDRI…" button + bundled-thumbnail picker.
