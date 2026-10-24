import SwiftUI
import SwiftData

/// "Moved to Recently Deleted · Undo" after a user delete (`.mirrorEntriesTrashed`). Delete no
/// longer asks first: it's reversible, as in Notes and Mail. Undo restores from Recently Deleted.
struct TrashUndoToast: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appDisplayMode) private var displayMode
    @State private var trashedIDs: [UUID] = []
    @State private var hideTask: Task<Void, Never>?
    @State private var undoFailed = false

    static let visibleSeconds: Double = 6

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if !trashedIDs.isEmpty {
                    toast
                        .padding(.horizontal, 16)
                        #if os(iOS)
                        .padding(.bottom, 72)   // above the tab bar
                        #else
                        .padding(.bottom, 20)
                        #endif
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.3, bounce: 0.15), value: trashedIDs)
            .onReceive(NotificationCenter.default.publisher(for: .mirrorEntriesTrashed)) { note in
                guard let ids = note.userInfo?["ids"] as? [UUID], !ids.isEmpty else { return }
                show(ids)
            }
            .alert("Couldn't restore", isPresented: $undoFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("It's still in Recently Deleted.")
            }
    }

    private var toast: some View {
        HStack(spacing: 12) {
            Image(systemName: "trash")
                .scaledFont(14, weight: .medium)
                .foregroundStyle(.secondary)
            Text(trashedIDs.count == 1 ? String(localized: "Moved to Recently Deleted")
                                       : String(localized: "\(trashedIDs.count) entries moved to Recently Deleted"))
                .scaledFont(displayMode == .sentinel ? 12 : 14, weight: displayMode == .sentinel ? .semibold : .medium, design: displayMode == .sentinel ? .monospaced : .default)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button("Undo") { undo() }
                .scaledFont(14, weight: .semibold)
                .foregroundStyle(displayMode == .sentinel ? MirrorTheme.ember : Color.accentColor)
                .buttonStyle(.plain)
                .accessibilityIdentifier("trash.undo")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 520)
        .background(MirrorTheme.inkMid, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(MirrorTheme.inkBorder, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 3)
        .accessibilityElement(children: .contain)
    }

    private func show(_ ids: [UUID]) {
        trashedIDs = ids
        AccessibilityNotification.Announcement(String(localized: "Moved to Recently Deleted")).post()
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.visibleSeconds))
            guard !Task.isCancelled else { return }
            trashedIDs = []
        }
    }

    private func undo() {
        let ids = trashedIDs
        hideTask?.cancel()
        trashedIDs = []
        do {
            try EntryTrash.restore(entryIDs: ids, in: modelContext)
        } catch {
            undoFailed = true
        }
    }
}
