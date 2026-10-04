import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import Photos
import PhotosUI
import UniformTypeIdentifiers

#if os(iOS)
struct NativePhotoPicker: UIViewControllerRepresentable {
    let onPicked: (Result<URL, Error>) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onPicked: (Result<URL, Error>) -> Void

        init(onPicked: @escaping (Result<URL, Error>) -> Void) {
            self.onPicked = onPicked
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider else { return }

            provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, error in
                if let error {
                    DispatchQueue.main.async {
                        self.onPicked(.failure(error))
                    }
                    return
                }

                guard let url else {
                    DispatchQueue.main.async {
                        self.onPicked(.failure(PhotoAttachError.unreadableImage))
                    }
                    return
                }

                do {
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(url.pathExtension.isEmpty ? "image" : url.pathExtension)
                    try FileManager.default.copyItem(at: url, to: tempURL)
                    DispatchQueue.main.async {
                        self.onPicked(.success(tempURL))
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.onPicked(.failure(error))
                    }
                }
            }
        }
    }
}

struct CameraPickerController: UIViewControllerRepresentable {
    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }
    let onPicked: (Result<URL, Error>) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = ["public.image"]
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onPicked: (Result<URL, Error>) -> Void

        init(onPicked: @escaping (Result<URL, Error>) -> Void) {
            self.onPicked = onPicked
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            picker.dismiss(animated: true)
            guard let image = info[.originalImage] as? UIImage,
                  let data = image.jpegData(compressionQuality: 0.92) else {
                onPicked(.failure(PhotoAttachError.unreadableImage))
                return
            }
            do {
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("jpg")
                try data.write(to: tempURL)
                onPicked(.success(tempURL))
            } catch {
                onPicked(.failure(error))
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
#else
/// macOS: an open panel instead of the photo-library sheet. Hands back a temp copy of the chosen
/// image, the same contract as the iOS picker, then closes its sheet.
struct NativePhotoPicker: View {
    let onPicked: (Result<URL, Error>) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var opened = false

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .onAppear {
                guard !opened else { return }
                opened = true
                DispatchQueue.main.async {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.image]
                    panel.allowsMultipleSelection = false
                    panel.canChooseDirectories = false
                    if panel.runModal() == .OK, let url = panel.url {
                        do {
                            let tempURL = FileManager.default.temporaryDirectory
                                .appendingPathComponent(UUID().uuidString)
                                .appendingPathExtension(url.pathExtension.isEmpty ? "image" : url.pathExtension)
                            try FileManager.default.copyItem(at: url, to: tempURL)
                            onPicked(.success(tempURL))
                        } catch {
                            onPicked(.failure(error))
                        }
                    }
                    dismiss()
                }
            }
    }
}

/// macOS has no camera sheet; the entry point is hidden (`isAvailable` is false).
struct CameraPickerController: View {
    let onPicked: (Result<URL, Error>) -> Void
    static var isAvailable: Bool { false }
    var body: some View { EmptyView() }
}
#endif

struct IdentifiableIndex: Identifiable {
    let id: Int
    var value: Int { id }
    init(value: Int) { id = value }
}

enum PhotoAttachError: Error {
    case unreadableImage
}

struct FormatToggleButton: View {
    var panelState: FormattingPanelState
    var isShowingPanel: Bool
    var onTap: () -> Void
    @Environment(\.appDisplayMode) private var displayMode

    var body: some View {
        Button(action: onTap) {
            let inlineStyles = panelState.activeInlineStyles
            let paraStyle = panelState.activeParagraphStyle
            let hasActive = !inlineStyles.isEmpty || paraStyle != .body
            let aaSize: CGFloat = paraStyle == .title ? 19 : paraStyle == .heading ? 18 : 16
            let aaWeight: Font.Weight = (inlineStyles.bold || paraStyle == .heading || paraStyle == .title) ? .bold : (paraStyle == .subheading ? .semibold : .regular)
            let aaDesign: Font.Design = paraStyle == .monospaced ? .monospaced : .default
            let accent: Color = displayMode == .sentinel ? MirrorTheme.ember : Color.accentColor
            Text("Aa")
                .font(.system(size: aaSize, weight: aaWeight, design: aaDesign))
                .italic(inlineStyles.italic)
                .strikethrough(inlineStyles.strikethrough)
                .underline(inlineStyles.underline)
                .foregroundStyle(isShowingPanel ? accent : hasActive ? Color.primary : Color.secondary)
                .frame(width: 38, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isShowingPanel ? "Hide formatting" : "Formatting")
    }
}
