import SwiftUI

/// The cupboard at home, laid out as shelves.
///
/// Everywhere else in this application the subject is something that happened;
/// here it is something a person owns and can walk over and pick up. So it is
/// tiles with stickers rather than rows with dates, grouped by what each thing
/// is for rather than by when it was bought — because the question this page
/// gets asked is never "what did I buy in March", it is "have I got anything
/// for a temperature".
struct FirstAidKitView: View {
    @Environment(ArchiveStore.self) private var store

    @State private var editing: MedicineEditing?
    @State private var reading: Medicine?
    @State private var isShowingRecommendations = false

    /// `.sheet(item:)` needs an identity, and "a new medicine, on this shelf"
    /// is a different sheet from "a new medicine, on no shelf".
    private enum MedicineEditing: Identifiable {
        case new(MedicineKind?)
        case existing(Medicine)

        var id: String {
            switch self {
            case .new(let kind): "new-\(kind?.rawValue ?? "any")"
            case .existing(let medicine): medicine.id.uuidString
            }
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 236, maximum: 340), spacing: Metrics.rowSpacing)]

    var body: some View {
        Group {
            if store.archive.firstAidKit.isEmpty {
                empty
            } else {
                content
            }
        }
        .background(Palette.page)
        .navigationTitle("First Aid Kit")
        .toolbar { toolbar }
        .sheet(item: $editing) { editing in
            switch editing {
            case .new(let kind):
                MedicineEditor(kind: kind).environment(store)
            case .existing(let medicine):
                MedicineEditor(medicine: medicine).environment(store)
            }
        }
        .sheet(item: $reading) { medicine in
            MedicineInstructionsSheet(medicine: medicine) {
                reading = nil
                editing = .existing(medicine)
            }
            .environment(store)
        }
        .sheet(isPresented: $isShowingRecommendations) {
            RecommendationsSheet { kind in
                isShowingRecommendations = false
                editing = .new(kind)
            }
            .environment(store)
        }
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                PageHeader(title: "First Aid Kit", subtitle: subtitle)

                missing
                expiring
                shelves
            }
            .frame(maxWidth: Metrics.readableWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .pageInsets()
        }
    }

    private var subtitle: String {
        let count = store.archive.medicineCount
        var parts = ["\(count) \(count == 1 ? "medicine" : "medicines")"]

        let expiring = store.archive.medicinesExpiring().count
        if expiring > 0 { parts.append("\(expiring) needing attention") }

        return parts.joined(separator: " · ")
    }

    /// The gaps, at the top, the way vaccinations that are due sit at the top of
    /// theirs. Each one can be set aside from here without opening anything —
    /// the whole point of the panel is that it is glanced at, not managed.
    @ViewBuilder
    private var missing: some View {
        let gaps = store.archive.missingMedicineKinds
        if !gaps.isEmpty {
            VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
                SectionHeader(title: "Missing from Your Kit") {
                    Button("Recommendations") { isShowingRecommendations = true }
                        .buttonStyle(.link)
                        .font(.subheadline)
                }

                GroupedRows {
                    ForEach(Array(gaps.enumerated()), id: \.element.id) { index, kind in
                        GroupedRow(showsDivider: index < gaps.count - 1) {
                            HStack(spacing: 10) {
                                MedicineKindRow(kind: kind)

                                Button("Add") { editing = .new(kind) }
                                    .buttonStyle(.link)

                                Button {
                                    store.update { $0.setHidden(true, forKind: kind) }
                                } label: {
                                    Image(systemName: "xmark")
                                        .imageScale(.small)
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(Palette.tertiaryText)
                                .help("Set aside — you can bring it back under Recommendations")
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var expiring: some View {
        let expiring = store.archive.medicinesExpiring()
        if !expiring.isEmpty {
            VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
                SectionHeader("Running Out of Time")

                GroupedRows {
                    ForEach(Array(expiring.enumerated()), id: \.element.id) { index, entry in
                        GroupedRow(showsDivider: index < expiring.count - 1) {
                            Button {
                                if let medicine = store.archive.medicine(id: entry.medicineID) {
                                    editing = .existing(medicine)
                                }
                            } label: {
                                MedicineExpiryRow(entry: entry)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    /// One shelf per direction, and one at the end for whatever has not been
    /// filed. A medicine that covers two directions stands on both shelves,
    /// which is the truth about it rather than a duplicate.
    @ViewBuilder
    private var shelves: some View {
        ForEach(store.archive.stockedMedicineKinds) { kind in
            shelf(
                title: kind.title,
                emoji: kind.suggestedEmoji,
                medicines: store.archive.medicines(of: kind),
                kind: kind
            )
        }

        let unsorted = store.archive.unsortedMedicines
        if !unsorted.isEmpty {
            shelf(title: "Not Filed Yet", emoji: "📦", medicines: unsorted, kind: nil)
        }
    }

    private func shelf(
        title: String,
        emoji: String,
        medicines: [Medicine],
        kind: MedicineKind?
    ) -> some View {
        VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            SectionHeader(title: "\(emoji)  \(title)") {
                Text("\(medicines.count)")
                    .font(.caption)
                    .foregroundStyle(Palette.tertiaryText)
                    .monospacedDigit()
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: Metrics.rowSpacing) {
                ForEach(medicines) { medicine in
                    MedicineTile(
                        medicine: medicine,
                        expiry: expiry(for: medicine),
                        onOpen: { editing = .existing(medicine) },
                        onInstructions: { reading = medicine }
                    )
                    .contextMenu {
                        if medicine.hasInstructions {
                            Button("Instructions…") { reading = medicine }
                        }
                        Button("Edit…") { editing = .existing(medicine) }
                        Divider()
                        Button("Remove from Kit", role: .destructive) {
                            store.update { $0.removeMedicine(id: medicine.id) }
                        }
                    }
                }
            }
        }
    }

    private func expiry(for medicine: Medicine) -> MedicineExpiry? {
        store.archive.medicinesExpiring().first { $0.medicineID == medicine.id }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(id: "kit.recommendations") {
            Button {
                isShowingRecommendations = true
            } label: {
                Label("Recommendations", systemImage: "checklist")
            }
            .help("What a home kit usually covers, and what you have set aside")
        }

        ToolbarItem(id: "kit.add") {
            Button {
                editing = .new(nil)
            } label: {
                Label("Add Medicine", systemImage: "plus")
            }
        }
    }

    // MARK: - Empty

    private var empty: some View {
        ArchiveEmptyState(
            title: "Nothing in the Kit Yet",
            message: "Add what is actually in the cupboard at home — a name, the date on the packet, and the leaflet if you want to keep it. The recommendations will tell you what a kit usually covers.",
            symbol: "cross.case",
            actionTitle: "Add Medicine",
            action: { editing = .new(nil) }
        )
    }
}

/// A medicine that is expired or close to it, as one line.
struct MedicineExpiryRow: View {
    let entry: MedicineExpiry

    var body: some View {
        HStack(spacing: 10) {
            Text(entry.emoji)
                .font(.system(size: 17))
                .frame(width: 24)

            Text(entry.name)
                .lineLimit(1)

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                Image(systemName: entry.isExpired() ? "exclamationmark.circle.fill" : "clock")
                    .imageScale(.small)
                Text(entry.description())
                Text("·")
                Text(entry.expiresOn.formatted(.dateTime.month(.abbreviated).year()))
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(entry.isExpired() ? Palette.critical : Palette.warning)
        }
        .contentShape(.rect)
    }
}
