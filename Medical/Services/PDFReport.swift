import AppKit
import CoreText
import Foundation

/// Renders a paginated PDF from a list of blocks.
///
/// Built on Core Text rather than a screenshot of a view, because an exported
/// medical record has to carry selectable, searchable text — a doctor receiving
/// it should be able to copy a diagnosis out of it, and a picture of words is
/// not a document.
///
/// Laid out block by block rather than as one continuous text flow, because the
/// tables are the point of this report and a text flow cannot draw one. Each
/// block measures itself, is placed if it fits, and otherwise continues on the
/// next page — tables repeat their header when they break.
nonisolated enum PDFReport {

    enum Block {
        case text(String, TextStyle)
        case table(ResultTable)
        /// Label-and-value lines for one record.
        case fields([Field])
        case rule
        case space(CGFloat)
        case pageBreak

        static func title(_ text: String) -> Block { .text(text, .title) }
        static func heading(_ text: String) -> Block { .text(text, .heading) }
        static func subheading(_ text: String) -> Block { .text(text, .subheading) }
        static func body(_ text: String) -> Block { .text(text, .body) }
        static func caption(_ text: String) -> Block { .text(text, .caption) }

        /// Drops anything with no value, so a record only shows what it knows.
        static func fields(_ pairs: [(String, String?)]) -> Block {
            .fields(pairs.compactMap { label, value in
                value?.nilIfEmpty.map { Field(label: label, value: $0) }
            })
        }
    }

    /// One line of a record's details.
    ///
    /// Deliberately not a table: records hold different things, and a table
    /// forces every row under one header. Nine columns of which six are empty
    /// is how a report becomes unreadable. Labelled lines carry exactly what a
    /// record has and nothing else, and two records with different fields still
    /// look like the same document.
    struct Field {
        var label: String
        var value: String
    }

    enum TextStyle {
        case title
        case heading
        case subheading
        case body
        case caption
    }

    // A4 at 72 dpi, with margins wide enough to stay readable when printed.
    private static let pageSize = CGSize(width: 595, height: 842)
    private static let margin: CGFloat = 56
    private static let footerHeight: CGFloat = 34

    private static var contentWidth: CGFloat { pageSize.width - margin * 2 }
    private static var contentTop: CGFloat { pageSize.height - margin }
    private static var contentBottom: CGFloat { margin + footerHeight }

    // MARK: - Entry point

    static func render(_ blocks: [Block], title: String, to url: URL) throws {
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        let info: [CFString: Any] = [
            kCGPDFContextTitle: title,
            kCGPDFContextCreator: "Medical",
        ]

        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, info as CFDictionary) else {
            throw ArchiveError.importFailed("Could not create the PDF context.")
        }

        var layout = Layout(context: context)
        layout.beginPage()

        for block in blocks {
            switch block {
            case .text(let string, let style):
                layout.draw(text: string, style: style)
            case .table(let table):
                layout.draw(table: table)
            case .fields(let fields):
                layout.draw(fields: fields)
            case .rule:
                layout.drawRule()
            case .space(let height):
                layout.advance(by: height)
            case .pageBreak:
                layout.newPage()
            }
        }

        layout.endPage()
        context.closePDF()
    }

    // MARK: - Layout

    /// Walks down the page placing blocks, starting a new page when one runs out
    /// of room.
    private struct Layout {
        let context: CGContext

        /// Distance from the top of the content area to where the next block goes.
        private var cursor: CGFloat = 0
        private var pageNumber = 0
        private var isPageOpen = false

        init(context: CGContext) {
            self.context = context
        }

        private var remainingHeight: CGFloat {
            (PDFReport.contentTop - PDFReport.contentBottom) - cursor
        }

        mutating func beginPage() {
            guard !isPageOpen else { return }
            context.beginPDFPage(nil)
            pageNumber += 1
            cursor = 0
            isPageOpen = true
        }

        mutating func endPage() {
            guard isPageOpen else { return }
            PDFReport.drawFooter(pageNumber: pageNumber, in: context)
            context.endPDFPage()
            isPageOpen = false
        }

        mutating func newPage() {
            endPage()
            beginPage()
        }

        mutating func advance(by height: CGFloat) {
            if height > remainingHeight {
                newPage()
            } else {
                cursor += height
            }
        }

        /// Converts a distance from the content top into a PDF y coordinate.
        private func y(at offset: CGFloat) -> CGFloat {
            PDFReport.contentTop - offset
        }

        // MARK: Text

        mutating func draw(text: String, style: TextStyle) {
            let attributed = NSAttributedString(
                string: text,
                attributes: PDFReport.attributes(for: style)
            )
            let spacingBefore = PDFReport.spacingBefore(style)
            let spacingAfter = PDFReport.spacingAfter(style)

            if cursor > 0 { cursor += spacingBefore }

            let framesetter = CTFramesetterCreateWithAttributedString(attributed)
            var start = 0

            while start < attributed.length {
                if remainingHeight < 24 { newPage() }

                let available = CGSize(width: PDFReport.contentWidth, height: remainingHeight)
                let path = CGPath(
                    rect: CGRect(
                        x: PDFReport.margin,
                        y: y(at: cursor) - available.height,
                        width: available.width,
                        height: available.height
                    ),
                    transform: nil
                )
                let frame = CTFramesetterCreateFrame(
                    framesetter,
                    CFRange(location: start, length: 0),
                    path,
                    nil
                )
                CTFrameDraw(frame, context)

                let visible = CTFrameGetVisibleStringRange(frame)
                guard visible.length > 0 else {
                    // Nothing fits even on a fresh page: give up on this block
                    // rather than loop for ever.
                    if cursor == 0 { return }
                    newPage()
                    continue
                }

                let used = PDFReport.height(
                    of: framesetter,
                    range: CFRange(location: start, length: visible.length),
                    width: PDFReport.contentWidth
                )
                cursor += used
                start += visible.length
            }

            cursor += spacingAfter
        }

        // MARK: Rule

        mutating func drawRule() {
            if remainingHeight < 12 { newPage() }
            cursor += 6
            context.saveGState()
            context.setStrokeColor(NSColor.lightGray.cgColor)
            context.setLineWidth(0.5)
            context.move(to: CGPoint(x: PDFReport.margin, y: y(at: cursor)))
            context.addLine(to: CGPoint(x: PDFReport.pageSize.width - PDFReport.margin, y: y(at: cursor)))
            context.strokePath()
            context.restoreGState()
            cursor += 8
        }

        // MARK: Tables

        mutating func draw(table: ResultTable) {
            let columns = table.columns.isEmpty ? ["Value"] : table.columns
            let widths = PDFReport.columnWidths(for: table, columns: columns)

            if let heading = table.title.nilIfEmpty {
                draw(text: heading, style: .subheading)
            }

            var rowIndex = 0
            var needsHeader = true

            repeat {
                let headerHeight = PDFReport.rowHeight(
                    cells: columns, widths: widths, style: .tableHeader
                )

                // A header stranded at the bottom of a page helps nobody.
                if needsHeader, remainingHeight < headerHeight + 26 { newPage() }

                if needsHeader {
                    drawRow(cells: columns, widths: widths, style: .tableHeader, isAbnormal: false)
                    needsHeader = false
                }

                while rowIndex < table.rows.count {
                    let row = table.rows[rowIndex]
                    let cells = PDFReport.padded(row.cells, to: columns.count)
                    let height = PDFReport.rowHeight(cells: cells, widths: widths, style: .tableCell)

                    if height > remainingHeight {
                        newPage()
                        needsHeader = true
                        break
                    }

                    drawRow(cells: cells, widths: widths, style: .tableCell, isAbnormal: row.isAbnormal)
                    rowIndex += 1
                }
            } while rowIndex < table.rows.count

            if let note = table.note?.nilIfEmpty {
                cursor += 4
                draw(text: note, style: .caption)
            }

            cursor += 10
        }

        /// Two columns: a fixed label gutter, then the value, wrapping.
        mutating func draw(fields: [PDFReport.Field]) {
            guard !fields.isEmpty else { return }

            let labelWidth: CGFloat = 116
            let valueWidth = PDFReport.contentWidth - labelWidth

            for field in fields {
                let height = max(
                    PDFReport.rowHeight(cells: [field.label], widths: [labelWidth], style: .tableCell),
                    PDFReport.rowHeight(cells: [field.value], widths: [valueWidth], style: .tableCell)
                )

                if height > remainingHeight { newPage() }

                let top = y(at: cursor)

                PDFReport.drawCell(
                    field.label,
                    in: CGRect(x: PDFReport.margin, y: top - height, width: labelWidth - 8, height: height),
                    style: .fieldLabel,
                    context: context
                )
                PDFReport.drawCell(
                    field.value,
                    in: CGRect(
                        x: PDFReport.margin + labelWidth,
                        y: top - height,
                        width: valueWidth,
                        height: height
                    ),
                    style: .tableCell,
                    context: context
                )

                cursor += height
            }

            cursor += 6
        }

        private mutating func drawRow(
            cells: [String],
            widths: [CGFloat],
            style: PDFReport.CellStyle,
            isAbnormal: Bool
        ) {
            let height = PDFReport.rowHeight(cells: cells, widths: widths, style: style)
            let top = y(at: cursor)

            if style == .tableHeader || isAbnormal {
                context.saveGState()
                context.setFillColor(
                    style == .tableHeader
                        ? NSColor(white: 0.94, alpha: 1).cgColor
                        : NSColor(red: 1, green: 0.96, blue: 0.94, alpha: 1).cgColor
                )
                context.fill(CGRect(
                    x: PDFReport.margin,
                    y: top - height,
                    width: PDFReport.contentWidth,
                    height: height
                ))
                context.restoreGState()
            }

            var x = PDFReport.margin
            for (index, cell) in cells.enumerated() {
                let width = widths[index]
                PDFReport.drawCell(
                    cell,
                    in: CGRect(
                        x: x + PDFReport.cellPadding,
                        y: top - height,
                        width: width - PDFReport.cellPadding * 2,
                        height: height
                    ),
                    style: style,
                    context: context
                )
                x += width
            }

            context.saveGState()
            context.setStrokeColor(NSColor(white: 0.8, alpha: 1).cgColor)
            context.setLineWidth(0.5)
            context.move(to: CGPoint(x: PDFReport.margin, y: top - height))
            context.addLine(to: CGPoint(x: PDFReport.margin + PDFReport.contentWidth, y: top - height))
            context.strokePath()
            context.restoreGState()

            cursor += height
        }
    }

    // MARK: - Cells

    fileprivate enum CellStyle {
        case tableHeader
        case tableCell
        case fieldLabel
    }

    fileprivate static let cellPadding: CGFloat = 6

    /// Column widths proportional to the longest cell in each column, clamped so
    /// no column collapses and the widest cannot swallow the page.
    /// Up to this width, a column is treated as atomic and never wrapped.
    /// Wide enough for a date, a dose or a batch number; too narrow for prose.
    private static let narrowColumnWidth: CGFloat = 92

    fileprivate static func columnWidths(for table: ResultTable, columns: [String]) -> [CGFloat] {
        let count = columns.count
        guard count > 0 else { return [] }

        var natural = [CGFloat](repeating: 0, count: count)
        for (index, header) in columns.enumerated() {
            natural[index] = measuredWidth(header, style: .tableHeader)
        }
        for row in table.rows {
            let cells = padded(row.cells, to: count)
            for (index, cell) in cells.enumerated() {
                natural[index] = max(natural[index], measuredWidth(cell, style: .tableCell))
            }
        }

        // No column may end up narrower than its longest single word. Scaling
        // to fit the page would otherwise squeeze a column until "Screening"
        // breaks into "Screenin / g", which reads as a typo rather than as a
        // wrapped word.
        var floors = [CGFloat](repeating: 0, count: count)
        for (index, header) in columns.enumerated() {
            floors[index] = longestWordWidth(header, style: .tableHeader)
        }
        for row in table.rows {
            let cells = padded(row.cells, to: count)
            for (index, cell) in cells.enumerated() {
                floors[index] = max(floors[index], longestWordWidth(cell, style: .tableCell))
            }
        }
        // A column that needs very little should never be the one that wraps.
        // Taking twenty points from a column of dates turns "May 27, 2004" into
        // two lines and saves almost nothing; taking twenty from a column of
        // sentences costs the reader nothing at all. So a narrow column's floor
        // is its whole content, not merely its longest word.
        floors = floors.enumerated().map { index, wordFloor in
            let unwrapped = natural[index] + cellPadding * 2
            let floor = max(wordFloor + cellPadding * 2, min(unwrapped, narrowColumnWidth))
            return min(floor, contentWidth * 0.55)
        }

        let padded = natural.enumerated().map { index, width in
            min(max(width + cellPadding * 2, floors[index]), contentWidth * 0.55)
        }

        let total = padded.reduce(0, +)
        guard total > 0 else {
            return [CGFloat](repeating: contentWidth / CGFloat(count), count: count)
        }
        guard total > contentWidth else {
            // Everything fits: hand out the slack proportionally.
            return padded.map { $0 / total * contentWidth }
        }

        // Too wide. Shrink only what is above its floor, so wrapping happens in
        // the columns that have room to wrap and never inside a word.
        let floorTotal = floors.reduce(0, +)
        guard floorTotal < contentWidth else {
            return floors.map { $0 / floorTotal * contentWidth }
        }

        let slack = padded.enumerated().map { $0.element - floors[$0.offset] }
        let slackTotal = slack.reduce(0, +)
        let available = contentWidth - floorTotal

        return padded.indices.map { index in
            floors[index] + (slackTotal > 0 ? slack[index] / slackTotal * available : 0)
        }
    }

    /// The width of the longest unbreakable run in the text.
    private static func longestWordWidth(_ text: String, style: CellStyle) -> CGFloat {
        text
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .reduce(0) { max($0, measuredWidth(String($1), style: style)) }
    }

    private static func measuredWidth(_ text: String, style: CellStyle) -> CGFloat {
        let attributed = NSAttributedString(string: text, attributes: cellAttributes(style))
        return min(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attributed), nil, nil, nil), 260)
    }

    fileprivate static func padded(_ cells: [String], to count: Int) -> [String] {
        var result = cells
        while result.count < count { result.append("") }
        if result.count > count { result.removeLast(result.count - count) }
        return result
    }

    fileprivate static func rowHeight(cells: [String], widths: [CGFloat], style: CellStyle) -> CGFloat {
        var height: CGFloat = 0
        for (index, cell) in cells.enumerated() where widths.indices.contains(index) {
            let attributed = NSAttributedString(string: cell, attributes: cellAttributes(style))
            let framesetter = CTFramesetterCreateWithAttributedString(attributed)
            height = max(height, self.height(
                of: framesetter,
                range: CFRange(location: 0, length: attributed.length),
                width: widths[index] - cellPadding * 2
            ))
        }
        return max(height + 8, 20)
    }

    fileprivate static func drawCell(
        _ text: String,
        in rect: CGRect,
        style: CellStyle,
        context: CGContext
    ) {
        let attributed = NSAttributedString(string: text, attributes: cellAttributes(style))
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let used = height(
            of: framesetter,
            range: CFRange(location: 0, length: attributed.length),
            width: rect.width
        )
        // Sit the text at the top of the cell so a wrapped value stays level
        // with its neighbours' first line.
        let box = CGRect(x: rect.minX, y: rect.maxY - used - 4, width: rect.width, height: used)
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: attributed.length),
            CGPath(rect: box, transform: nil),
            nil
        )
        CTFrameDraw(frame, context)
    }

    private static func cellAttributes(_ style: CellStyle) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        switch style {
        case .tableHeader:
            return [
                .font: NSFont.systemFont(ofSize: 9.5, weight: .semibold),
                .paragraphStyle: paragraph,
                .foregroundColor: NSColor.black,
            ]
        case .tableCell:
            return [
                .font: NSFont.systemFont(ofSize: 9.5),
                .paragraphStyle: paragraph,
                .foregroundColor: NSColor.black,
            ]
        case .fieldLabel:
            // Grey, so the eye runs down the values and only crosses a label
            // when it needs to know what it is looking at.
            return [
                .font: NSFont.systemFont(ofSize: 9.5),
                .paragraphStyle: paragraph,
                .foregroundColor: NSColor(white: 0.42, alpha: 1),
            ]
        }
    }

    // MARK: - Measurement

    fileprivate static func height(of framesetter: CTFramesetter, range: CFRange, width: CGFloat) -> CGFloat {
        var fitting = CFRange()
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            range,
            nil,
            CGSize(width: width, height: .greatestFiniteMagnitude),
            &fitting
        )
        return ceil(size.height)
    }

    // MARK: - Text styling

    fileprivate static func attributes(for style: TextStyle) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping

        switch style {
        case .title:
            return [
                .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
                .paragraphStyle: paragraph,
                .foregroundColor: NSColor.black,
            ]
        case .heading:
            return [
                .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
                .paragraphStyle: paragraph,
                .foregroundColor: NSColor.black,
            ]
        case .subheading:
            return [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .paragraphStyle: paragraph,
                .foregroundColor: NSColor.black,
            ]
        case .body:
            paragraph.lineSpacing = 2
            return [
                .font: NSFont.systemFont(ofSize: 10.5),
                .paragraphStyle: paragraph,
                .foregroundColor: NSColor.black,
            ]
        case .caption:
            return [
                .font: NSFont.systemFont(ofSize: 9),
                .paragraphStyle: paragraph,
                .foregroundColor: NSColor.darkGray,
            ]
        }
    }

    fileprivate static func spacingBefore(_ style: TextStyle) -> CGFloat {
        switch style {
        case .title: 0
        case .heading: 18
        case .subheading: 12
        case .body: 2
        case .caption: 2
        }
    }

    fileprivate static func spacingAfter(_ style: TextStyle) -> CGFloat {
        switch style {
        case .title: 14
        case .heading: 8
        case .subheading: 4
        case .body: 3
        case .caption: 3
        }
    }

    private static func drawFooter(pageNumber: Int, in context: CGContext) {
        let text = NSAttributedString(
            string: "Medical  ·  page \(pageNumber)",
            attributes: [
                .font: NSFont.systemFont(ofSize: 8),
                .foregroundColor: NSColor.gray,
            ]
        )
        let line = CTLineCreateWithAttributedString(text)
        context.textPosition = CGPoint(x: margin, y: margin)
        CTLineDraw(line, context)
    }
}
