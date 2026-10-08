import SwiftUI

/// The document library.
///
/// Not a file listing: every row answers the questions a document raises on its
/// own — what it is, how long it is, when it is from, and whether the medical
/// history actually uses it. A document nothing points at is a loose end, and
/// this page is where that shows.
struct DocumentsView: View {
    @Environment(ArchiveStore.self) private var store
    @Environment(Router.self) private var router

    @State private var model = DocumentsViewModel()
    @State private var opened: StoredDocument?
    @State private var removal: DocumentRemoval?

    var body: some View {
        let records = model.records(from: store.archive)

        VStack(spacing: 0) {
            if !store.archive.documents.isEmpty {
                FilterBar(searchText: $model.searchText, prompt: "Filter documents") {
                    Text("\(records.count) of \(store.archive.documentCount)")
                        .font(.caption)
                        .foregroundStyle(Palette.tertiaryText)
                        .monospacedDigit()
                }
            }

            if store.archive.documents.isEmpty {
                emptyArchive
            } else if records.isEmpty {
                noMatches
            } else {
                switch model.layout {
                case .list: list(records)
                case .grid: grid(records)
                }
            }
        }
        .background(Palette.page)
        .navigationTitle("Documents")
        .toolbar { toolbar }
        .sheet(item: $opened) { document in
            DocumentDetailSheet(documentID: document.id)
        }
        .documentRemoval($removal, store: store)
    }

    // MARK: - List

    private func list(_ records: [DocumentRecord]) -> some View {
        ScrollView {
            LazyVStack(spacing: Metrics.rowSpacing) {
                ForEach(records) { record in
                    Button {
                        opened = record.document
                    } label: {
                        DocumentLibraryRow(record: record)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { menuItems(for: record) }
                }
            }
            .frame(maxWidth: Metrics.readableWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .pageInsets()
        }
    }

    private func grid(_ records: [DocumentRecord]) -> some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 166), spacing: 16)],
                alignment: .leading,
                spacing: 16
            ) {
                ForEach(records) { record in
                    DocumentTile(
                        record: record,
                        url: store.fileURL(for: record.document),
                        isSelected: model.selection == record.id
                    )
                    .onTapGesture { model.selection = record.id }
                    .onTapGesture(count: 2) { opened = record.document }
                    .contextMenu { menuItems(for: record) }
                }
            }
            .padding(Metrics.gutter)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(id: "documents.layout") {
            Picker("View", selection: $model.layout) {
                ForEach(DocumentsViewModel.Layout.allCases) { layout in
                    Image(systemName: layout.symbol).tag(layout)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }

        ToolbarItem(id: "documents.sort") {
            Menu {
                Picker("Sort By", selection: $model.sortOrder) {
                    ForEach(DocumentsViewModel.SortOrder.allCases) { order in
                        Text(order.title).tag(order)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .menuIndicator(.hidden)
        }

        ToolbarItem(id: "documents.filter") {
            Menu {
                FilterSection(
                    title: "Statuses",
                    options: DocumentStatus.allCases,
                    label: \.title,
                    symbol: \.symbol,
                    filter: $model.statuses
                )

                FilterSection(
                    title: "Categories",
                    options: EventCategory.allCases,
                    label: \.title,
                    symbol: \.symbol,
                    filter: $model.categories
                )

                FilterSection(
                    title: "Kinds",
                    options: StoredDocument.Kind.allCases,
                    label: \.title,
                    symbol: \.symbol,
                    filter: $model.kinds
                )

                Divider()
                Button("Show Everything") { model.clearFilters() }
                    .disabled(!model.isFiltered)
            } label: {
                FilterMenuLabel(isFiltering: model.isFiltered)
            }
            .menuIndicator(.hidden)
        }
    }

    @ViewBuilder
    private func menuItems(for record: DocumentRecord) -> some View {
        Button("Open") { opened = record.document }
        Button("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([store.fileURL(for: record.document)])
        }

        Divider()

        Button(record.events.isEmpty ? "Create Medical Record…" : "Create Another Record…") {
            router.newRecord(from: record.document.id)
        }
        ForEach(record.events) { event in
            Button("Open “\(event.title)”") { router.open(event: event.id) }
        }

        Divider()

        if record.document.isArchived {
            Button("Move to Inbox") {
                store.update { $0.setArchived(false, forDocument: record.document.id) }
            }
        } else if record.events.isEmpty {
            Button("Archive") {
                store.update { $0.setArchived(true, forDocument: record.document.id) }
            }
        }

        Button("Remove from Library…", role: .destructive) {
            removal = DocumentRemoval(documents: [record.document])
        }
    }

    // MARK: - Empty states

    private var emptyArchive: some View {
        ArchiveEmptyState(
            title: "No Documents",
            message: "Imported files are kept here, unchanged, exactly as they arrived.",
            symbol: "text.document",
            actionTitle: "Import Documents",
            action: { router.startImport() }
        )
    }

    private var noMatches: some View {
        ContentUnavailableView.search(text: model.searchText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A document as the library shows it: name, then the four facts that decide
/// whether it is the one you are looking for.
struct DocumentLibraryRow: View {
    let record: DocumentRecord

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: record.document.kind.symbol)
                .font(.title2)
                .foregroundStyle(Palette.secondaryText)
                .frame(width: 26)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                Text(record.document.displayName)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(record.document.fileExtension)
                    if let pages = record.document.formattedPageCount {
                        Text("·")
                        Text(pages)
                    }
                    Text("·")
                    Text(record.document.formattedSize)
                    if let date = record.date {
                        Text("·")
                        Text(date.medium).monospacedDigit()
                    }
                }
                .font(.caption)
                .foregroundStyle(Palette.tertiaryText)

                DocumentUsageLine(record: record)
                    .padding(.top, 2)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.tertiaryText)
                .opacity(isHovering ? 1 : 0)
                .padding(.top, 4)
        }
        .cardSurface()
        .background {
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .fill(Palette.selection.opacity(isHovering ? 0.04 : 0))
        }
        .contentShape(.rect(cornerRadius: Metrics.cardRadius, style: .continuous))
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }
}

/// `Used in: 2 Medical Records`, with the records named when there is room.
struct DocumentUsageLine: View {
    let record: DocumentRecord

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: record.status.symbol)
                .imageScale(.small)
                .foregroundStyle(tint)

            Text(record.usageDescription)
                .font(.caption)
                .foregroundStyle(tint)

            if !record.citations.isEmpty {
                Text("·").foregroundStyle(Palette.tertiaryText)
                Text(record.citations.map(\.description).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
            }
        }
    }

    private var tint: Color {
        switch record.status {
        case .notProcessed: Palette.warning
        case .used: Palette.complete
        case .archived: Palette.secondaryText
        }
    }
}
