import SwiftUI

/// A result table, as a doctor reads it.
///
/// Plain rules and one weight of type. A table of blood values does not need
/// decoration; it needs the numbers to line up and the abnormal ones to be
/// findable without reading every line.
struct ResultTableView: View {
    let table: ResultTable

    /// Supplied where the table can be changed. A context menu alone is not an
    /// affordance: nobody right-clicks a table to find out whether it can be
    /// edited, so a table with no visible control reads as permanent.
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if table.title.nilIfEmpty != nil || onEdit != nil {
                HStack(spacing: 8) {
                    if let title = table.title.nilIfEmpty {
                        Text(title)
                            .font(.headline)
                    }

                    Spacer(minLength: 8)

                    if let onEdit {
                        Button("Edit", action: onEdit)
                            .buttonStyle(.link)
                            .font(.subheadline)
                    }
                    if let onDelete {
                        Button {
                            onDelete()
                        } label: {
                            Image(systemName: "trash")
                                .imageScale(.small)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.tertiaryText)
                        .help("Delete this table")
                    }
                }
                .opacity(onEdit == nil || isHovering ? 1 : 0.55)
                .animation(.easeOut(duration: 0.12), value: isHovering)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow {
                        ForEach(Array(table.columns.enumerated()), id: \.offset) { _, column in
                            cell(column, isHeader: true, isAbnormal: false)
                        }
                    }

                    ForEach(table.rows) { row in
                        GridRow {
                            ForEach(Array(PDFCells.padded(row.cells, to: table.columns.count).enumerated()), id: \.offset) { index, value in
                                cell(
                                    value,
                                    isHeader: false,
                                    isAbnormal: row.isAbnormal,
                                    isFirst: index == 0
                                )
                            }
                        }
                    }
                }
                .background(Palette.card, in: .rect(cornerRadius: Metrics.smallRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Metrics.smallRadius, style: .continuous)
                        .strokeBorder(Palette.separator, lineWidth: 1)
                }
            }

            if let note = table.note?.nilIfEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
            }
        }
        .onHover { isHovering = $0 }
    }

    private func cell(
        _ text: String,
        isHeader: Bool,
        isAbnormal: Bool,
        isFirst: Bool = false
    ) -> some View {
        Text(text.nilIfEmpty ?? "—")
            .font(isHeader ? .caption.weight(.semibold) : .callout)
            .foregroundStyle(foreground(isHeader: isHeader, isAbnormal: isAbnormal, isFirst: isFirst))
            .monospacedDigit()
            .textSelection(.enabled)
            .frame(minWidth: 96, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(background(isHeader: isHeader, isAbnormal: isAbnormal))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Palette.separator)
                    .frame(height: 1)
            }
    }

    private func foreground(isHeader: Bool, isAbnormal: Bool, isFirst: Bool) -> Color {
        if isHeader { return Palette.secondaryText }
        if isAbnormal { return Palette.critical }
        return isFirst ? Palette.primaryText : Palette.primaryText
    }

    private func background(isHeader: Bool, isAbnormal: Bool) -> Color {
        if isHeader { return Palette.subtleFill.opacity(0.6) }
        if isAbnormal { return Palette.critical.opacity(0.06) }
        return .clear
    }
}

/// Row padding shared between the on-screen table and the exported one, so the
/// PDF and the window can never disagree about a ragged row.
nonisolated enum PDFCells {
    static func padded(_ cells: [String], to count: Int) -> [String] {
        var result = cells
        while result.count < count { result.append("") }
        if result.count > count { result.removeLast(result.count - count) }
        return result
    }
}
