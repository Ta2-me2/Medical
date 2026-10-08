import Foundation

/// Checks the one-time move of a library out of `~/Documents` and into
/// Application Support.
///
/// Runs against a stand-in home directory (`CFFIXED_USER_HOME`), because a
/// check that moves folders is only worth having if it is allowed to move
/// real ones — and it must never be allowed to move the owner's.
///
/// The one case that cannot be staged here is a library iCloud has evicted to
/// placeholders. That path is guarded in `hasUndownloadedContents`, and there
/// is no way to fabricate an evicted file without an iCloud account.
func checkLibraryLocation() {
    let fileManager = FileManager.default

    guard let stub = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"], !stub.isEmpty else {
        section("Where the library lives")
        check("run.sh provides a stand-in home directory", false)
        return
    }

    let home = URL(fileURLWithPath: stub, isDirectory: true)
    let documents = home.appending(path: "Documents", directoryHint: .isDirectory)
    let support = home.appending(path: "Library/Application Support", directoryHint: .isDirectory)
    let container = support.appending(path: ArchiveLocation.containerName, directoryHint: .isDirectory)

    /// What libraries in Documents were called, before the application was
    /// renamed. Written out rather than taken from `folderName`, because the
    /// name on those folders is a fact about the past and does not follow the
    /// product.
    let legacy = "Medical ID Library"


    /// What one is called once it arrives.
    let name = ArchiveLocation.folderName

    func reset() {
        for folder in [documents, support] {
            try? fileManager.removeItem(at: folder)
            try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        UserDefaults.standard.removeObject(forKey: "libraryFolderPath")
    }

    /// A library folder with one original inside, so that a move can be checked
    /// for carrying the contents across and not merely the folder.
    @discardableResult
    func makeLibrary(at url: URL, marker: String) -> URL {
        try? fileManager.createDirectory(
            at: url.appending(path: "Originals/2011", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        try? Data("{}".utf8).write(to: url.appending(path: ArchiveLocation.archiveFilename))
        try? Data(marker.utf8).write(to: url.appending(path: "Originals/2011/scan.pdf"))
        return url
    }

    func exists(_ url: URL) -> Bool { fileManager.fileExists(atPath: url.path(percentEncoded: false)) }

    func marker(_ library: URL) -> String? {
        try? String(contentsOf: library.appending(path: "Originals/2011/scan.pdf"), encoding: .utf8)
    }

    var stored: String? { UserDefaults.standard.string(forKey: "libraryFolderPath") }

    /// A directory URL carries a trailing slash, which is not what any of these
    /// checks is about.
    /// The application's own idea of when two paths name one folder — trailing
    /// slashes, and `/var` against `/private/var`. These checks are about which
    /// folder, never about how it was spelled.
    func trimmed(_ path: String) -> String {
        FilePath.normalised(path)
    }
    func same(_ one: URL, _ other: URL) -> Bool {
        trimmed(one.path(percentEncoded: false)) == trimmed(other.path(percentEncoded: false))
    }

    let landed = container.appending(path: name, directoryHint: .isDirectory)

    section("The application's own folder is renamed with it")

    reset()
    let previousContainer = support.appending(path: "Medical ID", directoryHint: .isDirectory)
    let inside = makeLibrary(at: previousContainer.appending(path: legacy, directoryHint: .isDirectory),
                             marker: "carried across")
    UserDefaults.standard.set(inside.path(percentEncoded: false), forKey: "libraryFolderPath")

    check("the folder is renamed", ArchiveLocation.adoptRenamedContainerIfNeeded() != nil)
    check("the old name is gone", !exists(previousContainer))
    check("everything inside came with it",
          marker(container.appending(path: legacy, directoryHint: .isDirectory)) == "carried across")
    check("and the library the app had open is still the one it has open",
          trimmed(stored ?? "")
            == trimmed(container.appending(path: legacy).path(percentEncoded: false)))
    check("running again finds nothing to do",
          ArchiveLocation.adoptRenamedContainerIfNeeded() == nil)

    // Both names present: somebody has been here, and the app is not the one to
    // decide which of the two is real.
    reset()
    makeLibrary(at: support.appending(path: "Medical ID/Old", directoryHint: .isDirectory), marker: "old")
    makeLibrary(at: container.appending(path: "New", directoryHint: .isDirectory), marker: "new")
    check("a folder under both names is left alone",
          ArchiveLocation.adoptRenamedContainerIfNeeded() == nil)
    check("and both are untouched",
          marker(support.appending(path: "Medical ID/Old", directoryHint: .isDirectory)) == "old"
            && marker(container.appending(path: "New", directoryHint: .isDirectory)) == "new")

    // A library the owner keeps somewhere else is not repointed by a rename
    // that happened in a folder it does not live in.
    reset()
    makeLibrary(at: previousContainer.appending(path: legacy, directoryHint: .isDirectory), marker: "moved")
    let outside = makeLibrary(at: home.appending(path: "Elsewhere/Records", directoryHint: .isDirectory),
                              marker: "outside")
    UserDefaults.standard.set(outside.path(percentEncoded: false), forKey: "libraryFolderPath")
    _ = ArchiveLocation.adoptRenamedContainerIfNeeded()
    check("a library kept outside is still the one the app has open",
          trimmed(stored ?? "") == trimmed(outside.path(percentEncoded: false)))


    section("Where the library lives")

    reset()
    check("a fresh install points at Application Support",
          same(ArchiveLocation.defaultLocation, landed))
    check("with nothing in Documents there is nothing to move",
          ArchiveLocation.adoptLegacyLibraryIfNeeded() == .notNeeded)
    check("and no folder is created just by asking", !exists(container))

    section("Moving a library out of Documents")

    reset()
    let legacyLibrary = makeLibrary(at: documents.appending(path: legacy, directoryHint: .isDirectory), marker: "original")
    if case .moved(let from, let to) = ArchiveLocation.adoptLegacyLibraryIfNeeded() {
        check("the folder is moved", same(from, legacyLibrary) && same(to, landed))
    } else {
        check("the folder is moved", false)
    }
    check("Documents no longer holds it", !exists(legacyLibrary))
    check("the originals came with it", marker(landed) == "original")
    check("the archive file came with it", exists(landed.appending(path: ArchiveLocation.archiveFilename)))
    check("the new path is remembered", trimmed(stored ?? "") == trimmed(landed.path(percentEncoded: false)))
    check("running again does nothing", ArchiveLocation.adoptLegacyLibraryIfNeeded() == .notNeeded)
    check("and leaves the library where it was moved to", marker(landed) == "original")

    section("The library the app is actually pointed at")

    reset()
    let second = makeLibrary(at: documents.appending(path: "\(legacy) 2", directoryHint: .isDirectory), marker: "second")
    UserDefaults.standard.set(second.path(percentEncoded: false), forKey: "libraryFolderPath")
    _ = ArchiveLocation.adoptLegacyLibraryIfNeeded()
    check("a stored legacy path is followed, not just the default name", !exists(second))
    check("and it arrives under the current default name", marker(landed) == "second")

    section("What a library move leaves alone")

    reset()
    let elsewhere = home.appending(path: "Elsewhere/\(legacy)", directoryHint: .isDirectory)
    makeLibrary(at: elsewhere, marker: "deliberate")
    UserDefaults.standard.set(elsewhere.path(percentEncoded: false), forKey: "libraryFolderPath")
    check("a library the owner put somewhere else is not moved",
          ArchiveLocation.adoptLegacyLibraryIfNeeded() == .notNeeded)
    check("and is still there", marker(elsewhere) == "deliberate")

    reset()
    let lookalike = documents.appending(path: "\(legacy) Notes", directoryHint: .isDirectory)
    try? fileManager.createDirectory(at: lookalike, withIntermediateDirectories: true)
    try? Data("mine".utf8).write(to: lookalike.appending(path: "notes.txt"))
    UserDefaults.standard.set(lookalike.path(percentEncoded: false), forKey: "libraryFolderPath")
    check("a folder without an archive file is not ours to move",
          ArchiveLocation.adoptLegacyLibraryIfNeeded() == .notNeeded)
    check("and is untouched", exists(lookalike.appending(path: "notes.txt")))

    reset()
    let file = documents.appending(path: legacy)
    try? Data("not a folder".utf8).write(to: file)
    check("a file wearing the name is not a library",
          ArchiveLocation.adoptLegacyLibraryIfNeeded() == .notNeeded)
    check("and is untouched", exists(file))

    section("When the destination is taken")

    reset()
    let arriving = makeLibrary(at: documents.appending(path: "\(legacy) 2", directoryHint: .isDirectory), marker: "incoming")
    UserDefaults.standard.set(arriving.path(percentEncoded: false), forKey: "libraryFolderPath")
    makeLibrary(at: landed, marker: "already here")
    _ = ArchiveLocation.adoptLegacyLibraryIfNeeded()
    check("nothing already in Application Support is overwritten", marker(landed) == "already here")
    check("the arriving library keeps its own name instead",
          marker(container.appending(path: "\(legacy) 2", directoryHint: .isDirectory)) == "incoming")

    reset()
    let blocked = makeLibrary(at: documents.appending(path: "\(legacy) 2", directoryHint: .isDirectory), marker: "blocked")
    UserDefaults.standard.set(blocked.path(percentEncoded: false), forKey: "libraryFolderPath")
    makeLibrary(at: landed, marker: "a")
    makeLibrary(at: container.appending(path: "\(legacy) 2", directoryHint: .isDirectory), marker: "b")
    if case .failed = ArchiveLocation.adoptLegacyLibraryIfNeeded() {
        check("with both names taken the move is refused", true)
    } else {
        check("with both names taken the move is refused", false)
    }
    check("and the library stays exactly where it was", marker(blocked) == "blocked")
    check("and the app is still pointed at it",
          trimmed(stored ?? "") == trimmed(blocked.path(percentEncoded: false)))

    reset()
}
