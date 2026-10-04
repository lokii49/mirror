import SwiftUI

struct FullscreenPhotoView: View {
    let photoData: Data
    var onDismiss: (() -> Void)? = nil

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appDisplayMode) private var displayMode

    private static var doneEdge: ToolbarItemPlacement {
        #if os(macOS)
        return .cancellationAction
        #else
        return .topBarLeading
        #endif
    }

    private static var shareEdge: ToolbarItemPlacement {
        #if os(macOS)
        return .primaryAction
        #else
        return .topBarTrailing
        #endif
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack {
                    Color.black.ignoresSafeArea()
                    if let image = UIImage(data: photoData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(scale)
                            .offset(offset)
                            .gesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        scale = lastScale * value
                                    }
                                    .onEnded { _ in
                                        if scale < 1 {
                                            withAnimation(.spring()) { scale = 1; offset = .zero }
                                        }
                                        lastScale = scale
                                    }
                                    .simultaneously(with: DragGesture()
                                        .onChanged { value in
                                            if scale > 1 {
                                                offset = CGSize(
                                                    width: lastOffset.width + value.translation.width,
                                                    height: lastOffset.height + value.translation.height
                                                )
                                            }
                                        }
                                        .onEnded { _ in
                                            lastOffset = offset
                                        }
                                    )
                            )
                            .onTapGesture(count: 2) {
                                withAnimation(.spring()) {
                                    if scale > 1 { scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero }
                                    else { scale = 2; lastScale = 2 }
                                }
                            }
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: Self.doneEdge) {
                    Button {
                        onDismiss?()
                        dismiss()
                    } label: {
                        if displayMode == .sentinel {
                            Text("DONE").font(MirrorTheme.mono(15, weight: .medium))
                        } else {
                            Text("Done").fontWeight(.medium)
                        }
                    }
                    .foregroundStyle(displayMode == .sentinel ? MirrorTheme.ember : .white)
                    .cancelActionOnMac()
                }
                ToolbarItem(placement: Self.shareEdge) {
                    if let image = UIImage(data: photoData) {
                        ShareLink(item: Image(uiImage: image), preview: SharePreview("Photo", image: Image(uiImage: image))) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            #if os(iOS)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            #endif
        }
        #if os(macOS)
        // On Mac the full-screen cover is a plain sheet with no size of its own; without one the
        // viewer collapses to a strip. It sizes to the photo's shape, up to most of the screen.
        .frame(minWidth: 560, idealWidth: 880, maxWidth: .infinity, minHeight: 420, idealHeight: 640, maxHeight: .infinity)
        #endif
    }
}
