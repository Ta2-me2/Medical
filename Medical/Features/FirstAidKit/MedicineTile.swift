import SwiftUI

/// One box, as it sits on the shelf.
///
/// A tile rather than a row, and a picture rather than a symbol: this is the one
/// page in the app that is about objects a person owns rather than events that
/// happened to them, and it should look like it. The sticker is what the eye
/// finds first, exactly as it would on the real packet.
struct MedicineTile: View {
    let medicine: Medicine
    var expiry: MedicineExpiry?
    var onOpen: () -> Void
    var onInstructions: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                sticker

                VStack(alignment: .leading, spacing: 2) {
                    Text(medicine.name)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if let purpose = medicine.purpose?.nilIfEmpty {
                        Text(purpose)
                            .font(.caption)
                            .foregroundStyle(Palette.secondaryText)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                expiryLabel

                Spacer(minLength: 4)

                // A real button, not a badge. Reading the dose is the thing this
                // page exists for, and it should not go through the editor.
                if medicine.hasInstructions {
                    Button(action: onInstructions) {
                        Label("Instructions", systemImage: "doc.text")
                            .labelStyle(.iconOnly)
                            .imageScale(.medium)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Palette.selection)
                    .help("Read the instructions")
                    .accessibilityLabel("Instructions for \(medicine.name)")
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .cardSurface()
        .background {
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .fill(Palette.selection.opacity(isHovering ? 0.04 : 0))
        }
        .contentShape(.rect(cornerRadius: Metrics.cardRadius, style: .continuous))
        // A tap rather than wrapping the whole tile in a Button: a button
        // inside a button is a coin toss about which one gets the click, and
        // the instructions button has to win its own.
        .onTapGesture(perform: onOpen)
        .accessibilityAddTraits(.isButton)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }

    /// The emoji in a well, the way a label sits on a box.
    private var sticker: some View {
        Text(medicine.displayEmoji)
            .font(.system(size: 24))
            .frame(width: 44, height: 44)
            .background(Palette.subtleFill, in: .rect(cornerRadius: Metrics.smallRadius, style: .continuous))
    }

    /// Quiet until it matters. A box good for another two years says so in grey;
    /// one that ran out last month is the only red thing on the shelf.
    @ViewBuilder
    private var expiryLabel: some View {
        if let expiry {
            let expired = expiry.isExpired()
            HStack(spacing: 5) {
                Image(systemName: expired ? "exclamationmark.circle.fill" : "clock")
                    .imageScale(.small)
                Text(expiry.description())
            }
            .font(.caption)
            .foregroundStyle(expired ? Palette.critical : Palette.warning)
            .lineLimit(1)
        } else if let printed = medicine.expiry {
            Text("Use by \(printed.formatted)")
                .font(.caption)
                .foregroundStyle(Palette.tertiaryText)
                .monospacedDigit()
                .lineLimit(1)
        } else {
            Text("No expiry recorded")
                .font(.caption)
                .foregroundStyle(Palette.tertiaryText)
                .lineLimit(1)
        }
    }
}

/// The row the recommendations use: a direction, and what is missing from it.
struct MedicineKindRow: View {
    let kind: MedicineKind
    var detail: String?

    var body: some View {
        HStack(spacing: 12) {
            Text(kind.suggestedEmoji)
                .font(.system(size: 17))
                .frame(width: 30, height: 30)
                .background(Palette.subtleFill, in: .rect(cornerRadius: Metrics.smallRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title)
                    .lineLimit(1)
                Text(detail ?? kind.explanation)
                    .font(.caption)
                    .foregroundStyle(Palette.tertiaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)
        }
    }
}
