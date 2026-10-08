import Foundation

/// A note attached to a medical event.
///
/// Notes are where the parts of a medical history that no form has a field for
/// end up: what the doctor actually said, why a treatment was stopped, how it
/// felt. They belong to an event so they never float free of their context.
nonisolated struct Note: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var title: String?
    var body: String
    var createdAt: Date = .now
    var updatedAt: Date = .now

    init(
        id: UUID = UUID(),
        title: String? = nil,
        body: String,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Falls back to the first line of the body, the way Notes and Mail do.
    var displayTitle: String {
        if let title = title?.nilIfEmpty { return title }
        return firstLine.nilIfEmpty ?? "Untitled Note"
    }

    /// The part of the body that `displayTitle` has not already shown.
    ///
    /// Without this, an untitled one-line note renders its own text twice — once
    /// as the heading it was promoted into, and again as the preview underneath.
    var previewBelowTitle: String? {
        if title?.nilIfEmpty != nil {
            return flattened(body)
        }
        let remainder = body.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard remainder.count > 1 else { return nil }
        return flattened(String(remainder[1]))
    }

    var preview: String { flattened(body) ?? "" }

    // MARK: - Tolerant decoding

    private enum CodingKeys: String, CodingKey {
        case id, title, body, createdAt, updatedAt
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, or: UUID())
        title = c.value(.title)
        body = c.value(.body, or: "")
        createdAt = c.value(.createdAt, or: .now)
        updatedAt = c.value(.updatedAt, or: createdAt)
    }

    private var firstLine: String {
        body.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
    }

    private func flattened(_ text: String) -> String? {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }
}

/// A note paired with the event it belongs to, for the archive-wide Notes page.
nonisolated struct NoteRecord: Identifiable, Hashable, Sendable {
    var note: Note
    var event: MedicalEvent

    var id: UUID { note.id }
    var date: DateValue { event.date }
}

/// One record's use of a document, and the pages it uses.
nonisolated struct Citation: Identifiable, Hashable, Sendable {
    var eventID: UUID
    var eventTitle: String
    var pages: PageSelection
    var date: DateValue

    var id: UUID { eventID }

    /// `Vaccination (pages 20–21)`, or just the title when the whole document
    /// belongs to it.
    var description: String {
        pages.isWholeDocument ? eventTitle : "\(eventTitle) (\(pages.sentenceText))"
    }
}

/// A document together with every record that cites it.
///
/// A list rather than a single event: one scan can belong to an operation and
/// to the follow-up that discusses it, and the library page has to be able to
/// say so.
nonisolated struct DocumentRecord: Identifiable, Hashable, Sendable {
    var document: StoredDocument
    var events: [MedicalEvent]
    var status: DocumentStatus

    var id: UUID { document.id }

    var usageCount: Int { events.count }
    var isUsed: Bool { !events.isEmpty }

    /// The medical date this document belongs to: the earliest record citing
    /// it. A document with no record yet has no medical date at all.
    var date: DateValue? { events.map(\.date).min() }

    /// Documents still in the inbox sort by when they arrived, since that is
    /// the only date they have.
    var sortDate: Date { date?.date ?? document.importedAt }

    /// Which record uses which pages. On a ninety-page childhood card this is
    /// the only useful summary of what the document is doing in the archive.
    var citations: [Citation] {
        events.compactMap { event in
            event.attachments
                .first { $0.documentID == document.id }
                .map { Citation(eventID: event.id, eventTitle: event.title, pages: $0.pages, date: event.date) }
        }
    }

    /// `Used in 2 medical records`, or the plain status when there are none.
    var usageDescription: String {
        switch status {
        case .archived: DocumentStatus.archived.title
        case .notProcessed: DocumentStatus.notProcessed.title
        case .used: "Used in \(usageCount) medical \(usageCount == 1 ? "record" : "records")"
        }
    }
}
