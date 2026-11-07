import XCTest

/// Sentinel's mood list: a tap on a row's empty space (right of the name) picks that mood. Before
/// 2026-11-07 only the dot and the name took taps (the row's frame was the 80 pt label); this
/// failed on that build and passes with the fix.
final class SentinelMoodRowTapUITests: XCTestCase {
    @MainActor
    func testTapOnRowWhitespacePicksMood() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--forceDisplayMode=sentinel"]
        app.launch()
        let mood = app.buttons["Mood"].firstMatch
        XCTAssertTrue(mood.waitForExistence(timeout: 15))
        mood.tap()
        let row = app.buttons["PEACEFUL"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "panel"; shot.lifetime = .keepAlways; add(shot)
        // The panel is 250 pt wide and its trailing edge lines up with the Mood pill's: tap 24 pt
        // in from that edge, on the row's line, well right of the name.
        let pill = app.buttons["Mood"].firstMatch.frame
        let point = CGVector(dx: pill.maxX - 24, dy: row.frame.midY)
        app.coordinate(withNormalizedOffset: .zero).withOffset(point).tap()
        let picked = NSPredicate(format: "value == %@", "Peaceful")
        expectation(for: picked, evaluatedWith: app.buttons["Mood"].firstMatch)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.buttons["PEACEFUL"].exists, "the panel closes after a pick")
    }
}
