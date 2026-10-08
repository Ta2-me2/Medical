import Foundation

/// One thing in the cupboard.
///
/// Not a medical event and never on the timeline: a first-aid kit is an
/// inventory in the present tense. It says what is in the house today, it
/// changes when a box is used up, and none of it is history. Keeping it out of
/// `events` is what stops "bought paracetamol" from appearing between an
/// operation and a diagnosis.
nonisolated struct Medicine: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var name: String

    /// The owner's own words for what it is for — "fever and pain, after food".
    /// Free text on purpose: `kinds` is the vocabulary the checklist needs, and
    /// this is the sentence a person actually reaches for at two in the morning.
    var purpose: String?

    /// The sticker on the box. Chosen by the owner, never guessed from the name.
    var emoji: String?

    var expiry: DateValue?
    var quantity: String?

    /// Typed out when there is no leaflet worth photographing, or when the one
    /// in the packet is in a language nobody in the house reads.
    var instructions: String?

    /// Photographs or PDFs of the leaflet, from the same library as every other
    /// document — a scan of a packet insert is a document like any other.
    var attachments: [DocumentReference] = []

    /// Which of the recommended directions this covers. Ibuprofen that also
    /// brings a temperature down covers two, and should count for both.
    var kinds: [MedicineKind] = []

    var addedAt: Date = .now

    init(
        id: UUID = UUID(),
        name: String,
        purpose: String? = nil,
        emoji: String? = nil,
        expiry: DateValue? = nil,
        quantity: String? = nil,
        instructions: String? = nil,
        attachments: [DocumentReference] = [],
        kinds: [MedicineKind] = [],
        addedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.purpose = purpose
        self.emoji = emoji
        self.expiry = expiry
        self.quantity = quantity
        self.instructions = instructions
        self.attachments = attachments
        self.kinds = kinds
        self.addedAt = addedAt
    }

    /// The sticker, or the one its first direction suggests, or a plain pill.
    /// Never an empty square: the tile is read at a glance and the picture is
    /// most of what is being read.
    var displayEmoji: String {
        if let emoji = emoji?.nilIfEmpty { return emoji }
        return kinds.first?.suggestedEmoji ?? "💊"
    }

    var hasInstructions: Bool {
        instructions?.nilIfEmpty != nil || !attachments.isEmpty
    }

    /// The last day the box is good for.
    ///
    /// A packet printed "05/2027" is usable through the whole of May, not from
    /// the first of it. `DateValue` normalises to the start of whatever is
    /// known, so the useful day is the end of that period — otherwise every
    /// medicine dated by month would read as expired a month early.
    var lastUsefulDay: Date? {
        guard let expiry else { return nil }
        let calendar = Calendar.current
        let unit: Calendar.Component = switch expiry.precision {
        case .day: .day
        case .month: .month
        case .year: .year
        }
        guard let next = calendar.date(byAdding: unit, value: 1, to: expiry.date) else { return nil }
        return calendar.date(byAdding: .day, value: -1, to: next)
    }

    // MARK: - Tolerant decoding

    private enum CodingKeys: String, CodingKey {
        case id, name, purpose, emoji, expiry, quantity, instructions
        case attachments, kinds, addedAt
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, or: UUID())
        name = c.value(.name, or: "Unnamed medicine")
        purpose = c.value(.purpose)
        emoji = c.value(.emoji)
        expiry = c.value(.expiry)
        quantity = c.value(.quantity)
        instructions = c.value(.instructions)
        attachments = c.value(.attachments, or: [])
        kinds = c.value(.kinds, or: [])
        addedAt = c.value(.addedAt, or: .now)
    }
}

/// What a home first-aid kit is expected to cover.
///
/// Directions, never products. The app is able to say "there is nothing here
/// for an allergic reaction" because that is a fact about the cupboard. Which
/// antihistamine, at what dose, is a question for a pharmacist and for this
/// particular person's history — an archive that answered it would be claiming
/// a clinical authority it does not have and cannot earn.
nonisolated enum MedicineKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case painAndFever
    case allergy
    case coldAndThroat
    case digestion
    case antiseptic
    case dressings
    case burnsAndSkin
    case rehydration
    case instruments
    case ownPrescriptions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .painAndFever: "Pain and Fever"
        case .allergy: "Allergy"
        case .coldAndThroat: "Cold and Throat"
        case .digestion: "Stomach and Digestion"
        case .antiseptic: "Antiseptics"
        case .dressings: "Dressings"
        case .burnsAndSkin: "Burns and Skin"
        case .rehydration: "Rehydration"
        case .instruments: "Instruments"
        case .ownPrescriptions: "Your Own Prescriptions"
        }
    }

    /// One line saying what the gap is, in the words someone would use to
    /// describe the situation rather than the remedy.
    var explanation: String {
        switch self {
        case .painAndFever: "Something for a headache or a temperature"
        case .allergy: "Something for a reaction — a rash, a sting, hay fever"
        case .coldAndThroat: "Something for a sore throat, a blocked nose, a cough"
        case .digestion: "Something for an upset stomach, heartburn or nausea"
        case .antiseptic: "Something to clean a cut before covering it"
        case .dressings: "Plasters, gauze, tape — something to cover it with"
        case .burnsAndSkin: "Something for a burn, a graze or irritated skin"
        case .rehydration: "Oral rehydration salts, for a fever or a stomach bug"
        case .instruments: "A thermometer, tweezers, scissors, gloves"
        case .ownPrescriptions: "Whatever you take regularly, kept where you can find it"
        }
    }

    var symbol: String {
        switch self {
        case .painAndFever: "thermometer.medium"
        case .allergy: "allergens"
        case .coldAndThroat: "facemask"
        case .digestion: "fork.knife"
        case .antiseptic: "drop.triangle"
        case .dressings: "bandage"
        case .burnsAndSkin: "flame"
        case .rehydration: "drop"
        case .instruments: "scissors"
        case .ownPrescriptions: "pills"
        }
    }

    /// Offered as the sticker when the owner has not chosen one.
    var suggestedEmoji: String {
        switch self {
        case .painAndFever: "🤒"
        case .allergy: "🤧"
        case .coldAndThroat: "😷"
        case .digestion: "🍽️"
        case .antiseptic: "🧴"
        case .dressings: "🩹"
        case .burnsAndSkin: "🔥"
        case .rehydration: "💧"
        case .instruments: "🌡️"
        case .ownPrescriptions: "💊"
        }
    }

    /// The palette offered in the editor. Any emoji can be typed instead; these
    /// are simply the ones a cupboard usually needs.
    static let stickerPalette = [
        "💊", "🩹", "🌡️", "🧴", "💉", "🤒", "🤧", "😷",
        "🩺", "🧪", "🔥", "💧", "🍽️", "👁️", "👂", "🦷",
        "✂️", "🧤", "🌿", "🛡️", "🧼", "🫀", "🦴", "🧻",
    ]
}

/// The cupboard: what is in it, and which advice the owner has set aside.
///
/// A struct of its own rather than two more arrays on `Archive`, because it is
/// not part of the medical history — it is a second thing the same person keeps,
/// and the file should say so plainly.
nonisolated struct FirstAidKit: Codable, Hashable, Sendable {
    var medicines: [Medicine] = []

    /// Recommendations the owner has decided are not for them.
    ///
    /// Set aside, not deleted. Somebody with no children does not need a
    /// rehydration sachet on their conscience every time they open the page —
    /// but they may next year, so the advice waits in the recommendations sheet
    /// rather than disappearing.
    var hiddenKinds: [MedicineKind] = []

    var isEmpty: Bool { medicines.isEmpty }

    private enum CodingKeys: String, CodingKey { case medicines, hiddenKinds }

    init(medicines: [Medicine] = [], hiddenKinds: [MedicineKind] = []) {
        self.medicines = medicines
        self.hiddenKinds = hiddenKinds
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        medicines = c.value(.medicines, or: [])
        hiddenKinds = c.value(.hiddenKinds, or: [])
    }
}

/// A medicine that has run out of time, or is about to.
nonisolated struct MedicineExpiry: Identifiable, Hashable, Sendable {
    var medicineID: UUID
    var name: String
    var emoji: String

    /// The last day it is good for, not the first day of the printed period.
    var expiresOn: Date

    var id: UUID { medicineID }

    func isExpired(asOf now: Date = .now) -> Bool {
        expiresOn < Calendar.current.startOfDay(for: now)
    }

    /// `Expired 2 months ago` / `Expires in 3 weeks` / `Expires today`.
    func description(asOf now: Date = .now) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let end = calendar.startOfDay(for: expiresOn)

        if end == today { return "Expires today" }

        let earlier = min(today, end)
        let later = max(today, end)
        let months = calendar.dateComponents([.month], from: earlier, to: later).month ?? 0
        let days = calendar.dateComponents([.day], from: earlier, to: later).day ?? 0

        let span: String
        if months >= 24 {
            span = "\(months / 12) years"
        } else if months >= 1 {
            span = "\(months) \(months == 1 ? "month" : "months")"
        } else if days >= 14 {
            span = "\(days / 7) weeks"
        } else {
            span = "\(days) \(days == 1 ? "day" : "days")"
        }

        return end < today ? "Expired \(span) ago" : "Expires in \(span)"
    }
}
