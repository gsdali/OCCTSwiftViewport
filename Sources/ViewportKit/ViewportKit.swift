// ViewportKit
// A reusable 3D viewport component for CAD applications using RealityKit
//
// Copyright (c) 2026. All rights reserved.

/// ViewportKit provides a complete 3D viewport solution for CAD applications.
///
/// ## Overview
///
/// ViewportKit is built on RealityKit and provides:
/// - Smooth camera controls (orbit, pan, zoom) with inertia
/// - Arcball and turntable rotation styles
/// - ViewCube for orientation and quick navigation
/// - Configurable gestures for iOS and macOS
/// - Standard view presets (Top, Front, Isometric, etc.)
/// - Professional three-point lighting
///
/// ## Quick Start
///
/// ```swift
/// import SwiftUI
/// import ViewportKit
///
/// struct ContentView: View {
///     @StateObject private var controller = ViewportController()
///
///     var body: some View {
///         ViewportView(controller: controller) { content in
///             let box = ModelEntity(
///                 mesh: .generateBox(size: 1),
///                 materials: [SimpleMaterial(color: .gray, isMetallic: true)]
///             )
///             content.add(box)
///         }
///     }
/// }
/// ```
///
/// ## Camera Control
///
/// The viewport supports multiple camera control styles:
///
/// ```swift
/// // Configure rotation style
/// controller.cameraController.rotationStyle = .turntable  // Z-up locked
/// controller.cameraController.rotationStyle = .arcball    // Free rotation
///
/// // Animate to standard views
/// controller.goToStandardView(.top)
/// controller.goToStandardView(.isometricFrontRight)
///
/// // Focus on a point
/// controller.focusOn(point: SIMD3<Float>(0, 0, 0), distance: 10)
/// ```
///
/// ## Gesture Configuration
///
/// Customize gesture behavior for your application:
///
/// ```swift
/// let config = ViewportConfiguration(
///     gestureConfiguration: GestureConfiguration(
///         singleFingerDrag: .orbit,
///         twoFingerDrag: .pan,
///         pinchGesture: .zoom
///     )
/// )
/// let controller = ViewportController(configuration: config)
/// ```

// MARK: - Public API

// Camera
public typealias _CameraState = CameraState
public typealias _CameraController = CameraController
public typealias _StandardView = StandardView
public typealias _RotationStyle = RotationStyle
public typealias _ViewCubeFace = ViewCubeFace

// Views
public typealias _ViewportView = ViewportView
public typealias _ViewportController = ViewportController

// Configuration
public typealias _ViewportConfiguration = ViewportConfiguration
public typealias _GestureConfiguration = GestureConfiguration
public typealias _GestureAction = GestureAction
public typealias _ViewCubePosition = ViewCubePosition

// Display
public typealias _DisplayMode = DisplayMode
public typealias _LightingConfiguration = LightingConfiguration
public typealias _LightSettings = LightSettings

// ViewCube
public typealias _ViewCubeView = ViewCubeView
public typealias _ViewCubeRegion = ViewCubeRegion
