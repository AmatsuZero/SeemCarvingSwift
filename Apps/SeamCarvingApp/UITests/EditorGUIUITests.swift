import XCTest

@MainActor
final class EditorGUIUITests: XCTestCase {
    func testEditorControlsHaveUsableNonOverlappingFrames() {
        let app = XCUIApplication(bundleIdentifier: "com.seamcarving.ios")
        let importControl = app.buttons["editor.importButton"].firstMatch
        app.launch()

        let canvas = app.otherElements["editor.canvas"]
        let resize = app.buttons["Resize"]

        XCTAssertTrue(importControl.waitForExistence(timeout: 10))
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        XCTAssertTrue(resize.waitForExistence(timeout: 10))
        XCTAssertFalse(importControl.frame.isEmpty)
        XCTAssertFalse(canvas.frame.isEmpty)
        XCTAssertFalse(resize.frame.isEmpty)
        XCTAssertFalse(canvas.frame.intersects(resize.frame))
    }
}
