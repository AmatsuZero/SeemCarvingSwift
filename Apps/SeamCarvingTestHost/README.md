# Seam Carving Test Host

This is a minimal iOS host application for running the package's XCTest
targets on a physical device. It intentionally contains no product UI; the
host will become the starting point for the future GUI application.

## Generate the Xcode project

From this directory:

```sh
xcodegen generate
```

The generated `SeamCarvingTestHost.xcodeproj` is ignored because it is a
derived project. Regenerate it after changing `project.yml`.

## Run on a device

Select the `SeamCarvingDeviceTests` scheme and a connected iPad/iPhone in
Xcode, configure the host and test targets with your Apple Development team,
then run the test action. The test bundles host the existing package tests
inside `SeamCarvingTestHost.app`.
