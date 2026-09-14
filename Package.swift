// swift-tools-version: 6.0
// Modified by l4rxx in 2026 for the l4rxx edition.
import PackageDescription

let package = Package(
    name: "MacDuo",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "LidAngleKit",
            path: "Sources/LidAngleKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "MacDuo",
            dependencies: ["LidAngleKit"],
            path: "Sources/MacDuo",
            resources: [.copy("Metal/DepthShaders.metal")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "lidprobe",
            dependencies: ["LidAngleKit"],
            path: "Sources/lidprobe",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MacDuoTests",
            dependencies: ["MacDuo"],
            path: "Tests/MacDuoTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
