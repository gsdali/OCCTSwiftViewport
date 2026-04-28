// ViewportRenderer.swift
// ViewportKit
//
// MTKViewDelegate that drives Metal rendering for the viewport.

@preconcurrency import MetalKit
import simd
import SwiftUI

// MARK: - Uniform Types (Swift-side, must match Shaders.metal)

struct LightDataSwift {
    var directionAndIntensity: SIMD4<Float>  // xyz = direction, w = intensity
    var colorAndEnabled: SIMD4<Float>        // rgb = color, a = enabled flag
    var typeAndParams: SIMD4<Float>          // x = type (0=directional, 1=point), y = radius, z/w = unused
    var positionAndPad: SIMD4<Float>         // xyz = world position (point lights), w = unused
}

struct Uniforms {
    var viewProjectionMatrix: simd_float4x4
    var modelMatrix: simd_float4x4
    var viewMatrix: simd_float4x4
    var cameraPosition: SIMD4<Float>          // xyz + nearPlane in w
    var light0: LightDataSwift
    var light1: LightDataSwift
    var light2: LightDataSwift
    var ambientSkyColor: SIMD4<Float>         // rgb + specularPower in w
    var ambientGroundColor: SIMD4<Float>      // rgb + specularIntensity in w
    var materialParams: SIMD4<Float>          // fresnelPower, fresnelIntensity, matcapBlend, farPlane
    var lightViewProjectionMatrix: simd_float4x4  // for shadow mapping
    var shadowParams: SIMD4<Float>            // x = bias, y = intensity, z = enabled (1/0), w = edgeIntensity
    var shadowParams2: SIMD4<Float> = .zero   // x = lightSize, y = searchRadius, z/w = unused (PCSS)
    var iblParams: SIMD4<Float> = .zero       // x = intensity, y = rotationY (radians),
                                              // z = backgroundExposure, w = hasEnvMap
    var clipPlanes: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>) = (.zero, .zero, .zero, .zero)
    var clipPlaneCount: UInt32 = 0
    var _clipPad: SIMD3<Float> = .zero
}

// Per-body shader uniforms.
//
// IMPORTANT — Swift↔Metal sync:
// The matching `struct BodyUniforms` lives in Renderer/Shaders.metal.
// Field order, types, and 16-byte alignment must stay identical.
// Total stride is 64 bytes (4 × float4-equivalent slots).
struct BodyUniforms {
    var color: SIMD4<Float>             // offset  0  (16) — base colour rgb, opacity in a
    var objectIndex: UInt32 = 0          // offset 16
    var roughness: Float = 0.5           // offset 20
    var metallic: Float = 0.0            // offset 24
    var isSelected: UInt32 = 0           // offset 28  (1 = selected, 2 = hovered)
    var clearcoat: Float = 0             // offset 32
    var clearcoatRoughness: Float = 0.03 // offset 36
    var ior: Float = 1.5                 // offset 40
    var _pad0: Float = 0                 // offset 44
    var emissiveAndStrength: SIMD4<Float> = .zero  // offset 48 — xyz = emissive linear RGB, w = strength
}

extension BodyUniforms {
    /// Build per-body uniforms from a `ViewportBody`'s effective material.
    init(body: ViewportBody, objectIndex: UInt32 = 0, isSelected: UInt32 = 0) {
        let m = body.effectiveMaterial
        self.color = SIMD4<Float>(m.baseColor.x, m.baseColor.y, m.baseColor.z, m.opacity)
        self.objectIndex = objectIndex
        self.roughness = m.roughness
        self.metallic = m.metallic
        self.isSelected = isSelected
        self.clearcoat = m.clearcoat
        self.clearcoatRoughness = m.clearcoatRoughness
        self.ior = m.ior
        self.emissiveAndStrength = SIMD4<Float>(m.emissive.x, m.emissive.y, m.emissive.z, m.emissiveStrength)
    }
}

struct GridUniforms {
    var viewProjectionMatrix: simd_float4x4
    var gridOrigin: SIMD3<Float>
    var spacing: Float
    var halfCount: Int32
    var dotSize: Float
    var dotColor: SIMD4<Float>
}

struct AxisUniforms {
    var viewProjectionMatrix: simd_float4x4
}

struct SelectionOutlineParamsSwift {
    var viewProjectionMatrix: simd_float4x4
    var modelMatrix: simd_float4x4
    var outlineColor: SIMD3<Float>
    var outlineScale: Float
}

struct ShadowUniformsSwift {
    var lightViewProjectionMatrix: simd_float4x4
    var modelMatrix: simd_float4x4
}

struct SSAOParamsSwift {
    var texelSize: SIMD2<Float>
    var radius: Float
    var intensity: Float
    var nearPlane: Float
    var farPlane: Float
    var silhouetteThickness: Float
    var silhouetteIntensity: Float
    var exposure: Float
    var whitePoint: Float
    var dofAperture: Float
    var dofFocalDistance: Float
    var dofMaxBlurRadius: Float
    var dofEnabled: Float
}

// IMPORTANT — Swift↔Metal sync (see Renderer/Shaders.metal `struct TAAParams`).
struct TAAParamsSwift {
    var blendFactor: Float
    var disableClamp: Float = 0       // 1.0 = skip neighborhood AABB clamp (use for static scenes)
    var jitterOffset: SIMD2<Float>
    var texelSize: SIMD2<Float>
}

// IMPORTANT — Swift↔Metal sync (see Renderer/Shaders.metal `struct SkyboxUniforms`).
struct SkyboxUniformsSwift {
    var inverseViewProjection: simd_float4x4
    var params: SIMD4<Float>  // x = rotationY, y = backgroundExposure, z = mipLevel, w = unused
}

// MARK: - Cached Body Buffers

private struct BodyBuffers {
    let vertexBuffer: MTLBuffer?
    let indexBuffer: MTLBuffer?
    let indexCount: Int
    let edgeVertexBuffer: MTLBuffer?
    let edgeVertexCount: Int
    let vertexCount: Int
    // Tessellation (nil when tessellation disabled or edge-only body)
    let tessellation: TessellationBuffers?
    // Mesh shader meshlets (nil when mesh shaders disabled or edge-only body)
    let meshlets: MeshletBuffers?
}

// MARK: - ViewportRenderer

@MainActor
public final class ViewportRenderer: NSObject, MTKViewDelegate, Sendable {

    // MARK: - Properties

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    // MSAA pipelines (sampleCount matches view — 4 or 1)
    private let shadedPipeline: MTLRenderPipelineState
    private let wireframePipeline: MTLRenderPipelineState
    private let gridPipeline: MTLRenderPipelineState
    private let axisPipeline: MTLRenderPipelineState
    // 1x pick-only pipelines (pick texture is always sampleCount=1)
    private let pickShadedPipeline: MTLRenderPipelineState
    // Depth-only pipeline for SSAO depth pass
    private let depthOnlyPipeline: MTLRenderPipelineState
    // Shadow mapping
    private let shadowPipeline: MTLRenderPipelineState
    private let shadowMapManager: ShadowMapManager
    // Selection outline
    private let outlinePipeline: MTLRenderPipelineState
    private let stencilWriteState: MTLDepthStencilState
    private let stencilTestState: MTLDepthStencilState
    private let depthState: MTLDepthStencilState
    private let matcapTexture: MTLTexture
    private let msaaSampleCount: Int
    // Skybox (HDR background draw — IBL cubemap as fullscreen background)
    private let skyboxPipeline: MTLRenderPipelineState?
    private let skyboxDepthState: MTLDepthStencilState?

    // Hardware tessellation (PN triangles)
    private let tessellationManager: TessellationManager?
    private let tessellatedShadedPipeline: MTLRenderPipelineState?
    private let tessellatedShadowPipeline: MTLRenderPipelineState?
    private let tessellatedDepthOnlyPipeline: MTLRenderPipelineState?
    private let tessellatedPickPipeline: MTLRenderPipelineState?
    private let tessellationEnabled: Bool

    // Mesh shaders (Apple9+ / M3+ / A17+)
    private let meshShaderShadedPipeline: MTLRenderPipelineState?
    private let meshShaderShadowPipeline: MTLRenderPipelineState?
    private let meshShaderDepthOnlyPipeline: MTLRenderPipelineState?
    private let meshShaderPickPipeline: MTLRenderPipelineState?
    private let meshShadersEnabled: Bool

    /// Depth texture for the 1x pick pass (separate from the MSAA depth).
    private var pickDepthTexture: MTLTexture?
    private var pickDepthWidth: Int = 0
    private var pickDepthHeight: Int = 0

    // SSAO post-process
    private let ssaoPipeline: MTLRenderPipelineState?
    /// 1x resolved color texture for SSAO input (MSAA resolves into this)
    private var resolvedColorTexture: MTLTexture?
    /// 1x resolved depth texture for SSAO depth sampling
    private var resolvedDepthTexture: MTLTexture?
    private var resolvedWidth: Int = 0
    private var resolvedHeight: Int = 0

    // TAA
    private let taaPipeline: MTLRenderPipelineState?
    private var taaHistoryTexture: MTLTexture?
    private var taaOutputTexture: MTLTexture?
    private var taaFrameIndex: UInt32 = 0
    private var lastCameraState: CameraState?

    // Environment map IBL
    private var environmentMapManager: EnvironmentMapManager?

    private weak var controller: ViewportController?
    private var bodiesBinding: Binding<[ViewportBody]>

    /// Cached MTLBuffers keyed by body ID.
    private var bodyBufferCache: [String: BodyBuffers] = [:]
    /// Generation counter per body ID (detects geometry changes).
    private var bodyGeneration: [String: UInt64] = [:]

    /// Axis vertex buffer (6 vertices: 3 line segments with position+color).
    private let axisVertexBuffer: MTLBuffer

    // MARK: - Picking

    /// Manages the R32Uint pick ID texture (second color attachment).
    private let pickTextureManager: PickTextureManager
    /// Shared-mode buffer for single-pixel readback of pick ID.
    private let pickReadbackBuffer: MTLBuffer
    /// Maps objectIndex → bodyID, rebuilt each frame.
    private var currentIndexMap: [Int: String] = [:]

    // MARK: - Initialization

    public init?(controller: ViewportController, bodies: Binding<[ViewportBody]>) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            return nil
        }

        self.device = device
        self.commandQueue = commandQueue
        self.controller = controller
        self.bodiesBinding = bodies

        let sampleCount = controller.configuration.msaaSampleCount
        self.msaaSampleCount = sampleCount

        // Load shader library.
        // Xcode compiles .metal → default.metallib inside the resource bundle.
        // Plain SPM copies the .metal source, so fall back to runtime compilation.
        let library: MTLLibrary
        if let compiled = try? device.makeDefaultLibrary(bundle: Bundle.module) {
            library = compiled
        } else if let metalURL = Bundle.module.url(forResource: "Shaders", withExtension: "metal"),
                  let src = try? String(contentsOf: metalURL, encoding: .utf8),
                  let fromSource = try? device.makeLibrary(source: src, options: nil) {
            library = fromSource
        } else {
            return nil
        }

        // Vertex descriptor for interleaved position + normal (stride 6 floats)
        let vertexDesc = MTLVertexDescriptor()
        vertexDesc.attributes[0].format = .float3
        vertexDesc.attributes[0].offset = 0
        vertexDesc.attributes[0].bufferIndex = 0
        vertexDesc.attributes[1].format = .float3
        vertexDesc.attributes[1].offset = MemoryLayout<Float>.size * 3
        vertexDesc.attributes[1].bufferIndex = 0
        vertexDesc.layouts[0].stride = MemoryLayout<Float>.size * 6

        let depthFormat: MTLPixelFormat = .depth32Float_stencil8

        // --- MSAA pipelines (color-only, no pick texture) ---

        // Shaded pipeline (MSAA)
        let shadedDesc = MTLRenderPipelineDescriptor()
        shadedDesc.vertexFunction = library.makeFunction(name: "shaded_vertex")
        shadedDesc.fragmentFunction = library.makeFunction(name: "shaded_fragment")
        shadedDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        shadedDesc.colorAttachments[1].pixelFormat = .invalid
        shadedDesc.depthAttachmentPixelFormat = depthFormat
        shadedDesc.stencilAttachmentPixelFormat = depthFormat
        shadedDesc.rasterSampleCount = sampleCount
        shadedDesc.vertexDescriptor = vertexDesc

        guard let shadedPipeline = try? device.makeRenderPipelineState(descriptor: shadedDesc) else {
            return nil
        }
        self.shadedPipeline = shadedPipeline

        // Wireframe pipeline (MSAA)
        let wireDesc = MTLRenderPipelineDescriptor()
        wireDesc.vertexFunction = library.makeFunction(name: "wireframe_vertex")
        wireDesc.fragmentFunction = library.makeFunction(name: "wireframe_fragment")
        wireDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        wireDesc.colorAttachments[1].pixelFormat = .invalid
        wireDesc.colorAttachments[0].isBlendingEnabled = true
        wireDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        wireDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        wireDesc.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        wireDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        wireDesc.depthAttachmentPixelFormat = depthFormat
        wireDesc.stencilAttachmentPixelFormat = depthFormat
        wireDesc.rasterSampleCount = sampleCount
        wireDesc.vertexDescriptor = vertexDesc

        guard let wireframePipeline = try? device.makeRenderPipelineState(descriptor: wireDesc) else {
            return nil
        }
        self.wireframePipeline = wireframePipeline

        // Grid pipeline (MSAA)
        let gridDesc = MTLRenderPipelineDescriptor()
        gridDesc.vertexFunction = library.makeFunction(name: "grid_vertex")
        gridDesc.fragmentFunction = library.makeFunction(name: "grid_fragment")
        gridDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        gridDesc.colorAttachments[1].pixelFormat = .invalid
        gridDesc.depthAttachmentPixelFormat = depthFormat
        gridDesc.stencilAttachmentPixelFormat = depthFormat
        gridDesc.rasterSampleCount = sampleCount

        guard let gridPipeline = try? device.makeRenderPipelineState(descriptor: gridDesc) else {
            return nil
        }
        self.gridPipeline = gridPipeline

        // Axis pipeline (MSAA)
        let axisDesc = MTLRenderPipelineDescriptor()
        axisDesc.vertexFunction = library.makeFunction(name: "axis_vertex")
        axisDesc.fragmentFunction = library.makeFunction(name: "axis_fragment")
        axisDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        axisDesc.colorAttachments[1].pixelFormat = .invalid
        axisDesc.depthAttachmentPixelFormat = depthFormat
        axisDesc.stencilAttachmentPixelFormat = depthFormat
        axisDesc.rasterSampleCount = sampleCount

        let axisVertexDesc = MTLVertexDescriptor()
        axisVertexDesc.attributes[0].format = .float3
        axisVertexDesc.attributes[0].offset = 0
        axisVertexDesc.attributes[0].bufferIndex = 0
        axisVertexDesc.attributes[1].format = .float4
        axisVertexDesc.attributes[1].offset = MemoryLayout<Float>.size * 3
        axisVertexDesc.attributes[1].bufferIndex = 0
        axisVertexDesc.layouts[0].stride = MemoryLayout<Float>.size * 7

        axisDesc.vertexDescriptor = axisVertexDesc

        guard let axisPipeline = try? device.makeRenderPipelineState(descriptor: axisDesc) else {
            return nil
        }
        self.axisPipeline = axisPipeline

        // Skybox pipeline (MSAA, no vertex buffer — fullscreen triangle from vertex_id)
        let skyboxDesc = MTLRenderPipelineDescriptor()
        skyboxDesc.label = "skybox"
        skyboxDesc.vertexFunction = library.makeFunction(name: "skybox_vertex")
        skyboxDesc.fragmentFunction = library.makeFunction(name: "skybox_fragment")
        skyboxDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        skyboxDesc.colorAttachments[1].pixelFormat = .invalid
        skyboxDesc.depthAttachmentPixelFormat = depthFormat
        skyboxDesc.stencilAttachmentPixelFormat = depthFormat
        skyboxDesc.rasterSampleCount = sampleCount
        // No vertexDescriptor — vertex shader uses [[vertex_id]] only
        self.skyboxPipeline = try? device.makeRenderPipelineState(descriptor: skyboxDesc)

        // Skybox depth state: depth test always, no depth write.
        // Drawn first; subsequent geometry overwrites via normal depth test.
        let skyboxDepthDesc = MTLDepthStencilDescriptor()
        skyboxDepthDesc.depthCompareFunction = .always
        skyboxDepthDesc.isDepthWriteEnabled = false
        self.skyboxDepthState = device.makeDepthStencilState(descriptor: skyboxDepthDesc)

        // --- 1x pick-only pipeline (R32Uint, no MSAA) ---

        let pickShadedDesc = MTLRenderPipelineDescriptor()
        pickShadedDesc.label = "pick_shaded"
        pickShadedDesc.vertexFunction = library.makeFunction(name: "pick_vertex")
        pickShadedDesc.fragmentFunction = library.makeFunction(name: "pick_fragment")
        pickShadedDesc.colorAttachments[0].pixelFormat = .r32Uint
        pickShadedDesc.depthAttachmentPixelFormat = .depth32Float
        pickShadedDesc.rasterSampleCount = 1
        pickShadedDesc.vertexDescriptor = vertexDesc

        guard let pickShadedPipeline = try? device.makeRenderPipelineState(descriptor: pickShadedDesc) else {
            return nil
        }
        self.pickShadedPipeline = pickShadedPipeline

        // Depth-only pipeline (for SSAO depth pass — no color attachments)
        let depthOnlyDesc = MTLRenderPipelineDescriptor()
        depthOnlyDesc.label = "depth_only"
        depthOnlyDesc.vertexFunction = library.makeFunction(name: "depth_only_vertex")
        depthOnlyDesc.fragmentFunction = library.makeFunction(name: "depth_only_fragment")
        depthOnlyDesc.depthAttachmentPixelFormat = .depth32Float
        depthOnlyDesc.rasterSampleCount = 1
        depthOnlyDesc.vertexDescriptor = vertexDesc

        guard let depthOnlyPipeline = try? device.makeRenderPipelineState(descriptor: depthOnlyDesc) else {
            return nil
        }
        self.depthOnlyPipeline = depthOnlyPipeline

        // Shadow map pipeline (depth-only from light perspective)
        let shadowDesc = MTLRenderPipelineDescriptor()
        shadowDesc.label = "shadow_map"
        shadowDesc.vertexFunction = library.makeFunction(name: "shadow_vertex")
        shadowDesc.fragmentFunction = library.makeFunction(name: "depth_only_fragment")
        shadowDesc.depthAttachmentPixelFormat = .depth32Float
        shadowDesc.rasterSampleCount = 1
        shadowDesc.vertexDescriptor = vertexDesc

        guard let shadowPipeline = try? device.makeRenderPipelineState(descriptor: shadowDesc) else {
            return nil
        }
        self.shadowPipeline = shadowPipeline
        self.shadowMapManager = ShadowMapManager(device: device)

        // Selection outline pipeline (MSAA, renders expanded geometry where stencil != 1)
        let outlineDesc = MTLRenderPipelineDescriptor()
        outlineDesc.label = "selection_outline"
        outlineDesc.vertexFunction = library.makeFunction(name: "selection_outline_vertex")
        outlineDesc.fragmentFunction = library.makeFunction(name: "selection_outline_fragment")
        outlineDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        outlineDesc.colorAttachments[0].isBlendingEnabled = true
        outlineDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        outlineDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        outlineDesc.depthAttachmentPixelFormat = depthFormat
        outlineDesc.stencilAttachmentPixelFormat = depthFormat
        outlineDesc.rasterSampleCount = sampleCount
        outlineDesc.vertexDescriptor = vertexDesc

        guard let outlinePipeline = try? device.makeRenderPipelineState(descriptor: outlineDesc) else {
            return nil
        }
        self.outlinePipeline = outlinePipeline

        // --- Hardware tessellation pipelines (PN triangles) ---
        let quality = controller.configuration.renderingQuality
        let wantsTessellation = quality == .enhanced || quality == .maximum

        if wantsTessellation,
           let tessMgr = TessellationManager(device: device, library: library) {
            self.tessellationManager = tessMgr
            let maxTessFactor = controller.configuration.tessellationMaxFactor

            // Helper to configure tessellation on a pipeline descriptor
            func configureTessellation(_ desc: MTLRenderPipelineDescriptor) {
                desc.maxTessellationFactor = maxTessFactor
                desc.tessellationFactorStepFunction = .perPatch
                desc.tessellationPartitionMode = .fractionalEven
                desc.tessellationFactorFormat = .half
                desc.tessellationOutputWindingOrder = .counterClockwise
                desc.vertexDescriptor = nil // No vertex descriptor for tessellation
            }

            // Tessellated shaded pipeline
            let tsDesc = MTLRenderPipelineDescriptor()
            tsDesc.label = "tessellated_shaded"
            tsDesc.vertexFunction = library.makeFunction(name: "tessellated_vertex")
            tsDesc.fragmentFunction = library.makeFunction(name: "shaded_fragment")
            tsDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
            tsDesc.colorAttachments[1].pixelFormat = .invalid
            tsDesc.depthAttachmentPixelFormat = depthFormat
            tsDesc.stencilAttachmentPixelFormat = depthFormat
            tsDesc.rasterSampleCount = sampleCount
            configureTessellation(tsDesc)

            var diagErrors: [String] = []
            // Check if shader functions were found
            if tsDesc.vertexFunction == nil { diagErrors.append("tessellated_vertex function NOT FOUND") }

            do {
                self.tessellatedShadedPipeline = try device.makeRenderPipelineState(descriptor: tsDesc)
            } catch {
                self.tessellatedShadedPipeline = nil
                diagErrors.append("shaded: \(error.localizedDescription)")
            }

            // Tessellated shadow pipeline
            let tshDesc = MTLRenderPipelineDescriptor()
            tshDesc.label = "tessellated_shadow"
            tshDesc.vertexFunction = library.makeFunction(name: "tessellated_shadow_vertex")
            tshDesc.fragmentFunction = library.makeFunction(name: "depth_only_fragment")
            tshDesc.depthAttachmentPixelFormat = .depth32Float
            tshDesc.rasterSampleCount = 1
            configureTessellation(tshDesc)
            do {
                self.tessellatedShadowPipeline = try device.makeRenderPipelineState(descriptor: tshDesc)
            } catch {
                self.tessellatedShadowPipeline = nil
                diagErrors.append("shadow: \(error.localizedDescription)")
            }

            // Tessellated depth-only pipeline (SSAO)
            let tdDesc = MTLRenderPipelineDescriptor()
            tdDesc.label = "tessellated_depth_only"
            tdDesc.vertexFunction = library.makeFunction(name: "tessellated_depth_vertex")
            tdDesc.fragmentFunction = library.makeFunction(name: "depth_only_fragment")
            tdDesc.depthAttachmentPixelFormat = .depth32Float
            tdDesc.rasterSampleCount = 1
            configureTessellation(tdDesc)
            do {
                self.tessellatedDepthOnlyPipeline = try device.makeRenderPipelineState(descriptor: tdDesc)
            } catch {
                self.tessellatedDepthOnlyPipeline = nil
                diagErrors.append("depth: \(error.localizedDescription)")
            }

            // Tessellated pick pipeline
            let tpDesc = MTLRenderPipelineDescriptor()
            tpDesc.label = "tessellated_pick"
            tpDesc.vertexFunction = library.makeFunction(name: "tessellated_pick_vertex")
            tpDesc.fragmentFunction = library.makeFunction(name: "tessellated_pick_fragment")
            tpDesc.colorAttachments[0].pixelFormat = .r32Uint
            tpDesc.depthAttachmentPixelFormat = .depth32Float
            tpDesc.rasterSampleCount = 1
            configureTessellation(tpDesc)
            do {
                self.tessellatedPickPipeline = try device.makeRenderPipelineState(descriptor: tpDesc)
            } catch {
                self.tessellatedPickPipeline = nil
                diagErrors.append("pick: \(error.localizedDescription)")
            }

            self.tessellationEnabled = tessellatedShadedPipeline != nil

            // Write diagnostic to Documents for retrieval via devicectl
            let diagMsg: String
            if diagErrors.isEmpty {
                diagMsg = "OK: shaded=\(tessellatedShadedPipeline != nil) shadow=\(tessellatedShadowPipeline != nil) depth=\(tessellatedDepthOnlyPipeline != nil) pick=\(tessellatedPickPipeline != nil)"
            } else {
                diagMsg = "ERRORS:\n" + diagErrors.joined(separator: "\n")
            }
            NSLog("[ViewportRenderer] Tessellation: %@", diagMsg)
            if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? diagMsg.write(to: docs.appendingPathComponent("renderer_diag.txt"), atomically: true, encoding: .utf8)
            }
        } else {
            self.tessellationManager = nil
            self.tessellatedShadedPipeline = nil
            self.tessellatedShadowPipeline = nil
            self.tessellatedDepthOnlyPipeline = nil
            self.tessellatedPickPipeline = nil
            self.tessellationEnabled = false
            NSLog("[ViewportRenderer] Tessellation disabled")
        }

        // --- Mesh shader pipelines (Apple9+ / M3+ / A17+) ---
        let supportsMeshShaders = device.supportsFamily(.apple9)
        let wantsMeshShaders = quality == .maximum && supportsMeshShaders

        if wantsMeshShaders,
           let objectFunc = library.makeFunction(name: "meshlet_object"),
           let meshFunc = library.makeFunction(name: "meshlet_mesh"),
           let shadowMeshFunc = library.makeFunction(name: "meshlet_shadow_mesh"),
           let depthMeshFunc = library.makeFunction(name: "meshlet_depth_mesh"),
           let pickMeshFunc = library.makeFunction(name: "meshlet_pick_mesh") {

            // Helper to create mesh render pipeline
            func makeMeshPipeline(
                meshFn: MTLFunction,
                fragmentFn: MTLFunction?,
                colorFormat: MTLPixelFormat,
                depthFmt: MTLPixelFormat,
                stencilFmt: MTLPixelFormat = .invalid,
                samples: Int = 1,
                label: String
            ) -> MTLRenderPipelineState? {
                let desc = MTLMeshRenderPipelineDescriptor()
                desc.label = label
                desc.objectFunction = objectFunc
                desc.meshFunction = meshFn
                desc.fragmentFunction = fragmentFn
                if colorFormat != .invalid {
                    desc.colorAttachments[0].pixelFormat = colorFormat
                }
                desc.depthAttachmentPixelFormat = depthFmt
                if stencilFmt != .invalid {
                    desc.stencilAttachmentPixelFormat = stencilFmt
                }
                desc.rasterSampleCount = samples
                desc.maxTotalThreadsPerObjectThreadgroup = 1
                desc.maxTotalThreadsPerMeshThreadgroup = 64
                return try? device.makeRenderPipelineState(descriptor: desc, options: []).0
            }

            let shadedFrag = library.makeFunction(name: "shaded_fragment")!
            let depthFrag = library.makeFunction(name: "depth_only_fragment")
            let pickFrag = library.makeFunction(name: "pick_fragment")

            self.meshShaderShadedPipeline = makeMeshPipeline(
                meshFn: meshFunc, fragmentFn: shadedFrag,
                colorFormat: .bgra8Unorm, depthFmt: depthFormat, stencilFmt: depthFormat,
                samples: sampleCount, label: "mesh_shaded"
            )
            self.meshShaderShadowPipeline = makeMeshPipeline(
                meshFn: shadowMeshFunc, fragmentFn: depthFrag,
                colorFormat: .invalid, depthFmt: .depth32Float,
                label: "mesh_shadow"
            )
            self.meshShaderDepthOnlyPipeline = makeMeshPipeline(
                meshFn: depthMeshFunc, fragmentFn: depthFrag,
                colorFormat: .invalid, depthFmt: .depth32Float,
                label: "mesh_depth_only"
            )
            self.meshShaderPickPipeline = makeMeshPipeline(
                meshFn: pickMeshFunc, fragmentFn: pickFrag,
                colorFormat: .r32Uint, depthFmt: .depth32Float,
                label: "mesh_pick"
            )
            self.meshShadersEnabled = meshShaderShadedPipeline != nil
            NSLog("[ViewportRenderer] Mesh shaders: %@", meshShaderShadedPipeline != nil ? "enabled" : "FAILED")
        } else {
            self.meshShaderShadedPipeline = nil
            self.meshShaderShadowPipeline = nil
            self.meshShaderDepthOnlyPipeline = nil
            self.meshShaderPickPipeline = nil
            self.meshShadersEnabled = false
            NSLog("[ViewportRenderer] Mesh shaders: skipped (supports=%d)", supportsMeshShaders)
        }

        // SSAO post-process pipeline (1x, renders to drawable)
        let ssaoDesc = MTLRenderPipelineDescriptor()
        ssaoDesc.label = "ssao_postprocess"
        ssaoDesc.vertexFunction = library.makeFunction(name: "fullscreen_vertex")
        ssaoDesc.fragmentFunction = library.makeFunction(name: "ssao_fragment")
        ssaoDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        // SSAO output goes directly to the MSAA resolve target (drawable), so sampleCount=1
        // No depth needed for this fullscreen pass
        self.ssaoPipeline = try? device.makeRenderPipelineState(descriptor: ssaoDesc)

        // TAA resolve pipeline (1x fullscreen pass)
        let taaDesc = MTLRenderPipelineDescriptor()
        taaDesc.label = "taa_resolve"
        taaDesc.vertexFunction = library.makeFunction(name: "fullscreen_vertex")
        taaDesc.fragmentFunction = library.makeFunction(name: "taa_resolve_fragment")
        taaDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        self.taaPipeline = try? device.makeRenderPipelineState(descriptor: taaDesc)

        // Depth stencil state
        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.depthCompareFunction = .less
        depthDesc.isDepthWriteEnabled = true

        guard let depthState = device.makeDepthStencilState(descriptor: depthDesc) else {
            return nil
        }
        self.depthState = depthState

        // Stencil write state: write reference value to stencil for selected bodies
        let stencilWriteDesc = MTLDepthStencilDescriptor()
        stencilWriteDesc.depthCompareFunction = .less
        stencilWriteDesc.isDepthWriteEnabled = true
        let writeStencil = MTLStencilDescriptor()
        writeStencil.stencilCompareFunction = .always
        writeStencil.depthStencilPassOperation = .replace
        writeStencil.stencilFailureOperation = .keep
        writeStencil.depthFailureOperation = .keep
        stencilWriteDesc.frontFaceStencil = writeStencil
        stencilWriteDesc.backFaceStencil = writeStencil

        guard let stencilWriteState = device.makeDepthStencilState(descriptor: stencilWriteDesc) else {
            return nil
        }
        self.stencilWriteState = stencilWriteState

        // Stencil test state: only draw where stencil != reference (the outline ring)
        let stencilTestDesc = MTLDepthStencilDescriptor()
        stencilTestDesc.depthCompareFunction = .always
        stencilTestDesc.isDepthWriteEnabled = false
        let testStencil = MTLStencilDescriptor()
        testStencil.stencilCompareFunction = .notEqual
        testStencil.stencilFailureOperation = .keep
        testStencil.depthStencilPassOperation = .keep
        testStencil.depthFailureOperation = .keep
        stencilTestDesc.frontFaceStencil = testStencil
        stencilTestDesc.backFaceStencil = testStencil

        guard let stencilTestState = device.makeDepthStencilState(descriptor: stencilTestDesc) else {
            return nil
        }
        self.stencilTestState = stencilTestState

        // Build axis vertex buffer (6 vertices for 3 lines)
        let axisLength: Float = 1000.0
        let axisData: [Float] = [
            // X axis: red
            0, 0, 0,   1, 0, 0, 1,
            axisLength, 0, 0,   1, 0, 0, 1,
            // Y axis: green
            0, 0, 0,   0, 1, 0, 1,
            0, axisLength, 0,   0, 1, 0, 1,
            // Z axis: blue
            0, 0, 0,   0, 0, 1, 1,
            0, 0, axisLength,   0, 0, 1, 1,
        ]
        guard let axisVB = device.makeBuffer(
            bytes: axisData,
            length: axisData.count * MemoryLayout<Float>.size,
            options: .storageModeShared
        ) else {
            return nil
        }
        self.axisVertexBuffer = axisVB

        // Generate procedural matcap texture (256x256 RGBA8)
        let matcapSize = 256
        let matcapDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: matcapSize,
            height: matcapSize,
            mipmapped: false
        )
        matcapDesc.usage = [.shaderRead]
        guard let matcap = device.makeTexture(descriptor: matcapDesc) else {
            return nil
        }

        var matcapPixels = [UInt8](repeating: 0, count: matcapSize * matcapSize * 4)
        for y in 0..<matcapSize {
            for x in 0..<matcapSize {
                // Map pixel to [-1, 1] UV space
                let u = (Float(x) + 0.5) / Float(matcapSize) * 2.0 - 1.0
                let v = (Float(y) + 0.5) / Float(matcapSize) * 2.0 - 1.0
                let r2 = u * u + v * v

                var r: Float = 0.1
                var g: Float = 0.1
                var b: Float = 0.1

                if r2 <= 1.0 {
                    // Reconstruct view-space normal from UV
                    let nz = sqrt(1.0 - r2)
                    let nx = u
                    let ny = -v

                    // Studio lighting: key from upper-left, fill from right
                    let keyDir = simd_normalize(SIMD3<Float>(-0.5, 0.7, 0.5))
                    let fillDir = simd_normalize(SIMD3<Float>(0.6, 0.2, 0.7))
                    let normal = SIMD3<Float>(nx, ny, nz)

                    let keyDiff = max(simd_dot(normal, keyDir), 0.0) * 0.8
                    let fillDiff = max(simd_dot(normal, fillDir), 0.0) * 0.3

                    // Rim highlight
                    let rim = pow(1.0 - nz, 3.0) * 0.25

                    // Ambient base
                    let ambient: Float = 0.18

                    let brightness = min(keyDiff + fillDiff + rim + ambient, 1.0)
                    // Slight warm-cool tint
                    r = brightness * 1.0
                    g = brightness * 0.97
                    b = brightness * 0.95
                }

                let idx = (y * matcapSize + x) * 4
                matcapPixels[idx + 0] = UInt8(min(max(r * 255.0, 0), 255))
                matcapPixels[idx + 1] = UInt8(min(max(g * 255.0, 0), 255))
                matcapPixels[idx + 2] = UInt8(min(max(b * 255.0, 0), 255))
                matcapPixels[idx + 3] = 255
            }
        }

        matcap.replace(
            region: MTLRegionMake2D(0, 0, matcapSize, matcapSize),
            mipmapLevel: 0,
            withBytes: matcapPixels,
            bytesPerRow: matcapSize * 4
        )
        self.matcapTexture = matcap

        // Picking: texture manager + 4-byte shared readback buffer
        self.pickTextureManager = PickTextureManager(device: device)
        guard let readback = device.makeBuffer(length: MemoryLayout<UInt32>.size, options: .storageModeShared) else {
            return nil
        }
        self.pickReadbackBuffer = readback

        // Environment map manager (IBL)
        self.environmentMapManager = EnvironmentMapManager(device: device, library: library)

        super.init()
    }

    // MARK: - Public

    /// The Metal device, exposed for MTKView configuration.
    public var metalDevice: MTLDevice { device }

    /// Loads an equirectangular HDR image as the environment map for IBL.
    /// Legacy path; expects raw bytes with `Int32 width | Int32 height | RGBA32Float pixels`.
    public func loadEnvironmentMap(data: Data) {
        environmentMapManager?.loadEquirectangular(data: data, commandQueue: commandQueue)
    }

    /// Loads an HDR environment map from a file URL (Radiance `.hdr`).
    /// Throws on parse failure; on success, generates the prefiltered/irradiance/cube maps.
    public func loadEnvironmentMap(url: URL) throws {
        try environmentMapManager?.loadHDR(url: url, commandQueue: commandQueue)
    }

    /// Loads pre-decoded equirectangular RGBA32Float pixels into the IBL pipeline.
    public func loadEnvironmentMap(width: Int, height: Int, pixels: [Float]) {
        environmentMapManager?.loadEquirectangular(width: width, height: height, pixels: pixels, commandQueue: commandQueue)
    }

    /// Clears the current environment map.
    public func clearEnvironmentMap() {
        environmentMapManager?.clear()
    }

    /// Invalidates cached buffers so they are rebuilt on next draw.
    public func invalidateBuffers() {
        bodyBufferCache.removeAll()
        bodyGeneration.removeAll()
    }

    // MARK: - MTKViewDelegate

    nonisolated public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Handled in draw via drawable size
    }

    nonisolated public func draw(in view: MTKView) {
        MainActor.assumeIsolated {
            drawOnMainActor(in: view)
        }
    }

    // MARK: - Draw

    /// Ensures 1x resolved color + depth textures for SSAO input.
    private func ensureResolvedTextures(width: Int, height: Int) {
        guard width > 0, height > 0 else { return }
        guard width != resolvedWidth || height != resolvedHeight else { return }

        // 1x color texture that receives the MSAA resolve output
        let colorDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        colorDesc.usage = [.renderTarget, .shaderRead]
        colorDesc.storageMode = .private
        resolvedColorTexture = device.makeTexture(descriptor: colorDesc)

        // 1x depth texture for SSAO depth sampling
        let depthDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: width,
            height: height,
            mipmapped: false
        )
        depthDesc.usage = [.renderTarget, .shaderRead]
        depthDesc.storageMode = .private
        resolvedDepthTexture = device.makeTexture(descriptor: depthDesc)

        resolvedWidth = width
        resolvedHeight = height
    }

    /// Ensures TAA history + output textures exist at the given size.
    private func ensureTAATextures(width: Int, height: Int) {
        guard width > 0, height > 0 else { return }
        if let existing = taaHistoryTexture, existing.width == width, existing.height == height { return }

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private

        taaHistoryTexture = device.makeTexture(descriptor: desc)
        taaOutputTexture = device.makeTexture(descriptor: desc)
        taaFrameIndex = 0
    }

    /// Halton sequence value for sub-pixel jitter.
    private func halton(index: UInt32, base: UInt32) -> Float {
        var f: Float = 1.0
        var r: Float = 0.0
        var i = index
        while i > 0 {
            f /= Float(base)
            r += f * Float(i % base)
            i /= base
        }
        return r
    }

    /// Ensures the 1x depth texture for the pick pass matches the given size.
    private func ensurePickDepthTexture(width: Int, height: Int) {
        guard width > 0, height > 0 else { return }
        guard width != pickDepthWidth || height != pickDepthHeight else { return }

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = [.renderTarget]
        desc.storageMode = .private
        desc.sampleCount = 1

        pickDepthTexture = device.makeTexture(descriptor: desc)
        pickDepthWidth = width
        pickDepthHeight = height
    }

    private func drawOnMainActor(in view: MTKView) {
        guard let controller = controller else { return }
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor else { return }

        let cameraState = controller.cameraState
        let drawableSize = view.drawableSize
        let aspectRatio = Float(drawableSize.width / drawableSize.height)

        let viewMatrix = cameraState.viewMatrix
        var projMatrix = cameraState.projectionMatrix(aspectRatio: aspectRatio, near: 0.01, far: 10000.0)

        // TAA / progressive accumulation: apply Halton(2,3) sub-pixel jitter to the
        // projection matrix so each frame rasterizes at a different sub-pixel offset.
        // Without this, the existing TAA resolve only softens — it doesn't supersample.
        // We must compute the jitter here (pre-draw) to use the same value in the
        // TAA resolve pass below.
        let taaWillRun = controller.enableTAA && taaPipeline != nil
        let jitterPx: SIMD2<Float>
        if taaWillRun {
            let jx = halton(index: taaFrameIndex + 1, base: 2) - 0.5
            let jy = halton(index: taaFrameIndex + 1, base: 3) - 0.5
            jitterPx = SIMD2<Float>(jx, jy)
            // Convert pixel offset to NDC and bake into the projection matrix's column 2.
            // For both perspective and orthographic, this shifts the rasterized image
            // by (jx, jy) pixels post-projection.
            let w = Float(drawableSize.width)
            let h = Float(drawableSize.height)
            projMatrix.columns.2[0] += 2.0 * jx / w
            projMatrix.columns.2[1] += 2.0 * jy / h
        } else {
            jitterPx = .zero
        }

        let viewProjection = projMatrix * viewMatrix

        let lighting = controller.lightingConfiguration

        let nearPlane: Float = 0.01
        let farPlane: Float = 10000.0

        // Pack lights from lighting configuration
        let lightSources = [lighting.keyLight, lighting.fillLight, lighting.backLight]
        func packLight(_ ls: LightSettings) -> LightDataSwift {
            let typeVal: Float
            let radiusVal: Float
            switch ls.lightType {
            case .directional:
                typeVal = 0.0
                radiusVal = 0.0
            case .point(let radius):
                typeVal = 1.0
                radiusVal = radius
            }
            return LightDataSwift(
                directionAndIntensity: SIMD4<Float>(ls.direction.x, ls.direction.y, ls.direction.z, ls.intensity),
                colorAndEnabled: SIMD4<Float>(ls.color.x, ls.color.y, ls.color.z, ls.isEnabled ? 1.0 : 0.0),
                typeAndParams: SIMD4<Float>(typeVal, radiusVal, 0, 0),
                positionAndPad: SIMD4<Float>(ls.position.x, ls.position.y, ls.position.z, 0)
            )
        }

        // Debug toggles
        let useTessellation = tessellationEnabled && !controller.debugDisableTessellation
        let useMeshShaders = meshShadersEnabled && !controller.debugDisableTessellation

        // Shadow mapping: compute light VP matrix from key light direction
        let shadowEnabled = lighting.shadowsEnabled
        let lightVP: simd_float4x4
        if shadowEnabled {
            lightVP = computeLightViewProjection(lightDir: lighting.keyLight.direction, bodies: bodiesBinding.wrappedValue)
        } else {
            lightVP = matrix_identity_float4x4
        }
        let edgeIntensity = controller.edgeIntensity
        let shadowParams = SIMD4<Float>(
            lighting.shadowBias,
            lighting.shadowIntensity,
            shadowEnabled ? 1.0 : 0.0,
            edgeIntensity
        )

        // Collect active clip planes (up to 4)
        let activeClipPlanes = Array(controller.clipPlanes.filter { $0.isEnabled }.prefix(4))
        let clipPlaneVecs: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>) = {
            var planes: [SIMD4<Float>] = activeClipPlanes.map { $0.asFloat4 }
            while planes.count < 4 { planes.append(.zero) }
            return (planes[0], planes[1], planes[2], planes[3])
        }()
        let clipPlaneCount = UInt32(activeClipPlanes.count)

        let shadowParams2 = SIMD4<Float>(
            lighting.shadowLightSize,
            lighting.shadowSearchRadius,
            controller.debugDisableCurvature ? 1.0 : 0.0,
            0
        )

        let hasEnvMap: Float = (environmentMapManager?.hasEnvironmentMap ?? false) ? 1.0 : 0.0
        let iblParams = SIMD4<Float>(
            lighting.environmentIntensity,
            lighting.environmentRotationY,
            lighting.backgroundExposure,
            hasEnvMap
        )

        func makeUniforms() -> Uniforms {
            Uniforms(
                viewProjectionMatrix: viewProjection,
                modelMatrix: matrix_identity_float4x4,
                viewMatrix: viewMatrix,
                cameraPosition: SIMD4<Float>(cameraState.position.x, cameraState.position.y, cameraState.position.z, nearPlane),
                light0: packLight(lightSources[0]),
                light1: packLight(lightSources[1]),
                light2: packLight(lightSources[2]),
                ambientSkyColor: SIMD4<Float>(lighting.ambientSkyColor.x, lighting.ambientSkyColor.y, lighting.ambientSkyColor.z, lighting.specularPower),
                ambientGroundColor: SIMD4<Float>(lighting.ambientGroundColor.x, lighting.ambientGroundColor.y, lighting.ambientGroundColor.z, lighting.specularIntensity),
                materialParams: SIMD4<Float>(lighting.fresnelPower, lighting.fresnelIntensity, lighting.matcapBlend, farPlane),
                lightViewProjectionMatrix: lightVP,
                shadowParams: shadowParams,
                shadowParams2: shadowParams2,
                iblParams: iblParams,
                clipPlanes: clipPlaneVecs,
                clipPlaneCount: clipPlaneCount
            )
        }

        let bodies = bodiesBinding.wrappedValue
        let displayMode = controller.displayMode

        // Build index map for picking: objectIndex → bodyID
        var indexMap: [Int: String] = [:]
        var objectIndex: UInt32 = 0

        // Ensure buffers for all visible bodies
        for body in bodies where body.isVisible {
            ensureBuffers(for: body)
            indexMap[Int(objectIndex)] = body.id
            objectIndex += 1
        }
        currentIndexMap = indexMap

        let silhouettesEnabled = controller.configuration.enableSilhouettes
        let ssaoEnabled = (lighting.enableSSAO || silhouettesEnabled) && ssaoPipeline != nil && displayMode.showsSurfaces
        let taaEnabled = controller.enableTAA && taaPipeline != nil
        let w = Int(drawableSize.width)
        let h = Int(drawableSize.height)

        if ssaoEnabled || taaEnabled {
            ensureResolvedTextures(width: w, height: h)
        }
        if taaEnabled {
            ensureTAATextures(width: w, height: h)
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        // =========================================================
        // Pre-pass: Update tessellation factors (per-frame, camera-dependent)
        // =========================================================
        if useTessellation, let tessMgr = tessellationManager {
            var tessBufferList: [(TessellationBuffers, simd_float4x4)] = []
            var tessBodyCount = 0
            var nonTessBodyCount = 0
            for body in bodies where body.isVisible {
                if let buffers = bodyBufferCache[body.id] {
                    if let tess = buffers.tessellation {
                        tessBufferList.append((tess, matrix_identity_float4x4))
                        tessBodyCount += 1
                    } else if buffers.indexCount > 0 {
                        nonTessBodyCount += 1
                    }
                }
            }
            // One-time diagnostic log
            if tessBufferList.isEmpty && nonTessBodyCount > 0 {
                NSLog("[ViewportRenderer] WARNING: %d bodies have no tessellation data", nonTessBodyCount)
            }
            if !tessBufferList.isEmpty,
               let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
                let config = controller.configuration
                tessMgr.updateTessFactors(
                    tessBuffers: tessBufferList,
                    viewProjectionMatrix: viewProjection,
                    viewportSize: SIMD2<Float>(Float(w), Float(h)),
                    targetEdgePixels: config.adaptiveTessellation ? 4.0 : 1.0,
                    maxFactor: Float(config.tessellationMaxFactor),
                    encoder: computeEncoder
                )
                computeEncoder.endEncoding()
            }
        }

        // =========================================================
        // Pass 0: Shadow map (if enabled)
        // =========================================================
        if shadowEnabled {
            let mapSize = lighting.shadowMapSize
            shadowMapManager.ensureSize(mapSize)

            if let shadowTex = shadowMapManager.texture {
                let shadowPass = MTLRenderPassDescriptor()
                shadowPass.depthAttachment.texture = shadowTex
                shadowPass.depthAttachment.loadAction = .clear
                shadowPass.depthAttachment.storeAction = .store
                shadowPass.depthAttachment.clearDepth = 1.0

                if let shadowEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: shadowPass) {
                    shadowEncoder.setDepthStencilState(depthState)
                    shadowEncoder.setCullMode(.front) // Reduce shadow acne with front-face culling
                    shadowEncoder.setDepthBias(0.01, slopeScale: 1.5, clamp: 0.02)

                    for body in bodies where body.isVisible {
                        guard let buffers = bodyBufferCache[body.id] else { continue }
                        let hasMesh = buffers.vertexBuffer != nil && buffers.indexBuffer != nil && buffers.indexCount > 0

                        if hasMesh, let vb = buffers.vertexBuffer, let ib = buffers.indexBuffer {
                            var shadowUniforms = ShadowUniformsSwift(
                                lightViewProjectionMatrix: lightVP,
                                modelMatrix: matrix_identity_float4x4
                            )

                            if useMeshShaders, let ml = buffers.meshlets, let msPipeline = meshShaderShadowPipeline {
                                shadowEncoder.setRenderPipelineState(msPipeline)
                                shadowEncoder.setObjectBuffer(ml.descriptorBuffer, offset: 0, index: 0)
                                shadowEncoder.setObjectBytes(&shadowUniforms, length: MemoryLayout<ShadowUniformsSwift>.size, index: 1)
                                shadowEncoder.setMeshBuffer(ml.descriptorBuffer, offset: 0, index: 0)
                                shadowEncoder.setMeshBuffer(vb, offset: 0, index: 1)
                                shadowEncoder.setMeshBuffer(ml.vertexIndexBuffer, offset: 0, index: 2)
                                shadowEncoder.setMeshBuffer(ml.triangleIndexBuffer, offset: 0, index: 3)
                                shadowEncoder.setMeshBytes(&shadowUniforms, length: MemoryLayout<ShadowUniformsSwift>.size, index: 4)
                                shadowEncoder.drawMeshThreadgroups(
                                    MTLSize(width: ml.meshletCount, height: 1, depth: 1),
                                    threadsPerObjectThreadgroup: MTLSize(width: 1, height: 1, depth: 1),
                                    threadsPerMeshThreadgroup: MTLSize(width: 64, height: 1, depth: 1)
                                )
                            } else if useTessellation, let tess = buffers.tessellation, let tessPipeline = tessellatedShadowPipeline {
                                shadowEncoder.setRenderPipelineState(tessPipeline)
                                shadowEncoder.setTessellationFactorBuffer(tess.tessFactorBuffer, offset: 0, instanceStride: 0)
                                shadowEncoder.setVertexBuffer(tess.patchDataBuffer, offset: 0, index: 0)
                                shadowEncoder.setVertexBytes(&shadowUniforms, length: MemoryLayout<ShadowUniformsSwift>.size, index: 1)
                                shadowEncoder.drawPatches(
                                    numberOfPatchControlPoints: 3,
                                    patchStart: 0,
                                    patchCount: tess.patchCount,
                                    patchIndexBuffer: nil,
                                    patchIndexBufferOffset: 0,
                                    instanceCount: 1,
                                    baseInstance: 0
                                )
                            } else {
                                shadowEncoder.setRenderPipelineState(shadowPipeline)
                                shadowEncoder.setVertexBuffer(vb, offset: 0, index: 0)
                                shadowEncoder.setVertexBytes(&shadowUniforms, length: MemoryLayout<ShadowUniformsSwift>.size, index: 1)
                                shadowEncoder.drawIndexedPrimitives(
                                    type: .triangle,
                                    indexCount: buffers.indexCount,
                                    indexType: .uint32,
                                    indexBuffer: ib,
                                    indexBufferOffset: 0
                                )
                            }
                        }
                    }
                    shadowEncoder.endEncoding()
                }
            }
        }

        // =========================================================
        // Pass 1: Main MSAA render (color-only, no pick texture)
        // =========================================================
        renderPassDescriptor.colorAttachments[1].texture = nil

        // When SSAO or TAA is enabled, redirect MSAA resolve to our intermediate texture
        if (ssaoEnabled || taaEnabled), let resolvedColor = resolvedColorTexture {
            if msaaSampleCount > 1 {
                renderPassDescriptor.colorAttachments[0].resolveTexture = resolvedColor
            } else {
                // No MSAA: render directly to resolved color texture
                renderPassDescriptor.colorAttachments[0].texture = resolvedColor
            }
        }

        guard let mainEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
        mainEncoder.setDepthStencilState(depthState)

        // 0. Draw skybox background (HDR cubemap), if enabled.
        if lighting.drawBackground,
           let envMgr = environmentMapManager,
           let cubeMap = envMgr.cubeMap,
           let skyPipeline = skyboxPipeline,
           let skyDepth = skyboxDepthState {
            mainEncoder.setRenderPipelineState(skyPipeline)
            mainEncoder.setDepthStencilState(skyDepth)
            var skyUniforms = SkyboxUniformsSwift(
                inverseViewProjection: simd_inverse(viewProjection),
                params: SIMD4<Float>(
                    lighting.environmentRotationY,
                    lighting.backgroundExposure,
                    0, // mip level — sharp background
                    0
                )
            )
            mainEncoder.setVertexBytes(&skyUniforms, length: MemoryLayout<SkyboxUniformsSwift>.size, index: 0)
            mainEncoder.setFragmentBytes(&skyUniforms, length: MemoryLayout<SkyboxUniformsSwift>.size, index: 0)
            mainEncoder.setFragmentTexture(cubeMap, index: 0)
            mainEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            mainEncoder.setDepthStencilState(depthState)
        }

        // 1. Draw grid
        if controller.showGrid {
            drawGrid(encoder: mainEncoder, viewProjection: viewProjection, cameraState: cameraState, config: controller.configuration)
        }

        // 2. Draw axes
        if controller.showAxes {
            drawAxes(encoder: mainEncoder, viewProjection: viewProjection)
        }

        // 3. Draw bodies
        let selectedIDs = controller.selectedBodyIDs
        let hoveredID = controller.hoveredBodyID

        objectIndex = 0
        for body in bodies where body.isVisible {
            guard let buffers = bodyBufferCache[body.id] else {
                objectIndex += 1
                continue
            }

            var uniforms = makeUniforms()

            let selState: UInt32 = selectedIDs.contains(body.id) ? 1 : (hoveredID == body.id ? 2 : 0)
            var bodyUniforms = BodyUniforms(body: body, objectIndex: objectIndex, isSelected: selState)

            let hasMesh = buffers.vertexBuffer != nil && buffers.indexBuffer != nil && buffers.indexCount > 0
            let hasEdges = buffers.edgeVertexBuffer != nil && buffers.edgeVertexCount > 0

            // Shaded pass (mesh bodies only)
            if displayMode.showsSurfaces, hasMesh,
               let vb = buffers.vertexBuffer, let ib = buffers.indexBuffer {
                // Write stencil=1 for selected bodies
                if selState > 0 {
                    mainEncoder.setDepthStencilState(stencilWriteState)
                    mainEncoder.setStencilReferenceValue(1)
                } else {
                    mainEncoder.setDepthStencilState(depthState)
                }

                // Set shared fragment state (same for tessellated and non-tessellated)
                mainEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)
                mainEncoder.setFragmentBytes(&bodyUniforms, length: MemoryLayout<BodyUniforms>.size, index: 2)
                mainEncoder.setFragmentTexture(matcapTexture, index: 0)
                if shadowEnabled, let shadowTex = shadowMapManager.texture {
                    mainEncoder.setFragmentTexture(shadowTex, index: 1)
                }
                if let envMgr = environmentMapManager, envMgr.hasEnvironmentMap {
                    if let spec = envMgr.prefilteredSpecularMap { mainEncoder.setFragmentTexture(spec, index: 2) }
                    if let diff = envMgr.irradianceMap { mainEncoder.setFragmentTexture(diff, index: 3) }
                    if let brdf = envMgr.brdfLUT { mainEncoder.setFragmentTexture(brdf, index: 4) }
                }

                if useMeshShaders, let ml = buffers.meshlets, let msPipeline = meshShaderShadedPipeline {
                    mainEncoder.setRenderPipelineState(msPipeline)
                    mainEncoder.setObjectBuffer(ml.descriptorBuffer, offset: 0, index: 0)
                    mainEncoder.setObjectBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)
                    mainEncoder.setMeshBuffer(ml.descriptorBuffer, offset: 0, index: 0)
                    mainEncoder.setMeshBuffer(vb, offset: 0, index: 1)
                    mainEncoder.setMeshBuffer(ml.vertexIndexBuffer, offset: 0, index: 2)
                    mainEncoder.setMeshBuffer(ml.triangleIndexBuffer, offset: 0, index: 3)
                    mainEncoder.setMeshBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 4)
                    mainEncoder.drawMeshThreadgroups(
                        MTLSize(width: ml.meshletCount, height: 1, depth: 1),
                        threadsPerObjectThreadgroup: MTLSize(width: 1, height: 1, depth: 1),
                        threadsPerMeshThreadgroup: MTLSize(width: 64, height: 1, depth: 1)
                    )
                } else if useTessellation, let tess = buffers.tessellation, let tessPipeline = tessellatedShadedPipeline {
                    mainEncoder.setRenderPipelineState(tessPipeline)
                    mainEncoder.setTessellationFactorBuffer(tess.tessFactorBuffer, offset: 0, instanceStride: 0)
                    mainEncoder.setVertexBuffer(tess.patchDataBuffer, offset: 0, index: 0)
                    mainEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)
                    mainEncoder.drawPatches(
                        numberOfPatchControlPoints: 3,
                        patchStart: 0,
                        patchCount: tess.patchCount,
                        patchIndexBuffer: nil,
                        patchIndexBufferOffset: 0,
                        instanceCount: 1,
                        baseInstance: 0
                    )
                } else {
                    mainEncoder.setRenderPipelineState(shadedPipeline)
                    mainEncoder.setVertexBuffer(vb, offset: 0, index: 0)
                    mainEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)
                    mainEncoder.drawIndexedPrimitives(
                        type: .triangle,
                        indexCount: buffers.indexCount,
                        indexType: .uint32,
                        indexBuffer: ib,
                        indexBufferOffset: 0
                    )
                }
            }

            // Wireframe/edge pass
            let shouldDrawEdges = hasEdges && (displayMode.showsEdges || !hasMesh)
            if shouldDrawEdges, let edgeVB = buffers.edgeVertexBuffer {
                // For edge-only bodies, signal the shader to use the body color directly
                // instead of contrast-adaptive edge color (metallic = -1 sentinel)
                var edgeBodyUniforms = bodyUniforms
                if !hasMesh {
                    edgeBodyUniforms.metallic = -1.0
                }
                mainEncoder.setRenderPipelineState(wireframePipeline)
                mainEncoder.setVertexBuffer(edgeVB, offset: 0, index: 0)
                mainEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)
                mainEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)
                mainEncoder.setFragmentBytes(&edgeBodyUniforms, length: MemoryLayout<BodyUniforms>.size, index: 2)
                mainEncoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: buffers.edgeVertexCount)
            }

            objectIndex += 1
        }

        // 4. Selection outline pass (stencil test: draw only where stencil != 1)
        let allSelectedIDs = selectedIDs.union(hoveredID.map { [$0] } ?? [])
        if !allSelectedIDs.isEmpty {
            mainEncoder.setRenderPipelineState(outlinePipeline)
            mainEncoder.setDepthStencilState(stencilTestState)
            mainEncoder.setStencilReferenceValue(1)

            for body in bodies where body.isVisible && allSelectedIDs.contains(body.id) {
                guard let buffers = bodyBufferCache[body.id],
                      let vb = buffers.vertexBuffer,
                      let ib = buffers.indexBuffer,
                      buffers.indexCount > 0 else { continue }

                let isHover = (hoveredID == body.id && !selectedIDs.contains(body.id))
                let outlineColor: SIMD3<Float> = isHover
                    ? SIMD3<Float>(0.4, 0.7, 1.0)  // light blue for hover
                    : SIMD3<Float>(0.1, 0.5, 1.0)   // bright blue for selection

                var outlineParams = SelectionOutlineParamsSwift(
                    viewProjectionMatrix: viewProjection,
                    modelMatrix: matrix_identity_float4x4,
                    outlineColor: outlineColor,
                    outlineScale: 0.015
                )

                mainEncoder.setVertexBuffer(vb, offset: 0, index: 0)
                mainEncoder.setVertexBytes(&outlineParams, length: MemoryLayout<SelectionOutlineParamsSwift>.size, index: 1)
                mainEncoder.setFragmentBytes(&outlineParams, length: MemoryLayout<SelectionOutlineParamsSwift>.size, index: 1)
                mainEncoder.drawIndexedPrimitives(
                    type: .triangle,
                    indexCount: buffers.indexCount,
                    indexType: .uint32,
                    indexBuffer: ib,
                    indexBufferOffset: 0
                )
            }
        }

        mainEncoder.endEncoding()

        // =========================================================
        // Pass 2: 1x Pick pass (R32Uint, no MSAA)
        // =========================================================
        let pickingEnabled = controller.configuration.pickingConfiguration.isEnabled
        if pickingEnabled {
            let w = Int(drawableSize.width)
            let h = Int(drawableSize.height)
            pickTextureManager.ensureSize(width: w, height: h)
            ensurePickDepthTexture(width: w, height: h)

            if let pickTex = pickTextureManager.texture, let pickDepth = pickDepthTexture {
                let pickPass = MTLRenderPassDescriptor()
                pickPass.colorAttachments[0].texture = pickTex
                pickPass.colorAttachments[0].loadAction = .clear
                pickPass.colorAttachments[0].storeAction = .store
                pickPass.colorAttachments[0].clearColor = MTLClearColor(
                    red: Double(0xFFFF_FFFF),
                    green: 0, blue: 0, alpha: 0
                )
                pickPass.depthAttachment.texture = pickDepth
                pickPass.depthAttachment.loadAction = .clear
                pickPass.depthAttachment.storeAction = .dontCare
                pickPass.depthAttachment.clearDepth = 1.0

                if let pickEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: pickPass) {
                    pickEncoder.setDepthStencilState(depthState)

                    objectIndex = 0
                    for body in bodies where body.isVisible {
                        guard let buffers = bodyBufferCache[body.id] else {
                            objectIndex += 1
                            continue
                        }

                        let hasMesh = buffers.vertexBuffer != nil && buffers.indexBuffer != nil && buffers.indexCount > 0

                        if hasMesh, let vb = buffers.vertexBuffer, let ib = buffers.indexBuffer {
                            var uniforms = makeUniforms()
                            var bodyUniforms = BodyUniforms(body: body, objectIndex: objectIndex)

                            if useMeshShaders, let ml = buffers.meshlets, let msPipeline = meshShaderPickPipeline {
                                pickEncoder.setRenderPipelineState(msPipeline)
                                pickEncoder.setObjectBuffer(ml.descriptorBuffer, offset: 0, index: 0)
                                pickEncoder.setObjectBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)
                                pickEncoder.setMeshBuffer(ml.descriptorBuffer, offset: 0, index: 0)
                                pickEncoder.setMeshBuffer(vb, offset: 0, index: 1)
                                pickEncoder.setMeshBuffer(ml.vertexIndexBuffer, offset: 0, index: 2)
                                pickEncoder.setMeshBuffer(ml.triangleIndexBuffer, offset: 0, index: 3)
                                pickEncoder.setMeshBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 4)
                                pickEncoder.setFragmentBytes(&bodyUniforms, length: MemoryLayout<BodyUniforms>.size, index: 2)
                                pickEncoder.drawMeshThreadgroups(
                                    MTLSize(width: ml.meshletCount, height: 1, depth: 1),
                                    threadsPerObjectThreadgroup: MTLSize(width: 1, height: 1, depth: 1),
                                    threadsPerMeshThreadgroup: MTLSize(width: 64, height: 1, depth: 1)
                                )
                            } else if useTessellation, let tess = buffers.tessellation, let tessPipeline = tessellatedPickPipeline {
                                pickEncoder.setRenderPipelineState(tessPipeline)
                                pickEncoder.setTessellationFactorBuffer(tess.tessFactorBuffer, offset: 0, instanceStride: 0)
                                pickEncoder.setVertexBuffer(tess.patchDataBuffer, offset: 0, index: 0)
                                pickEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)
                                pickEncoder.setFragmentBytes(&bodyUniforms, length: MemoryLayout<BodyUniforms>.size, index: 2)
                                pickEncoder.drawPatches(
                                    numberOfPatchControlPoints: 3,
                                    patchStart: 0,
                                    patchCount: tess.patchCount,
                                    patchIndexBuffer: nil,
                                    patchIndexBufferOffset: 0,
                                    instanceCount: 1,
                                    baseInstance: 0
                                )
                            } else {
                                pickEncoder.setRenderPipelineState(pickShadedPipeline)
                                pickEncoder.setVertexBuffer(vb, offset: 0, index: 0)
                                pickEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)
                                pickEncoder.setFragmentBytes(&bodyUniforms, length: MemoryLayout<BodyUniforms>.size, index: 2)
                                pickEncoder.drawIndexedPrimitives(
                                    type: .triangle,
                                    indexCount: buffers.indexCount,
                                    indexType: .uint32,
                                    indexBuffer: ib,
                                    indexBufferOffset: 0
                                )
                            }
                        }

                        objectIndex += 1
                    }

                    pickEncoder.endEncoding()
                }
            }
        }

        // =========================================================
        // Pass 2.5: TAA resolve (if enabled)
        // =========================================================
        if taaEnabled, let taaPipeline = taaPipeline,
           let resolvedColor = resolvedColorTexture,
           let taaOutput = taaOutputTexture,
           let taaHistory = taaHistoryTexture {

            // Reset accumulation when the scene changes (camera move or animation).
            let cameraChanged = (lastCameraState == nil || lastCameraState! != cameraState)
            let isAnimating = controller.isAnimating
            if cameraChanged || isAnimating {
                taaFrameIndex = 0
            }

            let progressive = controller.enableProgressiveAccumulation && !isAnimating
            // Progressive mode: history weight = N/(N+1), unbounded N up to 256, no clamp.
            // Standard TAA mode: history weight = taaBlendFactor (0.9), 16-frame jitter cycle.
            let blendFactor: Float
            if progressive {
                blendFactor = taaFrameIndex == 0 ? 0 : Float(taaFrameIndex) / Float(taaFrameIndex + 1)
            } else {
                blendFactor = taaFrameIndex > 0 ? controller.taaBlendFactor : 0
            }
            let disableClamp: Float = progressive ? 1 : 0

            let taaPass = MTLRenderPassDescriptor()
            taaPass.colorAttachments[0].texture = taaOutput
            taaPass.colorAttachments[0].loadAction = .dontCare
            taaPass.colorAttachments[0].storeAction = .store

            if let taaEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: taaPass) {
                taaEncoder.setRenderPipelineState(taaPipeline)

                // In progressive mode, sample history at the same UV as current — each frame's
                // sub-pixel-jittered rasterization contributes to averaged supersampling.
                // In standard TAA, the unjitter step compensates so current and history align.
                let resolveJitter: SIMD2<Float> = progressive ? .zero : jitterPx
                var taaParams = TAAParamsSwift(
                    blendFactor: blendFactor,
                    disableClamp: disableClamp,
                    jitterOffset: resolveJitter,
                    texelSize: SIMD2<Float>(1.0 / Float(w), 1.0 / Float(h))
                )
                taaEncoder.setFragmentTexture(resolvedColor, index: 0)
                taaEncoder.setFragmentTexture(taaHistory, index: 1)
                taaEncoder.setFragmentBytes(&taaParams, length: MemoryLayout<TAAParamsSwift>.size, index: 0)
                taaEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                taaEncoder.endEncoding()
            }

            // Swap history: blit taaOutput → taaHistory for next frame
            if let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
                blitEncoder.copy(from: taaOutput, to: taaHistory)
                blitEncoder.endEncoding()
            }

            lastCameraState = cameraState
            // Standard TAA cycles a 16-sample Halton sequence; progressive accumulates up to 256.
            let frameCap: UInt32 = progressive ? 256 : 16
            taaFrameIndex = min(taaFrameIndex + 1, frameCap)
        }

        // Determine which color texture to feed into SSAO
        let ssaoInputColor: MTLTexture? = {
            if taaEnabled, let taaOutput = taaOutputTexture {
                return taaOutput
            }
            return resolvedColorTexture
        }()

        // =========================================================
        // Pass 3: SSAO post-process (if enabled)
        // =========================================================
        if ssaoEnabled, let ssaoPipeline = ssaoPipeline,
           let resolvedColor = ssaoInputColor,
           let resolvedDepth = resolvedDepthTexture {

            // First: render a 1x depth-only pass for SSAO sampling
            let depthOnlyPass = MTLRenderPassDescriptor()
            depthOnlyPass.depthAttachment.texture = resolvedDepth
            depthOnlyPass.depthAttachment.loadAction = .clear
            depthOnlyPass.depthAttachment.storeAction = .store
            depthOnlyPass.depthAttachment.clearDepth = 1.0

            if let depthEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: depthOnlyPass) {
                depthEncoder.setDepthStencilState(depthState)

                objectIndex = 0
                for body in bodies where body.isVisible {
                    guard let buffers = bodyBufferCache[body.id] else {
                        objectIndex += 1
                        continue
                    }
                    let hasMesh = buffers.vertexBuffer != nil && buffers.indexBuffer != nil && buffers.indexCount > 0
                    if hasMesh, let vb = buffers.vertexBuffer, let ib = buffers.indexBuffer {
                        var uniforms = makeUniforms()

                        if useMeshShaders, let ml = buffers.meshlets, let msPipeline = meshShaderDepthOnlyPipeline {
                            depthEncoder.setRenderPipelineState(msPipeline)
                            depthEncoder.setObjectBuffer(ml.descriptorBuffer, offset: 0, index: 0)
                            depthEncoder.setObjectBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)
                            depthEncoder.setMeshBuffer(ml.descriptorBuffer, offset: 0, index: 0)
                            depthEncoder.setMeshBuffer(vb, offset: 0, index: 1)
                            depthEncoder.setMeshBuffer(ml.vertexIndexBuffer, offset: 0, index: 2)
                            depthEncoder.setMeshBuffer(ml.triangleIndexBuffer, offset: 0, index: 3)
                            depthEncoder.setMeshBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 4)
                            depthEncoder.drawMeshThreadgroups(
                                MTLSize(width: ml.meshletCount, height: 1, depth: 1),
                                threadsPerObjectThreadgroup: MTLSize(width: 1, height: 1, depth: 1),
                                threadsPerMeshThreadgroup: MTLSize(width: 64, height: 1, depth: 1)
                            )
                        } else if useTessellation, let tess = buffers.tessellation, let tessPipeline = tessellatedDepthOnlyPipeline {
                            depthEncoder.setRenderPipelineState(tessPipeline)
                            depthEncoder.setTessellationFactorBuffer(tess.tessFactorBuffer, offset: 0, instanceStride: 0)
                            depthEncoder.setVertexBuffer(tess.patchDataBuffer, offset: 0, index: 0)
                            depthEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)
                            depthEncoder.drawPatches(
                                numberOfPatchControlPoints: 3,
                                patchStart: 0,
                                patchCount: tess.patchCount,
                                patchIndexBuffer: nil,
                                patchIndexBufferOffset: 0,
                                instanceCount: 1,
                                baseInstance: 0
                            )
                        } else {
                            depthEncoder.setRenderPipelineState(depthOnlyPipeline)
                            depthEncoder.setVertexBuffer(vb, offset: 0, index: 0)
                            depthEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)
                            depthEncoder.drawIndexedPrimitives(
                                type: .triangle,
                                indexCount: buffers.indexCount,
                                indexType: .uint32,
                                indexBuffer: ib,
                                indexBufferOffset: 0
                            )
                        }
                    }
                    objectIndex += 1
                }
                depthEncoder.endEncoding()
            }

            // SSAO composite pass: read resolved color + depth, output to drawable
            let ssaoPass = MTLRenderPassDescriptor()
            ssaoPass.colorAttachments[0].texture = drawable.texture
            ssaoPass.colorAttachments[0].loadAction = .dontCare
            ssaoPass.colorAttachments[0].storeAction = .store

            if let ssaoEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: ssaoPass) {
                ssaoEncoder.setRenderPipelineState(ssaoPipeline)

                let silhouetteConfig = controller.configuration
                let dofEnabled = controller.enableDepthOfField
                var dofFocalDist = controller.dofFocalDistance
                if dofEnabled && dofFocalDist == 0 {
                    // Auto-focus: use distance to scene center
                    var sceneCenter = SIMD3<Float>.zero
                    var count: Float = 0
                    for body in bodies where body.isVisible {
                        if let bb = body.boundingBox {
                            sceneCenter += (bb.min + bb.max) * 0.5
                            count += 1
                        }
                    }
                    if count > 0 {
                        sceneCenter /= count
                        dofFocalDist = simd_distance(cameraState.position, sceneCenter)
                    } else {
                        dofFocalDist = cameraState.distance
                    }
                }
                var ssaoParams = SSAOParamsSwift(
                    texelSize: SIMD2<Float>(1.0 / Float(w), 1.0 / Float(h)),
                    radius: lighting.ssaoRadius,
                    intensity: lighting.ssaoIntensity,
                    nearPlane: nearPlane,
                    farPlane: farPlane,
                    silhouetteThickness: silhouetteConfig.enableSilhouettes ? silhouetteConfig.silhouetteThickness : 0.0,
                    silhouetteIntensity: silhouetteConfig.enableSilhouettes ? silhouetteConfig.silhouetteIntensity : 0.0,
                    exposure: lighting.exposure,
                    whitePoint: lighting.whitePoint,
                    dofAperture: controller.dofAperture,
                    dofFocalDistance: dofFocalDist,
                    dofMaxBlurRadius: controller.dofMaxBlurRadius,
                    dofEnabled: dofEnabled ? 1.0 : 0.0
                )
                ssaoEncoder.setFragmentTexture(resolvedDepth, index: 0)
                ssaoEncoder.setFragmentTexture(resolvedColor, index: 1)
                ssaoEncoder.setFragmentBytes(&ssaoParams, length: MemoryLayout<SSAOParamsSwift>.size, index: 0)
                ssaoEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                ssaoEncoder.endEncoding()
            }
        }

        // Prune cache entries for bodies no longer in the scene.
        let activeIDs = Set(bodies.map(\.id))
        for id in bodyBufferCache.keys where !activeIDs.contains(id) {
            bodyBufferCache.removeValue(forKey: id)
            bodyGeneration.removeValue(forKey: id)
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Grid Drawing

    private func drawGrid(
        encoder: MTLRenderCommandEncoder,
        viewProjection: simd_float4x4,
        cameraState: CameraState,
        config: ViewportConfiguration
    ) {
        let spacing = computeGridSpacing(cameraState: cameraState, config: config)
        let halfCount: Int32 = 15
        let pivot = cameraState.pivot
        let centerX = (pivot.x / spacing).rounded() * spacing
        let centerZ = (pivot.z / spacing).rounded() * spacing

        var gridUniforms = GridUniforms(
            viewProjectionMatrix: viewProjection,
            gridOrigin: SIMD3<Float>(centerX, -0.01, centerZ),
            spacing: spacing,
            halfCount: halfCount,
            dotSize: max(2.0, 4.0 / cameraState.distance),
            dotColor: SIMD4<Float>(0.6, 0.6, 0.6, 1.0)
        )

        let count = Int(halfCount) * 2 + 1
        let instanceCount = count * count

        encoder.setRenderPipelineState(gridPipeline)
        encoder.setVertexBytes(&gridUniforms, length: MemoryLayout<GridUniforms>.size, index: 0)
        encoder.setFragmentBytes(&gridUniforms, length: MemoryLayout<GridUniforms>.size, index: 0)
        encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: 1, instanceCount: instanceCount)
    }

    private func computeGridSpacing(cameraState: CameraState, config: ViewportConfiguration) -> Float {
        let distance = cameraState.distance
        let fovRadians = cameraState.fieldOfView * .pi / 180.0
        let visibleWidth = 2.0 * distance * tan(fovRadians / 2.0)
        let targetDivisions: Float = 15.0
        let idealSpacing = visibleWidth / targetDivisions
        let baseSpacing = config.gridBaseSpacing
        let subdivisions = Float(max(config.gridSubdivisions, 2))

        guard baseSpacing > 0, idealSpacing > 0 else {
            return baseSpacing > 0 ? baseSpacing : 1.0
        }

        let level = (log(idealSpacing / baseSpacing) / log(subdivisions)).rounded()
        return baseSpacing * pow(subdivisions, level)
    }

    // MARK: - Axis Drawing

    private func drawAxes(encoder: MTLRenderCommandEncoder, viewProjection: simd_float4x4) {
        var axisUniforms = AxisUniforms(viewProjectionMatrix: viewProjection)

        encoder.setRenderPipelineState(axisPipeline)
        encoder.setVertexBuffer(axisVertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&axisUniforms, length: MemoryLayout<AxisUniforms>.size, index: 1)
        encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: 6)
    }

    // MARK: - Shadow Map Helpers

    /// Computes an orthographic light view-projection matrix that encompasses the scene.
    private func computeLightViewProjection(lightDir: SIMD3<Float>, bodies: [ViewportBody]) -> simd_float4x4 {
        // Compute scene bounding box
        var sceneMin = SIMD3<Float>(repeating: Float.greatestFiniteMagnitude)
        var sceneMax = SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)
        var hasGeometry = false

        for body in bodies where body.isVisible {
            if let bb = body.boundingBox {
                sceneMin = simd_min(sceneMin, bb.min)
                sceneMax = simd_max(sceneMax, bb.max)
                hasGeometry = true
            }
        }

        if !hasGeometry {
            sceneMin = SIMD3<Float>(-5, -5, -5)
            sceneMax = SIMD3<Float>(5, 5, 5)
        }

        let center = (sceneMin + sceneMax) * 0.5
        let extents = sceneMax - sceneMin
        let radius = simd_length(extents) * 0.5

        // Look-at from light direction
        let dir = simd_normalize(lightDir)
        let lightPos = center - dir * (radius * 2.0)

        // Determine up vector (avoid parallel to light direction)
        let tentativeUp = SIMD3<Float>(0, 1, 0)
        let up: SIMD3<Float>
        if abs(simd_dot(dir, tentativeUp)) > 0.99 {
            up = SIMD3<Float>(0, 0, 1)
        } else {
            up = tentativeUp
        }

        let lightView = simd_float4x4.lookAt(eye: lightPos, target: center, up: up)

        // Orthographic projection that covers the scene sphere
        let orthoSize = radius * 1.5
        let lightProj = simd_float4x4.orthographic(
            left: -orthoSize, right: orthoSize,
            bottom: -orthoSize, top: orthoSize,
            near: 0.01, far: radius * 4.0
        )

        return lightProj * lightView
    }

    // MARK: - Buffer Management

    private func ensureBuffers(for body: ViewportBody) {
        let currentGen = body.generation
        if let cachedGen = bodyGeneration[body.id], cachedGen == currentGen {
            return // buffer still valid
        }

        // Build vertex + index buffers (nil for edge-only bodies)
        var vertexBuffer: MTLBuffer?
        var indexBuffer: MTLBuffer?
        var indexCount = 0
        var vertexCount = 0

        if !body.vertexData.isEmpty, !body.indices.isEmpty {
            vertexBuffer = device.makeBuffer(
                bytes: body.vertexData,
                length: body.vertexData.count * MemoryLayout<Float>.size,
                options: .storageModeShared
            )
            indexBuffer = device.makeBuffer(
                bytes: body.indices,
                length: body.indices.count * MemoryLayout<UInt32>.size,
                options: .storageModeShared
            )
            indexCount = body.indices.count
            vertexCount = body.vertexData.count / 6
        }

        // Build edge vertex buffer (convert polylines to line segment pairs)
        var edgeVertices: [Float] = []
        for polyline in body.edges {
            guard polyline.count >= 2 else { continue }
            for i in 0..<(polyline.count - 1) {
                let a = polyline[i]
                let b = polyline[i + 1]
                // Each vertex needs position + normal (stride 6), normal is unused for wireframe
                edgeVertices.append(contentsOf: [a.x, a.y, a.z, 0, 0, 0])
                edgeVertices.append(contentsOf: [b.x, b.y, b.z, 0, 0, 0])
            }
        }

        let edgeVB: MTLBuffer?
        if !edgeVertices.isEmpty {
            edgeVB = device.makeBuffer(
                bytes: edgeVertices,
                length: edgeVertices.count * MemoryLayout<Float>.size,
                options: .storageModeShared
            )
        } else {
            edgeVB = nil
        }

        let edgeVertexCount = edgeVertices.count / 6

        // Skip bodies with no renderable data at all
        guard vertexBuffer != nil || edgeVB != nil else { return }

        // Build tessellation patch data if tessellation is enabled
        var tessBuffers: TessellationBuffers?
        if tessellationEnabled,
           let tessMgr = tessellationManager,
           let vb = vertexBuffer, let ib = indexBuffer,
           indexCount > 0 {
            let triangleCount = indexCount / 3
            tessBuffers = tessMgr.buildPatches(
                vertexBuffer: vb,
                indexBuffer: ib,
                faceIndices: body.faceIndices,
                triangleCount: triangleCount,
                commandQueue: commandQueue
            )
            // One-shot diagnostic for first body
            if !tessMgr.didLogDiagnostic {
                tessMgr.didLogDiagnostic = true
                let msg = "ensureBuffers: body=\(body.id) tris=\(triangleCount) faceIdx=\(body.faceIndices.count) tessResult=\(tessBuffers != nil) tessEnabled=\(tessellationEnabled) vb=\(vb.length) ib=\(ib.length)"
                NSLog("[ViewportRenderer] %@", msg)
                if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    let existing = (try? String(contentsOf: docs.appendingPathComponent("renderer_diag.txt"), encoding: .utf8)) ?? ""
                    try? (existing + "\n" + msg).write(to: docs.appendingPathComponent("renderer_diag.txt"), atomically: true, encoding: .utf8)
                }
            }
        }

        // Build meshlets if mesh shaders are enabled
        var meshletBufs: MeshletBuffers?
        if meshShadersEnabled, !body.vertexData.isEmpty, !body.indices.isEmpty {
            meshletBufs = MeshletBuilder.build(
                vertexData: body.vertexData,
                indices: body.indices,
                faceIndices: body.faceIndices,
                device: device
            )
        }

        bodyBufferCache[body.id] = BodyBuffers(
            vertexBuffer: vertexBuffer,
            indexBuffer: indexBuffer,
            indexCount: indexCount,
            edgeVertexBuffer: edgeVB,
            edgeVertexCount: edgeVertexCount,
            vertexCount: vertexCount,
            tessellation: tessBuffers,
            meshlets: meshletBufs
        )
        bodyGeneration[body.id] = currentGen
    }

    // MARK: - Picking

    /// Reads a single pixel from the pick ID buffer and decodes the result.
    ///
    /// - Parameters:
    ///   - pixel: The pixel coordinate (in drawable pixels) to sample.
    ///   - completion: Called with the decoded `PickResult`, or `nil` for background/no hit.
    public func performPick(at pixel: SIMD2<Int>, completion: @escaping @Sendable (PickResult?) -> Void) {
        guard let pickTexture = pickTextureManager.texture else {
            completion(nil)
            return
        }

        // Clamp to texture bounds
        let x = max(0, min(pixel.x, pickTextureManager.width - 1))
        let y = max(0, min(pixel.y, pickTextureManager.height - 1))

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
            completion(nil)
            return
        }

        // Blit 1x1 region from private pick texture to shared readback buffer
        blitEncoder.copy(
            from: pickTexture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: x, y: y, z: 0),
            sourceSize: MTLSize(width: 1, height: 1, depth: 1),
            to: pickReadbackBuffer,
            destinationOffset: 0,
            destinationBytesPerRow: MemoryLayout<UInt32>.size,
            destinationBytesPerImage: MemoryLayout<UInt32>.size
        )
        blitEncoder.endEncoding()

        let indexMap = currentIndexMap
        let readbackBuffer = pickReadbackBuffer

        commandBuffer.addCompletedHandler { _ in
            let rawValue = readbackBuffer.contents().load(as: UInt32.self)
            let result = PickResult(rawValue: rawValue, indexMap: indexMap)
            Task { @MainActor in
                completion(result)
            }
        }

        commandBuffer.commit()
    }
}
