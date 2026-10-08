import SwiftUI
import UniformTypeIdentifiers

/// Where imported files wait to become part of the record.
///
/// Import stops at the door. Nothing becomes a medical record until someone says
/// what it is — which is the only way a batch of a hundred and fifty scans can be
/// dealt with at all: bring them all in now, file them over the following weeks,
/// and the inbox is the count of what is left.
///
/// Importing happens here rather than on a screen of its own, because putting a
/// file in the inbox and looking at the inbox are the same task.
struct InboxView: View {
    @Environment(ArchiveStore.self) private var store
    @Environment(Router.self) private var router

    @State private var model = InboxViewModel()
    @State private var importer = DocumentImporter()
    @State private var isChoosingFiles = false
    @State private var opened: StoredDocument?
    @State private var renaming: StoredDocument?
    @State private var removal: DocumentRemoval?

    var body: some View {
        let records = model.records(from: store.archive)

        VStack(spacing: 0) {
            scopeBar

            if importer.isImporting || importer.importedCount != nil {
                ImportBanner(importer: importer) { router.show(.inbox) }
            }

            if store.archive.documents.isEmpty {
                empty
            } else if records.isEmpty {
                nothingInScope
            } else {
                list(records)
            }
        }
        .background(Palette.page)
        .navigationTitle("Inbox")
        .toolbar { toolbar }
        .dropDestination(for: URL.self) { urls, _ in
            importFiles(urls)
            return true
        }
        .fileImporter(
            isPresented: $isChoosingFiles,
            allowedContentTypes: [.pdf, .image, .tiff, .heic],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { importFiles(urls) }
        }
        .sheet(item: $opened) { document in
            DocumentDetailSheet(documentID: document.id)
        }
        .sheet(item: $renaming) { document in
            DocumentRenameSheet(document: document) { newTitle in
                store.update { $0.setTitle(newTitle, forDocument: document.id) }
            }
        }
        .documentRemoval($removal, store: store)
        .onChange(of: router.pendingImport) { _, isPending in
            if isPending {
                router.pendingImport = false
                isChoosingFiles = true
            }
        }
        .onAppear {
            if router.pendingImport {
                router.pendingImport = false
                isChoosingFiles = true
            }
        }
    }

    // MARK: - Chrome

    private var scopeBar: some View {
        FilterBar(searchText: $model.searchText, prompt: "Filter documents") {
            Picker("Scope", selection: $model.scope) {
                ForEach(InboxViewModel.Scope.allCases) { scope in
                    Text("\(scope.title) \(model.count(of: scope, in: store.archive))")
                        .tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if !model.selection.isEmpty {
            ToolbarItem(id: "inbox.remove") {
                Button(role: .destructive) {
                    removal = removalRequest(for: model.selection)
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        }

        ToolbarItem(id: "inbox.import") {
            Button {
                isChoosingFiles = true
            } label: {
                Label("Import", systemImage: "arrow.down.document")
            }
        }
    }

    // MARK: - List

    private func list(_ records: [DocumentRecord]) -> some View {
        List(records, selection: $model.selection) { record in
            InboxRow(record: record) {
                router.newRecord(from: record.document.id)
            } onOpenRecord: { eventID in
                router.open(event: eventID)
            } onUnarchive: {
                store.update { $0.setArchived(false, forDocument: record.document.id) }
            }
            .tag(record.id)
        }
        .listStyle(.inset)
        .contextMenu(forSelectionType: UUID.self) { ids in
            menu(for: ids.isEmpty ? [] : ids, in: records)
        } primaryAction: { ids in
            if let record = records.first(where: { ids.contains($0.id) }) {
                opened = record.document
            }
        }
    }

    @ViewBuilder
    private func menu(for ids: Set<UUID>, in records: [DocumentRecord]) -> some View {
        let chosen = records.filter { ids.contains($0.id) }

        if chosen.count == 1, let record = chosen.first {
            Button("Open") { opened = record.document }
            Button("Rename…") { renaming = record.document }
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
        }

        if !chosen.isEmpty {
            Divider()

            if chosen.allSatisfy(\.document.isArchived) {
                Button("Move to Inbox") { setArchived(false, for: chosen) }
            } else if chosen.allSatisfy({ !$0.document.isArchived }) {
                Button("Archive") { setArchived(true, for: chosen) }
            }

            Divider()

            Button("Remove from Library…", role: .destructive) {
                removal = removalRequest(for: ids)
            }
        }
    }

    // MARK: - Actions

    private func importFiles(_ urls: [URL]) {
        Task { await importer.importFiles(urls, into: store) }
    }

    private func setArchived(_ isArchived: Bool, for records: [DocumentRecord]) {
        store.update { archive in
            for record in records {
                archive.setArchived(isArchived, forDocument: record.document.id)
            }
        }
    }

    private func removalRequest(for ids: Set<UUID>) -> DocumentRemoval {
        DocumentRemoval(documents: store.archive.documents.filter { ids.contains($0.id) })
    }

    // MARK: - Empty states

    private var empty: some View {
        VStack(spacing: 20) {
            ArchiveEmptyState(
                title: "Inbox Is Empty",
                message: "Bring files in and they wait here. Nothing becomes part of your medical history until you say what it is.",
                symbol: "tray"
            )

            DropZone {
                isChoosingFiles = true
            } onDrop: { urls in
                importFiles(urls)
            }
            .frame(maxWidth: 420)
            .padding(.bottom, 60)
        }
    }

    private var nothingInScope: some View {
        ArchiveEmptyState(
            title: model.scope == .notProcessed ? "Nothing Left to File" : "Nothing Here",
            message: model.scope == .notProcessed
                ? "Every document in your library belongs to a medical record."
                : "No documents match this filter.",
            symbol: model.scope == .notProcessed ? "checkmark.circle" : "tray"
        )
    }
}

/// One row of the inbox: what the document is, and the one thing to do with it.
struct InboxRow: View {
    let record: DocumentRecord
    var onCreateRecord: () -> Void
    var onOpenRecord: (UUID) -> Void
    var onUnarchive: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            InboxRowContent(record: record, showsStatus: true)

            switch record.status {
            case .notProcessed:
                Button("Create Record…", action: onCreateRecord)
            case .used:
                if let event = record.events.first {
                    Button("Open Record") { onOpenRecord(event.id) }
                }
            case .archived:
                Button("Move to Inbox", action: onUnarchive)
            }
        }
        .padding(.vertical, 6)
    }
}

/// Progress and result of an import, shown where the files are landing.
struct ImportBanner: View {
    let importer: DocumentImporter
    var onOpenInbox: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if importer.isImporting {
                ProgressView(value: importer.progress)
                    .progressViewStyle(.linear)
                    .frame(width: 160)
                Text("Importing…")
                    .foregroundStyle(Palette.secondaryText)
            } else if let count = importer.importedCount {
                Image(systemName: count > 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(count > 0 ? Palette.complete : Palette.warning)
                Text(count == 1 ? "1 document added" : "\(count) documents added")
            }

            if let failure = importer.failure {
                Text(failure)
                    .font(.caption)
                    .foregroundStyle(Palette.critical)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if !importer.isImporting {
                Button("Dismiss") { importer.dismissResult() }
                    .buttonStyle(.link)
            }
        }
        .font(.callout)
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 10)
        .background(Palette.card)
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// One document as the inbox shows it: what it is called, how big it is, how
/// many pages, when it arrived, and where it stands.
struct InboxRowContent: View {
    let record: DocumentRecord
    var showsStatus: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.document.kind.symbol)
                .font(.title3)
                .foregroundStyle(Palette.secondaryText)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
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
                    Text("·")
                    Text("imported \(record.document.importedAt.formatted(.relative(presentation: .named)))")
                }
                .font(.caption)
                .foregroundStyle(Palette.tertiaryText)
            }

            Spacer(minLength: 12)

            if showsStatus {
                DocumentStatusLabel(record: record)
            }
        }
        .contentShape(.rect)
    }
}

/// The status chip. Colour only where it means something: an unprocessed
/// document is a loose end, a used one is settled, an archived one is neither.
struct DocumentStatusLabel: View {
    let record: DocumentRecord

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: record.status.symbol)
                .imageScale(.small)
            Text(record.usageDescription)
        }
        .font(.caption)
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(0.1), in: .capsule)
    }

    private var tint: Color {
        switch record.status {
        case .notProcessed: Palette.warning
        case .used: Palette.complete
        case .archived: Palette.secondaryText
        }
    }
}

/// Renaming a document changes only how the archive refers to it. The file on
/// disk keeps the name it arrived with, because that name is evidence.
struct DocumentRenameSheet: View {
    @Environment(\.dismiss) private var dismiss

    let document: StoredDocument
    var onSave: (String?) -> Void

    @State private var text: String

    init(document: StoredDocument, onSave: @escaping (String?) -> Void) {
        self.document = document
        self.onSave = onSave
        _text = State(initialValue: document.title ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rename Document").font(.headline)

            TextField("Name", text: $text, prompt: Text(document.originalFilename))
                .textFieldStyle(.roundedBorder)

            Text("The original file keeps its own name: \(document.originalFilename)")
                .font(.caption)
                .foregroundStyle(Palette.secondaryText)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") {
                    onSave(text.nilIfEmpty)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
