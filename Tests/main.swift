import Foundation

var failures = 0

func check(_ label: String, _ condition: Bool) {
    print(condition ? "  PASS  \(label)" : "  FAIL  \(label)")
    if !condition { failures += 1 }
}

func section(_ title: String) { print("\n\(title)") }

let encoder: JSONEncoder = {
    let e = JSONEncoder()
    e.outputFormatting = [.prettyPrinted, .sortedKeys]
    e.dateEncodingStrategy = .iso8601
    return e
}()

let decoder: JSONDecoder = {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    return d
}()

func document(_ name: String) -> StoredDocument {
    StoredDocument(
        originalFilename: name,
        relativePath: "Originals/2020/\(name)",
        contentHash: "hash-\(name)",
        byteSize: 1024,
        kind: .pdf,
        pageCount: 12
    )
}

// MARK: - Documents belong to the library, and may be cited more than once

section("Document library")

var archive = Archive()
let scan = document("discharge.pdf")
archive.addDocuments([scan])

check("a new document starts in the inbox", archive.status(of: scan) == .notProcessed)
check("inbox count sees it", archive.inboxCount == 1)

var surgery = MedicalEvent(date: DateValue(Date(), precision: .day), title: "Operation")
surgery.attachments = [DocumentReference(documentID: scan.id, pages: PageSelection.parse("15-17")!)]
archive.upsert(surgery)

check("citing it marks it used", archive.status(of: scan) == .used)
check("inbox is empty again", archive.inboxCount == 0)
check("used in exactly one record", archive.events(using: scan.id).count == 1)

var followUp = MedicalEvent(date: DateValue(Date(), precision: .day), title: "Follow-up")
followUp.attachments = [DocumentReference(documentID: scan.id, pages: PageSelection.parse("20-22")!)]
archive.upsert(followUp)

check("the same file serves two records", archive.events(using: scan.id).count == 2)
check("each record cites its own pages",
      Set(archive.citations(of: scan.id).map(\.pages.storedText)) == ["15-17", "20-22"])
check("and is stored only once", archive.documents.count == 1)
check("the record reads 'used in 2'", archive.record(for: scan).usageDescription == "Used in 2 medical records")

archive.removeEvent(id: followUp.id)
check("dropping one record leaves it used", archive.status(of: scan) == .used)
archive.removeEvent(id: surgery.id)
check("dropping the last returns it to the inbox", archive.status(of: scan) == .notProcessed)
check("the file itself is never removed", archive.documents.count == 1)

archive.setArchived(true, forDocument: scan.id)
check("archiving takes it out of the inbox", archive.status(of: scan) == .archived)
check("inbox count agrees", archive.inboxCount == 0)

// MARK: - Migration from the version that nested documents inside events

section("Migration from format 1")

let nestedID = UUID()
let orphanID = UUID()
let legacy = """
{
  "formatVersion": 1,
  "archiveID": "\(UUID().uuidString)",
  "createdAt": "2026-01-01T00:00:00Z",
  "patient": { "id": "\(UUID().uuidString)", "fullName": "John Appleseed" },
  "events": [
    {
      "id": "\(UUID().uuidString)",
      "date": { "date": "2016-05-03", "precision": "day" },
      "title": "Left knee arthroscopy",
      "category": "surgery",
      "documents": [
        {
          "id": "\(nestedID.uuidString)",
          "originalFilename": "arthroscopy.pdf",
          "relativePath": "Originals/2016/x-arthroscopy.pdf",
          "contentHash": "abc123",
          "byteSize": 17000,
          "kind": "pdf",
          "importedAt": "2026-08-07T09:00:00Z"
        }
      ],
      "notes": [{ "id": "\(UUID().uuidString)", "body": "Penicillin avoided." }]
    }
  ],
  "unfiledDocuments": [
    {
      "id": "\(orphanID.uuidString)",
      "originalFilename": "loose-scan.pdf",
      "relativePath": "Originals/2020/y-loose.pdf",
      "contentHash": "def456",
      "byteSize": 9000,
      "kind": "pdf",
      "importedAt": "2026-08-07T10:00:00Z"
    }
  ],
  "doctors": [], "facilities": [], "tags": []
}
"""

let migrated = try decoder.decode(Archive.self, from: Data(legacy.utf8))

check("the event survives", migrated.events.count == 1)
check("its note survives", migrated.events[0].notes.count == 1)
check("both documents are in the library", migrated.documents.count == 2)
check("the nested document was lifted, not lost", migrated.document(id: nestedID) != nil)
check("the loose document was adopted", migrated.document(id: orphanID) != nil)
check("the event now cites its document", migrated.events[0].attachments.map(\.documentID) == [nestedID])
check("a citation without pages means the whole document",
      migrated.events[0].attachments[0].pages.isWholeDocument)
check("the lifted document reads as used", migrated.status(of: migrated.document(id: nestedID)!) == .used)
check("the loose one lands in the inbox", migrated.status(of: migrated.document(id: orphanID)!) == .notProcessed)
check("page count is unknown, not zero", migrated.document(id: nestedID)!.pageCount == nil)
check("format version is stamped forward", migrated.formatVersion == Archive.currentFormatVersion)
check("the date keeps its year", migrated.events[0].date.year == 2016)

// Migrating twice must be a no-op: the app loads, saves, and loads again.
let rewritten = try decoder.decode(Archive.self, from: try encoder.encode(migrated))
check("a second load changes nothing", rewritten.documents.count == 2)
check("citations still resolve", rewritten.events[0].attachments.map(\.documentID) == [nestedID])

// MARK: - A reference to a document that is not in the library

section("Broken references")

let dangling = """
{
  "formatVersion": 2,
  "patient": { "fullName": "X" },
  "documents": [],
  "events": [{
    "id": "\(UUID().uuidString)",
    "date": { "date": "2020-01-01", "precision": "day" },
    "title": "Ghost",
    "attachments": [{"id": "\(UUID().uuidString)", "documentID": "\(UUID().uuidString)", "pages": "3-4"}]
  }],
  "doctors": [], "facilities": [], "tags": []
}
"""
let cleaned = try decoder.decode(Archive.self, from: Data(dangling.utf8))
check("a phantom attachment is dropped", cleaned.events[0].attachments.isEmpty)
check("the record itself is kept", cleaned.events.count == 1)

// MARK: - Status, pinning and tags round-trip

section("Round trip")

var round = Archive()
var event = MedicalEvent(date: DateValue(Date(), precision: .month), title: "Consult")
round.upsert(event)
event = round.events[0]
round.setStatus(.significant, forEvent: event.id)
round.setPinned(true, forEvent: event.id)
let tagIDs = round.resolveTags(named: ["knee", "surgery", "knee"])
check("duplicate tag names resolve to one tag", round.tags.count == 2)
check("resolving returns an id per name given", tagIDs.count == 3)

let restored = try decoder.decode(Archive.self, from: try encoder.encode(round))
check("status survives", restored.events[0].status == .significant)
check("pin survives", restored.events[0].isPinned == true)
check("month precision survives", restored.events[0].date.precision == .month)

// MARK: - Page ranges

section("Page selections")

check("a single page parses", PageSelection.parse("58")?.storedText == "58")
check("a range parses", PageSelection.parse("15-17")?.storedText == "15-17")
check("an en dash is accepted", PageSelection.parse("15–17")?.storedText == "15-17")
check("several parts parse", PageSelection.parse("15-17, 42-43, 58")?.storedText == "15-17, 42-43, 58")
check("overlaps merge", PageSelection.parse("1-3, 2-5")?.storedText == "1-5")
check("adjacent ranges merge", PageSelection.parse("1-2, 3-4")?.storedText == "1-4")
check("reversed bounds are righted", PageSelection.parse("17-15")?.storedText == "15-17")
check("empty means the whole document", PageSelection.parse("")?.isWholeDocument == true)
check("nonsense is rejected", PageSelection.parse("fifteen") == nil)
check("page zero is rejected", PageSelection.parse("0-3") == nil)
check("page count is counted", PageSelection.parse("15-17, 58")?.pageCount == 4)
check("pages are listed in order", PageSelection.parse("58, 15-16")?.pageNumbers == [15, 16, 58])
check("membership works", PageSelection.parse("15-17")?.contains(page: 16) == true)
check("membership excludes", PageSelection.parse("15-17")?.contains(page: 18) == false)

let citedRound = try decoder.decode(
    DocumentReference.self,
    from: try encoder.encode(DocumentReference(documentID: UUID(), pages: PageSelection.parse("42-43")!))
)
check("a citation round-trips its pages", citedRound.pages.storedText == "42-43")

// MARK: - Result tables

section("Result tables")

var lab = ResultTable(title: "Blood panel", columns: ["Test", "Result", "Reference"])
lab.rows.append(ResultRow(cells: ["Haemoglobin", "150 g/L", "130–170"]))
lab.rows.append(ResultRow(cells: ["Vitamin D", "42 nmol/L", "75–200"], isAbnormal: true))
check("abnormal rows are counted", lab.abnormalCount == 1)

lab.addColumn(named: "Note")
check("adding a column widens every row", lab.rows.allSatisfy { $0.cells.count == 4 })
lab.removeColumn(at: 3)
check("removing a column narrows every row", lab.rows.allSatisfy { $0.cells.count == 3 })

var ragged = ResultTable(columns: ["A", "B", "C"])
ragged.rows = [ResultRow(cells: ["only one"])]
ragged.squareUp()
check("ragged rows are squared up", ragged.rows[0].cells.count == 3)
check("cells read safely out of range", ragged.cell(row: 0, column: 9) == "")

var withTable = Archive()
var tabled = MedicalEvent(date: DateValue(Date(), precision: .day), title: "Lab")
tabled.tables = [lab]
withTable.upsert(tabled)
let tableRound = try decoder.decode(Archive.self, from: try encoder.encode(withTable))
check("tables survive a round trip", tableRound.events[0].tables.first?.rows.count == 2)
check("the abnormal mark survives", tableRound.events[0].tables.first?.rows[1].isAbnormal == true)
check("tables are searchable", tabled.searchableText.contains("Haemoglobin"))

// MARK: - Archived documents stay findable

section("Document archive")

var withArchived = Archive()
let paperwork = document("insurance.pdf")
withArchived.addDocuments([paperwork])
withArchived.setArchived(true, forDocument: paperwork.id)
check("archived documents leave the inbox", withArchived.inboxCount == 0)
check("archived documents have their own list", withArchived.archivedDocuments.count == 1)
check("archived documents stay in the library", withArchived.allDocuments.count == 1)
check("and stay findable by search",
      SearchService.search("insurance", in: withArchived).documents.count == 1)

// MARK: - Booster schedules

section("Vaccination boosters")

func vaccine(_ name: String, months: Int?, on date: DateValue, dose: String? = nil) -> MedicalEvent {
    var event = MedicalEvent(date: date, category: .vaccination, title: name)
    event.vaccinations = [
        Vaccination(name: name, dose: dose, booster: months.map { BoosterSchedule(afterMonths: $0) })
    ]
    return event
}

func day(_ y: Int, _ m: Int, _ d: Int) -> DateValue {
    DateValue(Calendar.current.date(from: DateComponents(year: y, month: m, day: d))!, precision: .day)
}

var shots = Archive()
shots.upsert(vaccine("Pneumococcal", months: 120, on: day(2020, 3, 1), dose: "1"))
let asOf = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 10))!

check("a dose with a schedule becomes due", shots.vaccinationsDue(asOf: asOf).count == 1)
check("ten years after the dose",
      shots.vaccinationsDue(asOf: asOf).first.map { Calendar.current.component(.year, from: $0.dueOn) } == 2030)
check("not yet overdue", shots.vaccinationsDue(asOf: asOf).first?.isOverdue(asOf: asOf) == false)

// A second dose supersedes the first, wherever it landed.
shots.upsert(vaccine("Pneumococcal", months: 120, on: day(2024, 6, 1), dose: "2"))
let due = shots.vaccinationsDue(asOf: asOf)
check("a second dose leaves only one outstanding answer", due.count == 1)
check("counted from the later dose", Calendar.current.component(.year, from: due[0].dueOn) == 2034)
check("and it names that dose", due[0].doseLabel == "2")

// Given late rather than early: the interval still runs from what happened.
var late = Archive()
late.upsert(vaccine("Tetanus", months: 120, on: day(2000, 1, 1)))
late.upsert(vaccine("Tetanus", months: 120, on: day(2015, 1, 1)))
check("a late dose pushes the next one out",
      Calendar.current.component(.year, from: late.vaccinationsDue(asOf: asOf)[0].dueOn) == 2025)
check("and it reads as overdue", late.vaccinationsDue(asOf: asOf)[0].isOverdue(asOf: asOf))

// Spelling differences must not create two schedules for one vaccine.
var spelled = Archive()
spelled.upsert(vaccine("Influenza", months: 12, on: day(2024, 1, 1)))
spelled.upsert(vaccine("influenza", months: 12, on: day(2025, 1, 1)))
check("case differences are one series", spelled.vaccinationsDue(asOf: asOf).count == 1)

// No schedule means no reminder.
var silent = Archive()
silent.upsert(vaccine("Hepatitis B", months: nil, on: day(2019, 5, 1)))
check("a dose with no schedule is silent", silent.vaccinationsDue(asOf: asOf).isEmpty)

// A fixed date wins over an interval and does not move.
var fixed = Archive()
var onDateEvent = MedicalEvent(date: day(2024, 1, 1), category: .vaccination, title: "Rabies")
onDateEvent.vaccinations = [
    Vaccination(name: "Rabies", booster: BoosterSchedule(onDate: day(2027, 9, 15)))
]
fixed.upsert(onDateEvent)
check("a named date is used as given",
      fixed.vaccinationsDue(asOf: asOf).first.map {
          Calendar.current.dateComponents([.year, .month], from: $0.dueOn)
      } == DateComponents(year: 2027, month: 9))

// The dashboard window keeps distant doses off the dashboard.
check("distant doses are out of the near window",
      shots.vaccinationsNeedingAttention(within: 12, asOf: asOf).isEmpty)
check("overdue ones are always in it",
      late.vaccinationsNeedingAttention(within: 12, asOf: asOf).count == 1)

let boosterRound = try decoder.decode(Archive.self, from: try encoder.encode(shots))
check("schedules survive a round trip",
      boosterRound.events.contains { $0.vaccinations.first?.booster?.afterMonths == 120 })

// MARK: - Doses gathered per vaccine

section("Vaccination series")

/// A record titled one way, carrying a dose of a differently named product —
/// which is the ordinary case: one disease, many product names over a lifetime.
func course(_ title: String, vaccine name: String, months: Int?, on date: DateValue,
            dose: String? = nil) -> MedicalEvent {
    var event = MedicalEvent(date: date, category: .vaccination, title: title)
    event.vaccinations = [
        Vaccination(name: name, dose: dose, booster: months.map { BoosterSchedule(afterMonths: $0) })
    ]
    return event
}

var grouped = Archive()
grouped.upsert(vaccine("Tetanus Vaccination", months: 120, on: day(2004, 3, 1), dose: "1"))
grouped.upsert(vaccine("Tetanus Vaccination", months: 120, on: day(2014, 3, 1), dose: "2"))
grouped.upsert(vaccine("Hepatitis B Vaccination", months: nil, on: day(2019, 5, 1)))

var series = grouped.vaccinationSeries
check("one entry per course, not per dose", series.count == 2)
check("in alphabetical order",
      series.map(\.name) == ["Hepatitis B Vaccination", "Tetanus Vaccination"])
check("every dose is kept", series.first { $0.name == "Tetanus Vaccination" }?.doseCount == 2)
check("newest dose first",
      series.first { $0.name == "Tetanus Vaccination" }?.latest?.vaccination.dose == "2")
check("and the oldest is still reachable",
      series.first { $0.name == "Tetanus Vaccination" }?.earliest?.vaccination.dose == "1")
check("a series spans the years its doses do",
      series.first { $0.name == "Tetanus Vaccination" }
        .map { ($0.earliest?.date.year, $0.latest?.date.year) } ?? (nil, nil) == (2004, 2014))

// The point of keying on the title: one disease, two products, one history.
var tuberculosis = Archive()
tuberculosis.upsert(course("Tuberculosis Vaccination", vaccine: "BCG", months: 84, on: day(2000, 4, 1)))
tuberculosis.upsert(course("Tuberculosis Vaccination", vaccine: "BCG-M", months: 84, on: day(2010, 4, 1)))
check("different products under one title are one course",
      tuberculosis.vaccinationSeries.count == 1)
check("titled by the record, not by the product",
      tuberculosis.vaccinationSeries.first?.name == "Tuberculosis Vaccination")
check("both doses are in it", tuberculosis.vaccinationSeries.first?.doseCount == 2)

let tbDue = tuberculosis.vaccinationsDue(asOf: asOf)
check("and they share one booster clock", tbDue.count == 1)
check("counted from the later product",
      Calendar.current.component(.year, from: tbDue[0].dueOn) == 2017)

// The converse: one product used against different things stays apart.
var shared = Archive()
shared.upsert(course("Measles Vaccination", vaccine: "MMR", months: nil, on: day(2011, 2, 1)))
shared.upsert(course("Mumps Vaccination", vaccine: "MMR", months: nil, on: day(2011, 2, 1)))
check("the same product under two titles is two courses", shared.vaccinationSeries.count == 2)

// Spelling of the title must not start a second course.
var spelledSeries = Archive()
spelledSeries.upsert(vaccine("Influenza Vaccination", months: 12, on: day(2024, 1, 1)))
spelledSeries.upsert(vaccine("influenza vaccination", months: 12, on: day(2025, 1, 1)))
let oneSeries = spelledSeries.vaccinationSeries
check("case differences group together", oneSeries.count == 1)
check("under the newest record's spelling", oneSeries.first?.name == "influenza vaccination")
check("grouping matches what the reminders call one course",
      oneSeries.count == spelledSeries.vaccinationsDue(asOf: asOf).count)

// Two vaccines given at one visit are one visit, not a course superseding
// itself — neither reminder may be silently dropped for the other.
var visit = Archive()
var travel = MedicalEvent(date: day(2020, 6, 1), category: .vaccination, title: "Travel clinic")
travel.vaccinations = [
    Vaccination(name: "Yellow Fever", booster: BoosterSchedule(afterMonths: 120)),
    Vaccination(name: "Typhoid", booster: BoosterSchedule(afterMonths: 36))
]
visit.upsert(travel)
let visitDue = visit.vaccinationsDue(asOf: asOf)
check("a visit with two vaccines yields one reminder", visitDue.count == 1)
check("at the earlier of the two dates, never the later",
      Calendar.current.component(.year, from: visitDue[0].dueOn) == 2023)

// A dose recorded outside a vaccination record still belongs to its record.
var mixed = Archive()
var checkup = MedicalEvent(date: day(2022, 9, 9), category: .consultation, title: "Travel clinic")
checkup.vaccinations = [Vaccination(name: "Yellow Fever")]
mixed.upsert(checkup)
check("a dose recorded outside a vaccination record still counts",
      mixed.vaccinationSeries.first?.name == "Travel clinic")

check("an archive with no doses has no series", Archive().vaccinationSeries.isEmpty)

// MARK: - Removing documents

section("Removing documents")

var removable = Archive()
let junk = document("holiday-photo.pdf")
removable.addDocuments([junk])
var citing = MedicalEvent(date: day(2020, 1, 1), title: "Consult")
citing.attachments = [DocumentReference(documentID: junk.id)]
removable.upsert(citing)

check("it starts cited", removable.events(using: junk.id).count == 1)
removable.removeDocument(id: junk.id)
check("the document is gone", removable.document(id: junk.id) == nil)
check("the citation went with it", removable.events[0].attachments.isEmpty)
check("the record itself stays", removable.events.count == 1)

// MARK: - Generated tables drop what nothing filled in

section("Table trimming")

var wide = ResultTable(
    title: "Vaccinations",
    columns: ["Date", "Vaccine", "Manufacturer", "Batch", "Site"],
    rows: [
        ResultRow(cells: ["Mar 2004", "BCG", "—", "443", "—"]),
        ResultRow(cells: ["May 2004", "OPV", "", "672", "—"]),
    ]
)
var trimmed = wide.droppingEmptyColumns()
check("empty columns go", trimmed.columns == ["Date", "Vaccine", "Batch"])
check("rows lose the same cells", trimmed.rows[0].cells == ["Mar 2004", "BCG", "443"])
check("rows stay aligned to the header",
      trimmed.rows.allSatisfy { $0.cells.count == trimmed.columns.count })

wide.rows[0].cells[2] = "Microgen"
check("a column with one value is kept",
      wide.droppingEmptyColumns().columns.contains("Manufacturer"))

let full = ResultTable(
    columns: ["Test", "Result"],
    rows: [ResultRow(cells: ["Haemoglobin", "14.2"])]
)
check("a table with nothing to drop is unchanged", full.droppingEmptyColumns() == full)

let allBlank = ResultTable(
    columns: ["Date", "A", "B"],
    rows: [ResultRow(cells: ["2020", "—", ""])]
)
check("the key column survives even when the rest is empty",
      allBlank.droppingEmptyColumns().columns == ["Date"])

let single = ResultTable(columns: ["Only"], rows: [ResultRow(cells: ["—"])])
check("a one-column table is never emptied", single.droppingEmptyColumns().columns == ["Only"])

checkLibraryLocation()
await checkLibraryDirectory()
await checkLibraryRestore()
checkReportSections()
checkFirstAidKit()
checkDocumentUsage()

// The checks that move libraries around write `libraryFolderPath` through
// UserDefaults, as the application does. The domain is removed by this process,
// the one that created it — cfprefsd keeps it cached, and deleting the file from
// outside only has it written straight back a moment later.
let defaultsDomain = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
UserDefaults.standard.removePersistentDomain(forName: defaultsDomain)

print("")
if failures == 0 {
    print("all checks passed")
} else {
    print("\(failures) check(s) failed")
    exit(1)
}
