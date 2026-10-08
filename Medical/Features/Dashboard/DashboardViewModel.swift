import Foundation

/// What the dashboard shows, read from the archive at this moment.
///
/// A value type rather than a stored object: there is no state here, only a
/// reading. The view stays free of logic and this stays trivially testable.
nonisolated struct DashboardViewModel {

    let patientName: String
    let pinned: [MedicalEvent]
    let recentEvents: [MedicalEvent]
    let recentDocuments: [DocumentRecord]
    let recentNotes: [NoteRecord]
    let inboxCount: Int
    let vaccinationsDue: [VaccinationDue]
    let medicinesExpiring: [MedicineExpiry]
    let isEmpty: Bool

    /// How many rows each list shows before it stops being a dashboard and
    /// starts being a worse version of the screen it summarises.
    private static let limit = 5
    private static let pinnedLimit = 8
    private static let dueLimit = 3

    init(archive: Archive) {
        patientName = archive.patient.displayName
        isEmpty = archive.isEmpty

        pinned = Array(archive.pinnedEvents.prefix(Self.pinnedLimit))
        recentEvents = archive.recentEvents(limit: Self.limit)
        recentDocuments = archive.recentDocuments(limit: Self.limit)
        recentNotes = archive.recentNotes(limit: Self.limit)
        inboxCount = archive.inboxCount
        // Capped hard: the dashboard reports what needs doing, it does not
        // become a vaccination schedule.
        vaccinationsDue = Array(archive.vaccinationsNeedingAttention().prefix(Self.dueLimit))
        // Same rule, same cap: a box that ran out last month is worth a line
        // here; the whole cupboard's dates are not.
        medicinesExpiring = Array(archive.medicinesExpiring().prefix(Self.dueLimit))
    }

    var hasAnything: Bool {
        !pinned.isEmpty || !recentEvents.isEmpty || !recentDocuments.isEmpty
            || !recentNotes.isEmpty || inboxCount > 0 || !vaccinationsDue.isEmpty
            || !medicinesExpiring.isEmpty
    }
}
