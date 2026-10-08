import Foundation
import Observation

/// Bringing files into the library.
///
/// Import does one thing: it copies originals in and puts them in the inbox.
/// It asks no questions, because the answer to "what is this document" is not
/// available while a hundred and fifty scans are still being read off a drive —
/// and a wizard that demands one per file makes bulk import impossible.
///
/// It has no screen of its own. Importing is the act of putting something in the
/// inbox, so it happens on the inbox, and a separate destination for it was one
/// step of navigation that never earned its place.
@Observable
final class DocumentImporter {

    var isImporting = false
    var progress: Double = 0
    var failure: String?

    /// How many documents landed in the inbox on the last run, for the message
    /// that appears afterwards. `nil` when nothing has been imported yet.
    var importedCount: Int?

    func dismissResult() {
        importedCount = nil
        failure = nil
    }

    /// Copies every chosen file into the library.
    ///
    /// Files are added one at a time rather than all-or-nothing: with a large
    /// batch, losing ninety-nine good imports because the hundredth was
    /// unreadable would be the wrong trade. Whatever failed is reported and the
    /// rest are kept.
    func importFiles(_ files: [URL], into store: ArchiveStore) async {
        guard !files.isEmpty, !isImporting else { return }

        isImporting = true
        failure = nil
        progress = 0
        defer { isImporting = false }

        var stored: [StoredDocument] = []
        var failures: [String] = []

        // A document has no medical date yet — nobody has said what it is. It is
        // filed under the year it arrived, and moves nowhere on disk when a
        // record later gives it a date; only the record carries that.
        let year = Calendar.current.component(.year, from: .now)

        for (index, url) in files.enumerated() {
            do {
                stored.append(try await store.storeOriginal(from: url, year: year, title: nil))
            } catch {
                failures.append(url.lastPathComponent)
            }
            progress = Double(index + 1) / Double(files.count)
        }

        if !stored.isEmpty {
            store.update { $0.addDocuments(stored) }
            await store.saveNow()
        }

        importedCount = stored.count

        if !failures.isEmpty {
            failure = "Could not import \(failures.count) of \(failures.count + stored.count): \(failures.prefix(3).joined(separator: ", "))"
        }
    }
}
