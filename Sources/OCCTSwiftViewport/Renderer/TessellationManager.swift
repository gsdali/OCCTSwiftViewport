// TessellationManager.swift
// OCCTSwiftViewport
//
// Manages GPU hardware tessellation: PN triangle patch preprocessing,
// per-frame adaptive tessellation factor computation, and pipeline states.

import simd
@preconcurrency import Metal

/// Per-body tessellation buffers cached alongside BodyBuffers.
struct TessellationBuffers {
    let patchDataBuffer: MTLBuffer       // PNPatchData per patch
    let tessFactorBuffer: MTLBuffer      // MTLTriangleTessellationFactorsHalf per patch
    let patchCount: Int
}

/// Manages PN triangle tessellation compute pipelines and per-body patch data.
@MainActor
final class TessellationManager {

    private let device: MTLDevice
    private let pnPatchPipeline: MTLComputePipelineState
    private let tessFactorPipeline: MTLComputePipelineState

    /// One-shot diagnostic flag
    var didLogDiagnostic = false

    init?(device: MTLDevice, library: MTLLibrary) {
        self.device = device

        guard let pnFunc = library.makeFunction(name: "compute_pn_patches"),
              let tfFunc = library.makeFunction(name: "compute_tess_factors"),
              let pnPipeline = try? device.makeComputePipelineState(function: pnFunc),
              let tfPipeline = try? device.makeComputePipelineState(function: tfFunc) else {
            return nil
        }

        self.pnPatchPipeline = pnPipeline
        self.tessFactorPipeline = tfPipeline
    }

    /// Builds PN triangle patch data from a triangle mesh. One-time per geometry change.
    ///
    /// - Parameters:
    ///   - vertexBuffer: Interleaved vertex buffer (stride 6 floats)
    ///   - indexBuffer: Triangle index buffer (UInt32)
    ///   - faceIndices: Per-triangle face index array
    ///   - triangleCount: Number of triangles
    ///   - commandQueue: Command queue for synchronous dispatch
    /// - Returns: TessellationBuffers with patch data and pre-allocated factor buffer
    func buildPatches(
        vertexBuffer: MTLBuffer,
        indexBuffer: MTLBuffer,
        faceIndices: [Int32],
        triangleCount: Int,
        commandQueue: MTLCommandQueue
    ) -> TessellationBuffers? {
        guard triangleCount > 0, faceIndices.count >= triangleCount else { return nil }

        // PNPatchData struct size with packed_float3: 13 * 12 + 4 + 4 = 164 bytes
        let patchStride = 164
        let patchBufferSize = triangleCount * patchStride

        guard let patchBuffer = device.makeBuffer(length: patchBufferSize, options: .storageModeShared) else {
            return nil
        }

        // Face indices buffer
        guard let faceIdxBuffer = device.makeBuffer(
            bytes: faceIndices,
            length: faceIndices.count * MemoryLayout<Int32>.size,
            options: .storageModeShared
        ) else { return nil }

        // Tessellation factor buffer (pre-allocated, updated per-frame)
        let factorStride = 8 // MTLTriangleTessellationFactorsHalf: 3 half edges + 1 half inside = 8 bytes
        guard let factorBuffer = device.makeBuffer(
            length: triangleCount * factorStride,
            options: .storageModeShared
        ) else { return nil }

        // Dispatch compute to build patches
        guard let cmdBuffer = commandQueue.makeCommandBuffer(),
              let encoder = cmdBuffer.makeComputeCommandEncoder() else { return nil }

        encoder.setComputePipelineState(pnPatchPipeline)
        encoder.setBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setBuffer(indexBuffer, offset: 0, index: 1)
        encoder.setBuffer(patchBuffer, offset: 0, index: 2)
        encoder.setBuffer(faceIdxBuffer, offset: 0, index: 3)

        var triCount = UInt32(triangleCount)
        encoder.setBytes(&triCount, length: MemoryLayout<UInt32>.size, index: 4)

        let threadsPerGroup = min(pnPatchPipeline.maxTotalThreadsPerThreadgroup, 256)
        let threadgroups = (triangleCount + threadsPerGroup - 1) / threadsPerGroup
        encoder.dispatchThreadgroups(
            MTLSize(width: threadgroups, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: threadsPerGroup, height: 1, depth: 1)
        )
        encoder.endEncoding()
        cmdBuffer.commit()
        cmdBuffer.waitUntilCompleted()

        return TessellationBuffers(
            patchDataBuffer: patchBuffer,
            tessFactorBuffer: factorBuffer,
            patchCount: triangleCount
        )
    }

    /// Updates tessellation factors for all visible bodies. Called per-frame.
    ///
    /// - Parameters:
    ///   - tessBuffers: Array of (tessellation buffers, model matrix) for visible bodies
    ///   - viewProjectionMatrix: Current camera VP matrix
    ///   - viewportSize: Viewport dimensions in pixels
    ///   - targetEdgePixels: Target pixels per tessellated edge
    ///   - maxFactor: Maximum tessellation factor
    ///   - encoder: Compute command encoder (caller manages begin/end)
    func updateTessFactors(
        tessBuffers: [(TessellationBuffers, simd_float4x4)],
        viewProjectionMatrix: simd_float4x4,
        viewportSize: SIMD2<Float>,
        targetEdgePixels: Float,
        maxFactor: Float,
        encoder: MTLComputeCommandEncoder
    ) {
        encoder.setComputePipelineState(tessFactorPipeline)

        let shouldLog = !didLogDiagnostic
        if shouldLog { didLogDiagnostic = true }

        for (tess, modelMatrix) in tessBuffers {
            // Combined MVP for this body (modelMatrix is identity for now)
            let mvp = viewProjectionMatrix * modelMatrix

            var params = TessFactorParamsSwift(
                viewProjectionMatrix: mvp,
                viewportSize: viewportSize,
                targetEdgePixels: targetEdgePixels,
                maxFactor: maxFactor
            )

            encoder.setBuffer(tess.patchDataBuffer, offset: 0, index: 0)
            encoder.setBuffer(tess.tessFactorBuffer, offset: 0, index: 1)
            encoder.setBytes(&params, length: MemoryLayout<TessFactorParamsSwift>.size, index: 2)

            var patchCount = UInt32(tess.patchCount)
            encoder.setBytes(&patchCount, length: MemoryLayout<UInt32>.size, index: 3)

            let threadsPerGroup = min(tessFactorPipeline.maxTotalThreadsPerThreadgroup, 256)
            let threadgroups = (tess.patchCount + threadsPerGroup - 1) / threadsPerGroup
            encoder.dispatchThreadgroups(
                MTLSize(width: threadgroups, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: threadsPerGroup, height: 1, depth: 1)
            )
        }
    }
}

// Swift-side mirror of TessFactorParams (must match shader struct layout)
struct TessFactorParamsSwift {
    var viewProjectionMatrix: simd_float4x4
    var viewportSize: SIMD2<Float>
    var targetEdgePixels: Float
    var maxFactor: Float
}
