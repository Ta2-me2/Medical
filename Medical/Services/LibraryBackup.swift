import Foundation

/// Zipping, with the system's own archiver.
///
/// `ditto` is what Finder's Compress uses. Going through it rather than a
/// library means the archives this app writes are ordinary zips that any Mac,
/// and any other operating system, can open in thirty years without this app.
nonisolated enum Zip {

    static func compress(folder: URL, to destination: URL) throws {
        try? FileManager.default.removeItem(at: destination)
        try run([
            "-c", "-k", "--sequesterRsrc", "--keepParent",
            folder.path(percentEncoded: false),
            destination.path(percentEncoded: false),
        ])
    }

    static func expand(archive: URL, into folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try run([
            "-x", "-k",
            archive.path(percentEncoded: false),
            folder.path(percentEncoded: false),
        ])
    }

    private static func run(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments

        let errors = Pipe()
        process.standardError = errors

        try process.run()
        let data = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ArchiveError.importFailed(message?.nilIfEmpty ?? "The archive could not be created.")
        }
    }
}

/// Moving the whole library between machines.
///
/// The library is already a plain folder, so a backup is just that folder in a
/// zip: `Archive.json`, every original, every snapshot. Nothing is transformed
/// on the way out, which is what makes the way back in trustworthy — restoring
/// is unzipping, not importing.
nonisolated struct LibraryBackup: Sendable {

    /// What a restored folder must contain before the app will point at it.
    static let requiredFile = ArchiveLocation.archiveFilename

    /// Writes the entire library to a single zip.
    static func export(from library: URL, to destination: URL) throws {
        guard FileManager.default.fileExists(atPath: library.path(percentEncoded: false)) else {
            throw ArchiveError.libraryUnavailable("There is nothing at \(library.path(percentEncoded: false)).")
        }
        try Zip.compress(folder: library, to: destination)
    }

    /// Unpacks a backup into the folder of libraries and returns the restored
    /// library, indistinguishable from one made on this Mac.
    ///
    /// The zip is written with `--keepParent`, so it expands to a folder
    /// containing the library folder. That extra layer is an artefact of how
    /// the archive was made, and inheriting it would leave the owner with a
    /// library nested one level too deep — invisible to a list that looks for
    /// libraries where libraries live, and shaped unlike every other one they
    /// own. So the backup is expanded out of sight first and only the library
    /// itself is kept.
    ///
    /// Never writes into an existing library: a restore that overwrites is a
    /// restore that can destroy the thing it was meant to protect. It takes the
    /// name the library had when it was backed up, and a number after it if
    /// that name is taken.
    static func restore(from backup: URL, into parent: URL) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)

        // Staged inside the destination folder, not in /tmp: the last step is
        // then a rename on the same volume rather than a second copy of an
        // archive that may be gigabytes. Hidden, so a restore interrupted
        // half-way leaves nothing that looks like a library.
        let staging = parent.appending(
            path: ".restoring-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: staging) }

        try Zip.expand(archive: backup, into: staging)

        guard let library = locateLibrary(under: staging) else {
            throw ArchiveError.corruptArchive(
                "That backup does not contain \(requiredFile)."
            )
        }

        let destination = freeName(like: library.lastPathComponent, in: parent)
        try fileManager.moveItem(at: library, to: destination)
        return destination
    }

    /// `Family Archive`, or `Family Archive 2` when the first is taken.
    private static func freeName(like name: String, in parent: URL) -> URL {
        let fileManager = FileManager.default
        var candidate = parent.appending(path: name, directoryHint: .isDirectory)
        var attempt = 2
        while fileManager.fileExists(atPath: candidate.path(percentEncoded: false)) {
            candidate = parent.appending(path: "\(name) \(attempt)", directoryHint: .isDirectory)
            attempt += 1
        }
        return candidate
    }

    /// A zip made with `--keepParent` unpacks to a folder containing the library
    /// folder, so look one level down as well as at the top.
    private static func locateLibrary(under root: URL) -> URL? {
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: root.appending(path: requiredFile).path(percentEncoded: false)) {
            return root
        }

        let contents = (try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        for candidate in contents {
            let isDirectory = (try? candidate.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDirectory else { continue }
            if fileManager.fileExists(atPath: candidate.appending(path: requiredFile).path(percentEncoded: false)) {
                return candidate
            }
        }

        return nil
    }

    /// A quick description of what a backup holds, shown before restoring so
    /// nobody swaps their library for a file they cannot identify.
    static func inspect(_ library: URL) -> Summary? {
        guard let data = try? Data(contentsOf: library.appending(path: requiredFile)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let archive = try? decoder.decode(Archive.self, from: data) else { return nil }
        return Summary(
            patientName: archive.patient.displayName,
            eventCount: archive.events.count,
            documentCount: archive.documents.count,
            createdAt: archive.createdAt
        )
    }

    struct Summary: Sendable {
        var patientName: String
        var eventCount: Int
        var documentCount: Int
        var createdAt: Date

        var description: String {
            "\(patientName) · \(eventCount) records · \(documentCount) documents"
        }
    }
}
