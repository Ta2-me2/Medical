import Foundation

/// Which pages of a document a record actually refers to.
///
/// Old medical cards arrive as one ninety-page scan covering a childhood. The
/// answer is never to cut the PDF up: the original is evidence and must stay
/// exactly as it came. Instead a record points at the pages it is about, and the
/// same file can be pointed at from several records with different pages.
///
/// Stored as a plain string — `"15-17, 42-43, 58"` — because that is what a
/// person writes on a folder, and it stays readable in the archive file forever.
nonisolated struct PageSelection: Hashable, Codable, Sendable {

    /// Empty means the whole document. Absence of a restriction is not the same
    /// as a restriction covering everything: a document whose length is unknown
    /// still has "all of it" as an answer.
    var ranges: [PageRange]

    init(ranges: [PageRange] = []) {
        self.ranges = PageSelection.normalise(ranges)
    }

    static let wholeDocument = PageSelection()

    var isWholeDocument: Bool { ranges.isEmpty }

    /// How many pages the selection covers, or `nil` for the whole document.
    var pageCount: Int? {
        isWholeDocument ? nil : ranges.reduce(0) { $0 + $1.count }
    }

    func contains(page: Int) -> Bool {
        isWholeDocument || ranges.contains { $0.contains(page) }
    }

    /// Every page number the selection names, in order.
    var pageNumbers: [Int] {
        ranges.flatMap { Array($0.first...$0.last) }
    }

    // MARK: - Text

    /// `15–17, 42–43, 58`. Uses an en dash, because this is read, not parsed.
    var displayText: String {
        isWholeDocument ? "All pages" : ranges.map(\.displayText).joined(separator: ", ")
    }

    /// The same, as it reads inside a sentence: `page 1`, `pages 2–3`,
    /// `all pages`. One page is a page.
    var sentenceText: String {
        if isWholeDocument { return "all pages" }
        let singlePage = ranges.count == 1 && ranges[0].count == 1
        return "\(singlePage ? "page" : "pages") \(displayText)"
    }

    /// `15-17, 42-43, 58`. Uses a hyphen: this is what goes in the file and what
    /// the parser accepts back.
    var storedText: String {
        ranges.map(\.storedText).joined(separator: ", ")
    }

    /// Reads anything a person is likely to type: `15-17`, `15–17`, `15 - 17`,
    /// `58`, or any of them separated by commas, semicolons or spaces.
    /// Returns `nil` only when the text contains something that is not a page.
    static func parse(_ text: String) -> PageSelection? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .wholeDocument }

        let separators = CharacterSet(charactersIn: ",;\n")
        var parsed: [PageRange] = []

        for piece in trimmed.components(separatedBy: separators) {
            let part = piece.trimmingCharacters(in: .whitespaces)
            guard !part.isEmpty else { continue }

            let bounds = part
                .replacingOccurrences(of: "–", with: "-")
                .replacingOccurrences(of: "—", with: "-")
                .components(separatedBy: "-")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            switch bounds.count {
            case 1:
                guard let page = Int(bounds[0]), page > 0 else { return nil }
                parsed.append(PageRange(first: page, last: page))
            case 2:
                guard let first = Int(bounds[0]), let last = Int(bounds[1]),
                      first > 0, last > 0
                else { return nil }
                parsed.append(PageRange(first: min(first, last), last: max(first, last)))
            default:
                return nil
            }
        }

        return PageSelection(ranges: parsed)
    }

    /// Sorted and merged, so `3, 1-2, 2` becomes `1-3` and the archive never
    /// records the same page twice.
    private static func normalise(_ ranges: [PageRange]) -> [PageRange] {
        let sorted = ranges.sorted { $0.first < $1.first }
        var merged: [PageRange] = []
        for range in sorted {
            if let last = merged.last, range.first <= last.last + 1 {
                merged[merged.count - 1] = PageRange(
                    first: last.first,
                    last: max(last.last, range.last)
                )
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    // MARK: - Coding

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = (try? container.decode(String.self)) ?? ""
        self = PageSelection.parse(text) ?? .wholeDocument
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(storedText)
    }
}

/// An inclusive run of page numbers, one-based, as printed on the page.
nonisolated struct PageRange: Hashable, Codable, Sendable {
    var first: Int
    var last: Int

    var count: Int { last - first + 1 }

    func contains(_ page: Int) -> Bool { page >= first && page <= last }

    var displayText: String { first == last ? "\(first)" : "\(first)–\(last)" }
    var storedText: String { first == last ? "\(first)" : "\(first)-\(last)" }
}

/// A record's citation of a document: which file, and which pages of it.
nonisolated struct DocumentReference: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var documentID: UUID
    var pages: PageSelection = .wholeDocument

    init(id: UUID = UUID(), documentID: UUID, pages: PageSelection = .wholeDocument) {
        self.id = id
        self.documentID = documentID
        self.pages = pages
    }

    private enum CodingKeys: String, CodingKey { case id, documentID, pages }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, or: UUID())
        documentID = try c.decode(UUID.self, forKey: .documentID)
        pages = c.value(.pages, or: .wholeDocument)
    }
}

/// A reference resolved against the library, for display.
nonisolated struct AttachedDocument: Identifiable, Hashable, Sendable {
    var reference: DocumentReference
    var document: StoredDocument

    var id: UUID { reference.id }

    /// `90 pages` for a whole document, `pages 15–17` for a citation of part.
    var pageDescription: String? {
        reference.pages.isWholeDocument ? document.formattedPageCount : reference.pages.sentenceText
    }
}
