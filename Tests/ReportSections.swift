import Foundation

/// Checks what the Doctor Report decides to print.
///
/// The rule under test is the one that made the report worth fixing: a record
/// whose every fact is already in a table above it is not printed again.
func checkReportSections() {
    let report = DoctorReport(libraryURL: URL(fileURLWithPath: "/tmp/not-used"))

    func archive(_ events: [MedicalEvent], documents: [StoredDocument] = []) -> Archive {
        var archive = Archive()
        archive.patient.fullName = "Test Owner"
        archive.documents = documents
        for event in events { archive.upsert(event) }
        return archive
    }

    func offered(_ archive: Archive, without dropped: DoctorReportRequest.Section...) -> [String: String] {
        var request = DoctorReportRequest()
        for section in dropped { request.setInclusion(false, of: section) }
        return Dictionary(uniqueKeysWithValues: report.parts(archive: archive, request: request)
            .map { ($0.section.rawValue, $0.detail) })
    }

    func shot(_ title: String, on date: DateValue, batch: String? = nil) -> MedicalEvent {
        var event = MedicalEvent(date: date, category: .vaccination, title: title)
        event.vaccinations = [Vaccination(name: "DTP", dose: "0.5", batchNumber: batch)]
        return event
    }

    section("What the report offers to print")

    let doses = archive([
        shot("Diphtheria Vaccination", on: day(2004, 5, 27), batch: "37-4"),
        shot("Tetanus Vaccination", on: day(2004, 5, 27), batch: "37-4"),
    ])
    var parts = offered(doses)
    check("a chronology is offered", parts["chronology"] == "2 records")
    check("the doses are offered", parts["vaccinations"] == "2 doses")
    check("records with nothing to add are not offered at all", parts["records"] == nil)
    check("and nothing else is invented",
          Set(parts.keys) == ["chronology", "vaccinations"])

    // Switch the table off and the same records have to be printed somewhere.
    parts = offered(doses, without: .vaccinations)
    check("without the table, the records carry the doses instead", parts["records"] == "2 records")

    section("What earns a record its own entry")

    var withNote = shot("Tetanus Vaccination", on: day(2011, 4, 12))
    withNote.notes = [Note(body: "Given in the left arm; sore for two days.")]
    check("a note earns it", offered(archive([withNote]))["records"] == "1 record")

    var withDoctor = shot("Tetanus Vaccination", on: day(2011, 4, 12))
    var archiveWithDoctor = archive([withDoctor])
    let doctor = Doctor(name: "Dr. Marta Silva", specialty: .generalPractice)
    archiveWithDoctor.doctors = [doctor]
    withDoctor.doctorID = doctor.id
    archiveWithDoctor.upsert(withDoctor)
    check("a doctor earns it",
          Dictionary(uniqueKeysWithValues: report.parts(archive: archiveWithDoctor, request: DoctorReportRequest())
            .map { ($0.section.rawValue, $0.detail) })["records"] == "1 record")

    var flagged = shot("Tetanus Vaccination", on: day(2011, 4, 12))
    flagged.status = .significant
    check("a status worth saying out loud earns it",
          offered(archive([flagged]))["records"] == "1 record")

    var screening = MedicalEvent(date: day(2019, 9, 13), category: .screening, title: "Tuberculosis Screening")
    screening.summary = "Test: Diaskintest\nResult: Negative"
    let findings = archive([screening])
    check("a finding is offered as a finding", offered(findings)["findings"] == "1 finding")
    check("and the record is not repeated under it", offered(findings)["records"] == nil)
    check("unless the findings table is switched off",
          offered(findings, without: .findings)["records"] == "1 record")

    section("Documents everything shares")

    let card = StoredDocument(
        originalFilename: "card.pdf",
        relativePath: "Originals/2004/card.pdf",
        contentHash: "hash",
        byteSize: 1024,
        kind: .pdf,
        pageCount: 2
    )
    let other = StoredDocument(
        originalFilename: "letter.pdf",
        relativePath: "Originals/2011/letter.pdf",
        contentHash: "hash-2",
        byteSize: 512,
        kind: .pdf,
        pageCount: 1
    )

    func citing(_ document: StoredDocument, page: Int? = nil, title: String) -> MedicalEvent {
        var event = shot(title, on: day(2004, 5, 27))
        let pages = page.map { PageSelection(ranges: [PageRange(first: $0, last: $0)]) } ?? .wholeDocument
        event.attachments = [DocumentReference(documentID: document.id, pages: pages)]
        return event
    }

    let sameCard = archive(
        [citing(card, title: "Diphtheria Vaccination"), citing(card, title: "Tetanus Vaccination")],
        documents: [card]
    )
    check("one document behind everything is not a reason to print records",
          offered(sameCard)["records"] == nil)
    check("and it is still offered as a source document",
          offered(sameCard)["sourceDocuments"] == "1 document")

    let twoCards = archive(
        [citing(card, title: "Diphtheria Vaccination"), citing(other, title: "Tetanus Vaccination")],
        documents: [card, other]
    )
    check("two different documents are a reason", twoCards.events.isEmpty == false
            && offered(twoCards)["records"] == "2 records")
    check("and both are offered", offered(twoCards)["sourceDocuments"] == "2 documents")

    let partOfOne = archive(
        [citing(card, page: 1, title: "Diphtheria Vaccination"),
         citing(card, page: 2, title: "Tetanus Vaccination")],
        documents: [card]
    )
    check("citing particular pages is a reason", offered(partOfOne)["records"] == "2 records")

    section("Nothing to report")

    check("an empty selection offers nothing", offered(archive([])).isEmpty)
}
