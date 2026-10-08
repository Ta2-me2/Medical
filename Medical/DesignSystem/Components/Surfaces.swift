import SwiftUI

/// A card: a rounded surface with a hairline edge and no shadow.
///
/// The hairline does the separating that a shadow would otherwise do, which is
/// why the interface stays flat and quiet even with a dozen cards on screen.
struct CardSurface: ViewModifier {
    var padding: CGFloat = Metrics.cardPadding
    var isEmphasised: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: .rect(cornerRadius: Metrics.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .strokeBorder(
                        isEmphasised ? Palette.selection.opacity(0.55) : Palette.separator,
                        lineWidth: isEmphasised ? 1.5 : 1
                    )
            }
    }
}

extension View {
    func cardSurface(padding: CGFloat = Metrics.cardPadding, isEmphasised: Bool = false) -> some View {
        modifier(CardSurface(padding: padding, isEmphasised: isEmphasised))
    }

    /// Standard page padding. Applied by every screen so nothing drifts.
    func pageInsets() -> some View {
        padding(.horizontal, Metrics.gutter)
            .padding(.vertical, Metrics.pageTop)
    }
}

/// The large title block at the top of a page.
struct PageHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.largeTitle.weight(.semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(Palette.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A quiet uppercase rule above a group of content.
struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.secondaryText)
            Spacer(minLength: 12)
            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title: title) { EmptyView() }
    }
}

/// A label/value line, as used on the patient page and in detail panels.
struct InfoRow<Value: View>: View {
    let label: String
    @ViewBuilder var value: Value

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .foregroundStyle(Palette.secondaryText)
                .frame(width: 150, alignment: .leading)
            value
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.body)
    }
}

extension InfoRow where Value == Text {
    init(_ label: String, _ value: String) {
        self.init(label: label) { Text(value) }
    }
}

/// Rows stacked inside one card with hairlines between them, the way grouped
/// lists look in System Settings.
struct GroupedRows<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(Palette.card, in: .rect(cornerRadius: Metrics.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(Palette.separator, lineWidth: 1)
        }
    }
}

/// One row inside `GroupedRows`.
struct GroupedRow<Content: View>: View {
    var showsDivider: Bool = true
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(.horizontal, Metrics.cardPadding)
                .padding(.vertical, 11)
            if showsDivider {
                Divider().padding(.leading, Metrics.cardPadding)
            }
        }
    }
}
