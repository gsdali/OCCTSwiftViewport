# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

OCCTSwiftViewport is a reusable Metal-based 3D viewport library for CAD applications, designed as a companion to [OCCTSwift](https://github.com/gsdali/OCCTSwift). The two libraries are fully independent — OCCTSwiftViewport has no knowledge of OCCT or B-Rep topology; OCCTSwift has no knowledge of rendering. The consuming app bridges them.

**Requirements:** iOS 18+ / macOS 15+, Swift 6.0+, Xcode 16+

## Build & Test Commands

```bash
# Build (Swift Package Manager)
swift build

# Run all tests (37 tests across 5 suites, uses Swift Testing framework)
swift test

# Run a single test suite
swift test --filter CameraStateTests

# Run a single test
swift test --filter "CameraStateTests/Default initialization"

# Clean build (use if stale PCH errors after renames)
swift package clean && swift build

# Run the demo app via SPM
swift run OCCTSwiftMetalDemo
```

The Xcode project (`ViewportKit.xcodeproj`) is generated from `project.yml` via [XcodeGen](https://github.com/yonaskolb/XcodeGen). It has two schemes: `OCCTSwiftMetalDemo_iOS` and `OCCTSwiftMetalDemo_macOS`. Regenerate after structural changes with `xcodegen`.

## Architecture

### Layer Separation

```
Your App (bridges OCCTSwift geometry → ViewportBody → OCCTSwiftViewport display)
    |                    |
OCCTSwift           OCCTSwiftViewport
(geometry kernel)   (rendering + viewport)
No dependency between them.
```

### Core Rendering Pipeline

```
ViewportController (@MainActor, ObservableObject — central hub)
  ├─ CameraController (@MainActor — orbit/pan/zoom with inertia + animation)
  │   └─ CameraState (immutable value type — rotation, distance, pivot, projection)
  ├─ PivotStrategy (@MainActor — dynamic orbit center based on zoom level)
  └─ ViewportRenderer (@MainActor, MTKViewDelegate — Metal render loop)
      ├─ Shaded pipeline (3-light Blinn-Phong + hemisphere ambient + Fresnel rim)
      ├─ Wireframe pipeline (contrast-adaptive edges, depth-biased)
      ├─ Grid pipeline (adaptive instanced dots)
      ├─ Axes pipeline (RGB colored lines)
      └─ Pick ID texture (R32Uint second color attachment, TBDR imageblock-based)
```

`MetalViewportView` is the SwiftUI entry point. It wraps `MTKView` via platform-specific representables and attaches gesture handlers (iOS: drag/pinch/rotation/tap; macOS: mouse with modifier keys + scroll wheel).

### Geometry Input

`ViewportBody` is the geometry-source-agnostic container. Vertex data is interleaved `[px, py, pz, nx, ny, nz, ...]` with stride 6 floats (24 bytes). Edge polylines are `[[SIMD3<Float>]]` for wireframe rendering. A generation counter enables buffer cache invalidation without diffing.

### GPU Picking

Pick IDs are encoded as `objectIndex | (primitiveID << 16)` into a R32Uint texture rendered as a second color attachment. `PickTextureManager` handles texture lifecycle. CPU-side raycasting (`SceneRaycast`) provides broadphase AABB culling then narrowphase Moller-Trumbore triangle intersection.

### Shaders

All Metal shaders are in `Sources/OCCTSwiftViewport/Renderer/Shaders.metal`. The uniform structs (`Uniforms`, `BodyUniforms`) must stay in sync between Swift and Metal — changes to one require matching changes in the other.

### Camera System

Three rotation styles: **arcball** (Ken Shoemake virtual sphere), **turntable** (Z-up locked spherical coords), **first-person** (yaw/pitch). Animation uses SLERP for rotation with ease-out (t³) curves on a 60 FPS timer. `PivotStrategy` auto-adjusts the orbit center: scene center when zoomed out, raycast hit point when zoomed in, with smoothstep blending in the transition zone.

## Swift 6 Concurrency Model

- All mutable state holders are `@MainActor`: `ViewportController`, `CameraController`, `ViewportRenderer`, `PivotStrategy`
- All value types and configs are `Sendable`: `CameraState`, `ViewportBody`, `BoundingBox`, `Ray`, `ViewportConfiguration`, `GestureConfiguration`, `LightingConfiguration`
- MetalKit imported with `@preconcurrency` for MTL type conformance
- `ViewportBody` uses `nonisolated(unsafe)` only for its static generation counter

## Key Conventions

- The public API surface is re-exported via typealiases in `Sources/OCCTSwiftViewport/OCCTSwiftViewport.swift`
- `ViewportBody` has convenience factory methods (`.box()`, `.cylinder()`, `.sphere()`, `.torus()`) in `Primitives.swift` for testing and demos
- Platform-specific code uses `#if os(iOS)` / `#elseif os(macOS)` blocks
- macOS uses a custom `ScrollCaptureMTKView` subclass for scroll/mouse events
- Tests use the Swift Testing framework (`import Testing`, `@Test`, `@Suite`), not XCTest
