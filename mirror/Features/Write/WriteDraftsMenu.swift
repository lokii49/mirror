import SwiftUI

/// The Write bar's Drafts menu: Save to Drafts, the newest drafts to continue, All Drafts….
/// Its own view (with the All Drafts sheet inside), so `WriteView.body` gains no modifiers.
struct WriteDraftsMenu: View {
    enum Style { case toolbar, macToolbar }

    var style: Style = .toolbar
    let canSave: Bool
    let save: () -> Void
    /// Continue a draft in this editor (the editor's own draft goes to Drafts first).
    let resume: (UUID) -> Void

    @Environment(\.appDisplayMode) private var displayMode
    @State private var drafts: [SavedDraftStore.Summary] = []
    @State private var showAll = false

    static let recentCount = 3

    var body: some View {
        Menu {
            Button("Save to Drafts", systemImage: "tray.and.arrow.down", action: save)
                .disabled(!canSave)
            let recent = drafts.filter { $0.payload != nil }.prefix(Self.recentCount)
            if !recent.isEmpty {
                Section("Continue writing") {
                    ForEach(Array(recent)) { draft in
                        Button { resume(draft.id) } label: {
                            Text(draft.preview ?? String(localized: "Photo or voice note"))
                            if let savedAt = draft.savedAt {
                                Text(savedAt.formatted(.relative(presentation: .named)))
                            }
                        }
                    }
                }
            }
            Divider()
            Button("All Drafts…", systemImage: "tray.full") { showAll = true }
        } label: {
            label
        }
        .menuIndicator(.hidden)
        .accessibilityLabel("Drafts")
        .accessibilityValue(drafts.isEmpty ? "" : String(localized: "\(drafts.count) drafts"))
        .accessibilityIdentifier("write.drafts")
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .mirrorSavedDraftsChanged)) { _ in reload() }
        .sheet(isPresented: $showAll) { LibrarySheet(page: .drafts) }
    }

    @ViewBuilder
    private var label: some View {
        switch style {
        case .toolbar:
            HStack(spacing: 5) {
                Text("Drafts")
                    .font(displayMode == .sentinel ? MirrorTheme.mono(13, weight: .semibold) : .system(size: 15, weight: .semibold))
                    .textCase(displayMode == .sentinel ? .uppercase : nil)
                if !drafts.isEmpty {
                    Text("\(drafts.count)")
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 17, minHeight: 17)
                        .background(displayMode == .sentinel ? MirrorTheme.ember : Color.accentColor, in: Capsule())
                }
            }
            .foregroundStyle(.secondary)
            .fixedSize()
        case .macToolbar:
            Image(systemName: drafts.isEmpty ? "tray" : "tray.full")
                .font(.system(size: 15))
                .frame(width: 34, height: 30)
                .contentShape(Rectangle())
        }
    }

    private func reload() {
        drafts = SavedDraftStore.summaries()
    }
}
