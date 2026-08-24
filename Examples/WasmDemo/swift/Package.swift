// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "WasmDemo",
    products: [
        .executable(name: "WasmBridgeWorker", targets: ["WasmBridgeWorker"]),
    ],
    dependencies: [
        .package(path: "../../.."),
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", exact: "0.56.1"),
    ],
    targets: [
        .executableTarget(
            name: "WasmBridgeWorker",
            dependencies: [
                .product(name: "SeamCarvingCore", package: "wasm-browser-demo"),
                .product(name: "JavaScriptKit", package: "JavaScriptKit"),
                .product(name: "JavaScriptEventLoop", package: "JavaScriptKit"),
            ]
        ),
    ]
)
