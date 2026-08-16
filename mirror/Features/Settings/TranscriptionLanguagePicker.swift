import SwiftUI

struct TranscriptionLanguagePickerView: View {
    @Binding var selected: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appDisplayMode) private var displayMode

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Group {
                            if displayMode == .sentinel {
                                Label("MODEL DOWNLOAD", systemImage: "info.circle").font(MirrorTheme.mono(11, weight: .semibold))
                            } else {
                                Label("Download language models", systemImage: "info.circle").font(.system(size: 13, weight: .semibold))
                            }
                        }
                        .foregroundStyle(.secondary)
                        Text("Some languages (e.g. Telugu, Tamil, Kannada) use Apple's on-device speech model. If transcription fails, the model may not be downloaded yet.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Text("To download: **iOS Settings → General → Language & Region → Add Language**")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(displayMode == .sentinel ? MirrorTheme.inkMid : nil)
                }

                Section {
                    ForEach(VoiceTranscriptionService.pickerLanguages) { lang in
                        Button {
                            selected = lang.id
                            dismiss()
                        } label: {
                            HStack {
                                Group {
                                    if displayMode == .sentinel {
                                        Text(lang.displayName).font(MirrorTheme.mono(14, weight: .medium))
                                    } else {
                                        Text(lang.displayName)
                                    }
                                }
                                .foregroundStyle(.primary)
                                Spacer()
                                if selected == lang.id {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(displayMode == .sentinel ? MirrorTheme.ember : Color.accentColor)
                                }
                            }
                        }
                        .listRowBackground(displayMode == .sentinel ? MirrorTheme.inkMid : nil)
                    }
                }
            }
            .scrollContentBackground(displayMode == .sentinel ? .hidden : .automatic)
            .background(displayMode == .sentinel ? MirrorTheme.bgBase : Color.clear)
            .navigationTitle(displayMode == .sentinel ? "Voice Signal" : "Voice Language")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
