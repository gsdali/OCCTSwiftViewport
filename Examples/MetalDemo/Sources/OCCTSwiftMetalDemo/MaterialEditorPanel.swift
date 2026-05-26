// MaterialEditorPanel.swift
// OCCTSwiftMetalDemo
//
// SwiftUI panel for editing the PBRMaterial of selected viewport bodies.
// Renders a 96×96 sphere preview, preset swatches, and parameter sliders.

import SwiftUI
import simd
import OCCTSwiftViewport

@MainActor
struct MaterialEditorPanel: View {

    @Binding var bodies: [ViewportBody]
    @ObservedObject var controller: ViewportController
    @ObservedObject var library: MaterialLibrary

    /// Current edit buffer. Reflects the first selected body's material when one is selected.
    @State private var editing: PBRMaterial = .plasticGlossy
    @State private var previewImage: CGImage?
    @State private var lastSelectionSnapshot: Set<String> = []
    @State private var showSaveDialog = false
    @State private var saveName: String = "My Material"

    /// Lazy renderer for the preview sphere. Rebuilt on demand.
    @State private var previewRenderer: OffscreenRenderer? = OffscreenRenderer()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if controller.selectedBodyIDs.isEmpty {
                Text("Select a body to edit its material")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                spherePreview
                presetGrid
                Divider()
                parameterSliders
                Divider()
                saveControls
            }
        }
        .onAppear { syncFromSelection() }
        .onChange(of: controller.selectedBodyIDs) { _, _ in syncFromSelection() }
    }

    // MARK: - Sphere preview

    private var spherePreview: some View {
        HStack {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.05))
                    .frame(width: 96, height: 96)
                if let img = previewImage {
                    Image(decorative: img, scale: 1.0)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            Spacer()
        }
    }

    // MARK: - Preset grid

    private var presetGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 56, maximum: 80), spacing: 6)]
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(library.materials) { named in
                presetSwatch(named)
            }
        }
    }

    private func presetSwatch(_ named: NamedMaterial) -> some View {
        let m = named.material
        let baseRGB = Color(red: Double(m.baseColor.x), green: Double(m.baseColor.y), blue: Double(m.baseColor.z))
        return Button {
            applyPreset(named.material)
        } label: {
            VStack(spacing: 2) {
                Circle()
                    .fill(baseRGB)
                    .frame(width: 32, height: 32)
                    .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 1))
                Text(named.name)
                    .font(.system(size: 9))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .help(named.name)
    }

    // MARK: - Parameter sliders

    private var parameterSliders: some View {
        VStack(alignment: .leading, spacing: 6) {
            colorRow
            slider("Metallic", value: $editing.metallic, range: 0...1)
            slider("Roughness", value: $editing.roughness, range: 0.04...1)
            slider(
                "IOR",
                value: $editing.ior, range: 1.0...2.5,
                disabled: editing.metallic > 0.5
            )
            slider("Clearcoat", value: $editing.clearcoat, range: 0...1)
            slider(
                "Coat Roughness",
                value: $editing.clearcoatRoughness, range: 0.04...1,
                disabled: editing.clearcoat < 0.001
            )
            slider("Opacity", value: $editing.opacity, range: 0...1)
            slider("Emission", value: $editing.emissiveStrength, range: 0...10)
        }
        .onChange(of: editing) { _, _ in
            applyEditingToSelection()
            schedulePreview()
        }
    }

    private var colorRow: some View {
        HStack {
            Text("Base Color").font(.caption).frame(width: 110, alignment: .leading)
            ColorPicker("", selection: Binding(
                get: {
                    Color(red: Double(editing.baseColor.x),
                          green: Double(editing.baseColor.y),
                          blue: Double(editing.baseColor.z))
                },
                set: { newColor in
                    if let rgb = newColor.linearRGB() {
                        editing.baseColor = SIMD3<Float>(Float(rgb.r), Float(rgb.g), Float(rgb.b))
                    }
                }
            ))
            .labelsHidden()
        }
    }

    private func slider(
        _ label: String,
        value: Binding<Float>,
        range: ClosedRange<Float>,
        disabled: Bool = false
    ) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .frame(width: 110, alignment: .leading)
                .foregroundStyle(disabled ? .secondary : .primary)
            Slider(value: value, in: range)
                .disabled(disabled)
            Text(String(format: "%.2f", value.wrappedValue))
                .font(.system(size: 10, design: .monospaced))
                .frame(width: 36, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Save / load

    private var saveControls: some View {
        HStack {
            Button {
                showSaveDialog = true
            } label: {
                Label("Save Material…", systemImage: "square.and.arrow.down")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .alert("Save material as…", isPresented: $showSaveDialog) {
            TextField("Name", text: $saveName)
            Button("Save") {
                let named = NamedMaterial(name: saveName, material: editing, isBuiltin: false)
                library.saveUserMaterial(named)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Logic

    /// Pulls the first selected body's material into the edit buffer. Called on selection change.
    private func syncFromSelection() {
        let ids = controller.selectedBodyIDs
        guard ids != lastSelectionSnapshot else { return }
        lastSelectionSnapshot = ids
        if let first = bodies.first(where: { ids.contains($0.id) }) {
            editing = first.effectiveMaterial
            schedulePreview()
        }
    }

    private func applyPreset(_ m: PBRMaterial) {
        editing = m
    }

    private func applyEditingToSelection() {
        let ids = controller.selectedBodyIDs
        guard !ids.isEmpty else { return }
        for i in bodies.indices where ids.contains(bodies[i].id) {
            bodies[i].material = editing
        }
    }

    /// Re-renders the preview sphere with the current edit buffer.
    /// Trailing-edge debounced via Task.sleep.
    @State private var previewTask: Task<Void, Never>?
    private func schedulePreview() {
        previewTask?.cancel()
        let snapshot = editing
        previewTask = Task {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100 ms debounce
            if Task.isCancelled { return }
            await renderPreview(material: snapshot)
        }
    }

    private func renderPreview(material: PBRMaterial) async {
        guard let renderer = previewRenderer else { return }
        var sphere = ViewportBody.sphere(id: "preview", radius: 0.5)
        sphere.material = material

        // Camera positioned to give a clean 3/4 view
        let cam = CameraState(
            distance: 1.6,
            pivot: SIMD3<Float>(0, 0, 0)
        )

        let opts = OffscreenRenderOptions(
            width: 192, height: 192, // 2x for retina; SwiftUI scales to 96
            cameraState: cam,
            displayMode: .shaded,
            lightingConfiguration: .threePoint,
            backgroundColor: SIMD4<Float>(0.10, 0.10, 0.11, 1.0),
            showGrid: false,
            showAxes: false,
            msaaSampleCount: 4
        )
        let img = renderer.render(bodies: [sphere], options: opts)
        previewImage = img
    }
}

// MARK: - Color helpers

private extension Color {
    /// Converts SwiftUI Color to linear sRGB components in 0…1.
    /// Returns nil if the color cannot be resolved (e.g. dynamic colors without context).
    func linearRGB() -> (r: Double, g: Double, b: Double)? {
        #if canImport(AppKit)
        let ns = NSColor(self).usingColorSpace(.sRGB)
        guard let c = ns else { return nil }
        return (linearize(Double(c.redComponent)),
                linearize(Double(c.greenComponent)),
                linearize(Double(c.blueComponent)))
        #else
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return (linearize(Double(r)), linearize(Double(g)), linearize(Double(b)))
        #endif
    }

    private func linearize(_ s: Double) -> Double {
        // sRGB → linear
        s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
    }
}
