// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SeamCarvingSwift",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SeamCarvingCore", targets: ["SeamCarvingCore"]),
        .library(name: "SeamCarvingAccelerate", targets: ["SeamCarvingAccelerate"]),
        .library(name: "SeamCarvingMetal", targets: ["SeamCarvingMetal"]),
        .library(name: "SeamCarvingAppleRuntime", targets: ["SeamCarvingAppleRuntime"]),
        .library(name: "SeamCarvingAppleImaging", targets: ["SeamCarvingAppleImaging"]),
        .library(name: "SeamCarvingCoreVideo", targets: ["SeamCarvingCoreVideo"]),
        .library(name: "SeamCarvingUIKit", targets: ["SeamCarvingUIKit"]),
        .library(name: "SeamCarvingAppKit", targets: ["SeamCarvingAppKit"]),
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
            name: "SeamCarvingAppleRuntime",
            dependencies: ["SeamCarvingCore", "SeamCarvingAccelerate", "SeamCarvingMetal"]
        ),
        .target(
            name: "SeamCarvingAppleImaging",
            dependencies: ["SeamCarvingCore", "SeamCarvingAppleRuntime"]
        ),
        .target(
            name: "SeamCarvingCoreVideo",
            dependencies: ["SeamCarvingCore", "SeamCarvingAppleRuntime", "SeamCarvingAppleImaging"]
        ),
        .target(
            name: "SeamCarvingUIKit",
            dependencies: ["SeamCarvingAppleRuntime", "SeamCarvingAppleImaging"]
        ),
        .target(
            name: "SeamCarvingAppKit",
            dependencies: ["SeamCarvingAppleRuntime", "SeamCarvingAppleImaging"]
        ),
        .target(
            name: "SeamCarvingApple",
            dependencies: ["SeamCarvingAppleRuntime", "SeamCarvingAppleImaging"]
        ),
        .target(
            name: "SeamCarvingVision",
            dependencies: ["SeamCarvingCore", "SeamCarvingAppleRuntime", "SeamCarvingAppleImaging"],
            linkerSettings: [.linkedFramework("Vision")]
        ),
        .target(
            name: "SeamCarvingCLI",
            dependencies: [
                "SeamCarvingCore",
                "SeamCarvingAppleRuntime",
                "SeamCarvingAppleImaging",
                "SeamCarvingVision",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "seamcarve-cli",
            dependencies: [
                "SeamCarvingCLI",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .target(
            name: "SeamCarvingBenchmark",
            dependencies: ["SeamCarvingCore", "SeamCarvingAccelerate", "SeamCarvingMetal", "SeamCarvingAppleImaging"]
        ),
        .executableTarget(name: "seamcarve-benchmark", dependencies: ["SeamCarvingBenchmark"]),
        .testTarget(name: "SeamCarvingCoreTests", dependencies: ["SeamCarvingCore", "SeamCarvingBenchmark"]),
        .testTarget(name: "SeamCarvingAccelerateTests", dependencies: ["SeamCarvingCore", "SeamCarvingAccelerate"]),
        .testTarget(name: "SeamCarvingMetalTests", dependencies: ["SeamCarvingCore", "SeamCarvingAccelerate", "SeamCarvingMetal"]),
        .testTarget(name: "SeamCarvingAppleRuntimeTests", dependencies: ["SeamCarvingCore", "SeamCarvingAppleRuntime"]),
        .testTarget(name: "SeamCarvingAppleImagingTests", dependencies: ["SeamCarvingCore", "SeamCarvingAppleRuntime", "SeamCarvingAppleImaging"]),
        .testTarget(name: "SeamCarvingCoreVideoTests", dependencies: ["SeamCarvingCore", "SeamCarvingAppleRuntime", "SeamCarvingCoreVideo"]),
        .testTarget(name: "SeamCarvingUIKitTests", dependencies: ["SeamCarvingCore", "SeamCarvingAppleRuntime", "SeamCarvingUIKit"]),
        .testTarget(name: "SeamCarvingAppKitTests", dependencies: ["SeamCarvingCore", "SeamCarvingAppleRuntime", "SeamCarvingAppKit"]),
        .testTarget(name: "SeamCarvingVisionTests", dependencies: ["SeamCarvingCore", "SeamCarvingAppleRuntime", "SeamCarvingAppleImaging", "SeamCarvingVision"]),
        .testTarget(name: "SeamCarvingCLITests", dependencies: ["SeamCarvingCLI", "SeamCarvingVision"]),
    ]
)
