import Foundation
import Observation

/// The draft of a medical record, whether it is being created or edited.
///
/// One model for both, because a record created from a scan and a record
/// corrected two years later are the same object and deserve the same form.
/// Works on a copy and commits once, so an unfinished edit can be abandoned.
@Observable
final class EventEditorViewModel {

    /// Where the record is coming from. Choosing a source is the first thing
    /// the flow asks, and the only step that differs between creating and
    /// editing — editing skips it.
    enum Stage {
        case chooseSource
        case form
    }

    var stage: Stage = .form

    /// Set when editing; `nil` when creating.
    let existingID: UUID?

    // Fields
    var title = ""
    var date = Date()
    var precision: DateValue.Precision = .day
    var category: EventCategory = .consultation
    var specialty: Specialty?
    var status: EventStatus = .normal
    var doctorName = ""
    var clinicName = ""
    var clinicKind: Facility.Kind = .clinic
    var summary = ""
    var tagsText = ""
    var noteBody = ""

    /// Documents from the library this record cites, and which pages of each.
    var attachments: [DocumentReference] = []

    /// Doses given at this event. Editable here because a vaccination is part of
    /// what happened, not a separate kind of record.
    var vaccinations: [Vaccination] = []

    /// Notes already attached to the record. Existing notes are shown but edited
    /// on the record page itself; this form only adds one.
    private(set) var existingNoteCount = 0

    var failure: String?
    var isSaving = false

    // MARK: - Construction

    /// A blank record, starting at the source question.
    init() {
        existingID = nil
        stage = .chooseSource
    }

    /// A blank record already attached to a document — the inbox path.
    init(documentID: UUID, suggestedTitle: String?, importedAt: Date) {
        existingID = nil
        stage = .form
        attachments = [DocumentReference(documentID: documentID)]
        title = suggestedTitle.map(Self.tidy) ?? ""
        // The import date is the only date known about a scan. Wrong more often
        // than right, but a better starting point than today, and the precision
        // control invites correcting it.
        date = importedAt
    }

    /// An existing record.
    init(event: MedicalEvent, archive: Archive) {
        existingID = event.id
        stage = .form
        title = event.title
        date = event.date.date
        precision = event.date.precision
        category = event.category
        specialty = event.specialty
        status = event.status
        doctorName = archive.doctor(for: event)?.name ?? ""
        clinicName = archive.facility(for: event)?.name ?? ""
        clinicKind = archive.facility(for: event)?.kind ?? .clinic
        summary = event.summary
        tagsText = archive.tags(ids: event.tagIDs).map(\.name).joined(separator: ", ")
        attachments = event.attachments
        vaccinations = event.vaccinations
        existingNoteCount = event.notes.count
    }

    // MARK: - Derived

    var isEditing: Bool { existingID != nil }
    var canSave: Bool { title.nilIfEmpty != nil }
    var dateValue: DateValue { DateValue(date, precision: precision) }

    var tagNames: [String] {
        tagsText.split(separator: ",").compactMap { $0.trimmingCharacters(in: .whitespaces).nilIfEmpty }
    }

    func addVaccination() {
        vaccinations.append(Vaccination(name: ""))
    }

    func removeVaccination(id: UUID) {
        vaccinations.removeAll { $0.id == id }
    }

    /// A vaccination with no name is a row the owner started and abandoned.
    var namedVaccinations: [Vaccination] {
        vaccinations.filter { $0.name.nilIfEmpty != nil }
    }

    func attach(_ documentID: UUID) {
        guard !attachments.contains(where: { $0.documentID == documentID }) else { return }
        attachments.append(DocumentReference(documentID: documentID))
    }

    func detach(referenceID: UUID) {
        attachments.removeAll { $0.id == referenceID }
    }

    /// The page text as typed, per citation, so an in-progress `"15-"` can sit
    /// in the field without being thrown away on every keystroke.
    var pageDrafts: [UUID: String] = [:]

    func pageText(for reference: DocumentReference) -> String {
        pageDrafts[reference.id] ?? reference.pages.storedText
    }

    func setPageText(_ text: String, for referenceID: UUID) {
        pageDrafts[referenceID] = text
        guard let index = attachments.firstIndex(where: { $0.id == referenceID }) else { return }
        // Only commit what parses. Half-typed input stays in the draft.
        if let parsed = PageSelection.parse(text) {
            attachments[index].pages = parsed
        }
    }

    func pageTextIsValid(_ text: String) -> Bool {
        PageSelection.parse(text) != nil
    }

    /// Turns `blood_test-2019.pdf` into `Blood test 2019` — a starting point,
    /// not an answer.
    static func tidy(_ filename: String) -> String {
        let base = (filename as NSString).deletingPathExtension
        let words = base
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
        guard let first = words.first else { return words }
        return first.uppercased() + words.dropFirst()
    }

    // MARK: - Commit

    func save(to store: ArchiveStore) {
        guard let title = title.nilIfEmpty else { return }

        isSaving = true
        defer { isSaving = false }

        let value = dateValue
        let noteToAdd = noteBody.nilIfEmpty

        store.update { archive in
            var event = existingID.flatMap { archive.event(id: $0) }
                ?? MedicalEvent(date: value, title: title)

            event.title = title
            event.date = value
            event.category = category
            event.specialty = specialty
            event.status = status
            event.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            event.attachments = attachments
            event.vaccinations = namedVaccinations
            event.doctorID = archive.resolveDoctor(named: doctorName, specialty: specialty)
            event.facilityID = archive.resolveFacility(named: clinicName, kind: clinicKind)
            event.tagIDs = archive.resolveTags(named: tagNames)

            if let noteToAdd {
                event.notes.append(Note(body: noteToAdd))
            }

            archive.upsert(event)
        }

        noteBody = ""
    }

    /// The id the caller should navigate to after saving.
    func savedEventID(in archive: Archive) -> UUID? {
        if let existingID { return existingID }
        // The record just written is the most recently created one.
        return archive.recentEvents(limit: 1).first?.id
    }
}
