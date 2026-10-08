import Foundation

/// The whole archive, and the exact shape of `Archive.json` on disk.
///
/// This type is both the in-memory model and the file format. There is no
/// separate persistence model to map to and no schema to keep in step — the
/// file is simply this struct, written out with readable keys and sorted so
/// that diffs between two versions of the archive stay meaningful.
nonisolated struct Archive: Codable, Sendable, Hashable {

    /// Bumped only when a change cannot be expressed by tolerant decoding.
    static let currentFormatVersion = 2

    var formatVersion: Int = Archive.currentFormatVersion
    var archiveID = UUID()
    var createdAt: Date = .now

    var patient = Patient()

    /// Every original the library holds, whether or not any record cites it.
    /// A document is a thing in its own right: it arrives before it is filed,
    /// and it can end up cited by several records at once.
    var documents: [StoredDocument] = []

    var events: [MedicalEvent] = []
    var doctors: [Doctor] = []
    var facilities: [Facility] = []
    var tags: [Tag] = []

    /// The cupboard, which is inventory rather than history. See `FirstAidKit`.
    var firstAidKit = FirstAidKit()

    init(
        formatVersion: Int = Archive.currentFormatVersion,
        archiveID: UUID = UUID(),
        createdAt: Date = .now,
        patient: Patient = Patient(),
        documents: [StoredDocument] = [],
        events: [MedicalEvent] = [],
        doctors: [Doctor] = [],
        facilities: [Facility] = [],
        tags: [Tag] = [],
        firstAidKit: FirstAidKit = FirstAidKit()
    ) {
        self.formatVersion = formatVersion
        self.archiveID = archiveID
        self.createdAt = createdAt
        self.patient = patient
        self.documents = documents
        self.events = events
        self.doctors = doctors
        self.facilities = facilities
        self.tags = tags
        self.firstAidKit = firstAidKit
    }

    // MARK: - Events

    /// Newest first — the order every screen in this app presents history in.
    var eventsNewestFirst: [MedicalEvent] {
        events.sorted { $0.date > $1.date }
    }

    var years: [Int] {
        Set(events.map(\.year)).sorted(by: >)
    }

    func events(in year: Int) -> [MedicalEvent] {
        events.filter { $0.year == year }.sorted { $0.date > $1.date }
    }

    // MARK: - Documents

    func document(id: UUID) -> StoredDocument? {
        documents.first { $0.id == id }
    }

    /// The documents a record cites, resolved, in the order it cites them.
    func attachments(for event: MedicalEvent) -> [AttachedDocument] {
        event.attachments.compactMap { reference in
            documents.first { $0.id == reference.documentID }
                .map { AttachedDocument(reference: reference, document: $0) }
        }
    }

    /// The leaflets a medicine cites, resolved the same way a record's are.
    func attachments(for medicine: Medicine) -> [AttachedDocument] {
        medicine.attachments.compactMap { reference in
            documents.first { $0.id == reference.documentID }
                .map { AttachedDocument(reference: reference, document: $0) }
        }
    }

    /// Every record that cites this document. The answer to "used in".
    func events(using documentID: UUID) -> [MedicalEvent] {
        events
            .filter { event in event.attachments.contains { $0.documentID == documentID } }
            .sorted { $0.date > $1.date }
    }

    /// Which pages of this document each record uses. What the library page
    /// shows under a ninety-page card that four records draw from.
    func citations(of documentID: UUID) -> [Citation] {
        events(using: documentID).compactMap { event in
            event.attachments
                .first { $0.documentID == documentID }
                .map { Citation(eventID: event.id, eventTitle: event.title, pages: $0.pages, date: event.date) }
        }
    }

    /// Read, never stored — see `DocumentStatus`.
    ///
    /// Looks the document up rather than trusting the value handed in: callers
    /// hold copies, and a copy taken before an edit would report the status the
    /// document used to have.
    func status(ofDocumentID id: UUID) -> DocumentStatus {
        guard let document = document(id: id) else { return .notProcessed }
        if document.isArchived { return .archived }
        // A leaflet filed against a medicine has been dealt with just as surely
        // as a scan filed against a record. Counting only records would leave it
        // in the inbox for ever, and would let it be deleted as unused.
        //
        // Only *whether* anything cites it — not which records, not in what
        // order. Building and sorting that list just to ask whether it was
        // empty was the most expensive line on the inbox's hot path.
        if firstAidKit.medicines.contains(where: { $0.attachments.contains { $0.documentID == id } }) {
            return .used
        }
        return events.contains { $0.attachments.contains { $0.documentID == id } } ? .used : .notProcessed
    }

    /// Everything in the cupboard that cites this document.
    func medicines(using documentID: UUID) -> [Medicine] {
        firstAidKit.medicines.filter { medicine in
            medicine.attachments.contains { $0.documentID == documentID }
        }
    }

    func status(of document: StoredDocument) -> DocumentStatus {
        status(ofDocumentID: document.id)
    }

    /// Every document, with the records that cite it, in one pass.
    ///
    /// Asking each document in turn which records cite it meant scanning every
    /// record once per document: forty documents and a thousand records is
    /// forty thousand scans, and this runs whenever the Documents or Inbox page
    /// draws, and inside every search. One pass over the records answers the
    /// question for all of them at once. The records per document come out in
    /// the same order `events(using:)` gives, so nothing on screen reorders.
    var allDocuments: [DocumentRecord] {
        var citing: [UUID: [MedicalEvent]] = [:]
        for event in events {
            // A record citing the same document twice, at different pages, is
            // still one record using it.
            for id in Set(event.attachments.map(\.documentID)) {
                citing[id, default: []].append(event)
            }
        }

        var cited = Set(citing.keys)
        for medicine in firstAidKit.medicines {
            for reference in medicine.attachments { cited.insert(reference.documentID) }
        }

        return documents
            .map { document in
                DocumentRecord(
                    document: document,
                    events: (citing[document.id] ?? []).sorted { $0.date > $1.date },
                    status: status(of: document, cited: cited)
                )
            }
            .sorted { $0.sortDate > $1.sortDate }
    }

    /// Every document something points at — a record or a medicine.
    ///
    /// Enough to say "used or not" for every document at once, without
    /// gathering *which* records: collecting those means copying whole records
    /// into lists, and the counts below never look at them.
    private var citedDocumentIDs: Set<UUID> {
        var ids = Set<UUID>()
        for event in events {
            for reference in event.attachments { ids.insert(reference.documentID) }
        }
        for medicine in firstAidKit.medicines {
            for reference in medicine.attachments { ids.insert(reference.documentID) }
        }
        return ids
    }

    /// The same rule as `status(ofDocumentID:)`, answered from a set built once.
    private func status(of document: StoredDocument, cited: Set<UUID>) -> DocumentStatus {
        if document.isArchived { return .archived }
        return cited.contains(document.id) ? .used : .notProcessed
    }

    /// How many documents are in each state, counted in one pass. The inbox's
    /// scope picker shows every one of these numbers at once.
    var documentStatusCounts: [DocumentStatus: Int] {
        let cited = citedDocumentIDs
        var counts: [DocumentStatus: Int] = [:]
        for document in documents {
            counts[status(of: document, cited: cited), default: 0] += 1
        }
        return counts
    }

    func record(for document: StoredDocument) -> DocumentRecord {
        DocumentRecord(document: document, events: events(using: document.id), status: status(of: document))
    }

    /// What the inbox shows: everything that has arrived and not yet been dealt
    /// with, oldest first — the order a backlog should be worked through.
    var inbox: [DocumentRecord] {
        allDocuments
            .filter { $0.status == .notProcessed }
            .sorted { $0.document.importedAt < $1.document.importedAt }
    }

    /// The sidebar's badge. It is drawn on every tab switch, so it is the one
    /// number in the app that has to be cheap above all others.
    var inboxCount: Int {
        let cited = citedDocumentIDs
        return documents.count { status(of: $0, cited: cited) == .notProcessed }
    }

    /// Documents deliberately set aside — health-visitor notes, administrative
    /// paperwork, superseded discharge letters. They stay in the library and
    /// stay searchable; they simply never reach the timeline, because nothing in
    /// the timeline is theirs to be part of.
    var archivedDocuments: [DocumentRecord] {
        allDocuments
            .filter { $0.status == .archived }
            .sorted { $0.document.importedAt > $1.document.importedAt }
    }

    var archivedCount: Int { documents.filter(\.isArchived).count }

    // MARK: - Notes and vaccinations

    var allNotes: [NoteRecord] {
        events
            .flatMap { event in event.notes.map { NoteRecord(note: $0, event: event) } }
            .sorted { $0.date > $1.date }
    }

    var allVaccinations: [VaccinationRecord] {
        events
            .flatMap { event in event.vaccinations.map { VaccinationRecord(vaccination: $0, event: event) } }
            .sorted { $0.date > $1.date }
    }

    /// Doses gathered into one list per course, alphabetically by title.
    ///
    /// Chronology is the wrong index for the question this page usually gets
    /// asked — "what have I had against this, and when was the last one" — and
    /// answering it by scrolling twenty years of doses is not answering it.
    var vaccinationSeries: [VaccinationSeries] {
        var grouped: [String: [VaccinationRecord]] = [:]
        // `allVaccinations` is already newest first, so each bucket inherits
        // that order rather than being sorted again.
        for record in allVaccinations {
            grouped[record.seriesKey, default: []].append(record)
        }

        return grouped.compactMap { key, records -> VaccinationSeries? in
            guard let newest = records.first else { return nil }
            return VaccinationSeries(key: key, name: newest.event.title, records: records)
        }
        .sorted {
            let byName = $0.name.localizedCaseInsensitiveCompare($1.name)
            return byName == .orderedSame ? $0.key < $1.key : byName == .orderedAscending
        }
    }

    /// Vaccinations that still need repeating, soonest first.
    ///
    /// One entry per course — keyed on the record's title, exactly as the
    /// vaccinations page groups them, so the page and the reminders can never
    /// tell the owner two different stories about what supersedes what. A
    /// later dose supersedes the earlier one's schedule entirely, including
    /// when it was given early or late, because the interval runs from the
    /// injection that happened, not from the one that was planned. That holds
    /// across product names: BCG followed by BCG-M is one course continued,
    /// not two clocks running side by side.
    func vaccinationsDue(asOf now: Date = .now) -> [VaccinationDue] {
        var series: [String: [VaccinationRecord]] = [:]
        for record in allVaccinations {
            series[record.seriesKey, default: []].append(record)
        }

        return series.values
            .compactMap { records -> VaccinationDue? in
                guard let latest = records.map(\.date).max() else { return nil }

                // Several vaccines recorded on the same day are one visit, not
                // a series superseding itself. Whichever of them comes due
                // first speaks for the course: a reminder that arrives early is
                // a nuisance, one that never arrives is a missed dose.
                return records
                    .filter { !($0.date < latest) }
                    .compactMap { record -> VaccinationDue? in
                        guard let schedule = record.vaccination.booster,
                              let due = schedule.dueDate(after: record.date)
                        else { return nil }
                        return VaccinationDue(
                            vaccinationID: record.vaccination.id,
                            eventID: record.event.id,
                            eventTitle: record.event.title,
                            name: record.vaccination.name,
                            seriesKey: record.seriesKey,
                            doseLabel: record.vaccination.dose,
                            lastGiven: record.date,
                            dueOn: due
                        )
                    }
                    .min { $0.dueOn < $1.dueOn }
            }
            .sorted { $0.dueOn < $1.dueOn }
    }

    /// What the dashboard shows: overdue first, then anything due inside the
    /// window. A reminder that fires four years early is not a reminder.
    func vaccinationsNeedingAttention(within months: Int = 12, asOf now: Date = .now) -> [VaccinationDue] {
        let horizon = Calendar.current.date(byAdding: .month, value: months, to: now) ?? now
        return vaccinationsDue(asOf: now).filter { $0.dueOn <= horizon }
    }

    // MARK: - First aid kit

    /// The cupboard in the order a cupboard is read: by name.
    var medicinesByName: [Medicine] {
        firstAidKit.medicines.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    var medicineCount: Int { firstAidKit.medicines.count }

    func medicines(of kind: MedicineKind) -> [Medicine] {
        medicinesByName.filter { $0.kinds.contains(kind) }
    }

    /// Medicines the owner has not filed under any direction. They are still in
    /// the cupboard and still expire; they simply sit on their own shelf.
    var unsortedMedicines: [Medicine] {
        medicinesByName.filter(\.kinds.isEmpty)
    }

    /// The directions that have something in them, in the fixed order the
    /// recommendations are listed — so the shelves do not reshuffle themselves
    /// every time a box is added.
    var stockedMedicineKinds: [MedicineKind] {
        MedicineKind.allCases.filter { !medicines(of: $0).isEmpty }
    }

    /// Directions with nothing in them, minus the ones set aside.
    var missingMedicineKinds: [MedicineKind] {
        MedicineKind.allCases.filter {
            medicines(of: $0).isEmpty && !firstAidKit.hiddenKinds.contains($0)
        }
    }

    func isHidden(_ kind: MedicineKind) -> Bool {
        firstAidKit.hiddenKinds.contains(kind)
    }

    /// Everything already out of date, plus everything that will be inside the
    /// window, soonest first.
    ///
    /// A cupboard is checked rarely, so the window is generous: a box that runs
    /// out in two months is worth knowing about while there is still time to
    /// replace it before somebody needs it at midnight.
    func medicinesExpiring(within days: Int = 90, asOf now: Date = .now) -> [MedicineExpiry] {
        let calendar = Calendar.current
        let horizon = calendar.date(byAdding: .day, value: days, to: now) ?? now

        return firstAidKit.medicines
            .compactMap { medicine -> MedicineExpiry? in
                guard let last = medicine.lastUsefulDay, last <= horizon else { return nil }
                return MedicineExpiry(
                    medicineID: medicine.id,
                    name: medicine.name,
                    emoji: medicine.displayEmoji,
                    expiresOn: last
                )
            }
            .sorted { $0.expiresOn < $1.expiresOn }
    }

    func medicine(id: UUID) -> Medicine? { firstAidKit.medicines.first { $0.id == id } }

    // MARK: - Lookup

    func event(id: UUID) -> MedicalEvent? { events.first { $0.id == id } }
    func doctor(id: UUID?) -> Doctor? { id.flatMap { needle in doctors.first { $0.id == needle } } }
    func facility(id: UUID?) -> Facility? { id.flatMap { needle in facilities.first { $0.id == needle } } }
    func tags(ids: [UUID]) -> [Tag] { tags.filter { ids.contains($0.id) } }

    func doctor(for event: MedicalEvent) -> Doctor? { doctor(id: event.doctorID) }
    func facility(for event: MedicalEvent) -> Facility? { facility(id: event.facilityID) }

    /// The context line under an event title: `Dr. Silva · Northgate Medical Center`.
    func attribution(for event: MedicalEvent) -> String? {
        [doctor(for: event)?.name, facility(for: event)?.name]
            .compactMap(\.self)
            .joined(separator: " · ")
            .nilIfEmpty
    }

    // MARK: - Counts

    var documentCount: Int { documents.count }
    var eventCount: Int { events.count }
    var vaccinationCount: Int { events.reduce(0) { $0 + $1.vaccinations.count } }
    var noteCount: Int { events.reduce(0) { $0 + $1.notes.count } }

    // MARK: - Recent and pinned
    //
    // What the dashboard is made of. Ordered by when things entered the archive
    // rather than when they happened medically: the dashboard answers "what have
    // I been doing", the timeline answers "what happened to me".

    var pinnedEvents: [MedicalEvent] {
        events.filter(\.isPinned).sorted { $0.date > $1.date }
    }

    /// Most recently added first.
    ///
    /// Ties break on the medical date, because a batch of paperwork filed in one
    /// sitting shares a creation time down to the second — and then insertion
    /// order would decide what "recent" means, which is no answer at all.
    func recentEvents(limit: Int) -> [MedicalEvent] {
        let ordered = events.sorted {
            $0.createdAt == $1.createdAt ? $0.date > $1.date : $0.createdAt > $1.createdAt
        }
        return Array(ordered.prefix(limit))
    }

    func recentDocuments(limit: Int) -> [DocumentRecord] {
        Array(
            allDocuments
                .sorted { $0.document.importedAt > $1.document.importedAt }
                .prefix(limit)
        )
    }

    func recentNotes(limit: Int) -> [NoteRecord] {
        Array(allNotes.sorted { $0.note.createdAt > $1.note.createdAt }.prefix(limit))
    }

    var isEmpty: Bool { events.isEmpty && documents.isEmpty }

    // MARK: - Mutation

    mutating func upsert(_ event: MedicalEvent) {
        var event = event
        event.updatedAt = .now
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            events[index] = event
        } else {
            events.append(event)
        }
    }

    /// Removes the record. The documents it cited stay in the library and, if no
    /// other record cites them, return to the inbox — the bytes are the one
    /// thing here that cannot be recreated.
    mutating func removeEvent(id: UUID) {
        events.removeAll { $0.id == id }
    }

    /// Forgets a document and every citation of it.
    ///
    /// The file on disk is dealt with separately, by the store: this type only
    /// ever describes the archive, and deciding the fate of bytes is not
    /// something a value type should be able to do by accident.
    mutating func removeDocument(id: UUID) {
        documents.removeAll { $0.id == id }
        for index in events.indices where events[index].attachments.contains(where: { $0.documentID == id }) {
            events[index].attachments.removeAll { $0.documentID == id }
            events[index].updatedAt = .now
        }
        for index in firstAidKit.medicines.indices {
            firstAidKit.medicines[index].attachments.removeAll { $0.documentID == id }
        }
    }

    mutating func addDocuments(_ newDocuments: [StoredDocument]) {
        documents.append(contentsOf: newDocuments)
    }

    mutating func setArchived(_ isArchived: Bool, forDocument id: UUID) {
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return }
        documents[index].isArchived = isArchived
    }

    mutating func setTitle(_ title: String?, forDocument id: UUID) {
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return }
        documents[index].title = title?.nilIfEmpty
    }

    mutating func upsert(_ medicine: Medicine) {
        if let index = firstAidKit.medicines.firstIndex(where: { $0.id == medicine.id }) {
            firstAidKit.medicines[index] = medicine
        } else {
            firstAidKit.medicines.append(medicine)
        }
    }

    mutating func removeMedicine(id: UUID) {
        firstAidKit.medicines.removeAll { $0.id == id }
    }

    mutating func setHidden(_ isHidden: Bool, forKind kind: MedicineKind) {
        if isHidden {
            guard !firstAidKit.hiddenKinds.contains(kind) else { return }
            firstAidKit.hiddenKinds.append(kind)
        } else {
            firstAidKit.hiddenKinds.removeAll { $0 == kind }
        }
    }

    mutating func attach(_ reference: DocumentReference, to eventID: UUID) {
        guard let index = events.firstIndex(where: { $0.id == eventID }) else { return }
        events[index].attachments.append(reference)
        events[index].updatedAt = .now
    }

    mutating func detach(referenceID: UUID, from eventID: UUID) {
        guard let index = events.firstIndex(where: { $0.id == eventID }) else { return }
        events[index].attachments.removeAll { $0.id == referenceID }
        events[index].updatedAt = .now
    }

    mutating func setPinned(_ isPinned: Bool, forEvent id: UUID) {
        guard let index = events.firstIndex(where: { $0.id == id }) else { return }
        events[index].isPinned = isPinned
        events[index].updatedAt = .now
    }

    mutating func setStatus(_ status: EventStatus, forEvent id: UUID) {
        guard let index = events.firstIndex(where: { $0.id == id }) else { return }
        events[index].status = status
        events[index].updatedAt = .now
    }

    /// Returns the id of an existing doctor with this name, or creates one.
    /// Keeps the reference tables from filling with near-duplicates.
    mutating func resolveDoctor(named name: String, specialty: Specialty? = nil) -> UUID? {
        guard let name = name.nilIfEmpty else { return nil }
        if let existing = doctors.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return existing.id
        }
        let doctor = Doctor(name: name, specialty: specialty)
        doctors.append(doctor)
        return doctor.id
    }

    mutating func resolveFacility(named name: String, kind: Facility.Kind = .clinic) -> UUID? {
        guard let name = name.nilIfEmpty else { return nil }
        if let existing = facilities.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return existing.id
        }
        let facility = Facility(name: name, kind: kind)
        facilities.append(facility)
        return facility.id
    }

    /// Resolves a list of tag names to ids, creating the ones that are new.
    mutating func resolveTags(named names: [String]) -> [UUID] {
        names.compactMap { rawName in
            guard let name = rawName.nilIfEmpty else { return nil }
            if let existing = tags.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                return existing.id
            }
            let tag = Tag(name: name)
            tags.append(tag)
            return tag.id
        }
    }

    // MARK: - Tolerant decoding

    private enum CodingKeys: String, CodingKey {
        case formatVersion, archiveID, createdAt, patient
        case documents, events, doctors, facilities, tags
        case firstAidKit
    }

    /// Version 1 kept documents inside events, plus a short-lived
    /// `unfiledDocuments` list at the top level.
    private enum LegacyCodingKeys: String, CodingKey {
        case unfiledDocuments
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = c.value(.formatVersion, or: Archive.currentFormatVersion)
        archiveID = c.value(.archiveID, or: UUID())
        createdAt = c.value(.createdAt, or: .now)
        patient = c.value(.patient, or: Patient())
        events = c.value(.events, or: [])
        doctors = c.value(.doctors, or: [])
        facilities = c.value(.facilities, or: [])
        tags = c.value(.tags, or: [])
        documents = c.value(.documents, or: [])
        firstAidKit = c.value(.firstAidKit, or: FirstAidKit())

        let legacy = try? decoder.container(keyedBy: LegacyCodingKeys.self)
        let unfiled: [StoredDocument] = legacy?.value(.unfiledDocuments, or: []) ?? []

        migrateDocumentsIntoLibrary(alsoAdopting: unfiled)
    }

    /// Lifts documents that older archives stored inside events into the
    /// library, leaving each event pointing at them by id.
    ///
    /// Runs on every load and does nothing once there is nothing to lift, so a
    /// file written by any version opens correctly without a migration step to
    /// remember to run — or to get wrong.
    private mutating func migrateDocumentsIntoLibrary(alsoAdopting unfiled: [StoredDocument]) {
        var known = Set(documents.map(\.id))

        for candidate in unfiled where !known.contains(candidate.id) {
            documents.append(candidate)
            known.insert(candidate.id)
        }

        for index in events.indices {
            let nested = events[index].legacyDocuments
            guard !nested.isEmpty else { continue }
            for document in nested where !known.contains(document.id) {
                documents.append(document)
                known.insert(document.id)
            }
            events[index].legacyDocuments = []
        }

        // A citation of a document that is not in the library would render as a
        // phantom attachment. Drop the citation, never the file.
        for index in events.indices {
            events[index].attachments.removeAll { !known.contains($0.documentID) }
        }

        formatVersion = Archive.currentFormatVersion
    }
}
