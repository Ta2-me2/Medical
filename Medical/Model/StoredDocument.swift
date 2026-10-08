import Foundation

/// A reference to an original file inside the library.
///
/// The record describes the file; it never contains it. The bytes stay in
/// `Originals/`, read-only, exactly as they were imported. Nothing in this app
/// is able to rewrite them — there is no code path that opens an original for
/// writing.
///
/// Documents live in the archive's own library rather than inside an event,
/// because one scan can belong to several medical records — a discharge letter
/// that covers an operation and the follow-up that came after it. Owned by an
/// event, it would have to be copied; owned by the archive, it is referenced.
nonisolated struct StoredDocument: Identifiable, Hashable, Codable, Sendable {

    enum Kind: String, Codable, CaseIterable, Sendable, Identifiable {
        case pdf
        case image
        case scan
        case other

        var id: String { rawValue }

        var title: String {
            switch self {
            case .pdf: "PDF"
            case .image: "Image"
            case .scan: "Scan"
            case .other: "File"
            }
        }

        var symbol: String {
            switch self {
            case .pdf: "text.document"
            case .image: "photo"
            case .scan: "scanner"
            case .other: "doc"
            }
        }

        static func inferred(from url: URL) -> Kind {
            switch url.pathExtension.lowercased() {
            case "pdf": .pdf
            case "png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "gif", "bmp", "webp": .image
            default: .other
            }
        }
    }

    var id = UUID()

    /// What the file was called when it arrived. Preserved verbatim: it is
    /// often the only clue about where a document came from.
    var originalFilename: String

    /// Path relative to the library root, e.g. `Originals/2011/3f2a…-blood-test.pdf`.
    /// Relative so that moving or renaming the library folder never breaks it.
    var relativePath: String

    /// SHA-256 of the bytes at import time. The integrity check compares against
    /// this; a mismatch means the file was altered or corrupted on disk.
    var contentHash: String

    var byteSize: Int
    var kind: Kind = .other

    /// Counted once, at import. A number the owner can see without opening the
    /// file — the difference between a one-page result and a forty-page
    /// discharge summary decides whether it is worth reading now.
    var pageCount: Int?

    var importedAt: Date = .now

    /// A name given by the owner, when the filename from the scanner is useless.
    var title: String?

    /// Set aside by hand. See `DocumentStatus`.
    var isArchived: Bool = false

    init(
        id: UUID = UUID(),
        originalFilename: String,
        relativePath: String,
        contentHash: String,
        byteSize: Int,
        kind: Kind = .other,
        pageCount: Int? = nil,
        importedAt: Date = .now,
        title: String? = nil,
        isArchived: Bool = false
    ) {
        self.id = id
        self.originalFilename = originalFilename
        self.relativePath = relativePath
        self.contentHash = contentHash
        self.byteSize = byteSize
        self.kind = kind
        self.pageCount = pageCount
        self.importedAt = importedAt
        self.title = title
        self.isArchived = isArchived
    }

    // MARK: - Derived

    var displayName: String { title?.nilIfEmpty ?? originalFilename }

    var fileExtension: String { (originalFilename as NSString).pathExtension.uppercased() }

    var formattedSize: String {
        Int64(byteSize).formatted(.byteCount(style: .file))
    }

    /// `12 pages`, or nothing at all when the count is unknown. Never `0 pages`:
    /// an unknown count and an empty document are different facts.
    var formattedPageCount: String? {
        guard let pageCount, pageCount > 0 else { return nil }
        return "\(pageCount) \(pageCount == 1 ? "page" : "pages")"
    }

    // MARK: - Tolerant decoding

    private enum CodingKeys: String, CodingKey {
        case id, originalFilename, relativePath, contentHash, byteSize
        case kind, pageCount, importedAt, title, isArchived
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, or: UUID())
        originalFilename = c.value(.originalFilename, or: "Untitled")
        relativePath = c.value(.relativePath, or: "")
        contentHash = c.value(.contentHash, or: "")
        byteSize = c.value(.byteSize, or: 0)
        kind = c.value(.kind, or: .other)
        pageCount = c.value(.pageCount)
        importedAt = c.value(.importedAt, or: .now)
        title = c.value(.title)
        isArchived = c.value(.isArchived, or: false)
    }
}
