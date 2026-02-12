// ViewportController.swift
// ViewportKit
//
// Observable controller for viewport state management.

import Foundation
import Combine
import RealityKit
import simd

/// Observable controller managing viewport state and interactions.
///
/// ViewportController is the main interface for controlling the viewport.
/// It manages camera state, handles user input, and coordinates with
/// the underlying RealityKit scene.
///
/// ## Example
///
/// ```swift
/// struct MyView: View {
///     @StateObject private var controller = ViewportController()
///
///     var body: some View {
///         ViewportView(controller: controller) { content in
///             // Add your 3D content here
///         }
///         .toolbar {
///             Button("Top") { controller.goToStandardView(.top) }
///         }
///     }
/// }
/// ```
@MainActor
public final class ViewportController: ObservableObject {

    // MARK: - Published Properties

    /// Current camera state.
    @Published public private(set) var cameraState: CameraState

    /// Current display mode.
    @Published public var displayMode: DisplayMode

    /// Whether the ViewCube is visible.
    @Published public var showViewCube: Bool

    /// Whether the coordinate axes are visible.
    @Published public var showAxes: Bool

    /// Whether the grid is visible.
    @Published public var showGrid: Bool

    /// Whether an animation is in progress.
    @Published public private(set) var isAnimating: Bool = false

    /// Lighting configuration for live adjustment.
    @Published public var lightingConfiguration: LightingConfiguration

    // MARK: - Configuration

    /// Viewport configuration.
    public let configuration: ViewportConfiguration

    // MARK: - Internal Components

    /// The camera controller managing movement.
    public let cameraController: CameraController

    /// The RealityKit camera entity (set by ViewportView).
    internal var cameraEntity: Entity?

    /// Cancellables for Combine subscriptions.
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    /// Creates a viewport controller with the specified configuration.
    public init(configuration: ViewportConfiguration = .cad) {
        self.configuration = configuration
        self.cameraState = configuration.initialCameraState
        self.displayMode = configuration.displayMode
        self.showViewCube = configuration.showViewCube
        self.showAxes = configuration.showAxes
        self.showGrid = configuration.showGrid
        self.lightingConfiguration = configuration.lightingConfiguration

        self.cameraController = CameraController(initialState: configuration.initialCameraState)
        cameraController.rotationStyle = configuration.rotationStyle
        cameraController.minDistance = configuration.minDistance
        cameraController.maxDistance = configuration.maxDistance

        // Apply gesture configuration
        let gc = configuration.gestureConfiguration
        cameraController.orbitSensitivity = gc.orbitSensitivity
        cameraController.panSensitivity = gc.panSensitivity
        cameraController.zoomSensitivity = gc.zoomSensitivity
        cameraController.scrollZoomSensitivity = gc.scrollZoomSensitivity
        cameraController.enableInertia = gc.enableInertia
        cameraController.dampingFactor = gc.dampingFactor

        // Subscribe to camera controller updates
        cameraController.$cameraState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.cameraState = state
            }
            .store(in: &cancellables)

        cameraController.$isAnimating
            .receive(on: DispatchQueue.main)
            .sink { [weak self] animating in
                self?.isAnimating = animating
            }
            .store(in: &cancellables)
    }

    // MARK: - Standard Views

    /// Animates to a standard view.
    ///
    /// - Parameters:
    ///   - view: The target standard view
    ///   - duration: Animation duration in seconds
    public func goToStandardView(_ view: StandardView, duration: Float = 0.3) {
        cameraController.animateTo(view, duration: duration)
    }

    /// Animates to a specific camera state.
    public func animateTo(_ state: CameraState, duration: Float = 0.3) {
        cameraController.animateTo(state, duration: duration)
    }

    // MARK: - Camera Control

    /// Handles orbit gesture input.
    public func handleOrbit(translation: CGSize) {
        cameraController.orbit(
            deltaX: Float(translation.width),
            deltaY: Float(translation.height)
        )
    }

    /// Ends orbit with velocity for inertia.
    public func endOrbit(velocity: CGSize) {
        cameraController.setAngularVelocity(SIMD2<Float>(
            Float(velocity.width) * 0.001,
            Float(velocity.height) * 0.001
        ))
    }

    /// Handles pan gesture input.
    public func handlePan(translation: CGSize) {
        cameraController.pan(
            deltaX: Float(translation.width),
            deltaY: Float(translation.height)
        )
    }

    /// Ends pan with velocity for inertia.
    public func endPan(velocity: CGSize) {
        cameraController.setPanVelocity(SIMD2<Float>(
            Float(velocity.width) * 0.001,
            Float(velocity.height) * 0.001
        ))
    }

    /// Handles zoom gesture input.
    public func handleZoom(magnification: CGFloat) {
        cameraController.zoom(factor: Float(magnification))
    }

    /// Handles scroll wheel zoom.
    public func handleScrollZoom(delta: CGFloat) {
        cameraController.scrollZoom(delta: Float(delta))
    }

    /// Focuses on a specific point.
    public func focusOn(point: SIMD3<Float>, distance: Float? = nil, animated: Bool = true) {
        cameraController.focusOn(point: point, distance: distance, animated: animated)
    }

    /// Resets the camera to the default view.
    public func reset(animated: Bool = true) {
        cameraController.reset(animated: animated)
    }

    // MARK: - Display Mode

    /// Cycles to the next display mode.
    public func cycleDisplayMode() {
        let modes = DisplayMode.allCases
        guard let currentIndex = modes.firstIndex(of: displayMode) else { return }
        let nextIndex = (currentIndex + 1) % modes.count
        displayMode = modes[nextIndex]
    }

    // MARK: - Toggle Methods

    /// Toggles ViewCube visibility.
    public func toggleViewCube() {
        showViewCube.toggle()
    }

    /// Toggles axes visibility.
    public func toggleAxes() {
        showAxes.toggle()
    }

    /// Toggles grid visibility.
    public func toggleGrid() {
        showGrid.toggle()
    }

    // MARK: - Projection Mode

    /// Toggles between perspective and orthographic projection.
    public func toggleProjection() {
        var state = cameraState
        state.isOrthographic.toggle()
        animateTo(state, duration: 0.3)
    }
}

// MARK: - Keyboard Shortcuts

extension ViewportController {
    /// Handles keyboard shortcuts for standard views and display modes.
    public func handleKeyPress(_ key: Character) {
        // Standard view shortcuts
        for view in StandardView.allCases {
            if view.keyboardShortcut == key {
                goToStandardView(view)
                return
            }
        }

        // Display mode shortcuts
        for mode in DisplayMode.allCases {
            if mode.keyboardShortcut == key {
                displayMode = mode
                return
            }
        }
    }
}
