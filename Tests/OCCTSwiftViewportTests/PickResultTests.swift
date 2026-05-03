import Testing
@testable import OCCTSwiftViewport

@Suite("PickResult Tests")
struct PickResultTests {

    private static let map: [Int: String] = [0: "a", 5: "b", 0xFFFF: "max"]

    @Test("Sentinel decodes to nil")
    func sentinelDecodesToNil() {
        #expect(PickResult(rawValue: PickResult.sentinel, indexMap: Self.map) == nil)
    }

    @Test("Face decode: kind=0, primitiveID in bits 16-29, objectIndex in bits 0-15")
    func faceDecode() {
        // kind=0 (face), primitiveID=42, objectIndex=5 → 0x002A_0005
        let raw: UInt32 = (0 << 30) | ((42 & 0x3FFF) << 16) | 5
        let r = PickResult(rawValue: raw, indexMap: Self.map)
        #expect(r != nil)
        #expect(r?.bodyID == "b")
        #expect(r?.bodyIndex == 5)
        #expect(r?.triangleIndex == 42)
        #expect(r?.kind == .face)
    }

    @Test("Edge decode: kind=1")
    func edgeDecode() {
        let raw: UInt32 = (1 << 30) | ((7 & 0x3FFF) << 16) | 0
        let r = PickResult(rawValue: raw, indexMap: Self.map)
        #expect(r?.kind == .edge)
        #expect(r?.triangleIndex == 7)
        #expect(r?.bodyID == "a")
    }

    @Test("Vertex decode: kind=2")
    func vertexDecode() {
        let raw: UInt32 = (2 << 30) | ((3 & 0x3FFF) << 16) | 5
        let r = PickResult(rawValue: raw, indexMap: Self.map)
        #expect(r?.kind == .vertex)
        #expect(r?.triangleIndex == 3)
        #expect(r?.bodyID == "b")
    }

    @Test("primitiveID truncates at 14 bits")
    func primitiveIDTruncates() {
        // 0x4001 has bit 14 set, which collides with kind bits.
        // Decoder must mask to 14 bits and treat the high 2 bits as kind only.
        // So primitiveID = 0x0001, kind = (0x4001 >> 14) & 0x3 = 1 (edge).
        let raw: UInt32 = (0x4001 << 16) | 5
        let r = PickResult(rawValue: raw, indexMap: Self.map)
        #expect(r?.triangleIndex == 1)
        #expect(r?.kind == .edge)
    }

    @Test("Layer map routes to widget when bodyID matches")
    func layerMapWidget() {
        let raw: UInt32 = (1 << 30) | (4 << 16) | 5
        let layerMap: [String: PickLayer] = ["b": .widget]
        let r = PickResult(rawValue: raw, indexMap: Self.map, layerMap: layerMap)
        #expect(r?.pickLayer == .widget)
    }

    @Test("Layer map default is .userGeometry")
    func layerMapDefault() {
        let raw: UInt32 = (0 << 30) | (4 << 16) | 5
        let r = PickResult(rawValue: raw, indexMap: Self.map)
        #expect(r?.pickLayer == .userGeometry)
    }

    @Test("Unknown objectIndex returns nil")
    func unknownObjectIndex() {
        let raw: UInt32 = (0 << 30) | (4 << 16) | 99
        #expect(PickResult(rawValue: raw, indexMap: Self.map) == nil)
    }
}
