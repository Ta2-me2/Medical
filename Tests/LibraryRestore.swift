import Foundation

/// Checks the round trip a library makes between two Macs: export to a zip,
/// restore from it, and end up with something indistinguishable from a library
/// that had been created here all along.
func checkLibraryRestore() async {
    let fileManager = FileManager.default

    guard let stub = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"], !stub.isEmpty else {
        section("Restoring a backup")
        check("run.sh provides a stand-in home directory", false)
        return
    }

    let home = URL(fileURLWithPath: stub, isDirectory: true)
    let support = home.appending(path: "Library/Application Support", directoryHint: .isDirectory)
    let container = support.appending(path: ArchiveLocation.containerName, directoryHint: .isDirectory)
    let desk = home.appending(path: "Desk", directoryHint: .isDirectory)

    func reset() {
        try? fileManager.removeItem(at: support)
        try? fileManager.removeItem(at: desk)
        try? fileManager.createDirectory(at: container, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: desk, withIntermediateDirectories: true)
    }

    func exists(_ url: URL) -> Bool { fileManager.fileExists(atPath: url.path(percentEncoded: false)) }

    /// A library with an original in it, so a restore can be checked for
    /// bringing the documents and not just the archive file.
    @discardableResult
    func makeLibrary(at url: URL, named owner: String) -> URL {
        try? fileManager.createDirectory(
            at: url.appending(path: "Originals/2019", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        try? Data("scan bytes".utf8).write(to: url.appending(path: "Originals/2019/report.pdf"))

        var archive = Archive()
        archive.patient.fullName = owner
        archive.upsert(MedicalEvent(date: day(2019, 4, 2), category: .laboratory, title: "Blood count"))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(archive).write(to: url.appending(path: ArchiveLocation.archiveFilename))
        return url
    }

    section("Restoring a backup")

    reset()
    let source = makeLibrary(at: container.appending(path: "Family Archive", directoryHint: .isDirectory),
                             named: "Anna Petrova")
    let backup = desk.appending(path: "Family Archive 2026-08-31.zip")

    do {
        try LibraryBackup.export(from: source, to: backup)
        check("a library exports to a single zip", exists(backup))
    } catch {
        check("a library exports to a single zip", false)
        return
    }

    // The second Mac: the same folder of libraries, without this one in it.
    try? fileManager.removeItem(at: source)

    guard let restored = try? LibraryBackup.restore(from: backup, into: container) else {
        check("the backup restores", false)
        return
    }

    check("the backup restores", exists(restored))
    check("directly into the folder of libraries",
          LibraryDirectory.identity(of: restored.deletingLastPathComponent())
            == LibraryDirectory.identity(of: container))
    check("under the name the library had", restored.lastPathComponent == "Family Archive")
    check("with the archive at its top level, not one folder down",
          exists(restored.appending(path: ArchiveLocation.archiveFilename)))
    check("and there is no extra folder wrapped around it",
          !exists(restored.appending(path: "Family Archive")))
    check("the originals came across",
          (try? String(contentsOf: restored.appending(path: "Originals/2019/report.pdf"), encoding: .utf8)) == "scan bytes")
    check("the records came across", LibraryBackup.inspect(restored)?.eventCount == 1)
    check("and so did whose they are", LibraryBackup.inspect(restored)?.patientName == "Anna Petrova")

    // The whole point of the shape: the list must find it afterwards.
    let directory = LibraryDirectory()
    let listed = await directory.entries(current: restored)
    check("the restored library is listed like any other",
          listed.filter { $0.name == "Family Archive" }.count == 1)
    check("and nothing else was left in the folder", listed.count == 1)

    // Restoring the same backup again must not touch the first copy.
    guard let second = try? LibraryBackup.restore(from: backup, into: container) else {
        check("restoring the same backup twice is allowed", false)
        return
    }
    check("restoring the same backup twice is allowed", exists(second))
    check("the second copy is numbered, not merged", second.lastPathComponent == "Family Archive 2")
    check("and the first is still there", exists(restored.appending(path: ArchiveLocation.archiveFilename)))

    let both = await directory.entries(current: restored)
    check("both are listed", both.map(\.name) == ["Family Archive", "Family Archive 2"])

    section("A backup that is not one")

    reset()
    let notALibrary = desk.appending(path: "Holiday Photos", directoryHint: .isDirectory)
    try? fileManager.createDirectory(at: notALibrary, withIntermediateDirectories: true)
    try? Data("jpeg".utf8).write(to: notALibrary.appending(path: "beach.jpg"))
    let wrongZip = desk.appending(path: "Holiday Photos.zip")
    try? Zip.compress(folder: notALibrary, to: wrongZip)

    var refused = false
    do { _ = try LibraryBackup.restore(from: wrongZip, into: container) } catch { refused = true }
    check("a zip with no archive in it is refused", refused)

    let leftovers = (try? fileManager.contentsOfDirectory(atPath: container.path(percentEncoded: false))) ?? []
    check("and nothing is left behind in the folder of libraries", leftovers.isEmpty)

    section("Opening up a library left too deep")

    reset()

    // What an early restore produced: the wrapper the zip unpacked into, with
    // the library one level inside it. The names are the ones that were on disk
    // at the time, from before the application was renamed — which is the point:
    // the repair has to recognise folders it did not make today.
    let wrapper = container.appending(path: "Medical ID Library 2026-08-30", directoryHint: .isDirectory)
    makeLibrary(at: wrapper.appending(path: "Medical ID Library", directoryHint: .isDirectory), named: "Anna Petrova")
    UserDefaults.standard.set(
        wrapper.appending(path: "Medical ID Library").path(percentEncoded: false),
        forKey: "libraryFolderPath"
    )

    var flattened = ArchiveLocation.flattenNestedLibraries()
    check("the library is lifted out of its wrapper", flattened.count == 1)
    check("into the folder of libraries, under its own name",
          flattened.first?.lastPathComponent == "Medical ID Library")
    check("the wrapper is gone", !exists(wrapper))
    check("the archive came with it",
          flattened.first.map { exists($0.appending(path: ArchiveLocation.archiveFilename)) } == true)
    check("the originals came with it",
          flattened.first.map { exists($0.appending(path: "Originals/2019/report.pdf")) } == true)
    check("and the app follows it",
          UserDefaults.standard.string(forKey: "libraryFolderPath").map {
              LibraryDirectory.identity(of: URL(fileURLWithPath: $0))
          } == flattened.first.map(LibraryDirectory.identity(of:)))
    check("running again finds nothing to do", ArchiveLocation.flattenNestedLibraries().isEmpty)

    let visible = await LibraryDirectory().entries(current: flattened[0])
    check("and it is listed like any other library", visible.map(\.name) == ["Medical ID Library"])

    // A folder somebody arranged themselves is not a wrapper.
    reset()
    let shelf = container.appending(path: "Old Macs", directoryHint: .isDirectory)
    makeLibrary(at: shelf.appending(path: "Mum", directoryHint: .isDirectory), named: "Mum")
    makeLibrary(at: shelf.appending(path: "Dad", directoryHint: .isDirectory), named: "Dad")
    flattened = ArchiveLocation.flattenNestedLibraries()
    check("a folder holding two libraries is left alone", flattened.isEmpty)
    check("and both are still in it",
          exists(shelf.appending(path: "Mum")) && exists(shelf.appending(path: "Dad")))

    reset()
    let mixed = container.appending(path: "Backups", directoryHint: .isDirectory)
    makeLibrary(at: mixed.appending(path: "From 2019", directoryHint: .isDirectory), named: "Anna")
    try? Data("notes".utf8).write(to: mixed.appending(path: "read me.txt"))
    check("a folder holding a library and something else is left alone",
          ArchiveLocation.flattenNestedLibraries().isEmpty)
    check("and keeps both", exists(mixed.appending(path: "read me.txt")))

    reset()
    UserDefaults.standard.removeObject(forKey: "libraryFolderPath")
}
