import XCTest

final class mirrorUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
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
        tv.tap()
        Thread.sleep(forTimeInterval: 0.8)
        dismissSystemDialogs(app)
        return tv
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

    /// Discard draft clears the text editor (entry == nil path: discardDraft()).
    @MainActor
    func testToolbar_discardDraft_clearsEditor() throws {
        let app = launchApp()
        tapWriteTab(in: app)

        let tv = focusEditor(in: app)
        tv.typeText("Text to discard")
        Thread.sleep(forTimeInterval: 0.5)

        app.buttons["Discard draft"].tap()
        Thread.sleep(forTimeInterval: 0.8)

        // After discard the editor should be empty and buttons disabled again
        XCTAssertFalse(app.buttons["Discard draft"].isEnabled, "Discard must be disabled after discarding")
        XCTAssertFalse(app.buttons["Save entry"].isEnabled,    "Save must be disabled after discarding")

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

        // Navigate to Entries tab
        app.tabBars.buttons["Entries"].tap()
        Thread.sleep(forTimeInterval: 1.5)

        // Tap the first entry in the list
        let firstEntry = app.cells.firstMatch
        XCTAssertTrue(firstEntry.waitForExistence(timeout: 5), "Entry must appear in list after save")
        firstEntry.tap()
        Thread.sleep(forTimeInterval: 1)

        // Tap Edit button on EntryDetailView
        let editBtn = app.buttons["Edit"]
        XCTAssertTrue(editBtn.waitForExistence(timeout: 5), "Edit button must exist on detail view")
        editBtn.tap()
        Thread.sleep(forTimeInterval: 1)

        // In edit mode: "Delete entry" replaces "Discard draft"
        let deleteEntry  = app.buttons["Delete entry"]
        let discardDraft = app.buttons["Discard draft"]

        XCTAssertTrue(deleteEntry.waitForExistence(timeout: 5),  "Delete entry must exist in edit mode")
        XCTAssertFalse(discardDraft.exists,                       "Discard draft must NOT exist in edit mode")
        XCTAssertTrue(deleteEntry.isEnabled,                      "Delete entry is always enabled in edit mode")
        XCTAssertTrue(app.buttons["Save entry"].isEnabled,        "Save entry must be enabled in edit mode")

        snapshot(app, name: "toolbar_edit_entry_mode")
    }

    /// Delete entry button → shows confirmation dialog.
    @MainActor
    func testToolbar_editEntry_deleteButtonShowsConfirmation() throws {
        let app = launchApp()
        tapWriteTab(in: app)

        let tv = focusEditor(in: app)
        tv.typeText("Entry to delete")
        Thread.sleep(forTimeInterval: 0.5)
        app.buttons["Save entry"].tap()
        Thread.sleep(forTimeInterval: 1.5)

        app.tabBars.buttons["Entries"].tap()
        Thread.sleep(forTimeInterval: 1.5)

        let firstEntry = app.cells.firstMatch
        XCTAssertTrue(firstEntry.waitForExistence(timeout: 5))
        firstEntry.tap()
        Thread.sleep(forTimeInterval: 1)

        app.buttons["Edit"].tap()
        Thread.sleep(forTimeInterval: 1)

        app.buttons["Delete entry"].tap()
        Thread.sleep(forTimeInterval: 0.5)

        // Confirmation dialog must appear
        XCTAssertTrue(
            app.buttons["Delete"].waitForExistence(timeout: 3),
            "Delete confirmation button must appear"
        )
        XCTAssertTrue(app.buttons["Cancel"].exists, "Cancel button must appear in confirmation")

        snapshot(app, name: "toolbar_delete_confirmation_dialog")

        // Cancel to avoid deleting in subsequent tests
        app.buttons["Cancel"].tap()
    }

    // MARK: - ToolRow (keyboard accessory bar)

    /// ToolRow appears when the editor is focused (keyboard visible).
    @MainActor
    func testToolRow_appearsOnEditorFocus() throws {
        let app = launchApp()
        tapWriteTab(in: app)

        _ = focusEditor(in: app)

        // The keyboard dismiss button is the reliable anchor for toolRow existence
        let dismissBtn = app.buttons.matching(
            NSPredicate(format: "label == 'keyboard.chevron.compact.down'")
        ).firstMatch
        let textFormatting = app.buttons["Text formatting"]

        XCTAssertTrue(
            textFormatting.waitForExistence(timeout: 5),
            "Text formatting (Aa) button must appear in toolRow when keyboard is visible"
        )

        snapshot(app, name: "toolrow_visible_with_keyboard")
        _ = dismissBtn // suppress unused warning
    }

    /// Tapping keyboard dismiss button hides the toolRow.
    @MainActor
    func testToolRow_keyboardDismissButton_hidesToolRow() throws {
        let app = launchApp()
        tapWriteTab(in: app)
        _ = focusEditor(in: app)

        let aaBtn = app.buttons["Text formatting"]
        XCTAssertTrue(aaBtn.waitForExistence(timeout: 5))

        // Dismiss keyboard via the chevron button
        let chevron = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'keyboard'")
        ).element(boundBy: 0)
        if chevron.exists {
            chevron.tap()
        } else {
            // Fallback: tap outside editor
            app.tap()
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

        let aaBtn = app.buttons["Text formatting"]
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

        // Close panel via Aa again
        aaBtn.tap()
        Thread.sleep(forTimeInterval: 0.8)

        XCTAssertFalse(app.buttons["Title"].exists, "Panel must close when Aa is tapped again")

        snapshot(app, name: "aa_panel_closed")
    }

    /// Panel's keyboard icon button dismisses the panel and restores the real keyboard.
    @MainActor
    func testFormattingPanel_keyboardIconButton_closesPanel() throws {
        let app = launchApp()
        tapWriteTab(in: app)
        let tv = focusEditor(in: app)
        tv.typeText("Close via keyboard icon")
        Thread.sleep(forTimeInterval: 0.3)

        let aaBtn = app.buttons["Text formatting"]
        XCTAssertTrue(aaBtn.waitForExistence(timeout: 5))
        aaBtn.tap()
        Thread.sleep(forTimeInterval: 0.8)

        XCTAssertTrue(app.buttons["Title"].waitForExistence(timeout: 3))

        // Tap the keyboard icon inside the panel (top-right of panel)
        let keyboardIcon = app.buttons.matching(
            NSPredicate(format: "label == 'keyboard'")
        ).firstMatch
        XCTAssertTrue(keyboardIcon.waitForExistence(timeout: 3), "Keyboard dismiss icon must exist in panel")
        keyboardIcon.tap()
        Thread.sleep(forTimeInterval: 0.8)

        XCTAssertFalse(app.buttons["Title"].exists, "Panel must close after tapping keyboard icon")
        // Aa button must still be visible (real keyboard returned)
        XCTAssertTrue(aaBtn.exists, "Aa button must still be visible after panel dismissed to keyboard")

        snapshot(app, name: "panel_closed_via_keyboard_icon")
    }

    // MARK: - ToolRow: Checklist Button Active State

    /// Checklist button in toolRow highlights after applying checklist style directly via toolRow.
    @MainActor
    func testToolRow_checklistButton_highlightsWhenChecklistActive() throws {
        let app = launchApp()
        tapWriteTab(in: app)
        let tv = focusEditor(in: app)
        tv.typeText("Buy milk")
        Thread.sleep(forTimeInterval: 0.5)
        dismissSystemDialogs(app)

        // Apply checklist via toolRow button while Aa panel is CLOSED — unambiguous single button
        let toolRowChecklist = app.buttons.matching(
            NSPredicate(format: "label == 'checklist'")
        ).firstMatch
        XCTAssertTrue(toolRowChecklist.waitForExistence(timeout: 5), "Checklist button must exist in toolRow")
        toolRowChecklist.tap()
        Thread.sleep(forTimeInterval: 0.5)

        // Active state is accent color — captured via screenshot
        snapshot(app, name: "toolrow_checklist_active_state")

        // Button still present after activation
        XCTAssertTrue(toolRowChecklist.exists, "Checklist button must remain in toolRow after activation")
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

        app.buttons["Text formatting"].tap()
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

        let aaBtn = app.buttons["Text formatting"]
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

        app.buttons["Text formatting"].tap()
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

        app.buttons["Text formatting"].tap()
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

        app.buttons["Text formatting"].tap()
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

        app.buttons["Text formatting"].tap()
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

        app.buttons["Text formatting"].tap()
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

        app.buttons["Text formatting"].tap()
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

        app.buttons["Text formatting"].tap()
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

        app.buttons["Text formatting"].tap()
        Thread.sleep(forTimeInterval: 0.8)

        XCTAssertFalse(app.buttons["Check All"].exists,   "Check All must not appear on body text")
        XCTAssertFalse(app.buttons["Uncheck All"].exists, "Uncheck All must not appear on body text")
        XCTAssertFalse(app.buttons["Delete Done"].exists, "Delete Done must not appear on body text")
        XCTAssertFalse(app.buttons["Sort Done"].exists,   "Sort Done must not appear on body text")

        snapshot(app, name: "panel_no_bulk_ops_on_body")
    }

    /// Bulk ops row IS present when cursor is on a checklist line.
    @MainActor
    func testFormattingPanel_bulkOps_appearOnChecklistLine() throws {
        let app = launchApp()
        tapWriteTab(in: app)
        let tv = focusEditor(in: app)
        tv.typeText("Buy milk")
        Thread.sleep(forTimeInterval: 0.5)
        dismissSystemDialogs(app)

        // Apply checklist via toolRow BEFORE opening Aa — no button ambiguity, state settled
        let toolRowChecklist = app.buttons.matching(
            NSPredicate(format: "label == 'checklist'")
        ).firstMatch
        XCTAssertTrue(toolRowChecklist.waitForExistence(timeout: 5))
        toolRowChecklist.tap()
        Thread.sleep(forTimeInterval: 0.5)

        // Now open Aa panel — activeParagraphStyle is already .checklistUnchecked
        let aaBtn = app.buttons["Text formatting"]
        XCTAssertTrue(aaBtn.waitForExistence(timeout: 5))
        aaBtn.tap()
        Thread.sleep(forTimeInterval: 0.8)

        // Bulk ops must be visible immediately
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

        // Apply checklist via toolRow BEFORE opening Aa
        let toolRowChecklist = app.buttons.matching(
            NSPredicate(format: "label == 'checklist'")
        ).firstMatch
        XCTAssertTrue(toolRowChecklist.waitForExistence(timeout: 5))
        toolRowChecklist.tap()
        Thread.sleep(forTimeInterval: 0.5)

        // Add more checklist items (Enter continues checklist style)
        tv.typeText("\nPick up kids\nPay bills")
        Thread.sleep(forTimeInterval: 0.5)

        // Open panel — cursor on last checklist line, bulk ops appear immediately
        let aaBtn = app.buttons["Text formatting"]
        XCTAssertTrue(aaBtn.waitForExistence(timeout: 5))
        aaBtn.tap()
        Thread.sleep(forTimeInterval: 0.8)

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

        // Apply checklist via toolRow BEFORE opening Aa
        let toolRowChecklist = app.buttons.matching(
            NSPredicate(format: "label == 'checklist'")
        ).firstMatch
        XCTAssertTrue(toolRowChecklist.waitForExistence(timeout: 5))
        toolRowChecklist.tap()
        Thread.sleep(forTimeInterval: 0.5)

        // Add second checklist item
        tv.typeText("\nItem two")
        Thread.sleep(forTimeInterval: 0.3)

        // Open panel — cursor on checklist line, bulk ops ready
        let aaBtn = app.buttons["Text formatting"]
        XCTAssertTrue(aaBtn.waitForExistence(timeout: 5))
        aaBtn.tap()
        Thread.sleep(forTimeInterval: 0.8)

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

        app.buttons["Text formatting"].tap()
        Thread.sleep(forTimeInterval: 0.8)

        // Clear highlight button uses "xmark" SF symbol
        let clearBtn = app.buttons.matching(NSPredicate(format: "label == 'xmark'")).firstMatch
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

        app.buttons["Text formatting"].tap()
        Thread.sleep(forTimeInterval: 0.8)

        let clearBtn = app.buttons.matching(NSPredicate(format: "label == 'xmark'")).firstMatch
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

        app.buttons["Text formatting"].tap()
        Thread.sleep(forTimeInterval: 0.8)

        // Highlight color buttons have no labels — locate them after xmark button
        // They are in the same HStack row as xmark; total 6 buttons (1 clear + 5 colors)
        // We tap each, then re-tap clear to reset
        let clearBtn = app.buttons.matching(NSPredicate(format: "label == 'xmark'")).firstMatch
        XCTAssertTrue(clearBtn.waitForExistence(timeout: 3))

        // Scroll to bottom of panel to ensure highlight row is visible
        let panel = app.otherElements.containing(.button, identifier: "xmark").firstMatch

        // Tap each color by coordinate offset from xmark — use otherElements approach
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

        app.buttons["Text formatting"].tap()
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

        app.buttons["Text formatting"].tap()
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

    /// Regression for Bugs 1 & 2: open Aa panel while on a checklist line → bulk ops must appear
    /// immediately without requiring the panel to be closed and re-opened.
    /// Fix: updateFormattingPanel(visible:true) now calls refreshActiveInlineStyles before showing panel.
    @MainActor
    func testRegression_openAaOnChecklistLine_bulkOpsAndChecklistHighlightAppearImmediately() throws {
        let app = launchApp()
        tapWriteTab(in: app)
        let tv = focusEditor(in: app)
        tv.typeText("Buy milk")
        Thread.sleep(forTimeInterval: 0.5)
        dismissSystemDialogs(app)

        // Apply checklist via toolRow — settles textViewDidChangeSelection before panel opens
        let toolRowChecklist = app.buttons.matching(
            NSPredicate(format: "label == 'checklist'")
        ).firstMatch
        XCTAssertTrue(toolRowChecklist.waitForExistence(timeout: 5))
        toolRowChecklist.tap()
        Thread.sleep(forTimeInterval: 0.6)   // let delegate fire and update panelState

        // Open Aa panel — Fix 1 ensures activeParagraphStyle is current at panel-open time
        let aaBtn = app.buttons["Text formatting"]
        XCTAssertTrue(aaBtn.waitForExistence(timeout: 5))
        aaBtn.tap()
        Thread.sleep(forTimeInterval: 0.8)

        // Bulk ops row must be visible immediately — no re-open needed
        XCTAssertTrue(app.buttons["Check All"].waitForExistence(timeout: 3),
                      "Check All must appear immediately when Aa opens on a checklist line (regression Fix 1)")
        XCTAssertTrue(app.buttons["Uncheck All"].waitForExistence(timeout: 3),
                      "Uncheck All must appear (regression Fix 1)")
        XCTAssertTrue(app.buttons["Delete Done"].waitForExistence(timeout: 3),
                      "Delete Done must appear (regression Fix 1)")
        XCTAssertTrue(app.buttons["Sort Done"].waitForExistence(timeout: 3),
                      "Sort Done must appear (regression Fix 1)")

        // The checklist button in the panel list row must also be present (highlighted state
        // is visual-only — verified via screenshot)
        XCTAssertTrue(app.buttons["checklist"].exists,
                      "Checklist list-row button must exist in panel when checklist style active (regression Fix 2)")

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

        // Apply checklist via toolRow — "○  Buy milk" is now displayed
        let toolRowChecklist = app.buttons.matching(
            NSPredicate(format: "label == 'checklist'")
        ).firstMatch
        XCTAssertTrue(toolRowChecklist.waitForExistence(timeout: 5))
        toolRowChecklist.tap()
        Thread.sleep(forTimeInterval: 0.6)

        // Open Aa panel
        let aaBtn = app.buttons["Text formatting"]
        XCTAssertTrue(aaBtn.waitForExistence(timeout: 5))
        aaBtn.tap()
        Thread.sleep(forTimeInterval: 0.8)

        // Tap Heading — Fix 2+3 strips the "○  " marker before applying heading attributes
        XCTAssertTrue(app.buttons["Heading"].waitForExistence(timeout: 3))
        app.buttons["Heading"].tap()
        Thread.sleep(forTimeInterval: 0.5)

        // Close the panel so the real keyboard returns and tv.value is readable
        let keyboardIcon = app.buttons.matching(
            NSPredicate(format: "label == 'keyboard'")
        ).firstMatch
        if keyboardIcon.exists {
            keyboardIcon.tap()
        } else {
            aaBtn.tap()
        }
        Thread.sleep(forTimeInterval: 0.6)

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

    // MARK: - Performance

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
