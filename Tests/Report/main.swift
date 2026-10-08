import Foundation
import PDFKit

// End-to-end check of the two things that leave the archive: the Doctor Report
// and a library backup. Both are built for real, on disk, and read back.

var failures = 0
func check(_ label: String, _ condition: Bool) {
    print(condition ? "  PASS  \(label)" : "  FAIL  \(label)")
    if !condition { failures += 1 }
}
func section(_ title: String) { print("\n\(title)") }

let root = FileManager.default.temporaryDirectory
    .appending(path: "medicalid-report-test-\(UUID().uuidString)", directoryHint: .isDirectory)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }

// A library with one ten-page source document.
let library = root.appending(path: "Library", directoryHint: .isDirectory)
let originals = library.appending(path: "Originals/2009", directoryHint: .isDirectory)
try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)

let sourcePDF = originals.appending(path: "card.pdf")
var sourcePages: [PDFReport.Block] = []
for page in 1...10 {
    if page > 1 { sourcePages.append(.pageBreak) }
    sourcePages.append(.title("Card page \(page)"))
    sourcePages.append(.body("Body of page \(page)."))
}
try PDFReport.render(sourcePages, title: "Card", to: sourcePDF)
check("the ten-page source was written", PDFDocument(url: sourcePDF)?.pageCount == 10)

let document = StoredDocument(
    originalFilename: "card.pdf",
    relativePath: "Originals/2009/card.pdf",
    contentHash: "hash",
    byteSize: 1000,
    kind: .pdf,
    pageCount: 10,
    title: "Childhood Medical Card"
)

var archive = Archive()
archive.patient = Patient(
    fullName: "Test Patient",
    dateOfBirth: Date(timeIntervalSince1970: 0),
    bloodType: .aPositive,
    allergies: [Allergy(substance: "Penicillin", severity: .severe, reaction: "Urticaria")],
    alerts: [MedicalAlert(text: "Severe penicillin allergy", level: .critical)],
    summary: "Otherwise well."
)
archive.addDocuments([document])

var lab = ResultTable(title: "Blood panel", columns: ["Test", "Result", "Reference"])
for index in 1...40 {
    lab.rows.append(ResultRow(
        cells: ["Analyte \(index)", "\(index).0 units", "0-100"],
        isAbnormal: index % 7 == 0
    ))
}

var event = MedicalEvent(
    date: DateValue(Date(timeIntervalSince1970: 1_200_000_000), precision: .day),
    category: .laboratory,
    title: "Annual blood panel",
    summary: "Everything within range except the flagged rows."
)
event.attachments = [DocumentReference(documentID: document.id, pages: PageSelection.parse("2-3")!)]
event.tables = [lab]
archive.upsert(event)

// MARK: - Doctor Report

section("Doctor Report")

let reportZip = root.appending(path: "Doctor Report.zip")
let report = DoctorReport(libraryURL: library)
try report.write(archive, request: DoctorReportRequest(), to: reportZip)

check("a zip was produced", FileManager.default.fileExists(atPath: reportZip.path(percentEncoded: false)))

let unpacked = root.appending(path: "unpacked", directoryHint: .isDirectory)
try Zip.expand(archive: reportZip, into: unpacked)

let payload = unpacked.appending(path: "Doctor Report", directoryHint: .isDirectory)
let reportPDF = payload.appending(path: "Doctor Report.pdf")
check("the report PDF is inside", FileManager.default.fileExists(atPath: reportPDF.path(percentEncoded: false)))
check(
    "the read me is inside",
    FileManager.default.fileExists(atPath: payload.appending(path: "Read Me.txt").path(percentEncoded: false))
)

if let rendered = PDFDocument(url: reportPDF) {
    // Forty table rows cannot fit on one page: the table must have broken across.
    check("the report paginated", rendered.pageCount >= 2)

    let text = (0..<rendered.pageCount).compactMap { rendered.page(at: $0)?.string }.joined(separator: "\n")
    check("the patient is named", text.contains("Test Patient"))
    check("the alert is carried", text.contains("Severe penicillin allergy"))
    check("the chronology is there", text.contains("Chronology"))
    check("the record title is there", text.contains("Annual blood panel"))
    check("the table header is there", text.contains("Reference"))
    check("the first table row is there", text.contains("Analyte 1"))
    check("the last table row is there", text.contains("Analyte 40"))
    check("a broken table repeats its header", text.components(separatedBy: "Reference").count - 1 >= 2)
    check("the cited pages are named", text.contains("pages 2–3"))
    check("the text is selectable, not an image", text.count > 400)
} else {
    check("the report PDF could be opened", false)
}

let sources = payload.appending(path: "Source Documents", directoryHint: .isDirectory)
let sourceFiles = ((try? FileManager.default.contentsOfDirectory(atPath: sources.path(percentEncoded: false))) ?? [])
    .filter { $0.hasSuffix(".pdf") }
check("one source file was written", sourceFiles.count == 1)

if let first = sourceFiles.first {
    check("its name says which pages", first.contains("2-3"))
    let extracted = PDFDocument(url: sources.appending(path: first))
    check("only the cited pages were copied", extracted?.pageCount == 2)
    let extractedText = (0..<(extracted?.pageCount ?? 0))
        .compactMap { extracted?.page(at: $0)?.string }.joined()
    check("they are the right pages", extractedText.contains("Card page 2") && extractedText.contains("Card page 3"))
    check("and no others", !extractedText.contains("Card page 5"))
}

check("the original was not touched", PDFDocument(url: sourcePDF)?.pageCount == 10)

// MARK: - Library backup

section("Library backup")

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
encoder.dateEncodingStrategy = .iso8601
try encoder.encode(archive).write(to: library.appending(path: "Archive.json"))

let backup = root.appending(path: "Backup.zip")
try LibraryBackup.export(from: library, to: backup)
check("a backup was produced", FileManager.default.fileExists(atPath: backup.path(percentEncoded: false)))

let restoreParent = root.appending(path: "restored", directoryHint: .isDirectory)
try FileManager.default.createDirectory(at: restoreParent, withIntermediateDirectories: true)
let restored = try LibraryBackup.restore(from: backup, into: restoreParent)

check(
    "the restored folder holds the archive file",
    FileManager.default.fileExists(atPath: restored.appending(path: "Archive.json").path(percentEncoded: false))
)
check(
    "the originals came with it",
    PDFDocument(url: restored.appending(path: "Originals/2009/card.pdf"))?.pageCount == 10
)

let summary = LibraryBackup.inspect(restored)
check("the backup describes itself", summary?.patientName == "Test Patient")
check("with the right counts", summary?.eventCount == 1 && summary?.documentCount == 1)

// Restoring twice must not overwrite the first restore.
let second = try LibraryBackup.restore(from: backup, into: restoreParent)
check("a second restore lands beside the first", second != restored)

// A zip that is not a library is refused rather than half-restored.
let notALibrary = root.appending(path: "junk", directoryHint: .isDirectory)
try FileManager.default.createDirectory(at: notALibrary, withIntermediateDirectories: true)
try Data("hello".utf8).write(to: notALibrary.appending(path: "readme.txt"))
let junkZip = root.appending(path: "junk.zip")
try Zip.compress(folder: notALibrary, to: junkZip)
var refused = false
do {
    _ = try LibraryBackup.restore(from: junkZip, into: restoreParent)
} catch {
    refused = true
}
check("a zip that is not a library is refused", refused)

print("")
if failures == 0 {
    print("all checks passed")
} else {
    print("\(failures) check(s) failed")
    exit(1)
}
