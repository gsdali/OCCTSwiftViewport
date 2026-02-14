// SpikeView.swift
// Test UI for Metal renderer spike.

import SwiftUI
import ViewportKit

struct SpikeView: View {
    @StateObject private var controller = ViewportController(
        configuration: ViewportConfiguration(
            rotationStyle: .turntable,
            showViewCube: true,
            showAxes: true,
            showGrid: true,
            pickingConfiguration: PickingConfiguration(isEnabled: true)
        )
    )

    /// Stores the original (unselected) color for each body.
    @State private var originalColors: [String: SIMD4<Float>] = [:]

    @State private var bodies: [ViewportBody] = [
        .box(
            id: "box",
            width: 1.5, height: 1.5, depth: 1.5,
            color: SIMD4<Float>(0.4, 0.6, 0.9, 1.0)
        ),
        .cylinder(
            id: "cylinder",
            radius: 0.5, height: 2.0, segments: 32,
            color: SIMD4<Float>(0.9, 0.5, 0.3, 1.0)
        ),
        .sphere(
            id: "sphere",
            radius: 0.7, segments: 32, rings: 16,
            color: SIMD4<Float>(0.3, 0.8, 0.4, 1.0)
        ),
    ]

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            MetalViewportView(controller: controller, bodies: $bodies)
        }
        .onAppear {
            // Position primitives so they don't overlap
            offsetBody(id: "box", dx: -2.5, dy: 0.75, dz: 0)
            offsetBody(id: "cylinder", dx: 0, dy: 1.0, dz: 0)
            offsetBody(id: "sphere", dx: 2.5, dy: 0.7, dz: 0)
            // Store original colors for selection highlighting
            for body in bodies {
                originalColors[body.id] = body.color
            }
        }
        .onChange(of: controller.pickResult) {
            applySelectionHighlight()
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List {
            selectionSection
            standardViewsSection
            displayModeSection
            overlaysSection
            projectionSection
            lightingSection
            statusSection
        }
        .navigationTitle("Metal Spike")
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        #endif
    }

    private var selectionSection: some View {
        Section("Selection") {
            if let pick = controller.pickResult {
                LabeledContent("Body", value: pick.bodyID)
                LabeledContent("Triangle", value: "\(pick.triangleIndex)")
                Button("Clear Selection") {
                    controller.clearSelection()
                }
            } else {
                Text("Click a body to select")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var standardViewsSection: some View {
        Section("Standard Views") {
            Button("Top") { controller.goToStandardView(.top) }
            Button("Front") { controller.goToStandardView(.front) }
            Button("Right") { controller.goToStandardView(.right) }
            Button("Isometric") { controller.goToStandardView(.isometricFrontRight) }
        }
    }

    private var displayModeSection: some View {
        Section("Display Mode") {
            Picker("Mode", selection: $controller.displayMode) {
                Text("Shaded").tag(DisplayMode.shaded)
                Text("Wireframe").tag(DisplayMode.wireframe)
                Text("Shaded + Edges").tag(DisplayMode.shadedWithEdges)
            }
            .pickerStyle(.inline)
        }
    }

    private var overlaysSection: some View {
        Section("Overlays") {
            Toggle("Grid", isOn: $controller.showGrid)
            Toggle("Axes", isOn: $controller.showAxes)
            Toggle("ViewCube", isOn: $controller.showViewCube)
        }
    }

    private var projectionSection: some View {
        Section("Projection") {
            Button(controller.cameraState.isOrthographic ? "Switch to Perspective" : "Switch to Orthographic") {
                controller.toggleProjection()
            }
        }
    }

    private var lightingSection: some View {
        Section("Lighting") {
            VStack(alignment: .leading) {
                Text("Specular Intensity: \(controller.lightingConfiguration.specularIntensity, specifier: "%.2f")")
                Slider(value: $controller.lightingConfiguration.specularIntensity, in: 0...1)
            }
            VStack(alignment: .leading) {
                Text("Shininess: \(controller.lightingConfiguration.specularPower, specifier: "%.0f")")
                Slider(value: $controller.lightingConfiguration.specularPower, in: 1...256)
            }
            VStack(alignment: .leading) {
                Text("Rim Light: \(controller.lightingConfiguration.fresnelIntensity, specifier: "%.2f")")
                Slider(value: $controller.lightingConfiguration.fresnelIntensity, in: 0...1)
            }
            VStack(alignment: .leading) {
                Text("Matcap Blend: \(controller.lightingConfiguration.matcapBlend, specifier: "%.2f")")
                Slider(value: $controller.lightingConfiguration.matcapBlend, in: 0...1)
            }
        }
    }

    private var statusSection: some View {
        Section("Status") {
            LabeledContent("Distance", value: String(format: "%.1f", controller.cameraState.distance))
            LabeledContent("Projection", value: controller.cameraState.isOrthographic ? "Orthographic" : "Perspective")
            LabeledContent("Display", value: controller.displayMode.displayName)
        }
    }

    // MARK: - Selection Highlight

    private func applySelectionHighlight() {
        let selectedID = controller.pickResult?.bodyID
        for i in bodies.indices {
            let id = bodies[i].id
            if id == selectedID {
                // Brighten the selected body
                if let orig = originalColors[id] {
                    bodies[i].color = SIMD4<Float>(
                        min(orig.x + 0.3, 1.0),
                        min(orig.y + 0.3, 1.0),
                        min(orig.z + 0.3, 1.0),
                        orig.w
                    )
                }
            } else {
                // Restore original color
                if let orig = originalColors[id] {
                    bodies[i].color = orig
                }
            }
        }
    }

    // MARK: - Helpers

    private func offsetBody(id: String, dx: Float, dy: Float, dz: Float) {
        guard let index = bodies.firstIndex(where: { $0.id == id }) else { return }
        var body = bodies[index]
        var newVerts: [Float] = []
        let vertexStride = 6
        for i in Swift.stride(from: 0, to: body.vertexData.count, by: vertexStride) {
            newVerts.append(body.vertexData[i] + dx)
            newVerts.append(body.vertexData[i + 1] + dy)
            newVerts.append(body.vertexData[i + 2] + dz)
            newVerts.append(body.vertexData[i + 3])
            newVerts.append(body.vertexData[i + 4])
            newVerts.append(body.vertexData[i + 5])
        }
        body.vertexData = newVerts
        body.edges = body.edges.map { polyline in
            polyline.map { p in SIMD3<Float>(p.x + dx, p.y + dy, p.z + dz) }
        }
        bodies[index] = body
    }
}
