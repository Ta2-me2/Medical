import SwiftUI

/// Empty states are part of the design, not a placeholder.
///
/// A new archive is empty by definition, so these are the first screens the
/// owner ever sees. They say what the page is for and offer the one action that
/// makes sense there.
struct ArchiveEmptyState: View {
    let title: String
    let message: String
    let symbol: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        // Fills whatever it is given. Without this the enclosing stack sizes to
        // its content and gets centred as a whole, taking the filter bar above
        // it into the middle of the window with it.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Shown while the library folder is being opened for the first time.
struct ArchiveLoadingState: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text("Opening library…")
                .font(.callout)
                .foregroundStyle(Palette.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Shown when the library could not be read at all. Deliberately blunt: this is
/// the one failure in the app that the owner must not miss.
struct ArchiveFailureState: View {
    let message: String
    var retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Library Unavailable", systemImage: "exclamationmark.triangle")
                .foregroundStyle(Palette.critical)
        } description: {
            VStack(spacing: 8) {
                Text(message)
                Text(ArchiveLocation.current.path(percentEncoded: false))
                    .font(.caption.monospaced())
                    .foregroundStyle(Palette.tertiaryText)
                    .textSelection(.enabled)
            }
        } actions: {
            Button("Try Again", action: retry)
                .buttonStyle(.borderedProminent)
        }
    }
}
