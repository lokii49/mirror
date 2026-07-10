import XCTest

final class BrainViewUITests: XCTestCase {

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

    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 8) {
        var swipes = 0
        while (!element.exists || !element.isHittable) && swipes < maxSwipes {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.4)
            swipes += 1
        }
    }

    @MainActor
    func testBrainView_seedMixed_showsGraph_andNodeSheet() throws {
        let app = launchApp()

        // 1. Go to Insights tab, open Settings.
        app.tabBars.buttons["Insights"].tap()
        Thread.sleep(forTimeInterval: 1)
        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()
        Thread.sleep(forTimeInterval: 1)

        // 2. Seed mixed sample entries via the debug section.
        let seedButton = app.buttons["Load Sample Entries (Mixed)"]
        scrollUntilHittable(seedButton, in: app, maxSwipes: 12)
        XCTAssertTrue(seedButton.exists, "Debug seed button must exist in DEBUG builds")
        seedButton.tap()
        Thread.sleep(forTimeInterval: 1.5)

        // 3. Relaunch instead of fighting sheet dismissal — entries persist.
        app.terminate()
        Thread.sleep(forTimeInterval: 1)
        app.launch()
        Thread.sleep(forTimeInterval: 2)
        app.tabBars.buttons["Insights"].tap()
        Thread.sleep(forTimeInterval: 1)

        // 4. Open Brain View from the Explore grid.
        let tile = app.staticTexts["Brain View"]
        scrollUntilHittable(tile, in: app, maxSwipes: 10)
        XCTAssertTrue(tile.exists && tile.isHittable, "Brain View tile must be visible")
        snapshot(app, name: "insights_explore_grid")
        tile.tap()

        // 5. Wait for extraction + layout, then capture the graph.
        Thread.sleep(forTimeInterval: 6)
        snapshot(app, name: "brain_view_graph")
        // No nav title by design (dark canvas made the system label
        // unreadable) — check the toolbar controls that replace it instead.
        XCTAssertTrue(app.buttons["3D"].waitForExistence(timeout: 5))

        // 2D toggle check — same graph, flat Canvas renderer.
        let toggle2D = app.buttons["2D"]
        if toggle2D.waitForExistence(timeout: 3) {
            toggle2D.tap()
            Thread.sleep(forTimeInterval: 1)
            snapshot(app, name: "brain_view_2d_graph")
            app.buttons["3D"].tap()
            Thread.sleep(forTimeInterval: 1)
        }

        // 5b. Verify pinch-to-zoom and drag-to-orbit actually move the camera.
        let window = app.windows.firstMatch
        window.pinch(withScale: 2.5, velocity: 2.0)
        Thread.sleep(forTimeInterval: 0.6)
        snapshot(app, name: "brain_view_after_zoom_in")

        window.pinch(withScale: 0.35, velocity: -2.0)
        Thread.sleep(forTimeInterval: 0.6)
        snapshot(app, name: "brain_view_after_zoom_out")

        let dragStart = window.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        let dragEnd = window.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.35))
        dragStart.press(forDuration: 0.05, thenDragTo: dragEnd)
        Thread.sleep(forTimeInterval: 0.6)
        snapshot(app, name: "brain_view_after_orbit")

        window.doubleTap()
        Thread.sleep(forTimeInterval: 0.8)
        snapshot(app, name: "brain_view_after_reset")

        // 6. Probe: layout is deterministic per graph but shifts with the
        // sample data / seed data changes over time, so sweep a grid of
        // points near the hub (nodes cluster around it via gravity) until
        // one lands on a node and opens the detail sheet — proves tap
        // hit-testing resolves correctly without depending on exact
        // on-screen coordinates staying fixed across data changes.
        let askButton = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Ask Mirror about'")).firstMatch
        let offsets: [CGVector] = [
            CGVector(dx: 0.5, dy: 0.5), CGVector(dx: 0.42, dy: 0.44), CGVector(dx: 0.58, dy: 0.44),
            CGVector(dx: 0.42, dy: 0.56), CGVector(dx: 0.58, dy: 0.56), CGVector(dx: 0.5, dy: 0.38),
            CGVector(dx: 0.5, dy: 0.62), CGVector(dx: 0.35, dy: 0.5), CGVector(dx: 0.65, dy: 0.5),
            // Wider ring — the 3D layout spreads nodes further from the hub
            // than the 2D one, so the tight center cluster above can miss.
            CGVector(dx: 0.25, dy: 0.35), CGVector(dx: 0.75, dy: 0.35), CGVector(dx: 0.25, dy: 0.65),
            CGVector(dx: 0.75, dy: 0.65), CGVector(dx: 0.3, dy: 0.25), CGVector(dx: 0.7, dy: 0.25),
            CGVector(dx: 0.35, dy: 0.75), CGVector(dx: 0.65, dy: 0.75), CGVector(dx: 0.5, dy: 0.25),
            CGVector(dx: 0.5, dy: 0.75), CGVector(dx: 0.2, dy: 0.5), CGVector(dx: 0.8, dy: 0.5),
        ]
        for offset in offsets {
            window.coordinate(withNormalizedOffset: offset).tap()
            Thread.sleep(forTimeInterval: 0.8)
            if askButton.waitForExistence(timeout: 1) { break }
        }
        snapshot(app, name: "brain_view_after_center_tap")

        XCTAssertTrue(askButton.exists, "Tapping a node must open its detail sheet (hit-test must resolve through glow sprite children to the named node)")
        snapshot(app, name: "brain_view_node_sheet")
        askButton.tap()
        Thread.sleep(forTimeInterval: 2)
        snapshot(app, name: "brain_view_ask_prefilled")
    }
}
