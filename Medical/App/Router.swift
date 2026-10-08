import Foundation
import Observation

/// The sections listed in the sidebar.
///
/// There is no Settings item by design. Library maintenance lives in the
/// application menu, where macOS users already look for it.
enum SidebarItem: String, CaseIterable, Identifiable, Hashable, Codable {
    case patient
    case dashboard
    case timeline
    case inbox
    case documents
    case vaccinations
    case firstAidKit
    case notes
    case export

    var id: String { rawValue }

    /// Everything except the patient profile, which is presented separately at
    /// the top of the sidebar.
    static var navigationItems: [SidebarItem] {
        allCases.filter { $0 != .patient }
    }

    var title: String {
        switch self {
        case .patient: "Patient"
        case .dashboard: "Dashboard"
        case .timeline: "Timeline"
        case .inbox: "Inbox"
        case .documents: "Documents"
        case .vaccinations: "Vaccinations"
        case .firstAidKit: "First Aid Kit"
        case .notes: "Notes"
        case .export: "Export"
        }
    }

    var symbol: String {
        switch self {
        case .patient: "person.crop.circle"
        case .dashboard: "house"
        case .timeline: "calendar"
        case .inbox: "tray"
        case .documents: "text.document"
        case .vaccinations: "syringe"
        case .firstAidKit: "cross.case"
        case .notes: "text.page"
        case .export: "square.and.arrow.up"
        }
    }
}

/// A page pushed on top of a section.
enum Destination: Hashable {
    case event(UUID)
}

/// Where the interface currently is.
///
/// One navigation path, sitting on top of whichever section is open. Back is
/// therefore never a guess: it removes the last thing that was pushed, and what
/// is underneath is the page you were on when you pushed it.
@Observable
final class Router {

    var selection: SidebarItem? = .dashboard {
        didSet {
            if oldValue != selection { path.removeAll() }
        }
    }

    var path: [Destination] = []

    /// Searching swaps the root of the stack, so a new query has to bring the
    /// stack down with it — otherwise the answer arrives underneath whatever
    /// was already open and the search appears to have done nothing. Emptying
    /// the field is left alone: it should not yank a reader out of the page
    /// they are reading.
    var searchText: String = "" {
        didSet {
            if !searchText.isEmpty, oldValue != searchText { path.removeAll() }
        }
    }

    /// Set when something elsewhere asks for the file chooser. The inbox owns
    /// importing, so every entry point routes there and raises this rather than
    /// each screen growing its own copy of the import machinery.
    var pendingImport = false

    /// Same idea for the library chooser: the Export page owns it, and the
    /// menu bar asks for it rather than growing a second copy.
    var pendingLibraries = false

    var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Opens an event from anywhere — a note, a document, a search result, a
    /// dose on the vaccinations page.
    ///
    /// Pushed onto the section already open, never onto a different one. This
    /// used to jump to the Timeline first, on the theory that an event is best
    /// read in its chronological context; the cost was that Back returned you
    /// to a page you had never been on. Where you came from is not context the
    /// application gets to overrule.
    func open(event id: UUID) {
        guard path.last != .event(id) else { return }
        path.append(.event(id))
    }

    func show(_ item: SidebarItem) {
        searchText = ""
        selection = item
        path.removeAll()
    }

    /// Opens the new-record flow. Presented as a sheet from wherever it is
    /// triggered, so it never costs the user their place.
    var newRecordSource: NewRecordSource?

    enum NewRecordSource: Identifiable, Hashable {
        /// Start by choosing a document, or none at all.
        case chooseSource
        /// Start from a document already in the inbox.
        case document(UUID)
        /// Edit a record that already exists.
        case existing(UUID)

        var id: String {
            switch self {
            case .chooseSource: "new"
            case .document(let id): "doc-\(id)"
            case .existing(let id): "event-\(id)"
            }
        }
    }

    /// Takes the user to the inbox with the file chooser open.
    func startImport() {
        searchText = ""
        selection = .inbox
        path.removeAll()
        pendingImport = true
    }

    /// Takes the user to the Export page with the library chooser open.
    func chooseLibrary() {
        searchText = ""
        selection = .export
        path.removeAll()
        pendingLibraries = true
    }

    func newRecord() {
        newRecordSource = .chooseSource
    }

    func newRecord(from documentID: UUID) {
        newRecordSource = .document(documentID)
    }

    func edit(eventID: UUID) {
        newRecordSource = .existing(eventID)
    }
}
