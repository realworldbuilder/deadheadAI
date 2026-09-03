import SwiftUI
import UIKit

/// One page of the full-screen viewer.
struct ImageViewerPage: Identifiable, Hashable {
    let url: URL
    /// Short kind label shown under the image ("Ticket").
    let caption: String
    let accessibilityLabel: String

    var id: URL { url }
}

/// Full-screen, swipeable, pinch-zoomable pager over remote images — black
/// in both appearances. Swipe between pages at 1x; a zoomed page keeps its
/// pans. Single tap hides the chrome, double tap toggles zoom, swipe down
/// (or the close button, or the VoiceOver escape) dismisses.
struct ImageViewer: View {
    let pages: [ImageViewerPage]
    var credit: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index: Int
    @State private var chromeHidden = false
    @State private var zoomedPages: Set<Int> = []
    @State private var dragOffset: CGFloat = 0
    /// Latched on the first movement so a page swipe that drifts can't
    /// turn into a dismiss.
    @State private var dragIsVertical: Bool?

    init(pages: [ImageViewerPage], initialIndex: Int = 0, credit: String? = nil) {
        self.pages = pages
        self.credit = credit
        let clamped = pages.isEmpty ? 0 : min(max(initialIndex, 0), pages.count - 1)
        _index = State(initialValue: clamped)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { offset, page in
                    ZoomableImagePage(page: page, isZoomed: zoomedBinding(offset)) {
                        withAnimation(.easeInOut(duration: 0.2)) { chromeHidden.toggle() }
                    }
                    .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            .offset(y: dragOffset)
        }
        .overlay(alignment: .top) { topChrome }
        .overlay(alignment: .bottom) { bottomChrome }
        .simultaneousGesture(dismissDrag)
        .preferredColorScheme(.dark)
        .presentationBackground(.black)
        .statusBarHidden(chromeHidden)
        .accessibilityAction(.escape) { dismiss() }
    }

    private var currentPage: ImageViewerPage? {
        pages.indices.contains(index) ? pages[index] : nil
    }

    private func zoomedBinding(_ offset: Int) -> Binding<Bool> {
        Binding(
            get: { zoomedPages.contains(offset) },
            set: { zoomed in
                if zoomed {
                    zoomedPages.insert(offset)
                } else {
                    zoomedPages.remove(offset)
                }
            })
    }

    // MARK: Chrome

    private var topChrome: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Close")
            Spacer()
            if let currentPage {
                ShareLink(item: currentPage.url) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Share scan")
            }
        }
        .padding(.horizontal, 8)
        .opacity(chromeHidden ? 0 : 1)
        .allowsHitTesting(!chromeHidden)
    }

    private var bottomChrome: some View {
        VStack(spacing: 8) {
            if let currentPage {
                Text(Self.caption(index: index, count: pages.count, label: currentPage.caption))
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
            }
            if pages.count > 1 {
                HStack(spacing: 6) {
                    ForEach(pages.indices, id: \.self) { i in
                        Circle()
                            .fill(.white.opacity(i == index ? 1 : 0.35))
                            .frame(width: 6, height: 6)
                    }
                }
                .accessibilityHidden(true)
            }
            if let credit {
                Text(credit)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.bottom, 12)
        .opacity(chromeHidden ? 0 : 1)
        .allowsHitTesting(false)
    }

    /// "Ticket · 2 of 3", or just the label for a single page.
    nonisolated static func caption(index: Int, count: Int, label: String) -> String {
        count > 1 ? "\(label) · \(index + 1) of \(count)" : label
    }

    // MARK: Dismiss

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                guard !zoomedPages.contains(index) else { return }
                let dy = value.translation.height, dx = value.translation.width
                if dragIsVertical == nil {
                    dragIsVertical = Self.isVerticalDrag(dx: dx, dy: dy)
                }
                guard dragIsVertical == true, dy > 0 else { return }
                if !reduceMotion { dragOffset = dy }
            }
            .onEnded { value in
                defer { dragIsVertical = nil }
                let dy = value.translation.height
                if dragIsVertical == true, !zoomedPages.contains(index),
                   Self.shouldDismiss(translation: dy, predictedEnd: value.predictedEndTranslation.height) {
                    dismiss()
                } else {
                    withAnimation(.snappy) { dragOffset = 0 }
                }
            }
    }

    /// A drag counts as a dismiss only when it is clearly downward.
    nonisolated static func isVerticalDrag(dx: CGFloat, dy: CGFloat) -> Bool {
        dy > 0 && abs(dy) > abs(dx) * 1.5
    }

    /// Far enough, or flicked hard enough.
    nonisolated static func shouldDismiss(translation: CGFloat, predictedEnd: CGFloat) -> Bool {
        translation > 0 && (translation > 120 || predictedEnd > 240)
    }
}

// MARK: - Page

/// One viewer page: loads its image through `ArchiveArtwork`, then hands
/// it to the zoomable scroll view. Transient failures can be retried.
struct ZoomableImagePage: View {
    let page: ImageViewerPage
    @Binding var isZoomed: Bool
    let onSingleTap: () -> Void

    @State private var image: UIImage?
    @State private var failed = false
    @State private var attempt = 0

    var body: some View {
        ZStack {
            if let image {
                ZoomableScrollView(image: image, isZoomed: $isZoomed, onSingleTap: onSingleTap)
            } else if failed {
                VStack(spacing: 12) {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.white.opacity(0.6))
                    Text("Couldn't load this scan")
                        .font(Theme.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                    Button("Retry") { attempt += 1 }
                        .buttonStyle(.bordered)
                        .tint(.white)
                }
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: "\(page.url.absoluteString)#\(attempt)") {
            let loaded = await ArchiveArtwork.shared.image(from: page.url)
            image = loaded
            failed = loaded == nil
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(page.accessibilityLabel)
        .accessibilityAddTraits(.isImage)
    }
}

// MARK: - Zoom

/// UIScrollView-backed zoom: pinch, pan, rubber-banding and double-tap
/// come from UIKit, and — the reason it isn't pure SwiftUI — at 1x with
/// bouncing off the scroll view refuses pans, so they fall through to the
/// pager and the dismiss gesture instead of fighting them.
struct ZoomableScrollView: UIViewRepresentable {
    let image: UIImage
    @Binding var isZoomed: Bool
    let onSingleTap: () -> Void

    func makeUIView(context: Context) -> ZoomableImageScrollView {
        let view = ZoomableImageScrollView()
        view.image = image
        return view
    }

    func updateUIView(_ view: ZoomableImageScrollView, context: Context) {
        view.image = image
        view.onSingleTap = onSingleTap
        view.onZoomChanged = { zoomed in isZoomed = zoomed }
    }
}

final class ZoomableImageScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    private var laidOutFor: CGSize = .zero
    private var lastZoomed = false

    var onZoomChanged: ((Bool) -> Void)?
    var onSingleTap: (() -> Void)?

    var image: UIImage? {
        get { imageView.image }
        set {
            guard newValue !== imageView.image else { return }
            imageView.image = newValue
            laidOutFor = .zero
            setNeedsLayout()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 6
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        bounces = false
        bouncesZoom = true
        backgroundColor = .clear
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(singleTap)
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != laidOutFor, bounds.width > 0, bounds.height > 0 {
            laidOutFor = bounds.size
            fitImage()
        }
        centerContent()
    }

    /// Lay the image out at 1x, aspect-fit inside the bounds, and let the
    /// maximum zoom reach the scan's native pixels (at least 2.5x).
    private func fitImage() {
        guard let image = imageView.image, image.size.width > 0, image.size.height > 0 else { return }
        zoomScale = 1
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let fitted = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        imageView.frame = CGRect(origin: .zero, size: fitted)
        contentSize = fitted
        contentOffset = .zero
        let pixelWidth = image.size.width * image.scale
        let native = pixelWidth / (fitted.width * max(traitCollection.displayScale, 1))
        maximumZoomScale = max(2.5, min(6, native))
    }

    private func centerContent() {
        let dx = max((bounds.width - contentSize.width) / 2, 0)
        let dy = max((bounds.height - contentSize.height) / 2, 0)
        contentInset = UIEdgeInsets(top: dy, left: dx, bottom: dy, right: dx)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerContent()
        let zoomed = zoomScale > 1.01
        if zoomed != lastZoomed {
            lastZoomed = zoomed
            bounces = zoomed
            onZoomChanged?(zoomed)
        }
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if zoomScale > 1.01 {
            setZoomScale(1, animated: true)
            return
        }
        let target = min(2.5, maximumZoomScale)
        let point = gesture.location(in: imageView)
        let size = CGSize(width: bounds.width / target, height: bounds.height / target)
        zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                        width: size.width, height: size.height), animated: true)
    }

    @objc private func handleSingleTap() {
        onSingleTap?()
    }
}
