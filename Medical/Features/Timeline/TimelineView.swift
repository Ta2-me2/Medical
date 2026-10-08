import SwiftUI

/// The heart of the archive: a life, on one continuous thread.
struct TimelineView: View {
    @Environment(ArchiveStore.self) private var store
    @Environment(Router.self) private var router

    @State private var model = TimelineViewModel()
    @State private var visibleYears: Set<Int> = []

    var body: some View {
        let groups = model.groups(from: store.archive)

        Group {
            if store.archive.isEmpty {
                emptyArchive
            } else if groups.isEmpty {
                filteredToNothing
            } else {
                content(groups)
            }
        }
        .background(Palette.page)
        .navigationTitle("Timeline")
        .toolbar { filterMenu }
        .onAppear {
            if model.activeYear == nil { model.activeYear = groups.first?.year }
        }
    }

    // MARK: - Content

    private func content(_ groups: [TimelineViewModel.YearGroup]) -> some View {
        HStack(spacing: 0) {
            YearRail(
                entries: groups.map { YearRail.Entry(year: $0.year, count: $0.count) },
                activeYear: model.activeYear
            ) { year in
                jump(to: year)
            }

            Divider()

            thread(groups)
        }
    }

    /// The rows of the timeline, flattened so that the line can run through
    /// year markers and events alike without a break.
    private func thread(_ groups: [TimelineViewModel.YearGroup]) -> some View {
        let rows = model.rows(from: groups)

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        HStack(alignment: .top, spacing: 12) {
                            TimelineRailSegment(
                                marker: row.marker,
                                isFirst: index == 0,
                                isLast: index == rows.count - 1,
                                markerCentre: row.markerCentre
                            )

                            rowContent(row)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: Metrics.readableWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, 8)
                .padding(.bottom, 48)
            }
            .onChange(of: model.activeYear) { _, year in
                guard model.isJumping, let year else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(TimelineViewModel.Row.yearID(year), anchor: .top)
                }
                // The jump animation sweeps past intermediate years; ignore what
                // the rail sees until it settles.
                Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    model.isJumping = false
                }
            }
        }
    }

    @ViewBuilder
    private func rowContent(_ row: TimelineViewModel.Row) -> some View {
        switch row.kind {
        case .year(let year, let count):
            YearHeader(year: year, count: count)
                .id(row.id)
                .onScrollVisibilityChange(threshold: 0.1) { isVisible in
                    updateVisibility(of: year, isVisible: isVisible)
                }

        case .event(let event):
            Button {
                router.open(event: event.id)
            } label: {
                EventCard(event: event, attribution: store.archive.attribution(for: event))
            }
            .buttonStyle(.plain)
            .padding(.bottom, Metrics.rowSpacing)
            .contextMenu {
                Button(event.isPinned ? "Unpin" : "Pin to Dashboard") {
                    store.update { $0.setPinned(!event.isPinned, forEvent: event.id) }
                }
                Divider()
                StatusPicker(status: Binding(
                    get: { event.status },
                    set: { newStatus in
                        store.update { $0.setStatus(newStatus, forEvent: event.id) }
                    }
                ))
                .pickerStyle(.inline)
            }
        }
    }

    private func jump(to year: Int) {
        model.isJumping = true
        model.activeYear = year
    }

    private func updateVisibility(of year: Int, isVisible: Bool) {
        if isVisible {
            visibleYears.insert(year)
        } else {
            visibleYears.remove(year)
        }
        guard !model.isJumping else { return }
        // Years run newest first, so the topmost visible one is the largest.
        if let topmost = visibleYears.max(), topmost != model.activeYear {
            model.activeYear = topmost
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var filterMenu: some ToolbarContent {
        ToolbarItem(id: "timeline.new") {
            Button {
                router.newRecord()
            } label: {
                Label("New Medical Record", systemImage: "plus")
            }
        }

        ToolbarItem(id: "timeline.filter") {
            Menu {
                FilterSection(
                    title: "Statuses",
                    options: EventStatus.allCases,
                    label: \.title,
                    filter: $model.statuses
                )

                FilterSection(
                    title: "Categories",
                    options: EventCategory.allCases,
                    label: \.title,
                    symbol: \.symbol,
                    filter: $model.categories
                )

                Divider()
                Button("Show Everything") { model.clearFilter() }
                    .disabled(!model.isFiltered)
            } label: {
                FilterMenuLabel(isFiltering: model.isFiltered)
            }
            .menuIndicator(.hidden)
        }
    }

    // MARK: - Empty states

    private var emptyArchive: some View {
        ArchiveEmptyState(
            title: "No History Yet",
            message: "Every document you import becomes an event here, in the year it happened.",
            symbol: "calendar",
            actionTitle: "New Medical Record",
            action: { router.newRecord() }
        )
    }

    private var filteredToNothing: some View {
        ArchiveEmptyState(
            title: "Nothing Matches This Filter",
            message: "Your archive has events, but none that match what you are showing.",
            symbol: "line.3.horizontal.decrease.circle",
            actionTitle: "Show Everything",
            action: { model.clearFilter() }
        )
    }
}

/// The year marker on the thread. A landmark while scrolling, quiet enough not
/// to compete with the events under it.
struct YearHeader: View {
    let year: Int
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(String(year))
                .font(.title2.weight(.semibold))
                .monospacedDigit()
            Text("\(count) \(count == 1 ? "event" : "events")")
                .font(.caption)
                .foregroundStyle(Palette.tertiaryText)
            Spacer(minLength: 0)
        }
        .padding(.top, 20)
        .padding(.bottom, 12)
    }
}
