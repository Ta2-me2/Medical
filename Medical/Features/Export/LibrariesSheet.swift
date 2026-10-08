import SwiftUI

/// The list of libraries, and the one that is open.
///
/// A library is a folder, which is the whole point of the format — but a folder
/// in Application Support is not somewhere anyone should have to go with hidden
/// files switched on to change which archive they are looking at. This is that
/// folder, shown as what it holds rather than as a path.
///
/// It is a sheet rather than a section on the Export page: choosing between
/// archives is something done rarely and deliberately, and it should not sit
/// next to the buttons used every visit.
struct LibrariesSheet: View {
    @Environment(ArchiveStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var entries: [LibraryEntry] = []
    @State private var selection: LibraryEntry.ID?
    @State private var prompt: NamePrompt?
    @State private var typedName = ""
    @State private var failure: String?
    @State private var isWorking = false
    @State private var hasLoaded = false

    private let directory = LibraryDirectory()

    /// Naming a new library and renaming an old one ask the same question, so
    /// they share one field rather than two nearly identical sheets.
    private enum NamePrompt: Identifiable {
        case create
        case rename(LibraryEntry)

        var id: String {
            switch self {
            case .create: "create"
            case .rename(let entry): "rename-\(entry.id)"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            list
            Divider()
            footer
        }
        .frame(width: 520, height: 420)
        .background(Palette.page)
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await reload()
        }
        .alert(promptTitle, isPresented: isPrompting) {
            TextField("Name", text: $typedName)
            Button("Cancel", role: .cancel) { prompt = nil }
            Button(promptConfirmation) { confirmPrompt() }
        } message: {
            Text(promptMessage)
        }
        .alert("Something Went Wrong", isPresented: Binding(
            get: { failure != nil },
            set: { if !$0 { failure = nil } }
        )) {
            Button("OK") { failure = nil }
        } message: {
            Text(failure ?? "")
        }
    }

    // MARK: - Chrome

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Libraries")
                .font(.title2.weight(.semibold))
            Text("One archive is open at a time. Opening another leaves this one exactly as it is.")
                .font(.callout)
                .foregroundStyle(Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    private var list: some View {
        List(entries, selection: $selection) { entry in
            row(entry)
        }
        .listStyle(.inset)
        .frame(maxHeight: .infinity)
        // Double-click and right-click go through the List's own primary
        // action. A `TapGesture` on the row would be the obvious way to do it
        // and is the wrong one: it swallows the single click the List needs to
        // move the selection, and the whole list stops answering the mouse.
        .contextMenu(forSelectionType: LibraryEntry.ID.self) { ids in
            if let entry = entry(in: ids) {
                Button("Open") { open(entry) }
                    .disabled(isCurrent(entry))
                Button("Rename…") { beginRenaming(entry) }
                Divider()
                Button("Show in Finder") { reveal(entry) }
            }
        } primaryAction: { ids in
            if let entry = entry(in: ids) { open(entry) }
        }
    }

    private func row(_ entry: LibraryEntry) -> some View {
        let isOpen = isCurrent(entry)

        // Nothing here is painted with the accent colour: the selected row is
        // already accent-coloured, and a blue badge on a blue row is a badge
        // nobody can read. The secondary and tertiary label colours invert
        // themselves on selection; a fixed colour would not.
        return HStack(spacing: 10) {
            Image(systemName: isOpen ? "folder.fill" : "folder")
                .font(.system(size: 15))
                .foregroundStyle(Palette.secondaryText)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(entry.name)
                        .font(.body.weight(isOpen ? .semibold : .regular))
                        .lineLimit(1)
                    if isOpen {
                        Chip(text: "Open")
                    }
                }
                Text(entry.summary)
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if let updated = entry.updatedAt {
                // Labelled, because a bare date beside a folder could be the
                // day it was made as easily as the day it was last written to.
                Text("Updated \(updated.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(Palette.tertiaryText)
            }
        }
        .padding(.vertical, 4)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                typedName = suggestedName
                prompt = .create
            } label: {
                Image(systemName: "plus")
            }
            .help("New Library…")

            Menu {
                Button("Rename…") {
                    if let entry = selectedEntry { beginRenaming(entry) }
                }
                Button("Show in Finder") {
                    if let entry = selectedEntry { reveal(entry) }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(selectedEntry == nil)

            if isWorking {
                ProgressView().controlSize(.small)
            }

            Spacer()

            Button("Done") { dismiss() }

            Button("Open") {
                if let entry = selectedEntry { open(entry) }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(selectedEntry == nil || isCurrent(selectedEntry) || isWorking)
        }
        .controlSize(.large)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Deleting is not here
    //
    // A library is decades of someone's medical history, and a list with a
    // minus button under it invites exactly one kind of accident. "Show in
    // Finder" is the way out: removing an archive should take the deliberate
    // path, through the Trash, where it can be taken back.

    // MARK: - State

    private var selectedEntry: LibraryEntry? {
        entries.first { $0.id == selection }
    }

    private func entry(in ids: Set<LibraryEntry.ID>) -> LibraryEntry? {
        entries.first { ids.contains($0.id) }
    }

    private func isCurrent(_ entry: LibraryEntry?) -> Bool {
        guard let entry else { return false }
        return entry.id == LibraryDirectory.identity(of: store.libraryURL)
    }

    /// "Medical Library 3" — the first number that is free, so the field
    /// opens with a name that will be accepted.
    private var suggestedName: String {
        let taken = Set(entries.map { $0.name.lowercased() })
        let stem = ArchiveLocation.folderName
        if !taken.contains(stem.lowercased()) { return stem }
        var attempt = 2
        while taken.contains("\(stem) \(attempt)".lowercased()) { attempt += 1 }
        return "\(stem) \(attempt)"
    }

    // MARK: - Actions

    private func reload() async {
        entries = await directory.entries(current: store.libraryURL)
        if selection == nil || !entries.contains(where: { $0.id == selection }) {
            selection = LibraryDirectory.identity(of: store.libraryURL)
        }
    }

    private func beginRenaming(_ entry: LibraryEntry) {
        typedName = entry.name
        prompt = .rename(entry)
    }

    private func reveal(_ entry: LibraryEntry) {
        NSWorkspace.shared.activateFileViewerSelecting([entry.url])
    }

    private func open(_ entry: LibraryEntry) {
        guard !isCurrent(entry), !isWorking else { return }
        isWorking = true
        Task {
            await store.relocate(to: entry.url)
            await reload()
            isWorking = false
            dismiss()
        }
    }

    private func confirmPrompt() {
        guard let prompt else { return }
        let name = typedName
        self.prompt = nil
        isWorking = true

        Task {
            do {
                switch prompt {
                case .create:
                    let created = try await directory.create(named: name)
                    // Created and opened in one move: an empty folder the app
                    // has never opened has no archive file in it yet, and would
                    // not appear in this list at all.
                    await store.relocate(to: created)
                    await reload()
                    isWorking = false
                    dismiss()
                    return

                case .rename(let entry):
                    let renamed = try await store.rename(entry.url, to: name, using: directory)
                    await reload()
                    selection = LibraryDirectory.identity(of: renamed)
                }
            } catch {
                failure = error.localizedDescription
            }
            isWorking = false
        }
    }

    // MARK: - The name prompt

    private var isPrompting: Binding<Bool> {
        Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } })
    }

    private var promptTitle: String {
        switch prompt {
        case .rename: "Rename Library"
        default: "New Library"
        }
    }

    private var promptConfirmation: String {
        switch prompt {
        case .rename: "Rename"
        default: "Create"
        }
    }

    private var promptMessage: String {
        switch prompt {
        case .rename:
            "The folder is renamed. Nothing inside it changes."
        default:
            "An empty library is created and opened. The one you are in now stays where it is."
        }
    }
}
