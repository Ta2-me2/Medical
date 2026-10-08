import SwiftUI

/// The years of a life, listed down the left edge.
///
/// It is both a table of contents and a position indicator: clicking a year
/// jumps to it, and scrolling the events moves the highlight. The count beside
/// each year is what makes the shape of a medical history visible at a glance —
/// the quiet decades and the heavy ones.
struct YearRail: View {

    /// A year, and how many records it holds — everything the rail draws.
    ///
    /// Not the year groups themselves. Those carry every record in the year, and
    /// SwiftUI decides whether to redraw a view by comparing what it was given:
    /// handing the rail a thousand records meant comparing a thousand records,
    /// field by field, to draw forty numbers.
    struct Entry: Identifiable, Hashable {
        let year: Int
        let count: Int
        var id: Int { year }
    }

    let entries: [Entry]
    let activeYear: Int?
    var onSelect: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(entries) { entry in
                        row(for: entry)
                            .id(entry.year)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 8)
            }
            .onChange(of: activeYear) { _, year in
                guard let year else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(year, anchor: .center)
                }
            }
        }
        .frame(width: Metrics.yearRailWidth)
        .background(Palette.page)
    }

    private func row(for entry: Entry) -> some View {
        let isActive = entry.year == activeYear

        return Button {
            onSelect(entry.year)
        } label: {
            HStack(spacing: 6) {
                Text(String(entry.year))
                    .font(.system(.callout, design: .default))
                    .fontWeight(isActive ? .semibold : .regular)
                    .monospacedDigit()

                Spacer(minLength: 4)

                Text(entry.count.formatted())
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(isActive ? Color.white.opacity(0.8) : Palette.tertiaryText)
            }
            .foregroundStyle(isActive ? Color.white : Palette.primaryText)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Metrics.smallRadius, style: .continuous)
                    .fill(isActive ? Palette.selection : .clear)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isActive)
    }
}
