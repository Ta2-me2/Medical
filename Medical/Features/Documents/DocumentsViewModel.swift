import Foundation
import Observation

/// Filtering, sorting and layout state for the document library.
@Observable
final class DocumentsViewModel {

    enum Layout: String, CaseIterable, Identifiable {
        case list
        case grid

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .list: "list.bullet"
            case .grid: "square.grid.2x2"
            }
        }

        var title: String {
            switch self {
            case .list: "as List"
            case .grid: "as Grid"
            }
        }
    }

    enum SortOrder: String, CaseIterable, Identifiable {
        case dateNewest
        case dateOldest
        case importedNewest
        case name
        case size
        case pages

        var id: String { rawValue }

        var title: String {
            switch self {
            case .dateNewest: "Newest First"
            case .dateOldest: "Oldest First"
            case .importedNewest: "Recently Imported"
            case .name: "Name"
            case .size: "Size"
            case .pages: "Page Count"
            }
        }
    }

    var layout: Layout = .list
    var sortOrder: SortOrder = .dateNewest
    var searchText = ""
    var statuses = InclusionFilter<DocumentStatus>()
    var categories = InclusionFilter<EventCategory>()
    var kinds = InclusionFilter<StoredDocument.Kind>()
    var selection: UUID?

    var isFiltered: Bool {
        statuses.isFiltering || categories.isFiltering || kinds.isFiltering
    }

    func clearFilters() {
        statuses.clear()
        categories.clear()
        kinds.clear()
    }

    func records(from archive: Archive) -> [DocumentRecord] {
        var records = archive.allDocuments

        if statuses.isFiltering {
            records = records.filter { statuses.allows($0.status) }
        }
        if categories.isFiltering {
            // A document counts as matching when any record citing it does.
            records = records.filter { record in
                record.events.contains { categories.allows($0.category) }
            }
        }
        if kinds.isFiltering {
            records = records.filter { kinds.allows($0.document.kind) }
        }
        if let query = searchText.nilIfEmpty?.lowercased() {
            records = records.filter { record in
                record.document.displayName.lowercased().contains(query)
                    || record.document.originalFilename.lowercased().contains(query)
                    || record.events.contains { $0.title.lowercased().contains(query) }
            }
        }

        return records.sorted(by: comparator)
    }

    private var comparator: (DocumentRecord, DocumentRecord) -> Bool {
        switch sortOrder {
        case .dateNewest:
            { $0.sortDate > $1.sortDate }
        case .dateOldest:
            { $0.sortDate < $1.sortDate }
        case .importedNewest:
            { $0.document.importedAt > $1.document.importedAt }
        case .name:
            { $0.document.displayName.localizedStandardCompare($1.document.displayName) == .orderedAscending }
        case .size:
            { $0.document.byteSize > $1.document.byteSize }
        case .pages:
            // Documents with no known page count sort last rather than as zero:
            // unknown is not the same as empty.
            { ($0.document.pageCount ?? -1) > ($1.document.pageCount ?? -1) }
        }
    }
}
