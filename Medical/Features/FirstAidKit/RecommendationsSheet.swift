import SwiftUI

/// Every direction a home kit is usually expected to cover, and what the
/// cupboard has against each.
///
/// The list is the same whether a direction is covered, missing or set aside —
/// advice that disappears the moment somebody dismisses it cannot be taken back,
/// and a person's circumstances change faster than their first-aid kit does.
struct RecommendationsSheet: View {
    @Environment(ArchiveStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var onAdd: (MedicineKind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            list
            Divider()
            footer
        }
        .frame(width: 560, height: 560)
        .background(Palette.page)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recommendations")
                .font(.title2.weight(.semibold))
            Text("A general checklist of what a home kit usually covers — not medical advice, and not a list of products. What belongs in each is between you and a pharmacist.")
                .font(.callout)
                .foregroundStyle(Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(MedicineKind.allCases.enumerated()), id: \.element.id) { index, kind in
                    row(kind)
                    if index < MedicineKind.allCases.count - 1 {
                        Divider().padding(.leading, 20)
                    }
                }
            }
        }
    }

    private func row(_ kind: MedicineKind) -> some View {
        let stocked = store.archive.medicines(of: kind)
        let isHidden = store.archive.isHidden(kind)

        return HStack(spacing: 12) {
            MedicineKindRow(kind: kind, detail: detail(for: kind, stocked: stocked))

            if stocked.isEmpty {
                Button("Add") { onAdd(kind) }
                    .buttonStyle(.link)
            }

            // A checkbox rather than a dismiss button: the state is "am I being
            // reminded about this", and it has to be visible in both directions.
            Toggle("Remind me", isOn: Binding(
                get: { !isHidden },
                set: { remind in store.update { $0.setHidden(!remind, forKind: kind) } }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help(isHidden ? "Set aside — not counted as missing" : "Counted as missing when empty")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        .opacity(isHidden ? 0.55 : 1)
    }

    private func detail(for kind: MedicineKind, stocked: [Medicine]) -> String? {
        guard !stocked.isEmpty else { return nil }
        let names = stocked.prefix(3).map(\.name).joined(separator: ", ")
        return stocked.count > 3 ? "\(names) and \(stocked.count - 3) more" : names
    }

    private var footer: some View {
        HStack {
            Text("\(store.archive.firstAidKit.hiddenKinds.count) set aside")
                .font(.caption)
                .foregroundStyle(Palette.tertiaryText)
                .monospacedDigit()
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .controlSize(.large)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}
