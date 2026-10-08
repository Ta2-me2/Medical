import SwiftUI

/// Editing the passport page.
///
/// Works on a copy and commits once, so a half-finished edit can always be
/// abandoned. For a page that other people may read in an emergency, a
/// cancellable edit matters more than a live-updating one.
struct PatientEditor: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Patient
    @State private var languagesText: String
    @State private var heightText: String
    @State private var weightText: String
    @State private var hasDateOfBirth: Bool
    @State private var dateOfBirth: Date

    private let onSave: (Patient) -> Void

    init(patient: Patient, onSave: @escaping (Patient) -> Void) {
        _draft = State(initialValue: patient)
        _languagesText = State(initialValue: patient.languages.joined(separator: ", "))
        _heightText = State(initialValue: patient.heightCM.map { String(Int($0.rounded())) } ?? "")
        _weightText = State(initialValue: patient.weightKG.map { String(format: "%g", $0) } ?? "")
        _hasDateOfBirth = State(initialValue: patient.dateOfBirth != nil)
        _dateOfBirth = State(initialValue: patient.dateOfBirth ?? Date(timeIntervalSince1970: 0))
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Patient").font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 10)

            Form {
                Section {
                    TextField("Full Name", text: $draft.fullName)

                    Toggle("Date of Birth", isOn: $hasDateOfBirth)
                    if hasDateOfBirth {
                        DatePicker("Born", selection: $dateOfBirth, displayedComponents: .date)
                    }

                    TextField("Languages", text: $languagesText, prompt: Text("English, Spanish"))
                }

                Section("Vitals") {
                    Picker("Blood Type", selection: $draft.bloodType) {
                        Text("Unknown").tag(Patient.BloodType?.none)
                        Divider()
                        ForEach(Patient.BloodType.allCases) { type in
                            Text(type.title).tag(Patient.BloodType?.some(type))
                        }
                    }
                    TextField("Height (cm)", text: $heightText)
                    TextField("Weight (kg)", text: $weightText)
                }

                Section("Medical Alerts") {
                    EditableList(
                        items: $draft.alerts,
                        placeholder: "Pacemaker fitted 2019",
                        newItem: { MedicalAlert(text: $0, level: .critical) },
                        label: \.text
                    )
                }

                Section("Known Allergies") {
                    EditableList(
                        items: $draft.allergies,
                        placeholder: "Penicillin",
                        newItem: { Allergy(substance: $0, severity: .severe) },
                        label: \.substance
                    )
                }

                Section("Chronic Conditions") {
                    EditableList(
                        items: $draft.chronicConditions,
                        placeholder: "Asthma",
                        newItem: { ChronicCondition(name: $0) },
                        label: \.name
                    )
                }

                Section("Emergency Contacts") {
                    EditableList(
                        items: $draft.emergencyContacts,
                        placeholder: "Name — phone",
                        newItem: { EmergencyContact(name: $0) },
                        label: \.name
                    )
                }

                Section("Medical Summary") {
                    TextEditor(text: $draft.summary)
                        .frame(height: 90)
                        .font(.body)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 520, height: 660)
    }

    private func save() {
        var patient = draft
        patient.dateOfBirth = hasDateOfBirth ? dateOfBirth : nil
        patient.languages = languagesText
            .split(separator: ",")
            .compactMap { $0.trimmingCharacters(in: .whitespaces).nilIfEmpty }
        patient.heightCM = Double(heightText.replacingOccurrences(of: ",", with: "."))
        patient.weightKG = Double(weightText.replacingOccurrences(of: ",", with: "."))
        onSave(patient)
        dismiss()
    }
}

/// Add and remove rows of a simple list, without a screen of its own.
///
/// Enough for the short lists on this page. Anything that needs more structure
/// belongs to an event, not to the patient record.
struct EditableList<Item: Identifiable & Hashable>: View {
    @Binding var items: [Item]
    let placeholder: String
    let newItem: (String) -> Item
    let label: KeyPath<Item, String>

    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items) { item in
                HStack {
                    Text(item[keyPath: label])
                    Spacer()
                    Button {
                        items.removeAll { $0.id == item.id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(Palette.tertiaryText)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 6) {
                TextField("", text: $draft, prompt: Text(placeholder))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(draft.nilIfEmpty == nil)
            }
        }
    }

    private func add() {
        guard let text = draft.nilIfEmpty else { return }
        items.append(newItem(text))
        draft = ""
    }
}
