import SwiftUI

/// Everything recorded about one event, in the order a person reads it:
/// what happened, what was found, what was prescribed, what was filed.
struct EventDetailView: View {
    @Environment(ArchiveStore.self) private var store
    @Environment(Router.self) private var router

    let eventID: UUID

    @State private var isAddingNote = false
    @State private var noteDraft = ""
    @State private var isConfirmingDelete = false
    @State private var previewedDocument: StoredDocument?
    @State private var editedTable: ResultTable?
    @State private var editedTableIsNew = false
    @State private var deletedTable: (eventID: UUID, table: ResultTable)?
    @State private var editedNote: Note?
    @State private var deletedNote: (eventID: UUID, note: Note)?

    var body: some View {
        Group {
            if let event = store.archive.event(id: eventID) {
                content(for: event)
            } else {
                ContentUnavailableView(
                    "Event Not Found",
                    systemImage: "questionmark.folder",
                    description: Text("It may have been deleted from the archive.")
                )
            }
        }
        .background(Palette.page)
        .navigationTitle(store.archive.event(id: eventID)?.title ?? "Event")
    }

    private func content(for event: MedicalEvent) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                header(event)
                summary(event)
                translations(event)
                diagnoses(event)
                medications(event)
                vaccinations(event)
                results(event)
                documents(event)
                notes(event)
                tags(event)
            }
            .frame(maxWidth: Metrics.readableWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .pageInsets()
        }
        .toolbar {
            ToolbarItem(id: "event.status") {
                Menu {
                    StatusPicker(status: Binding(
                        get: { event.status },
                        set: { newStatus in
                            store.update { $0.setStatus(newStatus, forEvent: event.id) }
                        }
                    ))
                    .pickerStyle(.inline)
                } label: {
                    Label {
                        Text("Status")
                    } icon: {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(event.status.color)
                    }
                }
                .menuIndicator(.hidden)
            }

            ToolbarItem(id: "event.pin") {
                Button {
                    store.update { $0.setPinned(!event.isPinned, forEvent: event.id) }
                } label: {
                    Label(
                        event.isPinned ? "Unpin" : "Pin",
                        systemImage: event.isPinned ? "pin.fill" : "pin"
                    )
                }
            }

            ToolbarItem(id: "event.edit") {
                Button {
                    router.edit(eventID: event.id)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }

            ToolbarItem(id: "event.addNote") {
                Button {
                    noteDraft = ""
                    isAddingNote = true
                } label: {
                    Label("Add Note", systemImage: "square.and.pencil")
                }
            }
            ToolbarItem(id: "event.delete") {
                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Label("Delete Record", systemImage: "trash")
                }
            }
        }
        .sheet(isPresented: $isAddingNote) {
            NoteComposer(title: "New Note", text: $noteDraft) {
                addNote(to: event)
            }
        }
        .sheet(item: $editedNote) { note in
            NoteEditor(note: note) { updated in
                store.update { archive in
                    guard let index = archive.events.firstIndex(where: { $0.id == event.id }),
                          let noteIndex = archive.events[index].notes.firstIndex(where: { $0.id == note.id })
                    else { return }
                    archive.events[index].notes[noteIndex] = updated
                    archive.events[index].updatedAt = .now
                }
            }
        }
        .sheet(item: $previewedDocument) { document in
            DocumentDetailSheet(documentID: document.id)
        }
        .sheet(item: $editedTable) { table in
            ResultTableEditor(table: table) { saved in
                store.update { archive in
                    guard let index = archive.events.firstIndex(where: { $0.id == event.id }) else { return }
                    if let existing = archive.events[index].tables.firstIndex(where: { $0.id == saved.id }) {
                        archive.events[index].tables[existing] = saved
                    } else {
                        archive.events[index].tables.append(saved)
                    }
                    archive.events[index].updatedAt = .now
                }
            }
        }
        .confirmationDialog(
            "Delete this table?",
            isPresented: Binding(get: { deletedTable != nil }, set: { if !$0 { deletedTable = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Table", role: .destructive) {
                if let pending = deletedTable {
                    store.update { archive in
                        guard let index = archive.events.firstIndex(where: { $0.id == pending.eventID })
                        else { return }
                        archive.events[index].tables.removeAll { $0.id == pending.table.id }
                        archive.events[index].updatedAt = .now
                    }
                }
                deletedTable = nil
            }
            Button("Cancel", role: .cancel) { deletedTable = nil }
        } message: {
            Text("“\(deletedTable?.table.displayTitle ?? "")” and everything typed into it will be removed from this record.")
        }
        .confirmationDialog(
            "Delete this note?",
            isPresented: Binding(get: { deletedNote != nil }, set: { if !$0 { deletedNote = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Note", role: .destructive) {
                if let pending = deletedNote {
                    store.update { archive in
                        guard let index = archive.events.firstIndex(where: { $0.id == pending.eventID })
                        else { return }
                        archive.events[index].notes.removeAll { $0.id == pending.note.id }
                        archive.events[index].updatedAt = .now
                    }
                }
                deletedNote = nil
            }
            Button("Cancel", role: .cancel) { deletedNote = nil }
        }
        .confirmationDialog(
            "Delete this event?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Event", role: .destructive) {
                store.deleteEvent(id: event.id)
                router.path.removeLast()
            }
        } message: {
            Text("The record and its notes will be removed. Its documents stay in the library and return to the Inbox unless another record uses them — nothing is deleted from disk.")
        }
    }

    // MARK: - Sections

    private func header(_ event: MedicalEvent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                CategoryLabel(category: event.category)
                if let specialty = event.specialty {
                    Text("·").foregroundStyle(Palette.tertiaryText)
                    Text(specialty.title)
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                }
                Spacer(minLength: 12)
                StatusLabel(status: event.status, forcesLabel: true)
            }

            Text(event.title)
                .font(.largeTitle.weight(.semibold))

            HStack(spacing: 8) {
                Text(event.dateRangeDescription)
                if let attribution = store.archive.attribution(for: event) {
                    Text("·").foregroundStyle(Palette.tertiaryText)
                    Text(attribution)
                }
            }
            .font(.callout)
            .foregroundStyle(Palette.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func summary(_ event: MedicalEvent) -> some View {
        if let text = event.summary.nilIfEmpty {
            Text(text)
                .font(.body)
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func translations(_ event: MedicalEvent) -> some View {
        if !event.translations.isEmpty {
            section("Translations") {
                GroupedRows {
                    let keys = event.translations.keys.sorted()
                    ForEach(Array(keys.enumerated()), id: \.element) { index, code in
                        GroupedRow(showsDivider: index < keys.count - 1) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(Locale.current.localizedString(forLanguageCode: code)?.capitalized ?? code.uppercased())
                                    .font(.caption)
                                    .foregroundStyle(Palette.secondaryText)
                                Text(event.translations[code] ?? "")
                                    .textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func diagnoses(_ event: MedicalEvent) -> some View {
        if !event.diagnoses.isEmpty {
            section("Diagnoses") {
                GroupedRows {
                    ForEach(Array(event.diagnoses.enumerated()), id: \.element.id) { index, diagnosis in
                        GroupedRow(showsDivider: index < event.diagnoses.count - 1) {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(diagnosis.name)
                                    if let code = diagnosis.code {
                                        Text(code)
                                            .font(.caption.monospaced())
                                            .foregroundStyle(Palette.tertiaryText)
                                    }
                                }
                                Spacer(minLength: 12)
                                Chip(text: diagnosis.status.title, tint: diagnosis.status.color)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func medications(_ event: MedicalEvent) -> some View {
        if !event.medications.isEmpty {
            section("Medications") {
                GroupedRows {
                    ForEach(Array(event.medications.enumerated()), id: \.element.id) { index, medication in
                        GroupedRow(showsDivider: index < event.medications.count - 1) {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(medication.name)
                                    if !medication.summary.isEmpty {
                                        Text(medication.summary)
                                            .font(.caption)
                                            .foregroundStyle(Palette.secondaryText)
                                    }
                                }
                                Spacer(minLength: 12)
                                if medication.isOngoing {
                                    Chip(text: "Ongoing", tint: Palette.complete)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func vaccinations(_ event: MedicalEvent) -> some View {
        if !event.vaccinations.isEmpty {
            section("Vaccinations") {
                VStack(spacing: Metrics.rowSpacing) {
                    ForEach(event.vaccinations) { vaccination in
                        VaccinationCard(
                            vaccination: vaccination,
                            heading: vaccination.name,
                            date: event.date
                        )
                    }
                }
            }
        }
    }

    /// The tables the owner has typed out. The reason this record is worth
    /// handing to anyone.
    @ViewBuilder
    private func results(_ event: MedicalEvent) -> some View {
        VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            SectionHeader(title: "Results") {
                Button("Add Table") {
                    editedTable = ResultTable()
                    editedTableIsNew = true
                }
                .buttonStyle(.link)
                .font(.subheadline)
            }

            if event.tables.isEmpty {
                GroupedRows {
                    GroupedRow(showsDivider: false) {
                        Text("Type the numbers from the document here, in English — this is what a doctor will read.")
                            .foregroundStyle(Palette.tertiaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                    ForEach(event.tables) { table in
                        ResultTableView(table: table) {
                            editedTable = table
                            editedTableIsNew = false
                        } onDelete: {
                            deletedTable = (event.id, table)
                        }
                        .contextMenu {
                            Button("Edit Table…") {
                                editedTable = table
                                editedTableIsNew = false
                            }
                            Button("Delete Table…", role: .destructive) {
                                deletedTable = (event.id, table)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func documents(_ event: MedicalEvent) -> some View {
        let attached = store.archive.attachments(for: event)
        if !attached.isEmpty {
            section("Source Documents") {
                GroupedRows {
                    ForEach(Array(attached.enumerated()), id: \.element.id) { index, attachment in
                        GroupedRow(showsDivider: index < attached.count - 1) {
                            Button {
                                previewedDocument = attachment.document
                            } label: {
                                // The pages this record uses, and whether other
                                // records use the same file, so detaching is
                                // never a surprise.
                                DocumentRow(
                                    document: attachment.document,
                                    pages: attachment.reference.pages,
                                    usage: sharedUsage(of: attachment.document, excluding: event)
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Detach from This Record") {
                                    store.update { $0.detach(referenceID: attachment.reference.id, from: event.id) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// `also in 2 other records`, or nothing when this is the only one.
    private func sharedUsage(of document: StoredDocument, excluding event: MedicalEvent) -> String? {
        let others = store.archive.events(using: document.id).filter { $0.id != event.id }
        guard !others.isEmpty else { return nil }
        return "also in \(others.count) other \(others.count == 1 ? "record" : "records")"
    }

    @ViewBuilder
    private func notes(_ event: MedicalEvent) -> some View {
        if !event.notes.isEmpty {
            section("Notes") {
                VStack(spacing: Metrics.rowSpacing) {
                    ForEach(event.notes) { note in
                        NoteCard(note: note) {
                            editedNote = note
                        } onDelete: {
                            deletedNote = (event.id, note)
                        }
                        .contextMenu {
                            Button("Edit Note…") { editedNote = note }
                            Button("Delete Note…", role: .destructive) {
                                deletedNote = (event.id, note)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func tags(_ event: MedicalEvent) -> some View {
        let eventTags = store.archive.tags(ids: event.tagIDs)
        if !eventTags.isEmpty {
            section("Tags") {
                HStack(spacing: 6) {
                    ForEach(eventTags) { tag in
                        Chip(text: tag.name)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            SectionHeader(title)
            content()
        }
    }

    // MARK: - Actions

    private func addNote(to event: MedicalEvent) {
        guard let body = noteDraft.nilIfEmpty else { return }
        store.update { archive in
            guard let index = archive.events.firstIndex(where: { $0.id == event.id }) else { return }
            archive.events[index].notes.append(Note(body: body))
            archive.events[index].updatedAt = .now
        }
        noteDraft = ""
    }
}

/// A note card with its own controls.
///
/// The same reasoning as the result tables: an entry the owner typed must be
/// visibly changeable, or they will assume it is not.
struct NoteCard: View {
    let note: Note
    var onEdit: () -> Void
    var onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(note.displayTitle)
                    .font(.headline)
                    .textSelection(.enabled)

                Spacer(minLength: 8)

                Button("Edit", action: onEdit)
                    .buttonStyle(.link)
                    .font(.subheadline)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .imageScale(.small)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.tertiaryText)
                .help("Delete this note")
            }
            .opacity(isHovering ? 1 : 0.55)
            .animation(.easeOut(duration: 0.12), value: isHovering)

            if let rest = note.previewBelowTitle {
                Text(rest)
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryText)
                    .textSelection(.enabled)
            }

            Text(stamp)
                .font(.caption)
                .foregroundStyle(Palette.tertiaryText)
        }
        .cardSurface()
        .onHover { isHovering = $0 }
    }

    /// Says when it was last touched once that stops being when it was written.
    private var stamp: String {
        let written = note.createdAt.formatted(date: .abbreviated, time: .shortened)
        guard note.updatedAt.timeIntervalSince(note.createdAt) > 60 else { return written }
        return "\(written) · edited \(note.updatedAt.formatted(date: .abbreviated, time: .shortened))"
    }
}

/// Writing a note. Plain text on purpose — rich text is one more format to
/// still be able to open in thirty years.
struct NoteComposer: View {
    @Environment(\.dismiss) private var dismiss

    var title: String = "New Note"
    @Binding var text: String
    var onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.headline)

            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 200)
                .background(Palette.card, in: .rect(cornerRadius: Metrics.smallRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Metrics.smallRadius, style: .continuous)
                        .strokeBorder(Palette.separator, lineWidth: 1)
                }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") {
                    onSave()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(text.nilIfEmpty == nil)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

/// Editing an existing note. Works on a copy, so an abandoned edit changes
/// nothing, and stamps `updatedAt` only when the text actually differs.
struct NoteEditor: View {
    @Environment(\.dismiss) private var dismiss

    let note: Note
    var onSave: (Note) -> Void

    @State private var text: String

    init(note: Note, onSave: @escaping (Note) -> Void) {
        self.note = note
        self.onSave = onSave
        _text = State(initialValue: note.body)
    }

    var body: some View {
        NoteComposer(title: "Edit Note", text: $text) {
            guard let body = text.nilIfEmpty, body != note.body else { return }
            var updated = note
            updated.body = body
            updated.updatedAt = .now
            onSave(updated)
        }
    }
}
