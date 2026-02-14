# OCCTSwiftViewport

A reusable 3D viewport component for CAD applications using Metal, designed to work with [OCCTSwift](https://github.com/gsdali/OCCTSwift).

## Features

- **Metal-based**: Direct Metal renderer for CAD visualization with full pipeline control
- **Smooth Camera Controls**: Orbit, pan, and zoom with configurable sensitivity and inertia
- **Multiple Rotation Styles**: Arcball (free rotation) and turntable (Z-up locked)
- **ViewCube**: Interactive orientation cube with 26 clickable regions
- **Standard Views**: Quick access to Top, Front, Right, Isometric views
- **Configurable Gestures**: Customize gesture mappings for iOS and macOS
- **Professional Lighting**: Three-point lighting presets for CAD visualization
- **Display Modes**: Wireframe, shaded, and shaded-with-edges rendering
- **GPU Picking**: TBDR imageblock-based pick ID buffer for selection
- **Swift 6 Ready**: Full Sendable conformance and actor isolation

## Demo App

The included `OCCTSwiftMetalDemo` app exercises OCCTSwift features through interactive galleries:

| Gallery | OCCTSwift Feature | Demos |
|---------|-------------------|-------|
| **Geometry Analysis** | Face/Edge properties, proximity | Surface type, area, curvatures; curve type, length; curvature direction overlays; proximity detection |
| **Curve2D** | `Curve2D`, `Curve2DGcc` | Showcase, intersections, hatching, tangent circles |
| **Curve3D** | `Curve3D` | Showcase, helix & spirals, curvature combs, BSpline fitting |
| **Surface** | `Surface` | Analytic, swept, freeform, pipe surfaces, iso-curves |
| **Sweeps** | `LawFunction`, `pipeShellWithLaw` | Constant, linear taper, S-curve, interpolated variable-section pipes |
| **Projection** | `Surface.projectCurve3D`, `projectPoint` | Curve on cylinder/sphere, composite projection, point projection |
| **Plate** | `Surface.plateThrough`, `nlPlateDeformed` | Plate from points, G0 deformation, G1 tangent deformation |
| **Medial Axis** | `MedialAxis` (BRepMAT2d) | Rectangle/L-shape/T-shape skeletons, wall thickness map |
| **GD&T** | `Document` PMI | Dimensions, geometric tolerances, datums from STEP files |

## Requirements

- iOS 18+ / macOS 15+
- Swift 6.0+
- Xcode 16+

## Installation

Add OCCTSwiftViewport to your project using Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/gsdali/OCCTSwiftViewport.git", from: "0.15.0")
]
```

## Quick Start

```swift
import SwiftUI
import OCCTSwiftViewport

struct ContentView: View {
    @StateObject private var controller = ViewportController()
    @State private var bodies: [ViewportBody] = [
        .box(size: 1, color: .gray)
    ]

    var body: some View {
        MetalViewportView(controller: controller, bodies: $bodies)
    }
}
```

## Camera Control

```swift
// Configure rotation style
controller.cameraController.rotationStyle = .turntable  // Z-up locked
controller.cameraController.rotationStyle = .arcball    // Free rotation

// Animate to standard views
controller.goToStandardView(.top)
controller.goToStandardView(.isometricFrontRight)

// Focus on a point
controller.focusOn(point: SIMD3<Float>(0, 0, 0), distance: 10)

// Reset view
controller.reset()
```

## Gesture Configuration

```swift
let config = ViewportConfiguration(
    gestureConfiguration: GestureConfiguration(
        singleFingerDrag: .orbit,
        twoFingerDrag: .pan,
        pinchGesture: .zoom,
        enableInertia: true,
        dampingFactor: 0.1
    )
)
let controller = ViewportController(configuration: config)
```

## Display Modes

```swift
controller.displayMode = .shaded
controller.displayMode = .wireframe
controller.displayMode = .shadedWithEdges
```

## ViewCube

The ViewCube provides visual orientation and quick navigation:

- Click faces for orthographic views (Top, Front, Right, etc.)
- Click corners for isometric views
- Click edges for intermediate views

## Lighting

```swift
let config = ViewportConfiguration(
    lightingConfiguration: .threePoint  // Key, fill, and back lights
)

// Or use presets
.studio       // Soft studio lighting
.architectural // Outdoor simulation
.flat         // Technical visualization
```

## Architecture

OCCTSwiftViewport uses a clean separation of concerns:

- **CameraState**: Immutable value type capturing camera orientation
- **CameraController**: Handles input and animation
- **ViewportController**: Observable state management
- **MetalViewportView**: SwiftUI view with Metal integration

## License

LGPL-2.1-only with Open CASCADE Technology Exception 1.0. See [LICENSE](LICENSE) and [OCCT_LGPL_EXCEPTION.md](OCCT_LGPL_EXCEPTION.md).
