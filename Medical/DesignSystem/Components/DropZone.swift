import SwiftUI

/// A dashed well that accepts a drop or a click.
struct DropZone: View {
    var title: String = "Drop files here, or click to choose"
    var height: CGFloat = 150
    var onChoose: () -> Void
    var onDrop: ([URL]) -> Void

    @State private var isTargeted = false

    var body: some View {
        Button(action: onChoose) {
            VStack(spacing: 10) {
                Image(systemName: "arrow.down.document")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(isTargeted ? Palette.selection : Palette.tertiaryText)
                Text(title)
                    .font(.callout)
                    .foregroundStyle(Palette.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                isTargeted ? Palette.selection.opacity(0.06) : Color.clear,
                in: .rect(cornerRadius: Metrics.cardRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .strokeBorder(
                        isTargeted ? Palette.selection : Palette.separator,
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                    )
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .dropDestination(for: URL.self) { urls, _ in
            onDrop(urls)
            return true
        } isTargeted: { isTargeted = $0 }
        .animation(.easeOut(duration: 0.15), value: isTargeted)
    }
}

/// A step heading, used by the record editor.
struct StepTitle: View {
    let title: String
    let subtitle: String

    init(_ title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title2.weight(.semibold))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
