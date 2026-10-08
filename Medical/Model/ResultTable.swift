import Foundation

/// A table of results, typed out by the owner.
///
/// This is the part of the archive a doctor actually reads. A scan of a Russian
/// lab form is evidence, but it is not usable by a clinician in another country;
/// the table beside it is the same information in English, in a shape anyone can
/// read at a glance.
///
/// The columns are whatever the source document has — `Test / Result /
/// Reference` for bloodwork, but just as easily `Date / Vaccine / Batch`. The
/// app imposes no schema, because no schema survives twenty years of paperwork
/// from several countries.
nonisolated struct ResultTable: Identifiable, Hashable, Codable, Sendable {

    var id = UUID()

    /// What the table is. Shown as its heading, in the app and in the export.
    var title: String

    var columns: [String]
    var rows: [ResultRow]

    /// Anything the table itself cannot say — the units used, the laboratory,
    /// that the original was in another language.
    var note: String?

    init(
        id: UUID = UUID(),
        title: String = "",
        columns: [String] = ["Test", "Result", "Reference"],
        rows: [ResultRow] = [],
        note: String? = nil
    ) {
        self.id = id
        self.title = title
        self.columns = columns
        self.rows = rows
        self.note = note
    }

    // MARK: - Derived

    var displayTitle: String { title.nilIfEmpty ?? "Results" }

    var isEmpty: Bool { rows.isEmpty && columns.allSatisfy { $0.nilIfEmpty == nil } }

    var abnormalCount: Int { rows.filter(\.isAbnormal).count }

    /// The cell at a position, tolerating rows that are shorter than the header.
    /// A row typed before a column was added must not crash the table.
    func cell(row: Int, column: Int) -> String {
        guard rows.indices.contains(row), rows[row].cells.indices.contains(column) else { return "" }
        return rows[row].cells[column]
    }

    var searchableText: String {
        ([title, note ?? ""] + columns + rows.flatMap(\.cells)).joined(separator: " ")
    }

    /// The same table without the columns nothing filled in.
    ///
    /// A generated table has to offer every column the data *could* have; a
    /// printed one should show only the columns it *does*. Six columns of which
    /// four are dashes is the fastest way to make a page unreadable.
    ///
    /// The first column is always kept: it is what the rows are identified by,
    /// and a table with no key column is a list of loose values.
    func droppingEmptyColumns(placeholders: Set<String> = ["—", "-"]) -> ResultTable {
        guard columns.count > 1 else { return self }

        let kept = columns.indices.filter { index in
            guard index > 0 else { return true }
            return rows.contains { row in
                guard row.cells.indices.contains(index) else { return false }
                guard let value = row.cells[index].nilIfEmpty else { return false }
                return !placeholders.contains(value)
            }
        }

        guard kept.count < columns.count else { return self }

        var trimmed = self
        trimmed.columns = kept.map { columns[$0] }
        trimmed.rows = rows.map { row in
            var row = row
            row.cells = kept.map { index in
                row.cells.indices.contains(index) ? row.cells[index] : ""
            }
            return row
        }
        return trimmed
    }

    // MARK: - Editing

    mutating func addColumn(named name: String = "") {
        columns.append(name)
        for index in rows.indices {
            rows[index].cells.append("")
        }
    }

    mutating func removeColumn(at index: Int) {
        guard columns.indices.contains(index) else { return }
        columns.remove(at: index)
        for rowIndex in rows.indices where rows[rowIndex].cells.indices.contains(index) {
            rows[rowIndex].cells.remove(at: index)
        }
    }

    mutating func addRow() {
        rows.append(ResultRow(cells: Array(repeating: "", count: columns.count)))
    }

    mutating func removeRow(id: UUID) {
        rows.removeAll { $0.id == id }
    }

    /// Pads every row to the header width. Called before saving so the stored
    /// table is rectangular even if editing left it ragged.
    mutating func squareUp() {
        for index in rows.indices {
            while rows[index].cells.count < columns.count { rows[index].cells.append("") }
            if rows[index].cells.count > columns.count {
                rows[index].cells.removeLast(rows[index].cells.count - columns.count)
            }
        }
    }

    // MARK: - Tolerant decoding

    private enum CodingKeys: String, CodingKey { case id, title, columns, rows, note }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, or: UUID())
        title = c.value(.title, or: "")
        columns = c.value(.columns, or: [])
        rows = c.value(.rows, or: [])
        note = c.value(.note)
    }
}

/// One line of a result table.
nonisolated struct ResultRow: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var cells: [String]

    /// Marked by hand when a value sits outside its reference range.
    ///
    /// The app never decides this: reference ranges differ by laboratory, by
    /// age, by method, and a guess printed next to a blood result is worse than
    /// no mark at all.
    var isAbnormal: Bool = false

    init(id: UUID = UUID(), cells: [String] = [], isAbnormal: Bool = false) {
        self.id = id
        self.cells = cells
        self.isAbnormal = isAbnormal
    }

    var isBlank: Bool { cells.allSatisfy { $0.nilIfEmpty == nil } }

    private enum CodingKeys: String, CodingKey { case id, cells, isAbnormal }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, or: UUID())
        cells = c.value(.cells, or: [])
        isAbnormal = c.value(.isAbnormal, or: false)
    }
}
