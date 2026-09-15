import XCTest

// Throwaway capture harness for the MirrorNotificationContentExtension design review —
// not a regression test, delete once the screenshots are captured.
final class NudgeNotificationScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCaptureExpandedNudgeClassic() throws {
        try capture(displayMode: "classic", suffix: "classic")
    }

    func testCaptureExpandedNudgeSentinel() throws {
        try capture(displayMode: "sentinel", suffix: "sentinel")
    }

    private func capture(displayMode: String, suffix: String) throws {
        let app = XCUIApplication()
        addUIInterruptionMonitor(withDescription: "Notification permission") { alert in
            let allow = alert.buttons["Allow"]
            if allow.exists { allow.tap(); return true }
            return false
        }
        app.launchArguments = ["--uitesting", "--forceDisplayMode=\(displayMode)", "--scheduleTestNudge"]
        app.launch()
        Thread.sleep(forTimeInterval: 1.5)
        app.tap() // wakes the interruption monitor if a permission alert is up
        Thread.sleep(forTimeInterval: 1)

        XCUIDevice.shared.press(.home)
        // Notification fires 3s after app init — catch the banner while it's still up
        // (it auto-dismisses a few seconds later), rather than navigating to Notification Center.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let banner = springboard.staticTexts["mirror"].firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 6), "nudge banner never appeared")
        attach(name: "01-banner-\(suffix)")

        banner.press(forDuration: 1.3)
        Thread.sleep(forTimeInterval: 1.5)
        attach(name: "02-expanded-\(suffix)")
    }

    private func attach(name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.lifetime = .keepAlways
        attachment.name = name
        add(attachment)
    }
}
