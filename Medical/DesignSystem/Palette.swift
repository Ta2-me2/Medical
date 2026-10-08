import SwiftUI

/// The complete colour vocabulary.
///
/// Four colours carry meaning and nothing else does. Everything that is not a
/// selection, an alert, a warning or a completed state is grey — which is what
/// lets the four that remain be read instantly.
enum Palette {

    // MARK: - Meaning

    /// Selection and interactive emphasis. Follows the user's accent colour.
    static let selection = Color.accentColor

    /// Life-threatening allergies, medical alerts, integrity failures.
    static let critical = Color.red

    /// Things that need attention but are not dangerous.
    static let warning = Color.orange

    /// Completed courses, verified integrity, finished imports.
    static let complete = Color.green

    // MARK: - Surfaces

    /// Card and list-row surface, sitting on the window background.
    static let card = Color(nsColor: .controlBackgroundColor)

    /// The page itself.
    static let page = Color(nsColor: .windowBackgroundColor)

    /// Hairline rules between rows and around cards.
    static let separator = Color(nsColor: .separatorColor)

    /// Fill for chips, wells and empty thumbnails.
    static let subtleFill = Color(nsColor: .quaternaryLabelColor).opacity(0.5)

    // MARK: - Text

    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let tertiaryText = Color(nsColor: .tertiaryLabelColor)
}

extension EventStatus {
    var color: Color {
        switch self {
        case .normal: Palette.complete
        case .followUp: Palette.warning
        case .significant: Palette.critical
        }
    }
}

extension Allergy.Severity {
    var color: Color {
        switch self {
        case .mild, .moderate: Palette.secondaryText
        case .severe: Palette.warning
        case .lifeThreatening: Palette.critical
        }
    }
}

extension MedicalAlert.Level {
    var color: Color {
        switch self {
        case .critical: Palette.critical
        case .warning: Palette.warning
        case .info: Palette.secondaryText
        }
    }

    var symbol: String {
        switch self {
        case .critical: "exclamationmark.triangle.fill"
        case .warning: "exclamationmark.circle.fill"
        case .info: "info.circle.fill"
        }
    }
}

extension Diagnosis.Status {
    var color: Color {
        switch self {
        case .active: Palette.warning
        case .chronic: Palette.secondaryText
        case .resolved: Palette.complete
        case .ruledOut: Palette.tertiaryText
        }
    }
}
