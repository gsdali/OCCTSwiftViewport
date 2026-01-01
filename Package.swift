// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ViewportKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "ViewportKit",
            targets: ["ViewportKit"]
        ),
    ],
    targets: [
        .target(
            name: "ViewportKit",
            path: "Sources/ViewportKit",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "ViewportKitTests",
            dependencies: ["ViewportKit"],
            path: "Tests/ViewportKitTests"
        ),
    ]
)
