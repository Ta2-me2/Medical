import SwiftUI

/// One page of results, grouped by what was found.
///
/// Everything leads back to an event, because in this archive everything is
/// part of one.
struct SearchResultsView: View {
    @Environment(ArchiveStore.self) private var store
    @Environment(Router.self) private var router

    let query: String

    var body: some View {
        let results = SearchService.search(query, in: store.archive)

        Group {
            if results.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                        PageHeader(
                            title: "Results",
                            subtitle: "\(results.total) \(results.total == 1 ? "match" : "matches") for “\(query)”"
                        )

                        group("Events", results.events) { event in
                            row(
                                title: event.title,
                                detail: "\(event.category.title) · \(event.date.medium)",
                                symbol: event.category.symbol,
                                status: event.status
                            ) { router.open(event: event.id) }
                        }

                        group("Diagnoses", results.diagnoses) { hit in
                            row(
                                title: hit.diagnosis.name,
                                detail: "\(hit.event.title) · \(hit.event.date.medium)",
                                symbol: "stethoscope",
                                status: hit.event.status
                            ) { router.open(event: hit.event.id) }
                        }

                        group("Medications", results.medications) { hit in
                            row(
                                title: hit.medication.name,
                                detail: "\(hit.event.title) · \(hit.event.date.medium)",
                                symbol: "pills"
                            ) { router.open(event: hit.event.id) }
                        }

                        group("Vaccinations", results.vaccinations) { record in
                            row(
                                title: record.vaccination.name,
                                detail: record.date.medium,
                                symbol: "syringe"
                            ) { router.open(event: record.event.id) }
                        }

                        group("Documents", results.documents) { record in
                            row(
                                title: record.document.displayName,
                                detail: record.usageDescription,
                                symbol: record.document.kind.symbol
                            ) {
                                if let event = record.events.first {
                                    router.open(event: event.id)
                                } else {
                                    router.show(.inbox)
                                }
                            }
                        }

                        group("Notes", results.notes) { record in
                            row(
                                title: record.note.displayTitle,
                                detail: "\(record.event.title) · \(record.date.medium)",
                                symbol: "text.page"
                            ) { router.open(event: record.event.id) }
                        }

                        group("First Aid Kit", results.medicines) { medicine in
                            row(
                                title: medicine.name,
                                detail: [medicine.purpose,
                                         medicine.expiry.map { "use by \($0.formatted)" }]
                                    .compactMap(\.self)
                                    .joined(separator: " · ")
                                    .nilIfEmpty ?? "In your first aid kit",
                                symbol: "cross.case"
                            ) { router.show(.firstAidKit) }
                        }

                        group("Doctors", results.doctors) { doctor in
                            row(
                                title: doctor.name,
                                detail: doctor.specialty?.title ?? "Doctor",
                                symbol: "person.crop.circle"
                            ) { router.show(.timeline) }
                        }

                        group("Hospitals and Clinics", results.facilities) { facility in
                            row(
                                title: facility.name,
                                detail: [facility.kind.title, facility.location].compactMap(\.self).joined(separator: " · "),
                                symbol: "building.2"
                            ) { router.show(.timeline) }
                        }
                    }
                    .frame(maxWidth: Metrics.readableWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .pageInsets()
                }
            }
        }
        .background(Palette.page)
        .navigationTitle("Search")
    }

    @ViewBuilder
    private func group<Item: Identifiable, Row: View>(
        _ title: String,
        _ items: [Item],
        @ViewBuilder row: @escaping (Item) -> Row
    ) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
                SectionHeader(title)
                GroupedRows {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        GroupedRow(showsDivider: index < items.count - 1) {
                            row(item)
                        }
                    }
                }
            }
        }
    }

    private func row(
        title: String,
        detail: String,
        symbol: String,
        status: EventStatus? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: symbol)
                    .foregroundStyle(Palette.secondaryText)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).lineLimit(1)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Palette.tertiaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                // The same colour the event carries on the timeline, so a
                // result found by search is recognisable as the same thing.
                if let status {
                    StatusDot(status: status)
                }
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Palette.tertiaryText)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
