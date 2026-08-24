# CLI target boundaries

`seamcarve-cli` is a macOS command-line application today, but its command
model must not dictate the portability of the seam-carving library. This
document defines the target boundaries used to keep syntax parsing, execution
orchestration, image I/O, and executable process handling separate. It reserves
an implementation slot for a Windows CLI without adding a placeholder target
that cannot yet be built or tested.

## Target graph

```text
SeamCarvingCore
        ^
        |
SeamCarvingCLIModel <--- SeamCarvingCLIArguments
        ^                         ^
        |                         |
SeamCarvingCLIOrchestration        |
        ^                         |
        |                         |
   +----+-------------------------+----+
   |                                     |
SeamCarvingAppleCLIBackend       SeamCarvingWindowsCLIBackend (future)
   |                                     |
Apple Runtime/Imaging/Vision      Windows codec / WinSDK adapter
   |                                     |
seamcarve-cli-apple              seamcarve-cli-windows (future)
```

| Target | Responsibility | May import |
| --- | --- | --- |
| `SeamCarvingCLIModel` | Command request/configuration validation, exit-code taxonomy, batch job planning, CLI-neutral output-format value types. | Foundation and `SeamCarvingCore` only. |
| `SeamCarvingCLIArguments` | `swift-argument-parser` declarations and conversion of argv values into model values. | `ArgumentParser`, `SeamCarvingCLIModel`. |
| `SeamCarvingCLIOrchestration` | File-system-neutral batch execution, progress/diagnostics, backend capability validation, and stable error presentation. | Foundation and `SeamCarvingCLIModel` only; it does not directly depend on Core. |
| `SeamCarvingAppleCLIBackend` | `CGImage` decoding/encoding, debug image artifacts, and turning a validated model configuration into an Apple/Vision processing request. | Model, orchestration, Apple Runtime/Imaging, Vision, and Apple imaging frameworks. |
| `SeamCarvingWindowsCLIBackend` *(future)* | Windows codec/WinSDK image adapter and Windows-specific diagnostic/process conventions. | Model, orchestration, Core, and Windows-only adapters. |
| `seamcarve-cli-apple` | macOS `@main`, help/version surface, console I/O, exit status, and Apple-backend assembly. | Arguments, orchestration, Apple backend, and `ArgumentParser`. |
| `seamcarve-cli-windows` *(future)* | Windows `@main`, console I/O, exit status, and Windows-backend assembly. | Arguments, orchestration, Windows backend, and `ArgumentParser`. |
| `SeamCarvingCLI` | Deprecated source-compatibility facade for the existing public product. | Temporarily re-export the three CLI libraries, including `SeamCarvingCLIArguments`; remove this facade in the next major release. |

`swift-argument-parser` remains a package-level SwiftPM dependency because
SwiftPM resolves dependencies per package, not per target. It is nevertheless
linked only by `SeamCarvingCLIArguments` and `seamcarve-cli-apple`; all non-CLI
products remain outside its dependency closure.

## Data ownership

`CLIOptions`, `CLIConfiguration`, `BatchConfiguration`, batch job descriptions,
`CLIExitCode`, `ResizeMode`, `SeamColor`, `SeamShape`, and `CLIOutputFormat`
belong to `SeamCarvingCLIModel`. The model must use its own
`FacePolicyRequest` and `FaceCadenceRequest` values rather than Vision types.
`SeamCarvingAppleCLIBackend` performs the one-way mapping from those values to
`FaceProtectionPolicy` and `FaceDetectionCadence`. `CLIProcessResult` is model
data as well: it is the callback result consumed by the portable batch
scheduler, even though `CLIProcessor` which produces it is Apple-specific.

This deliberately makes the **command model and orchestration contracts**
portable, not the full image-file CLI. File decoding, image rendering, Vision
face detection, and executable entry points remain adapter-specific until a
Windows/Android/WASM implementation is introduced.

## Windows reservation contract

The target graph reserves `SeamCarvingWindowsCLIBackend` and
`seamcarve-cli-windows` by name and responsibility only. Do not add empty SwiftPM
targets before there is a Windows toolchain CI lane and a real codec decision.

`SeamCarvingCLIOrchestration` owns these platform-neutral protocols:

```swift
public protocol CLIImageBackend: Sendable {
    var capabilities: CLIBackendCapabilities { get }
    func process(_ options: CLIOptions) async throws -> CLIProcessResult
    func exitCode(for error: Error) -> CLIExitCode?
    func message(for error: Error) -> String?
}

public protocol CLIFileSystem: Sendable {
    func enumerateImages(at inputDirectory: String, recursive: Bool) throws -> [CLIBatchInput]
    func outputPath(root: String, relativePath: String) -> String
    func createParentDirectory(forOutputPath path: String) throws
}
```

`CLIBatchInput` is a model value with `inputPath` and `relativePath` strings.
The file-system adapter returns a slash-normalized, root-relative `relativePath`
and owns native path joining. Orchestration owns deterministic sorting and
format-driven output-relative-name rewriting, then asks the adapter to turn it
into a native output path and create its parent. Thus Windows separator and
case rules do not leak into model/source files.

The capability value must include supported `CLIOutputFormat`s and optional
features such as face protection and debug artifacts. Before execution,
orchestration rejects an unsupported requested feature with the existing usage
or data-error contract; a Windows backend must never silently ignore an Apple
feature. Apple and Windows backends are also responsible for translating their
native I/O errors through the same backend methods.

## Dependency rules

1. `SeamCarvingCLIModel` must not import `ArgumentParser`, CoreGraphics,
   ImageIO, UniformTypeIdentifiers, `SeamCarvingVision`, or any Apple adapter.
2. Parser-specific types such as `CLIParsedArguments` and
   `ExpressibleByArgument` conformances belong only to
   `SeamCarvingCLIArguments`.
3. `CLIOutputFormat` is model-owned; its `UTType`/encoder implementation
   belongs in an AppleCLI extension.
4. `CLIExitCode` maps model errors itself. Each CLI backend supplies
   `CLIAppleErrorClassifier.exitCode(for:) -> CLIExitCode?` and
   `message(for:) -> String?`; the executable tries it before the model
   classifier. `BatchProcessor` receives the same message classifier callback.
   This preserves `CLIImageIOError`'s data-error result without importing it
   into the model.
5. New platform CLIs consume `SeamCarvingCLIModel` and provide their own
   backend and executable targets. They must not add platform checks to model or
   orchestration source files.
6. `SeamCarvingCLI` keeps source compatibility during this major release via
   deprecated forwarding APIs for `CLIOptions.parse(_:)` and
   `CLIConfiguration.parse(arguments:)`. The facade forwards to
   `SeamCarvingCLIArguments`; these methods are removed only when the facade is
   removed in the next major release.
7. `seamcarve-cli-apple` is an Apple-only product, declared in `Package.swift`
   under a manifest-level macOS availability guard. It must not compile a
   non-functional Windows stub. A future Windows package resolution exposes
   only `seamcarve-cli-windows` under the same user-facing artifact name.
