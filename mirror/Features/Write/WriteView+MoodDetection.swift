import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension WriteView {
    nonisolated(unsafe) static var moodImageCache: [String: UIImage] = [:]

    func moodMenuDotImage(for mood: String, isSelected: Bool) -> UIImage {
        let key = "\(mood)_\(isSelected)"
        if let cached = Self.moodImageCache[key] { return cached }
        let size = CGSize(width: 20, height: 20)
        #if os(macOS)
        let image = NSImage(size: size, flipped: false) { _ in
            let rect = CGRect(x: 5, y: 5, width: 10, height: 10)
            UIColor(MirrorTheme.moodColor(for: mood)).setFill()
            NSBezierPath(ovalIn: rect).fill()
            if isSelected {
                UIColor.white.setStroke()
                let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
                ring.lineWidth = 1.4
                ring.stroke()
            }
            return true
        }
        Self.moodImageCache[key] = image
        return image
        #else
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
        #endif
    }

    /// "Mirror suggests" runs on Core and Deep with an on-device model; the menu disables it
    /// otherwise instead of letting a tap do nothing.
    var canSuggestMood: Bool {
        let sub = SubscriptionService.shared
        return (sub.tier == .core || sub.tier == .deep) && LocalLLMService.isModelAvailable
    }

    func detectMoodWithMirror() {
        guard canSuggestMood else { return }
        let text = viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isDetectingMood = true
        Task {
            let detected = try? await InsightService.detectEmotion(text: text)
            await MainActor.run {
                if let detected, MirrorTheme.moodOptions.contains(detected) {
                    viewModel.selectedMood = detected
                    moodWasSuggested = true
                } else {
                    // Say so instead of ending with no change (2026-10-09).
                    withAnimation { showMoodSuggestionFailed = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        withAnimation { showMoodSuggestionFailed = false }
                    }
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
