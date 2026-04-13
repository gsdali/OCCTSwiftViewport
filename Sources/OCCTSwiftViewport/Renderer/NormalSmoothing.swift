// NormalSmoothing.swift
// OCCTSwiftViewport
//
// CPU-side crease-aware vertex normal averaging.
// Smooths normals across shared vertices while preserving hard edges.

import simd

/// Crease-aware vertex normal smoothing for tessellated CAD geometry.
///
/// Averages vertex normals across adjacent triangles that share vertex positions,
/// preserving hard creases where face normals differ by more than the crease angle.
/// This eliminates visible faceting on curved surfaces while keeping sharp edges crisp.
public enum NormalSmoothing {

    /// Smooths vertex normals in-place within an interleaved vertex buffer.
    ///
    /// - Parameters:
    ///   - vertexData: Interleaved `[px, py, pz, nx, ny, nz, ...]` with stride 6.
    ///     Normals are modified in-place.
    ///   - indices: Triangle index buffer (3 indices per triangle).
    ///   - creaseAngle: Maximum angle (radians) between face normals before
    ///     treating the edge as a hard crease. Default 0.524 (~30°).
    public static func smoothNormals(
        vertexData: inout [Float],
        indices: [UInt32],
        creaseAngle: Float = 0.524
    ) {
        let vertexCount = vertexData.count / 6
        let triangleCount = indices.count / 3
        guard vertexCount > 0, triangleCount > 0 else { return }

        let cosCrease = cos(creaseAngle)

        // --- Step 1: Compute face normals (area-weighted) ---
        var faceNormals = [SIMD3<Float>](repeating: .zero, count: triangleCount)
        for t in 0..<triangleCount {
            let i0 = Int(indices[t * 3])
            let i1 = Int(indices[t * 3 + 1])
            let i2 = Int(indices[t * 3 + 2])
            let p0 = position(vertexData, i0)
            let p1 = position(vertexData, i1)
            let p2 = position(vertexData, i2)
            let cross = simd_cross(p1 - p0, p2 - p0)
            let len = simd_length(cross)
            faceNormals[t] = len > 1e-12 ? cross / len : .zero
        }

        // --- Step 2: Build spatial hash of vertex positions ---
        // Maps quantized position → list of (vertexIndex, triangleIndex) pairs
        var positionMap: [SIMD3<Int32>: [(vertexIdx: Int, triIdx: Int)]] = [:]
        positionMap.reserveCapacity(vertexCount)

        for t in 0..<triangleCount {
            for c in 0..<3 {
                let vIdx = Int(indices[t * 3 + c])
                let key = quantize(position(vertexData, vIdx))
                positionMap[key, default: []].append((vertexIdx: vIdx, triIdx: t))
            }
        }

        // --- Step 3: Average normals within crease groups ---
        // Track which vertices have been processed to avoid redundant work
        var processed = [Bool](repeating: false, count: vertexCount)

        for (_, entries) in positionMap {
            // Deduplicate vertex indices at this position
            var uniqueVertices: [Int] = []
            var seen = Set<Int>()
            for entry in entries {
                if seen.insert(entry.vertexIdx).inserted {
                    uniqueVertices.append(entry.vertexIdx)
                }
            }

            // Collect all triangle indices touching this position
            var triSet = Set<Int>()
            for entry in entries {
                triSet.insert(entry.triIdx)
            }
            let adjacentTris = Array(triSet)

            if adjacentTris.count <= 1 {
                // Only one triangle — nothing to average
                for vIdx in uniqueVertices { processed[vIdx] = true }
                continue
            }

            // Group triangles by crease connectivity
            let groups = groupByCrease(
                triangles: adjacentTris,
                faceNormals: faceNormals,
                cosThreshold: cosCrease
            )

            // For each group, compute averaged normal and assign to member vertices
            for group in groups {
                // Area-weighted average of face normals in this group
                var sum = SIMD3<Float>.zero
                for triIdx in group {
                    sum += faceNormals[triIdx]
                }
                let averaged = simd_length(sum) > 1e-12 ? simd_normalize(sum) : faceNormals[group[0]]

                // Assign to all vertices at this position that belong to triangles in this group
                let groupSet = Set(group)
                for entry in entries where groupSet.contains(entry.triIdx) {
                    let vIdx = entry.vertexIdx
                    if !processed[vIdx] {
                        setNormal(&vertexData, vIdx, averaged)
                        processed[vIdx] = true
                    }
                }
            }
        }

        // Any unprocessed vertices keep their original normals
    }

    // MARK: - Private Helpers

    /// Extracts position from interleaved vertex data.
    private static func position(_ data: [Float], _ idx: Int) -> SIMD3<Float> {
        let base = idx * 6
        return SIMD3<Float>(data[base], data[base + 1], data[base + 2])
    }

    /// Writes a normal into interleaved vertex data.
    private static func setNormal(_ data: inout [Float], _ idx: Int, _ n: SIMD3<Float>) {
        let base = idx * 6 + 3
        data[base] = n.x
        data[base + 1] = n.y
        data[base + 2] = n.z
    }

    /// Quantizes a position to a grid for spatial hashing (tolerance ~1e-5).
    private static func quantize(_ p: SIMD3<Float>) -> SIMD3<Int32> {
        let scale: Float = 1e5
        return SIMD3<Int32>(
            Int32(round(p.x * scale)),
            Int32(round(p.y * scale)),
            Int32(round(p.z * scale))
        )
    }

    /// Groups triangle indices by crease-angle connectivity.
    ///
    /// Two triangles are in the same group if their face normals' dot product
    /// exceeds the cosine threshold (i.e., angle between normals < crease angle).
    /// Uses flood-fill: triangles within crease angle of any group member are added.
    private static func groupByCrease(
        triangles: [Int],
        faceNormals: [SIMD3<Float>],
        cosThreshold: Float
    ) -> [[Int]] {
        var assigned = [Bool](repeating: false, count: triangles.count)
        var groups: [[Int]] = []

        for i in 0..<triangles.count {
            guard !assigned[i] else { continue }

            // Flood-fill from this triangle
            var group = [triangles[i]]
            assigned[i] = true
            var queue = [i]

            while !queue.isEmpty {
                let current = queue.removeFirst()
                let currentNormal = faceNormals[triangles[current]]

                for j in 0..<triangles.count {
                    guard !assigned[j] else { continue }
                    let candidateNormal = faceNormals[triangles[j]]
                    let dot = simd_dot(currentNormal, candidateNormal)
                    if dot >= cosThreshold {
                        assigned[j] = true
                        group.append(triangles[j])
                        queue.append(j)
                    }
                }
            }

            groups.append(group)
        }

        return groups
    }
}
