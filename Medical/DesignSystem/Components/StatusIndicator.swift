import SwiftUI

/// The coloured dot that carries an event's status.
///
/// A dot rather than a filled badge: it reads at a glance down a long timeline
/// without any single event shouting. Green is the resting state and stays
/// quiet; orange and amber-red are the ones the eye should catch.
struct StatusDot: View {
    let status: EventStatus
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: size, height: size)
            .accessibilityLabel(status.title)
    }
}

/// Dot plus name. Shown where there is room to say what the colour means —
/// detail pages, menus — and suppressed for `normal`, which is the default and
/// would otherwise label almost every event in the archive.
struct StatusLabel: View {
    let status: EventStatus
    var forcesLabel: Bool = false

    var body: some View {
        if status.deservesLabel || forcesLabel {
            HStack(spacing: 5) {
                StatusDot(status: status, size: 7)
                Text(status.title)
                    .font(.caption)
                    .foregroundStyle(status.color)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(status.color.opacity(0.1), in: .capsule)
        }
    }
}

/// The control that sets a status. Used from the event page and the import
/// wizard, so the wording is identical in both.
struct StatusPicker: View {
    @Binding var status: EventStatus

    var body: some View {
        Picker("Status", selection: $status) {
            ForEach(EventStatus.allCases) { option in
                Label {
                    Text(option.title)
                } icon: {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(option.color)
                }
                .tag(option)
            }
        }
    }
}
