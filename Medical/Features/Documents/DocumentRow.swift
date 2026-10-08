import SwiftUI

/// A document as one compact line, for places that list documents inside
/// something else — a medical record, a search result.
struct DocumentRow: View {
    let document: StoredDocument
    /// Which pages the citing record uses. Whole document when omitted.
    var pages: PageSelection = .wholeDocument
    var usage: String?

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: document.kind.symbol)
                .font(.title3)
                .foregroundStyle(Palette.secondaryText)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(document.displayName)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(document.fileExtension)
                    if !pages.isWholeDocument {
                        Text("·")
                        // The pages this record is about, called out because on
                        // a ninety-page card they are the whole point.
                        Text(pages.sentenceText)
                            .foregroundStyle(Palette.secondaryText)
                    } else if let count = document.formattedPageCount {
                        Text("·")
                        Text(count)
                    }
                    Text("·")
                    Text(document.formattedSize)
                    if let usage {
                        Text("·")
                        Text(usage).lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(Palette.tertiaryText)
            }

            Spacer(minLength: 8)

            Image(systemName: "eye")
                .imageScale(.small)
                .foregroundStyle(Palette.tertiaryText)
        }
        .contentShape(.rect)
    }
}

/// A document as a tile, with a real preview of the page.
struct DocumentTile: View {
    let record: DocumentRecord
    let url: URL
    var isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            DocumentThumbnail(document: record.document, url: url)
                .overlay(alignment: .topTrailing) {
                    // A dot rather than a chip: at thumbnail size a word would
                    // cover the page it is describing.
                    if record.status != .used {
                        Circle()
                            .fill(record.status == .notProcessed ? Palette.warning : Palette.secondaryText)
                            .frame(width: 8, height: 8)
                            .padding(6)
                    }
                }

            VStack(spacing: 2) {
                Text(record.document.displayName)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(record.isUsed ? Palette.tertiaryText : Palette.warning)
            }
            .frame(width: 150)
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .fill(isSelected ? Palette.selection.opacity(0.14) : .clear)
        }
        .contentShape(.rect)
    }

    private var subtitle: String {
        if let date = record.date { return date.medium }
        return record.status.title
    }
}
