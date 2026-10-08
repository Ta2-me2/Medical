import Foundation

/// A doctor, stored once and referenced by every event they appear in.
///
/// Kept as a top-level record rather than a string on the event so that
/// "every visit to Dr. Silva since 2011" is a lookup, not a text search.
nonisolated struct Doctor: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var name: String
    var specialty: Specialty?
    var facilityID: UUID?
    var phone: String?
    var email: String?
    var notes: String?

    init(
        id: UUID = UUID(),
        name: String,
        specialty: Specialty? = nil,
        facilityID: UUID? = nil,
        phone: String? = nil,
        email: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.specialty = specialty
        self.facilityID = facilityID
        self.phone = phone
        self.email = email
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, specialty, facilityID, phone, email, notes
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, or: UUID())
        name = c.value(.name, or: "Unnamed")
        specialty = c.value(.specialty)
        facilityID = c.value(.facilityID)
        phone = c.value(.phone)
        email = c.value(.email)
        notes = c.value(.notes)
    }
}

/// A hospital, clinic, laboratory or pharmacy.
nonisolated struct Facility: Identifiable, Hashable, Codable, Sendable {

    enum Kind: String, Codable, CaseIterable, Sendable, Identifiable {
        case hospital
        case clinic
        case laboratory
        case pharmacy
        case dentalOffice
        case other

        var id: String { rawValue }

        var title: String {
            switch self {
            case .hospital: "Hospital"
            case .clinic: "Clinic"
            case .laboratory: "Laboratory"
            case .pharmacy: "Pharmacy"
            case .dentalOffice: "Dental Office"
            case .other: "Other"
            }
        }
    }

    var id = UUID()
    var name: String
    var kind: Kind = .clinic
    var address: String?
    var city: String?
    var country: String?
    var phone: String?

    init(
        id: UUID = UUID(),
        name: String,
        kind: Kind = .clinic,
        address: String? = nil,
        city: String? = nil,
        country: String? = nil,
        phone: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.address = address
        self.city = city
        self.country = country
        self.phone = phone
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, address, city, country, phone
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, or: UUID())
        name = c.value(.name, or: "Unnamed")
        kind = c.value(.kind, or: .clinic)
        address = c.value(.address)
        city = c.value(.city)
        country = c.value(.country)
        phone = c.value(.phone)
    }

    var location: String? {
        [city, country].compactMap(\.self).filter { !$0.isEmpty }.joined(separator: ", ").nilIfEmpty
    }
}

/// A free-form label. Tags are the escape hatch for structure the fixed schema
/// does not anticipate — over decades there will always be some.
nonisolated struct Tag: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var name: String

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }

    private enum CodingKeys: String, CodingKey { case id, name }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, or: UUID())
        name = c.value(.name, or: "Untitled")
    }
}
