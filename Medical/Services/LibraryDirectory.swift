import Foundation

/// One library folder, as the chooser sees it.
nonisolated struct LibraryEntry: Identifiable, Hashable, Sendable {
    var url: URL
    var name: String
    var patientName: String?
    var eventCount: Int?
    var documentCount: Int?
    var updatedAt: Date?

    var id: String { LibraryDirectory.identity(of: url) }

    /// `John Appleseed · 50 records · 21 documents`, or an honest shrug. A
    /// folder that cannot be read is still listed: pretending it is not there
    /// would leave the owner staring at a library they can see in Finder.
    var summary: String {
        guard let eventCount, let documentCount else {
            return "This folder could not be read"
        }
        var parts: [String] = []
        if let patientName, !patientName.isEmpty { parts.append(patientName) }
        parts.append("\(eventCount) \(eventCount == 1 ? "record" : "records")")
        parts.append("\(documentCount) \(documentCount == 1 ? "document" : "documents")")
        return parts.joined(separator: " · ")
    }
}

/// The folder of libraries, read and edited.
///
/// An archive meant to last decades will outlive more than one attempt at
/// starting it — a trial run, a restored backup, a second person's records.
/// Those all sit side by side in Application Support already; this is what lets
/// the owner see them without a detour through Finder and hidden folders.
///
/// An actor, like the rest of the disk layer: listing libraries reads every
/// archive file it finds, which has no business on the main thread.
actor LibraryDirectory {

    private let fileManager = FileManager.default

    /// Every library the application knows about: the ones in its own folder,
    /// plus wherever the current one actually is, which may be somewhere the
    /// owner chose.
    func entries(current: URL) -> [LibraryEntry] {
        let contents = (try? fileManager.contentsOfDirectory(
            at: ArchiveLocation.container,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var urls = contents.filter(isLibrary)
        if !urls.contains(where: { Self.identity(of: $0) == Self.identity(of: current) }) {
            urls.append(current)
        }

        return urls
            .map(entry(for:))
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Makes an empty library folder.
    ///
    /// Nothing is written into it here — `Archive.json` appears when the app
    /// opens it, through the same path that creates a first library. Creating
    /// and opening are therefore one action for the caller, and a folder is
    /// never left behind half-made.
    func create(named name: String) throws -> URL {
        let clean = try validated(name)
        let destination = ArchiveLocation.container.appending(path: clean, directoryHint: .isDirectory)
        guard !exists(destination) else {
            throw ArchiveError.invalidLibraryName("There is already a library called “\(clean)”.")
        }
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        return destination
    }

    /// Renames the folder and returns where it now is.
    ///
    /// The library is its folder, so renaming is `mv` and nothing else — no
    /// field inside the archive has to agree, because none of them holds a name.
    func rename(_ url: URL, to name: String) throws -> URL {
        let clean = try validated(name)
        guard clean != url.lastPathComponent else { return url }

        let destination = url.deletingLastPathComponent().appending(path: clean, directoryHint: .isDirectory)

        // On a case-insensitive volume "library" already "exists" when you are
        // renaming "Library" — that is the same folder, and a legal rename.
        let isRecapitalisation = Self.identity(of: destination)
            .compare(Self.identity(of: url), options: .caseInsensitive) == .orderedSame
        guard isRecapitalisation || !exists(destination) else {
            throw ArchiveError.invalidLibraryName("There is already a library called “\(clean)”.")
        }

        try fileManager.moveItem(at: url, to: destination)
        return destination
    }

    // MARK: - Reading

    private func isLibrary(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return false }
        return exists(url.appending(path: ArchiveLocation.archiveFilename))
    }

    private func entry(for url: URL) -> LibraryEntry {
        let summary = LibraryBackup.inspect(url)
        let modified = try? url
            .appending(path: ArchiveLocation.archiveFilename)
            .resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate

        return LibraryEntry(
            url: url,
            name: url.lastPathComponent,
            patientName: summary?.patientName,
            eventCount: summary?.eventCount,
            documentCount: summary?.documentCount,
            updatedAt: modified
        )
    }

    private func exists(_ url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path(percentEncoded: false))
    }

    private func validated(_ name: String) throws -> String {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !clean.isEmpty else {
            throw ArchiveError.invalidLibraryName("A library needs a name.")
        }
        guard !clean.hasPrefix(".") else {
            throw ArchiveError.invalidLibraryName("A name beginning with a dot would hide the folder from Finder.")
        }
        guard !clean.contains("/"), !clean.contains(":") else {
            throw ArchiveError.invalidLibraryName("A library name cannot contain “/” or “:”.")
        }
        return clean
    }

    /// One folder, one name for it. See `FilePath`.
    nonisolated static func identity(of url: URL) -> String {
        FilePath.normalised(url)
    }
}
