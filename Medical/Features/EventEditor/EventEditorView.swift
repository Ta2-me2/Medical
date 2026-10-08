import SwiftUI
import UniformTypeIdentifiers

/// Creating or editing a medical record.
///
/// A record is written by a person who has the document in front of them, so
/// the document is chosen first and the form comes second. Everything on the
/// form is optional except the title — a record with only a title and a date is
/// still a record, and refusing to save one would mean losing it.
struct EventEditorView: View {
    @Environment(ArchiveStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var model: EventEditorViewModel
    @State private var isChoosingFiles = false
    @State private var isChoosingFromLibrary = false
    @State private var isImporting = false

    init(source: Router.NewRecordSource, archive: Archive) {
        switch source {
        case .chooseSource:
            _model = State(initialValue: EventEditorViewModel())
        case .document(let id):
            let document = archive.document(id: id)
            _model = State(initialValue: EventEditorViewModel(
                documentID: id,
                suggestedTitle: document?.displayName,
                importedAt: document?.importedAt ?? .now
            ))
        case .existing(let id):
            if let event = archive.event(id: id) {
                _model = State(initialValue: EventEditorViewModel(event: event, archive: archive))
            } else {
                _model = State(initialValue: EventEditorViewModel())
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            switch model.stage {
            case .chooseSource: sourceStep
            case .form: formStep
            }

            Divider()

            footer
        }
        .frame(width: 620, height: 660)
        .background(Palette.page)
        .fileImporter(
            isPresented: $isChoosingFiles,
            allowedContentTypes: [.pdf, .image, .tiff, .heic],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { importAndAttach(urls) }
        }
        .sheet(isPresented: $isChoosingFromLibrary) {
            DocumentPickerSheet(
                alreadyAttached: Set(model.attachments.map(\.documentID))
            ) { document in
                model.attach(document.id)
                if model.title.isEmpty {
                    model.title = EventEditorViewModel.tidy(document.displayName)
                }
                model.stage = .form
            }
            .environment(store)
        }
    }

    // MARK: - Chrome

    private var header: some View {
        HStack {
            Text(model.isEditing ? "Edit Medical Record" : "New Medical Record")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if model.stage == .form, !model.isEditing {
                Button("Back") { model.stage = .chooseSource }
            }

            Spacer()

            if isImporting {
                ProgressView().controlSize(.small)
            }

            Button("Cancel", role: .cancel) { dismiss() }

            if model.stage == .form {
                Button(model.isEditing ? "Save" : "Create Record") {
                    model.save(to: store)
                    let id = model.savedEventID(in: store.archive)
                    dismiss()
                    if let id, !model.isEditing { router.open(event: id) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canSave || model.isSaving)
            }
        }
        .controlSize(.large)
        .padding(16)
    }

    // MARK: - Step 1: where the record comes from

    private var sourceStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                StepTitle(
                    "Choose a Document",
                    subtitle: "Anything in your library can be used, including documents other records already cite. Or bring in a new file, or start with none at all."
                )

                let inbox = store.archive.inbox

                if !inbox.isEmpty {
                    SectionHeader("Waiting in Your Inbox")
                    GroupedRows {
                        ForEach(Array(inbox.enumerated()), id: \.element.id) { index, record in
                            GroupedRow(showsDivider: index < inbox.count - 1) {
                                Button {
                                    model.attach(record.document.id)
                                    if model.title.isEmpty {
                                        model.title = EventEditorViewModel.tidy(record.document.displayName)
                                    }
                                    model.date = record.document.importedAt
                                    model.stage = .form
                                } label: {
                                    InboxRowContent(record: record, showsStatus: false)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                SectionHeader(inbox.isEmpty ? "Start From" : "Or")

                VStack(spacing: Metrics.rowSpacing) {
                    Button {
                        isChoosingFromLibrary = true
                    } label: {
                        actionRow(
                            "Choose from Your Library",
                            detail: "Any document you already have, including ones other records use. Pick the pages afterwards.",
                            symbol: "text.document"
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        isChoosingFiles = true
                    } label: {
                        actionRow(
                            "Import a New Document",
                            detail: "The file is copied into the library and attached to this record.",
                            symbol: "arrow.down.document"
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        model.stage = .form
                    } label: {
                        actionRow(
                            "Start Without a Document",
                            detail: "For a visit or a diagnosis that produced no paperwork.",
                            symbol: "square.and.pencil"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
    }

    private func actionRow(_ title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Palette.selection)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .cardSurface()
        .contentShape(.rect)
    }

    // MARK: - Step 2: the record itself

    private var formStep: some View {
        Form {
            Section {
                TextField("Title", text: $model.title, prompt: Text("What this record is"))

                DatePicker("Date", selection: $model.date, displayedComponents: .date)

                Picker("Known Precision", selection: $model.precision) {
                    ForEach(DateValue.Precision.allCases) { precision in
                        Text(precision.title).tag(precision)
                    }
                }

                Picker("Category", selection: $model.category) {
                    ForEach(EventCategory.allCases) { category in
                        Label(category.title, systemImage: category.symbol).tag(category)
                    }
                }

                Picker("Specialty", selection: $model.specialty) {
                    Text("Not specified").tag(Specialty?.none)
                    Divider()
                    ForEach(Specialty.allCases) { specialty in
                        Text(specialty.title).tag(Specialty?.some(specialty))
                    }
                }

                StatusPicker(status: $model.status)
            }

            Section {
                TextField("Doctor", text: $model.doctorName, prompt: Text("Name of doctor"))
                TextField("Clinic", text: $model.clinicName, prompt: Text("Name of clinic or hospital"))
                Picker("Clinic Type", selection: $model.clinicKind) {
                    ForEach(Facility.Kind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
            }

            Section("Summary") {
                TextEditor(text: $model.summary)
                    .frame(height: 80)
                    .font(.body)
            }

            Section {
                TextField("Tags", text: $model.tagsText, prompt: Text("Comma-separated"))
            } footer: {
                Text("Separate tags with commas.")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
            }

            Section {
                TextEditor(text: $model.noteBody)
                    .frame(height: 70)
                    .font(.body)
            } header: {
                Text(model.existingNoteCount > 0 ? "Add Another Note" : "Note")
            } footer: {
                if model.existingNoteCount > 0 {
                    Text("This record already has \(model.existingNoteCount) \(model.existingNoteCount == 1 ? "note" : "notes"). Existing notes are edited on the record itself.")
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                }
            }

            Section {
                if model.vaccinations.isEmpty {
                    Text("No doses recorded.")
                        .foregroundStyle(Palette.tertiaryText)
                }

                ForEach(Array(model.vaccinations.indices), id: \.self) { index in
                    vaccinationRow(index: index)
                }

                Button("Add Vaccination") { model.addVaccination() }
            } header: {
                Text("Vaccinations")
            } footer: {
                Text("Recording when a dose needs repeating is what puts it on the dashboard later. The interval counts from this dose, so a booster given early or late moves everything after it.")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
            }

            Section {
                if model.attachments.isEmpty {
                    Text("No documents attached.")
                        .foregroundStyle(Palette.tertiaryText)
                }

                ForEach(model.attachments) { reference in
                    if let document = store.archive.document(id: reference.documentID) {
                        attachmentRow(reference: reference, document: document)
                    }
                }

                HStack(spacing: 12) {
                    Button("Attach from Library…") { isChoosingFromLibrary = true }
                    Button("Import a File…") { isChoosingFiles = true }
                }
            } header: {
                Text("Source Documents")
            } footer: {
                Text("Leave pages empty for the whole document, or name the pages this record is about — 15-17, 42-43, 58. The file itself is never split.")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
            }

            if let failure = model.failure {
                Section {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Palette.critical)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// One cited document, with the pages this record draws from it.
    ///
    /// The page field is the whole reason a ninety-page childhood card can be
    /// left in one piece: several records point at the same file, each naming
    /// its own pages.
    private func attachmentRow(reference: DocumentReference, document: StoredDocument) -> some View {
        let text = model.pageText(for: reference)
        let isValid = model.pageTextIsValid(text)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: document.kind.symbol)
                    .foregroundStyle(Palette.secondaryText)
                VStack(alignment: .leading, spacing: 1) {
                    Text(document.displayName).lineLimit(1)
                    Text([document.fileExtension, document.formattedPageCount, document.formattedSize]
                        .compactMap(\.self).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(Palette.tertiaryText)
                }
                Spacer(minLength: 8)
                Button {
                    model.detach(referenceID: reference.id)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(Palette.tertiaryText)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                Text("Pages")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)

                TextField(
                    "",
                    text: Binding(
                        get: { model.pageText(for: reference) },
                        set: { model.setPageText($0, for: reference.id) }
                    ),
                    prompt: Text("All pages")
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)

                if !isValid {
                    Label("Not a page range", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Palette.warning)
                } else if !reference.pages.isWholeDocument, let count = reference.pages.pageCount {
                    Text("\(count) \(count == 1 ? "page" : "pages") selected")
                        .font(.caption)
                        .foregroundStyle(Palette.tertiaryText)
                }
            }
        }
    }

    /// One dose, with when it needs repeating.
    private func vaccinationRow(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("", text: binding(index: index, \.name), prompt: Text("Vaccine"))
                    .textFieldStyle(.roundedBorder)
                Button {
                    model.removeVaccination(id: model.vaccinations[index].id)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(Palette.tertiaryText)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                TextField("", text: optionalBinding(index: index, \.manufacturer), prompt: Text("Manufacturer"))
                    .textFieldStyle(.roundedBorder)
                TextField("", text: optionalBinding(index: index, \.dose), prompt: Text("Dose"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                TextField("", text: optionalBinding(index: index, \.batchNumber), prompt: Text("Batch"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)
            }

            BoosterField(schedule: boosterBinding(index: index))
        }
        .padding(.vertical, 2)
    }

    private func binding(index: Int, _ keyPath: WritableKeyPath<Vaccination, String>) -> Binding<String> {
        Binding(
            get: { model.vaccinations.indices.contains(index) ? model.vaccinations[index][keyPath: keyPath] : "" },
            set: { if model.vaccinations.indices.contains(index) { model.vaccinations[index][keyPath: keyPath] = $0 } }
        )
    }

    private func optionalBinding(index: Int, _ keyPath: WritableKeyPath<Vaccination, String?>) -> Binding<String> {
        Binding(
            get: { model.vaccinations.indices.contains(index) ? (model.vaccinations[index][keyPath: keyPath] ?? "") : "" },
            set: {
                if model.vaccinations.indices.contains(index) {
                    model.vaccinations[index][keyPath: keyPath] = $0.nilIfEmpty
                }
            }
        )
    }

    private func boosterBinding(index: Int) -> Binding<BoosterSchedule?> {
        Binding(
            get: { model.vaccinations.indices.contains(index) ? model.vaccinations[index].booster : nil },
            set: { if model.vaccinations.indices.contains(index) { model.vaccinations[index].booster = $0 } }
        )
    }

    // MARK: - Importing from inside the editor

    private func importAndAttach(_ urls: [URL]) {
        isImporting = true
        let year = model.dateValue.year

        Task {
            defer { isImporting = false }
            do {
                var stored: [StoredDocument] = []
                for url in urls {
                    stored.append(try await store.storeOriginal(from: url, year: year, title: nil))
                }
                store.update { $0.addDocuments(stored) }
                for document in stored { model.attach(document.id) }
                if model.title.isEmpty, let first = stored.first {
                    model.title = EventEditorViewModel.tidy(first.originalFilename)
                }
                model.stage = .form
            } catch {
                model.failure = error.localizedDescription
            }
        }
    }
}
