import SwiftUI

/// A download state's case, without its progress: what views animate on. Animating on the state
/// itself would spring on every progress tick.
enum ModelDownloadStage: Equatable {
    case notStarted, active, installed, failed

    init(_ state: ModelDownloadState) {
        switch state {
        case .notStarted: self = .notStarted
        case .downloading, .paused, .verifying: self = .active
        case .installed: self = .installed
        case .failed: self = .failed
        }
    }
}

/// A model download while it runs, is paused, or is being verified, in one layout that never
/// changes size: the bar keeps its place and dims when paused, a single round button turns
/// between pause and play, the byte count rolls, and the background hint fades out instead of
/// collapsing. Used for Gemma (`ModelDownloadStateControl`: reflection, weekly digest, monthly
/// report, Write, Ask) and Ask's search model (Settings and Ask's card).
struct ModelDownloadProgressPanel: View {
    let state: ModelDownloadState
    var alignment: HorizontalAlignment = .center
    /// "Downloading in the background — …". Off in compact places (Ask's card).
    var showsBackgroundHint = true
    let onPause: () -> Void
    let onResume: () -> Void

    private var accent: Color { MirrorTheme.primary }

    enum Phase: Equatable {
        case downloading, paused, pausedFromStart, verifying
    }

    private struct Snapshot {
        let phase: Phase
        let fraction: Double
        let written: Int64
        let expected: Int64
    }

    private var snapshot: Snapshot? {
        switch state {
        case .downloading(let progress, let written, let expected):
            return Snapshot(phase: .downloading, fraction: progress, written: written, expected: expected)
        case .paused(let resumable, let written, let expected):
            let fraction = resumable && expected > 0 ? Double(written) / Double(expected) : 0
            return Snapshot(phase: resumable ? .paused : .pausedFromStart, fraction: fraction, written: resumable ? written : 0, expected: expected)
        case .verifying:
            return Snapshot(phase: .verifying, fraction: 1, written: 0, expected: 0)
        default:
            return nil
        }
    }

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowsNonnumericFormatting = false   // "0 KB", not "Zero KB"
        return f
    }()

    var body: some View {
        if let snap = snapshot {
            VStack(alignment: alignment, spacing: 10) {
                HStack(spacing: 12) {
                    ModelDownloadBar(fraction: snap.fraction, phase: snap.phase, accent: accent)
                    toggleButton(snap.phase)
                }
                HStack(alignment: .firstTextBaseline) {
                    bytesLabel(snap)
                    Spacer(minLength: 8)
                    statusLabel(snap)
                }
                if showsBackgroundHint {
                    Text("Downloading in the background — lock your phone or switch apps freely, just don't force-quit.")
                        .scaledFont(11, weight: .regular, design: .default)
                        .kerning(0)
                        .foregroundStyle(MirrorTheme.textTertiary)
                        .multilineTextAlignment(alignment == .center ? .center : .leading)
                        .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        // Kept in the layout while paused, so the card doesn't change height.
                        .opacity(snap.phase == .downloading ? 1 : 0)
                        .accessibilityHidden(snap.phase != .downloading)
                }
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.86), value: snap.phase)
        }
    }

    @ViewBuilder
    private func bytesLabel(_ snap: Snapshot) -> some View {
        Group {
            if snap.phase == .verifying {
                Text("Verifying…")
            } else if snap.phase == .pausedFromStart {
                Text("Paused (will restart from 0%)")
            } else {
                Text("\(Self.byteFormatter.string(fromByteCount: snap.written)) of \(Self.byteFormatter.string(fromByteCount: snap.expected))")
                    .contentTransition(.numericText(value: Double(snap.written)))
            }
        }
        .font(.system(size: 12, weight: .medium).monospacedDigit())
        .foregroundStyle(MirrorTheme.textSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .animation(.linear(duration: 0.35), value: snap.written)
    }

    @ViewBuilder
    private func statusLabel(_ snap: Snapshot) -> some View {
        Group {
            switch snap.phase {
            case .downloading:
                Text(snap.fraction, format: .percent.precision(.fractionLength(0)))
                    .contentTransition(.numericText(value: snap.fraction))
                    .foregroundStyle(accent)
            case .paused:
                Text("Paused")
                    .foregroundStyle(MirrorTheme.textSecondary)
            case .pausedFromStart, .verifying:
                EmptyView()
            }
        }
        .font(.system(size: 12, weight: .semibold).monospacedDigit())
        .transition(.opacity)
        .animation(.linear(duration: 0.35), value: snap.fraction)
    }

    @ViewBuilder
    private func toggleButton(_ phase: Phase) -> some View {
        let isRunning = phase == .downloading
        ZStack {
            if phase == .verifying {
                ProgressView()
                    .controlSize(.small)
                    .tint(accent)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Button {
                    if isRunning { onPause() } else { onResume() }
                } label: {
                    Image(systemName: isRunning ? "pause.fill" : "play.fill")
                        .scaledFont(13, weight: .bold)
                        .foregroundStyle(isRunning ? accent : Color.white)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 34, height: 34)
                        .background {
                            buttonShape
                                .fill(isRunning ? accent.opacity(0.14) : accent)
                        }
                        .contentShape(buttonShape)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isRunning ? Text("Pause") : Text("Resume"))
                .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 34, height: 34)
    }

    private var buttonShape: AnyShape {
        AnyShape(Circle())
    }
}

/// The bar: fills with progress and a soft light that runs along it while downloading, dims and
/// rests while paused, and shimmers full-width while the file is checked. Still under Reduce Motion.
private struct ModelDownloadBar: View {
    let fraction: Double
    let phase: ModelDownloadProgressPanel.Phase
    let accent: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var height: CGFloat { 8 }
    private var isMoving: Bool { (phase == .downloading || phase == .verifying) && !reduceMotion }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let fill = max(phase == .pausedFromStart ? 0 : height, width * min(max(fraction, 0), 1))
            ZStack(alignment: .leading) {
                shape.fill(Color.primary.opacity(0.10))
                shape
                    .fill(accent.opacity(phase == .paused || phase == .pausedFromStart ? 0.38 : 1))
                    .frame(width: fill)
                    .overlay {
                        if isMoving {
                            ModelDownloadShine()
                                .clipShape(shape)
                                .transition(.opacity)
                        }
                    }
                    .animation(.linear(duration: 0.35), value: fraction)
            }
        }
        .frame(height: height)
        .animation(.easeInOut(duration: 0.3), value: phase)
        .accessibilityElement()
        .accessibilityLabel(Text("Download progress"))
        .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
    }

    private var shape: AnyShape {
        AnyShape(Capsule())
    }
}

/// A soft highlight that sweeps left to right, forever.
private struct ModelDownloadShine: View {
    @State private var offset: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            LinearGradient(colors: [.white.opacity(0), .white.opacity(0.45), .white.opacity(0)], startPoint: .leading, endPoint: .trailing)
                .frame(width: max(40, geo.size.width * 0.35))
                .offset(x: offset * (geo.size.width + 40))
                .onAppear {
                    withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { offset = 1 }
                }
        }
        .allowsHitTesting(false)
    }
}

/// The button that starts (or retries) a model download, the same everywhere: Gemma's card, the
/// search model's Settings screen and Ask's card. An icon, the title, and the download's size on
/// the trailing edge (a number, so it needs no translation); `compact` for small cards.
struct ModelDownloadButton: View {
    let title: LocalizedStringKey
    var systemImage = "arrow.down"
    /// Shown as "806 MB" on the trailing edge; nil hides it (Try Again).
    var byteCount: Int64? = nil
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: compact ? 8 : 10) {
                Image(systemName: systemImage)
                    .scaledFont(compact ? 12 : 14, weight: .bold)
                    .frame(width: compact ? 22 : 28, height: compact ? 22 : 28)
                    .background(.white.opacity(0.2), in: Circle())
                Text(title)
                    .scaledFont(compact ? 14 : 16, weight: .semibold, design: .default)
                    .kerning(0)
                    // A second line only when the title doesn't fit (large text sizes). Not an
                    // @Environment(\.dynamicTypeSize) check: that property on this struct made
                    // SettingsView crash on open in Debug builds on device (2026-10-24).
                    .lineLimit(1...2)
                    .minimumScaleFactor(0.8)
                if let byteCount {
                    Spacer(minLength: 8)
                    Text(ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file))
                        .font(.system(size: compact ? 12 : 13, weight: .semibold).monospacedDigit())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.18), in: Capsule())
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            .padding(.leading, compact ? 8 : 12)
            .padding(.trailing, compact ? 10 : 14)
            .frame(maxWidth: byteCount == nil && compact ? nil : .infinity, minHeight: compact ? 38 : 52)
            .background(fill, in: shape)
            .contentShape(shape)
        }
        .buttonStyle(PressScaleButtonStyle())
        .shadow(color: MirrorTheme.primary.opacity(compact ? 0.18 : 0.26), radius: compact ? 8 : 14, x: 0, y: compact ? 3 : 6)
    }

    private var fill: AnyShapeStyle {
        AnyShapeStyle(MirrorTheme.accentGradient)
    }

    private var shape: AnyShape {
        AnyShape(RoundedRectangle(cornerRadius: compact ? 12 : 16, style: .continuous))
    }
}

/// Presses down a little, and springs back.
private struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
