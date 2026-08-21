// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SeamCarvingSwift",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SeamCarvingCore", targets: ["SeamCarvingCore"]),
    ],
    targets: [
        .target(name: "SeamCarvingCore"),
        .testTarget(name: "SeamCarvingCoreTests", dependencies: ["SeamCarvingCore"]),
    ]
)
