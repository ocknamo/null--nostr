import SwiftUI

/// フルスクリーン画像ビューア — 複数画像をスワイプ閲覧 + ピンチズーム + ダブルタップズーム.
/// Mirrors Android ImageViewerDialog.kt.
/// Usage: .fullScreenCover(isPresented:) { ImageViewerView(images:initialIndex:onDismiss:) }
struct ImageViewerView: View {
    let images: [String]
    let authorPubkey: String?
    let initialIndex: Int
    let onDismiss: () -> Void

    @State private var currentIndex: Int
    @State private var isZoomed = false

    init(images: [String], authorPubkey: String? = nil, initialIndex: Int = 0, onDismiss: @escaping () -> Void) {
        self.images = images
        self.authorPubkey = authorPubkey
        self.initialIndex = initialIndex.clamped(to: 0...(max(0, images.count - 1)))
        self.onDismiss = onDismiss
        _currentIndex = State(initialValue: initialIndex.clamped(to: 0...(max(0, images.count - 1))))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(images.indices, id: \.self) { i in
                    ZoomableImageView(url: images[i], authorPubkey: authorPubkey, onZoomChanged: { isZoomed = $0 })
                        .tag(i)
                        .ignoresSafeArea()
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            // `.disabled(isZoomed)` は子ビューのダブルタップ/ドラッグまで無効化してしまうため使わない。
            // ズーム中の操作は ZoomableImageView 側のジェスチャーで処理する。

            HStack {
                if images.count > 1 {
                    Text("\(currentIndex + 1) / \(images.count)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.55))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: NuruIcons.close)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .zIndex(10)
            }
            .padding(.horizontal, NuruSpacing.space4)
            .padding(.top, NuruSpacing.space4)
            .allowsHitTesting(true)

            if images.count > 1 {
                VStack {
                    Spacer()
                    HStack(spacing: 6) {
                        ForEach(images.indices, id: \.self) { i in
                            Circle()
                                .fill(Color.white.opacity(i == currentIndex ? 1 : 0.4))
                                .frame(width: i == currentIndex ? 8 : 6,
                                       height: i == currentIndex ? 8 : 6)
                                .animation(.easeInOut(duration: 0.15), value: currentIndex)
                        }
                    }
                    .padding(.bottom, 32)
                }
                .allowsHitTesting(false)
            }
        }
    }
}

private struct ZoomableImageView: View {
    let url: String
    let authorPubkey: String?
    let onZoomChanged: (Bool) -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                CachedAsyncImage(url: URL(string: url), authorPubkey: authorPubkey, contentMode: .fit) {
                    Color.black.overlay(ProgressView().tint(.white))
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .scaleEffect(scale)
                .offset(offset)
                .contentShape(Rectangle())
                .highPriorityGesture(doubleTapGesture)
                .simultaneousGesture(magnifyGesture(container: geo.size))
                .simultaneousGesture(dragGesture(container: geo.size))
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onDisappear { resetZoom(animated: false) }
    }

    private func magnifyGesture(container: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let newScale = (lastScale * value).clamped(to: 1...5)
                scale = newScale
                if newScale <= 1.01 {
                    offset = .zero
                } else {
                    offset = clampedOffset(offset, scale: newScale, container: container)
                }
                onZoomChanged(newScale > 1.01)
            }
            .onEnded { _ in
                if scale <= 1.01 {
                    resetZoom(animated: true)
                } else {
                    scale = scale.clamped(to: 1...5)
                    offset = clampedOffset(offset, scale: scale, container: container)
                    lastScale = scale
                    lastOffset = offset
                    onZoomChanged(true)
                }
            }
    }

    private func dragGesture(container: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard scale > 1.01 else { return }
                let proposed = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
                offset = clampedOffset(proposed, scale: scale, container: container)
            }
            .onEnded { _ in
                guard scale > 1.01 else {
                    offset = .zero
                    lastOffset = .zero
                    return
                }
                lastOffset = offset
            }
    }

    private var doubleTapGesture: some Gesture {
        TapGesture(count: 2).onEnded {
            if scale > 1.01 {
                resetZoom(animated: true)
            } else {
                withAnimation(.spring(duration: 0.25)) {
                    scale = 2.5
                    lastScale = 2.5
                    offset = .zero
                    lastOffset = .zero
                    onZoomChanged(true)
                }
            }
        }
    }

    private func resetZoom(animated: Bool) {
        let changes = {
            scale = 1
            lastScale = 1
            offset = .zero
            lastOffset = .zero
            onZoomChanged(false)
        }
        if animated {
            withAnimation(.spring(duration: 0.25)) { changes() }
        } else {
            changes()
        }
    }

    private func clampedOffset(_ value: CGSize, scale: CGFloat, container: CGSize) -> CGSize {
        guard scale > 1 else { return .zero }
        let maxX = max(0, container.width * (scale - 1) / 2)
        let maxY = max(0, container.height * (scale - 1) / 2)
        return CGSize(
            width: value.width.clamped(to: -maxX...maxX),
            height: value.height.clamped(to: -maxY...maxY)
        )
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
