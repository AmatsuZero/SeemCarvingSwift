# Seam Carving Apple App

This directory contains the XcodeGen specification for the shared SwiftUI
editor. `SeamCarvingMac` and `SeamCarvingIOS` use the same `Sources/Shared`
tree and add only thin platform adapters.

## Generate and build

```sh
xcodegen generate
xcodebuild -project SeamCarvingApp.xcodeproj -scheme SeamCarvingMac build
xcodebuild -project SeamCarvingApp.xcodeproj -scheme SeamCarvingIOS \
  -destination 'generic/platform=iOS' build
```

The generated Xcode project is committed so the app can be opened and built
immediately. Regenerate it with `xcodegen generate` after changing
`project.yml`, then review the generated project diff.
