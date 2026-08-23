# Catalyst UI and Launch Warning Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the macOS UI layout, consolidate the app onto one iOS + Mac Catalyst application target, and distinguish app-owned startup warnings from Xcode/macOS service noise.

**Architecture:** The iOS application target becomes the single product target for iPhone, iPad, and Mac Catalyst. Shared SwiftUI views and `AppModel` remain the only editor implementation; platform services use UIKit APIs for iOS/Catalyst and are isolated behind small protocols. Native AppKit code is removed from the product target rather than carried forward as a second UI implementation.

**Tech Stack:** SwiftUI, UIKit, Mac Catalyst, PhotosPicker, UIDocumentPicker, XCTest/XCUITest, Xcode project settings, CoreGraphics/ImageIO.

**Spec:** Current app project `Apps/SeamCarvingApp/SeamCarvingApp.xcodeproj`, shared editor sources under `Apps/SeamCarvingApp/Sources/Shared`, and the existing GUI parity plan `docs/superpowers/plans/2026-08-23-gui-cli-parity-and-cli-ergonomics.md`.

## Global Constraints

- There must be one application target for iOS, iPadOS, and Mac Catalyst; do not retain a second native macOS application target.
- The same `ContentView`, `ResizeControlsView`, `MaskToolbarView`, `FaceProtectionControlsView`, `AppModel`, and `ResizeDocument` must be used on all three platforms.
- Use `#if targetEnvironment(macCatalyst)` only for genuine Catalyst differences; do not use `#if os(macOS)` as a proxy for “desktop UI”.
- Keep the existing Core/Apple/Metal behavior and package tests unchanged.
- Do not suppress all process logging with `OS_ACTIVITY_MODE=disable`; only remove app-owned registrations or fix app-owned errors.
- Do not modify or commit the user-owned untracked `CODE_REVIEW.md`.
- Every task adds regression coverage and ends with an independent commit.

## Current findings

- `SeamCarvingApp.xcodeproj` has separate `SeamCarvingIOS` and `SeamCarvingMac` application targets, plus separate platform test targets.
- `ContentView` selects layout using `horizontalSizeClass`, but macOS uses a nested `NavigationSplitView`/`ScrollView`/`Form` structure without explicit sidebar/detail sizing.
- `MacPlatformServices.swift` uses `NSOpenPanel`/`NSSavePanel`; Catalyst cannot use this native AppKit flow as the shared desktop path.
- The project has no AppIntents or shortcut declarations. `com.apple.linkd.autoShortcut`, `FSFindFolder`, and related XPC messages must therefore be verified as system/Xcode diagnostics before changing application code.

---

## Task 1: Reproduce and fix the macOS layout corruption

**Files:**
- Modify: `Apps/SeamCarvingApp/Sources/Shared/ContentView.swift`
- Modify: `Apps/SeamCarvingApp/Sources/Shared/ResizeControlsView.swift`
- Modify: `Apps/SeamCarvingApp/Sources/Shared/FaceProtectionControlsView.swift`
- Modify: `Apps/SeamCarvingApp/Sources/Shared/MaskToolbarView.swift`
- Modify: `Apps/SeamCarvingApp/Sources/Shared/CarveProgressView.swift`
- Test: `Apps/SeamCarvingApp/Tests/EditorUITests.swift`

**Interfaces:**
- Regular-width layout uses an explicit sidebar width range of approximately 280–380 points and a detail view that fills remaining space.
- The sidebar contains one vertical scroll container; nested `Form` instances must be replaced with sections/stacks that do not negotiate an unbounded width inside another scroll container.
- The detail canvas receives a minimum usable width and uses `GeometryReader`/aspect-fit sizing without offsetting the leading edge.

- [ ] **Step 1: Add an XCUITest regression** that launches the macOS target, asserts the import control and canvas placeholder exist, and records non-zero/intersecting frames for sidebar controls and detail content.
- [ ] **Step 2: Run the test against the current macOS target** and capture the failing frame/visibility behavior.
- [ ] **Step 3: Refactor the regular layout** to use explicit `NavigationSplitView` column sizing, one sidebar scroll container, and bounded control sections.
- [ ] **Step 4: Remove duplicate resize buttons** from the sidebar/detail composition unless both are intentionally visible and independently labeled.
- [ ] **Step 5: Run macOS GUI XCTest** with clean DerivedData and verify the placeholder, import button, controls, and resize button are visible without clipping.
- [ ] **Step 6: Commit** with `fix: stabilize desktop editor layout`.

## Task 2: Consolidate application targets into iOS + Mac Catalyst

**Files:**
- Modify: `Apps/SeamCarvingApp/SeamCarvingApp.xcodeproj/project.pbxproj`
- Modify: `Apps/SeamCarvingApp/SeamCarvingApp.xcodeproj/xcshareddata/xcschemes/SeamCarvingIOS.xcscheme`
- Create/modify: one unified app scheme named `SeamCarvingApp`
- Remove from project: native `SeamCarvingMac` application target and its native macOS app scheme
- Modify: `Apps/SeamCarvingApp/Tests/*` test target configuration

**Interfaces:**
- The unified app target keeps the iOS bundle identifier for iOS/iPadOS and uses the Catalyst variant/bundle settings required by Xcode for Mac Catalyst.
- Enable `SUPPORTS_MACCATALYST = YES` and configure `SUPPORTED_PLATFORMS`/SDK-specific settings through Xcode project configuration rather than source duplication.
- Replace separate native Mac and iOS app test targets with a shared app test target that can run on iOS Simulator, iPad device, and Mac Catalyst.

- [ ] **Step 1: Record the existing target/scheme graph** and build settings so the migration can be reviewed without losing signing, package products, or test-host relationships.
- [ ] **Step 2: Add a Catalyst destination build/test configuration** to the existing iOS target before deleting the native Mac target.
- [ ] **Step 3: Move shared app source/test membership** to the unified target and remove duplicate native Mac source/test membership.
- [ ] **Step 4: Rename schemes and update test hosts** so no scheme points to a deleted native Mac product.
- [ ] **Step 5: Build and test the unified target** on iPhone Simulator, iPad Simulator/device where available, and `platform=macOS,variant=Mac Catalyst`.
- [ ] **Step 6: Commit** with `refactor: consolidate app on mac catalyst`.

## Task 3: Replace AppKit-specific services with a Catalyst-safe platform service

**Files:**
- Create: `Apps/SeamCarvingApp/Sources/Shared/PlatformImageServices.swift`
- Modify: `Apps/SeamCarvingApp/Sources/Shared/ContentView.swift`
- Modify: `Apps/SeamCarvingApp/Sources/Shared/AppModel.swift`
- Modify: `Apps/SeamCarvingApp/Sources/Shared/ExportView.swift`
- Modify: `Apps/SeamCarvingApp/Sources/Shared/SeamCarvingApp.swift`
- Remove from target: `Apps/SeamCarvingApp/Sources/macOS/MacPlatformServices.swift`
- Modify/remove: `Apps/SeamCarvingApp/Sources/iOS/IOSPlatformServices.swift`
- Test: `Apps/SeamCarvingApp/Tests/AppModelTests.swift`

**Interfaces:**
- Define a small platform adapter for `openImage`, `importURL`, and `export(data:format:)`; the shared model remains independent of `NSOpenPanel`, `NSSavePanel`, and UIKit presentation details.
- iOS and Catalyst use `PhotosPicker`, `UIDocumentPickerViewController`, `UIDocumentPickerViewController(forExporting:)`, or `ShareLink` as appropriate.
- Image decoding/encoding stays in the shared model/ImageIO layer; platform adapters only select URLs/data and present system UI.
- Replace `#if os(macOS)` branches with `#if canImport(UIKit)` and explicit `#if targetEnvironment(macCatalyst)` where behavior really differs.

- [ ] **Step 1: Add adapter tests** for import cancellation, unsupported content, export cancellation, and successful PNG/JPEG/BMP data handoff.
- [ ] **Step 2: Implement the unified platform adapter** and migrate ContentView/ExportView to it.
- [ ] **Step 3: Remove the native AppKit service from the unified target** and remove the AppKit-only command implementation from the app entry point.
- [ ] **Step 4: Run Mac Catalyst, iPhone, and iPad tests** and verify file/photo import and export/share paths.
- [ ] **Step 5: Commit** with `feat: use unified catalyst platform services`.

## Task 4: Audit and reduce startup warnings without hiding failures

**Files:**
- Inspect/modify: `Apps/SeamCarvingApp/SeamCarvingApp.xcodeproj/project.pbxproj`
- Inspect/modify: `Apps/SeamCarvingApp/Sources/Shared/SeamCarvingApp.swift`
- Inspect: generated Info.plist/build settings for the unified target
- Add: `docs/superpowers/plans/2026-08-23-catalyst-launch-warning-audit.md` or an execution section in this plan

**Interfaces:**
- No AppIntents/shortcut registration is added unless a product requirement explicitly introduces one.
- Native AppKit `CommandGroup` code is not compiled for Catalyst.
- Build settings must not include stale AppIntents metadata phases, shortcut declarations, or invalid generated Info.plist entries.

- [ ] **Step 1: Run the unified Catalyst app with verbose logging** and classify each warning as app-owned, Xcode build-time, CoreSimulator, or macOS service noise.
- [ ] **Step 2: Search project configuration and generated Info.plist** for AppIntents, UIApplicationShortcutItems, shortcut metadata, stale bundle identifiers, and native Mac test-host references.
- [ ] **Step 3: Remove only app-owned causes**, such as stale metadata/build phases or AppKit command code compiled into Catalyst.
- [ ] **Step 4: Re-run on Mac Catalyst and a physical iPad**; verify that import, resize, and export work even if external `linkd.autoShortcut` diagnostics remain.
- [ ] **Step 5: Document unavoidable system/Xcode warnings** with exact OS/Xcode context instead of suppressing all logs.
- [ ] **Step 6: Commit** with `chore: audit catalyst startup diagnostics`.

## Task 5: Final cross-platform acceptance

**Files:**
- Modify: `docs/capability-matrix.md`
- Modify: `README.md`
- Modify: `Apps/SeamCarvingApp/Tests/*`

- [ ] **Step 1: Run package regression:** `swift test --package-path . --parallel`.
- [ ] **Step 2: Run clean Mac Catalyst XCTest** with a dedicated DerivedData and module-cache directory.
- [ ] **Step 3: Run iPhone/iPad Simulator XCTest** and the connected iPad device App XCTest.
- [ ] **Step 4: Run Metal screening on the iPad** and confirm the unified target still selects the expected backend.
- [ ] **Step 5: Verify UI acceptance:** no clipped controls, stable split/stack layouts, image import, mask painting, face preflight, resize/cancel, PNG/JPEG/BMP export, and share/export cancellation.
- [ ] **Step 6: Update the capability matrix** to state that macOS support is Mac Catalyst, not a separate native AppKit target; record any remaining system warnings separately from app failures.
- [ ] **Step 7: Run `git diff --check` and `git status --short`**, ensuring only `CODE_REVIEW.md` remains untracked.
- [ ] **Step 8: Commit** with `test: complete catalyst cross-platform acceptance`.

## Definition of Done

- The screenshot layout issue is fixed and covered by a GUI regression test.
- There is one application target for iOS, iPadOS, and Mac Catalyst, with one shared SwiftUI editor implementation.
- Native AppKit open/save code and duplicate native macOS target are removed from the product path.
- Startup diagnostics have been classified; app-owned causes are fixed, and unavoidable system/Xcode warnings are documented rather than hidden.
- Package tests, Mac Catalyst GUI tests, iOS/iPadOS tests, and available iPad device/Metal tests pass.
