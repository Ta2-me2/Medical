import Foundation

/// The seam between the app and its storage.
///
/// Nothing above this protocol knows whether the archive lives in a JSON file,
/// a database, or something that does not exist yet. Adding a second backend
/// means writing one more conformance — no screen and no view model changes.
nonisolated protocol ArchivePersistence: Sendable {

    /// Creates the library if it is not there yet, then reads it.
    func load() async throws -> Archive

    /// Writes atomically, keeping the previous version as a snapshot.
    func save(_ archive: Archive) async throws

    /// Copies a file into the library and returns the record describing it.
    /// The source is never moved or altered.
    func storeOriginal(from source: URL, year: Int, title: String?) async throws -> StoredDocument

    /// Absolute location of a stored original.
    func url(forRelativePath path: String) -> URL

    /// Re-hashes every original and reports the ones that no longer match.
    func verifyIntegrity(of archive: Archive) async -> [IntegrityIssue]

    /// Takes an original out of `Originals/`.
    ///
    /// `toTrash` puts it in the user's Trash, where the Finder can still bring
    /// it back; otherwise it moves to the library's `Removed/` folder, which
    /// nothing reads and the owner can empty by hand. Neither one deletes.
    func discardOriginal(_ document: StoredDocument, toTrash: Bool) async throws

    /// Writes the patient's avatar into the library and returns its filename.
    /// Replaces whatever was there: there is only ever one.
    func storeAvatar(_ pngData: Data) async throws -> String

    /// Removes the avatar file, if there is one.
    func removeAvatar(named filename: String) async

    /// Where the avatar lives, for displaying it.
    func avatarURL(named filename: String) -> URL

    /// Counts pages for documents that have no count yet.
    ///
    /// Page counts were added after some archives were already written, and a
    /// library that can never show them is worse than one that fills them in
    /// quietly the next time it opens.
    func pageCounts(missingIn archive: Archive) async -> [UUID: Int]
}

/// A file that is missing, unreadable, or no longer matches the hash recorded
/// when it was imported.
nonisolated struct IntegrityIssue: Identifiable, Hashable, Sendable {

    enum Kind: String, Sendable {
        case missing
        case unreadable
        case hashMismatch

        var title: String {
            switch self {
            case .missing: "File missing"
            case .unreadable: "File unreadable"
            case .hashMismatch: "File changed since import"
            }
        }
    }

    var id: UUID { documentID }
    var documentID: UUID
    var documentName: String
    var relativePath: String
    var kind: Kind
}

nonisolated enum ArchiveError: LocalizedError {
    case libraryUnavailable(String)
    case corruptArchive(String)
    case importFailed(String)

    /// Already a whole sentence about a name the owner typed. Prefixing it with
    /// machinery ("The library folder could not be opened…") would bury the one
    /// thing they need to read.
    case invalidLibraryName(String)

    var errorDescription: String? {
        switch self {
        case .libraryUnavailable(let detail): "The library folder could not be opened. \(detail)"
        case .corruptArchive(let detail): "The archive file could not be read. \(detail)"
        case .importFailed(let detail): "The document could not be imported. \(detail)"
        case .invalidLibraryName(let detail): detail
        }
    }
}
