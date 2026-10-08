import Foundation
import Observation

/// Filter and selection state for the inbox.
@Observable
final class InboxViewModel {

    /// The inbox exists for backlogs — someone scans two decades of paperwork in
    /// an afternoon and files it over months. The default view is therefore what
    /// is still outstanding, not everything ever imported.
    enum Scope: String, CaseIterable, Identifiable {
        case notProcessed
        case used
        case archived
        case all

        var id: String { rawValue }

        var title: String {
            switch self {
            case .notProcessed: "Not Processed"
            case .used: "Used"
            case .archived: "Archived"
            case .all: "All"
            }
        }

        var status: DocumentStatus? {
            switch self {
            case .notProcessed: .notProcessed
            case .used: .used
            case .archived: .archived
            case .all: nil
            }
        }
    }

    var scope: Scope = .notProcessed
    var searchText = ""
    var selection: Set<UUID> = []

    func records(from archive: Archive) -> [DocumentRecord] {
        var records = archive.allDocuments

        if let status = scope.status {
            records = records.filter { $0.status == status }
        }
        if let query = searchText.nilIfEmpty?.lowercased() {
            records = records.filter { $0.document.displayName.lowercased().contains(query) }
        }

        // Oldest first: a backlog is worked from the bottom of the pile.
        return records.sorted { $0.document.importedAt < $1.document.importedAt }
    }

    /// Counted from one pass over the archive rather than by asking every
    /// document, for every scope, which records cite it — four numbers used to
    /// cost four scans of everything.
    func count(of scope: Scope, in archive: Archive) -> Int {
        guard let status = scope.status else { return archive.documents.count }
        return archive.documentStatusCounts[status] ?? 0
    }
}
