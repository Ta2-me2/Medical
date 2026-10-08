import Foundation

/// What kind of medical event this is.
///
/// Categories are deliberately not colour coded. A lifetime timeline tinted by
/// thirteen different hues stops being readable; the symbol and the label carry
/// the meaning, and colour stays reserved for severity.
nonisolated enum EventCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case consultation
    case laboratory
    /// Functional testing — ECG, spirometry, Holter, ultrasound. Distinct from
    /// laboratory work on samples and from radiological imaging.
    case diagnostics
    case imaging
    case surgery
    case hospitalization
    case vaccination
    case dental
    case vision
    case prescription
    case emergency
    case screening
    case certificate
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .consultation: "Consultation"
        case .laboratory: "Laboratory"
        case .diagnostics: "Diagnostics"
        case .imaging: "Imaging"
        case .surgery: "Surgery"
        case .hospitalization: "Hospitalization"
        case .vaccination: "Vaccination"
        case .dental: "Dental"
        case .vision: "Vision"
        case .prescription: "Prescription"
        case .emergency: "Emergency"
        case .screening: "Screening"
        case .certificate: "Certificate"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .consultation: "stethoscope"
        case .laboratory: "testtube.2"
        case .diagnostics: "waveform.path.ecg"
        case .imaging: "scanner"
        case .surgery: "scissors"
        case .hospitalization: "bed.double"
        case .vaccination: "syringe"
        case .dental: "mouth"
        case .vision: "eye"
        case .prescription: "pills"
        case .emergency: "staroflife"
        case .screening: "list.bullet.clipboard"
        case .certificate: "checkmark.seal"
        case .other: "text.document"
        }
    }
}
