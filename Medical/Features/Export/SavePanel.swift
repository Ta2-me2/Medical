import AppKit
import UniformTypeIdentifiers

/// Asking where to save, and nothing else.
///
/// SwiftUI's `fileExporter` insists on writing a document of its own to the
/// chosen URL, and that write lands *after* the completion handler runs. For an
/// export that is assembled on disk — a folder zipped by `ditto` — the result is
/// that the placeholder overwrites the finished archive and the user is handed a
/// zero-byte file that no unarchiver will open.
///
/// So this asks for the destination and stops there. Whoever called it writes
/// the bytes, and nothing writes them twice.
@MainActor
enum SavePanel {

    static func destination(suggestedName: String, contentType: UTType) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [contentType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.showsTagField = false

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url
    }

    static func fileToOpen(contentType: UTType) -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [contentType]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url
    }
}
