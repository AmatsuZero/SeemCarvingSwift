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
        .library(name: "SeamCarvingVision", targets: ["SeamCarvingVision"]),
        .executable(name: "seamcarve-cli", targets: ["seamcarve-cli"]),
    ],
    targets: [
        .target(name: "SeamCarvingCore"),
        .target(name: "SeamCarvingAccelerate", dependencies: ["SeamCarvingCore"]),
        .target(
            name: "SeamCarvingMetal",
            dependencies: ["SeamCarvingCore"],
            resources: [.copy("Shaders/SeamCarving.metal")]
        ),
        .target(
            name: "SeamCarvingApple",
            dependencies: ["SeamCarvingCore", "SeamCarvingAccelerate", "SeamCarvingMetal"]
        ),
        .target(
            name: "SeamCarvingVision",
            dependencies: ["SeamCarvingCore", "SeamCarvingApple"],
            linkerSettings: [.linkedFramework("Vision")]
        ),
        .target(name: "SeamCarvingCLI", dependencies: ["SeamCarvingCore"]),
        .executableTarget(
            name: "seamcarve-cli",
            dependencies: ["SeamCarvingCLI", "SeamCarvingApple"]
        ),
        .testTarget(name: "SeamCarvingCoreTests", dependencies: ["SeamCarvingCore"]),
        .testTarget(name: "SeamCarvingAccelerateTests", dependencies: ["SeamCarvingCore", "SeamCarvingAccelerate"]),
        .testTarget(name: "SeamCarvingMetalTests", dependencies: ["SeamCarvingCore", "SeamCarvingMetal"]),
        .testTarget(name: "SeamCarvingAppleTests", dependencies: ["SeamCarvingCore", "SeamCarvingAccelerate", "SeamCarvingMetal", "SeamCarvingApple"]),
        .testTarget(name: "SeamCarvingVisionTests", dependencies: ["SeamCarvingCore", "SeamCarvingApple", "SeamCarvingVision"]),
        .testTarget(name: "SeamCarvingCLITests", dependencies: ["SeamCarvingCLI", "SeamCarvingApple"]),
    ]
)
