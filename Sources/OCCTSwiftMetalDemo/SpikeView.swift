// SpikeView.swift
// Test UI for OCCTSwift Metal Demo.

import SwiftUI
import UniformTypeIdentifiers
import simd
import OCCTSwiftViewport

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

    @StateObject private var selectionManager = SelectionManager()

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
        // Edge-only body: a wireframe triangle on the ground plane
        ViewportBody(
            id: "wire-triangle",
            vertexData: [],
            indices: [],
            edges: [
                [
                    SIMD3<Float>(-1.0, 0.0, 2.0),
                    SIMD3<Float>( 1.0, 0.0, 2.0),
                    SIMD3<Float>( 0.0, 0.0, 4.0),
                    SIMD3<Float>(-1.0, 0.0, 2.0),
                ]
            ],
            color: SIMD4<Float>(1.0, 1.0, 0.0, 1.0)
        ),
    ]

    /// CAD metadata for sub-body selection (populated by STEPLoader or procedural primitives).
    @State private var cadMetadata: [String: CADBodyMetadata] = [:]

    /// Whether a STEP file is currently loading.
    @State private var isLoadingSTEP = false

    /// Error message from the last STEP load attempt.
    @State private var loadError: String?

    /// Controls the file importer sheet.
    @State private var showFileImporter = false

    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    @State private var showSettings = false

    var body: some View {
        viewportLayout
        .onAppear {
            // Position primitives so they don't overlap
            offsetBody(id: "box", dx: -2.5, dy: 0.75, dz: 0)
            offsetBody(id: "cylinder", dx: 0, dy: 1.0, dz: 0)
            offsetBody(id: "sphere", dx: 2.5, dy: 0.7, dz: 0)
            // Store original colors for selection highlighting
            for body in bodies {
                originalColors[body.id] = body.color
            }
            // Build procedural metadata for primitive face selection
            buildProceduralMetadata()
        }
        .onChange(of: controller.pickResult) {
            handleSelectionChange()
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: stepContentTypes,
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
    }

    // MARK: - Content Types

    private var stepContentTypes: [UTType] {
        // STEP files use .stp / .step extensions
        let stepType = UTType(filenameExtension: "step") ?? .data
        let stpType = UTType(filenameExtension: "stp") ?? .data
        return [stepType, stpType]
    }

    // MARK: - Layout

    @ViewBuilder
    private var viewportLayout: some View {
        #if os(macOS)
        NavigationSplitView {
            sidebar
        } detail: {
            MetalViewportView(controller: controller, bodies: $bodies)
        }
        #else
        MetalViewportView(controller: controller, bodies: $bodies)
            .overlay(alignment: .topLeading) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.title2)
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .padding(12)
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    sidebar
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showSettings = false }
                            }
                        }
                }
                .presentationDetents([.medium, .large])
            }
        #endif
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List {
            fileSection
            selectionModeSection
            selectionSection
            standardViewsSection
            displayModeSection
            overlaysSection
            projectionSection
            lightingSection
            statusSection
        }
        .navigationTitle("OCCTSwift Metal Demo")
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 200, ideal: 260)
        #endif
    }

    // MARK: - File Section

    private var fileSection: some View {
        Section("File") {
            Button {
                showFileImporter = true
            } label: {
                Label("Open STEP File...", systemImage: "doc.badge.plus")
            }
            .disabled(isLoadingSTEP)

            if isLoadingSTEP {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading...")
                        .foregroundStyle(.secondary)
                }
            }

            if let error = loadError {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
    }

    // MARK: - Selection Mode Section

    private var selectionModeSection: some View {
        Section("Selection Mode") {
            Picker("Mode", selection: $selectionManager.mode) {
                ForEach(SelectionMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue.capitalized).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Selection Section

    private var selectionSection: some View {
        Section("Selection") {
            if let pick = controller.pickResult {
                LabeledContent("Body", value: pick.bodyID)
                LabeledContent("Triangle", value: "\(pick.triangleIndex)")

                if !selectionManager.selectionInfo.isEmpty {
                    Text(selectionManager.selectionInfo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Clear Selection") {
                    controller.clearSelection()
                    selectionManager.clearSelection()
                    removeHighlights()
                    restoreAllColors()
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
            LabeledContent("Bodies", value: "\(bodies.filter { !$0.id.hasPrefix("highlight-") }.count)")
        }
    }

    // MARK: - Selection Handling

    private func handleSelectionChange() {
        // Remove old highlights
        removeHighlights()

        // Restore all body colors
        restoreAllColors()

        guard let result = controller.pickResult else { return }

        // Delegate to SelectionManager for sub-body selection
        selectionManager.handlePick(
            result: result,
            ndc: controller.lastPickNDC,
            bodies: bodies,
            metadata: cadMetadata,
            cameraState: controller.cameraState,
            aspectRatio: controller.lastAspectRatio
        )

        // In body mode, brighten the selected body
        if selectionManager.mode == .body {
            if let idx = bodies.firstIndex(where: { $0.id == result.bodyID }),
               let orig = originalColors[result.bodyID] {
                bodies[idx].color = SIMD4<Float>(
                    min(orig.x + 0.3, 1.0),
                    min(orig.y + 0.3, 1.0),
                    min(orig.z + 0.3, 1.0),
                    orig.w
                )
            }
        }

        // Add highlight overlays
        bodies.append(contentsOf: selectionManager.highlightBodies)
    }

    private func removeHighlights() {
        bodies.removeAll { $0.id.hasPrefix("highlight-") }
    }

    private func restoreAllColors() {
        for i in bodies.indices {
            if let orig = originalColors[bodies[i].id] {
                bodies[i].color = orig
            }
        }
    }

    // MARK: - STEP File Import

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            loadSTEPFile(url)
        case .failure(let error):
            loadError = error.localizedDescription
        }
    }

    private func loadSTEPFile(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            loadError = "Cannot access file: permission denied"
            return
        }

        isLoadingSTEP = true
        loadError = nil

        Task {
            defer {
                url.stopAccessingSecurityScopedResource()
            }

            do {
                let result = try await STEPLoader.load(from: url)

                // Replace bodies with loaded geometry (keep wireframe triangle for testing)
                bodies = result.bodies
                cadMetadata = result.metadata

                // Store original colors
                originalColors = [:]
                for body in bodies {
                    originalColors[body.id] = body.color
                }

                // Focus camera on loaded geometry bounds
                focusOnBounds()

                isLoadingSTEP = false
            } catch {
                loadError = error.localizedDescription
                isLoadingSTEP = false
            }
        }
    }

    private func focusOnBounds() {
        var sceneMin = SIMD3<Float>(repeating: .infinity)
        var sceneMax = SIMD3<Float>(repeating: -.infinity)

        for body in bodies {
            guard let bb = body.boundingBox else { continue }
            sceneMin = simd_min(sceneMin, bb.min)
            sceneMax = simd_max(sceneMax, bb.max)
        }

        guard sceneMin.x < sceneMax.x else { return }

        let center = (sceneMin + sceneMax) * 0.5
        let extent = simd_length(sceneMax - sceneMin)
        let distance = extent * 1.5

        controller.focusOn(point: center, distance: distance, animated: true)
    }

    // MARK: - Procedural Metadata

    /// Builds CADBodyMetadata for procedural primitives so face/edge/vertex
    /// selection works on the default scene before any STEP file is loaded.
    private func buildProceduralMetadata() {
        for body in bodies {
            guard !body.faceIndices.isEmpty || !body.edges.isEmpty else { continue }

            let edgePolylines: [(edgeIndex: Int, points: [SIMD3<Float>])] =
                body.edges.enumerated().map { (idx, polyline) in
                    (edgeIndex: idx, points: polyline)
                }

            let vertices = deduplicateEdgeEndpoints(from: edgePolylines)

            cadMetadata[body.id] = CADBodyMetadata(
                faceIndices: body.faceIndices,
                edgePolylines: edgePolylines,
                vertices: vertices
            )
        }
    }

    private func deduplicateEdgeEndpoints(
        from edgePolylines: [(edgeIndex: Int, points: [SIMD3<Float>])]
    ) -> [SIMD3<Float>] {
        let tolerance: Float = 1e-5
        var unique: [SIMD3<Float>] = []
        for polyline in edgePolylines {
            guard let first = polyline.points.first, let last = polyline.points.last else { continue }
            for endpoint in [first, last] {
                let isDuplicate = unique.contains { existing in
                    simd_distance(existing, endpoint) < tolerance
                }
                if !isDuplicate {
                    unique.append(endpoint)
                }
            }
        }
        return unique
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
