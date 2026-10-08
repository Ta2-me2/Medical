import AppKit
import Observation
import SwiftUI

/// How the application looks, and where that choice is kept.
///
/// Two settings, both about appearance, both applied to AppKit rather than to
/// SwiftUI. `preferredColorScheme` reaches the views it is attached to and
/// nothing else — not the save panel, not an alert, not a window opened from
/// the menu bar — and an archive that turns white halfway through a task is a
/// worse thing than no dark mode at all. `NSApplication.appearance` reaches
/// everything the process draws.
@Observable
final class AppSettings {

    enum Appearance: String, CaseIterable, Identifiable, Sendable {
        case system
        case light
        case dark

        var id: String { rawValue }

        var title: String {
            switch self {
            case .system: "System"
            case .light: "Light"
            case .dark: "Dark"
            }
        }

        /// `nil` means "whatever the Mac is set to", which is what AppKit wants
        /// to hear in order to follow it.
        var nsAppearance: NSAppearance? {
            switch self {
            case .system: nil
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
            }
        }
    }

    enum Icon: String, CaseIterable, Identifiable, Sendable {
        case light
        case dark

        var id: String { rawValue }

        var title: String {
            switch self {
            case .light: "Light"
            case .dark: "Dark"
            }
        }

        var assetName: String {
            switch self {
            case .light: "IconLight"
            case .dark: "IconDark"
            }
        }

        var image: NSImage? { NSImage(named: assetName) }
    }

    private static let appearanceKey = "appearance"
    private static let iconKey = "appIcon"

    var appearance: Appearance {
        didSet {
            guard oldValue != appearance else { return }
            UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey)
            apply()
        }
    }

    var icon: Icon {
        didSet {
            guard oldValue != icon else { return }
            UserDefaults.standard.set(icon.rawValue, forKey: Self.iconKey)
            apply()
        }
    }

    init() {
        let defaults = UserDefaults.standard
        appearance = defaults.string(forKey: Self.appearanceKey)
            .flatMap(Appearance.init(rawValue:)) ?? .system
        icon = defaults.string(forKey: Self.iconKey)
            .flatMap(Icon.init(rawValue:)) ?? .light
    }

    /// Called at launch as well as on every change: a Dock icon set before the
    /// application has finished launching does not always survive it.
    func apply() {
        NSApplication.shared.appearance = appearance.nsAppearance
        if let image = icon.image {
            NSApplication.shared.applicationIconImage = image
        }
    }
}
