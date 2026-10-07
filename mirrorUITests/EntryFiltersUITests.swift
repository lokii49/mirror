import XCTest

final class EntryFiltersUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 120
    }
    @MainActor func testClassicCombinedFilters() throws { try checkFilters(mode: "classic", tab: "Entries") }
    @MainActor func testSentinelCombinedFilters() throws { try checkFilters(mode: "sentinel", tab: "Log") }

    @MainActor private func checkFilters(mode: String, tab: String) throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--perfSeed=50", "--entryFilterFixture", "--forceDisplayMode=\(mode)", "-AppleLanguages", "(en)"]
        app.launch()
        let entriesTab = app.tabBars.buttons[tab]
        XCTAssertTrue(entriesTab.waitForExistence(timeout: 10))
        if app.buttons["Not now"].waitForExistence(timeout: 3) { app.buttons["Not now"].tap() }
        entriesTab.tap()
        app.buttons["Search entries"].tap()
        let search = app.textFields.firstMatch
        search.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        search.typeText("\"Filter fixture\"")
        let alpha = fixture("Alpha", app: app)
        let beta = fixture("Beta", app: app)
        let gamma = fixture("Gamma", app: app)
        XCTAssertTrue(alpha.waitForExistence(timeout: 5))
        XCTAssertTrue(beta.waitForExistence(timeout: 5))

        // Cancel must discard the draft selection.
        app.buttons["filter.open"].tap()
        tapSwitch("filter.mood.Content", app: app)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(beta.waitForExistence(timeout: 5))

        app.buttons["filter.open"].tap()
        tapSwitch("filter.mood.Content", app: app)
        tapSwitch("filter.mood.Anxious", app: app)
        tapSwitch("filter.tag.work", app: app)
        tapSwitch("filter.tag.travel", app: app)
        let controls = XCTAttachment(screenshot: app.screenshot())
        controls.name = "Archive filter controls \(mode)"
        controls.lifetime = .keepAlways
        add(controls)
        app.buttons["filter.apply"].tap()
        XCTAssertTrue(alpha.waitForExistence(timeout: 5))
        XCTAssertTrue(beta.waitForExistence(timeout: 5))
        XCTAssertTrue(gamma.waitForExistence(timeout: 5))

        app.buttons["filter.open"].tap()
        let tagMatch = app.descendants(matching: .any)["filter.tagMatch"].firstMatch
        reveal(tagMatch, app: app)
        tagMatch.tap()
        app.buttons["All selected tags"].tap()
        app.buttons["filter.apply"].tap()
        XCTAssertTrue(alpha.waitForExistence(timeout: 5))
        let allTags = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "All selected tags:")).firstMatch
        XCTAssertTrue(allTags.waitForExistence(timeout: 5))
        let allAttachment = XCTAttachment(screenshot: app.screenshot())
        allAttachment.name = "All tags applied \(mode)"
        allAttachment.lifetime = .keepAlways
        add(allAttachment)
        waitForRemoval(beta)
        waitForRemoval(gamma)

        app.buttons["filter.open"].tap()
        tapSwitch("filter.photos", app: app)
        tapSwitch("filter.audio", app: app)
        tapSwitch("filter.pinned", app: app)
        app.buttons["filter.apply"].tap()
        XCTAssertTrue(alpha.waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Combined archive filters \(mode)"
        attachment.lifetime = .keepAlways
        add(attachment)

        app.buttons["filter.clearAll"].tap()
        XCTAssertEqual(search.value as? String, mode == "classic" ? "Search entries..." : "scan entries…")
        XCTAssertTrue(beta.waitForExistence(timeout: 5))
        XCTAssertTrue(gamma.waitForExistence(timeout: 5))
        app.terminate()
    }
    @MainActor private func fixture(_ name: String, app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Filter fixture \(name):")).firstMatch
    }
    @MainActor private func tapSwitch(_ identifier: String, app: XCUIApplication) {
        let control = app.switches[identifier]
        reveal(control, app: app)
        XCTAssertTrue(control.waitForExistence(timeout: 3), identifier)
        // SwiftUI exposes the whole Form row as the Switch's accessibility
        // frame on iOS 26. Tap the trailing switch rather than the row's label.
        control.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(control.value as? String, "1", "Switch should be selected: \(identifier)")
    }
    @MainActor private func reveal(_ control: XCUIElement, app: XCUIApplication) {
        for _ in 0..<8 {
            if control.exists && control.isHittable { return }
            app.swipeUp()
        }
    }
    @MainActor private func waitForRemoval(_ element: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }
}
