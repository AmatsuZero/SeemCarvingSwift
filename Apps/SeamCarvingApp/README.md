# Seam Carving Apple App

This directory contains the XcodeGen specification for the shared SwiftUI
editor. `SeamCarvingApp` is the single application target for iPhone, iPad,
and Mac Catalyst. The editor uses the same `Sources/Shared` tree on all three
platforms; UIKit services also cover the Catalyst build.

## Generate and build

```sh
xcodegen generate
xcodebuild -project SeamCarvingApp.xcodeproj -scheme SeamCarvingApp \
  -destination 'generic/platform=iOS' build
xcodebuild -project SeamCarvingApp.xcodeproj -scheme SeamCarvingApp \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  CODE_SIGNING_ALLOWED=NO build
```

The generated Xcode project is committed so the app can be opened and built
immediately. Regenerate it with `xcodegen generate` after changing
`project.yml`, then review the generated project diff.

## Launch screen

The iOS launch screen uses `Sources/iOS/LaunchScreen.storyboard`, with a
vector seam-path mark and the `LaunchBackground` named color. The color asset
has light and dark variants; Auto Layout centers the vector mark on every
iPhone and iPad size class. After an iOS build, validate that the compiled app
contains the storyboard with:

```sh
zsh Tests/verify-launch-screen.sh \
  /path/to/Build/Products/Debug-iphoneos/SeamCarving.app
```
