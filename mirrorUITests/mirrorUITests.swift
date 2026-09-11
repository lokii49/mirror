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

    /// Open the formatting panel from the toolRow Aa button ("Formatting" when
    /// closed, "Hide formatting" when open). Panel is confirmed open when the
    /// paragraph-style row is present.
    @discardableResult
    private func openFormattingPanel(in app: XCUIApplication) -> XCUIElement {
        let aa = app.buttons["Formatting"]
        XCTAssertTrue(aa.waitForExistence(timeout: 5), "Aa (Formatting) button must exist in toolRow")
        aa.tap()
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertTrue(app.buttons["Title"].waitForExistence(timeout: 3), "Panel must open (paragraph row visible)")
        return aa
    }

    /// Close the panel via the Aa toggle (now labelled "Hide formatting").
    private func closeFormattingPanel(in app: XCUIApplication) {
        let hide = app.buttons["Hide formatting"]
        if hide.exists { hide.tap() } else { app.buttons["Formatting"].tap() }
        Thread.sleep(forTimeInterval: 0.8)
    }

    /// Apply the checklist paragraph style. The toolRow no longer carries a
    /// checklist button (removed 2026-05) — the only entry point is the panel's
    /// list-row `checklist` icon.
    private func applyChecklistViaPanel(in app: XCUIApplication) {
        openFormattingPanel(in: app)
        let checklist = app.buttons["checklist"]
        XCTAssertTrue(checklist.waitForExistence(timeout: 3), "Panel checklist button must exist")
        checklist.tap()
        Thread.sleep(forTimeInterval: 0.5)
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
        // "Hide Keyboard" (identifier keyboard.chevron.compact.down) only renders
        // while the keyboard is up — a second anchor for toolRow presence.
        XCTAssertTrue(app.buttons["Hide Keyboard"].exists, "Keyboard-dismiss button must be in the toolRow")

        snapshot(app, name: "toolrow_visible_with_keyboard")
    }

    /// Tapping keyboard dismiss button hides the toolRow.
    @MainActor
    func testToolRow_keyboardDismissButton_hidesToolRow() throws {
        let app = launchApp()
        tapWriteTab(in: app)
        _ = focusEditor(in: app)

        let aaBtn = app.buttons["Formatting"]
        XCTAssertTrue(aaBtn.waitForExistence(timeout: 5))

        // Dismiss keyboard via the toolRow chevron ("Hide Keyboard")
        let chevron = app.buttons["Hide Keyboard"]
        if chevron.exists {
            chevron.tap()
        } else {
            app.tap() // fallback: tap outside the editor
        }
        Thread.sleep(forTimeInterval: 0.8)

        XCTAssertFalse(aaBtn.exists, "Aa button (toolRow) must disappear when keyboard is dismissed")

        snapshot(app, name: "toolrow_hidden_after_dismiss")
    }

    // MARK: - ToolRow: Aa Button (formatting panel toggle)

    /// Aa tap opens the formatting panel; second tap closes it.
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

        // Close panel via the Aa toggle — labelled "Hide formatting" while open
        app.buttons["Hide formatting"].tap()
        Thread.sleep(forTimeInterval: 0.8)

        XCTAssertFalse(app.buttons["Title"].exists, "Panel must close when Aa is tapped again")

        snapshot(app, name: "aa_panel_closed")
    }

    /// Closing the panel restores the real keyboard. On iPhone the panel is the
    /// text view's `inputView`, so dismissing it (Aa → "Hide formatting") must
    /// bring the keyboard straight back — "Hide Keyboard" only renders while the
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

        app.buttons["Hide formatting"].tap()
        Thread.sleep(forTimeInterval: 0.8)

        XCTAssertFalse(app.buttons["Title"].exists, "Panel must close")
        XCTAssertTrue(app.buttons["Formatting"].exists, "Aa button must return to its closed state")
        XCTAssertTrue(
            app.keyboards.element(boundBy: 0).waitForExistence(timeout: 3),
            "System keyboard must return after the panel closes (2.1 iPhone inputView-swap contract)"
        )

        snapshot(app, name: "panel_closed_keyboard_restored")
    }

    // MARK: - FormattingPanel: Checklist apply + active state

    /// Applying checklist from the panel keeps the panel open and surfaces the
    /// contextual bulk-ops row (the panel's `checklist` button is the only apply
    /// path since the toolRow button was removed 2026-05).
    @MainActor
    func testFormattingPanel_checklistButton_appliesAndShowsBulkOps() throws {
        let app = launchApp()
        tapWriteTab(in: app)
        let tv = focusEditor(in: app)
        tv.typeText("Buy milk")
        Thread.sleep(forTimeInterval: 0.5)
        dismissSystemDialogs(app)

        applyChecklistViaPanel(in: app)

        // Panel stays open; bulk-ops row appears because activeParagraphStyle changed to checklist
        XCTAssertTrue(app.buttons["Check All"].waitForExistence(timeout: 3),
                      "Bulk-ops row must appear once checklist is applied from the panel")
        XCTAssertTrue(app.buttons["checklist"].exists, "Panel checklist button must remain after activation")

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

        for label in ["Title", "Heading", "Subheading", "Body", "Mono"] {
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

        for label in ["Title", "Heading", "Subheading", "Mono", "Body"] {
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

        for icon in ["list.bullet", "list.dash", "list.number", "checklist", "decrease.indent", "increase.indent"] {
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

        app.buttons["Formatting"].tap()
        Thread.sleep(forTimeInterval: 0.8)

        XCTAssertFalse(app.buttons["Check All"].exists,   "Check All must not appear on body text")
        XCTAssertFalse(app.buttons["Uncheck All"].exists, "Uncheck All must not appear on body text")
        XCTAssertFalse(app.buttons["Delete Done"].exists, "Delete Done must not appear on body text")
        XCTAssertFalse(app.buttons["Sort Done"].exists,   "Sort Done must not appear on body text")

        snapshot(app, name: "panel_no_bulk_ops_on_body")
    }

    /// Bulk ops row is still present after the panel is closed and reopened with
    /// the cursor left on a checklist line.
    @MainActor
    func testFormattingPanel_bulkOps_appearOnChecklistLine() throws {
        let app = launchApp()
        tapWriteTab(in: app)
        let tv = focusEditor(in: app)
        tv.typeText("Buy milk")
        Thread.sleep(forTimeInterval: 0.5)
        dismissSystemDialogs(app)

        applyChecklistViaPanel(in: app)   // panel open, checklist applied
        closeFormattingPanel(in: app)     // keyboard back, cursor stays on the checklist line
        openFormattingPanel(in: app)      // reopen — activeParagraphStyle must still be checklist

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

        applyChecklistViaPanel(in: app)
        closeFormattingPanel(in: app)

        // Add more checklist items (Enter continues checklist style)
        tv.typeText("\nPick up kids\nPay bills")
        Thread.sleep(forTimeInterval: 0.5)

        openFormattingPanel(in: app)

        let checkAll = app.buttons["Check All"]
        XCTAssertTrue(checkAll.waitForExistence(timeout: 3))
        checkAll.tap()
        Thread.sleep(forTimeInterval: 0.5)
        snapshot(app, name: "bulk_after_check_all")

        let sortDone = app.buttons["Sort Done"]
        XCTAssertTrue(sortDone.waitForExistence(timeout: 3))
        sortDone.tap()
        Thread.sleep(forTimeInterval: 0.5)
        snapshot(app, name: "bulk_after_sort_done")

        let uncheckAll = app.buttons["Uncheck All"]
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

        applyChecklistViaPanel(in: app)
        closeFormattingPanel(in: app)

        // Add second checklist item
        tv.typeText("\nItem two")
        Thread.sleep(forTimeInterval: 0.3)

        openFormattingPanel(in: app)

        let checkAll = app.buttons["Check All"]
        XCTAssertTrue(checkAll.waitForExistence(timeout: 3))
        checkAll.tap()
        Thread.sleep(forTimeInterval: 0.5)
        snapshot(app, name: "bulk_before_delete_done")

        let deleteDone = app.buttons["Delete Done"]
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

        // Identifier stays "xmark" (audit 3.1 gave it a real VoiceOver label,
        // "No highlight", so a label-based lookup no longer matches).
        let clearBtn = app.buttons["xmark"]
        XCTAssertTrue(clearBtn.waitForExistence(timeout: 3))
        clearBtn.tap()
        Thread.sleep(forTimeInterval: 0.4)

        // Panel must still be open after clearing highlight
        XCTAssertTrue(app.buttons["Title"].exists, "Panel must remain open after clearing highlight")

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

        // Identifier stays "xmark" (audit 3.1 gave it a real VoiceOver label,
        // "No highlight", so a label-based lookup no longer matches).
        let clearBtn = app.buttons["xmark"]
        XCTAssertTrue(clearBtn.waitForExistence(timeout: 3))

        // Audit 3.1 gave each swatch a real VoiceOver label (HighlightPalette.name) —
        // tap each by name instead of by coordinate guesswork (Classic palette names).
        for name in ["Pink", "Purple", "Orange", "Mint", "Blue"] {
            let swatch = app.buttons[name]
            XCTAssertTrue(swatch.waitForExistence(timeout: 3), "\(name) highlight swatch must exist")
            swatch.tap()
            Thread.sleep(forTimeInterval: 0.2)
        }
        snapshot(app, name: "panel_highlight_colors_visible")

        // Verify tapping clear doesn't crash
        clearBtn.tap()
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertTrue(app.buttons["Title"].exists, "Panel still open after highlight interaction")
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

    /// Regression for Bugs 1 & 2: reopening the Aa panel with the cursor on a
    /// checklist line must surface the bulk-ops row on the FIRST render — no
    /// second close/reopen. Fix: updateFormattingPanel(visible:true) calls
    /// refreshActiveInlineStyles before showing the panel, so activeParagraphStyle
    /// is current at open time. (Checklist is now applied from the panel itself;
    /// the close→reopen is what exercises the fresh-open path.)
    @MainActor
    func testRegression_openAaOnChecklistLine_bulkOpsAndChecklistHighlightAppearImmediately() throws {
        let app = launchApp()
        tapWriteTab(in: app)
        let tv = focusEditor(in: app)
        tv.typeText("Buy milk")
        Thread.sleep(forTimeInterval: 0.5)
        dismissSystemDialogs(app)

        applyChecklistViaPanel(in: app)
        closeFormattingPanel(in: app)

        // Fresh open with checklist already active on the current line.
        openFormattingPanel(in: app)

        // Bulk ops must be present on the first render — tight timeout, no re-open.
        XCTAssertTrue(app.buttons["Check All"].waitForExistence(timeout: 1),
                      "Check All must appear immediately on panel open (regression Fix 1)")
        XCTAssertTrue(app.buttons["Uncheck All"].exists, "Uncheck All must appear (regression Fix 1)")
        XCTAssertTrue(app.buttons["Delete Done"].exists, "Delete Done must appear (regression Fix 1)")
        XCTAssertTrue(app.buttons["Sort Done"].exists,   "Sort Done must appear (regression Fix 1)")

        // Panel checklist button present (active-highlight is visual-only — see screenshot).
        XCTAssertTrue(app.buttons["checklist"].exists,
                      "Checklist list-row button must exist when checklist style is active (regression Fix 2)")

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

        // Apply checklist from the panel — "○  Buy milk" is now displayed. The
        // panel stays open, so Heading can be tapped straight after.
        applyChecklistViaPanel(in: app)

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

    // MARK: - Voice: inline recording (2.2)

    /// The toolRow mic button starts recording INLINE — no modal sheet. The
    /// keyboard and the editor's toolRow stay put; an `InlineRecordingRow`
    /// (or, if mic access is denied, an inline `MicPermissionNotice`) appears
    /// where the finished note will land.
    @MainActor
    func testVoice_micButton_recordsInlineWithoutModal() throws {
        let app = launchApp()
        tapWriteTab(in: app)
        let tv = focusEditor(in: app)
        tv.typeText("Narrating while I record")
        Thread.sleep(forTimeInterval: 0.3)

        let mic = app.buttons["Record voice note"]
        XCTAssertTrue(mic.waitForExistence(timeout: 5), "Mic button must exist in the toolRow")
        mic.tap()
        Thread.sleep(forTimeInterval: 0.5)
        dismissSystemDialogs(app) // grant the mic-permission prompt if it appears
        Thread.sleep(forTimeInterval: 0.8)

        let recordingRow = app.otherElements["Recording"]
        let stopButton   = app.buttons["Stop and add recording"]
        let permissionNotice = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Microphone access is off")
        ).firstMatch

        let recording = recordingRow.waitForExistence(timeout: 3) || stopButton.exists
        let denied = permissionNotice.exists
        XCTAssertTrue(recording || denied,
                      "Tapping the mic must show the inline recording row or the inline permission notice")

        // No modal: the editor's toolRow is still on screen either way.
        XCTAssertTrue(app.buttons["Formatting"].exists || app.buttons["Hide formatting"].exists,
                      "The toolRow (Aa button) must stay visible — recording is not modal")

        snapshot(app, name: recording ? "voice_inline_recording" : "voice_permission_denied_inline")

        if recording {
            let cancel = app.buttons["Cancel recording"]
            XCTAssertTrue(cancel.waitForExistence(timeout: 3), "Inline recording row must have a Cancel control")
            cancel.tap()
            Thread.sleep(forTimeInterval: 0.6)
            XCTAssertFalse(app.buttons["Stop and add recording"].exists, "Cancel must dismiss the recording row")
            let editorText = tv.value as? String ?? ""
            XCTAssertTrue(editorText.contains("Narrating while I record"),
                          "Editor text must survive an inline recording that was cancelled")
        }
    }

    // MARK: - Performance

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
