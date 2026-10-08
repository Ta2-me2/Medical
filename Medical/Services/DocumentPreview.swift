import AppKit
import Quartz
import QuickLookThumbnailing
import SwiftUI

/// The system Quick Look view, embedded.
///
/// Using the real thing rather than a PDF renderer means every format macOS can
/// preview works here for free — today's PDFs and JPEGs, and whatever formats a
/// clinic sends in fifteen years.
struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        view.autostarts = true
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? URL) != url {
            view.previewItem = url as NSURL
        }
    }
}

/// Thumbnails, generated once and kept for the life of the session.
///
/// An actor because generation is slow and concurrent: without it, scrolling a
/// grid would kick off the same render a dozen times.
actor ThumbnailCache {
    static let shared = ThumbnailCache()

    private var images: [UUID: NSImage] = [:]
    private var inFlight: [UUID: Task<NSImage?, Never>] = [:]

    func thumbnail(for id: UUID, url: URL, size: CGSize, scale: CGFloat) async -> NSImage? {
        if let cached = images[id] { return cached }
        if let running = inFlight[id] { return await running.value }

        let task = Task<NSImage?, Never> {
            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: size,
                scale: scale,
                representationTypes: .thumbnail
            )
            let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            return representation.map { NSImage(cgImage: $0.cgImage, size: size) }
        }

        inFlight[id] = task
        let image = await task.value
        inFlight[id] = nil
        if let image { images[id] = image }
        return image
    }
}

/// A document thumbnail with a symbol placeholder while it renders.
struct DocumentThumbnail: View {
    let document: StoredDocument
    let url: URL
    var size: CGSize = CGSize(width: 150, height: 194)

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Metrics.smallRadius, style: .continuous)
                .fill(Palette.card)

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(.rect(cornerRadius: Metrics.smallRadius, style: .continuous))
            } else {
                Image(systemName: document.kind.symbol)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Palette.tertiaryText)
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.smallRadius, style: .continuous)
                .strokeBorder(Palette.separator, lineWidth: 1)
        }
        .task(id: document.id) {
            image = await ThumbnailCache.shared.thumbnail(
                for: document.id,
                url: url,
                size: size,
                scale: 2
            )
        }
    }
}
