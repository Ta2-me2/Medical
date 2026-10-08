import SwiftUI

/// A document, opened.
///
/// The page itself on the left, everything the archive knows about it on the
/// right. Two panes rather than a preview alone, because the questions asked of
/// a document — when is it from, which records use it, is this the original —
/// are not answered by looking at the page.
struct DocumentDetailSheet: View {
    @Environment(ArchiveStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    let documentID: UUID

    @State private var isRenaming = false
    @State private var removal: DocumentRemoval?

    var body: some View {
        Group {
            if let document = store.archive.document(id: documentID) {
                content(store.archive.record(for: document))
            } else {
                ContentUnavailableView(
                    "Document Not Found",
                    systemImage: "questionmark.folder"
                )
                .frame(width: 900, height: 640)
            }
        }
    }

    private func content(_ record: DocumentRecord) -> some View {
        VStack(spacing: 0) {
            header(record)
            Divider()

            HStack(spacing: 0) {
                QuickLookPreview(url: store.fileURL(for: record.document))
                    .frame(minWidth: 520)

                Divider()

                metadata(record)
                    .frame(width: 300)
            }
        }
        .frame(width: 960, height: 680)
        .sheet(isPresented: $isRenaming) {
            DocumentRenameSheet(document: record.document) { newTitle in
                store.update { $0.setTitle(newTitle, forDocument: record.document.id) }
            }
        }
        .documentRemoval($removal, store: store)
    }

    // MARK: - Header

    private func header(_ record: DocumentRecord) -> some View {
        HStack(spacing: 10) {
            Image(systemName: record.document.kind.symbol)
                .font(.title3)
                .foregroundStyle(Palette.secondaryText)

            VStack(alignment: .leading, spacing: 1) {
                Text(record.document.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text(record.usageDescription)
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
            }

            Spacer(minLength: 12)

            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    // MARK: - Metadata

    private func metadata(_ record: DocumentRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                section("Document") {
                    GroupedRows {
                        GroupedRow { field("Format", record.document.fileExtension) }
                        GroupedRow { field("Pages", record.document.formattedPageCount ?? "Unknown") }
                        GroupedRow { field("Size", record.document.formattedSize) }
                        GroupedRow(showsDivider: false) {
                            field("Imported", record.document.importedAt.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                }

                section("Used In") {
                    GroupedRows {
                        if record.events.isEmpty {
                            GroupedRow(showsDivider: false) {
                                HStack {
                                    Text(record.status == .archived ? "Archived" : "Not used in any record")
                                        .foregroundStyle(Palette.tertiaryText)
                                    Spacer(minLength: 8)
                                    if record.status != .archived {
                                        Button("Create…") {
                                            dismiss()
                                            router.newRecord(from: record.document.id)
                                        }
                                        .buttonStyle(.link)
                                        .font(.subheadline)
                                    }
                                }
                            }
                        }

                        let citations = record.citations
                        ForEach(Array(citations.enumerated()), id: \.element.id) { index, citation in
                            GroupedRow(showsDivider: index < citations.count - 1) {
                                Button {
                                    dismiss()
                                    router.open(event: citation.eventID)
                                } label: {
                                    HStack(spacing: 8) {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(citation.eventTitle)
                                                .lineLimit(1)
                                            // The pages, not the category: on a
                                            // long card this is what tells the
                                            // reader which part is which.
                                            Text(citation.pages.isWholeDocument
                                                 ? "All pages · \(citation.date.medium)"
                                                 : "Pages \(citation.pages.displayText) · \(citation.date.medium)")
                                                .font(.caption)
                                                .foregroundStyle(Palette.tertiaryText)
                                        }
                                        Spacer(minLength: 6)
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(Palette.tertiaryText)
                                    }
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                section("Original") {
                    GroupedRows {
                        GroupedRow { field("Filename", record.document.originalFilename) }
                        GroupedRow(showsDivider: false) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("SHA-256")
                                    .foregroundStyle(Palette.secondaryText)
                                Text(record.document.contentHash)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(Palette.tertiaryText)
                                    .textSelection(.enabled)
                                    .lineLimit(3)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    Text("The file on disk is read-only and is never modified by this application.")
                        .font(.caption)
                        .foregroundStyle(Palette.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: Metrics.rowSpacing) {
                    Button("Create Another Record from This…") {
                        dismiss()
                        router.newRecord(from: record.document.id)
                    }
                    .frame(maxWidth: .infinity)

                    Button("Rename…") { isRenaming = true }
                        .frame(maxWidth: .infinity)

                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([store.fileURL(for: record.document)])
                    }
                    .frame(maxWidth: .infinity)

                    if record.document.isArchived {
                        Button("Move Back to Inbox") {
                            store.update { $0.setArchived(false, forDocument: record.document.id) }
                        }
                        .frame(maxWidth: .infinity)
                    } else if record.events.isEmpty {
                        Button("Archive") {
                            store.update { $0.setArchived(true, forDocument: record.document.id) }
                        }
                        .frame(maxWidth: .infinity)
                    }

                    Button("Remove from Library…", role: .destructive) {
                        removal = DocumentRemoval(documents: [record.document])
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(Metrics.gutter)
        }
        .background(Palette.page)
    }

    private func field(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .foregroundStyle(Palette.secondaryText)
            Spacer(minLength: 8)
            Text(value)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            SectionHeader(title)
            content()
        }
    }
}
