import Foundation

/// Where a document stands between arriving and being part of the record.
///
/// Only `archived` is stored. `used` and `notProcessed` are read from whether
/// any event references the document, so the status can never disagree with the
/// archive — a stored flag would eventually say "used" about a document nothing
/// points at any more.
nonisolated enum DocumentStatus: String, Codable, CaseIterable, Sendable, Identifiable {
    /// In the inbox, waiting to be filed.
    case notProcessed
    /// Referenced by at least one medical record.
    case used
    /// Deliberately set aside — a duplicate, a cover letter, something with no
    /// record of its own. Still in the library, out of the way.
    case archived

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notProcessed: "Not processed"
        case .used: "Used"
        case .archived: "Archived"
        }
    }

    var symbol: String {
        switch self {
        case .notProcessed: "tray"
        case .used: "checkmark.circle.fill"
        case .archived: "archivebox"
        }
    }
}
