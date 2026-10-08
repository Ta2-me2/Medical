import Foundation

/// The person the archive belongs to.
///
/// One per archive. This is the passport page: the handful of facts that matter
/// when someone else has to make a decision quickly.
nonisolated struct Patient: Hashable, Codable, Sendable {

    enum BloodType: String, Codable, CaseIterable, Sendable, Identifiable {
        case aPositive = "A+"
        case aNegative = "A−"
        case bPositive = "B+"
        case bNegative = "B−"
        case abPositive = "AB+"
        case abNegative = "AB−"
        case oPositive = "O+"
        case oNegative = "O−"

        var id: String { rawValue }
        var title: String { rawValue }
    }

    var id = UUID()
    var fullName: String = ""
    var dateOfBirth: Date?
    var bloodType: BloodType?

    /// Centimetres and kilograms. Stored in one unit and formatted on the way
    /// out, so a change of locale can never reinterpret the stored number.
    var heightCM: Double?
    var weightKG: Double?

    var languages: [String] = []
    var emergencyContacts: [EmergencyContact] = []
    var allergies: [Allergy] = []
    var chronicConditions: [ChronicCondition] = []
    var alerts: [MedicalAlert] = []
    var summary: String = ""

    /// Filename inside the library's `Avatar/` folder, if one was set.
    var avatarFilename: String?

    init(
        id: UUID = UUID(),
        fullName: String = "",
        dateOfBirth: Date? = nil,
        bloodType: BloodType? = nil,
        heightCM: Double? = nil,
        weightKG: Double? = nil,
        languages: [String] = [],
        emergencyContacts: [EmergencyContact] = [],
        allergies: [Allergy] = [],
        chronicConditions: [ChronicCondition] = [],
        alerts: [MedicalAlert] = [],
        summary: String = "",
        avatarFilename: String? = nil
    ) {
        self.id = id
        self.fullName = fullName
        self.dateOfBirth = dateOfBirth
        self.bloodType = bloodType
        self.heightCM = heightCM
        self.weightKG = weightKG
        self.languages = languages
        self.emergencyContacts = emergencyContacts
        self.allergies = allergies
        self.chronicConditions = chronicConditions
        self.alerts = alerts
        self.summary = summary
        self.avatarFilename = avatarFilename
    }

    // MARK: - Derived

    var displayName: String { fullName.nilIfEmpty ?? "Unnamed" }

    var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    var age: Int? {
        guard let dateOfBirth else { return nil }
        return Calendar.current.dateComponents([.year], from: dateOfBirth, to: .now).year
    }

    var formattedDateOfBirth: String? {
        dateOfBirth?.formatted(.dateTime.day().month(.wide).year())
    }

    var formattedHeight: String? {
        heightCM.map { "\(Int($0.rounded())) cm" }
    }

    var formattedWeight: String? {
        weightKG.map { weight in
            weight == weight.rounded()
                ? "\(Int(weight)) kg"
                : String(format: "%.1f kg", weight)
        }
    }

    /// Allergies that a stranger needs to see first.
    var criticalAllergies: [Allergy] {
        allergies.filter { $0.severity >= .severe }.sorted { $0.severity > $1.severity }
    }

    // MARK: - Tolerant decoding

    private enum CodingKeys: String, CodingKey {
        case id, fullName, dateOfBirth, bloodType, heightCM, weightKG, languages
        case emergencyContacts, allergies, chronicConditions, alerts, summary, avatarFilename
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, or: UUID())
        fullName = c.value(.fullName, or: "")
        dateOfBirth = c.value(.dateOfBirth)
        bloodType = c.value(.bloodType)
        heightCM = c.value(.heightCM)
        weightKG = c.value(.weightKG)
        languages = c.value(.languages, or: [])
        emergencyContacts = c.value(.emergencyContacts, or: [])
        allergies = c.value(.allergies, or: [])
        chronicConditions = c.value(.chronicConditions, or: [])
        alerts = c.value(.alerts, or: [])
        summary = c.value(.summary, or: "")
        avatarFilename = c.value(.avatarFilename)
    }
}
