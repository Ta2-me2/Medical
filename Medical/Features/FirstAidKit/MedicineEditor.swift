import SwiftUI

/// Adding a box to the cupboard, or correcting one already in it.
///
/// Everything the kit knows is on one screen. There is no wizard here because
/// there is no decision to walk somebody through: a medicine is a name, a date
/// printed on the packet, and — if the owner wants it — the leaflet.
struct MedicineEditor: View {
    @Environment(ArchiveStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let existing: Medicine?

    @State private var draft: Medicine
    @State private var hasExpiry: Bool
    @State private var expiryDate: Date
    @State private var precision: DateValue.Precision

    @State private var isChoosingFiles = false
    @State private var isChoosingFromLibrary = false
    @State private var isImporting = false
    @State private var isConfirmingDelete = false
    @State private var failure: String?

    init(medicine: Medicine? = nil, kind: MedicineKind? = nil) {
        existing = medicine

        var seed = medicine ?? Medicine(name: "")
        if medicine == nil, let kind {
            // Added from an empty shelf: the shelf it was added from is the
            // answer to "what is it for", and asking again would be rude.
            seed.kinds = [kind]
        }
        _draft = State(initialValue: seed)

        _hasExpiry = State(initialValue: medicine?.expiry != nil)
        _expiryDate = State(initialValue: medicine?.expiry?.date ?? .now)
        // Packets are printed by month far more often than by day.
        _precision = State(initialValue: medicine?.expiry?.precision ?? .month)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            form
            Divider()
            footer
        }
        .frame(width: 580, height: 650)
        .background(Palette.page)
        .fileImporter(
            isPresented: $isChoosingFiles,
            allowedContentTypes: [.pdf, .image, .tiff, .heic],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { importAndAttach(urls) }
        }
        .sheet(isPresented: $isChoosingFromLibrary) {
            DocumentPickerSheet(alreadyAttached: Set(draft.attachments.map(\.documentID))) { document in
                attach(document.id)
            }
            .environment(store)
        }
        .confirmationDialog(
            "Remove “\(draft.name.nilIfEmpty ?? "this medicine")” from the kit?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let existing { store.update { $0.removeMedicine(id: existing.id) } }
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The leaflet stays in your library. Only the entry in the first aid kit is removed.")
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
        HStack {
            Text(existing == nil ? "Add to First Aid Kit" : "Edit Medicine")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if existing != nil {
                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }

            Spacer()

            if isImporting { ProgressView().controlSize(.small) }

            Button("Cancel", role: .cancel) { dismiss() }

            Button(existing == nil ? "Add" : "Save") { save() }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.name.nilIfEmpty == nil)
        }
        .controlSize(.large)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Form

    private var form: some View {
        Form {
            Section {
                TextField("Name", text: $draft.name, prompt: Text("What is on the packet"))

                TextField(
                    "What it is for",
                    text: Binding(get: { draft.purpose ?? "" }, set: { draft.purpose = $0.nilIfEmpty }),
                    prompt: Text("Fever and pain")
                )

                TextField(
                    "How much is left",
                    text: Binding(get: { draft.quantity ?? "" }, set: { draft.quantity = $0.nilIfEmpty }),
                    prompt: Text("12 tablets")
                )
            }

            Section("Sticker") {
                stickerPicker
            }

            Section("Expiry") {
                Toggle("The packet has a date on it", isOn: $hasExpiry)

                if hasExpiry {
                    DatePicker("Use by", selection: $expiryDate, displayedComponents: .date)

                    Picker("Printed as", selection: $precision) {
                        ForEach(DateValue.Precision.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }

                    // Said out loud because it is the difference between a box
                    // that reads as expired and one that still has a month in it.
                    if precision != .day {
                        Text("A packet dated by month is good to the end of it.")
                            .font(.caption)
                            .foregroundStyle(Palette.tertiaryText)
                    }
                }
            }

            Section {
                kindPicker
            } header: {
                Text("What it covers")
            } footer: {
                Text("Used by the recommendations, so the kit can tell you what is missing. A painkiller that also brings a temperature down covers both.")
                    .font(.caption)
                    .foregroundStyle(Palette.tertiaryText)
            }

            Section("Instructions") {
                TextEditor(text: Binding(
                    get: { draft.instructions ?? "" },
                    set: { draft.instructions = $0.nilIfEmpty }
                ))
                .frame(minHeight: 90)
                .font(.body)

                attachments
            }
        }
        .formStyle(.grouped)
    }

    /// The emoji is shown, not named. Twenty-four of them is a cupboard's worth;
    /// anything else can be typed or pasted into the field beside them.
    private var stickerPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text(draft.displayEmoji)
                    .font(.system(size: 26))
                    .frame(width: 48, height: 48)
                    .background(Palette.subtleFill, in: .rect(cornerRadius: Metrics.smallRadius, style: .continuous))

                TextField(
                    "Sticker",
                    text: Binding(
                        get: { draft.emoji ?? "" },
                        // One character: this is a sticker, not a caption.
                        set: { draft.emoji = String($0.prefix(2)).nilIfEmpty }
                    ),
                    prompt: Text("Any emoji")
                )
                .frame(width: 110)

                Spacer(minLength: 0)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 34), spacing: 6)], spacing: 6) {
                ForEach(MedicineKind.stickerPalette, id: \.self) { option in
                    Button {
                        draft.emoji = option
                    } label: {
                        Text(option)
                            .font(.system(size: 18))
                            .frame(width: 32, height: 32)
                            .background {
                                RoundedRectangle(cornerRadius: Metrics.smallRadius, style: .continuous)
                                    .fill(draft.emoji == option ? Palette.selection.opacity(0.15) : .clear)
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: Metrics.smallRadius, style: .continuous)
                                    .strokeBorder(
                                        draft.emoji == option ? Palette.selection : .clear,
                                        lineWidth: 1.5
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var kindPicker: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(MedicineKind.allCases) { kind in
                let isOn = draft.kinds.contains(kind)
                Button {
                    if isOn {
                        draft.kinds.removeAll { $0 == kind }
                    } else {
                        draft.kinds.append(kind)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                            .imageScale(.small)
                            .foregroundStyle(isOn ? Palette.selection : Palette.tertiaryText)
                        Text(kind.title)
                            .font(.callout)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background {
                        RoundedRectangle(cornerRadius: Metrics.smallRadius, style: .continuous)
                            .fill(isOn ? Palette.selection.opacity(0.1) : Palette.subtleFill.opacity(0.5))
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var attachments: some View {
        let resolved = store.archive.attachments(for: draft)

        if resolved.isEmpty {
            Text("No leaflet attached.")
                .font(.caption)
                .foregroundStyle(Palette.tertiaryText)
        } else {
            ForEach(resolved) { attached in
                HStack(spacing: 8) {
                    Image(systemName: attached.document.kind.symbol)
                        .foregroundStyle(Palette.secondaryText)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(attached.document.displayName).lineLimit(1)
                        Text([attached.document.fileExtension,
                              attached.document.formattedPageCount,
                              attached.document.formattedSize]
                            .compactMap(\.self)
                            .joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(Palette.tertiaryText)
                    }

                    Spacer(minLength: 12)

                    Button(role: .destructive) {
                        draft.attachments.removeAll { $0.id == attached.reference.id }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }

        HStack(spacing: 10) {
            Button("Attach a File…") { isChoosingFiles = true }
            Button("From Library…") { isChoosingFromLibrary = true }
        }
    }

    // MARK: - Actions

    private func attach(_ documentID: UUID) {
        guard !draft.attachments.contains(where: { $0.documentID == documentID }) else { return }
        draft.attachments.append(DocumentReference(documentID: documentID))
    }

    private func importAndAttach(_ urls: [URL]) {
        isImporting = true
        Task {
            do {
                var stored: [StoredDocument] = []
                for url in urls {
                    // Filed under the year it arrived: a leaflet has no medical
                    // date of its own, and inventing one would put it in the
                    // Originals folder for a year nothing happened in.
                    let year = Calendar.current.component(.year, from: .now)
                    stored.append(try await store.storeOriginal(from: url, year: year, title: nil))
                }
                store.update { $0.addDocuments(stored) }
                for document in stored { attach(document.id) }
            } catch {
                failure = error.localizedDescription
            }
            isImporting = false
        }
    }

    private func save() {
        var medicine = draft
        medicine.name = medicine.name.trimmingCharacters(in: .whitespacesAndNewlines)
        medicine.expiry = hasExpiry ? DateValue(expiryDate, precision: precision) : nil
        store.update { $0.upsert(medicine) }
        dismiss()
    }
}
