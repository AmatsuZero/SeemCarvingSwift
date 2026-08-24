// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SeamCarvingSwift",
    products: [
        .library(name: "SeamCarvingCore", targets: ["SeamCarvingCore"]),
        .library(name: "SeamCarvingAccelerate", targets: ["SeamCarvingAccelerate"]),
        .library(name: "SeamCarvingMetal", targets: ["SeamCarvingMetal"]),
        .library(name: "SeamCarvingApple", targets: ["SeamCarvingApple"]),
        .library(name: "SeamCarvingVision", targets: ["SeamCarvingVision"]),
        // Expose the implementation modules so the standalone iOS test host
        // can link the package's existing XCTest sources.
        .library(name: "SeamCarvingCLI", targets: ["SeamCarvingCLI"]),
        .library(name: "SeamCarvingBenchmark", targets: ["SeamCarvingBenchmark"]),
        .executable(name: "seamcarve-cli", targets: ["seamcarve-cli"]),
        .executable(name: "seamcarve-benchmark", targets: ["seamcarve-benchmark"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.6.0"),
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
        .target(
            name: "SeamCarvingCLI",
            dependencies: [
                "SeamCarvingCore",
                "SeamCarvingApple",
                "SeamCarvingVision",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "seamcarve-cli",
            dependencies: [
                "SeamCarvingCLI",
                "SeamCarvingApple",
                "SeamCarvingVision",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .target(
            name: "SeamCarvingBenchmark",
            dependencies: ["SeamCarvingCore", "SeamCarvingAccelerate", "SeamCarvingMetal", "SeamCarvingApple"]
        ),
        .executableTarget(name: "seamcarve-benchmark", dependencies: ["SeamCarvingBenchmark"]),
        .testTarget(name: "SeamCarvingCoreTests", dependencies: ["SeamCarvingCore", "SeamCarvingBenchmark"]),
        .testTarget(name: "SeamCarvingAccelerateTests", dependencies: ["SeamCarvingCore", "SeamCarvingAccelerate"]),
        .testTarget(name: "SeamCarvingMetalTests", dependencies: ["SeamCarvingCore", "SeamCarvingAccelerate", "SeamCarvingMetal"]),
        .testTarget(name: "SeamCarvingAppleTests", dependencies: ["SeamCarvingCore", "SeamCarvingAccelerate", "SeamCarvingMetal", "SeamCarvingApple"]),
        .testTarget(name: "SeamCarvingVisionTests", dependencies: ["SeamCarvingCore", "SeamCarvingApple", "SeamCarvingVision"]),
        .testTarget(name: "SeamCarvingCLITests", dependencies: ["SeamCarvingCLI", "SeamCarvingApple"]),
    ]
)
