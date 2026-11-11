import Foundation
import Testing
@testable import mirror

/// Your own templates, kept sealed on this device. Synthetic text only.
@Suite("Custom templates")
struct CustomTemplateStoreTests {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "CustomTemplateStoreTests.\(UUID().uuidString)")! }
    private let open = WriteDraftStore.Crypto(seal: { Data($0.reversed()) }, open: { Data($0.reversed()) },
                                              openLegacyString: { $0 }, sealString: { $0 })
    private let locked = WriteDraftStore.Crypto(seal: { _ in nil }, open: { _ in nil },
                                                openLegacyString: { _ in nil }, sealString: { _ in nil })

    @Test func roundTripsSealed() {
        let d = defaults()
        let list = [CustomTemplate(title: "Synthetic check-in", text: "How did it go?\n- ")]
        #expect(CustomTemplateStore.save(list, defaults: d, crypto: open))
        let raw = d.data(forKey: CustomTemplateStore.key) ?? Data()
        #expect(!String(decoding: raw, as: UTF8.self).contains("Synthetic check-in"), "stored sealed, not plain")
        #expect(CustomTemplateStore.load(defaults: d, crypto: open) == .templates(list))
    }

    @Test func noneSavedIsAnEmptyList() {
        #expect(CustomTemplateStore.load(defaults: defaults(), crypto: open) == .templates([]))
    }

    @Test func unreadableIsUnavailableAndNotOverwritten() {
        let d = defaults()
        #expect(CustomTemplateStore.save([CustomTemplate(title: "A", text: "B")], defaults: d, crypto: open))
        #expect(CustomTemplateStore.load(defaults: d, crypto: locked) == .unavailable)
        #expect(CustomTemplateStore.readable(defaults: d, crypto: locked).isEmpty)
        // Sealing fails while locked: the saved list stays.
        #expect(!CustomTemplateStore.save([CustomTemplate(title: "C", text: "D")], defaults: d, crypto: locked))
        #expect(CustomTemplateStore.readable(defaults: d, crypto: open).map(\.title) == ["A"])
    }

    @Test func emptyListAndEraseRemoveTheKey() {
        let d = defaults()
        #expect(CustomTemplateStore.save([CustomTemplate(title: "A", text: "B")], defaults: d, crypto: open))
        #expect(CustomTemplateStore.save([], defaults: d, crypto: open))
        #expect(d.data(forKey: CustomTemplateStore.key) == nil)
        #expect(CustomTemplateStore.save([CustomTemplate(title: "A", text: "B")], defaults: d, crypto: open))
        CustomTemplateStore.erase(defaults: d)
        #expect(d.data(forKey: CustomTemplateStore.key) == nil)
    }

    @Test(arguments: [WritingTemplate.eveningReview, .weeklyPlan, .morningPages])
    func newBuiltInsPutTheCaretAfterTheirPrompt(_ template: WritingTemplate) {
        #expect(template.cursorOffset > 0)
        #expect(template.cursorOffset <= template.seedText.count)
        #expect(!template.title.isEmpty)
    }
}
