import Foundation

/// Checks the cupboard: when a box counts as expired, which directions read as
/// missing, and what a leaflet does to the document it is filed against.
func checkFirstAidKit() {
    section("Expiry dates on packets")

    let today = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 9))!

    func box(_ name: String, expires: DateValue?, kinds: [MedicineKind] = []) -> Medicine {
        Medicine(name: name, expiry: expires, kinds: kinds)
    }

    /// What is printed on the packet, at the precision it is printed to.
    func printed(_ year: Int, _ month: Int = 1, _ dayOfMonth: Int = 1,
                 as precision: DateValue.Precision) -> DateValue {
        DateValue(
            Calendar.current.date(from: DateComponents(year: year, month: month, day: dayOfMonth))!,
            precision: precision
        )
    }

    // A packet printed "09/2026" is good to the end of September, not from the
    // first of it. This is the whole reason `lastUsefulDay` exists.
    let thisMonth = box("Paracetamol", expires: printed(2026, 9, 1, as: .month))
    check("a packet dated by month lasts to the end of it",
          thisMonth.lastUsefulDay.map { Calendar.current.component(.day, from: $0) } == 30)

    var kit = Archive()
    kit.upsert(thisMonth)
    check("and is not called expired on its first day",
          kit.medicinesExpiring(asOf: today).first?.isExpired(asOf: today) == false)

    let lastYear = box("Old syrup", expires: printed(2025, 4, 1, as: .month))
    var expired = Archive()
    expired.upsert(lastYear)
    let overdue = expired.medicinesExpiring(asOf: today)
    check("a packet from last year is expired", overdue.first?.isExpired(asOf: today) == true)
    // Months up to two years, the same wording the booster reminders use — one
    // vocabulary for "how long ago" across the whole application.
    check("and says how long ago", overdue.first?.description(asOf: today) == "Expired 16 months ago")

    let dayPrecision = box("Eye drops", expires: printed(2026, 9, 9, as: .day))
    check("a packet dated to the day expires on that day, not before",
          dayPrecision.lastUsefulDay.map { Calendar.current.startOfDay(for: $0) }
            == Calendar.current.startOfDay(for: today))

    let byYear = box("Bandages", expires: printed(2026, 1, 1, as: .year))
    check("a packet dated by year lasts to the end of December",
          byYear.lastUsefulDay.map { Calendar.current.component(.month, from: $0) } == 12)

    var far = Archive()
    far.upsert(box("Plasters", expires: printed(2030, 1, 1, as: .month)))
    check("a packet years away is not reported", far.medicinesExpiring(asOf: today).isEmpty)

    var undated = Archive()
    undated.upsert(box("Tweezers", expires: nil))
    check("something with no date on it is never reported",
          undated.medicinesExpiring(asOf: today).isEmpty)

    section("What the kit says is missing")

    var stocked = Archive()
    stocked.upsert(box("Ibuprofen", expires: nil, kinds: [.painAndFever, .coldAndThroat]))

    check("a direction with something in it is not missing",
          !stocked.missingMedicineKinds.contains(.painAndFever))
    check("one medicine can cover two directions",
          !stocked.missingMedicineKinds.contains(.coldAndThroat))
    check("and the rest are still missing",
          stocked.missingMedicineKinds.count == MedicineKind.allCases.count - 2)
    check("it stands on both shelves",
          stocked.medicines(of: .painAndFever).count == 1
            && stocked.medicines(of: .coldAndThroat).count == 1)

    // Setting a recommendation aside stops it being counted, without deleting it.
    stocked.setHidden(true, forKind: .rehydration)
    check("a recommendation set aside stops counting as missing",
          !stocked.missingMedicineKinds.contains(.rehydration))
    check("but it is still one of the recommendations",
          MedicineKind.allCases.contains(.rehydration))
    check("and the kit knows it was set aside", stocked.isHidden(.rehydration))

    stocked.setHidden(true, forKind: .rehydration)
    check("setting it aside twice does not record it twice",
          stocked.firstAidKit.hiddenKinds.count == 1)

    stocked.setHidden(false, forKind: .rehydration)
    check("and it comes back", stocked.missingMedicineKinds.contains(.rehydration))

    var unfiled = Archive()
    unfiled.upsert(box("Something", expires: nil, kinds: []))
    check("a medicine filed under nothing sits on its own shelf",
          unfiled.unsortedMedicines.count == 1)
    check("and appears on no other", unfiled.stockedMedicineKinds.isEmpty)

    section("Leaflets are documents like any other")

    let leaflet = StoredDocument(
        originalFilename: "leaflet.pdf",
        relativePath: "Originals/2026/leaflet.pdf",
        contentHash: "hash",
        byteSize: 2048,
        kind: .pdf,
        pageCount: 2
    )

    var filed = Archive()
    filed.documents = [leaflet]
    var withLeaflet = box("Nurofen", expires: nil, kinds: [.painAndFever])
    withLeaflet.attachments = [DocumentReference(documentID: leaflet.id)]
    filed.upsert(withLeaflet)

    check("a leaflet in the kit counts as filed, not as inbox",
          filed.status(ofDocumentID: leaflet.id) == .used)
    check("the inbox does not claim it", filed.inboxCount == 0)
    check("and the kit can say which medicine cites it",
          filed.medicines(using: leaflet.id).first?.name == "Nurofen")

    filed.removeDocument(id: leaflet.id)
    check("removing the document detaches it from the medicine",
          filed.medicine(id: withLeaflet.id)?.attachments.isEmpty == true)
    check("and the medicine itself stays in the kit", filed.medicineCount == 1)

    section("Editing the kit")

    var edits = Archive()
    var pill = box("Aspirin", expires: nil)
    edits.upsert(pill)
    pill.purpose = "Headache"
    edits.upsert(pill)
    check("saving the same medicine twice edits it rather than duplicating it",
          edits.medicineCount == 1)
    check("and keeps the edit", edits.medicine(id: pill.id)?.purpose == "Headache")

    edits.removeMedicine(id: pill.id)
    check("removing it empties the kit", edits.firstAidKit.isEmpty)

    section("The sticker on the box")

    check("the owner's own sticker wins",
          Medicine(name: "X", emoji: "🦴", kinds: [.painAndFever]).displayEmoji == "🦴")
    check("otherwise the direction suggests one",
          Medicine(name: "X", kinds: [.dressings]).displayEmoji == MedicineKind.dressings.suggestedEmoji)
    check("and something with neither still has a picture",
          Medicine(name: "X").displayEmoji.isEmpty == false)

    section("Whether there is anything to read")

    // Gates the Instructions button on the tile: no button when there is
    // nothing behind it, and one as soon as either half exists.
    check("nothing written and nothing attached means nothing to read",
          Medicine(name: "Tweezers").hasInstructions == false)
    check("typed instructions are something to read",
          Medicine(name: "Loratadine", instructions: "One a day.").hasInstructions)
    check("blank typed instructions are not",
          Medicine(name: "Loratadine", instructions: "   ").hasInstructions == false)
    check("an attached leaflet is something to read",
          withLeaflet.hasInstructions)

    section("The kit survives a round trip")

    var full = Archive()
    var complete = Medicine(
        name: "Loratadine",
        purpose: "Hay fever",
        emoji: "🤧",
        expiry: printed(2027, 5, 1, as: .month),
        quantity: "10 tablets",
        instructions: "One a day, with water.",
        kinds: [.allergy]
    )
    complete.attachments = [DocumentReference(documentID: leaflet.id)]
    full.upsert(complete)
    full.setHidden(true, forKind: .instruments)

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    if let data = try? encoder.encode(full), let back = try? decoder.decode(Archive.self, from: data) {
        let restored = back.medicine(id: complete.id)
        check("the medicine comes back", restored?.name == "Loratadine")
        check("with its sticker", restored?.emoji == "🤧")
        check("with its expiry and precision",
              restored?.expiry?.precision == .month && restored?.expiry?.year == 2027)
        check("with what it is for", restored?.purpose == "Hay fever")
        check("with its written instructions", restored?.instructions == "One a day, with water.")
        check("with its leaflet", restored?.attachments.count == 1)
        check("with the direction it covers", restored?.kinds == [.allergy])
        check("and with what was set aside", back.isHidden(.instruments))
    } else {
        check("the kit survives a round trip", false)
    }

    // An archive written before the kit existed has no such key at all.
    let older = """
        {"formatVersion":2,"archiveID":"\(UUID().uuidString)","createdAt":"2020-01-01T00:00:00Z"}
        """
    if let data = older.data(using: .utf8), let back = try? decoder.decode(Archive.self, from: data) {
        check("an archive written before the kit existed still opens", back.firstAidKit.isEmpty)
        check("and every recommendation reads as missing",
              back.missingMedicineKinds.count == MedicineKind.allCases.count)
    } else {
        check("an archive written before the kit existed still opens", false)
    }

    section("Recommendations are directions, not products")

    check("every direction says what the gap is, not what to buy",
          MedicineKind.allCases.allSatisfy { !$0.explanation.isEmpty })
    check("every direction has a sticker and a symbol",
          MedicineKind.allCases.allSatisfy { !$0.suggestedEmoji.isEmpty && !$0.symbol.isEmpty })
}
