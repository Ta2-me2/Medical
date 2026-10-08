import SwiftUI

/// The window: sidebar on the left, one section at a time on the right.
struct RootView: View {
    @Environment(ArchiveStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router

        NavigationSplitView {
            Sidebar(router: router)
        } detail: {
            NavigationStack(path: $router.path) {
                detail
                    .navigationDestination(for: Destination.self) { destination in
                        switch destination {
                        case .event(let id):
                            EventDetailView(eventID: id)
                        }
                    }
            }
        }
        .searchable(
            text: $router.searchText,
            placement: .toolbar,
            prompt: "Search the archive"
        )
        .sheet(item: $router.newRecordSource) { source in
            EventEditorView(source: source, archive: store.archive)
                .environment(store)
                .environment(router)
        }
        .task {
            await store.load()
            await DemoArchive.seedIfNeeded(into: store)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch store.loadState {
        case .loading:
            ArchiveLoadingState()
        case .failed(let message):
            ArchiveFailureState(message: message) {
                Task { await store.load() }
            }
        case .ready:
            if router.isSearching {
                // Search replaces whatever section is open rather than pushing
                // onto it, so leaving search always returns you where you were.
                SearchResultsView(query: router.searchText)
            } else {
                section
            }
        }
    }

    @ViewBuilder
    private var section: some View {
        switch router.selection ?? .dashboard {
        case .patient: PatientView()
        case .dashboard: DashboardView()
        case .timeline: TimelineView()
        case .documents: DocumentsView()
        case .inbox: InboxView()
        case .vaccinations: VaccinationsView()
        case .firstAidKit: FirstAidKitView()
        case .notes: NotesView()
        case .export: ExportView()
        }
    }
}
