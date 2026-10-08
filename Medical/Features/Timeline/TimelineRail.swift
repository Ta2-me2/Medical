import SwiftUI

/// What sits on the line at this row.
enum TimelineMarker {
    /// An event. The dot carries its status colour.
    case event(EventStatus)
    /// A year boundary. A hollow ring, so years read as milestones on the same
    /// thread rather than as a different kind of thing.
    case year
}

/// The thread the whole history hangs from.
///
/// One continuous vertical line runs the length of the timeline, and every row
/// draws its own segment of it. That is what makes the history feel like one
/// story instead of a stack of unrelated cards: the line never breaks between
/// an event and the next, or between one year and the next.
struct TimelineRailSegment: View {
    let marker: TimelineMarker
    let isFirst: Bool
    let isLast: Bool

    /// Distance from the top of the row to the centre of the marker, so the dot
    /// lands level with the first line of text beside it.
    let markerCentre: CGFloat

    static let width: CGFloat = 18

    var body: some View {
        ZStack(alignment: .top) {
            line
            markerView
                .offset(y: markerCentre - markerDiameter / 2)
        }
        .frame(width: Self.width)
    }

    @ViewBuilder
    private var line: some View {
        if isLast {
            // The thread stops at the last marker rather than trailing into
            // empty space below the final event.
            if !isFirst {
                Rectangle()
                    .fill(Palette.separator)
                    .frame(width: 1, height: markerCentre)
            }
        } else {
            Rectangle()
                .fill(Palette.separator)
                .frame(width: 1)
                .frame(maxHeight: .infinity)
                // The very first row starts its line at the marker, not above it.
                .padding(.top, isFirst ? markerCentre : 0)
        }
    }

    @ViewBuilder
    private var markerView: some View {
        switch marker {
        case .event(let status):
            StatusDot(status: status, size: markerDiameter)
                // A ring in the page colour keeps the line from running into
                // the dot, without drawing a second visible shape.
                .padding(3)
                .background(Palette.page, in: .circle)
        case .year:
            Circle()
                .strokeBorder(Palette.separator, lineWidth: 1.5)
                .frame(width: markerDiameter, height: markerDiameter)
                .background(Palette.page, in: .circle)
        }
    }

    private var markerDiameter: CGFloat {
        switch marker {
        case .event: 9
        case .year: 11
        }
    }
}
