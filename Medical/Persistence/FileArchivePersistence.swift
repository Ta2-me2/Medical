import CryptoKit
import Foundation
import PDFKit
import UniformTypeIdentifiers

/// The default backend: one readable JSON file plus a folder of untouched originals.
///
/// An actor, so disk work never runs on the main thread and two saves can never
/// interleave. Writes go through a temporary file and an atomic replace, which
/// is what makes a power cut during a save survivable — the archive is either
/// the old version or the new one, never half of either.
actor FileArchivePersistence: ArchivePersistence {

    private let root: URL
    private let fileManager = FileManager.default

    init(root: URL = ArchiveLocation.current) {
        self.root = root
    }

    // MARK: - Paths

    private var archiveURL: URL { root.appending(path: ArchiveLocation.archiveFilename) }
    private var manifestURL: URL { root.appending(path: ArchiveLocation.manifestFilename) }
    private var originalsURL: URL { root.appending(path: ArchiveLocation.originalsFolder, directoryHint: .isDirectory) }
    private var snapshotsURL: URL { root.appending(path: ArchiveLocation.snapshotsFolder, directoryHint: .isDirectory) }

    nonisolated func url(forRelativePath path: String) -> URL {
        root.appending(path: path)
    }

    // MARK: - Coding

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        // Readability is the whole point of this format: sorted keys keep diffs
        // between snapshots meaningful, ISO-8601 keeps dates legible to a human.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    // MARK: - Load

    func load() async throws -> Archive {
        try createLibraryIfNeeded()

        guard fileManager.fileExists(atPath: archiveURL.path(percentEncoded: false)) else {
            let archive = Archive()
            try write(archive)
            return archive
        }

        let data: Data
        do {
            data = try Data(contentsOf: archiveURL)
        } catch {
            throw ArchiveError.corruptArchive(error.localizedDescription)
        }

        do {
            return try decoder.decode(Archive.self, from: data)
        } catch {
            // The archive on disk is unreadable. Never overwrite it — set it
            // aside intact so it can be inspected or repaired by hand.
            try? quarantineUnreadableArchive()
            throw ArchiveError.corruptArchive(error.localizedDescription)
        }
    }

    // MARK: - Save

    func save(_ archive: Archive) async throws {
        try createLibraryIfNeeded()
        try snapshotCurrentArchive()
        try write(archive)
        try writeManifest(for: archive)
        try pruneSnapshots()
    }

    private func write(_ archive: Archive) throws {
        let data = try encoder.encode(archive)
        let temporary = root.appending(path: ".Archive.json.tmp")
        try data.write(to: temporary, options: .atomic)

        if fileManager.fileExists(atPath: archiveURL.path(percentEncoded: false)) {
            _ = try fileManager.replaceItemAt(archiveURL, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: archiveURL)
        }
    }

    private func writeManifest(for archive: Archive) throws {
        let manifest = LibraryManifest(
            archiveID: archive.archiveID,
            createdAt: archive.createdAt,
            lastWrittenAt: .now
        )
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
    }

    // MARK: - Snapshots

    private func snapshotCurrentArchive() throws {
        guard fileManager.fileExists(atPath: archiveURL.path(percentEncoded: false)) else { return }
        let destination = snapshotsURL.appending(path: "archive-\(Self.snapshotStamp(for: .now)).json")
        guard !fileManager.fileExists(atPath: destination.path(percentEncoded: false)) else { return }
        try fileManager.copyItem(at: archiveURL, to: destination)
    }

    private func pruneSnapshots() throws {
        let contents = (try? fileManager.contentsOfDirectory(
            at: snapshotsURL,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []

        let sorted = contents
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }

        for stale in sorted.dropFirst(ArchiveLocation.snapshotLimit) {
            try? fileManager.removeItem(at: stale)
        }
    }

    private func quarantineUnreadableArchive() throws {
        let stamp = Int(Date.now.timeIntervalSince1970)
        let destination = root.appending(path: "Archive-unreadable-\(stamp).json")
        try fileManager.moveItem(at: archiveURL, to: destination)
    }

    // MARK: - Originals

    func storeOriginal(from source: URL, year: Int, title: String?) async throws -> StoredDocument {
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }

        let data: Data
        do {
            data = try Data(contentsOf: source)
        } catch {
            throw ArchiveError.importFailed(error.localizedDescription)
        }

        let yearFolder = originalsURL.appending(path: String(year), directoryHint: .isDirectory)
        try fileManager.createDirectory(at: yearFolder, withIntermediateDirectories: true)

        // Name = short id + a readable slug, so the folder is navigable in Finder
        // while still guaranteeing that two files can never collide.
        let id = UUID()
        let slug = Self.slug(from: title?.nilIfEmpty ?? source.deletingPathExtension().lastPathComponent)
        let ext = source.pathExtension.lowercased()
        let filename = "\(id.uuidString.prefix(8).lowercased())-\(slug)\(ext.isEmpty ? "" : ".\(ext)")"
        let destination = yearFolder.appending(path: filename)

        do {
            try data.write(to: destination, options: .atomic)
            // Originals are read-only on disk as well as in code. Two locks are
            // better than one for the only data here that cannot be recreated.
            try fileManager.setAttributes([.posixPermissions: 0o444], ofItemAtPath: destination.path(percentEncoded: false))
        } catch {
            throw ArchiveError.importFailed(error.localizedDescription)
        }

        let relativePath = "\(ArchiveLocation.originalsFolder)/\(year)/\(filename)"
        let kind = StoredDocument.Kind.inferred(from: source)

        return StoredDocument(
            id: id,
            originalFilename: source.lastPathComponent,
            relativePath: relativePath,
            contentHash: Self.hash(of: data),
            byteSize: data.count,
            kind: kind,
            pageCount: Self.pageCount(of: destination, kind: kind),
            importedAt: .now,
            title: title?.nilIfEmpty
        )
    }

    func discardOriginal(_ document: StoredDocument, toTrash: Bool) async throws {
        let source = url(forRelativePath: document.relativePath)
        guard fileManager.fileExists(atPath: source.path(percentEncoded: false)) else { return }

        // Originals are stored read-only. Moving needs the file writable, so
        // this is the one place that unlocks one — and only to move it out.
        try? fileManager.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: source.path(percentEncoded: false)
        )

        do {
            if toTrash {
                try fileManager.trashItem(at: source, resultingItemURL: nil)
            } else {
                let folder = root.appending(path: ArchiveLocation.removedFolder, directoryHint: .isDirectory)
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
                try fileManager.moveItem(at: source, to: Self.availableURL(
                    in: folder,
                    named: source.lastPathComponent,
                    fileManager: fileManager
                ))
            }
        } catch {
            throw ArchiveError.importFailed(error.localizedDescription)
        }
    }

    /// A name that is not taken yet, so removing two files that arrived with the
    /// same name never loses one of them.
    private nonisolated static func availableURL(
        in folder: URL,
        named name: String,
        fileManager: FileManager
    ) -> URL {
        var candidate = folder.appending(path: name)
        guard fileManager.fileExists(atPath: candidate.path(percentEncoded: false)) else { return candidate }

        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var attempt = 2
        repeat {
            let suffix = ext.isEmpty ? "\(stem) \(attempt)" : "\(stem) \(attempt).\(ext)"
            candidate = folder.appending(path: suffix)
            attempt += 1
        } while fileManager.fileExists(atPath: candidate.path(percentEncoded: false))
        return candidate
    }

    // MARK: - Avatar

    func storeAvatar(_ pngData: Data) async throws -> String {
        let folder = root.appending(path: ArchiveLocation.avatarFolder, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        // A fresh name each time: the same path would be served from the image
        // cache and the old face would keep showing.
        let filename = "avatar-\(UUID().uuidString.prefix(8).lowercased()).png"
        try pngData.write(to: folder.appending(path: filename), options: .atomic)

        // Only one avatar is ever current; the rest are litter.
        let existing = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for stale in existing where stale.lastPathComponent != filename {
            try? fileManager.removeItem(at: stale)
        }

        return filename
    }

    func removeAvatar(named filename: String) async {
        try? fileManager.removeItem(at: avatarURL(named: filename))
    }

    nonisolated func avatarURL(named filename: String) -> URL {
        root
            .appending(path: ArchiveLocation.avatarFolder, directoryHint: .isDirectory)
            .appending(path: filename)
    }

    // MARK: - Integrity

    func verifyIntegrity(of archive: Archive) async -> [IntegrityIssue] {
        var issues: [IntegrityIssue] = []

        for record in archive.allDocuments {
            let document = record.document
            let location = url(forRelativePath: document.relativePath)

            guard fileManager.fileExists(atPath: location.path(percentEncoded: false)) else {
                issues.append(.init(
                    documentID: document.id,
                    documentName: document.displayName,
                    relativePath: document.relativePath,
                    kind: .missing
                ))
                continue
            }

            guard let data = try? Data(contentsOf: location) else {
                issues.append(.init(
                    documentID: document.id,
                    documentName: document.displayName,
                    relativePath: document.relativePath,
                    kind: .unreadable
                ))
                continue
            }

            if Self.hash(of: data) != document.contentHash {
                issues.append(.init(
                    documentID: document.id,
                    documentName: document.displayName,
                    relativePath: document.relativePath,
                    kind: .hashMismatch
                ))
            }
        }

        return issues
    }

    func pageCounts(missingIn archive: Archive) async -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for document in archive.documents where document.pageCount == nil {
            let location = url(forRelativePath: document.relativePath)
            guard fileManager.fileExists(atPath: location.path(percentEncoded: false)),
                  let count = Self.pageCount(of: location, kind: document.kind)
            else { continue }
            counts[document.id] = count
        }
        return counts
    }

    // MARK: - Setup

    private func createLibraryIfNeeded() throws {
        do {
            for folder in [root, originalsURL, snapshotsURL] {
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            }
        } catch {
            throw ArchiveError.libraryUnavailable(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    /// `2026-08-07-194312`. Fixed locale and sortable, so the snapshot folder
    /// reads chronologically in Finder regardless of the user's region.
    nonisolated static func snapshotStamp(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: date)
    }

    /// Counted once, at import, so the library can show it without opening the
    /// file again. An unreadable PDF returns nothing rather than zero — not
    /// knowing and knowing it is empty are different answers.
    nonisolated static func pageCount(of url: URL, kind: StoredDocument.Kind) -> Int? {
        switch kind {
        case .pdf: PDFDocument(url: url)?.pageCount
        case .image, .scan: 1
        case .other: nil
        }
    }

    nonisolated static func hash(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func slug(from text: String) -> String {
        let lowered = text.lowercased().folding(options: .diacriticInsensitive, locale: .init(identifier: "en_US"))
        let allowed = CharacterSet.alphanumerics
        let cleaned = lowered.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let collapsed = String(cleaned)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? "document" : String(collapsed.prefix(48))
    }
}
