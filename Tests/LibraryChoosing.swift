import Foundation

/// Checks the folder of libraries: what counts as one, what may be created,
/// and what a rename is allowed to do.
///
/// Runs against the same stand-in home directory as the location checks, for
/// the same reason: it creates and renames real folders.
func checkLibraryDirectory() async {
    let fileManager = FileManager.default

    guard let stub = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"], !stub.isEmpty else {
        section("The folder of libraries")
        check("run.sh provides a stand-in home directory", false)
        return
    }

    let home = URL(fileURLWithPath: stub, isDirectory: true)
    let support = home.appending(path: "Library/Application Support", directoryHint: .isDirectory)
    let container = support.appending(path: ArchiveLocation.containerName, directoryHint: .isDirectory)
    let directory = LibraryDirectory()

    func reset() {
        try? fileManager.removeItem(at: support)
        try? fileManager.createDirectory(at: container, withIntermediateDirectories: true)
        UserDefaults.standard.removeObject(forKey: "libraryFolderPath")
    }

    /// A library folder with a readable archive in it, so the listing has
    /// something to describe and not merely to count.
    @discardableResult
    func makeLibrary(at url: URL, events: Int) -> URL {
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)

        var archive = Archive()
        archive.patient.fullName = "Test Owner"
        for index in 0..<events {
            archive.upsert(MedicalEvent(date: day(2020, 1, 1), category: .consultation, title: "Visit \(index)"))
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(archive).write(to: url.appending(path: ArchiveLocation.archiveFilename))
        return url
    }

    func exists(_ url: URL) -> Bool { fileManager.fileExists(atPath: url.path(percentEncoded: false)) }

    section("The folder of libraries")

    reset()
    let first = makeLibrary(at: container.appending(path: "Medical Library", directoryHint: .isDirectory), events: 3)
    makeLibrary(at: container.appending(path: "Medical Library 2", directoryHint: .isDirectory), events: 0)

    // A folder with no archive in it is somebody else's folder.
    try? fileManager.createDirectory(at: container.appending(path: "Not A Library", directoryHint: .isDirectory),
                                     withIntermediateDirectories: true)

    var listed = await directory.entries(current: first)
    check("every library in the folder is listed", listed.count == 2)
    check("in name order", listed.map(\.name) == ["Medical Library", "Medical Library 2"])
    check("a folder without an archive is not a library",
          !listed.contains { $0.name == "Not A Library" })
    check("each one says what is in it",
          listed.first?.summary == "Test Owner · 3 records · 0 documents")
    check("an empty one says so too",
          listed.last?.summary == "Test Owner · 0 records · 0 documents")

    // The owner may have put their library somewhere else entirely; the list is
    // useless if the one they are actually in is missing from it.
    let elsewhere = makeLibrary(at: home.appending(path: "Elsewhere/Records", directoryHint: .isDirectory), events: 1)
    listed = await directory.entries(current: elsewhere)
    check("a library outside the folder is listed when it is the open one", listed.count == 3)
    check("and is found by its own path",
          listed.contains { $0.id == LibraryDirectory.identity(of: elsewhere) })

    section("Creating and renaming libraries")

    reset()
    makeLibrary(at: container.appending(path: "Medical Library", directoryHint: .isDirectory), events: 2)

    let created = try? await directory.create(named: "  Second Opinion  ")
    check("a new library is created", created.map(exists) == true)
    check("with the name trimmed", created?.lastPathComponent == "Second Opinion")

    var refused = false
    do { _ = try await directory.create(named: "Medical Library") } catch { refused = true }
    check("a name already in use is refused", refused)

    refused = false
    do { _ = try await directory.create(named: "   ") } catch { refused = true }
    check("an empty name is refused", refused)

    refused = false
    do { _ = try await directory.create(named: ".hidden") } catch { refused = true }
    check("a name that would hide the folder is refused", refused)

    refused = false
    do { _ = try await directory.create(named: "2024/2025") } catch { refused = true }
    check("a name with a path separator is refused", refused)

    let original = container.appending(path: "Medical Library", directoryHint: .isDirectory)
    let renamed = try? await directory.rename(original, to: "Family Archive")
    check("a library can be renamed", renamed?.lastPathComponent == "Family Archive")
    check("the old folder is gone", !exists(original))
    check("and the archive came with it",
          renamed.map { exists($0.appending(path: ArchiveLocation.archiveFilename)) } == true)

    let contents = await directory.entries(current: renamed ?? container)
    check("the listing follows the new name",
          contents.contains { $0.name == "Family Archive" })
    check("and the records are still counted",
          contents.first { $0.name == "Family Archive" }?.eventCount == 2)

    refused = false
    do { _ = try await directory.rename(renamed!, to: "Second Opinion") } catch { refused = true }
    check("renaming onto another library is refused", refused)
    check("and neither of them moved",
          exists(container.appending(path: "Family Archive")) && exists(container.appending(path: "Second Opinion")))

    // Fixing the capitals is a rename, not a collision with itself.
    let recapitalised = try? await directory.rename(
        container.appending(path: "Family Archive", directoryHint: .isDirectory),
        to: "Family archive"
    )
    check("changing only the capitals is allowed", recapitalised?.lastPathComponent == "Family archive")

    reset()
}
