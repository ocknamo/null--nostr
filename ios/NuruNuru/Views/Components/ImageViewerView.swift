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

            // Pager
            TabView(selection: $currentIndex) {
                ForEach(images.indices, id: \.self) { i in
                    ZoomableImageView(url: images[i], authorPubkey: authorPubkey, onZoomChanged: { isZoomed = $0 })
                        .tag(i)
                        .ignoresSafeArea()
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .disabled(isZoomed) // lock paging when zoomed

            // Top bar
            HStack {
                // Page counter (only when multiple)
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

                // Close button
                Button(action: onDismiss) {
                    Image(systemName: NuruIcons.close)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, NuruSpacing.space4)
            .padding(.top, NuruSpacing.space4)

            // Page dots indicator (only when multiple)
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
            }
        }
    }
}

// MARK: - Zoomable Image

private struct ZoomableImageView: View {
    let url: String
    let authorPubkey: String?
    let onZoomChanged: (Bool) -> Void

    @State private var scale: CGFloat   = 1.0
    @State private var offset: CGSize   = .zero
    @State private var isError          = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                if isError {
                    Text("画像を読み込めませんでした")
                        .foregroundStyle(Color.white.opacity(0.7))
                        .font(NuruFont.bodyMedium())
                } else {
                    CachedAsyncImage(url: URL(string: url), authorPubkey: authorPubkey, contentMode: .fit) {
                        Color.black.overlay(ProgressView().tint(.white))
                    }
                    .frame(maxWidth: geo.size.width, maxHeight: geo.size.height)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(doubleTapGesture)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let newScale = (scale * value).clamped(to: 1...5)
                                scale = newScale
                                onZoomChanged(newScale > 1)
                            }
                            .onEnded { _ in
                                if scale < 1 { scale = 1; offset = .zero; onZoomChanged(false) }
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                if scale > 1 { offset = value.translation }
                            }
                            .onEnded { _ in
                                if scale <= 1 { offset = .zero }
                            }
                    )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var doubleTapGesture: some Gesture {
        TapGesture(count: 2).onEnded {
            withAnimation(.spring(duration: 0.25)) {
                if scale > 1.5 {
                    scale  = 1
                    offset = .zero
                    onZoomChanged(false)
                } else {
                    scale = 2.5
                    onZoomChanged(true)
                }
            }
        }
    }
}

// MARK: - Comparable+clamped helper (local)

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
