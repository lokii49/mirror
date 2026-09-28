import SwiftUI
import SwiftData
import UIKit

extension WriteView {
    nonisolated(unsafe) static var moodImageCache: [String: UIImage] = [:]

    func moodMenuDotImage(for mood: String, isSelected: Bool) -> UIImage {
        let key = "\(mood)_\(isSelected)"
        if let cached = Self.moodImageCache[key] { return cached }
        let size = CGSize(width: 20, height: 20)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let rect = CGRect(x: 5, y: 5, width: 10, height: 10)
            UIColor(MirrorTheme.moodColor(for: mood)).setFill()
            context.cgContext.fillEllipse(in: rect)
            if isSelected {
                UIColor.white.setStroke()
                context.cgContext.setLineWidth(1.4)
                context.cgContext.strokeEllipse(in: rect.insetBy(dx: 1, dy: 1))
            }
        }
        let result = image.withRenderingMode(.alwaysOriginal)
        Self.moodImageCache[key] = result
        return result
    }

    func detectMoodWithMirror() {
        let sub = SubscriptionService.shared
        guard sub.tier == .core || sub.tier == .deep else { return }
        guard LocalLLMService.isModelAvailable else { return }
        let text = viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isDetectingMood = true
        Task {
            let detected = try? await InsightService.detectEmotion(text: text)
            await MainActor.run {
                if let detected, MirrorTheme.moodOptions.contains(detected) {
                    viewModel.selectedMood = detected
                }
                isDetectingMood = false
            }
        }
    }

    /// Returns the detection so the save path can wait for it before the daily reflection and
    /// the mood-alert check read the entry's mood (see MoodAutoDetector).
    @discardableResult
    func autoDetectMoodIfNeeded(for entry: Entry) -> Task<Bool, Never>? {
        MoodAutoDetector.shared.detectIfNeeded(entry, context: modelContext)
    }
}
