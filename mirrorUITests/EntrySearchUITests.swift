import XCTest

final class EntrySearchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 90
    }

    @MainActor func testClassicArchiveSearch() throws { try checkSearch(mode: "classic", tab: "Entries") }
    @MainActor func testSentinelArchiveSearch() throws { try checkSearch(mode: "sentinel", tab: "Log") }

    @MainActor private func checkSearch(mode: String, tab: String) throws {
        let app = XCUIApplication()
        // Separate synthetic store and fixed key; no deletion or real journal access.
        app.launchArguments = ["--uitesting", "--perfSeed=50", "--forceDisplayMode=\(mode)", "-AppleLanguages", "(en)"]
        app.launch()
        let entriesTab = app.tabBars.buttons[tab]
        XCTAssertTrue(entriesTab.waitForExistence(timeout: 10))
        let dismissCheckIn = app.buttons["Not now"]
        if dismissCheckIn.waitForExistence(timeout: 3) { dismissCheckIn.tap() }
        entriesTab.tap()
        app.buttons["Search entries"].tap()
        let search = app.textFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        search.typeText("\"made coffee\" -noodles")
        let result = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "made coffee")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        // A word search switches the list to one ranked section.
        let ranked = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "best matches")).firstMatch
        XCTAssertTrue(ranked.waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Archive search \(mode)"
        attachment.lifetime = .keepAlways
        add(attachment)
        search.tap()
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "\"made coffee\" -noodles".count))
        search.typeText("has:video")
        let error = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Unsupported filter value")).firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        app.buttons["Search help"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.terminate()
    }
}
