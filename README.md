# OCCTSwiftViewport

A reusable Metal-based 3D viewport library for CAD applications on iOS and macOS. Designed as a rendering companion to [OCCTSwift](https://github.com/gsdali/OCCTSwift) — the two libraries are fully independent, with your app bridging geometry and display.

```
Your App
  ├── OCCTSwift          (geometry kernel — B-Rep, STEP, booleans, etc.)
  ├── OCCTSwiftViewport  (this library — Metal rendering, camera, picking)
  └── bridges Shape → ViewportBody → viewport display
```

## Features

- **Metal renderer** — Blinn-Phong shading, 3-light setup, shadow maps, environment mapping
- **Camera system** — Arcball, turntable, and first-person rotation with inertia and animation
- **ViewCube** — Interactive orientation widget with 26 clickable regions
- **GPU picking** — TBDR imageblock-based pick ID buffer for body and face selection
- **Display modes** — Wireframe, shaded, shaded-with-edges
- **Lighting presets** — `.threePoint`, `.studio`, `.architectural`, `.flat`
- **Gesture presets** — `.default`, `.blender`, `.fusion360`
- **Clip planes** — Section views with configurable cut planes
- **Measurements** — Distance, angle, and radius overlays
- **Grid and axes** — Adaptive instanced dot grid, RGB axis lines
- **Shadow maps** — Directional light depth pass
- **Swift 6 ready** — Full `Sendable` conformance, `@MainActor` isolation
- **Cross-platform** — iOS 18+ and macOS 15+ from shared source

## Requirements

- iOS 18+ / macOS 15+
- Swift 6.0+
- Xcode 16+

## Installation

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/gsdali/OCCTSwiftViewport.git", from: "0.40.0")
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

## Using with OCCTSwift

OCCTSwiftViewport has no dependency on OCCTSwift. Your app bridges the two by converting OCCTSwift `Shape` objects into `ViewportBody` values that the viewport can render.

### Converting Shapes to ViewportBody

```swift
import OCCTSwift
import OCCTSwiftViewport

// Triangulate the shape
let shape = Shape.box(width: 10, height: 5, depth: 3)!
let mesh = shape.triangulate(deflection: 0.1)

// Build interleaved vertex data: [px, py, pz, nx, ny, nz, ...]
var vertexData: [Float] = []
var indices: [UInt32] = []
for face in mesh.faces {
    for vertex in face.vertices {
        vertexData.append(contentsOf: [
            Float(vertex.position.x), Float(vertex.position.y), Float(vertex.position.z),
            Float(vertex.normal.x), Float(vertex.normal.y), Float(vertex.normal.z)
        ])
    }
    indices.append(contentsOf: face.indices)
}

// Extract wireframe edges
var edges: [[SIMD3<Float>]] = []
for i in 0..<shape.edgeCount {
    if let pts = shape.edgePolyline(at: i, deflection: 0.1) {
        edges.append(pts.map { SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z)) })
    }
}

let body = ViewportBody(
    id: "my-part",
    vertexData: vertexData,
    indices: indices,
    edges: edges,
    color: SIMD4<Float>(0.7, 0.7, 0.75, 1.0)
)
```

### The Demo App's CADFileLoader

The included demo app (`Sources/OCCTSwiftMetalDemo/`) has a `CADFileLoader` that handles the OCCTSwift → ViewportBody conversion for STEP, STL, OBJ, and BREP files. You can use it as a reference or copy it into your project.

```swift
// Load a STEP file into viewport bodies
let (bodies, shapes) = try CADFileLoader.load(from: stepFileURL)
```

## Camera Control

```swift
// Rotation styles
controller.cameraController.rotationStyle = .turntable  // Z-up locked (CAD default)
controller.cameraController.rotationStyle = .arcball    // Free rotation

// Standard views
controller.goToStandardView(.top)
controller.goToStandardView(.front)
controller.goToStandardView(.isometricFrontRight)

// Focus on geometry
controller.focusOnBounds()  // Fit all bodies in view
controller.focusOn(point: SIMD3<Float>(0, 0, 0), distance: 10)

// Reset
controller.reset()
```

## Gesture Configuration

```swift
// Use a preset
let config = ViewportConfiguration(
    gestureConfiguration: .blender  // or .fusion360, .default
)

// Or customize
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

## Display Modes and Lighting

```swift
// Display modes
controller.displayMode = .shaded
controller.displayMode = .wireframe
controller.displayMode = .shadedWithEdges

// Lighting presets
let config = ViewportConfiguration(
    lightingConfiguration: .threePoint  // Key, fill, and back lights
)
// Also: .studio, .architectural, .flat
```

## GPU Picking and Selection

```swift
// Pick at a screen coordinate
if let hit = controller.pick(at: screenPoint) {
    print("Hit body: \(hit.bodyIndex), face: \(hit.faceIndex)")
}

// CPU-side raycasting for more control
let ray = ProjectionUtility.ray(from: screenPoint, viewport: size,
                                 camera: controller.cameraState)
let hits = SceneRaycast.cast(ray: ray, bodies: bodies)
```

## Clip Planes

```swift
// Add a section cut
let clip = ClipPlane(
    normal: SIMD3<Float>(0, 1, 0),  // Cut along Y axis
    distance: 0.0
)
controller.clipPlanes = [clip]
```

## Measurements

```swift
// Distance between two points
let measurement = DistanceMeasurement(
    from: SIMD3<Float>(0, 0, 0),
    to: SIMD3<Float>(10, 0, 0)
)
controller.measurements = [.distance(measurement)]

// Overlay renders leader lines and labels automatically
MeasurementOverlay(controller: controller)
```

## ViewCube

```swift
// The ViewCube is built into MetalViewportView
// Click faces → orthographic views (Top, Front, Right, etc.)
// Click corners → isometric views
// Click edges → intermediate views

// Or use ViewCubeView standalone
ViewCubeView(controller: controller)
    .frame(width: 100, height: 100)
```

## Script Harness (CadQuery/OpenSCAD-style workflow)

A companion package [OCCTSwiftScripts](https://github.com/gsdali/OCCTSwiftScripts) provides a scripting workflow: edit Swift code, run it, and see geometry live in the viewport.

```
main.swift (full OCCTSwift API)
    │  swift run Script (~1-2s)
    ▼
iCloud Drive / OCCTSwiftScripts / output /
    ├─ body-0.brep
    ├─ body-1.brep
    ├─ manifest.json  ← triggers viewport reload
    └─ output.step    ← for external tools
    │
    ▼  iCloud sync (Mac ↔ iPhone)
    │
Demo app (ScriptWatcher auto-loads new geometry)
```

### Setup

```bash
git clone https://github.com/gsdali/OCCTSwiftScripts.git
cd OCCTSwiftScripts
swift build          # First build ~30s (pulls OCCTSwift)
```

### Write a script

```swift
// Sources/Script/main.swift
import OCCTSwift
import ScriptHarness

let ctx = ScriptContext(metadata: ManifestMetadata(
    name: "Bracket Assembly",
    revision: "3",
    source: "Customer drawing D-1234"
))
let C = ScriptContext.Colors.self

// Build geometry using the full OCCTSwift API
let base = Shape.box(width: 50, height: 10, depth: 30)!
let hole = Shape.cylinder(radius: 5, height: 12)!
    .translated(by: SIMD3(20, -1, 15))
let bracket = base.subtracting(hole)!
    .filleted(radius: 1.5)!

try ctx.add(bracket, id: "bracket", color: C.steel, name: "Main bracket")
try ctx.emit(description: "Bracket with mounting hole")
```

```bash
swift run Script     # Output appears in viewport automatically
```

### View on iPhone

1. Scripts write to iCloud Drive (`~/Library/Mobile Documents/com~apple~CloudDocs/OCCTSwiftScripts/output/`)
2. iCloud syncs BREP + manifest to iPhone
3. Demo app → Settings → Script Watcher → toggle on
4. Gallery view shows available scripts with metadata

### Promoting Scripts to Libraries

Once geometry code is validated in a script, extract it into a shared library that both scripts and apps import:

```swift
// Sources/BracketLib/Bracket.swift
public struct BracketResult { ... }
public enum Bracket {
    public static func build(holeRadius: Double = 5) -> BracketResult { ... }
}

// Sources/Script/main.swift — now a thin wrapper
let result = Bracket.build(holeRadius: 6)
try ctx.add(result.shape, id: "bracket", color: C.steel)
try ctx.emit(description: result.metadata.name)

// YourApp/ContentView.swift — same build() function
let result = Bracket.build(holeRadius: 6)
let body = convertToViewportBody(result.shape)
```

See [docs/SCRIPT_WORKFLOW.md](https://github.com/gsdali/OCCTSwiftScripts/blob/main/docs/SCRIPT_WORKFLOW.md) for the full workflow guide including HLR 2D views, dimension annotations, and library extraction patterns.

## Architecture

```
MetalViewportView (SwiftUI entry point)
  └─ MTKView via UIViewRepresentable / NSViewRepresentable
      └─ gesture handlers (iOS: drag/pinch/rotation/tap, macOS: mouse/scroll)

ViewportController (@MainActor, ObservableObject — central hub)
  ├─ CameraController (orbit/pan/zoom with inertia + SLERP animation)
  │   └─ CameraState (immutable value — rotation, distance, pivot, projection)
  ├─ PivotStrategy (dynamic orbit center based on zoom level)
  └─ ViewportRenderer (MTKViewDelegate — Metal render loop)
      ├─ Shaded pipeline   (3-light Blinn-Phong + hemisphere ambient + Fresnel rim)
      ├─ Wireframe pipeline (contrast-adaptive edges, depth-biased)
      ├─ Grid pipeline     (adaptive instanced dots)
      ├─ Axes pipeline     (RGB colored lines)
      ├─ Shadow map        (ShadowMapManager — directional light depth pass)
      ├─ Environment map   (EnvironmentMapManager — image-based lighting)
      └─ Pick ID texture   (R32Uint second color attachment, TBDR imageblock)
```

### Key Types

| Type | Role |
|------|------|
| `MetalViewportView` | SwiftUI view wrapping MTKView |
| `ViewportController` | Central observable state hub |
| `ViewportBody` | Geometry container (vertices + edges + color) |
| `CameraState` | Immutable camera orientation value |
| `CameraController` | Input handling + animation |
| `ViewportConfiguration` | Gesture + lighting + display settings |
| `GestureConfiguration` | Input mapping presets |
| `LightingConfiguration` | Light position/color presets |
| `ClipPlane` | Section cut plane |
| `SceneRaycast` | CPU-side ray intersection |
| `ProjectionUtility` | Screen ↔ world coordinate conversion |
| `PickResult` | GPU pick hit info |
| `ViewCubeView` | Orientation widget |

### Geometry Input

`ViewportBody` is geometry-source agnostic. It doesn't know about OCCT, BREP, or any CAD kernel:

```swift
ViewportBody(
    id: String,                    // Unique identifier
    vertexData: [Float],           // Interleaved [px,py,pz, nx,ny,nz, ...]
    indices: [UInt32],             // Triangle indices
    edges: [[SIMD3<Float>]],      // Wireframe polylines
    color: SIMD4<Float>,          // RGBA color
    faceIndices: [Int32]? = nil   // Optional: maps triangles → face IDs
)
```

### Swift 6 Concurrency

- All mutable state holders are `@MainActor`: `ViewportController`, `CameraController`, `ViewportRenderer`
- All value types are `Sendable`: `CameraState`, `ViewportBody`, `BoundingBox`, `Ray`, configurations
- No `DispatchQueue` usage — clean actor isolation throughout

## Demo App

The `OCCTSwiftMetalDemo` app exercises 60+ OCCTSwift features through interactive galleries:

| Gallery | Features | Count |
|---------|----------|-------|
| Curves 2D | Showcases, intersections, hatching, tangent circles | 4 |
| Curves 3D | Helix, spirals, curvature combs, BSpline fitting | 4 |
| Surfaces | Analytic, swept, freeform, pipe, iso-curves | 5 |
| Sweeps | Variable-section pipes with LawFunction | 4 |
| Projections | Curve/point projection onto surfaces | 4 |
| Plates | Plate surfaces, NLPlate deformation | 3 |
| Medial Axis | Voronoi skeleton, wall thickness map | 4 |
| Naming | TNaming topological history tracking | 4 |
| Annotations | Dimensions, labels, point clouds | 4 |
| OCCT 8 Features | v0.28–v0.93 comprehensive demos | 59 |

### Running the Demo

```bash
# macOS
swift run OCCTSwiftMetalDemo

# iOS (requires Xcode project)
xcodegen                    # Generate from project.yml
open OCCTSwiftViewport.xcodeproj
# Select OCCTSwiftMetalDemo_iOS scheme → Run
```

### File Import

The demo app imports STEP, STL, OBJ, and BREP files. On macOS, drag and drop or use the file picker. On iOS, use the Files integration.

## Testing

37 tests across 9 suites using Swift Testing framework:

```bash
swift test                                    # Run all tests
swift test --filter CameraStateTests          # Single suite
swift test --filter "CameraStateTests/Default initialization"  # Single test
```

Test suites cover camera state, bounding box, ray casting, projection, pivot strategy, and viewport body primitives.

## Build

```bash
swift build                           # Debug build
swift package clean && swift build    # Clean build (stale PCH fix)
xcodegen                             # Regenerate Xcode project from project.yml
```

**Note:** OCCTSwift is a local path dependency (`../OCCTSwift` in Package.swift). Clone both repositories as siblings:

```bash
git clone https://github.com/gsdali/OCCTSwift.git
git clone https://github.com/gsdali/OCCTSwiftViewport.git
# They should be at the same directory level
```

## License

LGPL-2.1-only with Open CASCADE Technology Exception 1.0. See [LICENSE](LICENSE) and [OCCT_LGPL_EXCEPTION.md](OCCT_LGPL_EXCEPTION.md).
