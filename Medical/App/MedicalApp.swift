import SwiftUI

@main
struct MedicalApp: App {

    @State private var store: ArchiveStore
    @State private var router = Router()
    @State private var settings = AppSettings()

    /// The library is put where it belongs before anything is allowed to read
    /// it, so the store is built pointing at the folder it actually ended up
    /// in rather than at one that moved out from under it a moment later.
    init() {
        // Order matters: every path below is built from the application's own
        // folder, so that folder settles on its name first.
        ArchiveLocation.adoptRenamedContainerIfNeeded()
        let move = ArchiveLocation.adoptLegacyLibraryIfNeeded()
        ArchiveLocation.flattenNestedLibraries()
        _store = State(initialValue: ArchiveStore(libraryMove: move))
    }


    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(router)
                .environment(settings)
                .frame(
                    minWidth: Metrics.windowMinWidth,
                    minHeight: Metrics.windowMinHeight
                )
                // Applied here as well as in `init`, because AppKit does not
                // reliably keep a Dock icon set before the app finished
                // launching.
                .task { settings.apply() }
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1180, height: 760)
        .commands {
            ArchiveCommands(store: store, router: router)
        }

        Window(AboutWindow.title, id: AboutWindow.id) {
            AboutView()
                .environment(settings)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .defaultPosition(.center)
        .restorationBehavior(.disabled)
    }
}

/// Menu bar commands.
///
/// Everything that would have gone in a Settings window lives here instead:
/// the library is a folder, and the things you do to it are actions, not
/// preferences.
struct ArchiveCommands: Commands {
    let store: ArchiveStore
    let router: Router

    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Medical") { openWindow(id: AboutWindow.id) }
        }

        CommandGroup(replacing: .newItem) {
            Button("New Medical Record…") { router.newRecord() }
                .keyboardShortcut("n", modifiers: .command)

            Button("Import Documents…") { router.startImport() }
                .keyboardShortcut("i", modifiers: .command)

            Button("Export…") { router.show(.export) }
                .keyboardShortcut("e", modifiers: [.command, .shift])
        }

        CommandMenu("Archive") {
            Button("Save Now") {
                Task { await store.saveNow() }
            }
            .keyboardShortcut("s", modifiers: .command)

            Divider()

            Button("Verify Integrity…") {
                router.show(.dashboard)
                Task { await store.verifyIntegrity() }
            }

            Button("Reveal Library in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([store.libraryURL])
            }

            Button("Libraries…") { router.chooseLibrary() }
        }
    }
}
