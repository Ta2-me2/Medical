import Foundation

/// When a vaccination needs repeating.
///
/// Either an interval from the dose that was given — "ten years" — or a date a
/// clinic named outright. Both are written down by the owner; the app never
/// invents a schedule, because schedules differ by country, by vaccine brand and
/// by the person's own history.
nonisolated struct BoosterSchedule: Hashable, Codable, Sendable {

    /// Months after the dose. 120 is ten years.
    var afterMonths: Int?

    /// A date the clinic gave, used instead of an interval when present.
    var onDate: DateValue?

    init(afterMonths: Int? = nil, onDate: DateValue? = nil) {
        self.afterMonths = afterMonths
        self.onDate = onDate
    }

    var isEmpty: Bool { afterMonths == nil && onDate == nil }

    /// The day this becomes due, counted from the dose actually given.
    ///
    /// Counting from the real dose rather than from a plan is the whole point:
    /// a booster given two years late moves everything after it by two years,
    /// and one given early moves it the other way. The archive follows what
    /// happened, not what was scheduled.
    func dueDate(after dose: DateValue) -> Date? {
        if let onDate { return onDate.date }
        guard let afterMonths, afterMonths > 0 else { return nil }
        return Calendar.current.date(byAdding: .month, value: afterMonths, to: dose.date)
    }

    /// `Every 10 years` / `Every 6 months` / `On 1 April 2035`.
    var description: String? {
        if let onDate { return "On \(onDate.formatted)" }
        guard let afterMonths, afterMonths > 0 else { return nil }
        if afterMonths % 12 == 0 {
            let years = afterMonths / 12
            return "Every \(years) \(years == 1 ? "year" : "years")"
        }
        return "Every \(afterMonths) \(afterMonths == 1 ? "month" : "months")"
    }

    // MARK: - Common intervals

    /// Offered in the editor. Anything else is typed as a number of months.
    static let presets: [(title: String, months: Int)] = [
        ("6 months", 6),
        ("1 year", 12),
        ("2 years", 24),
        ("5 years", 60),
        ("10 years", 120),
    ]

    private enum CodingKeys: String, CodingKey { case afterMonths, onDate }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        afterMonths = c.value(.afterMonths)
        onDate = c.value(.onDate)
    }
}

/// A vaccination that is coming up, or overdue.
///
/// Always derived from the most recent dose of that vaccine. If a second
/// pneumococcal dose is recorded, the first one's schedule is superseded — there
/// is only ever one outstanding answer per vaccine, and it is the one the last
/// dose implies.
nonisolated struct VaccinationDue: Identifiable, Hashable, Sendable {
    var vaccinationID: UUID
    var eventID: UUID
    var eventTitle: String
    var name: String

    /// Which course this reminder belongs to, so a page showing one course can
    /// show its reminder and not its neighbours'.
    var seriesKey: String
    var doseLabel: String?
    var lastGiven: DateValue
    var dueOn: Date

    var id: UUID { vaccinationID }

    func isOverdue(asOf now: Date = .now) -> Bool {
        dueOn < Calendar.current.startOfDay(for: now)
    }

    /// `Due in 3 months` / `Due next month` / `Overdue by 2 years`.
    func description(asOf now: Date = .now) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let due = calendar.startOfDay(for: dueOn)

        if due == today { return "Due today" }

        let months = calendar.dateComponents([.month], from: min(today, due), to: max(today, due)).month ?? 0
        let days = calendar.dateComponents([.day], from: min(today, due), to: max(today, due)).day ?? 0

        let span: String
        if months >= 24 {
            span = "\(months / 12) years"
        } else if months >= 1 {
            span = "\(months) \(months == 1 ? "month" : "months")"
        } else {
            span = "\(days) \(days == 1 ? "day" : "days")"
        }

        return due < today ? "Overdue by \(span)" : "Due in \(span)"
    }
}
