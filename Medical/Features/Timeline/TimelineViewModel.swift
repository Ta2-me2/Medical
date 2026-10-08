import Foundation
import Observation

/// State that belongs to the Timeline screen rather than to the archive:
/// which year is in view, and what is currently filtered out.
@Observable
final class TimelineViewModel {

    nonisolated struct YearGroup: Identifiable, Hashable {
        var id: Int { year }
        let year: Int
        let events: [MedicalEvent]
        var count: Int { events.count }
    }

    /// One line of the thread. Years and events are the same kind of row so the
    /// vertical line can run through both without a seam.
    nonisolated struct Row: Identifiable, Hashable {
        enum Kind: Hashable {
            case year(Int, count: Int)
            case event(MedicalEvent)
        }

        let id: String
        let kind: Kind

        static func yearID(_ year: Int) -> String { "year-\(year)" }

        var marker: TimelineMarker {
            switch kind {
            case .year: .year
            case .event(let event): .event(event.status)
            }
        }

        /// Where the dot sits relative to the top of the row, so it lines up
        /// with the first line of text beside it.
        var markerCentre: CGFloat {
            switch kind {
            case .year: 34
            case .event: 28
            }
        }
    }

    /// What to show, not what to hide. See `InclusionFilter`.
    var categories = InclusionFilter<EventCategory>()
    var statuses = InclusionFilter<EventStatus>()

    var activeYear: Int?

    /// Suppresses rail updates while a click-to-jump animation is running, so
    /// the rail does not chase the scroll through every year it passes.
    var isJumping = false

    var isFiltered: Bool { categories.isFiltering || statuses.isFiltering }

    func clearFilter() {
        categories.clear()
        statuses.clear()
    }

    /// Events grouped by year, newest first, with filtered rows removed.
    /// Years that end up empty disappear from the rail as well as the thread.
    func groups(from archive: Archive) -> [YearGroup] {
        let visible = archive.events.filter { categories.allows($0.category) && statuses.allows($0.status) }
        return Dictionary(grouping: visible, by: \.year)
            .map { YearGroup(year: $0.key, events: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.year > $1.year }
    }

    /// Flattens the groups into the single ordered list the thread renders.
    func rows(from groups: [YearGroup]) -> [Row] {
        groups.flatMap { group in
            [Row(id: Row.yearID(group.year), kind: .year(group.year, count: group.count))]
                + group.events.map { Row(id: $0.id.uuidString, kind: .event($0)) }
        }
    }
}
