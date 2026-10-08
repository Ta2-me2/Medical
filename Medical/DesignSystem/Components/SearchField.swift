import SwiftUI

/// An in-page search field.
///
/// Deliberately not `.searchable`: the window already has one search field, in
/// the toolbar, and it searches the whole archive. A second toolbar search
/// field is both confusing and — because AppKit gives them the same toolbar
/// identifier — a crash. This one filters the list under it, and lives with it.
struct SearchField: View {
    @Binding var text: String
    var prompt: String
    var width: CGFloat = 240

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .imageScale(.small)
                .foregroundStyle(Palette.tertiaryText)

            TextField("", text: $text, prompt: Text(prompt))
                .textFieldStyle(.plain)
                .focused($isFocused)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .imageScale(.small)
                        .foregroundStyle(Palette.tertiaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(width: width)
        .background(Palette.card, in: .rect(cornerRadius: Metrics.smallRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.smallRadius, style: .continuous)
                .strokeBorder(isFocused ? Palette.selection : Palette.separator, lineWidth: 1)
        }
        .animation(.easeOut(duration: 0.12), value: isFocused)
    }
}

/// The strip of controls above a list: a search field on the left, whatever the
/// screen needs on the right.
struct FilterBar<Trailing: View>: View {
    @Binding var searchText: String
    var prompt: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            SearchField(text: $searchText, prompt: prompt)
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 10)
        .background(Palette.page)
        .overlay(alignment: .bottom) { Divider() }
    }
}

extension FilterBar where Trailing == EmptyView {
    init(searchText: Binding<String>, prompt: String) {
        self.init(searchText: searchText, prompt: prompt) { EmptyView() }
    }
}
