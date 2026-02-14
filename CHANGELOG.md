# Changelog

All notable changes to OCCTSwiftViewport are documented in this file.

## [0.24.0] — 2026-02-15

### Added
- **Medial Axis Gallery** (`MedialAxisGallery.swift`): Computes and visualizes the Voronoi skeleton (medial axis) of planar shapes using OCCTSwift `MedialAxis` (BRepMAT2d).
  - Rectangle skeleton with inscribed circle node markers
  - L-shaped profile showing branching skeleton topology
  - Thickness map with arcs colored red (thin) to blue (thick) by wall distance
  - Custom T-profile skeleton with node/arc statistics
  - `computeForShape(_:)` API for use with STEP face selection
- Sidebar section: **Medial Axis Demos**

## [0.23.0] — 2026-02-15

### Added
- **Projection Gallery** (`ProjectionGallery.swift`): Projects 3D curves and points onto parametric surfaces using OCCTSwift `Surface.projectCurve3D`, `projectCurveSegments`, and `projectPoint`.
  - Curve on cylinder (diagonal line → helix on surface)
  - Curve on sphere (tilted circle → geodesic-like projection)
  - Composite projection with multi-segment UV coloring
  - Point projection with 20 scattered points, distance-colored lines (green=close, red=far)
- **Plate Gallery** (`PlateGallery.swift`): Creates and deforms plate surfaces using OCCTSwift `Surface.plateThrough`, `nlPlateDeformed` (G0), and `nlPlateDeformedG1` (G1).
  - Plate from scattered 3D points (terrain-like)
  - G0 position-constrained deformation (flat → curved)
  - G1 tangent-controlled deformation with direction arrows
- Sidebar sections: **Projection Demos**, **Plate Demos**

## [0.22.0] — 2026-02-15

### Added
- **Sweep Gallery** (`SweepGallery.swift`): Variable-section pipe sweeps using OCCTSwift `LawFunction` and `Shape.pipeShellWithLaw`.
  - Constant pipe (uniform cross-section)
  - Linear taper (narrowing from start to end)
  - S-curve sweep (smooth bulge)
  - Interpolated sweep (custom varying profile)
  - Each demo includes a 2D law function plot and spine wireframe overlay
- **GD&T display**: When STEP files with PMI data are loaded, dimensions, geometric tolerances, and datums are extracted and shown in a new **GD&T** sidebar section.

### Changed
- `CADLoadResult` now includes `dimensions: [DimensionInfo]`, `geomTolerances: [GeomToleranceInfo]`, and `datums: [DatumInfo]` arrays extracted from STEP documents via `Document.dimensions`, `Document.geomTolerances`, `Document.datums`.

## [0.21.0] — 2026-02-15

### Added
- **Surface Gallery** (`SurfaceGallery.swift`): Interactive surface demos using OCCTSwift `Surface` class.
  - Analytic surfaces: plane, cylinder, cone, sphere, torus (arranged in a row, trimmed, as UV grids)
  - Swept surfaces: extrusion along direction, revolution around axis
  - Freeform surfaces: 4×4 Bezier patch with control net overlay, 3×3 Bezier patch
  - Pipe surfaces: circular and elliptical cross-section pipes along curved spines
  - Iso-curves: U-iso (red) and V-iso (cyan) parameter curves highlighted on a Bezier surface
- Sidebar section: **Surface Demos**

## [0.20.0] — 2026-02-15

### Added
- **Curve3D Gallery** (`Curve3DGallery.swift`): 3D curve demos using OCCTSwift `Curve3D` class.
  - 3D curve showcase: line, circle, arc, ellipse, BSpline, Bezier in 3D space
  - Helix & spirals: helical interpolation, conical spiral, reversed + trimmed curves
  - Curvature combs: perpendicular comb teeth proportional to local curvature, with tip envelope
  - BSpline fitting: noisy point cloud with fitted curve (blue) vs exact interpolation (green)
- Sidebar section: **Curve3D Demos**

## [0.19.0] — 2026-02-15

### Added
- **3D geometry analysis in selection panel**: Selecting a face or edge on STEP geometry now shows rich property data in the selection info panel.
  - **Face selection**: surface type (Plane, Cylinder, BSpline, etc.), area, UV bounds, Gaussian curvature, mean curvature at the hit point
  - **Edge selection**: curve type (Line, Circle, BSpline, etc.), length, parameter bounds, curvature, projection distance at the hit point
- **Curvature direction overlays**: Toggleable overlays rendered at the selected point.
  - Faces: principal curvature directions (cyan kMin, magenta kMax) and surface normal (blue)
  - Edges: tangent direction (green), normal direction (blue), center of curvature (orange sphere + gray connector line)
- **Proximity detection**: "Check Proximity" button in the new **Analysis** sidebar section. When 2+ shapes are loaded, finds closest face pairs between shape 0 and shape 1, highlights them in color, and reports self-intersection status.
- Sidebar section: **Analysis** (curvature overlay toggle + proximity check)

## [0.18.0] — 2025-12-30

### Added
- Multi-format import (STEP, STL, OBJ) with face/edge/vertex selection
- Export to OBJ and PLY formats
- Shape healing operations (sew, upgrade, direct faces, convert to BSpline)
- Point classification (inside/outside/on boundary)

## [0.17.0] — 2025-12-30

### Added
- Curve2D gallery with showcase, intersections, hatching, and Gcc demos

## [0.16.0] — 2025-12-30

### Added
- STEP file import with face/edge/vertex selection
