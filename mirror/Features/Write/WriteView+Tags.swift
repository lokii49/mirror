import SwiftUI
import SwiftData

extension WriteView {
    var tagsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(entryTags, id: \.self) { tag in
                    HStack(spacing: 3) {
                        Text("#\(MirrorTheme.localizedTagName(for: tag))")
                            .font(.system(size: 12, weight: .medium))
                        Button {
                            entryTags.removeAll { $0 == tag }
                            if entry == nil { saveDraftToStorage() }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .buttonStyle(.plain)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        displayMode == .sentinel ? AnyShapeStyle(MirrorTheme.inkMid) : AnyShapeStyle(Color(.secondarySystemFill)),
                        in: displayMode == .sentinel ? AnyShape(RoundedRectangle(cornerRadius: 4, style: .continuous)) : AnyShape(Capsule())
                    )
                    .overlay {
                        if displayMode == .sentinel {
                            RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(MirrorTheme.inkBorder, lineWidth: 1)
                        }
                    }
                }

                if showTagInput {
                    TextField("tag", text: $tagText)
                        .font(.system(size: 12))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .frame(minWidth: 60)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            displayMode == .sentinel ? AnyShapeStyle(MirrorTheme.inkMid) : AnyShapeStyle(Color(.secondarySystemFill)),
                            in: displayMode == .sentinel ? AnyShape(RoundedRectangle(cornerRadius: 4, style: .continuous)) : AnyShape(Capsule())
                        )
                        .overlay {
                            if displayMode == .sentinel {
                                RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(MirrorTheme.inkBorder, lineWidth: 1)
                            }
                        }
                        .onSubmit { commitTag() }
                        .submitLabel(.done)
                        .focused($tagFieldFocused)
                        .onAppear { DispatchQueue.main.async { tagFieldFocused = true } }
                        .onChange(of: tagFieldFocused) { _, focused in
                            if !focused {
                                DispatchQueue.main.async {
                                    if !tagFieldFocused && tagText.isEmpty {
                                        showTagInput = false
                                    }
                                }
                            }
                        }

                    if !filteredTagSuggestions.isEmpty {
                        Rectangle()
                            .fill(Color(.separator))
                            .frame(width: 1, height: 16)
                            .padding(.horizontal, 2)

                        ForEach(filteredTagSuggestions, id: \.self) { tag in
                            Button {
                                entryTags.append(tag)
                                tagText = ""
                                showTagInput = false
                                if entry == nil { saveDraftToStorage() }
                            } label: {
                                let accent = displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.primary
                                Text("#\(MirrorTheme.localizedTagName(for: tag))")
                                    .font(displayMode == .sentinel ? MirrorTheme.mono(12, weight: .semibold) : .system(size: 12, weight: .medium))
                                    .foregroundStyle(accent)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        accent.opacity(0.10),
                                        in: displayMode == .sentinel ? AnyShape(RoundedRectangle(cornerRadius: 4, style: .continuous)) : AnyShape(Capsule())
                                    )
                                    .overlay {
                                        if displayMode == .sentinel {
                                            RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(accent.opacity(0.3), lineWidth: 1)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    Button {
                        showTagInput = true
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .semibold))
                            Text("tag")
                                .font(displayMode == .sentinel ? MirrorTheme.mono(11, weight: .semibold) : .system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            displayMode == .sentinel ? AnyShapeStyle(MirrorTheme.inkMid) : AnyShapeStyle(Color(.tertiarySystemFill)),
                            in: displayMode == .sentinel ? AnyShape(RoundedRectangle(cornerRadius: 4, style: .continuous)) : AnyShape(Capsule())
                        )
                        .overlay {
                            if displayMode == .sentinel {
                                RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(MirrorTheme.inkBorder, lineWidth: 1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
    }

    static let defaultTagSuggestions = [
        "therapy", "work", "personal", "idea", "dream"
    ]

    var filteredTagSuggestions: [String] {
        let query = tagText.lowercased()
        var seen = Set<String>()
        var combined: [String] = []
        for tag in existingTagSuggestions + Self.defaultTagSuggestions {
            if seen.insert(tag).inserted { combined.append(tag) }
        }
        let available = combined.filter { !entryTags.contains($0) }
        if query.isEmpty { return Array(available.prefix(15)) }
        return available.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    /// Distinct tag set across every entry, for the autocomplete row. Used to
    /// hold a live `@Query var allEntries: [Entry]` on `WriteView` just for
    /// this — that faulted (and decrypted, on `.tags` access) every entry in
    /// the journal and re-rendered the whole write screen on any entry
    /// change anywhere in the app (a background mood-detect save, etc.).
    /// Fetch on demand instead, scoped to the one stored property this
    /// needs (`.tags` is computed/encrypted, so `propertiesToFetch` targets
    /// its backing storage).
    func computeTagSuggestions() {
        var descriptor = FetchDescriptor<Entry>()
        descriptor.propertiesToFetch = [\.encryptedTagsStorage]
        let entries = (try? modelContext.fetch(descriptor)) ?? []
        var seen = Set<String>()
        var result: [String] = []
        for e in entries {
            for tag in e.tags where seen.insert(tag).inserted {
                result.append(tag)
            }
        }
        existingTagSuggestions = result
    }

    func commitTag() {
        let tag = tagText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        if !tag.isEmpty && !entryTags.contains(tag) {
            entryTags.append(tag)
        }
        tagText = ""
        showTagInput = false
        if entry == nil { saveDraftToStorage() }
    }
}
