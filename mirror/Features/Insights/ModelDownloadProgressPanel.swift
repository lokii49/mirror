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

    @Environment(\.appDisplayMode) private var displayMode
    private var isSentinel: Bool { displayMode == .sentinel }
    private var accent: Color { isSentinel ? MirrorTheme.ember : MirrorTheme.primary }

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
                    ModelDownloadBar(fraction: snap.fraction, phase: snap.phase, accent: accent, isSentinel: isSentinel)
                    toggleButton(snap.phase)
                }
                HStack(alignment: .firstTextBaseline) {
                    bytesLabel(snap)
                    Spacer(minLength: 8)
                    statusLabel(snap)
                }
                if showsBackgroundHint {
                    Text(isSentinel ? "DOWNLOADING IN BACKGROUND — DO NOT FORCE-QUIT" : "Downloading in the background — lock your phone or switch apps freely, just don't force-quit.")
                        .font(isSentinel ? MirrorTheme.mono(9.5, weight: .semibold) : .system(size: 11))
                        .kerning(isSentinel ? 0.3 : 0)
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
                Text(isSentinel ? "VERIFYING…" : "Verifying…")
            } else if snap.phase == .pausedFromStart {
                Text(isSentinel ? "PAUSED (WILL RESTART FROM 0%)" : "Paused (will restart from 0%)")
            } else {
                Text("\(Self.byteFormatter.string(fromByteCount: snap.written)) of \(Self.byteFormatter.string(fromByteCount: snap.expected))")
                    .contentTransition(.numericText(value: Double(snap.written)))
            }
        }
        .font(isSentinel ? MirrorTheme.mono(12, weight: .medium) : .system(size: 12, weight: .medium).monospacedDigit())
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
                Text(isSentinel ? "PAUSED" : "Paused")
                    .foregroundStyle(MirrorTheme.textSecondary)
            case .pausedFromStart, .verifying:
                EmptyView()
            }
        }
        .font(isSentinel ? MirrorTheme.mono(12, weight: .bold) : .system(size: 12, weight: .semibold).monospacedDigit())
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
                        .font(.system(size: 13, weight: .bold))
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
        isSentinel ? AnyShape(RoundedRectangle(cornerRadius: 7, style: .continuous)) : AnyShape(Circle())
    }
}

/// The bar: fills with progress and a soft light that runs along it while downloading, dims and
/// rests while paused, and shimmers full-width while the file is checked. Still under Reduce Motion.
private struct ModelDownloadBar: View {
    let fraction: Double
    let phase: ModelDownloadProgressPanel.Phase
    let accent: Color
    let isSentinel: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var height: CGFloat { isSentinel ? 6 : 8 }
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
        isSentinel ? AnyShape(RoundedRectangle(cornerRadius: 2, style: .continuous)) : AnyShape(Capsule())
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
