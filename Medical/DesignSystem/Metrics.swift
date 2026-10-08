import SwiftUI

/// Every spacing and radius in the app, in one place.
///
/// Screens never invent their own numbers. When the whole interface has to feel
/// like one piece of software for twenty years, consistent geometry is what does
/// most of that work.
enum Metrics {

    /// Horizontal padding from the window edge to page content.
    static let gutter: CGFloat = 28

    /// Vertical padding above a page title.
    static let pageTop: CGFloat = 24

    /// Between major sections of a page.
    static let sectionSpacing: CGFloat = 28

    /// Between a section header and its content.
    static let headerSpacing: CGFloat = 12

    /// Between sibling rows and cards.
    static let rowSpacing: CGFloat = 10

    /// Inside a card.
    static let cardPadding: CGFloat = 16

    static let cardRadius: CGFloat = 10
    static let smallRadius: CGFloat = 6

    /// Reading measure. Long text never stretches the full width of a wide
    /// window — a 1600 pt line of a doctor's summary is unreadable.
    static let readableWidth: CGFloat = 760

    static let sidebarMin: CGFloat = 232
    static let sidebarIdeal: CGFloat = 248
    static let sidebarMax: CGFloat = 300

    /// Width of the year rail in the timeline.
    static let yearRailWidth: CGFloat = 116

    /// Fixed date column in event cards, so titles line up down the page.
    /// Wide enough for a category name under the date.
    static let dateColumnWidth: CGFloat = 78

    static let avatarSmall: CGFloat = 30
    static let avatarLarge: CGFloat = 92

    static let windowMinWidth: CGFloat = 940
    static let windowMinHeight: CGFloat = 620
}
