import Foundation
import PDFKit

/// What to include in the report.
nonisolated struct DoctorReportRequest: Sendable {

    enum Scope: String, CaseIterable, Identifiable, Sendable {
        case entireArchive
        case category
        case dateRange

        var id: String { rawValue }

        var title: String {
            switch self {
            case .entireArchive: "Everything"
            case .category: "One category"
            case .dateRange: "A range of dates"
            }
        }
    }

    /// The parts a report is made of, in the order they appear.
    ///
    /// Every one of them is filled in from the same records, so leaving one out
    /// never loses a fact — it only changes how many times that fact is said.
    enum Section: String, CaseIterable, Identifiable, Sendable {
        case chronology
        case vaccinations
        case findings
        case diagnoses
        case medications
        case records
        case sourceDocuments

        var id: String { rawValue }

        var title: String {
            switch self {
            case .chronology: "Chronology"
            case .vaccinations: "All Vaccinations"
            case .findings: "Findings and Results"
            case .diagnoses: "All Diagnoses"
            case .medications: "All Medications"
            case .records: "Records in Full"
            case .sourceDocuments: "Source Documents"
            }
        }

        var explanation: String {
            switch self {
            case .chronology: "One line per record, oldest first"
            case .vaccinations: "Every dose, with batch numbers"
            case .findings: "Every result and observation"
            case .diagnoses: "Every diagnosis, with codes"
            case .medications: "Every medication"
            case .records: "Only records the tables above cannot hold"
            case .sourceDocuments: "The scanned pages the records cite"
            }
        }
    }

    var scope: Scope = .entireArchive
    var category: EventCategory = .consultation
    var from: Date = Calendar.current.date(byAdding: .year, value: -5, to: .now) ?? .now
    var to: Date = .now

    /// Everything, until the owner says otherwise.
    var sections: Set<Section> = Set(Section.allCases)

    func includes(_ section: Section) -> Bool { sections.contains(section) }

    mutating func setInclusion(_ isIncluded: Bool, of section: Section) {
        if isIncluded {
            sections.insert(section)
        } else {
            sections.remove(section)
        }
    }

    var suggestedFilename: String {
        let base = switch scope {
        case .entireArchive: "Doctor Report"
        case .category: "Doctor Report — \(category.title)"
        case .dateRange: "Doctor Report — \(from.formatted(.dateTime.year()))–\(to.formatted(.dateTime.year()))"
        }
        return "\(base).zip"
    }

    func matches(_ event: MedicalEvent) -> Bool {
        switch scope {
        case .entireArchive:
            true
        case .category:
            event.category == category
        case .dateRange:
            event.date.date >= Calendar.current.startOfDay(for: from)
                && event.date.date <= Calendar.current.startOfDay(for: to)
        }
    }
}

/// Builds the package a doctor is actually handed.
///
/// One button, one answer. A doctor with ten minutes does not want to choose
/// between CSV and JSON; they want the history, the numbers in a language they
/// read, and the originals to check against. So the report is a folder
/// containing exactly that, zipped.
///
/// The pages included are the pages the records cite. Handing over a ninety-page
/// childhood card because three of its pages are relevant is not thoroughness,
/// it is burying the answer. The full originals are never altered and are what
/// `LibraryBackup` carries.
nonisolated struct DoctorReport: Sendable {

    let libraryURL: URL

    func write(_ archive: Archive, request: DoctorReportRequest, to destination: URL) throws {
        let events = archive.eventsNewestFirst.filter(request.matches)

        let fileManager = FileManager.default
        let staging = fileManager.temporaryDirectory
            .appending(path: "Medical-Report-\(UUID().uuidString)", directoryHint: .isDirectory)
        let payload = staging.appending(
            path: destination.deletingPathExtension().lastPathComponent,
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: payload, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        try PDFReport.render(
            blocks(archive: archive, events: events, request: request),
            title: destination.deletingPathExtension().lastPathComponent,
            to: payload.appending(path: "Doctor Report.pdf")
        )

        if request.includes(.sourceDocuments) {
            try writeSourceDocuments(archive: archive, events: events, into: payload)
        }
        try writeReadMe(archive: archive, request: request, into: payload)

        try Zip.compress(folder: payload, to: destination)
    }

    // MARK: - What the report will contain

    /// One section that has something to put in it.
    nonisolated struct Part: Identifiable, Sendable {
        var section: DoctorReportRequest.Section
        /// "33 doses", "1 document" — what the reader is choosing to keep.
        var detail: String

        var id: String { section.rawValue }
    }

    /// The sections that would appear, given the records selected and the boxes
    /// ticked.
    ///
    /// The interface shows this list, so what the owner unticks is exactly what
    /// the report would otherwise have printed — there is no second, hidden
    /// idea of the report's shape for them to be surprised by.
    ///
    /// Order matters here: `Records in Full` only holds what the tables above it
    /// do not, so unticking a table above puts its contents back into Records
    /// rather than dropping them.
    func parts(archive: Archive, request: DoctorReportRequest) -> [Part] {
        let events = archive.eventsNewestFirst.filter(request.matches)
        guard !events.isEmpty else { return [] }

        var parts: [Part] = []

        // Both forms spelled out: "diagnosis" does not become "diagnosiss", and
        // a count nobody can read is a count nobody trusts.
        func add(_ section: DoctorReportRequest.Section, _ count: Int, _ one: String, _ many: String) {
            guard count > 0 else { return }
            parts.append(Part(section: section, detail: "\(count) \(count == 1 ? one : many)"))
        }

        add(.chronology, events.count, "record", "records")
        add(.vaccinations, events.reduce(0) { $0 + $1.vaccinations.count }, "dose", "doses")
        add(.findings, events.count { $0.summary.nilIfEmpty != nil }, "finding", "findings")
        add(.diagnoses, events.reduce(0) { $0 + $1.diagnoses.count }, "diagnosis", "diagnoses")
        add(.medications, events.reduce(0) { $0 + $1.medications.count }, "medication", "medications")
        add(.records, fullRecords(events, archive: archive, request: request).count, "record", "records")
        add(.sourceDocuments, citedDocuments(events, archive: archive), "document", "documents")

        return parts
    }

    /// The records that hold something no included table can show.
    ///
    /// A vaccination whose whole content is a date, a vaccine and a batch number
    /// is already printed, in full, in `All Vaccinations`. Printing it a second
    /// time under its own heading is not thoroughness — it is the same sentence
    /// twice, and fifty of them is eleven pages a doctor has to turn past.
    private func fullRecords(
        _ events: [MedicalEvent],
        archive: Archive,
        request: DoctorReportRequest
    ) -> [MedicalEvent] {
        let shared = sharedDocument(for: events, archive: archive)?.id
        return events.filter {
            adds(beyondTables: $0, archive: archive, request: request, sharedDocumentID: shared)
        }
    }

    private func adds(
        beyondTables event: MedicalEvent,
        archive: Archive,
        request: DoctorReportRequest,
        sharedDocumentID: UUID?
    ) -> Bool {
        // Things no summary table has a column for.
        if !event.notes.isEmpty { return true }
        if event.tables.contains(where: { !$0.rows.isEmpty }) { return true }
        if event.translations.values.contains(where: { $0.nilIfEmpty != nil }) { return true }
        if archive.doctor(for: event) != nil { return true }
        if clinicDescription(for: event, archive: archive) != nil { return true }
        if event.specialty != nil { return true }
        if event.endDate != nil { return true }
        if event.status.deservesLabel { return true }
        if !event.tagIDs.isEmpty { return true }
        if event.vaccinations.contains(where: { $0.notes?.nilIfEmpty != nil }) { return true }

        // Things a table would have shown, had it been asked to.
        if event.summary.nilIfEmpty != nil, !request.includes(.findings) { return true }
        if !event.vaccinations.isEmpty, !request.includes(.vaccinations) { return true }
        if !event.diagnoses.isEmpty, !request.includes(.diagnoses) { return true }
        if !event.medications.isEmpty, !request.includes(.medications) { return true }

        // A citation worth naming: part of a document, or a document that is not
        // the single one everything else refers to.
        let attachments = archive.attachments(for: event)
        if attachments.contains(where: { !$0.reference.pages.isWholeDocument }) { return true }
        if let sharedDocumentID {
            if attachments.contains(where: { $0.document.id != sharedDocumentID }) { return true }
        } else if !attachments.isEmpty {
            return true
        }

        return false
    }

    /// The one document every selected record cites in full, if there is one.
    ///
    /// Fifty records citing the same vaccination card produce fifty identical
    /// "Documents:" lines. Said once, at the top, it is a fact about the
    /// package; said fifty times it is furniture.
    private func sharedDocument(for events: [MedicalEvent], archive: Archive) -> StoredDocument? {
        var found: StoredDocument?
        for event in events {
            let attachments = archive.attachments(for: event)
            guard attachments.count == 1,
                  let only = attachments.first,
                  only.reference.pages.isWholeDocument
            else { return nil }

            if let found, found.id != only.document.id { return nil }
            found = only.document
        }
        return found
    }

    private func citedDocuments(_ events: [MedicalEvent], archive: Archive) -> Int {
        var seen: Set<String> = []
        for event in events {
            for attachment in archive.attachments(for: event) {
                seen.insert("\(attachment.document.id)#\(attachment.reference.pages.storedText)")
            }
        }
        return seen.count
    }

    // MARK: - The report itself

    private func blocks(
        archive: Archive,
        events: [MedicalEvent],
        request: DoctorReportRequest
    ) -> [PDFReport.Block] {
        var blocks: [PDFReport.Block] = []

        blocks.append(.title(archive.patient.displayName))
        blocks.append(.caption(coverLine(archive: archive, request: request)))
        blocks.append(.rule)

        blocks.append(contentsOf: patientBlocks(archive.patient))

        if events.isEmpty {
            blocks.append(.heading("Medical History"))
            blocks.append(.body("No records fall within this selection."))
            return blocks
        }

        // One document behind everything is a fact about the package, and
        // belongs with the other facts about the package.
        let shared = sharedDocument(for: events, archive: archive)
        if let shared, request.includes(.sourceDocuments) {
            let pages = shared.pageCount.map { " · \($0) \($0 == 1 ? "page" : "pages")" } ?? ""
            blocks.append(.fields([("Source", "\(shared.displayName)\(pages)")]))
        }

        // A chronology first, so the reader sees the shape of the history before
        // any single record. Oldest first: a history reads forwards.
        if request.includes(.chronology) {
            blocks.append(.heading("Chronology"))
            blocks.append(.table(chronology(events, archive: archive).droppingEmptyColumns()))
        }

        // Then the same history gathered by kind. A clinician looking for "what
        // has this person been vaccinated against" should not have to read fifty
        // records to assemble the answer themselves.
        blocks.append(contentsOf: summaryBlocks(events, archive: archive, request: request))

        let full = request.includes(.records)
            ? fullRecords(events, archive: archive, request: request)
            : []

        if !full.isEmpty {
            blocks.append(.pageBreak)
            blocks.append(.heading("Records in Full"))

            for event in full {
                blocks.append(contentsOf: recordBlocks(
                    event,
                    archive: archive,
                    request: request,
                    sharedDocumentID: shared?.id
                ))
            }
        }

        return blocks
    }

    private func coverLine(archive: Archive, request: DoctorReportRequest) -> String {
        var parts: [String] = []
        if let birth = archive.patient.formattedDateOfBirth {
            parts.append("Born \(birth)")
        }
        if let blood = archive.patient.bloodType {
            parts.append("Blood type \(blood.title)")
        }
        parts.append(scopeDescription(request))
        parts.append("Prepared \(Date.now.formatted(date: .long, time: .shortened))")
        return parts.joined(separator: "  ·  ")
    }

    private func scopeDescription(_ request: DoctorReportRequest) -> String {
        switch request.scope {
        case .entireArchive: "Complete history"
        case .category: request.category.title
        case .dateRange:
            "\(request.from.formatted(date: .abbreviated, time: .omitted)) – \(request.to.formatted(date: .abbreviated, time: .omitted))"
        }
    }

    private func patientBlocks(_ patient: Patient) -> [PDFReport.Block] {
        var blocks: [PDFReport.Block] = []

        if !patient.alerts.isEmpty {
            blocks.append(.heading("Medical Alerts"))
            for alert in patient.alerts {
                blocks.append(.body("• \(alert.text)"))
            }
        }

        if !patient.allergies.isEmpty {
            blocks.append(.heading("Allergies"))
            var table = ResultTable(title: "", columns: ["Substance", "Severity", "Reaction"])
            for allergy in patient.allergies {
                table.rows.append(ResultRow(
                    cells: [allergy.substance, allergy.severity.title, allergy.reaction ?? "—"],
                    isAbnormal: allergy.severity >= .severe
                ))
            }
            blocks.append(.table(table))
        }

        if !patient.chronicConditions.isEmpty {
            blocks.append(.heading("Chronic Conditions"))
            for condition in patient.chronicConditions {
                let since = condition.since.map { " — since \($0.medium)" } ?? ""
                blocks.append(.body("• \(condition.name)\(since)"))
            }
        }

        if let summary = patient.summary.nilIfEmpty {
            blocks.append(.heading("Summary"))
            blocks.append(.body(summary))
        }

        return blocks
    }

    private func chronology(_ events: [MedicalEvent], archive: Archive) -> ResultTable {
        var table = ResultTable(title: "", columns: ["Date", "Category", "Record", "Doctor / Clinic"])
        for event in events.sorted(by: { $0.date < $1.date }) {
            table.rows.append(ResultRow(
                cells: [
                    event.date.medium,
                    event.category.title,
                    event.title,
                    archive.attribution(for: event) ?? "—",
                ],
                isAbnormal: event.status == .significant
            ))
        }
        return table
    }

    /// Cross-cutting tables: every dose, every diagnosis, every medication,
    /// gathered from the whole selection.
    ///
    /// These repeat what the records below already say, and they earn the
    /// repetition: the records answer "what happened on this date", these answer
    /// "what is true about this person", and a doctor with ten minutes needs the
    /// second question answered first.
    private func summaryBlocks(
        _ events: [MedicalEvent],
        archive: Archive,
        request: DoctorReportRequest
    ) -> [PDFReport.Block] {
        var blocks: [PDFReport.Block] = []

        let doses = events.flatMap { event in event.vaccinations.map { (event, $0) } }
        if !doses.isEmpty, request.includes(.vaccinations) {
            var table = ResultTable(
                title: "All Vaccinations",
                // Every column the per-record table had, so that this one can
                // stand in for it entirely. The empty ones drop out below.
                columns: ["Date", "Record", "Vaccine", "Dose", "Manufacturer", "Batch", "Site", "Next due"]
            )
            for (event, vaccination) in doses.sorted(by: { $0.0.date < $1.0.date }) {
                table.rows.append(ResultRow(cells: [
                    event.date.medium,
                    event.title,
                    vaccination.name,
                    vaccination.dose ?? "—",
                    vaccination.manufacturer ?? "—",
                    vaccination.batchNumber ?? "—",
                    vaccination.site ?? "—",
                    nextDueDescription(vaccination, on: event.date) ?? "—",
                ]))
            }
            blocks.append(.table(table.droppingEmptyColumns()))
        }

        // Records whose content is prose: screenings, imaging, consultations.
        // Without this they exist only as individual entries further down, and a
        // reader wanting "every tuberculosis screening and what it said" has to
        // assemble the answer by hand. Not truncated — a finding half-quoted is
        // worse than one not shown.
        let findings = events.filter { $0.summary.nilIfEmpty != nil }
        if !findings.isEmpty, request.includes(.findings) {
            var table = ResultTable(
                title: "Findings and Results",
                columns: ["Date", "Record", "Category", "Finding"]
            )
            for event in findings.sorted(by: { $0.date < $1.date }) {
                table.rows.append(ResultRow(cells: [
                    event.date.medium,
                    event.title,
                    event.category.title,
                    event.summary.trimmingCharacters(in: .whitespacesAndNewlines),
                ]))
            }
            blocks.append(.table(table.droppingEmptyColumns()))
        }

        let diagnoses = events.flatMap { event in event.diagnoses.map { (event, $0) } }
        if !diagnoses.isEmpty, request.includes(.diagnoses) {
            var table = ResultTable(
                title: "All Diagnoses",
                columns: ["Date", "Diagnosis", "Code", "Status", "Record"]
            )
            for (event, diagnosis) in diagnoses.sorted(by: { $0.0.date < $1.0.date }) {
                table.rows.append(ResultRow(cells: [
                    event.date.medium,
                    diagnosis.name,
                    diagnosis.code ?? "—",
                    diagnosis.status.title,
                    event.title,
                ]))
            }
            blocks.append(.table(table.droppingEmptyColumns()))
        }

        let medications = events.flatMap { event in event.medications.map { (event, $0) } }
        if !medications.isEmpty, request.includes(.medications) {
            var table = ResultTable(
                title: "All Medications",
                columns: ["Date", "Medication", "Dose", "Frequency", "Ongoing"]
            )
            for (event, medication) in medications.sorted(by: { $0.0.date < $1.0.date }) {
                table.rows.append(ResultRow(cells: [
                    event.date.medium,
                    medication.name,
                    medication.dosage ?? "—",
                    medication.frequency ?? "—",
                    medication.isOngoing ? "Yes" : "—",
                ]))
            }
            blocks.append(.table(table.droppingEmptyColumns()))
        }

        return blocks
    }

    /// One record, in full.
    ///
    /// Everything the record holds appears, as labelled lines rather than as a
    /// table: records are not uniform — a vaccination knows a batch number, a
    /// consultation knows a diagnosis — and forcing them under one header would
    /// mean columns that are empty far more often than not. A line only exists
    /// when there is something to put in it, so nothing is missing and nothing
    /// is blank.
    private func recordBlocks(
        _ event: MedicalEvent,
        archive: Archive,
        request: DoctorReportRequest,
        sharedDocumentID: UUID?
    ) -> [PDFReport.Block] {
        var blocks: [PDFReport.Block] = [
            .subheading("\(event.date.formatted) — \(event.title)")
        ]

        // The category is dropped when the chronology already carries it for
        // every record; "Category: Vaccination" under "Hepatitis B Vaccination"
        // is a line that has never told anybody anything.
        blocks.append(.fields([
            ("Category", request.includes(.chronology) ? nil : event.category.title),
            ("Specialty", event.specialty?.title),
            ("Status", event.status.deservesLabel ? event.status.title : nil),
            ("Period", event.endDate.map { "\(event.date.formatted) – \($0.formatted)" }),
            ("Doctor", archive.doctor(for: event)?.name),
            ("Clinic", clinicDescription(for: event, archive: archive)),
            ("Diagnoses", event.diagnoses.isEmpty ? nil : event.diagnoses.map(describe).joined(separator: "\n")),
            ("Medications", event.medications.isEmpty ? nil : event.medications.map(describe).joined(separator: "\n")),
            ("Tags", archive.tags(ids: event.tagIDs).map(\.name).nilIfEmptyJoined),
            ("Documents", request.includes(.sourceDocuments)
                ? sourceDescription(for: event, archive: archive, sharedDocumentID: sharedDocumentID)
                : nil),
        ]))

        if let summary = event.summary.nilIfEmpty, !request.includes(.findings) {
            blocks.append(.body(summary))
        }

        if !event.vaccinations.isEmpty, !request.includes(.vaccinations) {
            blocks.append(.table(vaccinationTable(for: event).droppingEmptyColumns()))
        }

        // The tables are why this report is worth sending.
        for table in event.tables where !table.rows.isEmpty {
            blocks.append(.table(table))
        }

        for code in event.translations.keys.sorted() {
            guard let text = event.translations[code]?.nilIfEmpty else { continue }
            let language = Locale.current.localizedString(forLanguageCode: code)?.capitalized ?? code.uppercased()
            blocks.append(.fields([("In \(language)", text)]))
        }

        for note in event.notes {
            blocks.append(.fields([("Note", note.body)]))
        }

        blocks.append(.space(10))
        return blocks
    }

    private func clinicDescription(for event: MedicalEvent, archive: Archive) -> String? {
        guard let facility = archive.facility(for: event) else { return nil }
        return [facility.name, facility.location].compactMap(\.self).joined(separator: ", ")
    }

    private func describe(_ diagnosis: Diagnosis) -> String {
        var text = diagnosis.name
        if let code = diagnosis.code?.nilIfEmpty { text += " (\(code))" }
        if diagnosis.status != .active { text += " — \(diagnosis.status.title.lowercased())" }
        return text
    }

    private func describe(_ medication: Medication) -> String {
        var parts = [medication.name]
        if let detail = medication.summary.nilIfEmpty { parts.append(detail) }
        if medication.isOngoing { parts.append("ongoing") }
        return parts.joined(separator: " · ")
    }

    /// Which pages of what this record rests on — unless it rests on the one
    /// document the whole report already named.
    private func sourceDescription(
        for event: MedicalEvent,
        archive: Archive,
        sharedDocumentID: UUID?
    ) -> String? {
        var attachments = archive.attachments(for: event)
        if let sharedDocumentID {
            attachments.removeAll { $0.document.id == sharedDocumentID && $0.reference.pages.isWholeDocument }
        }
        guard !attachments.isEmpty else { return nil }
        return attachments.map { attachment in
            attachment.reference.pages.isWholeDocument
                ? attachment.document.displayName
                : "\(attachment.document.displayName), \(attachment.reference.pages.sentenceText)"
        }.joined(separator: "\n")
    }

    /// Everything a vaccination record knows, in the order a clinician reads it.
    private func vaccinationTable(for event: MedicalEvent) -> ResultTable {
        var table = ResultTable(
            title: "Vaccinations",
            columns: ["Vaccine", "Dose", "Manufacturer", "Batch", "Site", "Next due"]
        )
        for vaccination in event.vaccinations {
            table.rows.append(ResultRow(cells: [
                vaccination.name,
                vaccination.dose ?? "—",
                vaccination.manufacturer ?? "—",
                vaccination.batchNumber ?? "—",
                vaccination.site ?? "—",
                nextDueDescription(vaccination, on: event.date) ?? "—",
            ]))
        }
        return table
    }

    private func nextDueDescription(_ vaccination: Vaccination, on date: DateValue) -> String? {
        guard let due = vaccination.booster?.dueDate(after: date) else { return nil }
        return DateValue(due, precision: .day).medium
    }

    // MARK: - Source documents

    /// Copies out the pages the records cite, one file per distinct citation.
    ///
    /// Keyed by document *and* page range, not by record. Fifty records that all
    /// cite the same vaccination card produce one file, not fifty copies of it:
    /// a doctor handed fifty identical scans has been given nothing, and the
    /// package was a hundred megabytes of the same two pages.
    ///
    /// The report names each file where it cites it, so the mapping stays clear.
    private func writeSourceDocuments(
        archive: Archive,
        events: [MedicalEvent],
        into payload: URL
    ) throws {
        let fileManager = FileManager.default
        let folder = payload.appending(path: "Source Documents", directoryHint: .isDirectory)

        var written: Set<String> = []
        var wroteAny = false

        for event in events {
            for attachment in archive.attachments(for: event) {
                let key = "\(attachment.document.id.uuidString)#\(attachment.reference.pages.storedText)"
                guard !written.contains(key) else { continue }

                let source = libraryURL.appending(path: attachment.document.relativePath)
                guard fileManager.fileExists(atPath: source.path(percentEncoded: false)) else { continue }

                if !wroteAny {
                    try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
                    wroteAny = true
                }

                let name = Self.filename(for: attachment, sourceExtension: source.pathExtension)
                let pages = attachment.reference.pages

                if pages.isWholeDocument || attachment.document.kind != .pdf {
                    try? fileManager.removeItem(at: folder.appending(path: name))
                    try? fileManager.copyItem(at: source, to: folder.appending(path: name))
                } else {
                    try? extractPages(pages, from: source, to: folder.appending(path: name))
                }

                written.insert(key)
            }
        }
    }

    /// Named after the document, because that is what the file is. The page
    /// range distinguishes two extracts of the same original.
    static func filename(for attachment: AttachedDocument, sourceExtension: String) -> String {
        // Drop any extension the display name carries, or a document called
        // "Card.pdf" becomes "card-pdf.pdf".
        let base = (attachment.document.displayName as NSString).deletingPathExtension
        let stem = FileArchivePersistence.slug(from: base.nilIfEmpty ?? attachment.document.displayName)
        let ext = sourceExtension.isEmpty ? "pdf" : sourceExtension

        guard !attachment.reference.pages.isWholeDocument else { return "\(stem).\(ext)" }

        let pages = attachment.reference.pages.storedText.replacingOccurrences(of: ", ", with: "_")
        return "\(stem)-pages-\(pages).pdf"
    }

    /// Writes a new PDF containing only the cited pages. The source is opened
    /// read-only and never written back.
    private func extractPages(_ pages: PageSelection, from source: URL, to destination: URL) throws {
        guard let document = PDFDocument(url: source) else {
            throw ArchiveError.importFailed("Could not read \(source.lastPathComponent).")
        }

        let extract = PDFDocument()
        var index = 0
        for number in pages.pageNumbers {
            // Page numbers are one-based, as printed on the page.
            guard number >= 1, number <= document.pageCount,
                  let page = document.page(at: number - 1)
            else { continue }
            extract.insert(page, at: index)
            index += 1
        }

        guard index > 0 else { return }
        try? FileManager.default.removeItem(at: destination)
        extract.write(to: destination)
    }

    // MARK: - Read me

    /// Describes the package that was actually made.
    ///
    /// It used to describe the package the code was written to make — listing a
    /// chronology whether or not one was printed, and once announcing "0 result
    /// tables transcribed by the patient", which is a sentence about nothing.
    private func writeReadMe(
        archive: Archive,
        request: DoctorReportRequest,
        into payload: URL
    ) throws {
        let included = parts(archive: archive, request: request)
            .filter { request.includes($0.section) }

        var lines = [
            "\(archive.patient.displayName) — Medical Report",
            scopeDescription(request),
            "Prepared \(Date.now.formatted(date: .long, time: .shortened))",
            "",
            "Doctor Report.pdf",
        ]

        for part in included where part.section != .sourceDocuments {
            lines.append("    \(part.section.title) — \(part.detail)")
        }

        if let documents = included.first(where: { $0.section == .sourceDocuments }) {
            lines.append("")
            lines.append("Source Documents/ — \(documents.detail)")
            lines.append("    The original pages the records cite, exactly as scanned.")
            lines.append("    Where a record cites part of a longer document, only those")
            lines.append("    pages are included; the filename says which.")
        }

        lines.append(contentsOf: [
            "",
            "This package was produced by Medical, a personal medical archive.",
            "It is not an electronic medical record and carries no clinical",
            "authority of its own — the source documents are the evidence.",
        ])

        try Data(lines.joined(separator: "\n").utf8)
            .write(to: payload.appending(path: "Read Me.txt"), options: .atomic)
    }
}
