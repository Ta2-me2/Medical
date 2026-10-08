import Foundation

/// Fills a brand-new library with a plausible twenty-year history.
///
/// Runs once, only when the archive is genuinely empty, so nothing is ever
/// added on top of real records. The documents it creates are real PDFs written
/// into the library and hashed like any other import — the sample archive
/// exercises the same code path as the real one, rather than pretending.
enum DemoArchive {

    private static let seededKey = "didSeedSampleArchive"

    static func seedIfNeeded(into store: ArchiveStore) async {
        guard store.loadState == .ready,
              store.archive.isEmpty,
              !UserDefaults.standard.bool(forKey: Self.seededKey)
        else { return }

        UserDefaults.standard.set(true, forKey: Self.seededKey)

        var archive = Archive()
        archive.patient = samplePatient()

        let silva = Doctor(name: "Dr. Marta Silva", specialty: .cardiology)
        let carter = Doctor(name: "Dr. Helen Carter", specialty: .generalPractice)
        let hale = Doctor(name: "Dr. Owen Hale", specialty: .orthopedics)
        let reed = Doctor(name: "Dr. Alan Reed", specialty: .dermatology)
        archive.doctors = [silva, carter, hale, reed]

        let hospital = Facility(name: "Northgate Medical Center", kind: .hospital, city: "Northgate", country: "United States")
        let cityClinic = Facility(name: "Westbrook Family Clinic", kind: .clinic, city: "Westbrook", country: "United States")
        let lab = Facility(name: "Harbor Point Laboratory", kind: .laboratory, city: "Northgate", country: "United States")
        let dental = Facility(name: "Elm Street Dental", kind: .dentalOffice, city: "Westbrook", country: "United States")
        archive.facilities = [hospital, cityClinic, lab, dental]

        for template in templates() {
            var event = MedicalEvent(
                date: DateValue(date(template.year, template.month, template.day), precision: template.precision),
                category: template.category,
                specialty: template.specialty,
                status: template.status,
                isPinned: template.pinned,
                title: template.title,
                summary: template.summary
            )
            event.doctorID = doctorID(for: template, silva: silva, carter: carter, hale: hale, reed: reed)
            event.facilityID = facilityID(for: template, hospital: hospital, clinic: cityClinic, lab: lab, dental: dental)
            event.diagnoses = template.diagnoses
            event.medications = template.medications
            event.vaccinations = template.vaccinations
            event.translations = template.translations
            event.tables = template.tables
            if let note = template.note {
                event.notes = [Note(body: note, createdAt: event.date.date, updatedAt: event.date.date)]
            }

            if template.hasDocument {
                if let document = await makeDocument(for: template, event: event, store: store) {
                    archive.documents.append(document)
                    event.attachments = [DocumentReference(documentID: document.id)]
                    if !event.vaccinations.isEmpty {
                        event.vaccinations[0].certificateDocumentID = document.id
                    }
                }
            }

            archive.events.append(event)
        }

        // Two scans nobody has filed yet, so the inbox is not an empty screen
        // the first time it is opened.
        archive.documents.append(contentsOf: await makeInboxDocuments(store: store))

        // Paperwork that belongs in the library but never in a history.
        for var document in await makeArchivedDocuments(store: store) {
            document.isArchived = true
            archive.documents.append(document)
        }

        // The case the page ranges exist for: one long childhood card that
        // several records draw different pages from, never cut up.
        await addChildhoodCard(to: &archive, store: store)

        // A cupboard with something in it, including one box past its date, so
        // the section demonstrates what it is for rather than its empty state.
        archive.firstAidKit = FirstAidKit(medicines: sampleMedicines())

        store.update { $0 = archive }
        await store.saveNow()
    }

    /// What a modest home kit holds. Names are generic rather than branded: the
    /// sample is there to show the shelves, not to recommend a product.
    private static func sampleMedicines() -> [Medicine] {
        [
            Medicine(
                name: "Ibuprofen 200 mg",
                purpose: "Fever and pain",
                emoji: "🤒",
                expiry: DateValue(date(2028, 3, 1), precision: .month),
                quantity: "24 tablets",
                instructions: """
                    Adults and children over 12: one tablet every 6 to 8 hours, \
                    with food. No more than three tablets in 24 hours.
                    """,
                kinds: [.painAndFever]
            ),
            Medicine(
                name: "Cetirizine 10 mg",
                purpose: "Hay fever, rashes, insect bites",
                emoji: "🤧",
                expiry: DateValue(date(2027, 9, 1), precision: .month),
                quantity: "10 tablets",
                instructions: "One tablet a day, at any time of day.",
                kinds: [.allergy]
            ),
            Medicine(
                name: "Antiseptic solution",
                purpose: "Cleaning cuts and grazes",
                emoji: "🧴",
                expiry: DateValue(date(2026, 8, 1), precision: .month),
                quantity: "100 ml bottle",
                kinds: [.antiseptic]
            ),
            Medicine(
                name: "Assorted plasters",
                purpose: "Covering small cuts",
                emoji: "🩹",
                quantity: "Two sizes, about 20 left",
                kinds: [.dressings]
            ),
            Medicine(
                name: "Digital thermometer",
                purpose: "Taking a temperature",
                emoji: "🌡️",
                kinds: [.instruments]
            ),
            Medicine(
                name: "Oral rehydration salts",
                purpose: "Fever, stomach upsets",
                emoji: "💧",
                expiry: DateValue(date(2029, 1, 1), precision: .month),
                quantity: "6 sachets",
                instructions: "One sachet dissolved in 200 ml of water.",
                kinds: [.rehydration, .digestion]
            ),
        ]
    }

    // MARK: - Documents

    /// Writes a small PDF to a temporary file, then imports it through the real
    /// import path so it lands in `Originals/` with a proper hash.
    private static func makeDocument(
        for template: Template,
        event: MedicalEvent,
        store: ArchiveStore
    ) async -> StoredDocument? {
        let filename = "\(FileArchivePersistence.slug(from: template.title)).pdf"
        let temporary = FileManager.default.temporaryDirectory.appending(path: filename)

        let blocks: [PDFReport.Block] = [
            .title(template.documentHeading ?? template.title),
            .caption("\(template.facility) · \(DateValue(date(template.year, template.month, template.day), precision: template.precision).formatted)"),
            .heading("Findings"),
            .body(template.summary),
            .heading("Notes"),
            .body(template.note ?? "No additional remarks."),
            .caption("This is sample content generated by Medical to demonstrate the archive."),
        ]

        do {
            try await Task.detached(priority: .userInitiated) {
                try PDFReport.render(blocks, title: template.title, to: temporary)
            }.value
            let document = try await store.storeOriginal(from: temporary, year: template.year, title: template.title)
            try? FileManager.default.removeItem(at: temporary)
            return document
        } catch {
            return nil
        }
    }

    /// Documents that arrive with no record attached — the state every import
    /// starts in.
    private static func makeInboxDocuments(store: ArchiveStore) async -> [StoredDocument] {
        let drafts = [
            ("Scanned referral letter", "Referral to orthopaedics. Illegible signature, clinic stamp only."),
            ("Pharmacy receipt 2026", "Receipt for inhaler refill. Kept for insurance."),
        ]

        var documents: [StoredDocument] = []
        for (title, body) in drafts {
            let temporary = FileManager.default.temporaryDirectory
                .appending(path: "\(FileArchivePersistence.slug(from: title)).pdf")
            let blocks: [PDFReport.Block] = [
                .title(title),
                .body(body),
                .caption("This is sample content generated by Medical to demonstrate the archive."),
            ]
            do {
                try await Task.detached(priority: .userInitiated) {
                    try PDFReport.render(blocks, title: title, to: temporary)
                }.value
                let year = Calendar.current.component(.year, from: .now)
                documents.append(try await store.storeOriginal(from: temporary, year: year, title: title))
                try? FileManager.default.removeItem(at: temporary)
            } catch {
                continue
            }
        }
        return documents
    }

    /// A ninety-page scan of a paper childhood medical card, cited by three
    /// records at three different page ranges.
    private static func addChildhoodCard(to archive: inout Archive, store: ArchiveStore) async {
        let title = "Childhood Medical Card"
        let temporary = FileManager.default.temporaryDirectory
            .appending(path: "childhood-medical-card.pdf")

        var blocks: [PDFReport.Block] = []
        for page in 1...90 {
            if page > 1 { blocks.append(.pageBreak) }
            blocks.append(.title("Childhood Medical Card"))
            blocks.append(.caption("Westbrook Family Clinic · page \(page) of 90"))
            blocks.append(.body(cardPageText(page)))
        }

        guard (try? await Task.detached(priority: .userInitiated) {
            try PDFReport.render(blocks, title: title, to: temporary)
        }.value) != nil,
        let document = try? await store.storeOriginal(from: temporary, year: 1998, title: title)
        else { return }
        try? FileManager.default.removeItem(at: temporary)

        archive.documents.append(document)

        let citations: [(String, EventCategory, Int, Int, String, PageSelection)] = [
            ("Childhood vaccination schedule", .vaccination, 1998, 1,
             "Pages of the paper card covering routine childhood immunisation.",
             PageSelection(ranges: [PageRange(first: 15, last: 17)])),
            ("Routine school examination", .screening, 2001, 9,
             "Annual school medical, recorded on the card by the school nurse.",
             PageSelection(ranges: [PageRange(first: 42, last: 43)])),
            ("Chickenpox", .consultation, 2002, 3,
             "Childhood chickenpox, managed at home. One line on the card.",
             PageSelection(ranges: [PageRange(first: 58, last: 58)])),
        ]

        for (title, category, year, month, summary, pages) in citations {
            var event = MedicalEvent(
                date: DateValue(date(year, month, 1), precision: .month),
                category: category,
                title: title,
                summary: summary
            )
            event.attachments = [DocumentReference(documentID: document.id, pages: pages)]
            archive.events.append(event)
        }
    }

    private static func cardPageText(_ page: Int) -> String {
        """
        This page stands in for one sheet of a scanned paper medical card. \
        In a real archive it would carry handwriting, stamps and a nurse's \
        signature. What matters for the demonstration is that the file stays \
        whole: three separate medical records point at pages 15–17, 42–43 and \
        58 of this same document, and none of them required cutting it up.
        """
    }

    /// Documents that belong in the library but never in a history.
    private static func makeArchivedDocuments(store: ArchiveStore) async -> [StoredDocument] {
        let drafts = [
            ("Health visitor notes 1992", "Routine home visits during the first year. No findings."),
            ("Insurance policy 2019", "Administrative paperwork. Kept for reference only."),
        ]

        var documents: [StoredDocument] = []
        for (title, body) in drafts {
            let temporary = FileManager.default.temporaryDirectory
                .appending(path: "\(FileArchivePersistence.slug(from: title)).pdf")
            let blocks: [PDFReport.Block] = [
                .title(title),
                .body(body),
                .caption("This is sample content generated by Medical to demonstrate the archive."),
            ]
            do {
                try await Task.detached(priority: .userInitiated) {
                    try PDFReport.render(blocks, title: title, to: temporary)
                }.value
                documents.append(try await store.storeOriginal(from: temporary, year: 2019, title: title))
                try? FileManager.default.removeItem(at: temporary)
            } catch {
                continue
            }
        }
        return documents
    }

    // MARK: - Patient

    private static func samplePatient() -> Patient {
        Patient(
            fullName: "John Appleseed",
            dateOfBirth: date(1991, 4, 18),
            bloodType: .aPositive,
            heightCM: 182,
            weightKG: 78.5,
            languages: ["English", "Spanish"],
            emergencyContacts: [
                // Apple's own sample person, and a number from the range set
                // aside for fiction. Sample data goes out with the application
                // to anyone who builds it, so it must belong to nobody.
                EmergencyContact(name: "Mary Appleseed", relationship: "Mother", phone: "+1 555 0147"),
            ],
            allergies: [
                Allergy(substance: "Penicillin", severity: .severe, reaction: "Urticaria, swelling"),
                Allergy(substance: "Birch pollen", severity: .mild, reaction: "Seasonal rhinitis"),
            ],
            chronicConditions: [
                ChronicCondition(name: "Mild persistent asthma", since: DateValue(date(2009, 1, 1), precision: .year)),
            ],
            alerts: [
                MedicalAlert(text: "Severe penicillin allergy — do not administer beta-lactam antibiotics", level: .critical),
            ],
            summary: """
                Generally healthy adult with childhood-onset mild asthma, well controlled on \
                inhaled corticosteroids. One orthopedic surgery (2016, left knee arthroscopy). \
                No cardiac, metabolic or oncological history. Records span two countries and \
                two languages; documents before 2013 are in Spanish.
                """
        )
    }

    // MARK: - Templates

    private struct Template {
        var year: Int
        var month: Int = 1
        var day: Int = 1
        var precision: DateValue.Precision = .day
        var category: EventCategory
        var specialty: Specialty?
        var status: EventStatus = .normal
        var pinned: Bool = false
        var title: String
        var summary: String
        var facility: String
        var doctor: String?
        var note: String?
        var tables: [ResultTable] = []
        var diagnoses: [Diagnosis] = []
        var medications: [Medication] = []
        var vaccinations: [Vaccination] = []
        var translations: [String: String] = [:]
        var hasDocument: Bool = true
        var documentHeading: String?
    }

    private static func templates() -> [Template] {
        [
            Template(
                year: 2004, precision: .year,
                category: .vaccination, specialty: .pediatrics,
                title: "Childhood vaccination record",
                summary: "Consolidated vaccination card issued by the school medical office. Covers routine childhood immunisation completed between 1991 and 2004.",
                facility: "Westbrook Family Clinic",
                note: "Only the year is legible on the original stamp.",
                vaccinations: [
                    Vaccination(
                        name: "Diphtheria–Tetanus (Td)",
                        manufacturer: "Sanofi Pasteur",
                        dose: "Booster",
                        batchNumber: "K-1147",
                        booster: BoosterSchedule(afterMonths: 120)
                    ),
                ],
                translations: ["es": "Cartilla de vacunación consolidada, emitida por el servicio médico escolar."]
            ),
            Template(
                year: 2007, month: 3, precision: .month,
                category: .consultation, specialty: .otolaryngology,
                title: "Recurrent tonsillitis consultation",
                summary: "Third episode within a year. Conservative management advised; tonsillectomy discussed but not indicated at this stage.",
                facility: "Westbrook Family Clinic",
                doctor: "carter",
                diagnoses: [Diagnosis(name: "Chronic tonsillitis", code: "J35.0", status: .resolved)],
                translations: ["es": "Tercer episodio en un año. Se recomienda tratamiento conservador."]
            ),
            Template(
                year: 2009, month: 11, day: 12,
                category: .diagnostics, specialty: .pulmonology,
                status: .significant, pinned: true, title: "Spirometry and asthma diagnosis",
                summary: "Reduced FEV1 with significant bronchodilator reversibility. Mild persistent asthma confirmed.",
                facility: "Westbrook Family Clinic",
                doctor: "carter",
                note: "Start of long-term inhaled therapy. Peak flow diary recommended.",
                tables: [
                    ResultTable(
                        title: "Spirometry",
                        columns: ["Measure", "Before", "After bronchodilator", "Predicted"],
                        rows: [
                            ResultRow(cells: ["FEV1", "2.94 L", "3.51 L", "4.05 L"], isAbnormal: true),
                            ResultRow(cells: ["FVC", "4.42 L", "4.55 L", "4.80 L"]),
                            ResultRow(cells: ["FEV1/FVC", "66 %", "77 %", "> 75 %"], isAbnormal: true),
                            ResultRow(cells: ["Reversibility", "—", "+19 %", "> 12 % is significant"]),
                        ],
                        note: "Reversibility confirms asthma. Original report in Spanish."
                    ),
                ],
                diagnoses: [Diagnosis(name: "Mild persistent asthma", code: "J45.3", status: .chronic)],
                medications: [Medication(name: "Budesonide/Formoterol", dosage: "160/4.5 µg", frequency: "Twice daily", isOngoing: true)]
            ),
            Template(
                year: 2011, month: 6, day: 3,
                category: .laboratory, specialty: .generalPractice,
                title: "Annual blood panel",
                summary: "Complete blood count, metabolic panel and lipid profile. All values within reference range.",
                facility: "Westbrook Family Clinic",
                doctor: "carter"
            ),
            Template(
                year: 2013, month: 9, day: 2,
                category: .certificate, specialty: .generalPractice,
                title: "Medical certificate for relocation",
                summary: "General health certificate issued for immigration purposes. No communicable disease, vaccination record complete.",
                facility: "Westbrook Family Clinic",
                doctor: "carter",
                note: "Original in Spanish; certified translation attached to the same folder.",
                translations: ["es": "Certificado general de salud emitido para trámites de inmigración."]
            ),
            Template(
                year: 2014, month: 2, day: 20,
                category: .consultation, specialty: .generalPractice,
                status: .significant, pinned: true, title: "New patient intake",
                summary: "First appointment after relocation. Full history taken, asthma therapy continued unchanged, allergy to penicillin documented.",
                facility: "Northgate Medical Center",
                doctor: "carter",
                diagnoses: [Diagnosis(name: "Penicillin hypersensitivity", code: "Z88.0", status: .chronic)]
            ),
            Template(
                year: 2015, month: 5, day: 14,
                category: .dental, specialty: .dentistry,
                title: "Root canal treatment, tooth 36",
                summary: "Two-visit endodontic treatment with permanent composite restoration.",
                facility: "Elm Street Dental"
            ),
            Template(
                year: 2016, month: 4, day: 8,
                category: .imaging, specialty: .orthopedics,
                status: .significant, title: "MRI of the left knee",
                summary: "Medial meniscus tear, posterior horn. Mild joint effusion. No ligament injury.",
                facility: "Northgate Medical Center",
                doctor: "hale",
                diagnoses: [Diagnosis(name: "Medial meniscus tear", code: "S83.2", status: .resolved)]
            ),
            Template(
                year: 2016, month: 5, day: 3,
                category: .surgery, specialty: .orthopedics,
                status: .significant, pinned: true, title: "Left knee arthroscopy",
                summary: "Arthroscopic partial medial meniscectomy under spinal anaesthesia. Uncomplicated. Discharged the same day.",
                facility: "Northgate Medical Center",
                doctor: "hale",
                note: "Cephalosporin used for prophylaxis — penicillin avoided. No reaction.",
                medications: [Medication(name: "Ibuprofen", dosage: "400 mg", frequency: "As needed, up to 3× daily")]
            ),
            Template(
                year: 2016, month: 6, day: 21,
                category: .consultation, specialty: .orthopedics,
                title: "Post-operative review",
                summary: "Full range of motion restored. Physiotherapy completed. Return to running permitted after eight weeks.",
                facility: "Northgate Medical Center",
                doctor: "hale",
                hasDocument: false
            ),
            Template(
                year: 2018, month: 10, day: 30,
                category: .screening, specialty: .generalPractice,
                status: .followUp, title: "Annual check-up",
                summary: "Blood pressure 118/76. ECG normal. Asthma stable, no exacerbations in the past year.",
                facility: "Northgate Medical Center",
                doctor: "carter"
            ),
            Template(
                year: 2019, month: 7, day: 16,
                category: .screening, specialty: .dermatology,
                status: .followUp, title: "Mole mapping",
                summary: "Full-body dermatoscopic examination. Twelve nevi photographed for baseline. No atypical features.",
                facility: "Northgate Medical Center",
                doctor: "reed",
                note: "Repeat in two years."
            ),
            Template(
                year: 2021, month: 3, day: 11,
                category: .vaccination, specialty: .immunology,
                title: "COVID-19 Vaccination",
                summary: "Administered at the regional vaccination centre. Observed for 15 minutes, no immediate reaction.",
                facility: "Northgate Medical Center",
                vaccinations: [
                    Vaccination(name: "COVID-19 mRNA", manufacturer: "BioNTech/Pfizer", dose: "1 of 2", batchNumber: "EW4821", site: "Left deltoid"),
                ]
            ),
            Template(
                year: 2021, month: 4, day: 1,
                category: .vaccination, specialty: .immunology,
                title: "COVID-19 Vaccination",
                summary: "Second dose completed. Mild arm soreness for two days.",
                facility: "Northgate Medical Center",
                vaccinations: [
                    Vaccination(
                        name: "COVID-19 mRNA",
                        manufacturer: "BioNTech/Pfizer",
                        dose: "2 of 2",
                        batchNumber: "ER9480",
                        site: "Left deltoid",
                        booster: BoosterSchedule(afterMonths: 60)
                    ),
                ]
            ),
            Template(
                year: 2022, month: 1, day: 19,
                category: .emergency, specialty: .pulmonology,
                status: .significant, title: "Emergency department — asthma exacerbation",
                summary: "Presented with wheeze and dyspnoea following a viral illness. Treated with nebulised salbutamol and oral prednisolone. Discharged after four hours.",
                facility: "Northgate Medical Center",
                note: "Trigger was a chest infection. Inhaler technique reviewed and corrected.",
                diagnoses: [Diagnosis(name: "Acute asthma exacerbation", code: "J45.901", status: .resolved)],
                medications: [Medication(name: "Prednisolone", dosage: "40 mg", frequency: "Once daily for 5 days")]
            ),
            Template(
                year: 2023, month: 5, day: 22,
                category: .laboratory, specialty: .generalPractice,
                status: .followUp, title: "Blood panel and vitamin D",
                summary: "All values within range except vitamin D at 42 nmol/L. Supplementation started.",
                facility: "Harbor Point Laboratory",
                doctor: "carter",
                tables: [
                    ResultTable(
                        title: "Blood panel",
                        columns: ["Test", "Result", "Reference"],
                        rows: [
                            ResultRow(cells: ["Haemoglobin", "150 g/L", "130–170"]),
                            ResultRow(cells: ["Leukocytes", "6.1 ×10⁹/L", "4.0–9.0"]),
                            ResultRow(cells: ["Platelets", "244 ×10⁹/L", "150–400"]),
                            ResultRow(cells: ["ALT", "26 U/L", "0–41"]),
                            ResultRow(cells: ["Creatinine", "88 µmol/L", "62–106"]),
                            ResultRow(cells: ["Vitamin D (25-OH)", "42 nmol/L", "75–200"], isAbnormal: true),
                        ],
                        note: "Transcribed from the Spanish original. Units as printed on the form."
                    ),
                ],
                medications: [Medication(name: "Cholecalciferol", dosage: "2000 IU", frequency: "Daily", isOngoing: true)]
            ),
            Template(
                year: 2024, month: 2, day: 6,
                category: .consultation, specialty: .cardiology,
                status: .followUp, title: "Cardiology consultation",
                summary: "Referred after occasional palpitations. Examination normal, ECG sinus rhythm. Holter monitor arranged as a precaution.",
                facility: "Northgate Medical Center",
                doctor: "silva",
                note: "Symptoms correlate with caffeine intake and poor sleep rather than exertion."
            ),
            Template(
                year: 2024, month: 2, day: 27,
                category: .diagnostics, specialty: .cardiology,
                title: "24-hour Holter monitoring",
                summary: "Sinus rhythm throughout. Rare supraventricular ectopics, no arrhythmia. No further cardiac follow-up required.",
                facility: "Northgate Medical Center",
                doctor: "silva",
                diagnoses: [Diagnosis(name: "Benign supraventricular ectopy", status: .resolved)]
            ),
            Template(
                year: 2025, month: 1, day: 14,
                category: .vaccination, specialty: .immunology,
                title: "Seasonal influenza vaccination",
                summary: "Annual influenza immunisation, quadrivalent.",
                facility: "Northgate Medical Center",
                vaccinations: [
                    Vaccination(
                        name: "Influenza, quadrivalent",
                        manufacturer: "Sanofi Pasteur",
                        dose: "Annual",
                        batchNumber: "U7712AA",
                        site: "Right deltoid",
                        booster: BoosterSchedule(afterMonths: 12)
                    ),
                ]
            ),
            Template(
                year: 2025, month: 9, day: 9,
                category: .dental, specialty: .dentistry,
                title: "Dental hygiene and check-up",
                summary: "Scaling and polishing. No caries. Recall in twelve months.",
                facility: "Elm Street Dental",
                hasDocument: false
            ),
            Template(
                year: 2026, month: 3, day: 4,
                category: .screening, specialty: .generalPractice,
                status: .followUp, title: "Annual check-up",
                summary: "Weight stable, blood pressure 120/78. Asthma well controlled. Vitamin D now within range; supplementation continued.",
                facility: "Northgate Medical Center",
                doctor: "carter",
                note: "Next mole mapping due — book with dermatology."
            ),
            Template(
                year: 2026, month: 6, day: 18,
                category: .prescription, specialty: .pulmonology,
                title: "Repeat prescription, inhaled therapy",
                summary: "Twelve-month repeat prescription issued for maintenance inhaler and reliever.",
                facility: "Northgate Medical Center",
                doctor: "carter",
                medications: [
                    Medication(name: "Budesonide/Formoterol", dosage: "160/4.5 µg", frequency: "Twice daily", isOngoing: true),
                    Medication(name: "Salbutamol", dosage: "100 µg", frequency: "As needed", isOngoing: true),
                ]
            ),
        ]
    }

    // MARK: - Helpers

    private static func doctorID(
        for template: Template,
        silva: Doctor, carter: Doctor, hale: Doctor, reed: Doctor
    ) -> UUID? {
        switch template.doctor {
        case "silva": silva.id
        case "carter": carter.id
        case "hale": hale.id
        case "reed": reed.id
        default: nil
        }
    }

    private static func facilityID(
        for template: Template,
        hospital: Facility, clinic: Facility, lab: Facility, dental: Facility
    ) -> UUID? {
        switch template.facility {
        case hospital.name: hospital.id
        case clinic.name: clinic.id
        case lab.name: lab.id
        case dental.name: dental.id
        default: nil
        }
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day)) ?? .now
    }
}
