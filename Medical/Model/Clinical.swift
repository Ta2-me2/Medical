import Foundation

/// A diagnosis recorded at an event. The ICD-10 code is optional: most personal
/// paperwork does not carry one, and a missing code must never block recording
/// what the document actually says.
nonisolated struct Diagnosis: Identifiable, Hashable, Codable, Sendable {

    enum Status: String, Codable, CaseIterable, Sendable, Identifiable {
        case active
        case resolved
        case chronic
        case ruledOut

        var id: String { rawValue }

        var title: String {
            switch self {
            case .active: "Active"
            case .resolved: "Resolved"
            case .chronic: "Chronic"
            case .ruledOut: "Ruled out"
            }
        }
    }

    var id = UUID()
    var name: String
    var code: String?
    var status: Status = .active
    var notes: String?

    init(id: UUID = UUID(), name: String, code: String? = nil, status: Status = .active, notes: String? = nil) {
        self.id = id
        self.name = name
        self.code = code
        self.status = status
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey { case id, name, code, status, notes }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, or: UUID())
        name = c.value(.name, or: "Unnamed")
        code = c.value(.code)
        status = c.value(.status, or: .active)
        notes = c.value(.notes)
    }
}

/// A medication prescribed or taken.
nonisolated struct Medication: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var name: String
    var dosage: String?
    var frequency: String?
    var startDate: DateValue?
    var endDate: DateValue?
    var isOngoing: Bool = false
    var notes: String?

    init(
        id: UUID = UUID(),
        name: String,
        dosage: String? = nil,
        frequency: String? = nil,
        startDate: DateValue? = nil,
        endDate: DateValue? = nil,
        isOngoing: Bool = false,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.dosage = dosage
        self.frequency = frequency
        self.startDate = startDate
        self.endDate = endDate
        self.isOngoing = isOngoing
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, dosage, frequency, startDate, endDate, isOngoing, notes
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, or: UUID())
        name = c.value(.name, or: "Unnamed")
        dosage = c.value(.dosage)
        frequency = c.value(.frequency)
        startDate = c.value(.startDate)
        endDate = c.value(.endDate)
        isOngoing = c.value(.isOngoing, or: false)
        notes = c.value(.notes)
    }

    var summary: String {
        [dosage, frequency].compactMap(\.self).filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// A known allergy. Severity is one of the few things in this archive that
/// earns colour, because it is the one thing a stranger may need to read fast.
nonisolated struct Allergy: Identifiable, Hashable, Codable, Sendable {

    enum Severity: String, Codable, CaseIterable, Sendable, Identifiable, Comparable {
        case mild
        case moderate
        case severe
        case lifeThreatening

        var id: String { rawValue }

        var title: String {
            switch self {
            case .mild: "Mild"
            case .moderate: "Moderate"
            case .severe: "Severe"
            case .lifeThreatening: "Life-threatening"
            }
        }

        private var rank: Int {
            switch self {
            case .mild: 0
            case .moderate: 1
            case .severe: 2
            case .lifeThreatening: 3
            }
        }

        static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rank < rhs.rank }
    }

    var id = UUID()
    var substance: String
    var severity: Severity = .moderate
    var reaction: String?
    var notes: String?

    init(
        id: UUID = UUID(),
        substance: String,
        severity: Severity = .moderate,
        reaction: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.substance = substance
        self.severity = severity
        self.reaction = reaction
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey { case id, substance, severity, reaction, notes }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, or: UUID())
        substance = c.value(.substance, or: "Unknown")
        severity = c.value(.severity, or: .moderate)
        reaction = c.value(.reaction)
        notes = c.value(.notes)
    }
}

/// A long-running condition shown on the patient page.
nonisolated struct ChronicCondition: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var name: String
    var since: DateValue?
    var notes: String?

    init(id: UUID = UUID(), name: String, since: DateValue? = nil, notes: String? = nil) {
        self.id = id
        self.name = name
        self.since = since
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey { case id, name, since, notes }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, or: UUID())
        name = c.value(.name, or: "Unnamed")
        since = c.value(.since)
        notes = c.value(.notes)
    }
}

/// Something a stranger must know immediately — a pacemaker, an anticoagulant,
/// a transplant. Shown at the top of the patient page and nowhere else, so it
/// keeps its weight.
nonisolated struct MedicalAlert: Identifiable, Hashable, Codable, Sendable {

    enum Level: String, Codable, CaseIterable, Sendable, Identifiable {
        case critical
        case warning
        case info

        var id: String { rawValue }

        var title: String {
            switch self {
            case .critical: "Critical"
            case .warning: "Warning"
            case .info: "Information"
            }
        }
    }

    var id = UUID()
    var text: String
    var level: Level = .warning

    init(id: UUID = UUID(), text: String, level: Level = .warning) {
        self.id = id
        self.text = text
        self.level = level
    }

    private enum CodingKeys: String, CodingKey { case id, text, level }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, or: UUID())
        text = c.value(.text, or: "")
        level = c.value(.level, or: .warning)
    }
}

/// Who to call. Deliberately plain text — an emergency contact must survive the
/// contact leaving the address book.
nonisolated struct EmergencyContact: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var name: String
    var relationship: String?
    var phone: String?
    var email: String?

    init(
        id: UUID = UUID(),
        name: String,
        relationship: String? = nil,
        phone: String? = nil,
        email: String? = nil
    ) {
        self.id = id
        self.name = name
        self.relationship = relationship
        self.phone = phone
        self.email = email
    }

    private enum CodingKeys: String, CodingKey { case id, name, relationship, phone, email }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, or: UUID())
        name = c.value(.name, or: "Unnamed")
        relationship = c.value(.relationship)
        phone = c.value(.phone)
        email = c.value(.email)
    }
}
