// ViewportRenderer.swift
// ViewportKit
//
// MTKViewDelegate that drives Metal rendering for the viewport.

import MetalKit
import simd
import SwiftUI

// MARK: - Uniform Types (Swift-side, must match Shaders.metal)

struct Uniforms {
    var viewProjectionMatrix: simd_float4x4
    var modelMatrix: simd_float4x4
    var lightDirection: SIMD3<Float>
    var lightIntensity: Float
    var ambientIntensity: Float
    var cameraPosition: SIMD3<Float>
}

struct BodyUniforms {
    var color: SIMD4<Float>
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

// MARK: - Cached Body Buffers

private struct BodyBuffers {
    let vertexBuffer: MTLBuffer
    let indexBuffer: MTLBuffer
    let indexCount: Int
    let edgeVertexBuffer: MTLBuffer?
    let edgeVertexCount: Int
    let vertexCount: Int
}

// MARK: - ViewportRenderer

@MainActor
public final class ViewportRenderer: NSObject, MTKViewDelegate, Sendable {

    // MARK: - Properties

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let shadedPipeline: MTLRenderPipelineState
    private let wireframePipeline: MTLRenderPipelineState
    private let gridPipeline: MTLRenderPipelineState
    private let axisPipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState

    private weak var controller: ViewportController?
    private var bodiesBinding: Binding<[ViewportBody]>

    /// Cached MTLBuffers keyed by body ID.
    private var bodyBufferCache: [String: BodyBuffers] = [:]
    /// Generation counter per body ID (vertex count as cheap change detection).
    private var bodyGeneration: [String: Int] = [:]

    /// Axis vertex buffer (6 vertices: 3 line segments with position+color).
    private let axisVertexBuffer: MTLBuffer

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

        // Shaded pipeline
        let shadedDesc = MTLRenderPipelineDescriptor()
        shadedDesc.vertexFunction = library.makeFunction(name: "shaded_vertex")
        shadedDesc.fragmentFunction = library.makeFunction(name: "shaded_fragment")
        shadedDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        shadedDesc.depthAttachmentPixelFormat = .depth32Float

        // Vertex descriptor for interleaved position + normal (stride 6 floats)
        let vertexDesc = MTLVertexDescriptor()
        // Position: attribute(0), offset 0, 3 floats
        vertexDesc.attributes[0].format = .float3
        vertexDesc.attributes[0].offset = 0
        vertexDesc.attributes[0].bufferIndex = 0
        // Normal: attribute(1), offset 12 bytes (3 * 4)
        vertexDesc.attributes[1].format = .float3
        vertexDesc.attributes[1].offset = MemoryLayout<Float>.size * 3
        vertexDesc.attributes[1].bufferIndex = 0
        // Layout: stride = 6 floats = 24 bytes
        vertexDesc.layouts[0].stride = MemoryLayout<Float>.size * 6

        shadedDesc.vertexDescriptor = vertexDesc

        guard let shadedPipeline = try? device.makeRenderPipelineState(descriptor: shadedDesc) else {
            return nil
        }
        self.shadedPipeline = shadedPipeline

        // Wireframe pipeline (same vertex descriptor — uses position, ignores normal)
        let wireDesc = MTLRenderPipelineDescriptor()
        wireDesc.vertexFunction = library.makeFunction(name: "wireframe_vertex")
        wireDesc.fragmentFunction = library.makeFunction(name: "wireframe_fragment")
        wireDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        wireDesc.depthAttachmentPixelFormat = .depth32Float
        wireDesc.vertexDescriptor = vertexDesc

        guard let wireframePipeline = try? device.makeRenderPipelineState(descriptor: wireDesc) else {
            return nil
        }
        self.wireframePipeline = wireframePipeline

        // Grid pipeline (no vertex descriptor — positions computed in shader)
        let gridDesc = MTLRenderPipelineDescriptor()
        gridDesc.vertexFunction = library.makeFunction(name: "grid_vertex")
        gridDesc.fragmentFunction = library.makeFunction(name: "grid_fragment")
        gridDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        gridDesc.depthAttachmentPixelFormat = .depth32Float

        guard let gridPipeline = try? device.makeRenderPipelineState(descriptor: gridDesc) else {
            return nil
        }
        self.gridPipeline = gridPipeline

        // Axis pipeline
        let axisDesc = MTLRenderPipelineDescriptor()
        axisDesc.vertexFunction = library.makeFunction(name: "axis_vertex")
        axisDesc.fragmentFunction = library.makeFunction(name: "axis_fragment")
        axisDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        axisDesc.depthAttachmentPixelFormat = .depth32Float

        let axisVertexDesc = MTLVertexDescriptor()
        // Position: attribute(0), 3 floats
        axisVertexDesc.attributes[0].format = .float3
        axisVertexDesc.attributes[0].offset = 0
        axisVertexDesc.attributes[0].bufferIndex = 0
        // Color: attribute(1), 4 floats
        axisVertexDesc.attributes[1].format = .float4
        axisVertexDesc.attributes[1].offset = MemoryLayout<Float>.size * 3
        axisVertexDesc.attributes[1].bufferIndex = 0
        // Stride: 7 floats (px,py,pz, r,g,b,a)
        axisVertexDesc.layouts[0].stride = MemoryLayout<Float>.size * 7

        axisDesc.vertexDescriptor = axisVertexDesc

        guard let axisPipeline = try? device.makeRenderPipelineState(descriptor: axisDesc) else {
            return nil
        }
        self.axisPipeline = axisPipeline

        // Depth stencil state
        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.depthCompareFunction = .less
        depthDesc.isDepthWriteEnabled = true

        guard let depthState = device.makeDepthStencilState(descriptor: depthDesc) else {
            return nil
        }
        self.depthState = depthState

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

        super.init()
    }

    // MARK: - Public

    /// The Metal device, exposed for MTKView configuration.
    public var metalDevice: MTLDevice { device }

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

    private func drawOnMainActor(in view: MTKView) {
        guard let controller = controller else { return }
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor else { return }
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }

        encoder.setDepthStencilState(depthState)

        let cameraState = controller.cameraState
        let drawableSize = view.drawableSize
        let aspectRatio = Float(drawableSize.width / drawableSize.height)

        let viewMatrix = cameraState.viewMatrix
        let projMatrix = cameraState.projectionMatrix(aspectRatio: aspectRatio, near: 0.01, far: 10000.0)
        let viewProjection = projMatrix * viewMatrix

        let lighting = controller.configuration.lightingConfiguration

        // 1. Draw grid
        if controller.showGrid {
            drawGrid(encoder: encoder, viewProjection: viewProjection, cameraState: cameraState, config: controller.configuration)
        }

        // 2. Draw axes
        if controller.showAxes {
            drawAxes(encoder: encoder, viewProjection: viewProjection)
        }

        // 3. Draw bodies
        let bodies = bodiesBinding.wrappedValue
        let displayMode = controller.displayMode

        for body in bodies where body.isVisible {
            ensureBuffers(for: body)

            guard let buffers = bodyBufferCache[body.id] else { continue }

            var uniforms = Uniforms(
                viewProjectionMatrix: viewProjection,
                modelMatrix: matrix_identity_float4x4,
                lightDirection: lighting.keyLight.direction,
                lightIntensity: lighting.keyLight.intensity,
                ambientIntensity: lighting.ambientIntensity,
                cameraPosition: cameraState.position
            )

            var bodyUniforms = BodyUniforms(color: body.color)

            // Shaded pass
            if displayMode.showsSurfaces {
                encoder.setRenderPipelineState(shadedPipeline)
                encoder.setVertexBuffer(buffers.vertexBuffer, offset: 0, index: 0)
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)
                encoder.setFragmentBytes(&bodyUniforms, length: MemoryLayout<BodyUniforms>.size, index: 2)
                encoder.drawIndexedPrimitives(
                    type: .triangle,
                    indexCount: buffers.indexCount,
                    indexType: .uint32,
                    indexBuffer: buffers.indexBuffer,
                    indexBufferOffset: 0
                )
            }

            // Wireframe pass
            if displayMode.showsEdges, let edgeVB = buffers.edgeVertexBuffer, buffers.edgeVertexCount > 0 {
                encoder.setRenderPipelineState(wireframePipeline)
                encoder.setVertexBuffer(edgeVB, offset: 0, index: 0)
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)
                encoder.setFragmentBytes(&bodyUniforms, length: MemoryLayout<BodyUniforms>.size, index: 2)
                encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: buffers.edgeVertexCount)
            }
        }

        encoder.endEncoding()
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

    // MARK: - Buffer Management

    private func ensureBuffers(for body: ViewportBody) {
        let currentGen = body.vertexData.count
        if let cachedGen = bodyGeneration[body.id], cachedGen == currentGen {
            return // buffer still valid
        }

        // Build vertex buffer
        guard !body.vertexData.isEmpty else { return }
        guard let vertexBuffer = device.makeBuffer(
            bytes: body.vertexData,
            length: body.vertexData.count * MemoryLayout<Float>.size,
            options: .storageModeShared
        ) else { return }

        // Build index buffer
        guard !body.indices.isEmpty else { return }
        guard let indexBuffer = device.makeBuffer(
            bytes: body.indices,
            length: body.indices.count * MemoryLayout<UInt32>.size,
            options: .storageModeShared
        ) else { return }

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

        bodyBufferCache[body.id] = BodyBuffers(
            vertexBuffer: vertexBuffer,
            indexBuffer: indexBuffer,
            indexCount: body.indices.count,
            edgeVertexBuffer: edgeVB,
            edgeVertexCount: edgeVertexCount,
            vertexCount: body.vertexData.count / 6
        )
        bodyGeneration[body.id] = currentGen
    }
}
