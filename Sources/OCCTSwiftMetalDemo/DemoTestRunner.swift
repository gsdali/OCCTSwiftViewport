// DemoTestRunner.swift
// OCCTSwiftMetalDemo
//
// Automated test runner that cycles through all demo galleries,
// validating each produces bodies without crashing.
// Launch with: swift run OCCTSwiftMetalDemo --test-all-demos

import Foundation
import simd
import OCCTSwift
import OCCTSwiftViewport
import OCCTSwiftTools

/// Describes a single demo to test.
struct DemoEntry {
    let category: String
    let name: String
    let run: () -> Curve2DGallery.GalleryResult
}

/// Runs all demos and reports results.
@MainActor
enum DemoTestRunner {

    static var isTestMode: Bool {
        ProcessInfo.processInfo.arguments.contains("--test-all-demos")
    }

    /// All demos across every gallery category.
    static var allDemos: [DemoEntry] {
        var demos: [DemoEntry] = []

        // Curve 2D
        demos.append(DemoEntry(category: "Curve2D", name: "showcase", run: Curve2DGallery.curveShowcase))
        demos.append(DemoEntry(category: "Curve2D", name: "intersections", run: Curve2DGallery.intersectionDemo))
        demos.append(DemoEntry(category: "Curve2D", name: "hatching", run: Curve2DGallery.hatchingDemo))
        demos.append(DemoEntry(category: "Curve2D", name: "gcc", run: Curve2DGallery.gccDemo))

        // Curve 3D
        demos.append(DemoEntry(category: "Curve3D", name: "showcase", run: Curve3DGallery.curveShowcase))
        demos.append(DemoEntry(category: "Curve3D", name: "helixAndSpirals", run: Curve3DGallery.helixAndSpirals))
        demos.append(DemoEntry(category: "Curve3D", name: "curvatureCombs", run: Curve3DGallery.curvatureCombs))
        demos.append(DemoEntry(category: "Curve3D", name: "bsplineFitting", run: Curve3DGallery.bsplineFitting))

        // Surfaces
        demos.append(DemoEntry(category: "Surface", name: "analytic", run: SurfaceGallery.analyticSurfaces))
        demos.append(DemoEntry(category: "Surface", name: "swept", run: SurfaceGallery.sweptSurfaces))
        demos.append(DemoEntry(category: "Surface", name: "freeform", run: SurfaceGallery.freeformSurfaces))
        demos.append(DemoEntry(category: "Surface", name: "pipe", run: SurfaceGallery.pipeSurfaces))
        demos.append(DemoEntry(category: "Surface", name: "isoCurves", run: SurfaceGallery.isoCurves))

        // Sweeps
        demos.append(DemoEntry(category: "Sweep", name: "constant", run: SweepGallery.constantPipe))
        demos.append(DemoEntry(category: "Sweep", name: "linearTaper", run: SweepGallery.linearTaper))
        demos.append(DemoEntry(category: "Sweep", name: "sCurve", run: SweepGallery.sCurveSweep))
        demos.append(DemoEntry(category: "Sweep", name: "interpolated", run: SweepGallery.interpolatedSweep))

        // Projection
        demos.append(DemoEntry(category: "Projection", name: "curveOnCylinder", run: ProjectionGallery.curveOnCylinder))
        demos.append(DemoEntry(category: "Projection", name: "curveOnSphere", run: ProjectionGallery.curveOnSphere))
        demos.append(DemoEntry(category: "Projection", name: "composite", run: ProjectionGallery.compositeProjection))
        demos.append(DemoEntry(category: "Projection", name: "pointProjection", run: ProjectionGallery.pointProjection))

        // Plates
        demos.append(DemoEntry(category: "Plate", name: "fromPoints", run: PlateGallery.plateFromPoints))
        demos.append(DemoEntry(category: "Plate", name: "deformed", run: PlateGallery.deformedPlate))
        demos.append(DemoEntry(category: "Plate", name: "tangent", run: PlateGallery.tangentDeformation))

        // Medial Axis
        demos.append(DemoEntry(category: "MedialAxis", name: "rectangle", run: MedialAxisGallery.rectangleSkeleton))
        demos.append(DemoEntry(category: "MedialAxis", name: "lShape", run: MedialAxisGallery.lShapeSkeleton))
        demos.append(DemoEntry(category: "MedialAxis", name: "thicknessMap", run: MedialAxisGallery.thicknessMap))
        demos.append(DemoEntry(category: "MedialAxis", name: "customProfile", run: MedialAxisGallery.customProfileSkeleton))

        // Naming
        demos.append(DemoEntry(category: "Naming", name: "primitive", run: NamingGallery.primitiveHistory))
        demos.append(DemoEntry(category: "Naming", name: "modification", run: NamingGallery.modificationTracking))
        demos.append(DemoEntry(category: "Naming", name: "tracing", run: NamingGallery.forwardBackwardTrace))
        demos.append(DemoEntry(category: "Naming", name: "selection", run: NamingGallery.namedSelection))

        // Annotations
        demos.append(DemoEntry(category: "Annotation", name: "length", run: AnnotationGallery.lengthDimensions))
        demos.append(DemoEntry(category: "Annotation", name: "radial", run: AnnotationGallery.radialDimensions))
        demos.append(DemoEntry(category: "Annotation", name: "angle", run: AnnotationGallery.angleDimensions))
        demos.append(DemoEntry(category: "Annotation", name: "labelsAndCloud", run: AnnotationGallery.labelsAndPointCloud))

        // OCCT 8 (all cases)
        let occt8: [(String, () -> Curve2DGallery.GalleryResult)] = [
            ("helixCurves", OCCT8Gallery.helixCurves),
            ("kdTree", OCCT8Gallery.kdTreeQueries),
            ("wedges", OCCT8Gallery.wedgePrimitives),
            ("hatchPatterns", OCCT8Gallery.hatchPatterns),
            ("shapeOps", OCCT8Gallery.shapeOperations),
            ("polynomials", OCCT8Gallery.polynomialRoots),
            ("transformOps", OCCT8Gallery.transformOps),
            ("shapeAnalysis", OCCT8Gallery.shapeAnalysis),
            ("intersections", OCCT8Gallery.intersectionAnalysis),
            ("volumeOps", OCCT8Gallery.volumeOps),
            ("quasiUniform", OCCT8Gallery.quasiUniformSampling),
            ("bezierFill", OCCT8Gallery.bezierSurfaceFill),
            ("revolution", OCCT8Gallery.revolutionDemo),
            ("linearRib", OCCT8Gallery.linearRibDemo),
            ("asymmetricChamfer", OCCT8Gallery.asymmetricChamfer),
            ("loftAdvanced", OCCT8Gallery.loftAdvanced),
            ("offsetByJoin", OCCT8Gallery.offsetByJoin),
            ("featureOps", OCCT8Gallery.featureOps),
            ("pipeTransitions", OCCT8Gallery.pipeTransitions),
            ("faceFromSurface", OCCT8Gallery.faceFromSurface),
            ("sectionAndValidation", OCCT8Gallery.sectionAndValidation),
            ("shapeRepair", OCCT8Gallery.shapeRepair),
            ("multiFuse", OCCT8Gallery.multiFuse),
            ("splitFaceByWire", OCCT8Gallery.splitFaceByWire),
            ("projectionAndOffset", OCCT8Gallery.projectionAndOffset),
            ("faceDivision", OCCT8Gallery.faceDivision),
            ("hollowAndAnalysis", OCCT8Gallery.hollowAndAnalysis),
            ("orientedBoundingBox", OCCT8Gallery.orientedBoundingBox),
            ("fuseAndBlend", OCCT8Gallery.fuseAndBlend),
            ("variableOffset", OCCT8Gallery.variableOffset),
            ("freeBoundsAndFeatures", OCCT8Gallery.freeBoundsAndFeatures),
            ("inertiaAndDistance", OCCT8Gallery.inertiaAndDistance),
            ("surgeryAndDetection", OCCT8Gallery.surgeryAndDetection),
            ("solidAnd2DFillets", OCCT8Gallery.solidAnd2DFillets),
            ("bsplineFillAndSubdivision", OCCT8Gallery.bsplineFillAndSubdivision),
            ("extremaAndArcs", OCCT8Gallery.extremaAndArcs),
            ("fillingAndSelfIntersection", OCCT8Gallery.fillingAndSelfIntersection),
            ("concavityAndInertia", OCCT8Gallery.concavityAndInertia),
            ("localOpsAndValidation", OCCT8Gallery.localOpsAndValidation),
            ("splitOpsAndExtrema", OCCT8Gallery.splitOpsAndExtrema),
            ("extremaAndCurveAnalysis", OCCT8Gallery.extremaAndCurveAnalysis),
            ("conicsAndPolyDistance", OCCT8Gallery.conicsAndPolyDistance),
            ("transformsAndTopology", OCCT8Gallery.transformsAndTopology),
            ("brepFillAndHealing", OCCT8Gallery.brepFillAndHealing),
            ("geometry2DCompletions", OCCT8Gallery.geometry2DCompletions),
            ("ocafFramework", OCCT8Gallery.ocafFramework),
            ("ocafPersistenceAndSTEP", OCCT8Gallery.ocafPersistenceAndSTEP),
            ("fileIOFormats", OCCT8Gallery.fileIOFormats),
            ("xdeAssembly", OCCT8Gallery.xdeAssembly),
            ("splitAndContours", OCCT8Gallery.splitAndContours),
            ("pointCloudAndRays", OCCT8Gallery.pointCloudAndRays),
            ("curvatureAndIntersection", OCCT8Gallery.curvatureAndIntersection),
            ("trihedronsAndFilling", OCCT8Gallery.trihedronsAndFilling),
            ("featBooleansAndContours", OCCT8Gallery.featBooleansAndContours),
            ("tkG2dToolkit", OCCT8Gallery.tkG2dToolkit),
            ("fairCurveAndAnalysis", OCCT8Gallery.fairCurveAndAnalysis),
            ("curveTransAndGeomFill", OCCT8Gallery.curveTransAndGeomFill),
            ("plateAndGeomFill", OCCT8Gallery.plateAndGeomFill),
            ("tkBoolIntersection", OCCT8Gallery.tkBoolIntersection),
            ("tkFeatOps", OCCT8Gallery.tkFeatOps),
            ("tkFilletOps", OCCT8Gallery.tkFilletOps),
            ("tkHlrOps", OCCT8Gallery.tkHlrOps),
            ("meshAndValidation", OCCT8Gallery.meshAndValidation),
            ("blendAndSampling", OCCT8Gallery.blendAndSampling),
            ("geomEntitiesAndBisector", OCCT8Gallery.geomEntitiesAndBisector),
            ("gccAnaSolvers", OCCT8Gallery.gccAnaSolvers),
            ("shapeModifiersAndPolygons", OCCT8Gallery.shapeModifiersAndPolygons),
            ("evolvedAndMeshOps", OCCT8Gallery.evolvedAndMeshOps),
            ("extremaAndFactories", OCCT8Gallery.extremaAndFactories),
            ("colorAndMaterial", OCCT8Gallery.colorAndMaterial),
            ("dateAndPixMap", OCCT8Gallery.dateAndPixMap),
            ("xcafDocAttributes", OCCT8Gallery.xcafDocAttributes),
            ("vrmlAndDocAttributes", OCCT8Gallery.vrmlAndDocAttributes),
            ("unitsAndBinaryIO", OCCT8Gallery.unitsAndBinaryIO),
            ("extendedAttributesAndShapeFix", OCCT8Gallery.extendedAttributesAndShapeFix),
            ("transformAndRecognition", OCCT8Gallery.transformAndRecognition),
            ("tnamingAndPackedMaps", OCCT8Gallery.tnamingAndPackedMaps),
            ("transactionsAndDeltas", OCCT8Gallery.transactionsAndDeltas),
            ("pathAndPresentation", OCCT8Gallery.pathAndPresentation),
            ("curveEvalAndQuaternion", OCCT8Gallery.curveEvalAndQuaternion),
            ("obbAndClassification", OCCT8Gallery.obbAndClassification),
            ("patternsAndInterpolation", OCCT8Gallery.patternsAndInterpolation),
            ("linearAlgebraAndConversions", OCCT8Gallery.linearAlgebraAndConversions),
            ("conicConversionsAndSolvers", OCCT8Gallery.conicConversionsAndSolvers),
            ("assemblyRefAndPaths", OCCT8Gallery.assemblyRefAndPaths),
            ("spatialQueryAndPrecision", OCCT8Gallery.spatialQueryAndPrecision),
            ("analyticIntersections", OCCT8Gallery.analyticIntersections),
            ("compBezierToBSpline", OCCT8Gallery.compBezierToBSpline),
            ("fileIOAndWireframeFix", OCCT8Gallery.fileIOAndWireframeFix),
            ("stlIOAndCurveAnalysis", OCCT8Gallery.stlIOAndCurveAnalysis),
            ("trimmedCurveAndSurfaceAnalysis", OCCT8Gallery.trimmedCurveAndSurfaceAnalysis),
            ("adjacencyAndEdgeAnalysis", OCCT8Gallery.adjacencyAndEdgeAnalysis),
            ("transformsAndGeometryProps", OCCT8Gallery.transformsAndGeometryProps),
            ("analyticBoundsAndQuadrics", OCCT8Gallery.analyticBoundsAndQuadrics),
            ("geometryFactoriesAndPipeShell", OCCT8Gallery.geometryFactoriesAndPipeShell),
            ("surfaceFactoriesAndWireAnalysis", OCCT8Gallery.surfaceFactoriesAndWireAnalysis),
            ("bsplineAndSewingDemo", OCCT8Gallery.bsplineAndSewingDemo),
            ("geomPropertyCoverage", OCCT8Gallery.geomPropertyCoverage),
            ("extremaAndConicDemo", OCCT8Gallery.extremaAndConicDemo),
            ("mathSolversAndEvaluation", OCCT8Gallery.mathSolversAndEvaluation),
            ("meshAndProjectionDemo", OCCT8Gallery.meshAndProjectionDemo),
            ("builderAndMassProperties", OCCT8Gallery.builderAndMassProperties),
            ("interpolationAndLofting", OCCT8Gallery.interpolationAndLofting),
            ("helixAndQuaternionDemo", OCCT8Gallery.helixAndQuaternionDemo),
        ]
        for (name, run) in occt8 {
            demos.append(DemoEntry(category: "OCCT8", name: name, run: run))
        }

        return demos
    }

    /// Run all demos sequentially in the viewport, logging results.
    /// Calls the completion handler with bodies for each demo so SpikeView can display them.
    static func runAll(
        loadDemo: @escaping ([ViewportBody], String) -> Void,
        completion: @escaping (Int, Int) -> Void
    ) {
        let demos = allDemos
        let total = demos.count
        var passed = 0
        var failed = 0
        var index = 0

        print("╔══════════════════════════════════════════════════════════════╗")
        print("║  DEMO TEST RUNNER — \(total) demos                              ║")
        print("╚══════════════════════════════════════════════════════════════╝")

        func runNext() {
            guard index < demos.count else {
                print("")
                print("════════════════════════════════════════════════════════════════")
                print("  RESULTS: \(passed) passed, \(failed) failed out of \(total)")
                print("════════════════════════════════════════════════════════════════")
                completion(passed, failed)
                return
            }

            let demo = demos[index]
            let num = index + 1
            index += 1

            let startTime = CFAbsoluteTimeGetCurrent()
            let result = demo.run()
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime

            let bodyCount = result.bodies.count
            let hasContent = !result.bodies.isEmpty || !result.description.isEmpty
            let status: String
            if hasContent {
                passed += 1
                status = "✅"
            } else {
                failed += 1
                status = "❌"
            }

            let timeStr = String(format: "%.2fs", elapsed)
            print("\(status) [\(num)/\(total)] \(demo.category)/\(demo.name) — \(bodyCount) bodies, \(timeStr)")
            if !result.description.isEmpty {
                // Truncate long descriptions
                let desc = result.description.prefix(120)
                print("   └─ \(desc)")
            }

            // Display in viewport
            loadDemo(result.bodies, "[\(num)/\(total)] \(demo.category)/\(demo.name)")

            // Schedule next demo after a brief delay so the viewport renders
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                runNext()
            }
        }

        runNext()
    }
}
