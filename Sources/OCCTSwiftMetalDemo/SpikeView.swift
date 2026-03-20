// SpikeView.swift
// Test UI for OCCTSwift Metal Demo.

import SwiftUI
import UniformTypeIdentifiers
import simd
import OCCTSwift
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

    /// CAD metadata for sub-body selection (populated by CADFileLoader or procedural primitives).
    @State private var cadMetadata: [String: CADBodyMetadata] = [:]

    /// Original OCCTSwift shapes for export, healing, and classification.
    @State private var loadedShapes: [OCCTSwift.Shape] = []

    /// Whether a file is currently loading.
    @State private var isLoadingFile = false

    /// Error message from the last load attempt.
    @State private var loadError: String?

    /// Status message for healing/export operations.
    @State private var operationStatus: String?

    /// Controls the file importer sheet.
    @State private var showFileImporter = false

    /// Controls the export file dialog.
    @State private var showExportDialog = false
    @State private var pendingExportFormat: ExportFormat?

    /// Proximity detection result text.
    @State private var proximityInfo: String?

    /// GD&T data from STEP files.
    @State private var dimensions: [DimensionInfo] = []
    @State private var geomTolerances: [GeomToleranceInfo] = []
    @State private var datums: [DatumInfo] = []

    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    @State private var showSettings = false

    @StateObject private var scriptWatcher = ScriptWatcher()

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
            allowedContentTypes: supportedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .onChange(of: showExportDialog) {
            if showExportDialog, let format = pendingExportFormat {
                showExportDialog = false
                exportShapes(format: format)
            }
        }
    }

    // MARK: - Content Types

    private var supportedContentTypes: [UTType] {
        let stepType = UTType(filenameExtension: "step") ?? .data
        let stpType = UTType(filenameExtension: "stp") ?? .data
        let stlType = UTType(filenameExtension: "stl") ?? .data
        let objType = UTType(filenameExtension: "obj") ?? .data
        let brepType = UTType(filenameExtension: "brep") ?? .data
        let brpType = UTType(filenameExtension: "brp") ?? .data
        return [stepType, stpType, stlType, objType, brepType, brpType]
    }

    // MARK: - Layout

    @ViewBuilder
    private var viewportLayout: some View {
        #if os(macOS)
        NavigationSplitView {
            sidebar
        } detail: {
            MetalViewportView(controller: controller, bodies: $bodies)
                .overlay(alignment: .bottom) { statusOverlay }
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
                .accessibilityIdentifier("settingsButton")
                .padding(12)
            }
            .overlay(alignment: .bottom) { statusOverlay }
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

    @ViewBuilder
    private var statusOverlay: some View {
        if let status = operationStatus {
            Text(status)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding(.bottom, 8)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List {
            DisclosureGroup("File & Tools") {
                fileSection
                exportSection
                healingSection
                analysisSection
                scriptWatcherSection
            }

            DisclosureGroup("Geometry Demos") {
                DisclosureGroup("Curves 2D") {
                    curve2DDemoButtons
                }
                DisclosureGroup("Curves 3D") {
                    curve3DDemoButtons
                }
                DisclosureGroup("Surfaces") {
                    surfaceDemoButtons
                }
                DisclosureGroup("Sweeps") {
                    sweepDemoButtons
                }
                DisclosureGroup("Projections") {
                    projectionDemoButtons
                }
                DisclosureGroup("Plates") {
                    plateDemoButtons
                }
            }

            DisclosureGroup("Modeling Demos") {
                DisclosureGroup("Medial Axis") {
                    medialAxisDemoButtons
                }
                DisclosureGroup("Naming") {
                    namingDemoButtons
                }
                DisclosureGroup("Annotations") {
                    annotationDemoButtons
                }
            }

            DisclosureGroup("OCCT 8 Features") {
                DisclosureGroup("Primitives & Analysis") {
                    occt8PrimitivesButtons
                }
                DisclosureGroup("Modeling Operations") {
                    occt8ModelingButtons
                }
                DisclosureGroup("Advanced Operations") {
                    occt8AdvancedButtons
                }
                DisclosureGroup("Curves & Geometry") {
                    occt8CurvesButtons
                }
                DisclosureGroup("Transforms & OCAF") {
                    occt8TransformsButtons
                }
                DisclosureGroup("I/O & Assembly") {
                    occt8IOButtons
                }
            }

            gdtSection

            DisclosureGroup("Viewport") {
                selectionModeSection
                selectionSection
                standardViewsSection
                displayModeSection
                overlaysSection
                projectionSection
                lightingSection
                shadowSection
                dofSection
                taaSection
            }

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
                // On iOS, dismiss the settings sheet first so the file
                // importer can present without conflicting sheets.
                showSettings = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    showFileImporter = true
                }
            } label: {
                Label("Open File (STEP/STL/OBJ/BREP)...", systemImage: "doc.badge.plus")
            }
            .disabled(isLoadingFile)

            if isLoadingFile {
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

            if let status = operationStatus {
                Text(status)
                    .foregroundStyle(.green)
                    .font(.caption)
            }
        }
    }

    // MARK: - Export Section

    private var exportSection: some View {
        Section("Export") {
            Button("Export as OBJ...") {
                pendingExportFormat = .obj
                showExportDialog = true
            }
            Button("Export as PLY...") {
                pendingExportFormat = .ply
                showExportDialog = true
            }
            Button("Export as STEP...") {
                pendingExportFormat = .step
                showExportDialog = true
            }
            Button("Export as BREP...") {
                pendingExportFormat = .brep
                showExportDialog = true
            }
        }
        .disabled(loadedShapes.isEmpty)
    }

    // MARK: - Script Watcher Section

    private var scriptWatcherSection: some View {
        Section("Script Watcher") {
            Toggle("Watch Scripts", isOn: $scriptWatcher.isWatching)

            if scriptWatcher.isWatching {
                Button("Reload") {
                    scriptWatcher.reload()
                }

                // Metadata display
                if let meta = scriptWatcher.manifestMetadata {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(meta.name)
                            .font(.caption.bold())
                        if let rev = meta.revision {
                            Text("Rev \(rev)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let source = meta.source {
                            Text(source)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let tags = meta.tags, !tags.isEmpty {
                            Text(tags.joined(separator: ", "))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 2)
                }

                if !scriptWatcher.scriptBodies.isEmpty {
                    Text("\(scriptWatcher.scriptBodies.count) bodies loaded")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                if let time = scriptWatcher.lastLoadTime {
                    Text("Last: \(time.formatted(.dateTime.hour().minute().second()))")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                if let error = scriptWatcher.lastError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            // Gallery of available scripts
            if !scriptWatcher.availableScripts.isEmpty {
                ForEach(scriptWatcher.availableScripts) { entry in
                    Button {
                        scriptWatcher.loadScript(entry)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.name)
                                    .font(.caption)
                                Text("\(entry.bodyCount) bodies · \(entry.timestamp.formatted(.dateTime.month().day().hour().minute()))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "cube")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .onChange(of: scriptWatcher.lastLoadTime) {
            guard !scriptWatcher.scriptBodies.isEmpty else { return }
            // Replace only script-prefixed bodies, keep others
            bodies.removeAll { $0.id.hasPrefix("script-") }
            bodies.append(contentsOf: scriptWatcher.scriptBodies)
            // Update shapes
            loadedShapes = scriptWatcher.scriptShapes
            // Update original colors
            for body in scriptWatcher.scriptBodies {
                originalColors[body.id] = body.color
            }
            focusOnBounds()
        }
    }

    // MARK: - Healing Section

    private var healingSection: some View {
        Section("Healing") {
            Button("Sew Faces") { applyHealing(.sew) }
            Button("Upgrade (Full Pipeline)") { applyHealing(.upgrade) }
            Button("Direct Faces") { applyHealing(.directFaces) }
            Button("Convert to BSpline") { applyHealing(.toBSpline) }
        }
        .disabled(loadedShapes.isEmpty)
    }

    // MARK: - Analysis Section

    private var analysisSection: some View {
        Section("Analysis") {
            Toggle("Curvature Overlays", isOn: $selectionManager.showCurvatureOverlays)

            Button("Check Proximity") {
                let result = selectionManager.checkProximity(
                    shapes: loadedShapes,
                    bodies: bodies,
                    metadata: cadMetadata
                )
                proximityInfo = result.info
                removeHighlights()
                bodies.append(contentsOf: result.bodies)
            }
            .disabled(loadedShapes.count < 2)

            if let info = proximityInfo {
                Text(info)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Curve2D Demo Section

    private enum Curve2DDemo {
        case showcase, intersections, hatching, gcc
    }

    @ViewBuilder
    private var curve2DDemoButtons: some View {
        Button("Curve Showcase") { loadCurve2DDemo(.showcase) }
        Button("Intersections") { loadCurve2DDemo(.intersections) }
        Button("Hatching") { loadCurve2DDemo(.hatching) }
        Button("Tangent Circles") { loadCurve2DDemo(.gcc) }
    }

    // MARK: - Curve3D Demo Section

    private enum Curve3DDemo {
        case showcase, helixAndSpirals, curvatureCombs, bsplineFitting
    }

    @ViewBuilder
    private var curve3DDemoButtons: some View {
        Button("3D Curve Showcase") { loadCurve3DDemo(.showcase) }
        Button("Helix & Spirals") { loadCurve3DDemo(.helixAndSpirals) }
        Button("Curvature Combs") { loadCurve3DDemo(.curvatureCombs) }
        Button("BSpline Fitting") { loadCurve3DDemo(.bsplineFitting) }
    }

    private func loadCurve3DDemo(_ demo: Curve3DDemo) {
        let result: Curve2DGallery.GalleryResult
        switch demo {
        case .showcase:
            result = Curve3DGallery.curveShowcase()
        case .helixAndSpirals:
            result = Curve3DGallery.helixAndSpirals()
        case .curvatureCombs:
            result = Curve3DGallery.curvatureCombs()
        case .bsplineFitting:
            result = Curve3DGallery.bsplineFitting()
        }

        bodies = result.bodies
        cadMetadata = [:]
        loadedShapes = []
        originalColors = [:]
        for body in bodies {
            originalColors[body.id] = body.color
        }
        selectionManager.clearSelection()
        controller.clearSelection()
        operationStatus = nil
        proximityInfo = nil
        focusOnBounds()
        // Use isometric view for 3D curves (not top-down)
        controller.goToStandardView(.isometricFrontRight)
    }

    // MARK: - Sweep Demo Section

    private enum SweepDemo {
        case constant, linearTaper, sCurve, interpolated
    }

    @ViewBuilder
    private var sweepDemoButtons: some View {
        Button("Constant Pipe") { loadSweepDemo(.constant) }
        Button("Linear Taper") { loadSweepDemo(.linearTaper) }
        Button("S-Curve Sweep") { loadSweepDemo(.sCurve) }
        Button("Interpolated Sweep") { loadSweepDemo(.interpolated) }
    }

    private func loadSweepDemo(_ demo: SweepDemo) {
        let result: Curve2DGallery.GalleryResult
        switch demo {
        case .constant:
            result = SweepGallery.constantPipe()
        case .linearTaper:
            result = SweepGallery.linearTaper()
        case .sCurve:
            result = SweepGallery.sCurveSweep()
        case .interpolated:
            result = SweepGallery.interpolatedSweep()
        }

        bodies = result.bodies
        cadMetadata = [:]
        loadedShapes = []
        originalColors = [:]
        for body in bodies {
            originalColors[body.id] = body.color
        }
        selectionManager.clearSelection()
        controller.clearSelection()
        operationStatus = nil
        proximityInfo = nil
        focusOnBounds()
        controller.goToStandardView(.isometricFrontRight)
    }

    // MARK: - Medial Axis Demo Section

    private enum MedialAxisDemo {
        case rectangle, lShape, thicknessMap, customProfile
    }

    @ViewBuilder
    private var medialAxisDemoButtons: some View {
        Button("Rectangle Skeleton") { loadMedialAxisDemo(.rectangle) }
        Button("L-Shape Skeleton") { loadMedialAxisDemo(.lShape) }
        Button("Thickness Map") { loadMedialAxisDemo(.thicknessMap) }
        Button("Custom Profile") { loadMedialAxisDemo(.customProfile) }
    }

    private func loadMedialAxisDemo(_ demo: MedialAxisDemo) {
        let result: Curve2DGallery.GalleryResult
        switch demo {
        case .rectangle:
            result = MedialAxisGallery.rectangleSkeleton()
        case .lShape:
            result = MedialAxisGallery.lShapeSkeleton()
        case .thicknessMap:
            result = MedialAxisGallery.thicknessMap()
        case .customProfile:
            result = MedialAxisGallery.customProfileSkeleton()
        }

        bodies = result.bodies
        cadMetadata = [:]
        loadedShapes = []
        originalColors = [:]
        for body in bodies {
            originalColors[body.id] = body.color
        }
        selectionManager.clearSelection()
        controller.clearSelection()
        operationStatus = result.description
        proximityInfo = nil
        focusOnBounds()
        controller.goToStandardView(.top)
    }

    // MARK: - Naming Demo Section

    private enum NamingDemo {
        case primitive, modification, tracing, selection
    }

    @ViewBuilder
    private var namingDemoButtons: some View {
        Button("Primitive History") { loadNamingDemo(.primitive) }
        Button("Modification Tracking") { loadNamingDemo(.modification) }
        Button("Forward/Backward Trace") { loadNamingDemo(.tracing) }
        Button("Named Selection") { loadNamingDemo(.selection) }
    }

    private func loadNamingDemo(_ demo: NamingDemo) {
        let result: Curve2DGallery.GalleryResult
        switch demo {
        case .primitive:
            result = NamingGallery.primitiveHistory()
        case .modification:
            result = NamingGallery.modificationTracking()
        case .tracing:
            result = NamingGallery.forwardBackwardTrace()
        case .selection:
            result = NamingGallery.namedSelection()
        }

        bodies = result.bodies
        cadMetadata = [:]
        loadedShapes = []
        originalColors = [:]
        for body in bodies {
            originalColors[body.id] = body.color
        }
        selectionManager.clearSelection()
        controller.clearSelection()
        operationStatus = result.description
        proximityInfo = nil
        focusOnBounds()
        controller.goToStandardView(.isometricFrontRight)
    }

    // MARK: - Annotation Demo Section

    private enum AnnotationDemo {
        case length, radial, angle, labelsAndCloud
    }

    @ViewBuilder
    private var annotationDemoButtons: some View {
        Button("Length Dimensions") { loadAnnotationDemo(.length) }
        Button("Radius & Diameter") { loadAnnotationDemo(.radial) }
        Button("Angle Dimensions") { loadAnnotationDemo(.angle) }
        Button("Labels & Point Cloud") { loadAnnotationDemo(.labelsAndCloud) }
    }

    private func loadAnnotationDemo(_ demo: AnnotationDemo) {
        let result: Curve2DGallery.GalleryResult
        switch demo {
        case .length:
            result = AnnotationGallery.lengthDimensions()
        case .radial:
            result = AnnotationGallery.radialDimensions()
        case .angle:
            result = AnnotationGallery.angleDimensions()
        case .labelsAndCloud:
            result = AnnotationGallery.labelsAndPointCloud()
        }

        bodies = result.bodies
        cadMetadata = [:]
        loadedShapes = []
        originalColors = [:]
        for body in bodies {
            originalColors[body.id] = body.color
        }
        selectionManager.clearSelection()
        controller.clearSelection()
        operationStatus = result.description
        proximityInfo = nil
        focusOnBounds()
        controller.goToStandardView(.isometricFrontRight)
    }

    // MARK: - OCCT 8 Demo Section

    private enum OCCT8Demo {
        case helixCurves, kdTree, wedges, hatchPatterns, shapeOps, polynomials
        case transformOps, shapeAnalysis, intersections, volumeOps
        case quasiUniform, bezierFill, revolution, linearRib
        case asymmetricChamfer, loftAdvanced, offsetByJoin, featureOps
        case pipeTransitions, faceFromSurface
        case sectionAndValidation, shapeRepair, multiFuse, splitFaceByWire
        case projectionAndOffset, faceDivision, hollowAndAnalysis
        case orientedBoundingBox, fuseAndBlend, variableOffset
        case freeBoundsAndFeatures, inertiaAndDistance, surgeryAndDetection
        case solidAnd2DFillets, bsplineFillAndSubdivision
        case extremaAndArcs
        case fillingAndSelfIntersection, concavityAndInertia
        case localOpsAndValidation, splitOpsAndExtrema
        case extremaAndCurveAnalysis
        case conicsAndPolyDistance
        case transformsAndTopology
        case brepFillAndHealing
        case geometry2DCompletions
        case ocafFramework
        case ocafPersistenceAndSTEP
        case fileIOFormats
        case xdeAssembly
        case splitAndContours
        case pointCloudAndRays
        case curvatureAndIntersection
        case trihedronsAndFilling
        case featBooleansAndContours
        case tkG2dToolkit
        case fairCurveAndAnalysis
        case curveTransAndGeomFill
        case plateAndGeomFill
        case tkBoolIntersection
        case tkFeatOps
        case tkFilletOps
        case tkHlrOps
        case meshAndValidation
        case blendAndSampling
        case geomEntitiesAndBisector
        case gccAnaSolvers
        case shapeModifiersAndPolygons
        case evolvedAndMeshOps
        case extremaAndFactories
        case colorAndMaterial
        case dateAndPixMap
        case xcafDocAttributes
        case vrmlAndDocAttributes
        case unitsAndBinaryIO
        case extendedAttributesAndShapeFix
    }

    // MARK: - OCCT 8 Sub-groups

    @ViewBuilder
    private var occt8PrimitivesButtons: some View {
        Button("Helix Curves") { loadOCCT8Demo(.helixCurves) }
        Button("KD-Tree Queries") { loadOCCT8Demo(.kdTree) }
        Button("Wedge Primitives") { loadOCCT8Demo(.wedges) }
        Button("Hatch Patterns") { loadOCCT8Demo(.hatchPatterns) }
        Button("Shape Operations") { loadOCCT8Demo(.shapeOps) }
        Button("Polynomial Roots") { loadOCCT8Demo(.polynomials) }
        Button("Transforms & Offset") { loadOCCT8Demo(.transformOps) }
        Button("Shape Analysis") { loadOCCT8Demo(.shapeAnalysis) }
        Button("Intersection Analysis") { loadOCCT8Demo(.intersections) }
        Button("Volume & Connected") { loadOCCT8Demo(.volumeOps) }
        Button("Curve Sampling") { loadOCCT8Demo(.quasiUniform) }
        Button("Bezier Surface Fill") { loadOCCT8Demo(.bezierFill) }
    }

    @ViewBuilder
    private var occt8ModelingButtons: some View {
        Button("Revolution from Curve") { loadOCCT8Demo(.revolution) }
        Button("Linear Rib") { loadOCCT8Demo(.linearRib) }
        Button("Asymmetric Chamfer") { loadOCCT8Demo(.asymmetricChamfer) }
        Button("Loft Advanced") { loadOCCT8Demo(.loftAdvanced) }
        Button("Offset by Join") { loadOCCT8Demo(.offsetByJoin) }
        Button("Feature Ops") { loadOCCT8Demo(.featureOps) }
        Button("Pipe Transitions") { loadOCCT8Demo(.pipeTransitions) }
        Button("Face from Surface") { loadOCCT8Demo(.faceFromSurface) }
        Button("Section & Validation") { loadOCCT8Demo(.sectionAndValidation) }
        Button("Shape Repair") { loadOCCT8Demo(.shapeRepair) }
        Button("Multi-Fuse") { loadOCCT8Demo(.multiFuse) }
        Button("Split Face by Wire") { loadOCCT8Demo(.splitFaceByWire) }
    }

    @ViewBuilder
    private var occt8AdvancedButtons: some View {
        Button("Projection & Offset") { loadOCCT8Demo(.projectionAndOffset) }
        Button("Face Division") { loadOCCT8Demo(.faceDivision) }
        Button("Hollow & Analysis") { loadOCCT8Demo(.hollowAndAnalysis) }
        Button("Oriented Bounding Box") { loadOCCT8Demo(.orientedBoundingBox) }
        Button("Fuse & Blend") { loadOCCT8Demo(.fuseAndBlend) }
        Button("Variable Offset") { loadOCCT8Demo(.variableOffset) }
        Button("Free Bounds & Features") { loadOCCT8Demo(.freeBoundsAndFeatures) }
        Button("Inertia & Distance") { loadOCCT8Demo(.inertiaAndDistance) }
        Button("Surgery & Detection") { loadOCCT8Demo(.surgeryAndDetection) }
        Button("Solid & 2D Fillets") { loadOCCT8Demo(.solidAnd2DFillets) }
        Button("BSpline Fill & Subdivision") { loadOCCT8Demo(.bsplineFillAndSubdivision) }
        Button("Extrema & Arcs") { loadOCCT8Demo(.extremaAndArcs) }
    }

    @ViewBuilder
    private var occt8CurvesButtons: some View {
        Button("Filling & Self-Intersection") { loadOCCT8Demo(.fillingAndSelfIntersection) }
        Button("Concavity & Inertia") { loadOCCT8Demo(.concavityAndInertia) }
        Button("Local Ops & Validation") { loadOCCT8Demo(.localOpsAndValidation) }
        Button("Split Ops & Extrema") { loadOCCT8Demo(.splitOpsAndExtrema) }
        Button("Extrema & Curve Analysis") { loadOCCT8Demo(.extremaAndCurveAnalysis) }
        Button("Conics & Poly Distance") { loadOCCT8Demo(.conicsAndPolyDistance) }
    }

    @ViewBuilder
    private var occt8TransformsButtons: some View {
        Button("Transforms & Topology") { loadOCCT8Demo(.transformsAndTopology) }
        Button("BRepFill & Healing") { loadOCCT8Demo(.brepFillAndHealing) }
        Button("2D Geometry Suite") { loadOCCT8Demo(.geometry2DCompletions) }
        Button("OCAF Framework") { loadOCCT8Demo(.ocafFramework) }
        Button("OCAF Persistence & STEP") { loadOCCT8Demo(.ocafPersistenceAndSTEP) }
    }

    @ViewBuilder
    private var occt8IOButtons: some View {
        Button("File I/O Formats") { loadOCCT8Demo(.fileIOFormats) }
        Button("XDE Assembly") { loadOCCT8Demo(.xdeAssembly) }
        Button("Split & Contours") { loadOCCT8Demo(.splitAndContours) }
        Button("Point Cloud & Rays") { loadOCCT8Demo(.pointCloudAndRays) }
        Button("Curvature & Intersection") { loadOCCT8Demo(.curvatureAndIntersection) }
        Button("Trihedrons & Filling") { loadOCCT8Demo(.trihedronsAndFilling) }
        Button("Feat Booleans & Contours") { loadOCCT8Demo(.featBooleansAndContours) }
        Button("TkG2d Toolkit") { loadOCCT8Demo(.tkG2dToolkit) }
        Button("FairCurve & Analysis") { loadOCCT8Demo(.fairCurveAndAnalysis) }
        Button("CurveTrans & GeomFill") { loadOCCT8Demo(.curveTransAndGeomFill) }
        Button("Plate & GeomFill") { loadOCCT8Demo(.plateAndGeomFill) }
        Button("TKBool Intersection") { loadOCCT8Demo(.tkBoolIntersection) }
        Button("TKFeat Operations") { loadOCCT8Demo(.tkFeatOps) }
        Button("TKFillet Operations") { loadOCCT8Demo(.tkFilletOps) }
        Button("HLR & Reflect Lines") { loadOCCT8Demo(.tkHlrOps) }
        Button("Mesh & Validation") { loadOCCT8Demo(.meshAndValidation) }
        Button("Blend & Sampling") { loadOCCT8Demo(.blendAndSampling) }
        Button("Geom Entities & Bisector") { loadOCCT8Demo(.geomEntitiesAndBisector) }
        Button("GccAna Solvers") { loadOCCT8Demo(.gccAnaSolvers) }
        Button("Modifiers & Polygons") { loadOCCT8Demo(.shapeModifiersAndPolygons) }
        Button("Evolved & Mesh Ops") { loadOCCT8Demo(.evolvedAndMeshOps) }
        Button("Extrema & Factories") { loadOCCT8Demo(.extremaAndFactories) }
        Button("Color & Material") { loadOCCT8Demo(.colorAndMaterial) }
        Button("Date & PixMap") { loadOCCT8Demo(.dateAndPixMap) }
        Button("XCAF Attributes") { loadOCCT8Demo(.xcafDocAttributes) }
        Button("VRML & Doc Attributes") { loadOCCT8Demo(.vrmlAndDocAttributes) }
        Button("Units & Binary I/O") { loadOCCT8Demo(.unitsAndBinaryIO) }
        Button("Ext Attributes & Fix") { loadOCCT8Demo(.extendedAttributesAndShapeFix) }
    }

    private func loadOCCT8Demo(_ demo: OCCT8Demo) {
        let result: Curve2DGallery.GalleryResult
        var useTopView = false

        switch demo {
        case .helixCurves:
            result = OCCT8Gallery.helixCurves()
        case .kdTree:
            result = OCCT8Gallery.kdTreeQueries()
        case .wedges:
            result = OCCT8Gallery.wedgePrimitives()
        case .hatchPatterns:
            result = OCCT8Gallery.hatchPatterns()
            useTopView = true
        case .shapeOps:
            result = OCCT8Gallery.shapeOperations()
        case .polynomials:
            result = OCCT8Gallery.polynomialRoots()
            useTopView = true
        case .transformOps:
            result = OCCT8Gallery.transformOps()
        case .shapeAnalysis:
            result = OCCT8Gallery.shapeAnalysis()
        case .intersections:
            result = OCCT8Gallery.intersectionAnalysis()
        case .volumeOps:
            result = OCCT8Gallery.volumeOps()
        case .quasiUniform:
            result = OCCT8Gallery.quasiUniformSampling()
        case .bezierFill:
            result = OCCT8Gallery.bezierSurfaceFill()
        case .revolution:
            result = OCCT8Gallery.revolutionDemo()
        case .linearRib:
            result = OCCT8Gallery.linearRibDemo()
        case .asymmetricChamfer:
            result = OCCT8Gallery.asymmetricChamfer()
        case .loftAdvanced:
            result = OCCT8Gallery.loftAdvanced()
        case .offsetByJoin:
            result = OCCT8Gallery.offsetByJoin()
        case .featureOps:
            result = OCCT8Gallery.featureOps()
        case .pipeTransitions:
            result = OCCT8Gallery.pipeTransitions()
        case .faceFromSurface:
            result = OCCT8Gallery.faceFromSurface()
        case .sectionAndValidation:
            result = OCCT8Gallery.sectionAndValidation()
        case .shapeRepair:
            result = OCCT8Gallery.shapeRepair()
        case .multiFuse:
            result = OCCT8Gallery.multiFuse()
        case .splitFaceByWire:
            result = OCCT8Gallery.splitFaceByWire()
        case .projectionAndOffset:
            result = OCCT8Gallery.projectionAndOffset()
        case .faceDivision:
            result = OCCT8Gallery.faceDivision()
        case .hollowAndAnalysis:
            result = OCCT8Gallery.hollowAndAnalysis()
        case .orientedBoundingBox:
            result = OCCT8Gallery.orientedBoundingBox()
        case .fuseAndBlend:
            result = OCCT8Gallery.fuseAndBlend()
        case .variableOffset:
            result = OCCT8Gallery.variableOffset()
        case .freeBoundsAndFeatures:
            result = OCCT8Gallery.freeBoundsAndFeatures()
        case .inertiaAndDistance:
            result = OCCT8Gallery.inertiaAndDistance()
        case .surgeryAndDetection:
            result = OCCT8Gallery.surgeryAndDetection()
        case .solidAnd2DFillets:
            result = OCCT8Gallery.solidAnd2DFillets()
        case .bsplineFillAndSubdivision:
            result = OCCT8Gallery.bsplineFillAndSubdivision()
        case .extremaAndArcs:
            result = OCCT8Gallery.extremaAndArcs()
        case .fillingAndSelfIntersection:
            result = OCCT8Gallery.fillingAndSelfIntersection()
        case .concavityAndInertia:
            result = OCCT8Gallery.concavityAndInertia()
        case .localOpsAndValidation:
            result = OCCT8Gallery.localOpsAndValidation()
        case .splitOpsAndExtrema:
            result = OCCT8Gallery.splitOpsAndExtrema()
        case .extremaAndCurveAnalysis:
            result = OCCT8Gallery.extremaAndCurveAnalysis()
        case .conicsAndPolyDistance:
            result = OCCT8Gallery.conicsAndPolyDistance()
        case .transformsAndTopology:
            result = OCCT8Gallery.transformsAndTopology()
        case .brepFillAndHealing:
            result = OCCT8Gallery.brepFillAndHealing()
        case .geometry2DCompletions:
            result = OCCT8Gallery.geometry2DCompletions()
        case .ocafFramework:
            result = OCCT8Gallery.ocafFramework()
        case .ocafPersistenceAndSTEP:
            result = OCCT8Gallery.ocafPersistenceAndSTEP()
        case .fileIOFormats:
            result = OCCT8Gallery.fileIOFormats()
        case .xdeAssembly:
            result = OCCT8Gallery.xdeAssembly()
        case .splitAndContours:
            result = OCCT8Gallery.splitAndContours()
        case .pointCloudAndRays:
            result = OCCT8Gallery.pointCloudAndRays()
        case .curvatureAndIntersection:
            result = OCCT8Gallery.curvatureAndIntersection()
        case .trihedronsAndFilling:
            result = OCCT8Gallery.trihedronsAndFilling()
        case .featBooleansAndContours:
            result = OCCT8Gallery.featBooleansAndContours()
        case .tkG2dToolkit:
            result = OCCT8Gallery.tkG2dToolkit()
            useTopView = true
        case .fairCurveAndAnalysis:
            result = OCCT8Gallery.fairCurveAndAnalysis()
        case .curveTransAndGeomFill:
            result = OCCT8Gallery.curveTransAndGeomFill()
        case .plateAndGeomFill:
            result = OCCT8Gallery.plateAndGeomFill()
        case .tkBoolIntersection:
            result = OCCT8Gallery.tkBoolIntersection()
        case .tkFeatOps:
            result = OCCT8Gallery.tkFeatOps()
        case .tkFilletOps:
            result = OCCT8Gallery.tkFilletOps()
        case .tkHlrOps:
            result = OCCT8Gallery.tkHlrOps()
        case .meshAndValidation:
            result = OCCT8Gallery.meshAndValidation()
        case .blendAndSampling:
            result = OCCT8Gallery.blendAndSampling()
        case .geomEntitiesAndBisector:
            result = OCCT8Gallery.geomEntitiesAndBisector()
        case .gccAnaSolvers:
            result = OCCT8Gallery.gccAnaSolvers()
        case .shapeModifiersAndPolygons:
            result = OCCT8Gallery.shapeModifiersAndPolygons()
        case .evolvedAndMeshOps:
            result = OCCT8Gallery.evolvedAndMeshOps()
        case .extremaAndFactories:
            result = OCCT8Gallery.extremaAndFactories()
        case .colorAndMaterial:
            result = OCCT8Gallery.colorAndMaterial()
        case .dateAndPixMap:
            result = OCCT8Gallery.dateAndPixMap()
        case .xcafDocAttributes:
            result = OCCT8Gallery.xcafDocAttributes()
        case .vrmlAndDocAttributes:
            result = OCCT8Gallery.vrmlAndDocAttributes()
        case .unitsAndBinaryIO:
            result = OCCT8Gallery.unitsAndBinaryIO()
        case .extendedAttributesAndShapeFix:
            result = OCCT8Gallery.extendedAttributesAndShapeFix()
        }

        bodies = result.bodies
        cadMetadata = [:]
        loadedShapes = []
        originalColors = [:]
        for body in bodies {
            originalColors[body.id] = body.color
        }
        selectionManager.clearSelection()
        controller.clearSelection()
        operationStatus = result.description
        proximityInfo = nil
        focusOnBounds()
        controller.goToStandardView(useTopView ? .top : .isometricFrontRight)
    }

    // MARK: - Projection Demo Section

    private enum ProjectionDemo {
        case curveOnCylinder, curveOnSphere, composite, pointProjection
    }

    @ViewBuilder
    private var projectionDemoButtons: some View {
        Button("Curve on Cylinder") { loadProjectionDemo(.curveOnCylinder) }
        Button("Curve on Sphere") { loadProjectionDemo(.curveOnSphere) }
        Button("Composite Projection") { loadProjectionDemo(.composite) }
        Button("Point Projection") { loadProjectionDemo(.pointProjection) }
    }

    private func loadProjectionDemo(_ demo: ProjectionDemo) {
        let result: Curve2DGallery.GalleryResult
        switch demo {
        case .curveOnCylinder:
            result = ProjectionGallery.curveOnCylinder()
        case .curveOnSphere:
            result = ProjectionGallery.curveOnSphere()
        case .composite:
            result = ProjectionGallery.compositeProjection()
        case .pointProjection:
            result = ProjectionGallery.pointProjection()
        }

        bodies = result.bodies
        cadMetadata = [:]
        loadedShapes = []
        originalColors = [:]
        for body in bodies {
            originalColors[body.id] = body.color
        }
        selectionManager.clearSelection()
        controller.clearSelection()
        operationStatus = nil
        proximityInfo = nil
        focusOnBounds()
        controller.goToStandardView(.isometricFrontRight)
    }

    // MARK: - Plate Demo Section

    private enum PlateDemo {
        case fromPoints, deformed, tangent
    }

    @ViewBuilder
    private var plateDemoButtons: some View {
        Button("Plate from Points") { loadPlateDemo(.fromPoints) }
        Button("Deformed Plate (G0)") { loadPlateDemo(.deformed) }
        Button("Tangent Deformation (G1)") { loadPlateDemo(.tangent) }
    }

    private func loadPlateDemo(_ demo: PlateDemo) {
        let result: Curve2DGallery.GalleryResult
        switch demo {
        case .fromPoints:
            result = PlateGallery.plateFromPoints()
        case .deformed:
            result = PlateGallery.deformedPlate()
        case .tangent:
            result = PlateGallery.tangentDeformation()
        }

        bodies = result.bodies
        cadMetadata = [:]
        loadedShapes = []
        originalColors = [:]
        for body in bodies {
            originalColors[body.id] = body.color
        }
        selectionManager.clearSelection()
        controller.clearSelection()
        operationStatus = nil
        proximityInfo = nil
        focusOnBounds()
        controller.goToStandardView(.isometricFrontRight)
    }

    // MARK: - GD&T Section

    private var gdtSection: some View {
        Section("GD&T") {
            if dimensions.isEmpty && geomTolerances.isEmpty && datums.isEmpty {
                Text("No GD&T data (load STEP with PMI)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            if !dimensions.isEmpty {
                ForEach(Array(dimensions.enumerated()), id: \.offset) { i, dim in
                    LabeledContent("Dim \(i)",
                                   value: String(format: "%.3f [%.3f, +%.3f]",
                                                 dim.value, dim.lowerTolerance, dim.upperTolerance))
                }
            }

            if !geomTolerances.isEmpty {
                ForEach(Array(geomTolerances.enumerated()), id: \.offset) { i, tol in
                    LabeledContent("Tol \(i)",
                                   value: String(format: "%.4f (type %d)", tol.value, tol.type))
                }
            }

            if !datums.isEmpty {
                ForEach(Array(datums.enumerated()), id: \.offset) { i, datum in
                    LabeledContent("Datum \(i)", value: datum.name)
                }
            }
        }
    }

    // MARK: - Surface Demo Section

    private enum SurfaceDemo {
        case analytic, swept, freeform, pipe, isoCurves
    }

    @ViewBuilder
    private var surfaceDemoButtons: some View {
        Button("Analytic Surfaces") { loadSurfaceDemo(.analytic) }
        Button("Swept Surfaces") { loadSurfaceDemo(.swept) }
        Button("Freeform Surfaces") { loadSurfaceDemo(.freeform) }
        Button("Pipe Surfaces") { loadSurfaceDemo(.pipe) }
        Button("Iso Curves") { loadSurfaceDemo(.isoCurves) }
    }

    private func loadSurfaceDemo(_ demo: SurfaceDemo) {
        let result: Curve2DGallery.GalleryResult
        switch demo {
        case .analytic:
            result = SurfaceGallery.analyticSurfaces()
        case .swept:
            result = SurfaceGallery.sweptSurfaces()
        case .freeform:
            result = SurfaceGallery.freeformSurfaces()
        case .pipe:
            result = SurfaceGallery.pipeSurfaces()
        case .isoCurves:
            result = SurfaceGallery.isoCurves()
        }

        bodies = result.bodies
        cadMetadata = [:]
        loadedShapes = []
        originalColors = [:]
        for body in bodies {
            originalColors[body.id] = body.color
        }
        selectionManager.clearSelection()
        controller.clearSelection()
        operationStatus = nil
        proximityInfo = nil
        focusOnBounds()
        controller.goToStandardView(.isometricFrontRight)
    }

    private func loadCurve2DDemo(_ demo: Curve2DDemo) {
        let result: Curve2DGallery.GalleryResult
        switch demo {
        case .showcase:
            result = Curve2DGallery.curveShowcase()
        case .intersections:
            result = Curve2DGallery.intersectionDemo()
        case .hatching:
            result = Curve2DGallery.hatchingDemo()
        case .gcc:
            result = Curve2DGallery.gccDemo()
        }

        bodies = result.bodies
        cadMetadata = [:]
        loadedShapes = []
        originalColors = [:]
        for body in bodies {
            originalColors[body.id] = body.color
        }
        selectionManager.clearSelection()
        controller.clearSelection()
        operationStatus = nil
        proximityInfo = nil

        // Focus camera and switch to top-down view for 2D curves
        focusOnBounds()
        controller.goToStandardView(.top)
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
            Button("Fit All") { focusOnBounds(); controller.goToStandardView(.isometricFrontRight) }
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

            VStack(alignment: .leading) {
                Text("Edge Intensity: \(controller.edgeIntensity, specifier: "%.1f")")
                Slider(value: $controller.edgeIntensity, in: 0.5...10.0)
            }
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
            VStack(alignment: .leading) {
                Text("Exposure: \(controller.lightingConfiguration.exposure, specifier: "%.2f")")
                Slider(value: $controller.lightingConfiguration.exposure, in: 0.5...3.0)
            }
            VStack(alignment: .leading) {
                Text("White Point: \(controller.lightingConfiguration.whitePoint, specifier: "%.2f")")
                Slider(value: $controller.lightingConfiguration.whitePoint, in: 0.5...2.0)
            }
        }
    }

    private var shadowSection: some View {
        Section("Shadows") {
            Toggle("Shadows", isOn: $controller.lightingConfiguration.shadowsEnabled)
            if controller.lightingConfiguration.shadowsEnabled {
                VStack(alignment: .leading) {
                    Text("Shadow Intensity: \(controller.lightingConfiguration.shadowIntensity, specifier: "%.2f")")
                    Slider(value: $controller.lightingConfiguration.shadowIntensity, in: 0...1)
                }
                VStack(alignment: .leading) {
                    Text("PCSS Light Size: \(controller.lightingConfiguration.shadowLightSize, specifier: "%.3f")")
                    Slider(value: $controller.lightingConfiguration.shadowLightSize, in: 0...0.1)
                }
                VStack(alignment: .leading) {
                    Text("PCSS Search Radius: \(controller.lightingConfiguration.shadowSearchRadius, specifier: "%.3f")")
                    Slider(value: $controller.lightingConfiguration.shadowSearchRadius, in: 0...0.05)
                }
            }
        }
    }

    private var dofSection: some View {
        Section("Depth of Field") {
            Toggle("Enable DoF", isOn: $controller.enableDepthOfField)
            if controller.enableDepthOfField {
                VStack(alignment: .leading) {
                    Text("Aperture: \(controller.dofAperture, specifier: "%.1f")")
                    Slider(value: $controller.dofAperture, in: 0.5...16.0)
                }
                VStack(alignment: .leading) {
                    Text("Focal Distance: \(controller.dofFocalDistance, specifier: "%.1f") (0 = auto)")
                    Slider(value: $controller.dofFocalDistance, in: 0...100.0)
                }
                VStack(alignment: .leading) {
                    Text("Max Blur: \(controller.dofMaxBlurRadius, specifier: "%.1f")")
                    Slider(value: $controller.dofMaxBlurRadius, in: 1...20)
                }
            }
        }
    }

    private var taaSection: some View {
        Section("Anti-Aliasing") {
            Toggle("Temporal AA (TAA)", isOn: $controller.enableTAA)
            if controller.enableTAA {
                VStack(alignment: .leading) {
                    Text("Blend Factor: \(controller.taaBlendFactor, specifier: "%.2f")")
                    Slider(value: $controller.taaBlendFactor, in: 0.5...0.98)
                }
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
            aspectRatio: controller.lastAspectRatio,
            shapes: loadedShapes
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

    // MARK: - File Import

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            loadCADFile(url)
        case .failure(let error):
            loadError = error.localizedDescription
        }
    }

    private func loadCADFile(_ url: URL) {
        guard let format = CADFileFormat(fileExtension: url.pathExtension) else {
            loadError = "Unsupported file format: .\(url.pathExtension)"
            return
        }

        guard url.startAccessingSecurityScopedResource() else {
            loadError = "Cannot access file: permission denied"
            return
        }

        isLoadingFile = true
        loadError = nil
        operationStatus = nil

        Task {
            defer {
                url.stopAccessingSecurityScopedResource()
            }

            do {
                let result = try await CADFileLoader.load(from: url, format: format)

                bodies = result.bodies
                cadMetadata = result.metadata
                loadedShapes = result.shapes
                dimensions = result.dimensions
                geomTolerances = result.geomTolerances
                datums = result.datums

                originalColors = [:]
                for body in bodies {
                    originalColors[body.id] = body.color
                }

                proximityInfo = nil
                focusOnBounds()
                isLoadingFile = false
            } catch {
                loadError = error.localizedDescription
                isLoadingFile = false
            }
        }
    }

    // MARK: - Export

    private func exportShapes(format: ExportFormat) {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: format.fileExtension) ?? .data]
        panel.nameFieldStringValue = "export.\(format.fileExtension)"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            performExport(format: format, to: url)
        }
        #else
        // On iOS, export to a temp file and show share sheet
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("export.\(format.fileExtension)")
        performExport(format: format, to: tempURL)
        #endif
    }

    private func performExport(format: ExportFormat, to url: URL) {
        operationStatus = nil
        Task {
            do {
                try await ExportManager.export(shapes: loadedShapes, format: format, to: url)
                operationStatus = "Exported \(format.rawValue) to \(url.lastPathComponent)"
            } catch {
                loadError = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Healing

    private enum HealingOperation {
        case sew, upgrade, directFaces, toBSpline
    }

    private func applyHealing(_ operation: HealingOperation) {
        guard !loadedShapes.isEmpty else { return }
        operationStatus = nil

        var newShapes: [OCCTSwift.Shape] = []
        var anyChanged = false

        for shape in loadedShapes {
            let healed: OCCTSwift.Shape?
            switch operation {
            case .sew:
                healed = shape.sewn()
            case .upgrade:
                healed = shape.upgraded()
            case .directFaces:
                healed = shape.directFaces()
            case .toBSpline:
                healed = shape.convertedToBSpline()
            }

            if let healed {
                newShapes.append(healed)
                anyChanged = true
            } else {
                newShapes.append(shape)
            }
        }

        guard anyChanged else {
            operationStatus = "Healing had no effect on geometry"
            return
        }

        // Re-mesh healed shapes
        loadedShapes = newShapes
        var newBodies: [ViewportBody] = []
        var newMetadata: [String: CADBodyMetadata] = [:]

        for (i, shape) in newShapes.enumerated() {
            let bodyID = "healed-\(i)"
            let color = SIMD4<Float>(0.7, 0.7, 0.7, 1.0)
            let (body, meta) = CADFileLoader.shapeToBodyAndMetadata(shape, id: bodyID, color: color)
            if let body {
                newBodies.append(body)
                if let meta {
                    newMetadata[bodyID] = meta
                }
            }
        }

        bodies = newBodies
        cadMetadata = newMetadata
        originalColors = [:]
        for body in bodies {
            originalColors[body.id] = body.color
        }

        let opName: String
        switch operation {
        case .sew: opName = "Sew Faces"
        case .upgrade: opName = "Upgrade"
        case .directFaces: opName = "Direct Faces"
        case .toBSpline: opName = "Convert to BSpline"
        }
        operationStatus = "\(opName) applied successfully"
        focusOnBounds()
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
