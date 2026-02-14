// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OCCTSwiftViewport",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "OCCTSwiftViewport",
            targets: ["OCCTSwiftViewport"]
        ),
    ],
    targets: [
        .target(
            name: "OCCTSwiftViewport",
            path: "Sources/OCCTSwiftViewport",
            resources: [
                .process("Renderer/Shaders.metal")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "OCCTSwiftMetalDemo",
            dependencies: ["OCCTSwiftViewport"],
            path: "Sources/OCCTSwiftMetalDemo",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "OCCTSwiftViewportTests",
            dependencies: ["OCCTSwiftViewport"],
            path: "Tests/OCCTSwiftViewportTests"
        ),
    ]
)
