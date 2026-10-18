import XCTest

// App Store screenshot driver (first used for 3.1.3), not a regression test: every test here is skipped unless
// STORE_SCREENSHOTS_DIR is set (TEST_RUNNER_STORE_SCREENSHOTS_DIR on the xcodebuild command line). Each language
// launches the scratch store with StoreDemoSeed's journal in that language; captures go to <dir>/raw,
// <dir>/raw-ipad and <dir>/raw-duo. STORE_LOCALES (comma-separated fastlane locales) narrows the languages.
final class StoreScreenshotTests: XCTestCase {
    private var root: String { (ProcessInfo.processInfo.environment["STORE_SCREENSHOTS_DIR"] ?? "") + "/raw" }

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["STORE_SCREENSHOTS_DIR"] != nil,
                          "App Store screenshot driver; set TEST_RUNNER_STORE_SCREENSHOTS_DIR to run it")
    }

    /// fastlane locale → (seed code, AppleLanguages, AppleLocale, Ask Mirror, Mood Timeline, Brain View titles).
    private let locales: [(String, String, String, String, String, String, String)] = [
        ("en-GB", "en", "en-GB", "en_GB", "Ask Mirror", "Mood Timeline", "Brain View"),
        ("de-DE", "de", "de", "de_DE", "Mirror fragen", "Stimmungsverlauf", "Denkkarte"),
        ("es-ES", "es", "es", "es_ES", "Preguntar a Mirror", "Cronología del estado de ánimo", "Mapa mental"),
        ("fr-FR", "fr", "fr", "fr_FR", "Demander à Mirror", "Chronologie de l'humeur", "Carte mentale"),
        ("it", "it", "it", "it_IT", "Chiedi a Mirror", "Cronologia dell'umore", "Mappa mentale"),
        ("ja", "ja", "ja", "ja_JP", "Mirrorに質問", "ムードタイムライン", "マインドマップ"),
        ("ko", "ko", "ko", "ko_KR", "Mirror에게 질문", "기분 타임라인", "마인드맵"),
        ("pt-BR", "pt", "pt-BR", "pt_BR", "Perguntar ao Mirror", "Linha do tempo de humor", "Mapa mental"),
        ("ru", "ru", "ru", "ru_RU", "Спросить Mirror", "Хронология настроения", "Карта мыслей"),
        ("zh-Hans", "zh", "zh-Hans", "zh_CN", "向 Mirror 提问", "情绪时间线", "思维导图"),
    ]

    func testCaptureStoreScreenshots() throws {
        let only = ProcessInfo.processInfo.environment["STORE_LOCALES"]?.split(separator: ",").map(String.init)
        for loc in locales where only == nil || only!.contains(loc.0) {
            try capture(loc)
        }
    }

    private func launch(_ loc: (String, String, String, String, String, String, String), mode: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.setValue(false, forKey: "idleAnimationWaitEnabled")
        app.launchArguments = ["--uitesting", "--perfSeed=0", "--scratchDraftStorage", "--seedStoreDemo=\(loc.1)", "--forceDisplayMode=\(mode)",
                               "--initialTab=entries", "-AppleLanguages", "(\(loc.2))", "-AppleLocale", loc.3,
                               // Ask's "Smarter search" download offer, already answered.
                               "-smartAskSearchConsent", "declined"]
        app.launch()
        Thread.sleep(forTimeInterval: 5)
        return app
    }

    private func capture(_ loc: (String, String, String, String, String, String, String)) throws {
        let dir = "\(root)/\(loc.0)"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        var app = launch(loc, mode: "classic")
        shot("\(dir)/1-entries.png")

        // Write: the seeded draft (title, line, checklist) with the keyboard and its bar.
        tab(app, 1)
        let tv = app.textViews.firstMatch
        if tv.waitForExistence(timeout: 5), !app.keyboards.element(boundBy: 0).waitForExistence(timeout: 2) {
            tv.tap()
        }
        Thread.sleep(forTimeInterval: 1.5)
        // The keyboard's one-time "slide to type" tip (English run first, so later runs never see it).
        for label in ["Continue", "Weiter"] where app.buttons[label].exists { app.buttons[label].tap(); Thread.sleep(forTimeInterval: 1) }
        shot("\(dir)/2-write.png")
        // The Aa button's label is "Formatting" in each language (Localizable.xcstrings).
        let aa = app.buttons.matching(NSPredicate(format: "label IN %@", Self.formattingLabels)).firstMatch
        if aa.exists { aa.tap() }
        Thread.sleep(forTimeInterval: 1.5)
        shot("\(dir)/2b-write-aa.png")
        app.terminate()
        app = launch(loc, mode: "classic")

        // Insights, then Ask, Mood Timeline and Brain View from its Explore tiles.
        tab(app, 2)
        Thread.sleep(forTimeInterval: 2)
        shot("\(dir)/3-insights.png")
        for (title, name, settle) in [(loc.4, "4-ask", 2.0), (loc.5, "5-mood-timeline", 2.5), (loc.6, "6-brain", 6.0)] {
            if openTile(app, title) {
                Thread.sleep(forTimeInterval: settle)
                // Brain View on its 2D map: every topic labelled and the graph fills the screen (3D reads as a
                // small cluster at this journal size).
                if name == "6-brain", app.buttons["2D"].exists { app.buttons["2D"].tap(); Thread.sleep(forTimeInterval: 3) }
                shot("\(dir)/\(name).png")
                app.navigationBars.buttons.element(boundBy: 0).tap()
                Thread.sleep(forTimeInterval: 1.5)
            }
        }
        app.terminate()

        // Sentinel: the same journal's Briefing.
        app = launch(loc, mode: "sentinel")
        tab(app, 2)
        Thread.sleep(forTimeInterval: 2.5)
        shot("\(dir)/7-sentinel-briefing.png")
        app.terminate()
    }

    /// Brain View's "Zoom out" button in each language (Localizable.xcstrings).
    static let zoomOutLabels = ["Zoom out", "Verkleinern", "Alejar", "Zoom arrière", "Riduci", "縮小", "축소", "Reduzir",
                                "Уменьшить", "缩小"]

    static let formattingLabels = ["Formatting", "Formatierung", "Formato", "Mise en forme", "Formattazione", "書式", "서식",
                                   "Formatação", "Форматирование", "格式"]

    /// iPad slides: Entries with an entry open in the reader, Insights, Write (the template's A, B, E).
    func testCaptureIPadScreenshots() throws {
        let only = ProcessInfo.processInfo.environment["STORE_LOCALES"]?.split(separator: ",").map(String.init)
        XCUIDevice.shared.orientation = .portrait
        for loc in locales where only == nil || only!.contains(loc.0) {
            let dir = "\(root)-ipad/\(loc.0)"
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            var app = launch(loc, mode: "classic")
            shot("\(dir)/ipad-1-entries-list.png")
            let first = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", String(StoreFirstEntry.prefix[loc.1] ?? ""))).firstMatch
            if first.waitForExistence(timeout: 5) { first.tap(); Thread.sleep(forTimeInterval: 2) }
            shot("\(dir)/ipad-1-entries.png")
            app.terminate()
            app = launch(loc, mode: "classic")
            let tabs = Self.tabTitles[loc.1] ?? Self.tabTitles["en"]!
            topTab(app, tabs[2])
            Thread.sleep(forTimeInterval: 2.5)
            shot("\(dir)/ipad-2-insights.png")
            topTab(app, tabs[1])
            // The editor focuses itself on the restored draft. A tap in the page could land on a checklist
            // circle, so only the title line is tapped, and only when the keyboard didn't come up.
            let tv = app.textViews.firstMatch
            if tv.waitForExistence(timeout: 5), !app.keyboards.element(boundBy: 0).waitForExistence(timeout: 3) {
                tv.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)).tap()
            }
            Thread.sleep(forTimeInterval: 2.5)
            shot("\(dir)/ipad-3-write.png")
            let aa = app.buttons.matching(NSPredicate(format: "label IN %@", Self.formattingLabels)).firstMatch
            if aa.exists { aa.tap(); Thread.sleep(forTimeInterval: 1.5) }
            shot("\(dir)/ipad-3-write-aa.png")
            app.terminate()
        }
    }

    /// iPad Write only, `-kb` names: run without switching the simulator's language, because after a switch and
    /// reboot the simulator shows no on-screen keyboard. The status bar is then taken from the switched run.
    func testCaptureIPadWriteScreenshots() throws {
        let only = ProcessInfo.processInfo.environment["STORE_LOCALES"]?.split(separator: ",").map(String.init)
        XCUIDevice.shared.orientation = .portrait
        for loc in locales where only == nil || only!.contains(loc.0) {
            let dir = "\(root)-ipad/\(loc.0)"
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let app = launch(loc, mode: "classic")
            topTab(app, (Self.tabTitles[loc.1] ?? Self.tabTitles["en"]!)[1])
            let tv = app.textViews.firstMatch
            if tv.waitForExistence(timeout: 5), !app.keyboards.element(boundBy: 0).waitForExistence(timeout: 3) {
                tv.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)).tap()
            }
            Thread.sleep(forTimeInterval: 2.5)
            shot("\(dir)/ipad-3-write-kb.png")
            let aa = app.buttons.matching(NSPredicate(format: "label IN %@", Self.formattingLabels)).firstMatch
            if aa.exists { aa.tap(); Thread.sleep(forTimeInterval: 1.5) }
            shot("\(dir)/ipad-3-write-aa-kb.png")
            app.terminate()
        }
    }

    /// iPhone Duo, in the pose it's in (`DUO_POSE`, "open" or "closed"; folding is done by hand in Device Hub,
    /// and a reboot brings back the closed pose). The opened inner display can only be captured from the Mac
    /// (`simctl io screenshot --display=<port>`; `XCUIScreen.main` and plain simctl return black there), so each
    /// shot is a handshake with duo_watch.sh: the test writes `<name>.want` and waits until the watcher has
    /// written `<name>.png` and removed the request.
    func testCaptureDuoScreenshots() throws {
        let env = ProcessInfo.processInfo.environment
        let only = env["STORE_LOCALES"]?.split(separator: ",").map(String.init)
        let pose = env["DUO_POSE"] ?? "open"
        let brainOnly = env["DUO_ONLY"] == "brain", writeOnly = env["DUO_ONLY"] == "write"
        for loc in locales where only == nil || only!.contains(loc.0) {
            let dir = "\(root)-duo/\(loc.0)"
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let tabs = Self.tabTitles[loc.1] ?? Self.tabTitles["en"]!
            let tiles = [(loc.4, "4-ask", 2.0), (loc.5, "5-mood-timeline", 2.5), (loc.6, "6-brain", 6.0)]
            if brainOnly {
                captureDuoTiles(loc, tabs, Array(tiles.suffix(1)), dir, pose)
                continue
            }
            if writeOnly {
                captureDuoWrite(loc, tabs, dir, pose)
                continue
            }

            var app = launch(loc, mode: "classic")
            hostShot(dir, "duo-\(pose)-1-entries")
            let first = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", String(StoreFirstEntry.prefix[loc.1] ?? ""))).firstMatch
            if first.waitForExistence(timeout: 5) { first.tap(); Thread.sleep(forTimeInterval: 2) }
            hostShot(dir, "duo-\(pose)-1-entries-open")
            app.terminate()

            app = launch(loc, mode: "classic")
            topTab(app, tabs[2])
            Thread.sleep(forTimeInterval: 2.5)
            hostShot(dir, "duo-\(pose)-2-insights")
            app.terminate()
            captureDuoTiles(loc, tabs, tiles, dir, pose)

            captureDuoWrite(loc, tabs, dir, pose)
        }
    }

    private func captureDuoWrite(_ loc: (String, String, String, String, String, String, String), _ tabs: [String],
                                 _ dir: String, _ pose: String) {
        let app = launch(loc, mode: "classic")
        topTab(app, tabs[1])
        let tv = app.textViews.firstMatch
        if tv.waitForExistence(timeout: 5), !app.keyboards.element(boundBy: 0).waitForExistence(timeout: 3) {
            tv.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)).tap()
        }
        Thread.sleep(forTimeInterval: 1.5)
        for label in ["Continue", "Weiter"] where app.buttons[label].exists { app.buttons[label].tap(); Thread.sleep(forTimeInterval: 1) }
        Thread.sleep(forTimeInterval: 1)
        hostShot(dir, "duo-\(pose)-3-write")
        let aa = app.buttons.matching(NSPredicate(format: "label IN %@", Self.formattingLabels)).firstMatch
        if aa.exists { aa.tap(); Thread.sleep(forTimeInterval: 1.5) }
        hostShot(dir, "duo-\(pose)-3-write-aa")
        app.terminate()
    }

    /// Explore tiles, a fresh launch each: on the opened Duo the back button sits in the side bar, not a nav bar.
    private func captureDuoTiles(_ loc: (String, String, String, String, String, String, String), _ tabs: [String],
                                 _ tiles: [(String, String, Double)], _ dir: String, _ pose: String) {
        for (title, name, settle) in tiles {
            let app = launch(loc, mode: "classic")
            topTab(app, tabs[2])
            Thread.sleep(forTimeInterval: 2)
            if openTile(app, title, scrollViewSwipe: pose == "open") {
                Thread.sleep(forTimeInterval: settle)
                if name == "6-brain", app.buttons["2D"].exists { app.buttons["2D"].tap(); Thread.sleep(forTimeInterval: 3) }
                // The opened Duo's wide map runs off the bottom edge; one step out fits it.
                if name == "6-brain", pose == "open" {
                    let zoomOut = app.buttons.matching(NSPredicate(format: "label IN %@", Self.zoomOutLabels)).firstMatch
                    if zoomOut.exists { zoomOut.tap(); Thread.sleep(forTimeInterval: 1.5) }
                }
                hostShot(dir, "duo-\(pose)-\(name)")
            }
            app.terminate()
        }
    }

    /// Asks duo_watch.sh on the Mac for a screenshot and waits for it (up to 20 s).
    private func hostShot(_ dir: String, _ name: String) {
        let want = "\(dir)/\(name).want"
        try? FileManager.default.removeItem(atPath: "\(dir)/\(name).png")
        FileManager.default.createFile(atPath: want, contents: nil)
        let deadline = Date().addingTimeInterval(20)
        while FileManager.default.fileExists(atPath: want), Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
    }

    /// Entries, Write and Insights tab titles (Localizable.xcstrings), by seed code.
    private static let tabTitles: [String: [String]] = [
        "en": ["Entries", "Write", "Insights"], "de": ["Einträge", "Schreiben", "Einblicke"],
        "es": ["Entradas", "Escribir", "Perspectivas"], "fr": ["Entrées", "Écrire", "Aperçus"],
        "it": ["Voci", "Scrivi", "Approfondimenti"], "ja": ["エントリー", "書く", "インサイト"],
        "ko": ["항목", "쓰기", "인사이트"], "pt": ["Entradas", "Escrever", "Percepções"],
        "ru": ["Записи", "Написать", "Аналитика"], "zh": ["条目", "写作", "洞察"],
    ]

    /// iPad's top tab bar, by title: by index it also counts the sidebar button and the keyboard bar's buttons.
    private func topTab(_ app: XCUIApplication, _ title: String) {
        let inBar = app.tabBars.buttons[title]
        let button = inBar.exists ? inBar : app.buttons[title].firstMatch
        if button.waitForExistence(timeout: 5) { button.tap() }
        Thread.sleep(forTimeInterval: 1.5)
    }

    private func tab(_ app: XCUIApplication, _ index: Int) {
        let button = app.tabBars.buttons.element(boundBy: index)
        if button.waitForExistence(timeout: 5) { button.tap() }
        Thread.sleep(forTimeInterval: 1.5)
    }

    /// Scrolls Insights until the tile titled `title` can be tapped. On the opened Duo only a swipe on the scroll
    /// view element moves the page (`app.swipeUp` and coordinate drags don't), so `scrollViewSwipe` uses that.
    private func openTile(_ app: XCUIApplication, _ title: String, scrollViewSwipe: Bool = false) -> Bool {
        // A tile is its title text, or (Brain View's dark card on the opened Duo) one button whose label starts with it.
        let candidates = [app.staticTexts[title].firstMatch,
                          app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch]
        for _ in 0..<8 {
            if let tile = candidates.first(where: { $0.exists && $0.isHittable }) { tile.tap(); return true }
            if scrollViewSwipe { app.scrollViews.firstMatch.swipeUp() } else { app.swipeUp(velocity: .slow) }
            Thread.sleep(forTimeInterval: 0.6)
        }
        return false
    }

    private func shot(_ path: String) {
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: path))
    }
}

/// The start of each demo journal's newest entry (StoreDemoSeed), to open it in the iPad reader.
private enum StoreFirstEntry {
    static let prefix: [String: String] = [
        "en": "First week leading", "de": "Erste Woche als", "es": "Primera semana al", "fr": "Première semaine à",
        "it": "Prima settimana alla", "ja": "新しいプロジェクト", "ko": "새 프로젝트를", "pt": "Primeira semana à",
        "ru": "Первая неделя во", "zh": "带领新项目",
    ]
}
