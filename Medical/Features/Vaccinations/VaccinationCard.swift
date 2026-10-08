import SwiftUI

/// One dose, with the details that matter if it ever has to be proved.
///
/// The heading is the record it belongs to, not the vaccine, because that is
/// what the owner named and what tells them apart. Vaccine names repeat — two
/// records can both say "Pneumococcal" — and a list headed by them says nothing
/// about which is which. The vaccine goes in the table with the batch, where a
/// clinician looks for it anyway.
struct VaccinationCard: View {
    let vaccination: Vaccination

    /// What this dose is called here. The record's title on the vaccinations
    /// page; the vaccine's own name on the record page, where the title is
    /// already the heading of the page itself.
    let heading: String

    let date: DateValue
    var showsDate: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(heading)
                    .font(.headline)
                Spacer(minLength: 8)
                if showsDate {
                    Text(date.medium)
                        .font(.caption)
                        .foregroundStyle(Palette.tertiaryText)
                        .monospacedDigit()
                }
            }

            let facts = details
            if !facts.isEmpty {
                // A fixed-column grid so batch numbers line up down the page and
                // can be compared at a glance. Every value is labelled: a bare
                // "2" beside a vaccine name is not a dose, it is a riddle.
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                    ForEach(facts, id: \.label) { fact in
                        GridRow {
                            Text(fact.label)
                                .foregroundStyle(Palette.secondaryText)
                                .gridColumnAlignment(.leading)
                            Text(fact.value)
                                .textSelection(.enabled)
                        }
                    }
                }
                .font(.caption)
            }

            if let repeats = vaccination.booster?.description {
                HStack(spacing: 5) {
                    Image(systemName: "clock")
                        .imageScale(.small)
                    Text(repeats)
                }
                .font(.caption)
                .foregroundStyle(Palette.secondaryText)
            }

            if let notes = vaccination.notes {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
            }
        }
        .cardSurface()
    }

    private var details: [(label: String, value: String)] {
        var rows: [(String, String)] = []

        // Only when the heading is not already the vaccine's name.
        if vaccination.name.caseInsensitiveCompare(heading) != .orderedSame,
           let name = vaccination.name.nilIfEmpty {
            rows.append(("Vaccine", name))
        }

        if let dose = vaccination.dose { rows.append(("Dose", dose)) }
        if let manufacturer = vaccination.manufacturer { rows.append(("Manufacturer", manufacturer)) }
        if let batch = vaccination.batchNumber { rows.append(("Batch", batch)) }
        if let site = vaccination.site { rows.append(("Site", site)) }
        return rows
    }
}
