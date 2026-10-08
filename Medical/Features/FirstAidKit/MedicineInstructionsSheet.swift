import SwiftUI

/// How to take it, opened straight from the shelf.
///
/// Reading the instructions is the one thing a person does with a first-aid kit
/// in a hurry, and it is not editing. Sending them through the editor to find
/// out how many tablets to take would put a Save button between somebody with a
/// headache and the answer.
struct MedicineInstructionsSheet: View {
    @Environment(ArchiveStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let medicine: Medicine
    var onEdit: () -> Void

    @State private var selected: UUID?

    private var leaflets: [AttachedDocument] {
        store.archive.attachments(for: medicine)
    }

    private var written: String? { medicine.instructions?.nilIfEmpty }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            panes
            Divider()
            footer
        }
        .frame(
            width: leaflets.isEmpty ? 560 : 940,
            height: leaflets.isEmpty ? 480 : 660
        )
        .background(Palette.page)
        .onAppear { selected = selected ?? leaflets.first?.reference.id }
    }

    // MARK: - Chrome

    private var header: some View {
        HStack(spacing: 12) {
            Text(medicine.displayEmoji)
                .font(.system(size: 22))
                .frame(width: 40, height: 40)
                .background(Palette.subtleFill, in: .rect(cornerRadius: Metrics.smallRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(medicine.name)
                    .font(.headline)

                if let detail = subtitle {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    /// What it is for and how much is left — the two things worth knowing
    /// alongside the dose, and both already recorded.
    private var subtitle: String? {
        [medicine.purpose?.nilIfEmpty, medicine.quantity?.nilIfEmpty]
            .compactMap(\.self)
            .joined(separator: " · ")
            .nilIfEmpty
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Edit…") { onEdit() }

            Spacer()

            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .controlSize(.large)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Content

    /// Typed instructions on the left, the leaflet on the right — and whichever
    /// of the two exists alone gets the whole sheet.
    @ViewBuilder
    private var panes: some View {
        if leaflets.isEmpty {
            writtenPane
        } else if written == nil {
            leafletPane
        } else {
            HStack(spacing: 0) {
                writtenPane
                    .frame(width: 320)
                Divider()
                leafletPane
            }
        }
    }

    @ViewBuilder
    private var writtenPane: some View {
        if let written {
            ScrollView {
                Text(written)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(20)
            }
        } else {
            ContentUnavailableView(
                "Nothing Written Down",
                systemImage: "text.page",
                description: Text("Add the dose and how often to take it in the editor.")
            )
        }
    }

    @ViewBuilder
    private var leafletPane: some View {
        VStack(spacing: 0) {
            // Only when there is a choice to make. One leaflet needs no picker,
            // and a picker with one option in it is furniture.
            if leaflets.count > 1 {
                Picker("Leaflet", selection: Binding(
                    get: { selected ?? leaflets.first?.reference.id },
                    set: { selected = $0 }
                )) {
                    ForEach(leaflets) { attached in
                        Text(attached.document.displayName)
                            .tag(Optional(attached.reference.id))
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider()
            }

            if let current {
                QuickLookPreview(url: store.fileURL(for: current.document))
            }
        }
    }

    private var current: AttachedDocument? {
        leaflets.first { $0.reference.id == selected } ?? leaflets.first
    }
}
