import Foundation

/// Where the library folder lives.
///
/// The library is a plain folder the user can move, back up with Time Machine,
/// or copy to another machine. Its path is remembered, not hardcoded, so
/// relocating it is a supported operation rather than a migration.
///
/// It lives in Application Support, not in Documents. Documents belongs to the
/// person, not to the program: a folder left there is theirs to rename, tidy
/// into a subfolder, or drag somewhere else on a Tuesday afternoon — all of
/// which quietly break an application holding the folder open. Application
/// Support is the opposite promise. It is where an application keeps what it
/// looks after on the owner's behalf, it survives dragging the app to the
/// Trash, and — the reason that matters most here — it is not synced to iCloud
/// the way Desktop and Documents often are, so an archive of medical records
/// stops being copied to a server nobody asked about.
nonisolated enum ArchiveLocation {

    /// The single folder Medical owns in Application Support. Every library
    /// lives inside it, and nothing that is not the owner's data does.
    static let containerName = "Medical"

    static let folderName = "Medical Library"

    /// What those two were called before the application was renamed. Kept
    /// because folders on disk outlive product decisions, and a library the
    /// owner already has must keep opening.
    private static let legacyContainerName = "Medical ID"
    private static let legacyFolderName = "Medical ID Library"

    fileprivate static let bookmarkKey = "libraryFolderPath"

    /// `~/Library/Application Support/Medical/Medical Library` unless the user
    /// has moved it.
    static var current: URL {
        if let stored = UserDefaults.standard.string(forKey: bookmarkKey), !stored.isEmpty {
            return URL(fileURLWithPath: stored, isDirectory: true)
        }
        return defaultLocation
    }

    /// Everything the application stores for its owner, under one roof — so
    /// that a new library, or one unpacked from a backup, lands beside the
    /// current one instead of scattering folders through Application Support.
    static var container: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Library/Application Support", directoryHint: .isDirectory)
        return support.appending(path: containerName, directoryHint: .isDirectory)
    }

    static var defaultLocation: URL {
        container.appending(path: folderName, directoryHint: .isDirectory)
    }

    static func setCurrent(_ url: URL) {
        UserDefaults.standard.set(url.path(percentEncoded: false), forKey: bookmarkKey)
    }

    // MARK: - Layout
    //
    // Everything below is the on-disk contract. Changing any of these names
    // breaks existing libraries, so they are defined once, here.

    static let archiveFilename = "Archive.json"
    static let manifestFilename = "Library.json"
    static let originalsFolder = "Originals"
    static let snapshotsFolder = "Snapshots"
    static let avatarFolder = "Avatar"

    /// Originals the owner has taken out of the archive but not deleted.
    /// Nothing in the app writes to `Originals/` after import; removal moves
    /// files here so the archive is clean and the bytes are still there.
    static let removedFolder = "Removed"

    /// How many previous versions of `Archive.json` to keep.
    static let snapshotLimit = 40
}

// MARK: - Leaving Documents

extension ArchiveLocation {

    /// The result of the one-time move out of `~/Documents`.
    enum Adoption: Equatable {
        /// Nothing to do: the library is already outside Documents.
        case notNeeded
        /// Moved, and the stored path now points at the new folder.
        case moved(from: URL, to: URL)
        /// iCloud has not finished downloading the library. Downloads were
        /// requested; the move is retried on a later launch.
        case waitingForDownload(URL)
        /// The move failed. The library is untouched and still works.
        case failed(URL, String)
    }

    /// Moves a library that still sits in `~/Documents` into Application Support.
    ///
    /// Only a folder that is plainly ours is touched: it must be directly in
    /// Documents, carry the library's name, and contain an archive file.
    /// Anywhere else, the owner put it there deliberately — and deliberate is
    /// not something to undo on their behalf.
    ///
    /// Nothing is ever copied-then-deleted by hand and nothing is overwritten:
    /// either the folder arrives whole at a name that was free, or it stays
    /// exactly where it is.
    @discardableResult
    static func adoptLegacyLibraryIfNeeded() -> Adoption {
        let fileManager = FileManager.default

        let stored = UserDefaults.standard.string(forKey: bookmarkKey).flatMap {
            $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true)
        }
        let source = (stored ?? legacyDefaultLocation).standardizedFileURL
        guard isLegacyLibrary(source) else { return .notNeeded }

        // A folder iCloud is still syncing may exist on disk as placeholders
        // rather than files. Moving those out of the synced tree would carry
        // across the stubs and strand the contents, so ask for the real bytes
        // and leave the library where it is until they arrive.
        if hasUndownloadedContents(source) {
            return .waitingForDownload(source)
        }

        guard let destination = freeDestination(for: source) else {
            return .failed(source, "A library folder is already there.")
        }

        do {
            try fileManager.createDirectory(at: container, withIntermediateDirectories: true)
            try fileManager.moveItem(at: source, to: destination)
        } catch {
            // The library stays where it is and keeps working. A move that did
            // not happen is an inconvenience; a half-moved library would not be.
            return .failed(source, error.localizedDescription)
        }

        setCurrent(destination)
        return .moved(from: source, to: destination)
    }

    /// `~/Documents/Medical ID Library`, where libraries were kept before.
    private static var legacyDefaultLocation: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return documents.appending(path: legacyFolderName, directoryHint: .isDirectory)
    }

    private static func isLegacyLibrary(_ url: URL) -> Bool {
        let fileManager = FileManager.default
        let documents = legacyDefaultLocation.deletingLastPathComponent().standardizedFileURL
        guard url.deletingLastPathComponent().standardizedFileURL == documents else { return false }

        // "Medical ID Library", and the "Medical ID Library 2" that starting a
        // new library beside the old one produces.
        guard url.lastPathComponent.hasPrefix(legacyFolderName) else { return false }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return false }

        return fileManager.fileExists(atPath: url.appending(path: archiveFilename).path(percentEncoded: false))
    }

    /// Prefers the current default name: a library called "Medical ID Library
    /// 2" arrives as "Medical Library", carrying neither the old product's name
    /// nor a number that explains a history the owner has forgotten.
    private static func freeDestination(for source: URL) -> URL? {
        let fileManager = FileManager.default
        let candidates = [folderName, source.lastPathComponent]
        for name in candidates {
            let candidate = container.appending(path: name, directoryHint: .isDirectory)
            if !fileManager.fileExists(atPath: candidate.path(percentEncoded: false)) {
                return candidate
            }
        }
        return nil
    }

    private static func hasUndownloadedContents(_ url: URL) -> Bool {
        let fileManager = FileManager.default
        guard fileManager.isUbiquitousItem(at: url) else { return false }

        let keys: Set<URLResourceKey> = [.ubiquitousItemDownloadingStatusKey]
        guard let walker = fileManager.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else {
            return true
        }

        var waiting = false
        for case let file as URL in walker {
            let status = try? file.resourceValues(forKeys: keys).ubiquitousItemDownloadingStatus
            guard status == .notDownloaded else { continue }
            try? fileManager.startDownloadingUbiquitousItem(at: file)
            waiting = true
        }
        return waiting
    }
}

// MARK: - Renaming the application's own folder

extension ArchiveLocation {

    /// Follows the application's own folder when the application is renamed.
    ///
    /// The folder in Application Support carries the product's name, and the
    /// product's name changed. Nothing inside is touched: the folder is renamed
    /// and anything that pointed into it is pointed into it still. Runs before
    /// everything else at launch, because every other path is built from it.
    @discardableResult
    static func adoptRenamedContainerIfNeeded() -> URL? {
        let fileManager = FileManager.default
        let previous = container
            .deletingLastPathComponent()
            .appending(path: legacyContainerName, directoryHint: .isDirectory)

        guard fileManager.fileExists(atPath: previous.path(percentEncoded: false)),
              !fileManager.fileExists(atPath: container.path(percentEncoded: false))
        else { return nil }

        do {
            try fileManager.moveItem(at: previous, to: container)
        } catch {
            // The old folder still works; only its name is out of date.
            return nil
        }

        // A stored path pointing anywhere inside now points inside the new name.
        if let stored = UserDefaults.standard.string(forKey: bookmarkKey), !stored.isEmpty {
            let was = FilePath.normalised(previous)
            let points = FilePath.normalised(stored)
            if points == was || points.hasPrefix(was + "/") {
                let inside = String(points.dropFirst(was.count))
                setCurrent(URL(
                    fileURLWithPath: FilePath.normalised(container) + inside,
                    isDirectory: true
                ))
            }
        }

        return container
    }
}

// MARK: - Repairing a library left too deep

extension ArchiveLocation {

    /// Opens up a library that an early restore left one level too deep.
    ///
    /// A backup zip expands to a folder containing the library folder, and
    /// restoring used to keep that wrapper: `Medical/<wrapper>/<library>`.
    /// A library down there is shaped unlike every other one the owner has, and
    /// the chooser — which looks for libraries where libraries live — loses
    /// sight of it the moment they open a different one.
    ///
    /// Only a wrapper is touched: a folder that is no library itself and holds
    /// nothing but one. A folder with two libraries in it, or with anything
    /// else beside them, was arranged by somebody and is left alone.
    @discardableResult
    static func flattenNestedLibraries() -> [URL] {
        let fileManager = FileManager.default
        var moved: [URL] = []

        let contents = (try? fileManager.contentsOfDirectory(
            at: container,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        for wrapper in contents {
            guard isDirectory(wrapper), !holdsArchive(wrapper) else { continue }

            let inside = (try? fileManager.contentsOfDirectory(
                at: wrapper,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            guard inside.count == 1, let library = inside.first,
                  isDirectory(library), holdsArchive(library)
            else { continue }

            guard let destination = freeName(like: library.lastPathComponent) else { continue }

            // Asked while the folder is still there: comparing paths is much
            // more reliable about a place that exists than about one that was
            // moved a line ago.
            let wasOpen = isCurrent(library)

            do {
                try fileManager.moveItem(at: library, to: destination)
            } catch {
                // Leave it where it is; it still opens.
                continue
            }

            // The wrapper has nothing left in it but whatever Finder dropped.
            try? fileManager.removeItem(at: wrapper)

            if wasOpen { setCurrent(destination) }
            moved.append(destination)
        }

        return moved
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: url.path(percentEncoded: false),
            isDirectory: &isDirectory
        )
        return exists && isDirectory.boolValue
    }

    private static func holdsArchive(_ url: URL) -> Bool {
        FileManager.default.fileExists(
            atPath: url.appending(path: archiveFilename).path(percentEncoded: false)
        )
    }

    private static func isCurrent(_ url: URL) -> Bool {
        guard let stored = UserDefaults.standard.string(forKey: bookmarkKey), !stored.isEmpty else {
            return false
        }
        return trimmed(stored) == trimmed(url.path(percentEncoded: false))
    }

    private static func freeName(like name: String) -> URL? {
        let fileManager = FileManager.default
        var candidate = container.appending(path: name, directoryHint: .isDirectory)
        var attempt = 2
        while fileManager.fileExists(atPath: candidate.path(percentEncoded: false)) {
            guard attempt < 100 else { return nil }
            candidate = container.appending(path: "\(name) \(attempt)", directoryHint: .isDirectory)
            attempt += 1
        }
        return candidate
    }

    /// Two spellings of one folder are one folder. `/var` and `/private/var`
    /// are the same place, a directory URL carries a trailing slash and a
    /// listed one does not, and the stored path and a freshly listed path
    /// routinely disagree on both.
    private static func trimmed(_ path: String) -> String {
        FilePath.normalised(path)
    }
}

/// Two spellings of one folder are one folder.
///
/// Paths reach the application from three directions — typed into defaults,
/// handed back by a directory listing, built by appending components — and the
/// three disagree about trailing slashes and about `/var` versus `/private/var`.
/// Comparing them raw means the application quietly stops recognising the
/// library it has open.
nonisolated enum FilePath {

    /// macOS firmlinks these three; nothing else on the system needs the same
    /// treatment.
    private static let firmlinked = ["/var", "/tmp", "/etc"]

    static func normalised(_ path: String) -> String {
        var value = URL(fileURLWithPath: path)
            .resolvingSymlinksInPath()
            .path(percentEncoded: false)

        // `resolvingSymlinksInPath` only adds the `/private` prefix when the
        // result names something that exists, so a folder that has just been
        // moved or deleted compares unequal to itself.
        for root in firmlinked where value == root || value.hasPrefix(root + "/") {
            value = "/private" + value
            break
        }

        while value.count > 1, value.hasSuffix("/") { value.removeLast() }
        return value
    }

    static func normalised(_ url: URL) -> String {
        normalised(url.path(percentEncoded: false))
    }
}

/// Written next to `Archive.json` so that a folder found in twenty years
/// explains itself without this application.
nonisolated struct LibraryManifest: Codable, Sendable {
    var application = "Medical"
    var formatVersion = Archive.currentFormatVersion
    var archiveID: UUID
    var createdAt: Date
    var lastWrittenAt: Date
    var readMe = """
        This folder is a personal medical archive.

        Archive.json holds every record in plain, readable JSON.
        Originals/ holds the imported documents, unmodified, organised by year.
        Snapshots/ holds previous versions of Archive.json.

        Nothing here requires the Medical application to read.
        """
}
