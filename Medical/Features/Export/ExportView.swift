import SwiftUI
import UniformTypeIdentifiers

/// Two things leave this archive, and they are not variations of each other.
///
/// A **Doctor Report** is for a person: the history, the numbers in English, and
/// the pages the records actually cite. A **Library backup** is for a machine:
/// every byte, unchanged, so another Mac can carry on where this one stopped.
/// Offering eight file formats instead was offering the reader a decision that
/// was never theirs to make.
struct ExportView: View {
    @Environment(ArchiveStore.self) private var store
    @Environment(Router.self) private var router

    @State private var request = DoctorReportRequest()
    @State private var isWorking = false
    @State private var outcome: Outcome?
    @State private var isChoosingLibrary = false

    private enum Outcome: Identifiable {
        case wrote(URL, String)
        case restored(String)
        case failed(String)

        var id: String {
            switch self {
            case .wrote(let url, _): "wrote-\(url.path())"
            case .restored(let message): "restored-\(message)"
            case .failed(let message): "failed-\(message)"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                PageHeader(
                    title: "Export",
                    subtitle: "Hand your history to a doctor, or move it to another Mac."
                )

                doctorReportSection
                librarySection
            }
            .frame(maxWidth: Metrics.readableWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .pageInsets()
        }
        .background(Palette.page)
        .navigationTitle("Export")
        .sheet(isPresented: $isChoosingLibrary) {
            LibrariesSheet()
                .environment(store)
        }
        .onChange(of: router.pendingLibraries) { _, isPending in
            if isPending {
                router.pendingLibraries = false
                isChoosingLibrary = true
            }
        }
        .onAppear {
            if router.pendingLibraries {
                router.pendingLibraries = false
                isChoosingLibrary = true
            }
        }
        .alert(item: alertItem) { outcome in
            switch outcome {
            case .wrote(let url, let message):
                Alert(
                    title: Text("Ready"),
                    message: Text(message),
                    primaryButton: .default(Text("Show in Finder")) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    },
                    secondaryButton: .cancel(Text("Done"))
                )
            case .restored(let message):
                Alert(title: Text("Library Restored"), message: Text(message), dismissButton: .default(Text("OK")))
            case .failed(let message):
                Alert(title: Text("Export Failed"), message: Text(message), dismissButton: .default(Text("OK")))
            }
        }
    }

    // MARK: - Doctor Report

    private var doctorReportSection: some View {
        VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            SectionHeader("For a Doctor")

            VStack(alignment: .leading, spacing: 14) {
                Text("A single package: your history as a readable report, the result tables you have written in English, and the exact pages your records refer to.")
                    .foregroundStyle(Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                GroupedRows {
                    GroupedRow {
                        Picker("Include", selection: $request.scope) {
                            ForEach(DoctorReportRequest.Scope.allCases) { scope in
                                Text(scope.title).tag(scope)
                            }
                        }
                    }

                    if request.scope == .category {
                        GroupedRow {
                            Picker("Category", selection: $request.category) {
                                ForEach(EventCategory.allCases) { Text($0.title).tag($0) }
                            }
                        }
                    }

                    if request.scope == .dateRange {
                        GroupedRow {
                            DatePicker("From", selection: $request.from, displayedComponents: .date)
                        }
                        GroupedRow {
                            DatePicker("To", selection: $request.to, displayedComponents: .date)
                        }
                    }

                    GroupedRow(showsDivider: false) {
                        HStack {
                            Text("Records")
                                .foregroundStyle(Palette.secondaryText)
                            Spacer(minLength: 12)
                            Text(matchingEvents.isEmpty
                                 ? "Nothing matches"
                                 : "\(matchingEvents.count) selected")
                                .foregroundStyle(Palette.secondaryText)
                                .monospacedDigit()
                        }
                    }
                }

                sections

                HStack(spacing: 12) {
                    Button {
                        exportDoctorReport()
                    } label: {
                        Label("Doctor Report", systemImage: "square.and.arrow.up")
                            .frame(minWidth: 180)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.extraLarge)
                    .disabled(isWorking || matchingEvents.isEmpty)

                    if isWorking {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .cardSurface()
        }
    }

    /// The report's own table of contents, before it is written.
    ///
    /// Only the sections that would actually be printed appear here, so what
    /// the owner unticks is exactly what the report would otherwise have
    /// contained. Nothing is ever lost by unticking: a table switched off puts
    /// its records back into "Records in Full", which is where they came from.
    @ViewBuilder
    private var sections: some View {
        let parts = DoctorReport(libraryURL: store.libraryURL).parts(archive: store.archive, request: request)

        if !parts.isEmpty {
            VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
                Text("Sections")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.secondaryText)

                GroupedRows {
                    ForEach(Array(parts.enumerated()), id: \.element.id) { index, part in
                        GroupedRow(showsDivider: index < parts.count - 1) {
                            Toggle(isOn: Binding(
                                get: { self.request.includes(part.section) },
                                set: { self.request.setInclusion($0, of: part.section) }
                            )) {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(part.section.title)
                                        Text(part.section.explanation)
                                            .font(.caption)
                                            .foregroundStyle(Palette.tertiaryText)
                                    }
                                    Spacer(minLength: 12)
                                    Text(part.detail)
                                        .font(.caption)
                                        .foregroundStyle(Palette.tertiaryText)
                                        .monospacedDigit()
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Library

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            SectionHeader("Your Library")

            VStack(alignment: .leading, spacing: 14) {
                Text("Everything, byte for byte: the archive file, every original, every snapshot. This is what you keep, and what you restore from on another Mac.")
                    .foregroundStyle(Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                GroupedRows {
                    GroupedRow {
                        HStack(spacing: 8) {
                            Text("Location").foregroundStyle(Palette.secondaryText)
                            Spacer(minLength: 12)
                            Text(store.libraryURL.path(percentEncoded: false))
                                .font(.caption)
                                .foregroundStyle(Palette.tertiaryText)
                                .lineLimit(1)
                                .truncationMode(.head)
                                .textSelection(.enabled)
                            // Application Support is hidden in Finder, so the
                            // path alone is not a way to reach the folder.
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([store.libraryURL])
                            } label: {
                                Image(systemName: "arrow.up.forward.square")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(Palette.selection)
                            .help("Show in Finder")
                        }
                    }
                    GroupedRow(showsDivider: false) {
                        HStack {
                            Text("Contents").foregroundStyle(Palette.secondaryText)
                            Spacer(minLength: 12)
                            Text("\(store.archive.eventCount) records · \(store.archive.documentCount) documents")
                                .foregroundStyle(Palette.secondaryText)
                                .monospacedDigit()
                        }
                    }
                }

                if let notice = libraryMoveNotice {
                    Label(notice, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(Palette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 12) {
                    Button {
                        exportLibrary()
                    } label: {
                        Label("Export Library…", systemImage: "externaldrive")
                    }
                    .disabled(isWorking)

                    Button {
                        chooseBackupToRestore()
                    } label: {
                        Label("Restore from Backup…", systemImage: "arrow.down.document")
                    }
                    .disabled(isWorking)

                    Spacer()

                    Button {
                        isChoosingLibrary = true
                    } label: {
                        Label("Libraries…", systemImage: "books.vertical")
                    }
                    .disabled(isWorking)
                }
                .controlSize(.large)
            }
            .cardSurface()
        }
    }

    // MARK: - Derived

    /// One alert, two sources. The page's own outcome covers everything that
    /// leaves the archive alone; the store's announcement covers restoring,
    /// which reloads the archive and rebuilds this page on the way. Two `alert`
    /// modifiers on one view is one alert too many for SwiftUI to show.
    private var alertItem: Binding<Outcome?> {
        Binding(
            get: { outcome ?? store.announcement.map { .restored($0) } },
            set: { newValue in
                guard newValue == nil else { return }
                outcome = nil
                store.announcement = nil
            }
        )
    }

    /// Said out loud only when the library was meant to move into Application
    /// Support at launch and did not. Silence would let the owner believe their
    /// records had left Documents — and left iCloud — when they had not.
    private var libraryMoveNotice: String? {
        switch store.libraryMove {
        case .notNeeded, .moved:
            return nil
        case .waitingForDownload:
            return "This library is still being downloaded from iCloud. Medical will move it out of Documents once every file is on this Mac."
        case .failed(_, let reason):
            return "Medical could not move this library out of Documents: \(reason) It is still where it was, and still works."
        }
    }

    /// "50 records · Chronology, All Vaccinations, Source Documents".
    private var writtenSummary: String {
        let names = DoctorReport(libraryURL: store.libraryURL)
            .parts(archive: store.archive, request: request)
            .filter { request.includes($0.section) }
            .map(\.section.title)

        let count = matchingEvents.count
        let records = "\(count) record\(count == 1 ? "" : "s")"
        return names.isEmpty ? records : "\(records) · \(names.joined(separator: ", "))"
    }

    private var matchingEvents: [MedicalEvent] {
        store.archive.eventsNewestFirst.filter(request.matches)
    }

    private var backupFilename: String {
        let stamp = DateValue.calendarString(from: .now)
        return "\(store.libraryURL.lastPathComponent) \(stamp).zip"
    }

    // MARK: - Actions

    /// Ask first, write second. See `SavePanel`.
    private func exportDoctorReport() {
        guard let url = SavePanel.destination(
            suggestedName: request.suggestedFilename,
            contentType: .zip
        ) else { return }
        writeReport(to: url)
    }

    private func exportLibrary() {
        guard let url = SavePanel.destination(
            suggestedName: backupFilename,
            contentType: .zip
        ) else { return }
        writeBackup(to: url)
    }

    private func chooseBackupToRestore() {
        guard let url = SavePanel.fileToOpen(contentType: .zip) else { return }
        restore(from: url)
    }

    private func writeReport(to url: URL) {
        let archive = store.archive
        let report = DoctorReport(libraryURL: store.libraryURL)
        let request = request
        perform {
            try await Task.detached(priority: .userInitiated) {
                try report.write(archive, request: request, to: url)
            }.value
            return .wrote(url, "\(url.lastPathComponent) — \(writtenSummary).")
        }
    }

    private func writeBackup(to url: URL) {
        let library = store.libraryURL
        perform {
            await store.saveNow()
            try await Task.detached(priority: .userInitiated) {
                try LibraryBackup.export(from: library, to: url)
            }.value
            return .wrote(url, "Your whole library is in \(url.lastPathComponent).")
        }
    }

    private func restore(from backup: URL) {
        let previous = store.libraryURL.lastPathComponent
        isWorking = true
        Task {
            do {
                let restored = try await Task.detached(priority: .userInitiated) {
                    // Into the folder of libraries, not beside whichever one
                    // happens to be open — a restored library belongs with the
                    // others, or the list will not find it again.
                    try LibraryBackup.restore(from: backup, into: ArchiveLocation.container)
                }.value

                let contents = LibraryBackup.inspect(restored).map { " — \($0.description)" } ?? ""
                await store.relocate(to: restored)

                // Said afterwards, not before: relocating rebuilds this page,
                // and an alert whose reason to appear predates the page it
                // appears on does not appear at all.
                store.announcement = "“\(restored.lastPathComponent)” is now open\(contents). “\(previous)” is untouched, and both are in Libraries."
            } catch {
                outcome = .failed(error.localizedDescription)
            }
            isWorking = false
        }
    }

    /// Runs a piece of work off the main actor and reports whatever happens.
    private func perform(_ work: @escaping () async throws -> Outcome) {
        isWorking = true
        Task {
            do {
                outcome = try await work()
            } catch {
                outcome = .failed(error.localizedDescription)
            }
            isWorking = false
        }
    }
}

