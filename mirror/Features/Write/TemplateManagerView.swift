import SwiftUI

/// Your templates: add, edit and delete the ones that sit beside the built-ins in "Need a starting
/// point?". Kept on this device only (`CustomTemplateStore`).
struct TemplateManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var templates: [CustomTemplate] = []
    @State private var unavailable = false
    @State private var editing: CustomTemplate?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            List {
                if unavailable {
                    Text("Your templates can't be read until this device is unlocked.")
                        .foregroundStyle(.secondary)
                } else {
                    Section {
                        if templates.isEmpty {
                            Text("Write the start of an entry you use often, like a checklist or a set of questions.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(templates) { template in
                            Button {
                                editing = template
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(template.title).foregroundStyle(.primary)
                                    Text(template.text.replacingOccurrences(of: "\n", with: " "))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                .padding(.vertical, 2)
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button("Delete", role: .destructive) { delete(template) }
                                    .tint(.red)
                            }
                            .contextMenu {
                                Button("Delete", systemImage: "trash", role: .destructive) { delete(template) }
                            }
                        }
                        Button("New Template", systemImage: "plus") {
                            editing = CustomTemplate(title: "", text: "")
                        }
                        .accessibilityIdentifier("templates.new")
                    } footer: {
                        Text("Kept on this device only.")
                    }
                }
            }
            .navigationTitle("Templates")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, idealWidth: 480, minHeight: 420, idealHeight: 520)
        #endif
        .onAppear(perform: reload)
        .sheet(item: $editing) { template in
            TemplateEditorView(template: template) { saved in
                upsert(saved)
            }
        }
        .alert("Couldn't save", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This device can't encrypt right now. Try again once it's unlocked.")
        }
    }

    private func reload() {
        switch CustomTemplateStore.load() {
        case .templates(let list):
            templates = list
            unavailable = false
        case .unavailable:
            templates = []
            unavailable = true
        }
    }

    private func upsert(_ template: CustomTemplate) {
        var next = templates
        if let index = next.firstIndex(where: { $0.id == template.id }) { next[index] = template } else { next.append(template) }
        commit(next)
    }

    private func delete(_ template: CustomTemplate) {
        commit(templates.filter { $0.id != template.id })
    }

    private func commit(_ next: [CustomTemplate]) {
        guard !unavailable else { return }
        if CustomTemplateStore.save(next) { templates = next } else { failed = true }
    }
}

/// One template's name and text.
private struct TemplateEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State var template: CustomTemplate
    let onSave: (CustomTemplate) -> Void

    /// Anything typed: a swipe mustn't drop it (Cancel is the way out).
    private var hasInput: Bool {
        !template.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !template.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSave: Bool {
        !template.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !template.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Evening check-in", text: $template.title)
                        .accessibilityIdentifier("template.title")
                }
                Section("Starts with") {
                    TextEditor(text: $template.text)
                        .frame(minHeight: 160)
                        .accessibilityIdentifier("template.text")
                }
            }
            #if os(macOS)
            .formStyle(.grouped)
            #endif
            .navigationTitle(template.title.isEmpty ? String(localized: "New Template") : template.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        template.title = template.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(template)
                        dismiss()
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier("template.save")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 380)
        #endif
        .interactiveDismissDisabled(hasInput)
    }
}
