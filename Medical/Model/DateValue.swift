import Foundation

/// A date together with how precisely it is actually known.
///
/// Paper records from decades ago are frequently dated only "March 2007", or
/// just "2004". Storing those as a plain `Date` would force the archive to
/// invent a day it does not know, and the invented day would then be presented
/// to the reader as fact. `DateValue` keeps the precision alongside the value
/// so the archive never claims to be more exact than its source.
nonisolated struct DateValue: Hashable, Codable, Sendable, Comparable {

    enum Precision: String, Codable, Sendable, CaseIterable, Identifiable {
        case day
        case month
        case year

        var id: String { rawValue }

        var title: String {
            switch self {
            case .day: "Exact date"
            case .month: "Month and year"
            case .year: "Year only"
            }
        }
    }

    /// Always normalised to the start of the known period, so that sorting and
    /// grouping behave identically regardless of what the source document said.
    var date: Date
    var precision: Precision

    init(_ date: Date, precision: Precision = .day) {
        self.precision = precision
        self.date = DateValue.normalise(date, to: precision)
    }

    // MARK: - Components

    var year: Int { Calendar.current.component(.year, from: date) }
    var month: Int { Calendar.current.component(.month, from: date) }

    // MARK: - Presentation

    /// Full form, used on detail pages: `14 March 2007`, `March 2007`, `2007`.
    var formatted: String {
        switch precision {
        case .day: date.formatted(.dateTime.day().month(.wide).year())
        case .month: date.formatted(.dateTime.month(.wide).year())
        case .year: String(year)
        }
    }

    /// Compact form for list rows and cards: `14 Mar`, `Mar`, `2007`.
    /// The year is carried by the surrounding section header, so it is omitted
    /// unless it is the only thing known.
    var compact: String {
        switch precision {
        case .day: date.formatted(.dateTime.day().month(.abbreviated))
        case .month: date.formatted(.dateTime.month(.abbreviated))
        case .year: String(year)
        }
    }

    /// Medium form for contexts without a year header: `14 Mar 2007`.
    var medium: String {
        switch precision {
        case .day: date.formatted(.dateTime.day().month(.abbreviated).year())
        case .month: date.formatted(.dateTime.month(.abbreviated).year())
        case .year: String(year)
        }
    }

    // MARK: - Comparable

    static func < (lhs: DateValue, rhs: DateValue) -> Bool { lhs.date < rhs.date }

    // MARK: - Coding

    // Stored as a bare calendar date — `"2004-01-01"` — not as an instant.
    //
    // A medical event happens on a day, not at a moment on a world clock.
    // Encoding it as an instant makes the archive depend on the time zone it was
    // written in: an event dated 2004 in Jerusalem is stored as
    // `2003-12-31T21:00:00Z`, which reads as the wrong year to a human opening
    // the file, and *is* the wrong year to an app opening it further west.
    // A floating calendar date has neither problem.

    private enum CodingKeys: String, CodingKey {
        case date, precision
    }

    // Done with `DateComponents` rather than a `DateFormatter`: a shared
    // formatter would be a data race, and a per-call one is pure overhead for a
    // string this simple.

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        precision = container.value(.precision, or: .day)

        if let text: String = container.value(.date) {
            if let parsed = DateValue.calendarDate(from: text) {
                date = DateValue.normalise(parsed, to: precision)
                return
            }
            // Instants written by an earlier version still decode.
            if let parsed = ISO8601DateFormatter().date(from: text) {
                date = DateValue.normalise(parsed, to: precision)
                return
            }
        }

        if let instant: Date = container.value(.date) {
            date = DateValue.normalise(instant, to: precision)
            return
        }

        throw DecodingError.dataCorruptedError(
            forKey: .date,
            in: container,
            debugDescription: "Expected a calendar date such as 2004-01-01."
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(DateValue.calendarString(from: date), forKey: .date)
        try container.encode(precision, forKey: .precision)
    }

    /// `2004-01-01`, in the reader's own calendar.
    static func calendarString(from date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 1, parts.day ?? 1)
    }

    /// Reads `2004-01-01` back as local midnight on that day, whatever the
    /// time zone happens to be. Also accepts a leading date from a longer
    /// timestamp, so `2004-01-01T00:00:00Z` is understood too.
    static func calendarDate(from text: String) -> Date? {
        let head = text.prefix(10)
        let pieces = head.split(separator: "-")
        guard pieces.count == 3,
              let year = Int(pieces[0]),
              let month = Int(pieces[1]),
              let day = Int(pieces[2])
        else { return nil }
        return Calendar.current.date(from: DateComponents(year: year, month: month, day: day))
    }

    // MARK: - Helpers

    private static func normalise(_ date: Date, to precision: Precision) -> Date {
        let calendar = Calendar.current
        switch precision {
        case .day:
            return calendar.startOfDay(for: date)
        case .month:
            let parts = calendar.dateComponents([.year, .month], from: date)
            return calendar.date(from: parts) ?? date
        case .year:
            let parts = calendar.dateComponents([.year], from: date)
            return calendar.date(from: parts) ?? date
        }
    }
}
