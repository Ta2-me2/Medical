import SwiftUI

/// Every dose ever given — grouped by the vaccine it was a dose of.
///
/// A vaccination record gets asked two questions. "What have I had against
/// this, and when was the last one" is the common one, and a single
/// chronological thread answered it by making the reader do the grouping in
/// their head, scrolling twenty years to collect three doses. So the doses are
/// gathered per vaccine by default, and the thread is one click away for the
/// times the question really is about a date.
struct VaccinationsView: View {
    @Environment(ArchiveStore.self) private var store
    @Environment(Router.self) private var router

    @State private var model = VaccinationsViewModel()

    var body: some View {
        let series = store.archive.vaccinationSeries
        let shown = model.filtered(series)

        Group {
            if series.isEmpty {
                empty
            } else if shown.isEmpty {
                filteredToNothing
            } else {
                content(all: series, shown: shown)
            }
        }
        .background(Palette.page)
        .navigationTitle("Vaccinations")
        .toolbar { toolbar(options: model.options(from: series)) }
    }

    // MARK: - Content

    /// Lazy all the way down.
    ///
    /// A plain `VStack` builds and lays out every card the moment the page
    /// opens, visible or not. A lifetime of doses is hundreds of cards, each
    /// with a grid inside, and laying all of them out at once was nearly three
    /// seconds on a thousand-record archive — and then as long again to tear
    /// down on the way out. A lazy stack builds what is on screen. For that to
    /// work the series have to be its direct children, which is why `byVaccine`
    /// hands back a `ForEach` rather than wrapping one in a stack of its own.
    private func content(all: [VaccinationSeries], shown: [VaccinationSeries]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                PageHeader(title: "Vaccinations", subtitle: subtitle(all: all, shown: shown))

                upcoming

                switch model.grouping {
                case .vaccine:
                    byVaccine(shown)
                case .date:
                    thread(model.chronological(shown), headedByVaccine: false)
                }
            }
            .frame(maxWidth: Metrics.readableWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .pageInsets()
        }
    }

    private func subtitle(all: [VaccinationSeries], shown: [VaccinationSeries]) -> String {
        let doses = shown.reduce(0) { $0 + $1.doseCount }
        let total = all.reduce(0) { $0 + $1.doseCount }

        if model.isFiltered {
            return "\(doses) of \(total) \(total == 1 ? "dose" : "doses")"
        }
        let vaccines = all.count
        return "\(doses) \(doses == 1 ? "dose" : "doses") · \(vaccines) \(vaccines == 1 ? "vaccine" : "vaccines")"
    }

    /// Only what still needs doing. A vaccine with no repeat, or one whose next
    /// dose is a decade away, has nothing to say here.
    ///
    /// Narrowed by the same filter as the list below it. A page that says it is
    /// showing one vaccine, and then reminds you about another, is telling the
    /// reader two things at once.
    @ViewBuilder
    private var upcoming: some View {
        let due = store.archive.vaccinationsDue().filter {
            model.vaccines.allows(VaccineOption(key: $0.seriesKey, name: $0.eventTitle))
        }
        if !due.isEmpty {
            VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
                SectionHeader("Next Doses")
                GroupedRows {
                    ForEach(Array(due.enumerated()), id: \.element.id) { index, entry in
                        GroupedRow(showsDivider: index < due.count - 1) {
                            Button {
                                router.open(event: entry.eventID)
                            } label: {
                                HStack(spacing: 10) {
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
            .padding(.bottom, 4)
        }
    }

    // MARK: - By vaccine

    private func byVaccine(_ series: [VaccinationSeries]) -> some View {
        // No stack of its own: the series sit directly in the page's lazy
        // stack, which spaces them exactly as the stack here used to.
        ForEach(series) { entry in
            VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
                seriesHeader(entry)
                // Inside a group the title is already overhead, so each card
                // leads with the product instead — which is the one thing
                // that tells three doses of the same course apart.
                thread(entry.records, headedByVaccine: true)
            }
        }
    }

    private func seriesHeader(_ series: VaccinationSeries) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(series.name)
                .font(.title3.weight(.semibold))

            Spacer(minLength: 12)

            Text(span(of: series))
                .font(.caption)
                .foregroundStyle(Palette.tertiaryText)
                .monospacedDigit()
        }
    }

    /// "3 doses · 2011–2024". One dose says so without pretending to a range.
    private func span(of series: VaccinationSeries) -> String {
        let count = "\(series.doseCount) \(series.doseCount == 1 ? "dose" : "doses")"
        guard let newest = series.latest, let oldest = series.earliest else { return count }

        let last = newest.date.year
        let first = oldest.date.year
        return first == last ? "\(count) · \(last)" : "\(count) · \(first)–\(last)"
    }

    // MARK: - The thread

    /// Doses on a vertical line, newest at the top. Used for one vaccine's
    /// doses and for the whole archive alike — the shape means the same thing
    /// in both places.
    private func thread(_ records: [VaccinationRecord], headedByVaccine: Bool) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                row(record, isLast: index == records.count - 1, headedByVaccine: headedByVaccine)
            }
        }
    }

    private func row(_ record: VaccinationRecord, isLast: Bool, headedByVaccine: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            // The rail: a dot for the dose, a line continuing to the next one.
            VStack(spacing: 0) {
                Circle()
                    .strokeBorder(Palette.selection, lineWidth: 2)
                    .frame(width: 9, height: 9)
                    .padding(.top, 16)
                if !isLast {
                    Rectangle()
                        .fill(Palette.separator)
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 9)

            VStack(alignment: .leading, spacing: 0) {
                Text(record.date.formatted)
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
                    .monospacedDigit()
                    .padding(.bottom, 5)

                Button {
                    router.open(event: record.event.id)
                } label: {
                    VaccinationCard(
                        vaccination: record.vaccination,
                        heading: heading(for: record, headedByVaccine: headedByVaccine),
                        date: record.date
                    )
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }
            .padding(.bottom, isLast ? 0 : 16)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// A dose with no vaccine name recorded falls back to the record's title
    /// rather than showing a card with no heading at all.
    private func heading(for record: VaccinationRecord, headedByVaccine: Bool) -> String {
        guard headedByVaccine, let name = record.vaccination.name.nilIfEmpty else {
            return record.event.title
        }
        return name
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func toolbar(options: [VaccineOption]) -> some ToolbarContent {
        ToolbarItem(id: "vaccinations.grouping") {
            Picker("Group", selection: $model.grouping) {
                // Written out, not two icons: a list glyph beside a calendar
                // glyph is a guess, and this control changes what the whole
                // page is.
                ForEach(VaccinationsViewModel.Grouping.allCases) { grouping in
                    Text(grouping.title).tag(grouping)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("Group doses by vaccine, or list them by date")
        }

        ToolbarItem(id: "vaccinations.filter") {
            Menu {
                FilterSection(
                    title: "Vaccines",
                    options: options,
                    label: \.name,
                    filter: $model.vaccines
                )
            } label: {
                FilterMenuLabel(isFiltering: model.isFiltered)
            }
            .menuIndicator(.hidden)
            .disabled(options.count < 2)
        }
    }

    // MARK: - Empty states

    private var empty: some View {
        ArchiveEmptyState(
            title: "No Vaccinations",
            message: "Import a vaccination certificate and choose the Vaccination category to record a dose here.",
            symbol: "syringe",
            actionTitle: "New Medical Record",
            action: { router.newRecord() }
        )
    }

    private var filteredToNothing: some View {
        ArchiveEmptyState(
            title: "Nothing Matches This Filter",
            message: "You have vaccinations recorded, but none of the vaccines you are showing.",
            symbol: "line.3.horizontal.decrease.circle",
            actionTitle: "Show Everything",
            action: { model.clearFilter() }
        )
    }
}
