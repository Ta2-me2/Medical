import Foundation
import Observation

/// Search and filter state for the Notes screen.
@Observable
final class NotesViewModel {

    var searchText = ""
    var categoryFilter: EventCategory?

    func records(from archive: Archive) -> [NoteRecord] {
        var records = archive.allNotes

        if let categoryFilter {
            records = records.filter { $0.event.category == categoryFilter }
        }

        if let query = searchText.nilIfEmpty?.lowercased() {
            records = records.filter {
                $0.note.body.lowercased().contains(query)
                    || $0.note.displayTitle.lowercased().contains(query)
                    || $0.event.title.lowercased().contains(query)
            }
        }

        return records
    }
}
