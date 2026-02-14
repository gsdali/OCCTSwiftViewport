// RotationStyle.swift
// ViewportKit
//
// Camera rotation behavior styles.

import Foundation

/// Defines how camera rotation behaves in response to drag gestures.
///
/// Different CAD applications use different rotation models. This enum
/// allows configuration of the rotation behavior to match user preferences.
public enum RotationStyle: String, CaseIterable, Sendable {

    /// Arcball (trackball) rotation - unrestricted 3D rotation.
    ///
    /// Uses Ken Shoemake's arcball algorithm for intuitive 3D rotation.
    /// Dragging on the sphere rotates around axes perpendicular to drag.
    /// Dragging outside the sphere rotates around the view axis.
    ///
    /// Best for: Freeform 3D modeling, inspecting objects from any angle.
    case arcball

    /// Turntable rotation - Z-axis locked, like a pottery wheel.
    ///
    /// Horizontal drag rotates around the world Z (up) axis.
    /// Vertical drag tilts the camera up/down with limits to prevent
    /// going below the horizon.
    ///
    /// Best for: Architectural visualization, map-like views, CAD where
    /// "up" should always be up.
    case turntable

    /// First-person style rotation - camera-centric.
    ///
    /// Horizontal drag rotates left/right (yaw).
    /// Vertical drag looks up/down (pitch).
    /// Similar to first-person game controls.
    ///
    /// Best for: Walk-through visualizations, VR-style navigation.
    case firstPerson

    // MARK: - Properties

    /// Human-readable description of this rotation style.
    public var description: String {
        switch self {
        case .arcball:
            return "Free rotation in any direction"
        case .turntable:
            return "Rotate around vertical axis, tilt up/down"
        case .firstPerson:
            return "Look around from camera position"
        }
    }

    /// Whether this style constrains rotation to prevent gimbal lock issues.
    public var hasConstraints: Bool {
        switch self {
        case .arcball:
            return false
        case .turntable, .firstPerson:
            return true
        }
    }

    /// Recommended default for CAD applications.
    public static let cadDefault: RotationStyle = .turntable

    /// Recommended default for artistic/modeling applications.
    public static let modelingDefault: RotationStyle = .arcball
}
