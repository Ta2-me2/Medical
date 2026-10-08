import Foundation
import Observation

/// State that belongs to the Vaccinations screen: how the doses are arranged,
/// and which vaccines are being shown.
@Observable
final class VaccinationsViewModel {

    /// Two questions, two shapes.
    ///
    /// "What have I had against diphtheria?" is answered by a list per course.
    /// "What did I have in 2019?" is answered by a date. Neither shape answers
    /// the other question well, so the page offers both rather than picking.
    enum Grouping: String, CaseIterable, Identifiable, Sendable {
        case vaccine
        case date

        var id: String { rawValue }

        var title: String {
            switch self {
            case .vaccine: "By Vaccine"
            case .date: "By Date"
            }
        }
    }

    var grouping: Grouping = .vaccine
    var vaccines = InclusionFilter<VaccineOption>()

    var isFiltered: Bool { vaccines.isFiltering }

    func clearFilter() {
        vaccines.clear()
    }

    func options(from series: [VaccinationSeries]) -> [VaccineOption] {
        series.map { VaccineOption(key: $0.key, name: $0.name) }
    }

    func filtered(_ series: [VaccinationSeries]) -> [VaccinationSeries] {
        series.filter { vaccines.allows(VaccineOption(key: $0.key, name: $0.name)) }
    }

    /// The same doses the vaccine grouping is showing, back on one date order.
    func chronological(_ series: [VaccinationSeries]) -> [VaccinationRecord] {
        series.flatMap(\.records).sorted { $0.date > $1.date }
    }
}

/// One course of vaccination, as a thing that can be ticked in a filter menu.
///
/// Identity is the normalised key alone: the label follows the most recent
/// dose's record, and a filter should not quietly stop matching because a later
/// record was titled with different capitals.
nonisolated struct VaccineOption: Identifiable, Hashable, Sendable {
    let key: String
    let name: String

    var id: String { key }

    static func == (one: Self, other: Self) -> Bool { one.key == other.key }
    func hash(into hasher: inout Hasher) { hasher.combine(key) }
}
