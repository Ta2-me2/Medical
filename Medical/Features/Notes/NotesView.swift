import SwiftUI

/// Every note ever written, newest first.
///
/// Notes are the part of a medical history nobody else records. Each one keeps
/// a visible line back to the event it belongs to, so it never becomes an
/// orphaned thought.
struct NotesView: View {
    @Environment(ArchiveStore.self) private var store
    @Environment(Router.self) private var router

    @State private var model = NotesViewModel()

    var body: some View {
        let records = model.records(from: store.archive)

        VStack(spacing: 0) {
            if store.archive.noteCount > 0 {
                FilterBar(searchText: $model.searchText, prompt: "Filter notes") {
                    Text("\(records.count) of \(store.archive.noteCount)")
                        .font(.caption)
                        .foregroundStyle(Palette.tertiaryText)
                        .monospacedDigit()
                }
            }

            if store.archive.noteCount == 0 {
                empty
            } else if records.isEmpty {
                ContentUnavailableView.search(text: model.searchText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list(records)
            }
        }
        .background(Palette.page)
        .navigationTitle("Notes")
        .toolbar {
            ToolbarItem(id: "notes.filter") {
                Menu {
                    Picker("Category", selection: $model.categoryFilter) {
                        Text("All Categories").tag(EventCategory?.none)
                        Divider()
                        ForEach(EventCategory.allCases) { category in
                            Text(category.title).tag(EventCategory?.some(category))
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("Filter", systemImage: model.categoryFilter == nil
                        ? "line.3.horizontal.decrease.circle"
                        : "line.3.horizontal.decrease.circle.fill")
                }
                .menuIndicator(.hidden)
            }
        }
    }

    private func list(_ records: [NoteRecord]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                ForEach(records) { record in
                    Button {
                        router.open(event: record.event.id)
                    } label: {
                        card(record)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: Metrics.readableWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .pageInsets()
        }
    }

    private func card(_ record: NoteRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(record.note.displayTitle)
                .font(.headline)
                .lineLimit(2)

            if let rest = record.note.previewBelowTitle {
                Text(rest)
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(3)
            }

            HStack(spacing: 6) {
                Image(systemName: record.event.category.symbol)
                    .imageScale(.small)
                Text(record.event.title)
                    .lineLimit(1)
                Text("·")
                Text(record.date.medium)
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(Palette.tertiaryText)
            .padding(.top, 2)
        }
        .cardSurface()
    }

    private var empty: some View {
        ArchiveEmptyState(
            title: "No Notes",
            message: "Notes are added to an event — open one from the timeline and write what the paperwork does not say.",
            symbol: "text.page",
            actionTitle: "Open Timeline",
            action: { router.show(.timeline) }
        )
    }
}
