import SwiftUI

struct TranscriptionLanguagePickerView: View {
    @Binding var selected: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Download language models", systemImage: "info.circle")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("Some languages (e.g. Telugu, Tamil, Kannada) use Apple's on-device speech model. If transcription fails, the model may not be downloaded yet.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Text("To download: **iOS Settings → General → Language & Region → Add Language**")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    ForEach(VoiceTranscriptionService.pickerLanguages) { lang in
                        Button {
                            selected = lang.id
                            dismiss()
                        } label: {
                            HStack {
                                Text(lang.displayName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selected == lang.id {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Voice Language")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
