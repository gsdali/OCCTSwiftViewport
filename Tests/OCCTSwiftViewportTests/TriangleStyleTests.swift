// TriangleStyleTests.swift
// OCCTSwiftViewport Tests
//
// Per-triangle highlight style — issue #25.

import Testing
import simd
@testable import OCCTSwiftViewport

@Suite("TriangleStyle Tests")
struct TriangleStyleTests {

    @Test("TriangleStyle.none has zero alpha")
    func noneIsTransparent() {
        let style = TriangleStyle.none
        #expect(style.color.w == 0.0)
    }

    @Test("Default-constructed TriangleStyle is .none")
    func defaultIsNone() {
        let style = TriangleStyle()
        #expect(style == TriangleStyle.none)
    }

    @Test("ViewportBody default triangleStyles is empty")
    func bodyDefaultIsEmpty() {
        let body = ViewportBody.box(id: "default-style")
        #expect(body.triangleStyles.isEmpty)
    }

    @Test("ViewportBody round-trips a non-empty triangleStyles array")
    func bodyAcceptsStyleArray() {
        // Pick a body whose triangle count we know from its index buffer.
        let base = ViewportBody.box(id: "styled")
        let triangleCount = base.indices.count / 3
        let styles: [TriangleStyle] = (0..<triangleCount).map { i in
            // Highlight even-indexed triangles in red, leave odd ones transparent.
            i.isMultiple(of: 2)
                ? TriangleStyle(color: SIMD4<Float>(1, 0, 0, 0.6))
                : .none
        }
        let body = ViewportBody(
            id: "styled",
            vertexData: base.vertexData,
            indices: base.indices,
            edges: base.edges,
            triangleStyles: styles,
            color: base.color
        )
        #expect(body.triangleStyles.count == triangleCount)
        #expect(body.triangleStyles[0].color.w == 0.6)
        #expect(body.triangleStyles[1] == .none)
    }
}
