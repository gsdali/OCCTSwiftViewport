// DisplayMode.swift
// ViewportKit
//
// Display modes for rendering geometry.

import Foundation

/// Display mode for rendering geometry in the viewport.
///
/// Different display modes provide different visual representations
/// of 3D content, from simple wireframes to fully lit shaded views.
public enum DisplayMode: String, CaseIterable, Sendable {

    /// Wireframe rendering - edges only.
    case wireframe

    /// Shaded rendering with lighting.
    case shaded

    /// Shaded with visible edges overlay.
    case shadedWithEdges

    /// Flat shading without smooth interpolation.
    case flat

    /// X-ray mode - transparent with visible internal edges.
    case xray

    /// Rendered with materials and textures.
    case rendered

    // MARK: - Properties

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .wireframe: return "Wireframe"
        case .shaded: return "Shaded"
        case .shadedWithEdges: return "Shaded + Edges"
        case .flat: return "Flat"
        case .xray: return "X-Ray"
        case .rendered: return "Rendered"
        }
    }

    /// Whether this mode shows surface shading.
    public var showsSurfaces: Bool {
        switch self {
        case .wireframe:
            return false
        case .shaded, .shadedWithEdges, .flat, .xray, .rendered:
            return true
        }
    }

    /// Whether this mode shows edges.
    public var showsEdges: Bool {
        switch self {
        case .wireframe, .shadedWithEdges, .xray:
            return true
        case .shaded, .flat, .rendered:
            return false
        }
    }

    /// Whether this mode uses smooth shading.
    public var usesSmoothShading: Bool {
        switch self {
        case .flat:
            return false
        case .wireframe, .shaded, .shadedWithEdges, .xray, .rendered:
            return true
        }
    }

    /// Whether this mode shows transparency.
    public var usesTransparency: Bool {
        self == .xray
    }

    /// Keyboard shortcut for this mode.
    public var keyboardShortcut: Character? {
        switch self {
        case .wireframe: return "w"
        case .shaded: return "s"
        case .shadedWithEdges: return "e"
        case .xray: return "x"
        default: return nil
        }
    }
}
