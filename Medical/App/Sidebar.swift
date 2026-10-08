import SwiftUI

/// The standard macOS sidebar: the person the archive belongs to, then the
/// places their history can be looked at from.
struct Sidebar: View {
    @Environment(ArchiveStore.self) private var store
    @Bindable var router: Router

    var body: some View {
        List(selection: $router.selection) {
            Section {
                profileRow
                    .tag(SidebarItem.patient)
            }

            Section {
                ForEach(SidebarItem.navigationItems) { item in
                    Label(item.title, systemImage: item.symbol)
                        .badge(item == .inbox ? store.archive.inboxCount : 0)
                        .tag(item)
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            // Beside the sidebar toggle, where the window's own controls live
            // rather than the archive's.
            ToolbarItem(id: "sidebar.appearance", placement: .navigation) {
                AppearanceMenu()
            }
        }
        .navigationSplitViewColumnWidth(
            min: Metrics.sidebarMin,
            ideal: Metrics.sidebarIdeal,
            max: Metrics.sidebarMax
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SaveIndicator(state: store.saveState)
        }
    }

    private var profileRow: some View {
        HStack(spacing: 9) {
            PatientAvatar(patient: store.archive.patient, url: store.avatarURL())
            VStack(alignment: .leading, spacing: 1) {
                Text(store.archive.patient.displayName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text("Personal Medical Archive")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}

/// A single quiet line telling the owner their archive is written to disk.
///
/// A local-first archive has no cloud spinner to reassure anyone, so it says so
/// itself — and stays silent once everything is saved.
struct SaveIndicator: View {
    let state: ArchiveStore.SaveState

    var body: some View {
        Group {
            switch state {
            case .saved:
                EmptyView()
            case .pending, .saving:
                label("Saving…", symbol: "arrow.clockwise", tint: Palette.secondaryText)
            case .failed(let message):
                label(message, symbol: "exclamationmark.triangle.fill", tint: Palette.critical)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: state)
    }

    private func label(_ text: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .imageScale(.small)
            Text(text)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(tint)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
