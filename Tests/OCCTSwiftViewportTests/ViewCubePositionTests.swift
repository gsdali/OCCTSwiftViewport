import Testing
import SwiftUI
@testable import OCCTSwiftViewport

@Suite("ViewCube position")
struct ViewCubePositionTests {

    @Test("Each position maps to the matching SwiftUI alignment (#62)")
    func positionToAlignment() {
        #expect(ViewCubePosition.topLeading.overlayAlignment == .topLeading)
        #expect(ViewCubePosition.topTrailing.overlayAlignment == .topTrailing)
        #expect(ViewCubePosition.bottomLeading.overlayAlignment == .bottomLeading)
        #expect(ViewCubePosition.bottomTrailing.overlayAlignment == .bottomTrailing)
    }

    @Test("Default configuration keeps the cube bottom-trailing (no behaviour change)")
    func defaultPositionUnchanged() {
        #expect(ViewportConfiguration().viewCubePosition == .bottomTrailing)
        #expect(ViewportConfiguration.cad.viewCubePosition == .bottomTrailing)
    }
}
