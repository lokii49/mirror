import SwiftUI

/// Edits a value copy: Cancel never changes the archive's active criteria.
struct EntryFiltersView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appDisplayMode) private var displayMode
    @State var criteria: EntryFilterCriteria
    let moods: [String]
    let tags: [String]
    let apply: (EntryFilterCriteria) -> Void

    private var availableMoods: [String] { Array(Set(moods).union(criteria.moods)).sorted() }
    private var availableTags: [String] { Array(Set(tags).union(criteria.tags)).sorted() }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Dates", selection: $criteria.dateScope) {
                        Text("All time").tag(EntryFilterCriteria.DateScope.allTime)
                        Text("Date range").tag(EntryFilterCriteria.DateScope.range)
                        Text("Today").tag(EntryFilterCriteria.DateScope.today)
                        Text("This week").tag(EntryFilterCriteria.DateScope.thisWeek)
                        Text("This month").tag(EntryFilterCriteria.DateScope.thisMonth)
                    }
                    if criteria.dateScope == .range {
                        Toggle("Start date", isOn: endpointEnabled(start: true))
                        if criteria.startDate != nil {
                            DatePicker("From", selection: endpoint(start: true), displayedComponents: .date)
                        }
                        Toggle("End date", isOn: endpointEnabled(start: false))
                        if criteria.endDate != nil {
                            DatePicker("Through", selection: endpoint(start: false), displayedComponents: .date)
                        }
                        if !criteria.hasValidRange() {
                            Text("The end date must be on or after the start date.").foregroundStyle(.red)
                        }
                    }
                } header: { Text("Dates") } footer: {
                    Text("Date ranges include the full first and last day. Relative dates update when the day changes.")
                }
                if !availableMoods.isEmpty {
                    Section {
                        ForEach(availableMoods, id: \.self) { mood in
                            Toggle(isOn: selection(mood, moods: true)) {
                                Label {
                                    Text(MirrorTheme.localizedMoodName(for: mood))
                                } icon: {
                                    Circle().fill(MirrorTheme.moodColor(for: mood)).frame(width: 9, height: 9)
                                }
                            }
                            .accessibilityIdentifier("filter.mood.\(mood)")
                        }
                    } header: { Text("Moods") } footer: { Text("Match any selected mood.") }
                }
                if !availableTags.isEmpty {
                    Section {
                        Picker("Tag matching", selection: $criteria.tagMatch) {
                            Text("Any selected tag").tag(EntryFilterCriteria.TagMatch.any)
                            Text("All selected tags").tag(EntryFilterCriteria.TagMatch.all)
                        }
                        .accessibilityIdentifier("filter.tagMatch")
                        ForEach(availableTags, id: \.self) { tag in
                            Toggle("#\(MirrorTheme.localizedTagName(for: tag))", isOn: selection(tag, moods: false))
                                .accessibilityIdentifier("filter.tag.\(tag)")
                        }
                    } header: { Text("Tags") }
                }
                Section("Media and pins") {
                    Toggle("With photos", isOn: $criteria.photosOnly).accessibilityIdentifier("filter.photos")
                    Toggle("With voice notes", isOn: $criteria.audioOnly).accessibilityIdentifier("filter.audio")
                    Toggle("Pinned only", isOn: $criteria.pinnedOnly).accessibilityIdentifier("filter.pinned")
                }
                Section {
                    Button("Clear filters") { criteria = EntryFilterCriteria() }
                        .disabled(!criteria.isActive)
                } footer: { Text("Different filter categories and your search must all match.") }
            }
            .formStyle(.grouped)
            .onChange(of: criteria.dateScope) { _, scope in
                if scope == .range, criteria.startDate == nil, criteria.endDate == nil {
                    criteria.startDate = Date()
                    criteria.endDate = criteria.startDate
                }
            }
            .navigationTitle("Filter entries")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        var value = criteria
                        if value.dateScope == .range, value.startDate == nil, value.endDate == nil {
                            value.dateScope = .allTime
                        }
                        apply(value)
                        dismiss()
                    }
                        .disabled(!criteria.hasValidRange())
                        .accessibilityIdentifier("filter.apply")
                }
            }
            .tint(displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.violet)
        }
        #if os(macOS)
        .frame(minWidth: 440, idealWidth: 480, minHeight: 520, idealHeight: 660)
        #endif
    }

    private func selection(_ value: String, moods: Bool) -> Binding<Bool> {
        Binding(get: { (moods ? criteria.moods : criteria.tags).contains(value) }, set: { enabled in
            if moods {
                if enabled { criteria.moods.insert(value) } else { criteria.moods.remove(value) }
            } else {
                if enabled { criteria.tags.insert(value) } else { criteria.tags.remove(value) }
            }
        })
    }
    private func endpointEnabled(start: Bool) -> Binding<Bool> {
        Binding(get: { (start ? criteria.startDate : criteria.endDate) != nil }, set: { enabled in
            if start { criteria.startDate = enabled ? (criteria.endDate ?? Date()) : nil }
            else { criteria.endDate = enabled ? (criteria.startDate ?? Date()) : nil }
        })
    }
    private func endpoint(start: Bool) -> Binding<Date> {
        Binding(get: { (start ? criteria.startDate : criteria.endDate) ?? Date() }, set: { value in
            if start { criteria.startDate = value } else { criteria.endDate = value }
        })
    }
}
