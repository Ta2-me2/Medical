import SwiftUI

/// Choosing a document that is already in the library.
///
/// The inbox is only the documents nobody has filed yet, so picking from it
/// alone makes a document unreachable the moment it is used once. That is the
/// opposite of what the library is for: a ninety-page card is meant to be cited
/// again and again, at different pages, by as many records as need it.
struct DocumentPickerSheet: View {
    @Environment(ArchiveStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Documents the record already cites, shown as such so nothing is added twice.
    let alreadyAttached: Set<UUID>
    var onPick: (StoredDocument) -> Void

    @State private var searchText = ""
    @State private var scope: Scope = .all

    private enum Scope: String, CaseIterable, Identifiable {
        case all
        case inbox
        case used
        case archived

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: "All"
            case .inbox: "Inbox"
            case .used: "In Records"
            case .archived: "Archived"
            }
        }

        var status: DocumentStatus? {
            switch self {
            case .all: nil
            case .inbox: .notProcessed
            case .used: .used
            case .archived: .archived
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if store.archive.documents.isEmpty {
                ContentUnavailableView(
                    "No Documents Yet",
                    systemImage: "text.document",
                    description: Text("Import a file first and it will be available here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if records.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list
            }

            Divider()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .padding(16)
        }
        .frame(width: 640, height: 560)
        .background(Palette.page)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose a Document").font(.headline)

            HStack(spacing: 10) {
                SearchField(text: $searchText, prompt: "Filter documents", width: 240)

                Spacer(minLength: 8)

                Picker("Scope", selection: $scope) {
                    ForEach(Scope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: Metrics.rowSpacing) {
                ForEach(records) { record in
                    let isAttached = alreadyAttached.contains(record.document.id)

                    Button {
                        onPick(record.document)
                        dismiss()
                    } label: {
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
                                }
                                .font(.caption)
                                .foregroundStyle(Palette.tertiaryText)

                                // Which records already draw on it, and from
                                // which pages — the context for choosing your
                                // own page range.
                                if !record.citations.isEmpty {
                                    Text(record.citations.map(\.description).joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundStyle(Palette.secondaryText)
                                        .lineLimit(2)
                                }
                            }

                            Spacer(minLength: 12)

                            if isAttached {
                                Chip(text: "Attached", tint: Palette.complete)
                            }
                        }
                        .cardSurface()
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(isAttached)
                    .opacity(isAttached ? 0.5 : 1)
                }
            }
            .padding(20)
        }
    }

    private var records: [DocumentRecord] {
        var result = store.archive.allDocuments

        if let status = scope.status {
            result = result.filter { $0.status == status }
        }
        if let query = searchText.nilIfEmpty?.lowercased() {
            result = result.filter {
                $0.document.displayName.lowercased().contains(query)
                    || $0.document.originalFilename.lowercased().contains(query)
            }
        }
        return result
    }
}
