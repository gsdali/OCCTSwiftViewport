// ViewportConfiguration.swift
// ViewportKit
//
// Master configuration for viewport behavior and appearance.

import Foundation
import simd

/// Master configuration for a viewport.
///
/// ViewportConfiguration aggregates all settings for camera behavior,
/// gesture handling, display modes, and lighting.
public struct ViewportConfiguration: Sendable {

    // MARK: - Camera Settings

    /// Initial camera state when viewport loads.
    public var initialCameraState: CameraState

    /// Rotation style (arcball or turntable).
    public var rotationStyle: RotationStyle

    /// Minimum distance from pivot.
    public var minDistance: Float

    /// Maximum distance from pivot.
    public var maxDistance: Float

    /// Default field of view in degrees.
    public var defaultFieldOfView: Float

    // MARK: - Gesture Settings

    /// Gesture configuration.
    public var gestureConfiguration: GestureConfiguration

    // MARK: - Display Settings

    /// Display mode for geometry.
    public var displayMode: DisplayMode

    /// Lighting configuration.
    public var lightingConfiguration: LightingConfiguration

    /// Whether to show the ViewCube.
    public var showViewCube: Bool

    /// ViewCube position.
    public var viewCubePosition: ViewCubePosition

    /// Whether to show coordinate axes.
    public var showAxes: Bool

    /// Whether to show ground grid.
    public var showGrid: Bool

    /// Background color (platform-agnostic).
    public var backgroundColor: SIMD4<Float>

    // MARK: - Initialization

    /// Creates a viewport configuration with default settings.
    public init(
        initialCameraState: CameraState = .isometric,
        rotationStyle: RotationStyle = .turntable,
        minDistance: Float = 0.1,
        maxDistance: Float = 10000,
        defaultFieldOfView: Float = 45,
        gestureConfiguration: GestureConfiguration = .default,
        displayMode: DisplayMode = .shaded,
        lightingConfiguration: LightingConfiguration = .threePoint,
        showViewCube: Bool = true,
        viewCubePosition: ViewCubePosition = .bottomTrailing,
        showAxes: Bool = false,
        showGrid: Bool = true,
        backgroundColor: SIMD4<Float> = SIMD4<Float>(0.95, 0.95, 0.95, 1.0)
    ) {
        self.initialCameraState = initialCameraState
        self.rotationStyle = rotationStyle
        self.minDistance = minDistance
        self.maxDistance = maxDistance
        self.defaultFieldOfView = defaultFieldOfView
        self.gestureConfiguration = gestureConfiguration
        self.displayMode = displayMode
        self.lightingConfiguration = lightingConfiguration
        self.showViewCube = showViewCube
        self.viewCubePosition = viewCubePosition
        self.showAxes = showAxes
        self.showGrid = showGrid
        self.backgroundColor = backgroundColor
    }

    // MARK: - Presets

    /// Configuration optimized for CAD applications.
    public static let cad = ViewportConfiguration(
        rotationStyle: .turntable,
        showViewCube: true,
        showAxes: true,
        showGrid: true
    )

    /// Configuration optimized for model viewing.
    public static let modelViewer = ViewportConfiguration(
        rotationStyle: .arcball,
        showViewCube: false,
        showAxes: false,
        showGrid: false
    )

    /// Configuration for architectural visualization.
    public static let architectural = ViewportConfiguration(
        initialCameraState: StandardView.isometricFrontRight.cameraState(distance: 50),
        rotationStyle: .turntable,
        displayMode: .shaded,
        lightingConfiguration: .architectural,
        showViewCube: true,
        showGrid: true
    )
}

// MARK: - ViewCube Position

/// Position of the ViewCube overlay.
public enum ViewCubePosition: String, CaseIterable, Sendable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
}
