import SwiftUI

/// One event, as it appears on the timeline.
///
/// The date sits in a fixed-width column so titles align down the whole page,
/// the way message lists do. Everything else is one quiet column: title, who and
/// where, two lines of summary, then what is attached.
struct EventCard: View {
    let event: MedicalEvent
    var attribution: String?
    var isSelected: Bool = false

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            dateColumn

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(event.title)
                        .font(.headline)
                        .foregroundStyle(Palette.primaryText)
                        .lineLimit(2)

                    if event.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(Palette.tertiaryText)
                    }

                    Spacer(minLength: 0)

                    StatusLabel(status: event.status)
                }

                if let attribution {
                    Text(attribution)
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                        .lineLimit(1)
                }

                if let summary = event.summary.nilIfEmpty {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryText)
                        .lineLimit(2)
                        .padding(.top, 1)
                }

                if event.attachmentCount > 0 || event.noteCount > 0 {
                    HStack(spacing: 12) {
                        CountBadge(symbol: "paperclip", count: event.attachmentCount)
                        CountBadge(symbol: "text.page", count: event.noteCount)
                    }
                    .padding(.top, 3)
                }
            }
        }
        .cardSurface(isEmphasised: isSelected)
        .background {
            // Hover is a whisper, not a highlight: the card lifts by a barely
            // perceptible fill rather than changing colour.
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .fill(Palette.selection.opacity(isHovering && !isSelected ? 0.04 : 0))
        }
        .contentShape(.rect(cornerRadius: Metrics.cardRadius, style: .continuous))
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }

    /// Date, then what kind of thing this was.
    ///
    /// The category used to be a small grey line beside the title, competing
    /// with it. Below the date there was empty space and, at a glance, nothing
    /// telling a vaccination from an operation. A symbol large enough to read
    /// without reading does that job, and the word underneath removes any doubt.
    private var dateColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(event.date.compact)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Palette.primaryText)
                .monospacedDigit()

            if event.date.precision == .day {
                Text(event.date.date.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.caption)
                    .foregroundStyle(Palette.tertiaryText)
            }

            Image(systemName: event.category.symbol)
                .font(.system(size: 19, weight: .light))
                .foregroundStyle(Palette.secondaryText)
                .frame(height: 26)
                .padding(.top, 10)

            Text(event.category.title)
                .font(.caption2)
                .foregroundStyle(Palette.tertiaryText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: Metrics.dateColumnWidth, alignment: .leading)
    }
}
