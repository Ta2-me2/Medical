import Foundation

/// Checks that counting document usage in one pass gives exactly the answers
/// asking one document at a time used to give.
///
/// The reference below is the original code, verbatim, built only from
/// `events(using:)` and `medicines(using:)` — functions the rewrite did not
/// touch. Comparing the new code with itself would prove nothing.
func checkDocumentUsage() {

    func referenceStatus(_ id: UUID, in archive: Archive) -> DocumentStatus {
        guard let document = archive.document(id: id) else { return .notProcessed }
        if document.isArchived { return .archived }
        if !archive.medicines(using: id).isEmpty { return .used }
        return archive.events(using: id).isEmpty ? .notProcessed : .used
    }

    func referenceDocuments(in archive: Archive) -> [DocumentRecord] {
        archive.documents
            .map {
                DocumentRecord(
                    document: $0,
                    events: archive.events(using: $0.id),
                    status: referenceStatus($0.id, in: archive)
                )
            }
            .sorted { $0.sortDate > $1.sortDate }
    }

    func agrees(_ archive: Archive) -> (documents: Bool, status: Bool, inbox: Bool, counts: Bool) {
        let documents = archive.allDocuments == referenceDocuments(in: archive)
        let status = archive.documents.allSatisfy {
            archive.status(ofDocumentID: $0.id) == referenceStatus($0.id, in: archive)
        }
        let inbox = archive.inboxCount
            == archive.documents.filter { referenceStatus($0.id, in: archive) == .notProcessed }.count
        let counts = [DocumentStatus.notProcessed, .used, .archived].allSatisfy { state in
            (archive.documentStatusCounts[state] ?? 0)
                == archive.documents.filter { referenceStatus($0.id, in: archive) == state }.count
        }
        return (documents, status, inbox, counts)
    }

    func scan(_ index: Int, importedDaysAgo days: Int = 0) -> StoredDocument {
        var document = StoredDocument(
            originalFilename: "scan-\(index).pdf",
            relativePath: "Originals/2020/scan-\(index).pdf",
            contentHash: "hash-\(index)",
            byteSize: 1024,
            kind: .pdf,
            pageCount: 4
        )
        document.importedAt = Date(timeIntervalSince1970: 1_700_000_000 - Double(days) * 86_400)
        return document
    }

    func pages(_ page: Int) -> PageSelection {
        PageSelection(ranges: [PageRange(first: page, last: page)])
    }

    section("Document usage, counted in one pass")

    // Every shape a document's usage can take, one of each.
    let twoRecords = scan(0, importedDaysAgo: 1)
    let citedTwiceByOne = scan(1, importedDaysAgo: 2)
    let onlyAMedicine = scan(2, importedDaysAgo: 3)
    let archivedButCited = scan(3, importedDaysAgo: 4)
    let archivedAlone = scan(4, importedDaysAgo: 5)
    let untouched = scan(5, importedDaysAgo: 6)

    var archive = Archive()
    archive.documents = [twoRecords, citedTwiceByOne, onlyAMedicine, archivedButCited, archivedAlone, untouched]
    archive.documents[3].isArchived = true
    archive.documents[4].isArchived = true

    var older = MedicalEvent(date: day(2015, 3, 1), category: .laboratory, title: "Blood count")
    older.attachments = [DocumentReference(documentID: twoRecords.id)]
    var newer = MedicalEvent(date: day(2019, 6, 1), category: .laboratory, title: "Blood count again")
    newer.attachments = [
        DocumentReference(documentID: twoRecords.id),
        DocumentReference(documentID: citedTwiceByOne.id, pages: pages(1)),
        DocumentReference(documentID: citedTwiceByOne.id, pages: pages(3)),
        DocumentReference(documentID: archivedButCited.id),
    ]
    archive.upsert(older)
    archive.upsert(newer)

    var leaflet = Medicine(name: "Ibuprofen")
    leaflet.attachments = [DocumentReference(documentID: onlyAMedicine.id)]
    archive.upsert(leaflet)

    let shapes = agrees(archive)
    check("the document list is identical to the old one", shapes.documents)
    check("every single-document status is identical", shapes.status)
    check("the inbox badge is identical", shapes.inbox)
    check("every scope count is identical", shapes.counts)

    // And the answers themselves, so agreement is not agreement on a mistake.
    func record(_ document: StoredDocument) -> DocumentRecord? {
        archive.allDocuments.first { $0.document.id == document.id }
    }
    check("cited by two records: used, by both",
          record(twoRecords)?.status == .used && record(twoRecords)?.events.count == 2)
    check("its records are newest first, as before",
          record(twoRecords)?.events.map(\.title) == ["Blood count again", "Blood count"])
    check("cited twice by one record: that record is listed once",
          record(citedTwiceByOne)?.events.count == 1)
    check("cited only by a medicine: used, with no records",
          record(onlyAMedicine)?.status == .used && record(onlyAMedicine)?.events.isEmpty == true)
    check("archived wins over being cited", record(archivedButCited)?.status == .archived)
    check("archived and uncited: archived", record(archivedAlone)?.status == .archived)
    check("uncited: in the inbox", record(untouched)?.status == .notProcessed)
    check("the badge counts exactly the one in the inbox", archive.inboxCount == 1)
    check("and a scope count for every state",
          archive.documentStatusCounts == [.used: 3, .archived: 2, .notProcessed: 1])

    section("Document usage, against a randomised archive")

    // A deterministic generator, so a failure here can be reproduced.
    struct SplitMix: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    var allAgree = true
    for seed in 1...12 {
        var rng = SplitMix(state: UInt64(seed))
        var random = Archive()
        random.documents = (0..<30).map { scan($0, importedDaysAgo: Int.random(in: 0...400, using: &rng)) }
        for index in random.documents.indices where Int.random(in: 0..<6, using: &rng) == 0 {
            random.documents[index].isArchived = true
        }
        for index in 0..<200 {
            var event = MedicalEvent(
                date: day(2000 + Int.random(in: 0...25, using: &rng), Int.random(in: 1...12, using: &rng), 1),
                category: .consultation,
                title: "Visit \(index)"
            )
            for _ in 0..<Int.random(in: 0...3, using: &rng) {
                let document = random.documents.randomElement(using: &rng)!
                let selection = Bool.random(using: &rng) ? PageSelection.wholeDocument : pages(Int.random(in: 1...4, using: &rng))
                event.attachments.append(DocumentReference(documentID: document.id, pages: selection))
            }
            random.upsert(event)
        }
        for index in 0..<10 {
            var medicine = Medicine(name: "Medicine \(index)")
            if Bool.random(using: &rng) {
                medicine.attachments = [DocumentReference(documentID: random.documents.randomElement(using: &rng)!.id)]
            }
            random.upsert(medicine)
        }

        let result = agrees(random)
        if !(result.documents && result.status && result.inbox && result.counts) {
            allAgree = false
            print("      disagreement at seed \(seed): \(result)")
        }
    }
    check("twelve random archives of 200 records: every answer identical", allAgree)
}
