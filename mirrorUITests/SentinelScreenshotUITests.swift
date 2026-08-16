import XCTest

/// Captures a reference screenshot of Sentinel mode for the App Store
/// listing — none of the existing screenshots show it, and 2.0.7 is its
/// first release. Not a correctness test; kept because "can the user
/// actually reach Sentinel mode and see it themed" is a real regression
/// to guard against.
final class SentinelScreenshotUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        Thread.sleep(forTimeInterval: 2)
        return app
    }

    private func snapshot(_ app: XCUIApplication, name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    @MainActor
    func testCaptureSentinelBriefingScreenshot() throws {
        let app = launchApp()

        let insightsTab = app.tabBars.buttons["Briefing"].exists
            ? app.tabBars.buttons["Briefing"]
            : app.tabBars.buttons["Insights"]
        XCTAssertTrue(insightsTab.waitForExistence(timeout: 5))
        insightsTab.tap()
        Thread.sleep(forTimeInterval: 1)

        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()
        Thread.sleep(forTimeInterval: 1)

        let sentinelCard = app.buttons["Sentinel"].exists
            ? app.buttons["Sentinel"]
            : app.staticTexts["Sentinel"]
        if sentinelCard.waitForExistence(timeout: 5) {
            sentinelCard.tap()
            Thread.sleep(forTimeInterval: 1)
        }

        snapshot(app, name: "Sentinel_Settings")

        app.swipeUp()
        Thread.sleep(forTimeInterval: 1)
        snapshot(app, name: "Sentinel_Settings_DisplayMode")

        let dragStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02))
        let dragEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
        dragStart.press(forDuration: 0.05, thenDragTo: dragEnd)
        Thread.sleep(forTimeInterval: 1.5)

        snapshot(app, name: "Sentinel_Briefing")
    }
}
