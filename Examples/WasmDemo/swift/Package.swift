// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "WasmDemo",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "WasmBridgeWorker", targets: ["WasmBridgeWorker"]),
    ],
    dependencies: [
        .package(name: "SeamCarvingSwift", path: "../../.."),
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", exact: "0.56.1"),
    ],
    targets: [
        .target(
            name: "WasmBridgeCore",
            dependencies: [
                .product(name: "SeamCarvingCore", package: "SeamCarvingSwift"),
            ]
        ),
        .testTarget(name: "WasmBridgeCoreTests", dependencies: ["WasmBridgeCore"]),
        .executableTarget(
            name: "WasmBridgeWorker",
            dependencies: [
                "WasmBridgeCore",
                .product(name: "JavaScriptKit", package: "JavaScriptKit"),
                .product(name: "JavaScriptEventLoop", package: "JavaScriptKit"),
            ]
        ),
    ]
)
