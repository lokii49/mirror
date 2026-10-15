import XCTest

final class mirrorUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        // --clearWriteTestState wipes the draft + all Entry/Insight rows on launch.
        // The draft otherwise survives relaunch (persisted UserDefaults), so
        // without this every test's typed text piles onto the last, breaking
        // cursor-position and panel-layout assumptions in later tests.
        app.launchArguments = ["--uitesting", "--clearWriteTestState"]
        app.launch()
        Thread.sleep(forTimeInterval: 2)
        return app
    }

    private func tapWriteTab(in app: XCUIApplication) {
        app.tabBars.buttons["Write"].tap()
        Thread.sleep(forTimeInterval: 1)
    }

    private func focusEditor(in app: XCUIApplication) -> XCUIElement {
        let tv = app.textViews.firstMatch
        XCTAssertTrue(tv.waitForExistence(timeout: 5))
        // Clear any permission / onboarding dialog BEFORE the first tap — a dialog
        // landing between tap and typeText is the classic "no keyboard focus" flake.
        dismissSystemDialogs(app)
        tv.tap()
        Thread.sleep(forTimeInterval: 0.8)
        dismissSystemDialogs(app)
        // Keyboard up ⇒ the editor has focus. If a dialog ate the first tap, retry.
        if !app.keyboards.element(boundBy: 0).waitForExistence(timeout: 2) {
            tv.tap()
            Thread.sleep(forTimeInterval: 0.6)
        }
        return tv
    }

    /// Open a saved entry for editing from the Entries tab. Entry rows are
    /// `EntryRow` + `.onTapGesture` inside a `List` whose first cell is the
    /// calendar heatmap, so `app.cells.firstMatch` is the heatmap, not an entry —
    /// locate the row by a substring of its text instead.
    private func openEntryForEditing(in app: XCUIApplication, textFragment: String) {
        app.tabBars.buttons["Entries"].tap()
        Thread.sleep(forTimeInterval: 1.5)

        let row = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", textFragment)
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Saved entry must appear in the list")
        row.tap()
        Thread.sleep(forTimeInterval: 1)

        let editBtn = app.buttons["Edit"]
        XCTAssertTrue(editBtn.waitForExistence(timeout: 5), "Edit button must exist on entry detail")
        editBtn.tap()
        Thread.sleep(forTimeInterval: 1)
    }

    private func dismissSystemDialogs(_ app: XCUIApplication) {
        for label in ["Continue", "Got It", "OK", "Allow", "Done"] {
            let btn = app.buttons[label]
            if btn.exists { btn.tap(); Thread.sleep(forTimeInterval: 0.3) }
        }
    }

    private func snapshot(_ app: XCUIApplication, name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    /// Open the formatting panel from the keyboard bar's Aa button ("Formatting").
    /// On iPhone the whole bar hides while the panel is open. Panel is confirmed
    /// open when the paragraph-style row is present.
    @discardableResult
    private func openFormattingPanel(in app: XCUIApplication) -> XCUIElement {
        let aa = app.buttons["Formatting"]
        XCTAssertTrue(aa.waitForExistence(timeout: 5), "Aa (Formatting) button must exist in toolRow")
        aa.tap()
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertTrue(app.buttons["Title"].waitForExistence(timeout: 3), "Panel must open (paragraph row visible)")
        return aa
    }

    /// Close the panel via its own close button. The bar (and its Aa) is hidden
    /// while the panel is open on iPhone, so there is no Aa toggle to tap.
    private func closeFormattingPanel(in app: XCUIApplication) {
        let close = app.buttons["closeFormatPanel"]
        XCTAssertTrue(close.waitForExistence(timeout: 3), "Panel close button must exist")
        close.tap()
        Thread.sleep(forTimeInterval: 0.8)
    }

    /// Apply the checklist paragraph style from the keyboard bar (panel closed).
    /// The Aa panel no longer has a checklist button (Notes layout, 2026-10).
    private func applyChecklist(in app: XCUIApplication) {
        let checklist = app.buttons["keyboardBar.checklist"]
        XCTAssertTrue(checklist.waitForExistence(timeout: 3), "Bar checklist button must exist")
        checklist.tap()
        Thread.sleep(forTimeInterval: 0.5)
    }

    /// Swap the open panel's rows to the color swatches via the color dot.
    private func showColorSwatches(in app: XCUIApplication) {
        let dot = app.buttons["colorPicker"]
        XCTAssertTrue(dot.waitForExistence(timeout: 3), "Panel color dot must exist")
        dot.tap()
        Thread.sleep(forTimeInterval: 0.5)
    }

    // MARK: - Settings: Quick capture via Siri copy (user-reported UI check)

    /// Purely a screenshot capture for visual review — the actual defect (settings copy tells
    /// the user to say "in mirror" when the registered AppShortcut phrase resolves the app name
    /// to "MirrorNotes", CFBundleDisplayName, not the lowercase target name) is confirmed by
    /// reading Info.plist/project.pbxproj, not by anything this test can assert on its own.
    @MainActor
    func testSettings_protocolInputSection_siriCaptureRow_screenshot() throws {
        let app = launchApp()
        app.tabBars.buttons["Insights"].tap()
        Thread.sleep(forTimeInterval: 1)

        app.navigationBars.buttons["person.circle"].tap()
        Thread.sleep(forTimeInterval: 1)

        app.staticTexts["Journal"].tap()
        Thread.sleep(forTimeInterval: 1)

        XCTAssertTrue(app.staticTexts["Quick capture via Siri"].waitForExistence(timeout: 5))
        snapshot(app, name: "settings_protocol_input_siriCaptureRow")
    }

    /// Same row, Sentinel theme — this row's fix went through two rounds without this test:
    /// the first (bottom-aligning the icon) looked fine in Classic but knocked the icon out of
    /// vertical alignment with its title, reported back as looking worse. Sentinel mode renders
    /// this exact same SettingsRowLabel/ProtocolSettingsView code (see CLAUDE.md's Sentinel
    /// mode note: every themed branch is a place the two themes can silently diverge), so a
    /// Classic-only screenshot never would have caught it either way — both need checking.
    @MainActor
    func testSettings_protocolInputSection_siriCaptureRow_sentinel_screenshot() throws {
        let app = launchApp()
        app.tabBars.buttons["Insights"].tap()
        Thread.sleep(forTimeInterval: 1)

        app.navigationBars.buttons["person.circle"].tap()
        Thread.sleep(forTimeInterval: 1)

        let sentinelCard = app.buttons["Sentinel"].exists ? app.buttons["Sentinel"] : app.staticTexts["Sentinel"]
        if sentinelCard.waitForExistence(timeout: 5) {
            sentinelCard.tap()
            Thread.sleep(forTimeInterval: 1)
        }

        app.staticTexts["Protocol"].tap()
        Thread.sleep(forTimeInterval: 1)

        XCTAssertTrue(app.staticTexts["Quick capture via Siri"].waitForExistence(timeout: 5))
        snapshot(app, name: "settings_protocol_input_siriCaptureRow_sentinel")
    }

    // MARK: - Talk It Out model gate (writing-roadmap.md Tier 2 / FM-availability fix)

    /// Live confirmation for the FM-capable side of the mirrorApp.modelAvailable() fix — the
    /// user reporting the original bug has no Apple Intelligence-eligible device, and this
    /// session's Xcode 27 beta simulator happens to report Foundation Models as available (see
    /// writing-roadmap.md Tier 2's "surprising finding"), so it stands in for one. Before the
    /// fix, LocalLLMService.isModelAvailable being true via FM wasn't enough — the chip's own
    /// gate went through the same code path as nudge/digest/report, so this also stands in for
    /// those. Tapping "Talk it out" must reach the real TalkItOutView directly, never the
    /// "AI model needed" download card, since FM alone should be sufficient.
    @MainActor
    func testTalkItOut_foundationModelsAvailable_skipsModelDownloadGate() throws {
        let app = launchApp()
        tapWriteTab(in: app)

        let starterChipLabel = "Need a starting point? Talk it out, or use a template"
        let starterChip = app.buttons[starterChipLabel].exists ? app.buttons[starterChipLabel] : app.otherElements[starterChipLabel]
        XCTAssertTrue(starterChip.waitForExistence(timeout: 5), "Starter chip must exist on a blank new entry")
        starterChip.tap()
        Thread.sleep(forTimeInterval: 0.5)

        let talkItOutMenuItem = app.buttons["Talk it out"].exists ? app.buttons["Talk it out"] : app.buttons["TALK IT OUT"]
        XCTAssertTrue(talkItOutMenuItem.waitForExistence(timeout: 3), "Talk it out menu item must exist")
        talkItOutMenuItem.tap()
        Thread.sleep(forTimeInterval: 1.5)

        XCTAssertFalse(
            app.staticTexts["AI MODEL NEEDED"].exists || app.staticTexts["AI model needed"].exists,
            "Foundation Models is available in this environment — Talk It Out must not show the Gemma-download gate"
        )
        snapshot(app, name: "talkItOut_foundationModels_skipsDownloadGate")
    }

    // MARK: - Top Bar Toolbar: New Draft (entry == nil)

    /// Empty draft → both "Discard draft" and "Save entry" are disabled.
    @MainActor
    func testToolbar_newDraft_emptyState_bothButtonsDisabled() throws {
        let app = launchApp()
        tapWriteTab(in: app)

        let discardBtn = app.buttons["Discard draft"]
        let saveBtn    = app.buttons["Save entry"]

        XCTAssertTrue(discardBtn.waitForExistence(timeout: 5), "Discard draft must exist in new draft mode")
        XCTAssertTrue(saveBtn.waitForExistence(timeout: 5),    "Save entry must exist")

        XCTAssertFalse(discardBtn.isEnabled, "Discard draft must be disabled when no draft content")
        XCTAssertFalse(saveBtn.isEnabled,    "Save entry must be disabled when no draft content")

        snapshot(app, name: "toolbar_newdraft_empty")
    }

    /// After typing → both buttons become enabled.
    @MainActor
    func testToolbar_newDraft_withContent_bothButtonsEnabled() throws {
        let app = launchApp()
        tapWriteTab(in: app)

        let tv = focusEditor(in: app)
        tv.typeText("Today was a good day")
        Thread.sleep(forTimeInterval: 0.5)

        let discardBtn = app.buttons["Discard draft"]
        let saveBtn    = app.buttons["Save entry"]

        XCTAssertTrue(discardBtn.isEnabled, "Discard draft must be enabled when draft has content")
        XCTAssertTrue(saveBtn.isEnabled,    "Save entry must be enabled when draft has content")

        snapshot(app, name: "toolbar_newdraft_with_content")
    }

    /// Discard draft clears the editor immediately. `startDeleteWithUndo` now
    /// clears the draft on the first tap and runs a 10s undo countdown, so the
    /// discard button stays enabled (as the undo affordance) — assert on the
    /// editor content, not the button state.
    @MainActor
    func testToolbar_discardDraft_clearsEditor() throws {
        let app = launchApp()
        tapWriteTab(in: app)

        let tv = focusEditor(in: app)
        tv.typeText("Text to discard")
        Thread.sleep(forTimeInterval: 0.5)

        app.buttons["Discard draft"].tap()
        Thread.sleep(forTimeInterval: 1.0)

        let editorText = tv.value as? String ?? ""
        XCTAssertTrue(
            editorText.isEmpty || editorText == tv.placeholderValue,
            "Editor must be empty immediately after discard. Got: \"\(editorText)\""
        )
        XCTAssertFalse(app.buttons["Save entry"].isEnabled, "Save must be disabled once the draft is cleared")

        snapshot(app, name: "toolbar_after_discard")
    }

    // MARK: - Top Bar Toolbar: Edit Existing Entry (entry != nil)

    /// Create an entry, open it for editing; toolbar shows "Delete entry" (not "Discard draft").
    @MainActor
    func testToolbar_editEntry_showsDeleteEntryLabel() throws {
        let app = launchApp()
        tapWriteTab(in: app)

        // Create a new entry
        let tv = focusEditor(in: app)
        tv.typeText("Entry for edit toolbar test")
        Thread.sleep(forTimeInterval: 0.5)
        app.buttons["Save entry"].tap()
        Thread.sleep(forTimeInterval: 1.5)

        openEntryForEditing(in: app, textFragment: "edit toolbar test")

        // In edit mode: "Delete entry" replaces "Discard draft"
        let deleteEntry  = app.buttons["Delete entry"]
        let discardDraft = app.buttons["Discard draft"]

        XCTAssertTrue(deleteEntry.waitForExistence(timeout: 5),  "Delete entry must exist in edit mode")
        XCTAssertFalse(discardDraft.exists,                       "Discard draft must NOT exist in edit mode")
        XCTAssertTrue(deleteEntry.isEnabled,                      "Delete entry is always enabled in edit mode")
        XCTAssertTrue(app.buttons["Save entry"].isEnabled,        "Save entry must be enabled in edit mode")

        snapshot(app, name: "toolbar_edit_entry_mode")
    }

    /// Delete entry → same immediate-clear + undo-countdown as discard
    /// (`startDeleteWithUndo`, `WriteView+Actions.swift:195`), not a
    /// confirmation dialog — "Delete entry" and "Discard draft" share the
    /// same handler (`WriteView+Subviews.swift:307,333`).
    @MainActor
    func testToolbar_editEntry_deleteButtonShowsUndoCountdown() throws {
        let app = launchApp()
        tapWriteTab(in: app)

        let tv = focusEditor(in: app)
        tv.typeText("Entry to delete")
        Thread.sleep(forTimeInterval: 0.5)
        app.buttons["Save entry"].tap()
        Thread.sleep(forTimeInterval: 1.5)

        openEntryForEditing(in: app, textFragment: "Entry to delete")

        app.buttons["Delete entry"].tap()
        Thread.sleep(forTimeInterval: 0.5)

        // Editor clears immediately; the undo affordance appears instead of a dialog.
        let editorText = tv.value as? String ?? ""
        XCTAssertTrue(
            editorText.isEmpty || editorText == tv.placeholderValue,
            "Editor must be empty immediately after Delete entry. Got: \"\(editorText)\""
        )
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 3), "Undo button must appear")
        XCTAssertTrue(app.staticTexts["Entry will be deleted"].exists, "Delete-pending banner must appear")

        snapshot(app, name: "toolbar_delete_undo_countdown")

        // Undo to restore the entry, avoiding side effects in subsequent tests.
        app.buttons["Undo"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        let restoredText = tv.value as? String ?? ""
        XCTAssertTrue(restoredText.contains("Entry to delete"), "Undo must restore the entry text")
    }

    // MARK: - ToolRow (keyboard accessory bar)

    /// ToolRow appears when the editor is focused (keyboard visible).
    @MainActor
    func testToolRow_appearsOnEditorFocus() throws {
        let app = launchApp()
        tapWriteTab(in: app)

        _ = focusEditor(in: app)

        let textFormatting = app.buttons["Formatting"]
        XCTAssertTrue(
            textFormatting.waitForExistence(timeout: 5),
            "Text formatting (Aa) button must appear in toolRow when keyboard is visible"
        )
        // The attach menu only renders in the bar while the keyboard is up — a
        // second anchor for toolRow presence.
        XCTAssertTrue(app.buttons["keyboardBar.attach"].exists, "Attach menu must be in the toolRow")

        snapshot(app, name: "toolrow_visible_with_keyboard")
    }

    /// Dismissing the keyboard hides the toolRow.
    @MainActor
    func testToolRow_hidesWhenKeyboardDismissed() throws {
        let app = launchApp()
        tapWriteTab(in: app)
        _ = focusEditor(in: app)

        let aaBtn = app.buttons["Formatting"]
        XCTAssertTrue(aaBtn.waitForExistence(timeout: 5))

        // No dismiss button in the bar anymore: drag the editor down into the keyboard, which
        // .scrollDismissesKeyboard(.interactively) needs (a short swipe mid-editor never reaches it).
        let start = app.textViews.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.97))
        start.press(forDuration: 0.05, thenDragTo: end)
        Thread.sleep(forTimeInterval: 0.8)

        XCTAssertFalse(aaBtn.exists, "Aa button (toolRow) must disappear when keyboard is dismissed")

        snapshot(app, name: "toolrow_hidden_after_dismiss")
    }

    // MARK: - ToolRow: Aa Button (formatting panel toggle)

    /// Aa tap opens the formatting panel; the panel's close button closes it.
    @MainActor
    func testToolRow_aaButton_togglesFormattingPanel() throws {
        let app = launchApp()
        tapWriteTab(in: app)
        let tv = focusEditor(in: app)
        tv.typeText("Some text")
        Thread.sleep(forTimeInterval: 0.3)

        let aaBtn = app.buttons["Formatting"]
        XCTAssertTrue(aaBtn.waitForExistence(timeout: 5))

        // Open panel
        aaBtn.tap()
        Thread.sleep(forTimeInterval: 0.8)

        // Panel rows: paragraph style buttons must appear
        XCTAssertTrue(
            app.buttons["Title"].waitForExistence(timeout: 3),
            "Title paragraph button must appear when formatting panel opens"
        )
        XCTAssertTrue(app.buttons["Heading"].exists)
        XCTAssertTrue(app.buttons["Body"].exists)

        snapshot(app, name: "aa_panel_open")

        // Close panel via its close button — the bar (Aa included) is hidden while open
        app.buttons["closeFormatPanel"].tap()
        Thread.sleep(forTimeInterval: 0.8)

        XCTAssertFalse(app.buttons["Title"].exists, "Panel must close when its close button is tapped")
        XCTAssertTrue(app.buttons["Formatting"].exists, "Bar Aa button must return after the panel closes")

        snapshot(app, name: "aa_panel_closed")
    }

    /// Closing the panel restores the real keyboard. On iPhone the panel is the
    /// text view's `inputView`, so dismissing it (its `closeFormatPanel` button)
    /// must bring the keyboard straight back — the bar only renders while the
    /// keyboard is up, so its return is the proof. This is the closest automated
    /// check of the 2.1 iPhone keyboard-swap contract.
    @MainActor
    func testFormattingPanel_aaButton_closesPanelAndRestoresKeyboard() throws {
        let app = launchApp()
        tapWriteTab(in: app)
        let tv = focusEditor(in: app)
        tv.typeText("Close and restore keyboard")
        Thread.sleep(forTimeInterval: 0.3)

        // Baseline: system keyboard is up before opening the panel.
        XCTAssertTrue(app.keyboards.element(boundBy: 0).exists, "Keyboard should be up before opening the panel")

        openFormattingPanel(in: app)

        // Panel is up as the inputView — the system keyboard is swapped out.
        XCTAssertFalse(app.keyboards.element(boundBy: 0).exists, "System keyboard must be gone while the panel is shown")

        app.buttons["closeFormatPanel"].tap()
        Thread.sleep(forTimeInterval: 0.8)

        XCTAssertFalse(app.buttons["Title"].exists, "Panel must close")
        XCTAssertTrue(app.buttons["Formatting"].exists, "Bar Aa button must be back after the panel closes")
        XCTAssertTrue(
            app.keyboards.element(boundBy: 0).waitForExistence(timeout: 3),
            "System keyboard must return after the panel closes (2.1 iPhone inputView-swap contract)"
        )

        snapshot(app, name: "panel_closed_keyboard_restored")
    }

    // MARK: - FormattingPanel: Checklist apply + active state

    /// Applying checklist from the keyboard bar surfaces the contextual
    /// Checklist actions menu in the bar (the panel has no checklist controls
    /// since the Notes-style redesign, 2026-10).
    @MainActor
    func testFormattingPanel_checklistButton_appliesAndShowsBulkOps() throws {
        let app = launchApp()
        tapWriteTab(in: app)
        let tv = focusEditor(in: app)
        tv.typeText("Buy milk")
        Thread.sleep(forTimeInterval: 0.5)
        dismissSystemDialogs(app)

        applyChecklist(in: app)

        // A long press on the bar's Checklist button opens the four actions.
        let actions = app.buttons["keyboardBar.checklist"]
        XCTAssertTrue(actions.waitForExistence(timeout: 3), "Checklist button must stay in the bar")
        actions.press(forDuration: 0.8)
        XCTAssertTrue(app.buttons["Check All"].waitForExistence(timeout: 3), "Menu must list Check All")
        XCTAssertTrue(app.buttons["Delete Done"].exists, "Menu must list Delete Done")
        app.buttons["Check All"].tap()
        XCTAssertTrue(app.buttons["keyboardBar.checklist"].exists, "Bar checklist button must remain after activation")

        snapshot(app, name: "panel_checklist_active_state")
    }

    // MARK: - FormattingPanel: Paragraph Styles

    /// All 5 paragraph style buttons present in panel.
    @MainActor
    func testFormattingPanel_paragraphStyleRow_allButtonsPresent() throws {
        let app = launchApp()
        tapWriteTab(in: app)
        let tv = focusEditor(in: app)
        tv.typeText("Style test")
        Thread.sleep(forTimeInterval: 0.3)

        app.buttons["Formatting"].tap()
        Thread.sleep(forTimeInterval: 0.8)

        for label in ["Title", "Heading", "Subheading", "Body", "Code"] {
            XCTAssertTrue(
                app.buttons[label].waitForExistence(timeout: 3),
                "\(label) button must be present in formatting panel"
            )
        }

        snapshot(app, name: "panel_paragraph_row")
    }

    /// Tap Title → only Title is active; tap Body → Body is active again.
    @MainActor
    func testFormattingPanel_paragraphStyle_titleThenBody() throws {
        let app = launchApp()
        tapWriteTab(in: app)
        let tv = focusEditor(in: app)
        tv.typeText("Heading line")
        Thread.sleep(forTimeInterval: 0.3)

        let aaBtn = app.buttons["Formatting"]
        aaBtn.tap()
        Thread.sleep(forTimeInterval: 0.8)

        app.buttons["Title"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        snapshot(app, name: "panel_title_selected")

        // Re-open panel (Aa toggles closed after tap, or panel stays open)
        // Panel stays open — verify Title button is now accented via screenshot
        // Switch back to Body
        app.buttons["Body"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        snapshot(app, name: "panel_body_reselected")
    }

    /// Cycle through all paragraph styles — each tap doesn't crash, buttons remain tappable.
    @MainActor
    func testFormattingPanel_paragraphStyle_cycleThroughAll() throws {
        let app = launchApp()
        tapWriteTab(in: app)
        let tv = focusEditor(in: app)
        tv.typeText("Cycle styles")
        Thread.sleep(forTimeInterval: 0.3)

        app.buttons["Formatting"].tap()
        Thread.sleep(forTimeInterval: 0.8)

        for label in ["Title", "Heading", "Subheading", "Code", "Body"] {
            // "Code" is the rightmost item in the paragraph-style row's horizontal
            // ScrollView — a synthetic tap doesn't auto-scroll like VoiceOver does,
            // so it's off-screen with a degenerate frame. Even reading `.isHittable`
            // on it throws ("Activation point invalid"), so scroll unconditionally
            // *before* touching the Code element at all: drag from "Subheading"
            // (the previous, still-hittable button in the same row) to bring Code
            // into view.
            if label == "Code" {
                let anchor = app.buttons["Subheading"]
                if anchor.exists {
                    let start = anchor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                    start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: -250, dy: 0)))
                    Thread.sleep(forTimeInterval: 0.4)
                }
            }
            let btn = app.buttons[label]
            XCTAssertTrue(btn.waitForExistence(timeout: 3))
            btn.tap()
            Thread.sleep(forTimeInterval: 0.3)
        }

        snapshot(app, name: "panel_paragraph_cycle_done")
    }

    // MARK: - FormattingPanel: Inline Styles

    /// All 4 inline style buttons present.
    @MainActor
    func testFormattingPanel_inlineStyleRow_allButtonsPresent() throws {
        let app = launchApp()
        tapWriteTab(in: app)
        let tv = focusEditor(in: app)
        tv.typeText("Inline test")
        Thread.sleep(forTimeInterval: 0.3)

        app.buttons["Formatting"].tap()
        Thread.sleep(forTimeInterval: 0.8)

        for label in ["B", "I", "U", "S"] {
            XCTAssertTrue(
                app.buttons[label].waitForExistence(timeout: 3),
                "\(label) inline button must be present"
            )
        }

        snapshot(app, name: "panel_inline_row")
    }

    /// Bold toggle: tap B twice — on then off. Panel stays open; button remains tappable.
    @MainActor
    func testFormattingPanel_bold_toggleOnOff() throws {
        let app = launchApp()
        tapWriteTab(in: app)
        let tv = focusEditor(in: app)
        tv.typeText("Toggle bold")
        Thread.sleep(forTimeInterval: 0.3)

        app.buttons["Formatting"].tap()
        Thread.sleep(forTimeInterval: 0.8)

        let boldBtn = app.buttons["B"]
        XCTAssertTrue(boldBtn.waitForExistence(timeout: 3))

        boldBtn.tap()
        Thread.sleep(forTimeInterval: 0.4)
        snapshot(app, name: "panel_bold_on")

        boldBtn.tap()
        Thread.sleep(forTimeInterval: 0.4)
        snapshot(app, name: "panel_bold_off")

        XCTAssertTrue(boldBtn.exists, "Bold button must still exist after toggling off")
    }

    /// Multiple inline styles active simultaneously (bold + italic + underline).
    @MainActor
    func testFormattingPanel_inlineStyles_multipleCombinations() throws {
        let app = launchApp()
        tapWriteTab(in: app)
        let tv = focusEditor(in: app)
        tv.typeText("Multi style")
        Thread.sleep(forTimeInterval: 0.3)

        app.buttons["Formatting"].tap()
        Thread.sleep(forTimeInterval: 0.8)

        // Activate Bold, Italic, Underline
        for label in ["B", "I", "U"] {
            let btn = app.buttons[label]
            XCTAssertTrue(btn.waitForExistence(timeout: 3))
            btn.tap()
            Thread.sleep(forTimeInterval: 0.3)
        }
        snapshot(app, name: "panel_bold_italic_underline_active")

        // Deactivate all three
        for label in ["B", "I", "U"] {
            app.buttons[label].tap()
            Thread.sleep(forTimeInterval: 0.3)
        }
        snapshot(app, name: "panel_all_inline_deactivated")
    }

    /// Strikethrough toggle works independently of other inline styles.
    @MainActor
    func testFormattingPanel_strikethrough_togglesIndependently() throws {
        let app = launchApp()
        tapWriteTab(in: app)
        let tv = focusEditor(in: app)
        tv.typeText("Strike this")
        Thread.sleep(forTimeInterval: 0.3)

        app.buttons["Formatting"].tap()
        Thread.sleep(forTimeInterval: 0.8)

        let sBtn = app.buttons["S"]
        XCTAssertTrue(sBtn.waitForExistence(timeout: 3))
        sBtn.tap()
        Thread.sleep(forTimeInterval: 0.3)
        snapshot(app, name: "panel_strikethrough_on")

        sBtn.tap()
        Thread.sleep(forTimeInterval: 0.3)
        snapshot(app, name: "panel_strikethrough_off")

        XCTAssertTrue(sBtn.exists)
    }

    // MARK: - FormattingPanel: List Buttons

    /// All list-type buttons present in panel.
    @MainActor
    func testFormattingPanel_listRow_allButtonsPresent() throws {
        let app = launchApp()
        tapWriteTab(in: app)
        let tv = focusEditor(in: app)
        tv.typeText("List test")
        Thread.sleep(forTimeInterval: 0.3)

        app.buttons["Formatting"].tap()
        Thread.sleep(forTimeInterval: 0.8)

        // Checklist moved to the keyboard bar (`keyboardBar.checklist`); quote joined this row.
        for icon in ["list.bullet", "list.dash", "list.number", "decrease.indent", "increase.indent", "blockQuote"] {
            XCTAssertTrue(
                app.buttons[icon].waitForExistence(timeout: 3),
                "\(icon) list button must be present"
            )
        }

        snapshot(app, name: "panel_list_row")
    }

    /// Tapping bulleted list then dashed list — only one active at a time.
    @MainActor
    func testFormattingPanel_listTypes_switchBetweenTypes() throws {
        let app = launchApp()
        tapWriteTab(in: app)
        let tv = focusEditor(in: app)
        tv.typeText("Switch list types")
        Thread.sleep(forTimeInterval: 0.3)

        app.buttons["Formatting"].tap()
        Thread.sleep(forTimeInterval: 0.8)

        app.buttons["list.bullet"].tap()
        Thread.sleep(forTimeInterval: 0.4)
        snapshot(app, name: "panel_bulleted_active")

        app.buttons["list.dash"].tap()
        Thread.sleep(forTimeInterval: 0.4)
        snapshot(app, name: "panel_dashed_active")

        app.buttons["list.number"].tap()
        Thread.sleep(forTimeInterval: 0.4)
        snapshot(app, name: "panel_numbered_active")
    }

    // MARK: - FormattingPanel: Bulk Ops (contextual — checklist only)

    /// Bulk ops row is NOT present when cursor is on regular body text.
    @MainActor
    func testFormattingPanel_bulkOps_hiddenOnBodyText() throws {
        let app = launchApp()
        tapWriteTab(in: app)
        let tv = focusEditor(in: app)
        tv.typeText("Regular body text")
        Thread.sleep(forTimeInterval: 0.3)

        // Checklist actions live in the keyboard bar now (panel closed).
        XCTAssertTrue(app.buttons["keyboardBar.checklist"].waitForExistence(timeout: 5), "Bar must be up")
        XCTAssertEqual(app.buttons.matching(identifier: "keyboardBar.checklist").count, 1, "One checklist button, no second actions icon")
        XCTAssertFalse(app.buttons["Check All"].exists,   "Check All must not appear on body text")
        XCTAssertFalse(app.buttons["Uncheck All"].exists, "Uncheck All must not appear on body text")
        XCTAssertFalse(app.buttons["Delete Done"].exists, "Delete Done must not appear on body text")
        XCTAssertFalse(app.buttons["Sort Done"].exists,   "Sort Done must not appear on body text")

        snapshot(app, name: "panel_no_bulk_ops_on_body")
    }

    /// Checklist actions are a long press on the keyboard bar's Checklist button (panel closed):
    /// open the menu, return the action.
    @MainActor
    private func checklistAction(_ name: String, in app: XCUIApplication) -> XCUIElement {
        let checklist = app.buttons["keyboardBar.checklist"]
        if checklist.waitForExistence(timeout: 3) { checklist.press(forDuration: 0.8) }
        return app.buttons[name]
    }

    /// The bar's bulk-ops menu is still present after the panel is opened and
    /// closed with the cursor left on a checklist line.
    @MainActor
    func testFormattingPanel_bulkOps_appearOnChecklistLine() throws {
        let app = launchApp()
        tapWriteTab(in: app)
        let tv = focusEditor(in: app)
        tv.typeText("Buy milk")
        Thread.sleep(forTimeInterval: 0.5)
        dismissSystemDialogs(app)

        applyChecklist(in: app)           // checklist applied from the bar
        openFormattingPanel(in: app)      // bar hides while the panel is open
        closeFormattingPanel(in: app)     // bar back — activeParagraphStyle must still be checklist

        let actions = app.buttons["keyboardBar.checklist"]
        XCTAssertTrue(actions.waitForExistence(timeout: 3), "Checklist button must be in the bar")
        actions.press(forDuration: 0.8)
        XCTAssertTrue(app.buttons["Check All"].waitForExistence(timeout: 3),   "Check All must appear")
        XCTAssertTrue(app.buttons["Uncheck All"].waitForExistence(timeout: 3), "Uncheck All must appear")
        XCTAssertTrue(app.buttons["Delete Done"].waitForExistence(timeout: 3), "Delete Done must appear")
        XCTAssertTrue(app.buttons["Sort Done"].waitForExistence(timeout: 3),   "Sort Done must appear")

        snapshot(app, name: "panel_bulk_ops_visible_on_checklist")
    }

    /// Bulk ops: Check All → Sort Done → Uncheck All full flow.
    @MainActor
    func testFormattingPanel_bulkOps_fullFlow() throws {
        let app = launchApp()
        tapWriteTab(in: app)
        let tv = focusEditor(in: app)
        tv.typeText("Buy groceries")
        Thread.sleep(forTimeInterval: 0.5)
        dismissSystemDialogs(app)

        applyChecklist(in: app)

        // Add more checklist items (Enter continues checklist style)
        tv.typeText("\nPick up kids\nPay bills")
        Thread.sleep(forTimeInterval: 0.5)

        let checkAll = checklistAction("Check All", in: app)
        XCTAssertTrue(checkAll.waitForExistence(timeout: 3))
        checkAll.tap()
        Thread.sleep(forTimeInterval: 0.5)
        snapshot(app, name: "bulk_after_check_all")

        let sortDone = checklistAction("Sort Done", in: app)
        XCTAssertTrue(sortDone.waitForExistence(timeout: 3))
        sortDone.tap()
        Thread.sleep(forTimeInterval: 0.5)
        snapshot(app, name: "bulk_after_sort_done")

        let uncheckAll = checklistAction("Uncheck All", in: app)
        XCTAssertTrue(uncheckAll.waitForExistence(timeout: 3))
        uncheckAll.tap()
        Thread.sleep(forTimeInterval: 0.5)
        snapshot(app, name: "bulk_after_uncheck_all")
    }

    /// Delete Done removes all checked items.
    @MainActor
    func testFormattingPanel_bulkOps_deleteDone() throws {
        let app = launchApp()
        tapWriteTab(in: app)
        let tv = focusEditor(in: app)
        tv.typeText("Item one")
        Thread.sleep(forTimeInterval: 0.5)
        dismissSystemDialogs(app)

        applyChecklist(in: app)

        // Add second checklist item
        tv.typeText("\nItem two")
        Thread.sleep(forTimeInterval: 0.3)

        let checkAll = checklistAction("Check All", in: app)
        XCTAssertTrue(checkAll.waitForExistence(timeout: 3))
        checkAll.tap()
        Thread.sleep(forTimeInterval: 0.5)
        snapshot(app, name: "bulk_before_delete_done")

        let deleteDone = checklistAction("Delete Done", in: app)
        XCTAssertTrue(deleteDone.waitForExistence(timeout: 3))
        deleteDone.tap()
        Thread.sleep(forTimeInterval: 0.5)
        snapshot(app, name: "bulk_after_delete_done")
    }

    // MARK: - FormattingPanel: Highlight Colors

    /// All 5 color swatches plus the clear (xmark) button are present.
    @MainActor
    func testFormattingPanel_highlights_clearButtonPresent() throws {
        let app = launchApp()
        tapWriteTab(in: app)
        let tv = focusEditor(in: app)
        tv.typeText("Highlight test")
        Thread.sleep(forTimeInterval: 0.3)

        app.buttons["Formatting"].tap()
        Thread.sleep(forTimeInterval: 0.8)
        showColorSwatches(in: app)

        // Clear highlight button uses "xmark" SF symbol
        // Identifier stays "xmark" (audit 3.1 gave it a real VoiceOver label,
        // "No highlight", so a label-based lookup no longer matches).
        let clearBtn = app.buttons["xmark"]
        XCTAssertTrue(clearBtn.waitForExistence(timeout: 3), "Clear highlight (xmark) button must exist")

        snapshot(app, name: "panel_highlight_row")
    }

    /// Tapping clear highlight button doesn't crash and panel stays open.
    @MainActor
    func testFormattingPanel_highlights_clearHighlight() throws {
        let app = launchApp()
        tapWriteTab(in: app)
        let tv = focusEditor(in: app)
        tv.typeText("Text to highlight")
        Thread.sleep(forTimeInterval: 0.3)

        app.buttons["Formatting"].tap()
        Thread.sleep(forTimeInterval: 0.8)
        showColorSwatches(in: app)

        // Identifier stays "xmark" (audit 3.1 gave it a real VoiceOver label,
        // "No highlight", so a label-based lookup no longer matches).
        let clearBtn = app.buttons["xmark"]
        XCTAssertTrue(clearBtn.waitForExistence(timeout: 3))
        clearBtn.tap()
        Thread.sleep(forTimeInterval: 0.4)

        // Panel must still be open after clearing highlight (back from the swatches)
        XCTAssertTrue(app.buttons["colorsBack"].exists, "Color swatches must stay up after clearing highlight")
        app.buttons["colorsBack"].tap()
        Thread.sleep(forTimeInterval: 0.4)
        XCTAssertTrue(app.buttons["Title"].waitForExistence(timeout: 3), "Panel must remain open after clearing highlight")

        snapshot(app, name: "panel_after_clear_highlight")
    }

    /// Each highlight color cell is tappable (5 colors by index — no accessibility labels, tested via tap).
    @MainActor
    func testFormattingPanel_highlights_colorCellsTappable() throws {
        let app = launchApp()
        tapWriteTab(in: app)
        let tv = focusEditor(in: app)
        tv.typeText("Color highlight test")
        Thread.sleep(forTimeInterval: 0.3)

        app.buttons["Formatting"].tap()
        Thread.sleep(forTimeInterval: 0.8)
        showColorSwatches(in: app)

        // Identifier stays "xmark" (audit 3.1 gave it a real VoiceOver label,
        // "No highlight", so a label-based lookup no longer matches).
        let clearBtn = app.buttons["xmark"]
        XCTAssertTrue(clearBtn.waitForExistence(timeout: 3))

        // Audit 3.1 gave each swatch a real VoiceOver label (HighlightPalette.name) —
        // tap each by name instead of by coordinate guesswork (Classic palette names).
        // Identifiers, not names: the highlight and text-colour rows share colour names (2026-10-09).
        for name in (0..<5).map({ "highlight-\($0)" }) + (0..<5).map({ "textColor-\($0)" }) {
            let swatch = app.buttons[name]
            XCTAssertTrue(swatch.waitForExistence(timeout: 3), "\(name) swatch must exist")
            XCTAssertTrue(swatch.isHittable, "\(name) swatch must be on screen")
            swatch.tap()
            Thread.sleep(forTimeInterval: 0.2)
        }
        snapshot(app, name: "panel_highlight_colors_visible")

        // Verify tapping clear doesn't crash
        clearBtn.tap()
        Thread.sleep(forTimeInterval: 0.3)
        app.buttons["colorsBack"].tap()
        Thread.sleep(forTimeInterval: 0.4)
        XCTAssertTrue(app.buttons["Title"].waitForExistence(timeout: 3), "Panel still open after highlight interaction")
    }

    // MARK: - FormattingPanel: Combined Scenarios

    /// Paragraph style + inline style both active simultaneously.
    @MainActor
    func testFormattingPanel_paragraphAndInlineCombined() throws {
        let app = launchApp()
        tapWriteTab(in: app)
        let tv = focusEditor(in: app)
        tv.typeText("Combined styles line")
        Thread.sleep(forTimeInterval: 0.3)

        app.buttons["Formatting"].tap()
        Thread.sleep(forTimeInterval: 0.8)

        // Apply heading
        app.buttons["Heading"].tap()
        Thread.sleep(forTimeInterval: 0.3)

        // Apply bold italic
        app.buttons["B"].tap()
        Thread.sleep(forTimeInterval: 0.3)
        app.buttons["I"].tap()
        Thread.sleep(forTimeInterval: 0.3)

        // All three buttons must still exist (panel still open)
        XCTAssertTrue(app.buttons["Heading"].exists)
        XCTAssertTrue(app.buttons["B"].exists)
        XCTAssertTrue(app.buttons["I"].exists)

        snapshot(app, name: "panel_heading_bold_italic_combined")
    }

    /// Switching paragraph styles when inline styles are active doesn't clear inline state.
    @MainActor
    func testFormattingPanel_changeParagraphStyle_preservesInlineStyles() throws {
        let app = launchApp()
        tapWriteTab(in: app)
        let tv = focusEditor(in: app)
        tv.typeText("Persist inline test")
        Thread.sleep(forTimeInterval: 0.3)

        app.buttons["Formatting"].tap()
        Thread.sleep(forTimeInterval: 0.8)

        // Set bold first
        app.buttons["B"].tap()
        Thread.sleep(forTimeInterval: 0.3)

        // Now change paragraph style — bold button must still exist (panel open)
        app.buttons["Heading"].tap()
        Thread.sleep(forTimeInterval: 0.3)
        app.buttons["Title"].tap()
        Thread.sleep(forTimeInterval: 0.3)

        XCTAssertTrue(app.buttons["B"].exists, "Inline style buttons must remain after paragraph style changes")

        snapshot(app, name: "panel_inline_persists_across_paragraph_change")
    }

    // MARK: - Regression Tests

    /// Regression for Bugs 1 & 2: with the cursor on a checklist line, the bulk
    /// ops must be there on the FIRST render after the panel round-trip — no
    /// second close/reopen. Fix: updateFormattingPanel(visible:true) calls
    /// refreshActiveInlineStyles before showing the panel, so activeParagraphStyle
    /// is current. (Checklist and its actions now live in the keyboard bar; the
    /// open→close is what exercises the fresh-render path.)
    @MainActor
    func testRegression_openAaOnChecklistLine_bulkOpsAndChecklistHighlightAppearImmediately() throws {
        let app = launchApp()
        tapWriteTab(in: app)
        let tv = focusEditor(in: app)
        tv.typeText("Buy milk")
        Thread.sleep(forTimeInterval: 0.5)
        dismissSystemDialogs(app)

        applyChecklist(in: app)

        // Panel round-trip with checklist already active on the current line.
        openFormattingPanel(in: app)
        closeFormattingPanel(in: app)

        // Bulk ops must be present on the first render — tight timeout, no re-open.
        let actions = app.buttons["keyboardBar.checklist"]
        XCTAssertTrue(actions.waitForExistence(timeout: 1),
                      "Checklist button must be back immediately after the panel closes (regression Fix 1)")
        actions.press(forDuration: 0.8)
        XCTAssertTrue(app.buttons["Check All"].waitForExistence(timeout: 3),
                      "Check All must appear (regression Fix 1)")
        XCTAssertTrue(app.buttons["Uncheck All"].exists, "Uncheck All must appear (regression Fix 1)")
        XCTAssertTrue(app.buttons["Delete Done"].exists, "Delete Done must appear (regression Fix 1)")
        XCTAssertTrue(app.buttons["Sort Done"].exists,   "Sort Done must appear (regression Fix 1)")

        // Bar checklist button present (active-highlight is visual-only — see screenshot).
        XCTAssertTrue(app.buttons["keyboardBar.checklist"].exists,
                      "Bar checklist button must exist when checklist style is active (regression Fix 2)")

        snapshot(app, name: "regression_fix1_bulk_ops_immediate")
    }

    /// Regression for Bug 3: switching from checklist to a heading/title style must strip
    /// the "○  " marker from the paragraph text.
    /// Fix: apply() now calls stripListMarkerAndApply for ALL non-list target styles, not just body.
    @MainActor
    func testRegression_checklistToHeading_stripsListMarkerFromText() throws {
        let app = launchApp()
        tapWriteTab(in: app)
        let tv = focusEditor(in: app)
        tv.typeText("Buy milk")
        Thread.sleep(forTimeInterval: 0.5)
        dismissSystemDialogs(app)

        // Apply checklist from the bar — "○  Buy milk" is now displayed — then
        // open the panel for Heading.
        applyChecklist(in: app)
        openFormattingPanel(in: app)

        // Tap Heading — Fix 2+3 strips the "○  " marker before applying heading attributes
        XCTAssertTrue(app.buttons["Heading"].waitForExistence(timeout: 3))
        app.buttons["Heading"].tap()
        Thread.sleep(forTimeInterval: 0.5)

        // Close the panel so the real keyboard returns and tv.value is readable
        closeFormattingPanel(in: app)

        // Verify textView content does NOT contain the checklist marker prefix
        let displayedText = tv.value as? String ?? ""
        XCTAssertFalse(
            displayedText.contains("○"),
            "After switching checklist → Heading, text must not contain '○' marker. Got: \"\(displayedText)\" (regression Fix 2+3)"
        )
        XCTAssertTrue(
            displayedText.contains("Buy milk"),
            "After marker strip, original words must remain. Got: \"\(displayedText)\""
        )

        snapshot(app, name: "regression_fix3_heading_no_marker")
    }

    // MARK: - Checklist: automatic sorting

    /// Taps the circle of the checklist row whose text is `item`.
    @MainActor
    private func tapCircle(of item: String, in app: XCUIApplication) {
        let tv = app.textViews.firstMatch
        let text = tv.value as? String ?? ""
        let lines = text.components(separatedBy: "\n")
        guard let row = lines.firstIndex(where: { $0.contains(item) }) else { return XCTFail("No row \(item)") }
        // Rows sit about 34pt apart below the 8pt inset; the circle is at the row's left edge.
        let point = tv.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 12, dy: 8 + 17 + CGFloat(row) * 34))
        point.tap()
        Thread.sleep(forTimeInterval: 0.8)
    }

    /// The first checkbox tap asks, as Notes does. Not Now leaves the list in place; turning it
    /// on (Enable Sorting) moves a checked item below the unchecked ones.
    @MainActor
    func testChecklist_firstCheckAsksAboutSorting() throws {
        let app = launchApp()
        tapWriteTab(in: app)
        let tv = focusEditor(in: app)
        applyChecklist(in: app)
        tv.typeText("Milk\nEggs\nBread")
        Thread.sleep(forTimeInterval: 0.5)

        tapCircle(of: "Milk", in: app)
        let prompt = app.alerts["Enable Automatic Sorting?"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 3), "The first check must ask about automatic sorting")
        prompt.buttons["Enable Sorting"].tap()
        Thread.sleep(forTimeInterval: 1.2)
        // The text view's accessibility value can stop at the first line, so check the first row:
        // Milk (checked) must have left it.
        let lines = (tv.value as? String ?? "").components(separatedBy: "\n")
        XCTAssertTrue(lines.first?.contains("Eggs") == true, "Enable Sorting must move the checked item below the others. Got: \(lines)")
        snapshot(app, name: "checklist_sorted")

        // Asked once: the next check sorts without asking.
        tapCircle(of: "Eggs", in: app)
        XCTAssertFalse(app.alerts["Enable Automatic Sorting?"].waitForExistence(timeout: 1.5), "Sorting is asked only once")
    }

    @MainActor
    func testChecklist_notNowKeepsTheOrder() throws {
        let app = launchApp()
        tapWriteTab(in: app)
        let tv = focusEditor(in: app)
        applyChecklist(in: app)
        tv.typeText("Milk\nEggs")
        Thread.sleep(forTimeInterval: 0.5)
        tapCircle(of: "Milk", in: app)
        let prompt = app.alerts["Enable Automatic Sorting?"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 3))
        prompt.buttons["Not Now"].tap()
        Thread.sleep(forTimeInterval: 1)
        let lines = (tv.value as? String ?? "").components(separatedBy: "\n")
        XCTAssertTrue(lines.first?.contains("Milk") == true, "Not Now must leave the list in place. Got: \(lines)")
    }

    // MARK: - Voice: recorder sheet

    /// The attach menu's Record Audio opens the recorder sheet (as Notes does). Recording starts
    /// from the red button; Delete Recording closes the sheet and leaves the entry's text alone.
    /// The microphone prompt may appear on a fresh install, so a denied state is accepted too.
    @MainActor
    func testVoice_recordAudio_opensRecorderSheet() throws {
        let app = launchApp()
        tapWriteTab(in: app)
        let tv = focusEditor(in: app)
        tv.typeText("Narrating while I record")
        Thread.sleep(forTimeInterval: 0.3)

        let attach = app.buttons["keyboardBar.attach"]
        XCTAssertTrue(attach.waitForExistence(timeout: 5), "Attach menu must exist in the toolRow")
        attach.tap()
        let record = app.buttons["Record Audio"]
        XCTAssertTrue(record.waitForExistence(timeout: 3), "Attach menu must list Record Audio")
        record.tap()

        XCTAssertTrue(app.staticTexts["New Recording"].waitForExistence(timeout: 3), "Record Audio must open the recorder sheet")
        let recordButton = app.buttons["recorderRecord"]
        XCTAssertTrue(recordButton.exists, "The recorder must have the record button")
        recordButton.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.buttons["Allow"].waitForExistence(timeout: 2) {
            springboard.buttons["Allow"].tap()
            Thread.sleep(forTimeInterval: 0.5)
            if recordButton.label == "Record" { recordButton.tap() }
        }
        Thread.sleep(forTimeInterval: 1.5)
        let recording = recordButton.label == "Pause recording"
        let denied = app.staticTexts["Microphone access is off"].exists
        XCTAssertTrue(recording || denied, "The red button must start recording, or say microphone access is off")

        // Pause first: while recording, the timer and waveform redraw 20 times a second, so the
        // app never goes idle and XCUITest can't tap the menu.
        if recording {
            recordButton.tap()
            XCTAssertTrue(app.buttons["recorderPlay"].waitForExistence(timeout: 3))
            Thread.sleep(forTimeInterval: 1)
            XCTAssertEqual(recordButton.label, "Record", "The red button must pause the recording")
        }

        app.buttons["recorderMore"].tap()
        let delete = app.buttons["Delete Recording"]
        XCTAssertTrue(delete.waitForExistence(timeout: 3), "The more menu must offer Delete Recording")
        delete.tap()
        XCTAssertTrue(app.staticTexts["New Recording"].waitForNonExistence(timeout: 3), "Delete Recording must close the sheet")
        let editorText = tv.value as? String ?? ""
        XCTAssertTrue(editorText.contains("Narrating while I record"), "Editor text must survive a deleted recording")
    }

    // MARK: - Performance

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
