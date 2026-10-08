import SwiftUI

/// A category shown as symbol plus name, in grey.
///
/// Categories are never colour coded. Fourteen tinted chips down a timeline
/// stop reading as information and start reading as decoration.
struct CategoryLabel: View {
    let category: EventCategory
    var showsTitle: Bool = true

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: category.symbol)
                .font(.caption)
                .imageScale(.medium)
            if showsTitle {
                Text(category.title)
                    .font(.caption)
            }
        }
        .foregroundStyle(Palette.secondaryText)
    }
}

/// A small count with its symbol — attachments, notes.
/// Hidden entirely at zero rather than shown as "0".
struct CountBadge: View {
    let symbol: String
    let count: Int

    var body: some View {
        if count > 0 {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .imageScale(.small)
                Text(count.formatted())
            }
            .font(.caption)
            .foregroundStyle(Palette.tertiaryText)
            .monospacedDigit()
        }
    }
}

/// A neutral pill used for tags and status words.
struct Chip: View {
    let text: String
    var tint: Color = Palette.secondaryText

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.1), in: .capsule)
    }
}

/// Initials in a circle. Used instead of a photo until one is set — a personal
/// archive should not ship with a stock silhouette.
struct AvatarView: View {
    let initials: String
    var size: CGFloat = Metrics.avatarSmall

    var body: some View {
        Circle()
            .fill(Palette.subtleFill)
            .overlay {
                Text(initials.isEmpty ? "—" : initials)
                    .font(.system(size: size * 0.38, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.secondaryText)
            }
            .frame(width: size, height: size)
    }
}
