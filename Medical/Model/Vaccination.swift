import Foundation

/// A single administered dose.
///
/// Lives inside its medical event, like everything else. The Vaccinations page
/// is a projection over events, not a second place where doses are stored —
/// otherwise the two would eventually disagree.
nonisolated struct Vaccination: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var name: String
    var manufacturer: String?
    var dose: String?
    var batchNumber: String?
    var site: String?
    var notes: String?

    /// Points at a document belonging to the same event.
    var certificateDocumentID: UUID?

    /// When this needs repeating, if it does.
    var booster: BoosterSchedule?

    init(
        id: UUID = UUID(),
        name: String,
        manufacturer: String? = nil,
        dose: String? = nil,
        batchNumber: String? = nil,
        site: String? = nil,
        notes: String? = nil,
        certificateDocumentID: UUID? = nil,
        booster: BoosterSchedule? = nil
    ) {
        self.id = id
        self.name = name
        self.manufacturer = manufacturer
        self.dose = dose
        self.batchNumber = batchNumber
        self.site = site
        self.notes = notes
        self.certificateDocumentID = certificateDocumentID
        self.booster = booster
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, manufacturer, dose, batchNumber, site, notes
        case certificateDocumentID, booster
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, or: UUID())
        name = c.value(.name, or: "Unnamed vaccine")
        manufacturer = c.value(.manufacturer)
        dose = c.value(.dose)
        batchNumber = c.value(.batchNumber)
        site = c.value(.site)
        notes = c.value(.notes)
        certificateDocumentID = c.value(.certificateDocumentID)
        booster = c.value(.booster)
    }
}

/// A vaccination paired with the event it belongs to, for pages that show doses
/// across the whole archive.
nonisolated struct VaccinationRecord: Identifiable, Hashable, Sendable {
    var vaccination: Vaccination
    var event: MedicalEvent

    var id: UUID { vaccination.id }
    var date: DateValue { event.date }

    /// Which series this dose belongs to.
    ///
    /// The record's title, not the vaccine's own name. Protection against one
    /// disease is given under many product names over a lifetime — BCG and
    /// BCG-M, DTP and ADS-M — and grouping by the product would scatter one
    /// history across four headings and start four separate booster clocks.
    /// What the dose was *for* is what the owner wrote on the record.
    var seriesKey: String { VaccinationSeries.key(for: event.title) }
}

/// Every dose of one vaccine, newest first.
///
/// A projection, not a record: doses live inside their events and are gathered
/// here on the way to the screen. Nothing has to be kept in step, and a dose
/// cannot end up in the wrong series by accident.
nonisolated struct VaccinationSeries: Identifiable, Hashable, Sendable {

    /// The normalised record title that holds the doses together — the same key
    /// the booster schedule uses, so the vaccinations page and the reminders can
    /// never disagree about what counts as one course.
    var key: String

    /// Titled the way the most recent dose's record titles it.
    var name: String

    /// Newest first.
    var records: [VaccinationRecord]

    var id: String { key }
    var doseCount: Int { records.count }

    /// Case and stray spacing do not start a second series. Anything beyond
    /// that is left alone: guessing that "Tetanus" and "Tetanus booster" are
    /// the same course would be the application deciding what the owner meant.
    static func key(for title: String) -> String {
        title.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "  ", with: " ")
    }
    var latest: VaccinationRecord? { records.first }
    var earliest: VaccinationRecord? { records.last }
}
