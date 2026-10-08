import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A chosen image, wrapped so it can drive a sheet.
nonisolated struct LoadedImage: Identifiable {
    let id = UUID()
    let image: NSImage
}

/// Positioning a photograph inside the circle it will be shown in.
///
/// Drag to move, pinch or use the slider to zoom. What is rendered is exactly
/// what the circle covers, so the result cannot differ from the preview.
struct AvatarEditor: View {
    @Environment(\.dismiss) private var dismiss

    let image: NSImage
    var onSave: (Data) -> Void

    /// The diameter the crop is rendered at. Generous enough for a Retina
    /// display at the largest size the app shows an avatar.
    private static let outputSize: CGFloat = 512
    private static let previewSize: CGFloat = 320

    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var dragOffset: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        VStack(spacing: 20) {
            Text("Position the Photo")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            preview

            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle")
                    .foregroundStyle(Palette.tertiaryText)
                Slider(value: $zoom, in: 1...4)
                Image(systemName: "person.crop.circle.fill")
                    .foregroundStyle(Palette.tertiaryText)
            }

            Text("Drag to move, or pinch on the trackpad.")
                .font(.caption)
                .foregroundStyle(Palette.secondaryText)

            HStack {
                Button("Reset") {
                    withAnimation(.easeOut(duration: 0.2)) {
                        zoom = 1
                        offset = .zero
                    }
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Use Photo") {
                    if let data = renderedPNG() { onSave(data) }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
        }
        .padding(20)
        .frame(width: 380)
    }

    // MARK: - Preview

    private var currentZoom: CGFloat { min(max(zoom * pinch, 1), 4) }

    private var currentOffset: CGSize {
        CGSize(width: offset.width + dragOffset.width, height: offset.height + dragOffset.height)
    }

    private var preview: some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: Self.previewSize, height: Self.previewSize)
            .scaleEffect(currentZoom)
            .offset(currentOffset)
            .frame(width: Self.previewSize, height: Self.previewSize)
            .clipShape(.circle)
            .overlay { Circle().strokeBorder(Palette.separator, lineWidth: 1) }
            .contentShape(.circle)
            .gesture(
                DragGesture()
                    .updating($dragOffset) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        offset.width += value.translation.width
                        offset.height += value.translation.height
                    }
            )
            .gesture(
                MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { value in
                        zoom = min(max(zoom * value.magnification, 1), 4)
                    }
            )
    }

    // MARK: - Rendering

    /// Draws the same transform into a square bitmap and returns it as PNG.
    ///
    /// The circle is not baked into the file: the image stays square and every
    /// place that shows it clips to a circle. That way a future layout can crop
    /// it differently without the corners having been thrown away.
    private func renderedPNG() -> Data? {
        let side = Self.outputSize
        let scale = side / Self.previewSize

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(side),
            pixelsHigh: Int(side),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        defer { NSGraphicsContext.restoreGraphicsState() }

        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: side, height: side).fill()

        // `aspectRatio(.fill)` in the preview scales the shorter edge to the
        // frame; the same rule here keeps what is drawn identical to what was
        // shown.
        let source = image.size
        guard source.width > 0, source.height > 0 else { return nil }

        let fill = max(side / source.width, side / source.height) * currentZoom
        let drawn = CGSize(width: source.width * fill, height: source.height * fill)

        let origin = CGPoint(
            x: (side - drawn.width) / 2 + currentOffset.width * scale,
            // AppKit's y axis runs the other way from SwiftUI's.
            y: (side - drawn.height) / 2 - currentOffset.height * scale
        )

        image.draw(
            in: NSRect(origin: origin, size: drawn),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )

        return bitmap.representation(using: .png, properties: [:])
    }
}

/// The avatar wherever it is shown: the photograph if there is one, initials if
/// there is not.
///
/// A personal archive should not ship with a stock silhouette; until a photo is
/// chosen, the person's own initials are the truest thing available.
struct PatientAvatar: View {
    let patient: Patient
    let url: URL?
    var size: CGFloat = Metrics.avatarSmall

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(.circle)
            } else {
                AvatarView(initials: patient.initials, size: size)
            }
        }
        .task(id: url?.path()) {
            guard let url else {
                image = nil
                return
            }
            image = NSImage(contentsOf: url)
        }
    }
}
