// LightingConfiguration.swift
// ViewportKit
//
// Lighting presets and configuration for 3D scenes.

import Foundation
import simd

/// Configuration for scene lighting.
///
/// Defines light positions, intensities, and colors for consistent
/// CAD visualization lighting.
public struct LightingConfiguration: Sendable {

    // MARK: - Properties

    /// Key light (main directional light).
    public var keyLight: LightSettings

    /// Fill light (secondary, softer light).
    public var fillLight: LightSettings

    /// Back/rim light (for edge definition).
    public var backLight: LightSettings

    /// Ambient light intensity (0-1).
    public var ambientIntensity: Float

    /// Ambient light color.
    public var ambientColor: SIMD3<Float>

    /// Whether shadows are enabled.
    public var shadowsEnabled: Bool

    /// Shadow softness (0 = hard, 1 = soft).
    public var shadowSoftness: Float

    // MARK: - Initialization

    public init(
        keyLight: LightSettings,
        fillLight: LightSettings,
        backLight: LightSettings,
        ambientIntensity: Float = 0.3,
        ambientColor: SIMD3<Float> = SIMD3<Float>(1, 1, 1),
        shadowsEnabled: Bool = true,
        shadowSoftness: Float = 0.3
    ) {
        self.keyLight = keyLight
        self.fillLight = fillLight
        self.backLight = backLight
        self.ambientIntensity = ambientIntensity
        self.ambientColor = ambientColor
        self.shadowsEnabled = shadowsEnabled
        self.shadowSoftness = shadowSoftness
    }

    // MARK: - Presets

    /// Standard three-point lighting for CAD.
    ///
    /// Provides clear definition of form with:
    /// - Key light from upper-right-front
    /// - Fill light from left to soften shadows
    /// - Back light for edge definition
    public static let threePoint = LightingConfiguration(
        keyLight: LightSettings(
            direction: simd_normalize(SIMD3<Float>(-0.5, -0.3, -0.8)),
            intensity: 1.0,
            color: SIMD3<Float>(1.0, 0.98, 0.95)  // Slightly warm
        ),
        fillLight: LightSettings(
            direction: simd_normalize(SIMD3<Float>(0.6, 0.1, -0.5)),
            intensity: 0.4,
            color: SIMD3<Float>(0.95, 0.97, 1.0)  // Slightly cool
        ),
        backLight: LightSettings(
            direction: simd_normalize(SIMD3<Float>(0.0, 0.5, 0.8)),
            intensity: 0.3,
            color: SIMD3<Float>(1.0, 1.0, 1.0)
        ),
        ambientIntensity: 0.25
    )

    /// Soft studio lighting.
    public static let studio = LightingConfiguration(
        keyLight: LightSettings(
            direction: simd_normalize(SIMD3<Float>(-0.3, -0.4, -0.8)),
            intensity: 0.8,
            color: SIMD3<Float>(1.0, 1.0, 1.0)
        ),
        fillLight: LightSettings(
            direction: simd_normalize(SIMD3<Float>(0.5, 0.2, -0.6)),
            intensity: 0.5,
            color: SIMD3<Float>(1.0, 1.0, 1.0)
        ),
        backLight: LightSettings(
            direction: simd_normalize(SIMD3<Float>(0.0, 0.6, 0.6)),
            intensity: 0.4,
            color: SIMD3<Float>(1.0, 1.0, 1.0)
        ),
        ambientIntensity: 0.35,
        shadowsEnabled: true,
        shadowSoftness: 0.5
    )

    /// Architectural visualization lighting (simulates outdoor).
    public static let architectural = LightingConfiguration(
        keyLight: LightSettings(
            direction: simd_normalize(SIMD3<Float>(-0.4, -0.5, -0.7)),
            intensity: 1.2,
            color: SIMD3<Float>(1.0, 0.95, 0.9)  // Warm sunlight
        ),
        fillLight: LightSettings(
            direction: simd_normalize(SIMD3<Float>(0.5, 0.3, -0.4)),
            intensity: 0.3,
            color: SIMD3<Float>(0.8, 0.9, 1.0)  // Sky blue fill
        ),
        backLight: LightSettings(
            direction: simd_normalize(SIMD3<Float>(0.1, 0.7, 0.5)),
            intensity: 0.2,
            color: SIMD3<Float>(0.9, 0.95, 1.0)
        ),
        ambientIntensity: 0.2,
        shadowsEnabled: true,
        shadowSoftness: 0.2
    )

    /// Flat lighting for technical visualization.
    public static let flat = LightingConfiguration(
        keyLight: LightSettings(
            direction: SIMD3<Float>(0, 0, -1),
            intensity: 0.8,
            color: SIMD3<Float>(1, 1, 1)
        ),
        fillLight: LightSettings(
            direction: SIMD3<Float>(0, 0, -1),
            intensity: 0.0,
            color: SIMD3<Float>(1, 1, 1)
        ),
        backLight: LightSettings(
            direction: SIMD3<Float>(0, 0, 1),
            intensity: 0.0,
            color: SIMD3<Float>(1, 1, 1)
        ),
        ambientIntensity: 0.6,
        shadowsEnabled: false
    )
}

// MARK: - Light Settings

/// Settings for a single light source.
public struct LightSettings: Sendable {
    /// Direction the light is pointing (normalized).
    public var direction: SIMD3<Float>

    /// Light intensity (0-2 typical range).
    public var intensity: Float

    /// Light color (RGB, 0-1 range).
    public var color: SIMD3<Float>

    /// Whether this light is enabled.
    public var isEnabled: Bool

    public init(
        direction: SIMD3<Float>,
        intensity: Float = 1.0,
        color: SIMD3<Float> = SIMD3<Float>(1, 1, 1),
        isEnabled: Bool = true
    ) {
        self.direction = direction
        self.intensity = intensity
        self.color = color
        self.isEnabled = isEnabled
    }
}
