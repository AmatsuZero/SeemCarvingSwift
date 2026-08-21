// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SeamCarvingSwift",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SeamCarvingCore", targets: ["SeamCarvingCore"]),
        .library(name: "SeamCarvingAccelerate", targets: ["SeamCarvingAccelerate"]),
        .library(name: "SeamCarvingMetal", targets: ["SeamCarvingMetal"]),
        .library(name: "SeamCarvingApple", targets: ["SeamCarvingApple"]),
    ],
    targets: [
        .target(name: "SeamCarvingCore"),
        .target(name: "SeamCarvingAccelerate", dependencies: ["SeamCarvingCore"]),
        .target(
            name: "SeamCarvingMetal",
            dependencies: ["SeamCarvingCore"],
            resources: [.copy("Shaders/SeamCarving.metal")]
        ),
        .target(name: "SeamCarvingApple", dependencies: ["SeamCarvingCore"]),
        .testTarget(name: "SeamCarvingCoreTests", dependencies: ["SeamCarvingCore"]),
        .testTarget(name: "SeamCarvingAccelerateTests", dependencies: ["SeamCarvingCore", "SeamCarvingAccelerate"]),
        .testTarget(name: "SeamCarvingMetalTests", dependencies: ["SeamCarvingCore", "SeamCarvingMetal"]),
        .testTarget(name: "SeamCarvingAppleTests", dependencies: ["SeamCarvingCore", "SeamCarvingApple"]),
    ]
)
