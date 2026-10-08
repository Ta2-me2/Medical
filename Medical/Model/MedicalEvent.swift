import Foundation

/// The one object everything else hangs from.
///
/// Documents, notes, vaccinations, diagnoses and medications are all owned by an
/// event rather than stored in parallel lists. The Documents, Notes and
/// Vaccinations pages are projections over events. That is why the archive has
/// no way to drift out of sync with itself: there is only ever one copy of
/// anything.
nonisolated struct MedicalEvent: Identifiable, Hashable, Codable, Sendable {

    var id = UUID()

    var date: DateValue
    /// Set for things that span time — a hospital stay, a course of treatment.
    var endDate: DateValue?

    var category: EventCategory = .consultation
    var specialty: Specialty?

    /// Set by hand. Drives the colour this event shows everywhere it appears.
    var status: EventStatus = .normal

    /// Kept in reach on the dashboard — an operation, a diagnosis, the things
    /// worth finding again without scrolling twenty years.
    var isPinned: Bool = false

    var title: String
    var summary: String = ""

    /// Manual translations, keyed by ISO language code.
    ///
    /// A lifetime archive crosses countries and languages, and a summary in a
    /// language you no longer read is not an archive. Entered by hand — this
    /// app does not translate anything on its own.
    var translations: [String: String] = [:]

    var doctorID: UUID?
    var facilityID: UUID?

    var diagnoses: [Diagnosis] = []
    var medications: [Medication] = []
    var vaccinations: [Vaccination] = []

    /// Citations into the archive's document library: which file, and which
    /// pages of it. The record does not own the file — several records may cite
    /// the same one, at different pages.
    var attachments: [DocumentReference] = []

    /// Tables the owner typed out from those documents, in English.
    /// The part of the record a doctor actually reads.
    var tables: [ResultTable] = []

    var notes: [Note] = []
    var tagIDs: [UUID] = []

    var createdAt: Date = .now
    var updatedAt: Date = .now

    /// Only ever non-empty while reading an archive written by an older version.
    /// Never encoded; `Archive` empties it during migration.
    var legacyDocuments: [StoredDocument] = []

    init(
        id: UUID = UUID(),
        date: DateValue,
        endDate: DateValue? = nil,
        category: EventCategory = .consultation,
        specialty: Specialty? = nil,
        status: EventStatus = .normal,
        isPinned: Bool = false,
        title: String,
        summary: String = "",
        translations: [String: String] = [:],
        doctorID: UUID? = nil,
        facilityID: UUID? = nil,
        diagnoses: [Diagnosis] = [],
        medications: [Medication] = [],
        vaccinations: [Vaccination] = [],
        attachments: [DocumentReference] = [],
        tables: [ResultTable] = [],
        notes: [Note] = [],
        tagIDs: [UUID] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.date = date
        self.endDate = endDate
        self.category = category
        self.specialty = specialty
        self.status = status
        self.isPinned = isPinned
        self.title = title
        self.summary = summary
        self.translations = translations
        self.doctorID = doctorID
        self.facilityID = facilityID
        self.diagnoses = diagnoses
        self.medications = medications
        self.vaccinations = vaccinations
        self.attachments = attachments
        self.tables = tables
        self.notes = notes
        self.tagIDs = tagIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Derived

    var year: Int { date.year }

    /// `14 Mar 2007` or `14 Mar – 21 Mar 2007` for events that span time.
    var dateRangeDescription: String {
        guard let endDate else { return date.formatted }
        return "\(date.formatted) – \(endDate.formatted)"
    }

    var attachmentCount: Int { attachments.count }
    var tableCount: Int { tables.count }
    var noteCount: Int { notes.count }

    /// Everything a text search should look at for this event, flattened once.
    var searchableText: String {
        var parts: [String] = [title, summary, category.title, status.title]
        if let specialty { parts.append(specialty.title) }
        parts.append(contentsOf: translations.values)
        parts.append(contentsOf: diagnoses.flatMap { [$0.name, $0.code ?? ""] })
        parts.append(contentsOf: medications.map(\.name))
        parts.append(contentsOf: vaccinations.flatMap { [$0.name, $0.manufacturer ?? "", $0.batchNumber ?? ""] })
        parts.append(contentsOf: notes.map { "\($0.displayTitle) \($0.body)" })
        parts.append(contentsOf: tables.map(\.searchableText))
        parts.append(date.formatted)
        return parts.joined(separator: " ")
    }

    // MARK: - Tolerant decoding

    // See `KeyedDecodingContainer.value(_:or:)`. Fields added in later versions
    // must keep this initialiser exhaustive, and must supply a default here.

    private enum CodingKeys: String, CodingKey {
        case id, date, endDate, category, specialty, status, isPinned, title, summary, translations
        case doctorID, facilityID, diagnoses, medications, vaccinations
        case attachments, tables, notes, tagIDs, createdAt, updatedAt
    }

    /// Archives written before the document library existed nested whole
    /// documents inside the event. Kept in its own key set so the encoder,
    /// which is synthesised from `CodingKeys`, never sees a key it has no
    /// property for.
    private enum LegacyCodingKeys: String, CodingKey {
        case documents
        /// Before page ranges existed, a record cited whole documents by id.
        case documentIDs
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, or: UUID())
        date = try c.decode(DateValue.self, forKey: .date)
        endDate = c.value(.endDate)
        category = c.value(.category, or: .other)
        specialty = c.value(.specialty)
        status = c.value(.status, or: .normal)
        isPinned = c.value(.isPinned, or: false)
        title = c.value(.title, or: "Untitled")
        summary = c.value(.summary, or: "")
        translations = c.value(.translations, or: [:])
        doctorID = c.value(.doctorID)
        facilityID = c.value(.facilityID)
        diagnoses = c.value(.diagnoses, or: [])
        medications = c.value(.medications, or: [])
        vaccinations = c.value(.vaccinations, or: [])
        notes = c.value(.notes, or: [])

        // Documents used to be nested inside the event. Read them here and let
        // `Archive` lift them into the library, so an archive written before the
        // document library existed opens without losing a single file.
        let legacy = try? decoder.container(keyedBy: LegacyCodingKeys.self)
        legacyDocuments = legacy?.value(.documents, or: []) ?? []
        tables = c.value(.tables, or: [])

        // Newest form first, then each older one. A citation without pages means
        // the whole document, which is exactly what every reference written
        // before page ranges meant.
        let citations: [DocumentReference] = c.value(.attachments, or: [])
        if !citations.isEmpty {
            attachments = citations
        } else {
            let legacyIDs: [UUID] = legacy?.value(.documentIDs, or: []) ?? []
            let ids = legacyIDs.isEmpty ? legacyDocuments.map(\.id) : legacyIDs
            attachments = ids.map { DocumentReference(documentID: $0) }
        }
        tagIDs = c.value(.tagIDs, or: [])
        createdAt = c.value(.createdAt, or: .now)
        updatedAt = c.value(.updatedAt, or: .now)
    }
}
