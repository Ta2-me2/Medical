import SwiftUI

/// A pending request to take documents out of the archive.
///
/// Removal is the one operation in this app that can lose something, so it is
/// never a single click. The dialog says how many files, warns when a medical
/// record still cites one, and makes the owner choose what happens to the bytes.
nonisolated struct DocumentRemoval: Identifiable, Hashable, Sendable {
    var id = UUID()
    var documents: [StoredDocument]

    var count: Int { documents.count }

    var title: String {
        count == 1
            ? "Remove “\(documents[0].displayName)”?"
            : "Remove \(count) documents?"
    }
}

extension View {
    /// Attaches the removal dialog, and performs whichever choice is made.
    func documentRemoval(_ request: Binding<DocumentRemoval?>, store: ArchiveStore) -> some View {
        modifier(DocumentRemovalModifier(request: request, store: store))
    }
}

private struct DocumentRemovalModifier: ViewModifier {
    @Binding var request: DocumentRemoval?
    let store: ArchiveStore

    @State private var failure: String?

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                request?.title ?? "",
                isPresented: Binding(
                    get: { request != nil },
                    set: { if !$0 { request = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Move Files to Trash", role: .destructive) { remove(toTrash: true) }
                Button("Keep Files, Remove from Archive") { remove(toTrash: false) }
                Button("Cancel", role: .cancel) { request = nil }
            } message: {
                Text(message)
            }
            .alert(
                "Could Not Remove",
                isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
            ) {
                Button("OK") { failure = nil }
            } message: {
                Text(failure ?? "")
            }
    }

    private var message: String {
        guard let request else { return "" }

        let cited = request.documents.filter { !store.archive.events(using: $0.id).isEmpty }
        var lines: [String] = []

        if !cited.isEmpty {
            let records = Set(cited.flatMap { store.archive.events(using: $0.id).map(\.id) }).count
            lines.append(
                cited.count == 1
                    ? "One of these is used by \(records) medical \(records == 1 ? "record" : "records"), which will lose the attachment."
                    : "\(cited.count) of these are used by medical records, which will lose the attachments."
            )
        }

        lines.append(
            "Moving to Trash keeps the files recoverable in Finder. Otherwise they are kept in the library's Removed folder — nothing is deleted outright."
        )

        return lines.joined(separator: "\n\n")
    }

    private func remove(toTrash: Bool) {
        guard let documents = request?.documents else { return }
        request = nil

        Task {
            var problems: [String] = []
            for document in documents {
                if let problem = await store.remove(document, toTrash: toTrash) {
                    problems.append("\(document.displayName): \(problem)")
                }
            }
            if !problems.isEmpty {
                failure = problems.prefix(3).joined(separator: "\n")
            }
        }
    }
}
