// CADSampleView.swift
// ViewportKit Sample - CAD Interface
//
// This sample demonstrates how to build a CAD-like interface using ViewportKit.
// Based on the RailwayCAD interface structure.

import SwiftUI
import RealityKit

// Note: In a real app, you would import ViewportKit
// import ViewportKit

/// Sample CAD interface demonstrating ViewportKit integration.
///
/// This view shows how to:
/// - Set up a ViewportView with custom content
/// - Add toolbar controls for standard views
/// - Create a sidebar with display options
/// - Handle keyboard shortcuts
///
/// ## Usage
///
/// ```swift
/// @main
/// struct CADApp: App {
///     var body: some Scene {
///         WindowGroup {
///             CADSampleView()
///         }
///     }
/// }
/// ```
public struct CADSampleView: View {

    // MARK: - State

    @StateObject private var viewportController = ViewportController(
        configuration: .cad
    )

    @State private var showInspector: Bool = true

    // MARK: - Body

    public init() {}

    public var body: some View {
        NavigationSplitView {
            // Left sidebar - Tools
            toolsSidebar
        } detail: {
            // Main viewport
            ZStack {
                ViewportView(controller: viewportController) { content in
                    await addSampleContent(to: &content)
                }

                // Top toolbar overlay
                VStack {
                    topToolbar
                    Spacer()
                    bottomStatusBar
                }
            }
        }
        .inspector(isPresented: $showInspector) {
            // Right panel - Properties
            propertiesInspector
        }
        #if os(macOS)
        .frame(minWidth: 900, minHeight: 600)
        #endif
    }

    // MARK: - Tools Sidebar

    private var toolsSidebar: some View {
        List {
            Section("View") {
                ForEach([StandardView.top, .front, .right, .isometricFrontRight], id: \.self) { view in
                    Button(view.displayName) {
                        viewportController.goToStandardView(view)
                    }
                }
            }

            Section("Display") {
                ForEach(DisplayMode.allCases, id: \.self) { mode in
                    Button {
                        viewportController.displayMode = mode
                    } label: {
                        HStack {
                            Text(mode.displayName)
                            Spacer()
                            if viewportController.displayMode == mode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Section("Options") {
                Toggle("ViewCube", isOn: $viewportController.showViewCube)
                Toggle("Axes", isOn: $viewportController.showAxes)
                Toggle("Grid", isOn: $viewportController.showGrid)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Tools")
    }

    // MARK: - Top Toolbar

    private var topToolbar: some View {
        HStack {
            // View buttons
            HStack(spacing: 4) {
                toolbarButton(icon: "arrow.up.square", tooltip: "Top View") {
                    viewportController.goToStandardView(.top)
                }
                toolbarButton(icon: "arrow.right.square", tooltip: "Front View") {
                    viewportController.goToStandardView(.front)
                }
                toolbarButton(icon: "arrow.right.square.fill", tooltip: "Right View") {
                    viewportController.goToStandardView(.right)
                }
                toolbarButton(icon: "cube", tooltip: "Isometric") {
                    viewportController.goToStandardView(.isometricFrontRight)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Spacer()

            // Display mode
            HStack(spacing: 4) {
                toolbarButton(
                    icon: viewportController.displayMode == .wireframe ? "square" : "cube.fill",
                    tooltip: "Display Mode"
                ) {
                    viewportController.cycleDisplayMode()
                }

                toolbarButton(
                    icon: viewportController.cameraState.isOrthographic ? "square.dashed" : "perspective",
                    tooltip: "Toggle Projection"
                ) {
                    viewportController.toggleProjection()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Spacer()

            // Reset view
            toolbarButton(icon: "arrow.counterclockwise", tooltip: "Reset View") {
                viewportController.reset()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding()
    }

    private func toolbarButton(icon: String, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    // MARK: - Bottom Status Bar

    private var bottomStatusBar: some View {
        HStack {
            // Camera info
            Text(String(format: "Distance: %.1f", viewportController.cameraState.distance))
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            // Projection mode
            Text(viewportController.cameraState.isOrthographic ? "Orthographic" : "Perspective")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            // Display mode
            Text(viewportController.displayMode.displayName)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
    }

    // MARK: - Properties Inspector

    private var propertiesInspector: some View {
        List {
            Section("Camera") {
                LabeledContent("Distance", value: String(format: "%.2f", viewportController.cameraState.distance))
                LabeledContent("FOV", value: String(format: "%.0f°", viewportController.cameraState.fieldOfView))
                LabeledContent("Projection", value: viewportController.cameraState.isOrthographic ? "Ortho" : "Persp")
            }

            Section("Pivot") {
                let pivot = viewportController.cameraState.pivot
                LabeledContent("X", value: String(format: "%.2f", pivot.x))
                LabeledContent("Y", value: String(format: "%.2f", pivot.y))
                LabeledContent("Z", value: String(format: "%.2f", pivot.z))
            }

            Section("Rotation Style") {
                Picker("Style", selection: Binding(
                    get: { viewportController.cameraController.rotationStyle },
                    set: { viewportController.cameraController.rotationStyle = $0 }
                )) {
                    Text("Turntable").tag(RotationStyle.turntable)
                    Text("Arcball").tag(RotationStyle.arcball)
                }
                .pickerStyle(.segmented)
            }
        }
        .inspectorColumnWidth(min: 200, ideal: 250, max: 300)
    }

    // MARK: - Sample Content

    @MainActor
    private func addSampleContent(to content: inout RealityViewContent) async {
        // Create a sample box (representing track/CAD geometry)
        let box = ModelEntity(
            mesh: .generateBox(width: 2, height: 0.2, depth: 5),
            materials: [SimpleMaterial(color: .gray, isMetallic: true)]
        )
        box.position = SIMD3<Float>(0, 0, 0.1)
        content.add(box)

        // Add some cylinders representing rails
        let railMaterial = SimpleMaterial(color: .init(white: 0.5, alpha: 1), isMetallic: true)

        let leftRail = ModelEntity(
            mesh: .generateCylinder(height: 5, radius: 0.05),
            materials: [railMaterial]
        )
        leftRail.position = SIMD3<Float>(-0.5, 0, 0.25)
        leftRail.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
        content.add(leftRail)

        let rightRail = ModelEntity(
            mesh: .generateCylinder(height: 5, radius: 0.05),
            materials: [railMaterial]
        )
        rightRail.position = SIMD3<Float>(0.5, 0, 0.25)
        rightRail.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
        content.add(rightRail)

        // Add sleepers
        let sleeperMaterial = SimpleMaterial(color: .init(red: 0.4, green: 0.3, blue: 0.2, alpha: 1), isMetallic: false)
        for i in stride(from: -2.0, through: 2.0, by: 0.5) {
            let sleeper = ModelEntity(
                mesh: .generateBox(width: 1.5, height: 0.1, depth: 0.15),
                materials: [sleeperMaterial]
            )
            sleeper.position = SIMD3<Float>(0, Float(i), 0.05)
            content.add(sleeper)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct CADSampleView_Previews: PreviewProvider {
    static var previews: some View {
        CADSampleView()
    }
}
#endif
