import Foundation

/// How much attention an event still needs.
///
/// Chosen by hand, never inferred. The archive has no opinion about whether a
/// result was good news — only the person living the history does, and a guess
/// here would be worse than no answer.
nonisolated enum EventStatus: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Read, understood, nothing outstanding.
    case normal
    /// Something to come back to — a repeat test, a referral, a recheck.
    case followUp
    /// A turning point in the history. Surgery, a diagnosis, an emergency.
    case significant

    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal: "Normal"
        case .followUp: "Follow-up"
        case .significant: "Significant"
        }
    }

    /// Shown only where the status carries information. `normal` is the resting
    /// state of almost every event in a long archive; labelling all of them
    /// would bury the two statuses that mean something.
    var deservesLabel: Bool { self != .normal }
}
