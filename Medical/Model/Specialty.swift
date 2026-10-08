import Foundation

/// The field of medicine an event belongs to.
///
/// Separate from `EventCategory`: a consultation and an MRI can both belong to
/// neurology, and exporting "everything neurological" is a real need when
/// changing doctors.
nonisolated enum Specialty: String, Codable, CaseIterable, Sendable, Identifiable {
    case generalPractice
    case cardiology
    case dermatology
    case neurology
    case ophthalmology
    case orthopedics
    case dentistry
    case gastroenterology
    case endocrinology
    case pulmonology
    case urology
    case gynecology
    case psychiatry
    case pediatrics
    case oncology
    case otolaryngology
    case allergology
    case immunology
    case rheumatology
    case surgery
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .generalPractice: "General Practice"
        case .cardiology: "Cardiology"
        case .dermatology: "Dermatology"
        case .neurology: "Neurology"
        case .ophthalmology: "Ophthalmology"
        case .orthopedics: "Orthopedics"
        case .dentistry: "Dentistry"
        case .gastroenterology: "Gastroenterology"
        case .endocrinology: "Endocrinology"
        case .pulmonology: "Pulmonology"
        case .urology: "Urology"
        case .gynecology: "Gynecology"
        case .psychiatry: "Psychiatry"
        case .pediatrics: "Pediatrics"
        case .oncology: "Oncology"
        case .otolaryngology: "Ear, Nose & Throat"
        case .allergology: "Allergology"
        case .immunology: "Immunology"
        case .rheumatology: "Rheumatology"
        case .surgery: "Surgery"
        case .other: "Other"
        }
    }
}
