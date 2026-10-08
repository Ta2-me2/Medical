import Foundation

nonisolated struct DiagnosisHit: Identifiable, Hashable {
    var diagnosis: Diagnosis
    var event: MedicalEvent
    var id: UUID { diagnosis.id }
}

nonisolated struct MedicationHit: Identifiable, Hashable {
    var medication: Medication
    var event: MedicalEvent
    var id: UUID { medication.id }
}

nonisolated struct SearchResults {
    var events: [MedicalEvent] = []
    var documents: [DocumentRecord] = []
    var notes: [NoteRecord] = []
    var vaccinations: [VaccinationRecord] = []
    var diagnoses: [DiagnosisHit] = []
    var medications: [MedicationHit] = []
    var doctors: [Doctor] = []
    var facilities: [Facility] = []
    var medicines: [Medicine] = []

    var total: Int {
        events.count + documents.count + notes.count + vaccinations.count
            + diagnoses.count + medications.count + doctors.count + facilities.count
            + medicines.count
    }

    var isEmpty: Bool { total == 0 }
}

/// Searches everything, in one pass over the archive.
///
/// A linear scan, deliberately: a lifetime of records is a few thousand events,
/// which a modern machine filters faster than a person can finish typing. An
/// index would be a second copy of the data to keep correct — and the archive's
/// first rule is that nothing is stored twice.
nonisolated enum SearchService {

    /// How many hits of each kind to show before the results page stops being
    /// readable.
    private static let limitPerSection = 12

    static func search(_ rawQuery: String, in archive: Archive) -> SearchResults {
        guard let query = rawQuery.nilIfEmpty?.lowercased() else { return SearchResults() }

        var results = SearchResults()

        results.events = archive.eventsNewestFirst
            .filter { $0.searchableText.lowercased().contains(query) }

        results.documents = archive.allDocuments.filter {
            $0.document.displayName.lowercased().contains(query)
                || $0.document.originalFilename.lowercased().contains(query)
        }

        results.notes = archive.allNotes.filter {
            $0.note.body.lowercased().contains(query) || $0.note.displayTitle.lowercased().contains(query)
        }

        results.vaccinations = archive.allVaccinations.filter {
            $0.vaccination.name.lowercased().contains(query)
                || ($0.vaccination.manufacturer?.lowercased().contains(query) ?? false)
                || ($0.vaccination.batchNumber?.lowercased().contains(query) ?? false)
        }

        results.diagnoses = archive.eventsNewestFirst.flatMap { event in
            event.diagnoses
                .filter { $0.name.lowercased().contains(query) || ($0.code?.lowercased().contains(query) ?? false) }
                .map { DiagnosisHit(diagnosis: $0, event: event) }
        }

        results.medications = archive.eventsNewestFirst.flatMap { event in
            event.medications
                .filter { $0.name.lowercased().contains(query) }
                .map { MedicationHit(medication: $0, event: event) }
        }

        // The cupboard is searched too: somebody typing "ibuprofen" wants the
        // box in the bathroom quite as much as the prescription from 2014.
        results.medicines = archive.medicinesByName.filter {
            $0.name.lowercased().contains(query)
                || ($0.purpose?.lowercased().contains(query) ?? false)
                || $0.kinds.contains { kind in kind.title.lowercased().contains(query) }
        }

        results.doctors = archive.doctors.filter { $0.name.lowercased().contains(query) }
        results.facilities = archive.facilities.filter { $0.name.lowercased().contains(query) }

        return trimmed(results)
    }

    private static func trimmed(_ results: SearchResults) -> SearchResults {
        var trimmed = results
        trimmed.events = Array(results.events.prefix(limitPerSection))
        trimmed.documents = Array(results.documents.prefix(limitPerSection))
        trimmed.notes = Array(results.notes.prefix(limitPerSection))
        trimmed.vaccinations = Array(results.vaccinations.prefix(limitPerSection))
        trimmed.diagnoses = Array(results.diagnoses.prefix(limitPerSection))
        trimmed.medications = Array(results.medications.prefix(limitPerSection))
        trimmed.doctors = Array(results.doctors.prefix(limitPerSection))
        trimmed.facilities = Array(results.facilities.prefix(limitPerSection))
        trimmed.medicines = Array(results.medicines.prefix(limitPerSection))
        return trimmed
    }
}
