// AnyViewportView.swift
// ViewportKit
//
// Unified viewport view that switches between RealityKit and Metal backends
// based on the controller's configuration.

import SwiftUI
import RealityKit

/// A viewport view that automatically uses the renderer specified
/// by `ViewportConfiguration.rendererBackend`.
///
/// Supply RealityKit entities, Metal bodies, or both — only the inputs
/// matching the active backend are used.
///
/// ## Example — RealityKit (default)
///
/// ```swift
/// let controller = ViewportController()  // defaults to .realityKit
/// AnyViewportView(controller: controller, entities: [myEntity])
/// ```
///
/// ## Example — Metal
///
/// ```swift
/// let config = ViewportConfiguration(rendererBackend: .metal)
/// let controller = ViewportController(configuration: config)
/// AnyViewportView(controller: controller, bodies: $myBodies)
/// ```
public struct AnyViewportView: View {

    @ObservedObject private var controller: ViewportController

    private let entities: [Entity]
    @Binding private var bodies: [ViewportBody]

    /// Creates a viewport view that switches backend based on configuration.
    ///
    /// - Parameters:
    ///   - controller: The viewport controller (its `configuration.rendererBackend` selects the renderer)
    ///   - entities: RealityKit entities (used when backend is `.realityKit`)
    ///   - bodies: Metal geometry bodies (used when backend is `.metal`)
    public init(
        controller: ViewportController,
        entities: [Entity] = [],
        bodies: Binding<[ViewportBody]> = .constant([])
    ) {
        self.controller = controller
        self.entities = entities
        self._bodies = bodies
    }

    public var body: some View {
        switch controller.configuration.rendererBackend {
        case .realityKit:
            ViewportView(controller: controller, entities: entities)
        case .metal:
            MetalViewportView(controller: controller, bodies: $bodies)
        }
    }
}
