import SwiftUI

/// A working surface, not a scoreboard.
///
/// Counting documents and events tells the owner nothing they can act on — the
/// number goes up and nobody is any wiser. What is worth showing is what has
/// been happening lately, and what has been marked as worth keeping in reach.
struct DashboardView: View {
    @Environment(ArchiveStore.self) private var store
    @Environment(Router.self) private var router

    @State private var previewed: StoredDocument?

    var body: some View {
        let model = DashboardViewModel(archive: store.archive)

        Group {
            if model.hasAnything {
                content(model)
            } else {
                // A page title above an empty screen is a heading for nothing.
                // Every other section shows the empty state alone; so does this.
                emptyArchive
            }
        }
        .background(Palette.page)
        .navigationTitle("Dashboard")
        .sheet(item: $previewed) { document in
            DocumentDetailSheet(documentID: document.id)
        }
    }

    /// Not a statistic: a backlog with an action attached.
    private func inboxBanner(_ count: Int) -> some View {
        Button {
            router.show(.inbox)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "tray.full")
                    .foregroundStyle(Palette.warning)
                Text(count == 1
                     ? "1 document is waiting in your Inbox"
                     : "\(count) documents are waiting in your Inbox")
                    .font(.body.weight(.medium))
                Spacer(minLength: 8)
                Text("Review")
                    .foregroundStyle(Palette.selection)
            }
            .padding(Metrics.cardPadding)
            .background(Palette.warning.opacity(0.06), in: .rect(cornerRadius: Metrics.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .strokeBorder(Palette.warning.opacity(0.25), lineWidth: 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// Deliberately short and deliberately conditional. Vaccinations that are
    /// years away say nothing today, and a dashboard that lists them all turns
    /// into a schedule nobody reads.
    @ViewBuilder
    private func vaccinationsDueSection(_ due: [VaccinationDue]) -> some View {
        if !due.isEmpty {
            section("Vaccinations Due", destination: .vaccinations) {
                ForEach(Array(due.enumerated()), id: \.element.id) { index, entry in
                    GroupedRow(showsDivider: index < due.count - 1) {
                        Button {
                            router.open(event: entry.eventID)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "syringe")
                                    .foregroundStyle(Palette.secondaryText)
                                    .frame(width: 14)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.eventTitle).lineLimit(1)
                                    Text("\(entry.name) · last given \(entry.lastGiven.medium)")
                                        .font(.caption)
                                        .foregroundStyle(Palette.tertiaryText)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 12)

                                BoosterDueLabel(due: entry)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// The cupboard's own reminder, next to the vaccinations one and following
    /// the same rule: only what is expired or nearly so, and never more than a
    /// few lines of it.
    @ViewBuilder
    private func medicinesExpiringSection(_ expiring: [MedicineExpiry]) -> some View {
        if !expiring.isEmpty {
            section("First Aid Kit", destination: .firstAidKit) {
                ForEach(Array(expiring.enumerated()), id: \.element.id) { index, entry in
                    GroupedRow(showsDivider: index < expiring.count - 1) {
                        Button {
                            router.show(.firstAidKit)
                        } label: {
                            MedicineExpiryRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func content(_ model: DashboardViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                PageHeader(title: "Medical Archive", subtitle: model.patientName)

                if !store.integrityIssues.isEmpty {
                    IntegrityBanner(issues: store.integrityIssues)
                }

                if model.inboxCount > 0 {
                    inboxBanner(model.inboxCount)
                }
                vaccinationsDueSection(model.vaccinationsDue)
                medicinesExpiringSection(model.medicinesExpiring)
                pinnedSection(model.pinned)
                recentEventsSection(model.recentEvents)
                recentDocumentsSection(model.recentDocuments)
                recentNotesSection(model.recentNotes)
                importButton.padding(.top, 8)
            }
            .frame(maxWidth: Metrics.readableWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .pageInsets()
        }
    }

    // MARK: - Pinned

    @ViewBuilder
    private func pinnedSection(_ events: [MedicalEvent]) -> some View {
        section("Pinned", isEmpty: events.isEmpty, emptyText: "Pin an operation, a diagnosis or anything you keep looking up.") {
            ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                GroupedRow(showsDivider: index < events.count - 1) {
                    eventRow(event, symbol: "pin.fill")
                }
            }
        }
    }

    // MARK: - Recent events

    @ViewBuilder
    private func recentEventsSection(_ events: [MedicalEvent]) -> some View {
        if !events.isEmpty {
            section("Recent Events", destination: .timeline) {
                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    GroupedRow(showsDivider: index < events.count - 1) {
                        eventRow(event, symbol: nil)
                    }
                }
            }
        }
    }

    private func eventRow(_ event: MedicalEvent, symbol: String?) -> some View {
        Button {
            router.open(event: event.id)
        } label: {
            HStack(spacing: 10) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.caption)
                        .foregroundStyle(Palette.tertiaryText)
                        .frame(width: 14)
                } else {
                    StatusDot(status: event.status)
                        .frame(width: 14)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Image(systemName: event.category.symbol)
                            .imageScale(.small)
                        Text(event.category.title)
                        Text("·")
                        Text(event.date.medium).monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(Palette.tertiaryText)
                }

                Spacer(minLength: 12)

                StatusLabel(status: event.status, forcesLabel: symbol != nil)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Recent documents

    @ViewBuilder
    private func recentDocumentsSection(_ records: [DocumentRecord]) -> some View {
        if !records.isEmpty {
            section("Recent Documents", destination: .documents) {
                ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                    GroupedRow(showsDivider: index < records.count - 1) {
                        documentRow(record)
                    }
                }
            }
        }
    }

    private func documentRow(_ record: DocumentRecord) -> some View {
        Button {
            previewed = record.document
        } label: {
            HStack(spacing: 10) {
                Image(systemName: record.document.kind.symbol)
                    .foregroundStyle(Palette.secondaryText)
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 2) {
                    Text(record.document.originalFilename)
                        .lineLimit(1)
                    Text("Imported \(record.document.importedAt.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(Palette.tertiaryText)
                }

                Spacer(minLength: 12)

                // Whether this file has been made part of the record yet.
                // A document nobody has filed is a loose end, and the dashboard
                // is where a loose end should surface.
                if record.isUsed {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                            .imageScale(.small)
                            .foregroundStyle(Palette.complete)
                        Text(record.events.map(\.title).joined(separator: ", "))
                            .lineLimit(1)
                            .foregroundStyle(Palette.secondaryText)
                    }
                    .font(.caption)
                    .frame(maxWidth: 220, alignment: .trailing)
                } else {
                    Chip(
                        text: record.status.title,
                        tint: record.status == .notProcessed ? Palette.warning : Palette.secondaryText
                    )
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Recent notes

    @ViewBuilder
    private func recentNotesSection(_ records: [NoteRecord]) -> some View {
        if !records.isEmpty {
            section("Recent Notes", destination: .notes) {
                ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                    GroupedRow(showsDivider: index < records.count - 1) {
                        Button {
                            router.open(event: record.event.id)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "text.page")
                                    .foregroundStyle(Palette.secondaryText)
                                    .frame(width: 14)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(record.note.displayTitle)
                                        .lineLimit(1)
                                    Text("\(record.event.title) · \(record.date.medium)")
                                        .font(.caption)
                                        .foregroundStyle(Palette.tertiaryText)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 12)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Scaffolding

    /// A titled group with an optional "Show All" link to the full screen.
    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        destination: SidebarItem? = nil,
        isEmpty: Bool = false,
        emptyText: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            SectionHeader(title: title) {
                if let destination {
                    Button("Show All") { router.show(destination) }
                        .buttonStyle(.link)
                        .font(.subheadline)
                }
            }

            GroupedRows {
                if isEmpty {
                    GroupedRow(showsDivider: false) {
                        Text(emptyText ?? "Nothing yet.")
                            .foregroundStyle(Palette.tertiaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    content()
                }
            }
        }
    }

    private var importButton: some View {
        HStack(spacing: 12) {
            Button {
                router.newRecord()
            } label: {
                Label("New Medical Record", systemImage: "plus")
                    .frame(minWidth: 190)
            }
            .buttonStyle(.borderedProminent)

            Button {
                router.startImport()
            } label: {
                Label("Import Documents", systemImage: "arrow.down.document")
            }
        }
        .controlSize(.extraLarge)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var emptyArchive: some View {
        ArchiveEmptyState(
            title: "Your Archive Is Empty",
            message: "Import a medical document to create the first event in your history.",
            symbol: "cross.case",
            actionTitle: "Import Documents",
            action: { router.startImport() }
        )
    }
}

/// Shown only when a stored original no longer matches what was imported.
/// The one place on this page allowed to raise its voice.
struct IntegrityBanner: View {
    let issues: [IntegrityIssue]

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Palette.critical)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(issues.count) original \(issues.count == 1 ? "file needs" : "files need") attention")
                    .font(.body.weight(.medium))
                Text(issues.prefix(3).map(\.documentName).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(Metrics.cardPadding)
        .background(Palette.critical.opacity(0.06), in: .rect(cornerRadius: Metrics.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(Palette.critical.opacity(0.25), lineWidth: 1)
        }
    }
}
