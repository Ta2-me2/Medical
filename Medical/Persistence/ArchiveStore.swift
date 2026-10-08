import Foundation
import Observation

/// The single in-memory copy of the archive, and the only thing the interface
/// ever mutates.
///
/// Every change goes through `update`, which applies the mutation and schedules
/// a save. Views never call the persistence layer, and never learn whether a
/// save succeeded by asking — they read `saveState`.
@Observable
final class ArchiveStore {

    enum LoadState: Equatable {
        case loading
        case ready
        case failed(String)
    }

    enum SaveState: Equatable {
        case saved
        case pending
        case saving
        case failed(String)
    }

    private(set) var archive = Archive()
    private(set) var loadState: LoadState = .loading
    private(set) var saveState: SaveState = .saved
    private(set) var lastSavedAt: Date?
    private(set) var integrityIssues: [IntegrityIssue] = []

    private var persistence: any ArchivePersistence
    private var pendingSave: Task<Void, Never>?

    /// Long enough that typing in a text field does not write the file on every
    /// keystroke, short enough that closing the lid right after an edit is safe.
    private let autosaveDelay: Duration = .milliseconds(1200)

    init(
        persistence: any ArchivePersistence = FileArchivePersistence(),
        libraryMove: ArchiveLocation.Adoption = .notNeeded
    ) {
        self.persistence = persistence
        self.libraryMove = libraryMove
    }

    private(set) var libraryURL: URL = ArchiveLocation.current

    /// A sentence the screen owes the owner after an action that reloads the
    /// archive — restoring a backup, above all.
    ///
    /// It lives here rather than on the page that started it because loading a
    /// different archive rebuilds that page from scratch, and a message kept in
    /// the page's own state would be thrown away in the moment it was earned.
    var announcement: String?

    /// What happened to a library that was still in Documents at launch.
    /// Kept so the one case the owner needs to hear about — it did not move —
    /// can say so instead of passing for success.
    private(set) var libraryMove: ArchiveLocation.Adoption

    /// Points the app at a different library folder and reads it.
    ///
    /// Used by switching libraries and by restore. The library being left is
    /// written out first and then left exactly where it was: neither switching
    /// nor restoring is allowed to become a way of losing an archive.
    func relocate(to url: URL) async {
        await saveNow()
        await adopt(url)
    }

    /// Renames a library's folder, and keeps working if it is the open one.
    ///
    /// The order matters. The archive is written to the old path first, then
    /// the folder moves, then the store is pointed at the new path — saving
    /// afterwards through a stale root would quietly recreate the folder the
    /// owner had just renamed away from.
    func rename(_ url: URL, to name: String, using directory: LibraryDirectory) async throws -> URL {
        let isOpen = LibraryDirectory.identity(of: url) == LibraryDirectory.identity(of: libraryURL)
        if isOpen { await saveNow() }

        let destination = try await directory.rename(url, to: name)

        if isOpen { repoint(to: destination) }
        return destination
    }

    /// Takes up a library folder, without writing anything to the previous one.
    private func adopt(_ url: URL) async {
        repoint(to: url)
        await load()
    }

    /// Follows the same archive to a new path without re-reading it.
    ///
    /// A rename changes the folder's name and nothing inside it, so reloading
    /// would spend the time to arrive at the copy already in memory — and take
    /// the screen back to its loading state on the way, closing whatever the
    /// owner had open in front of it.
    private func repoint(to url: URL) {
        ArchiveLocation.setCurrent(url)
        libraryURL = url
        libraryMove = .notNeeded
        persistence = FileArchivePersistence(root: url)
    }

    // MARK: - Loading

    func load() async {
        loadState = .loading
        do {
            archive = try await persistence.load()
            loadState = .ready
            await backfillPageCounts()
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    /// Fills in page counts for documents imported before the library counted
    /// them. Runs after the archive is on screen, so opening stays instant.
    private func backfillPageCounts() async {
        let counts = await persistence.pageCounts(missingIn: archive)
        guard !counts.isEmpty else { return }
        update { archive in
            for index in archive.documents.indices {
                if let count = counts[archive.documents[index].id] {
                    archive.documents[index].pageCount = count
                }
            }
        }
    }

    // MARK: - Mutation

    /// Applies a change and schedules a save.
    ///
    /// Synchronous on purpose: the interface must reflect the edit immediately,
    /// and durability is a separate concern that follows a moment later.
    func update(_ mutate: (inout Archive) -> Void) {
        mutate(&archive)
        scheduleSave()
    }

    func upsert(_ event: MedicalEvent) {
        update { $0.upsert(event) }
    }

    func deleteEvent(id: UUID) {
        update { $0.removeEvent(id: id) }
    }

    private func scheduleSave() {
        saveState = .pending
        pendingSave?.cancel()
        pendingSave = Task { [autosaveDelay] in
            try? await Task.sleep(for: autosaveDelay)
            guard !Task.isCancelled else { return }
            await self.saveNow()
        }
    }

    /// Writes immediately. Called on quit and before exporting, where waiting
    /// out the autosave delay would be wrong.
    func saveNow() async {
        pendingSave?.cancel()
        pendingSave = nil
        saveState = .saving
        let snapshot = archive
        do {
            try await persistence.save(snapshot)
            saveState = .saved
            lastSavedAt = .now
        } catch {
            saveState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Documents

    /// Copies a file into the library. The source file is left untouched.
    func storeOriginal(from source: URL, year: Int, title: String? = nil) async throws -> StoredDocument {
        try await persistence.storeOriginal(from: source, year: year, title: title)
    }

    /// Removes a document from the archive, and moves its file out of the way.
    ///
    /// Two steps, in this order: the file first, so a failure to move it leaves
    /// the archive still pointing at something real rather than referring to a
    /// document it has already forgotten.
    func remove(_ document: StoredDocument, toTrash: Bool) async -> String? {
        do {
            try await persistence.discardOriginal(document, toTrash: toTrash)
        } catch {
            return error.localizedDescription
        }
        update { $0.removeDocument(id: document.id) }
        await saveNow()
        return nil
    }

    /// Saves a new avatar and points the patient record at it.
    func setAvatar(_ pngData: Data) async -> String? {
        let previous = archive.patient.avatarFilename
        do {
            let filename = try await persistence.storeAvatar(pngData)
            update { $0.patient.avatarFilename = filename }
            if let previous, previous != filename {
                await persistence.removeAvatar(named: previous)
            }
            await saveNow()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func clearAvatar() async {
        guard let filename = archive.patient.avatarFilename else { return }
        update { $0.patient.avatarFilename = nil }
        await persistence.removeAvatar(named: filename)
        await saveNow()
    }

    func avatarURL() -> URL? {
        archive.patient.avatarFilename.map { persistence.avatarURL(named: $0) }
    }

    func fileURL(for document: StoredDocument) -> URL {
        persistence.url(forRelativePath: document.relativePath)
    }

    // MARK: - Integrity

    func verifyIntegrity() async {
        integrityIssues = await persistence.verifyIntegrity(of: archive)
    }
}
