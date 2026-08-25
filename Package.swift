// swift-tools-version: 6.0
import CompilerPluginSupport
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
        .library(name: "SeamCarvingCLIModel", targets: ["SeamCarvingCLIModel"]),
        .library(name: "SeamCarvingCLIArguments", targets: ["SeamCarvingCLIArguments"]),
        .library(name: "SeamCarvingCLIOrchestration", targets: ["SeamCarvingCLIOrchestration"]),
        .library(name: "SeamCarvingAppleCLIBackend", targets: ["SeamCarvingAppleCLIBackend"]),
        // Deprecated source-compatible umbrella for existing CLI library users.
        .library(name: "SeamCarvingCLI", targets: ["SeamCarvingCLI"]),
        .library(name: "SeamCarvingBenchmark", targets: ["SeamCarvingBenchmark"]),
        .library(name: "SeamCarvingAndroidBridge", type: .dynamic, targets: ["SeamCarvingAndroidBridge"]),
        .executable(name: "seamcarve-cli", targets: ["seamcarve-cli-apple"]),
        .executable(name: "seamcarve-benchmark", targets: ["seamcarve-benchmark"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.6.0"),
        .package(url: "https://github.com/swiftlang/swift-java", exact: "0.2.0"),
        .package(url: "https://github.com/swiftlang/swift-subprocess.git", exact: "0.4.0"),
    ],
    targets: [
        .target(name: "SeamCarvingCore"),
        .target(
            name: "SeamCarvingAndroidBridge",
            dependencies: [
                "SeamCarvingCore",
                .product(name: "SwiftJava", package: "swift-java"),
            ],
            exclude: ["swift-java.config"],
            plugins: [
                .plugin(name: "JExtractSwiftPlugin", package: "swift-java"),
            ]
        ),
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
        .target(name: "SeamCarvingCLIModel", dependencies: ["SeamCarvingCore"]),
        .target(
            name: "SeamCarvingCLIArguments",
            dependencies: [
                "SeamCarvingCLIModel",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .target(name: "SeamCarvingCLIOrchestration", dependencies: ["SeamCarvingCLIModel"]),
        .target(
            name: "SeamCarvingAppleCLIBackend",
            dependencies: [
                "SeamCarvingCLIModel",
                "SeamCarvingCLIOrchestration",
                "SeamCarvingCore",
                "SeamCarvingAppleRuntime",
                "SeamCarvingAppleImaging",
                "SeamCarvingVision",
            ]
        ),
        .target(
            name: "SeamCarvingCLI",
            dependencies: [
                "SeamCarvingCLIModel",
                "SeamCarvingCLIArguments",
                "SeamCarvingCLIOrchestration",
                "SeamCarvingAppleCLIBackend",
            ]
        ),
        .executableTarget(
            name: "seamcarve-cli-apple",
            dependencies: [
                "SeamCarvingCLIModel",
                "SeamCarvingCLIArguments",
                "SeamCarvingCLIOrchestration",
                "SeamCarvingAppleCLIBackend",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .target(
            name: "SeamCarvingBenchmark",
            dependencies: ["SeamCarvingCore", "SeamCarvingAccelerate", "SeamCarvingMetal", "SeamCarvingAppleImaging"]
        ),
        .executableTarget(name: "seamcarve-benchmark", dependencies: ["SeamCarvingBenchmark"]),
        .testTarget(name: "SeamCarvingCoreTests", dependencies: ["SeamCarvingCore"]),
        .testTarget(name: "SeamCarvingAndroidBridgeTests", dependencies: ["SeamCarvingAndroidBridge"]),
        .testTarget(name: "SeamCarvingBenchmarkTests", dependencies: ["SeamCarvingCore", "SeamCarvingBenchmark"]),
        .testTarget(name: "SeamCarvingAccelerateTests", dependencies: ["SeamCarvingCore", "SeamCarvingAccelerate"]),
        .testTarget(name: "SeamCarvingMetalTests", dependencies: ["SeamCarvingCore", "SeamCarvingAccelerate", "SeamCarvingMetal"]),
        .testTarget(name: "SeamCarvingAppleRuntimeTests", dependencies: ["SeamCarvingCore", "SeamCarvingAppleRuntime"]),
        .testTarget(name: "SeamCarvingAppleImagingTests", dependencies: ["SeamCarvingCore", "SeamCarvingAppleRuntime", "SeamCarvingAppleImaging"]),
        .testTarget(name: "SeamCarvingCoreVideoTests", dependencies: ["SeamCarvingCore", "SeamCarvingAppleRuntime", "SeamCarvingCoreVideo"]),
        .testTarget(name: "SeamCarvingUIKitTests", dependencies: ["SeamCarvingCore", "SeamCarvingAppleRuntime", "SeamCarvingUIKit"]),
        .testTarget(name: "SeamCarvingAppKitTests", dependencies: ["SeamCarvingCore", "SeamCarvingAppleRuntime", "SeamCarvingAppKit"]),
        .testTarget(name: "SeamCarvingAppleCompatibilityTests", dependencies: ["SeamCarvingApple", "SeamCarvingCore"]),
        .testTarget(name: "SeamCarvingVisionTests", dependencies: ["SeamCarvingCore", "SeamCarvingAppleRuntime", "SeamCarvingAppleImaging", "SeamCarvingVision"]),
        .testTarget(name: "SeamCarvingCLIArgumentsTests", dependencies: ["SeamCarvingCLIArguments", "SeamCarvingCLIModel"]),
        .testTarget(name: "SeamCarvingCLIOrchestrationTests", dependencies: ["SeamCarvingCLIOrchestration", "SeamCarvingCLIArguments", "SeamCarvingCLIModel"]),
        .testTarget(name: "SeamCarvingAppleCLITests", dependencies: ["SeamCarvingAppleCLIBackend", "SeamCarvingCLIArguments", "SeamCarvingCLIModel", "SeamCarvingCLIOrchestration"]),
    ]
)
