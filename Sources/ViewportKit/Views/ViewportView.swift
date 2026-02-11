// ViewportView.swift
// ViewportKit
//
// Main SwiftUI view for 3D viewport using RealityKit.

import SwiftUI
import RealityKit
import simd

/// A 3D viewport view using RealityKit.
///
/// ViewportView provides a complete 3D viewing experience with:
/// - Orbit, pan, and zoom gestures
/// - ViewCube for orientation and quick navigation
/// - Configurable display modes and lighting
///
/// ## Example
///
/// ```swift
/// struct ContentView: View {
///     @StateObject private var controller = ViewportController()
///
///     var body: some View {
///         ViewportView(controller: controller, entities: [
///             makeBox()
///         ])
///     }
///
///     func makeBox() -> Entity {
///         ModelEntity(
///             mesh: .generateBox(size: 1),
///             materials: [SimpleMaterial(color: .gray, isMetallic: true)]
///         )
///     }
/// }
/// ```
public struct ViewportView: View {

    // MARK: - Properties

    @ObservedObject private var controller: ViewportController

    /// Entities to display in the viewport.
    private let entities: [Entity]

    // MARK: - Gesture State

    @State private var lastDragValue: CGSize = .zero
    @State private var lastMagnification: CGFloat = 1.0
    @State private var isOrbiting: Bool = false
    @State private var isPanning: Bool = false

    // MARK: - Grid State

    @State private var lastGridSpacing: Float = 0

    // MARK: - Entity Names

    private static let userContainerName = "_ViewportKit_UserEntities"
    private static let gridContainerName = "_ViewportKit_Grid"
    private static let xAxisName = "_ViewportKit_XAxis"
    private static let yAxisName = "_ViewportKit_YAxis"
    private static let zAxisName = "_ViewportKit_ZAxis"

    // MARK: - Initialization

    /// Creates a viewport view with the specified controller and entities.
    ///
    /// - Parameters:
    ///   - controller: The viewport controller managing state
    ///   - entities: Entities to display in the scene
    public init(
        controller: ViewportController,
        entities: [Entity] = []
    ) {
        self.controller = controller
        self.entities = entities
    }

    // MARK: - Body

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                realityView

                // ViewCube overlay
                if controller.showViewCube {
                    viewCubeOverlay
                }
            }
        }
    }

    // MARK: - RealityView

    private var realityView: some View {
        RealityView { content in
            // Set to virtual camera mode (non-AR)
            content.camera = .virtual

            // Create and configure camera entity
            let cameraEntity = PerspectiveCamera()
            cameraEntity.camera.fieldOfViewInDegrees = controller.cameraState.fieldOfView
            content.add(cameraEntity)
            controller.cameraEntity = cameraEntity

            // Set up lighting
            setupLighting(content: content)

            // Always create grid container (toggle visibility via isEnabled)
            let gridContainer = Entity()
            gridContainer.name = Self.gridContainerName
            gridContainer.isEnabled = controller.showGrid
            addGridContent(to: gridContainer)
            content.add(gridContainer)

            // Always create coordinate axes (toggle visibility via isEnabled)
            addCoordinateAxes(content: content, enabled: controller.showAxes)

            // Create a container for user-provided entities so we can
            // efficiently replace them in the update closure.
            let container = Entity()
            container.name = Self.userContainerName
            content.add(container)

            // Add initial user entities
            for entity in entities {
                container.addChild(entity)
            }

        } update: { content in
            // Update camera transform from controller state
            if let camera = controller.cameraEntity {
                camera.transform = controller.cameraState.transform
            }

            // Update axis visibility and screen-space scaling
            updateAxes(in: content)

            // Update grid visibility and adaptive dot spacing
            updateGrid(in: content)

            // Sync user entities: replace container children with current set.
            if let container = content.entities.first(where: { $0.name == Self.userContainerName }) {
                let currentChildren = Set(container.children.map(ObjectIdentifier.init))
                let desiredChildren = Set(entities.map(ObjectIdentifier.init))

                // Remove entities no longer in the desired set
                for child in container.children where !desiredChildren.contains(ObjectIdentifier(child)) {
                    child.removeFromParent()
                }

                // Add entities not yet in the container
                for entity in entities where !currentChildren.contains(ObjectIdentifier(entity)) {
                    container.addChild(entity)
                }
            }
        }
        #if os(iOS)
        .overlay { panGestureOverlay }
        .gesture(orbitGesture)
        .gesture(zoomGesture)
        .gesture(doubleTapGesture)
        #else
        .gesture(macGestures)
        .gesture(macMagnifyGesture)
        #endif
    }

    // MARK: - iOS Gestures

    #if os(iOS)
    private var panGestureOverlay: some View {
        TwoFingerPanGestureView(
            onChanged: { translation in
                isPanning = true
                controller.handlePan(translation: translation)
            },
            onEnded: { velocity in
                controller.endPan(velocity: velocity)
            }
        )
    }

    private var orbitGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard !isPanning else { return }

                let delta = CGSize(
                    width: value.translation.width - lastDragValue.width,
                    height: value.translation.height - lastDragValue.height
                )
                lastDragValue = value.translation

                controller.handleOrbit(translation: delta)
            }
            .onEnded { value in
                lastDragValue = .zero
                if !isPanning {
                    controller.endOrbit(velocity: value.velocity)
                }
                isPanning = false
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let delta = value.magnification / lastMagnification
                lastMagnification = value.magnification
                controller.handleZoom(magnification: delta)
            }
            .onEnded { _ in
                lastMagnification = 1.0
            }
    }

    private var doubleTapGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                controller.reset(animated: true)
            }
    }
    #endif

    // MARK: - macOS Gestures

    #if os(macOS)
    private var macGestures: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let delta = CGSize(
                    width: value.translation.width - lastDragValue.width,
                    height: value.translation.height - lastDragValue.height
                )
                lastDragValue = value.translation

                // Check modifier keys
                let modifiers = NSEvent.modifierFlags

                if modifiers.contains(.shift) {
                    controller.handlePan(translation: delta)
                } else if modifiers.contains(.option) {
                    let zoomDelta = 1.0 + delta.height * 0.01
                    controller.handleZoom(magnification: zoomDelta)
                } else {
                    controller.handleOrbit(translation: delta)
                }
            }
            .onEnded { value in
                lastDragValue = .zero
                controller.endOrbit(velocity: value.velocity)
            }
    }

    private var macMagnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let delta = value.magnification / lastMagnification
                lastMagnification = value.magnification
                controller.handleZoom(magnification: delta)
            }
            .onEnded { _ in
                lastMagnification = 1.0
            }
    }
    #endif

    // MARK: - ViewCube Overlay

    private var viewCubeOverlay: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                ViewCubeView(controller: controller)
                    .frame(width: 80, height: 80)
                    .padding(12)
            }
        }
    }

    // MARK: - Scene Setup

    @MainActor
    private func setupLighting(content: RealityViewCameraContent) {
        let lighting = controller.configuration.lightingConfiguration

        // Key light
        if lighting.keyLight.isEnabled {
            let keyLight = DirectionalLight()
            keyLight.light.intensity = lighting.keyLight.intensity * 1000
            keyLight.light.color = platformColor(from: lighting.keyLight.color)
            keyLight.look(
                at: .zero,
                from: -lighting.keyLight.direction * 10,
                relativeTo: nil
            )
            if lighting.shadowsEnabled {
                keyLight.shadow = DirectionalLightComponent.Shadow()
            }
            content.add(keyLight)
        }

        // Fill light
        if lighting.fillLight.isEnabled {
            let fillLight = DirectionalLight()
            fillLight.light.intensity = lighting.fillLight.intensity * 1000
            fillLight.light.color = platformColor(from: lighting.fillLight.color)
            fillLight.look(
                at: .zero,
                from: -lighting.fillLight.direction * 10,
                relativeTo: nil
            )
            content.add(fillLight)
        }

        // Back light
        if lighting.backLight.isEnabled {
            let backLight = DirectionalLight()
            backLight.light.intensity = lighting.backLight.intensity * 1000
            backLight.light.color = platformColor(from: lighting.backLight.color)
            backLight.look(
                at: .zero,
                from: -lighting.backLight.direction * 10,
                relativeTo: nil
            )
            content.add(backLight)
        }
    }

    private func platformColor(from simd: SIMD3<Float>) -> PlatformColor {
        #if os(iOS)
        return UIColor(red: CGFloat(simd.x), green: CGFloat(simd.y), blue: CGFloat(simd.z), alpha: 1)
        #else
        return NSColor(red: CGFloat(simd.x), green: CGFloat(simd.y), blue: CGFloat(simd.z), alpha: 1)
        #endif
    }

    // MARK: - Grid

    @MainActor
    private func addGridContent(to container: Entity) {
        let config = controller.configuration

        switch config.gridStyle {
        case .plane:
            let ground = ModelEntity(
                mesh: .generatePlane(width: config.gridSize, depth: config.gridSize),
                materials: [SimpleMaterial(color: .init(white: 0.9, alpha: 1), isMetallic: false)]
            )
            ground.position = SIMD3<Float>(0, 0, -0.01)
            container.addChild(ground)

        case .dots:
            let spacing = computeGridSpacing()
            lastGridSpacing = spacing
            let pivot = controller.cameraState.pivot
            let centerX = (pivot.x / spacing).rounded() * spacing
            let centerZ = (pivot.z / spacing).rounded() * spacing
            container.position = SIMD3<Float>(centerX, -0.01, centerZ)
            generateDots(in: container, spacing: spacing)
        }
    }

    @MainActor
    private func generateDots(in container: Entity, spacing: Float) {
        let dotSize = spacing * 0.03
        let dotMaterial = SimpleMaterial(color: .init(white: 0.7, alpha: 1), isMetallic: false)
        let dotMesh: MeshResource = .generatePlane(width: dotSize, depth: dotSize)
        let halfCount = 15

        for ix in -halfCount...halfCount {
            for iy in -halfCount...halfCount {
                let dot = ModelEntity(mesh: dotMesh, materials: [dotMaterial])
                dot.position = SIMD3<Float>(
                    Float(ix) * spacing,
                    0,
                    Float(iy) * spacing
                )
                container.addChild(dot)
            }
        }
    }

    @MainActor
    private func updateGrid(in content: RealityViewCameraContent) {
        guard let gridContainer = content.entities.first(where: { $0.name == Self.gridContainerName }) else { return }
        gridContainer.isEnabled = controller.showGrid

        let config = controller.configuration
        guard config.gridStyle == .dots, controller.showGrid else { return }

        let spacing = computeGridSpacing()

        // Always update container position to follow camera pivot
        let pivot = controller.cameraState.pivot
        let centerX = (pivot.x / spacing).rounded() * spacing
        let centerZ = (pivot.z / spacing).rounded() * spacing
        gridContainer.position = SIMD3<Float>(centerX, -0.01, centerZ)

        // Only regenerate dots when spacing level changes
        guard spacing != lastGridSpacing else { return }
        lastGridSpacing = spacing

        // Clear existing dots
        for child in gridContainer.children {
            child.removeFromParent()
        }

        generateDots(in: gridContainer, spacing: spacing)
    }

    private func computeGridSpacing() -> Float {
        let config = controller.configuration
        let distance = controller.cameraState.distance
        let fovRadians = controller.cameraState.fieldOfView * .pi / 180.0
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

    // MARK: - Coordinate Axes

    @MainActor
    private func addCoordinateAxes(content: RealityViewCameraContent, enabled: Bool) {
        let config = controller.configuration
        let axisLength = config.axisLength
        let axisRadius = config.axisRadius

        // X axis (red)
        let xAxis = ModelEntity(
            mesh: .generateCylinder(height: axisLength, radius: axisRadius),
            materials: [SimpleMaterial(color: .red, isMetallic: false)]
        )
        xAxis.name = Self.xAxisName
        xAxis.position = SIMD3<Float>(axisLength / 2, 0, 0)
        xAxis.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 0, 1))
        xAxis.isEnabled = enabled
        content.add(xAxis)

        // Y axis (green)
        let yAxis = ModelEntity(
            mesh: .generateCylinder(height: axisLength, radius: axisRadius),
            materials: [SimpleMaterial(color: .green, isMetallic: false)]
        )
        yAxis.name = Self.yAxisName
        yAxis.position = SIMD3<Float>(0, axisLength / 2, 0)
        yAxis.isEnabled = enabled
        content.add(yAxis)

        // Z axis (blue)
        let zAxis = ModelEntity(
            mesh: .generateCylinder(height: axisLength, radius: axisRadius),
            materials: [SimpleMaterial(color: .blue, isMetallic: false)]
        )
        zAxis.name = Self.zAxisName
        zAxis.position = SIMD3<Float>(0, 0, axisLength / 2)
        zAxis.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
        zAxis.isEnabled = enabled
        content.add(zAxis)
    }

    @MainActor
    private func updateAxes(in content: RealityViewCameraContent) {
        let showAxes = controller.showAxes
        let config = controller.configuration
        let axisNames = [Self.xAxisName, Self.yAxisName, Self.zAxisName]

        for name in axisNames {
            guard let axis = content.entities.first(where: { $0.name == name }) else { continue }
            axis.isEnabled = showAxes

            if showAxes && config.axisStyle == .constantScreenWidth {
                let initialDistance = config.initialCameraState.distance
                let currentDistance = controller.cameraState.distance
                let scaleFactor = currentDistance / initialDistance
                // Scale cross-section (X and Z) while preserving length (Y)
                axis.scale = SIMD3<Float>(scaleFactor, 1.0, scaleFactor)
            } else {
                axis.scale = SIMD3<Float>(1.0, 1.0, 1.0)
            }
        }
    }
}

// MARK: - iOS Two-Finger Pan Gesture

#if os(iOS)
/// A transparent UIView overlay that recognizes two-finger pan gestures via UIKit.
///
/// SwiftUI's `DragGesture` cannot distinguish finger count, so this bridges
/// a `UIPanGestureRecognizer` configured for exactly two touches.
private struct TwoFingerPanGestureView: UIViewRepresentable {
    var onChanged: (CGSize) -> Void
    var onEnded: (CGSize) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let recognizer = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        recognizer.minimumNumberOfTouches = 2
        recognizer.maximumNumberOfTouches = 2
        recognizer.delegate = context.coordinator
        view.addGestureRecognizer(recognizer)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onChanged: onChanged, onEnded: onEnded)
    }

    @MainActor
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onChanged: (CGSize) -> Void
        var onEnded: (CGSize) -> Void

        init(onChanged: @escaping (CGSize) -> Void, onEnded: @escaping (CGSize) -> Void) {
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .changed:
                let translation = recognizer.translation(in: recognizer.view)
                onChanged(CGSize(width: translation.x, height: translation.y))
                recognizer.setTranslation(.zero, in: recognizer.view)
            case .ended, .cancelled:
                let velocity = recognizer.velocity(in: recognizer.view)
                onEnded(CGSize(width: velocity.x, height: velocity.y))
            default:
                break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
#endif

// MARK: - Platform Color Type

#if os(iOS)
private typealias PlatformColor = UIColor
#else
private typealias PlatformColor = NSColor
#endif
