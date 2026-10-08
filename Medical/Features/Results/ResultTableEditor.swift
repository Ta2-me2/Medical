import SwiftUI

/// Typing a table out of a scanned form.
///
/// The columns are the owner's to choose. Presets exist because most tables are
/// one of three shapes and nobody should have to build a lab report's header by
/// hand every time — but any of them can be renamed or thrown away.
struct ResultTableEditor: View {
    @Environment(\.dismiss) private var dismiss

    @State private var table: ResultTable
    private let onSave: (ResultTable) -> Void

    init(table: ResultTable, onSave: @escaping (ResultTable) -> Void) {
        _table = State(initialValue: table)
        self.onSave = onSave
    }

    /// Column sets that cover most of what a personal archive contains.
    private static let presets: [(name: String, columns: [String])] = [
        ("Laboratory", ["Test", "Result", "Reference"]),
        ("Measurements", ["Measure", "Value", "Unit"]),
        ("Findings", ["Finding", "Detail"]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 780, height: 640)
        .background(Palette.page)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Result Table").font(.headline)
            Spacer()
            Menu {
                ForEach(Array(Self.presets.enumerated()), id: \.offset) { _, preset in
                    Button(preset.name) { applyPreset(preset.columns) }
                }
            } label: {
                Label("Columns", systemImage: "tablecells")
            }
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Title").font(.caption).foregroundStyle(Palette.secondaryText)
                    TextField("", text: $table.title, prompt: Text("Complete blood count"))
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Columns") {
                        Button("Add Column") { table.addColumn() }
                            .buttonStyle(.link)
                            .font(.subheadline)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(table.columns.indices), id: \.self) { index in
                                HStack(spacing: 4) {
                                    TextField("", text: binding(forColumn: index), prompt: Text("Column"))
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 130)
                                    Button {
                                        table.removeColumn(at: index)
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(Palette.tertiaryText)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(table.columns.count <= 1)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Rows") {
                        Button("Add Row") { table.addRow() }
                            .buttonStyle(.link)
                            .font(.subheadline)
                    }

                    if table.rows.isEmpty {
                        Text("No rows yet.")
                            .foregroundStyle(Palette.tertiaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(table.rows.enumerated()), id: \.element.id) { rowIndex, row in
                                HStack(spacing: 8) {
                                    ForEach(Array(table.columns.indices), id: \.self) { columnIndex in
                                        TextField("", text: binding(row: rowIndex, column: columnIndex))
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 130)
                                    }

                                    // Marked by hand: reference ranges vary by
                                    // laboratory and by patient, so the app has
                                    // no business deciding this.
                                    Toggle(isOn: binding(abnormalFor: rowIndex)) {
                                        Image(systemName: "exclamationmark.triangle")
                                    }
                                    .toggleStyle(.button)
                                    .help("Outside the reference range")

                                    Button {
                                        table.removeRow(id: row.id)
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(Palette.tertiaryText)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Note").font(.caption).foregroundStyle(Palette.secondaryText)
                    TextField(
                        "",
                        text: Binding(get: { table.note ?? "" }, set: { table.note = $0.nilIfEmpty }),
                        prompt: Text("Units, laboratory, original language")
                    )
                    .textFieldStyle(.roundedBorder)
                }
            }
            .padding(20)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
            Button("Save") {
                table.squareUp()
                table.rows.removeAll(where: \.isBlank)
                onSave(table)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(table.columns.isEmpty)
        }
        .controlSize(.large)
        .padding(16)
    }

    // MARK: - Bindings

    private func binding(forColumn index: Int) -> Binding<String> {
        Binding(
            get: { table.columns.indices.contains(index) ? table.columns[index] : "" },
            set: { if table.columns.indices.contains(index) { table.columns[index] = $0 } }
        )
    }

    private func binding(row: Int, column: Int) -> Binding<String> {
        Binding(
            get: {
                guard table.rows.indices.contains(row),
                      table.rows[row].cells.indices.contains(column)
                else { return "" }
                return table.rows[row].cells[column]
            },
            set: { newValue in
                guard table.rows.indices.contains(row) else { return }
                while table.rows[row].cells.count <= column { table.rows[row].cells.append("") }
                table.rows[row].cells[column] = newValue
            }
        )
    }

    private func binding(abnormalFor row: Int) -> Binding<Bool> {
        Binding(
            get: { table.rows.indices.contains(row) ? table.rows[row].isAbnormal : false },
            set: { if table.rows.indices.contains(row) { table.rows[row].isAbnormal = $0 } }
        )
    }

    private func applyPreset(_ columns: [String]) {
        table.columns = columns
        table.squareUp()
    }
}
