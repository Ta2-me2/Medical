import SwiftUI

/// A set of choices where empty means everything.
///
/// Filters used to be stored as exclusions — the categories to hide — which
/// meant showing one category required turning off the other twelve. Storing the
/// inclusions instead makes the common case one click, and "everything" is the
/// natural resting state rather than a state you have to rebuild by hand.
nonisolated struct InclusionFilter<Option: Hashable & Sendable>: Sendable {
    private(set) var selected: Set<Option> = []

    var isFiltering: Bool { !selected.isEmpty }

    /// Empty means no restriction, so everything passes.
    func allows(_ option: Option) -> Bool {
        selected.isEmpty || selected.contains(option)
    }

    func isSelected(_ option: Option) -> Bool { selected.contains(option) }

    mutating func toggle(_ option: Option) {
        if selected.contains(option) {
            selected.remove(option)
        } else {
            selected.insert(option)
        }
    }

    /// Narrows to exactly one — what a click on a row means when the intent is
    /// "just this one", rather than "one more".
    mutating func only(_ option: Option) {
        selected = [option]
    }

    mutating func clear() {
        selected.removeAll()
    }
}

/// One group inside a filter menu: an "all" row, then the options.
///
/// Plain toggles, so several can be on at once, and one row that puts everything
/// back. No modifier keys to discover.
struct FilterSection<Option: Hashable & Identifiable & Sendable>: View {
    let title: String
    let options: [Option]
    let label: (Option) -> String
    var symbol: ((Option) -> String)?
    @Binding var filter: InclusionFilter<Option>

    var body: some View {
        Section(title) {
            Button {
                filter.clear()
            } label: {
                Label(
                    "All \(title)",
                    systemImage: filter.isFiltering ? "" : "checkmark"
                )
            }

            Divider()

            ForEach(options) { option in
                Toggle(isOn: Binding(
                    get: { filter.isSelected(option) },
                    set: { _ in filter.toggle(option) }
                )) {
                    if let symbol {
                        Label(label(option), systemImage: symbol(option))
                    } else {
                        Text(label(option))
                    }
                }
            }
        }
    }
}

/// The toolbar button that opens a filter menu, filled in when anything is
/// narrowing the list.
struct FilterMenuLabel: View {
    let isFiltering: Bool

    var body: some View {
        Label(
            "Filter",
            systemImage: isFiltering
                ? "line.3.horizontal.decrease.circle.fill"
                : "line.3.horizontal.decrease.circle"
        )
    }
}
