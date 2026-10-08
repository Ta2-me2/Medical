import AppKit
import SwiftUI

/// The passport page.
///
/// Everything here is what someone else would need if the owner could not
/// speak for themselves. That is why alerts and severe allergies sit above the
/// fold, and why the page has nothing else competing with them.
struct PatientView: View {
    @Environment(ArchiveStore.self) private var store

    @State private var isEditing = false
    @State private var isChoosingPhoto = false
    @State private var croppedImage: NSImage?
    @State private var isHoveringAvatar = false

    var body: some View {
        let patient = store.archive.patient

        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                identity(patient)

                // Every section keeps its place whether or not it has content.
                // Hiding an empty one leaves no sign that this archive can
                // record an allergy at all — and "no allergies recorded" is a
                // different statement from "nobody ever asked". Alerts stay
                // first, because that is where they belong the day there is one.
                alerts(patient.alerts)
                vitals(patient)
                allergies(patient.allergies)
                conditions(patient.chronicConditions)
                contacts(patient.emergencyContacts)

                if let summary = patient.summary.nilIfEmpty {
                    section("Medical Summary") {
                        Text(summary)
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: Metrics.readableWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .pageInsets()
        }
        .background(Palette.page)
        .navigationTitle("Patient")
        .toolbar {
            ToolbarItem(id: "patient.edit") {
                Button("Edit") { isEditing = true }
            }
        }
        .fileImporter(
            isPresented: $isChoosingPhoto,
            allowedContentTypes: [.image]
        ) { result in
            guard case .success(let url) = result else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            croppedImage = NSImage(contentsOf: url)
        }
        .sheet(item: Binding(
            get: { croppedImage.map { LoadedImage(image: $0) } },
            set: { if $0 == nil { croppedImage = nil } }
        )) { loaded in
            AvatarEditor(image: loaded.image) { png in
                Task { _ = await store.setAvatar(png) }
            }
        }
        .sheet(isPresented: $isEditing) {
            PatientEditor(patient: patient) { updated in
                store.update { $0.patient = updated }
            }
        }
    }

    // MARK: - Sections

    private func identity(_ patient: Patient) -> some View {
        HStack(alignment: .center, spacing: 20) {
            PatientAvatar(patient: patient, url: store.avatarURL(), size: Metrics.avatarLarge)
                .overlay {
                    if isHoveringAvatar {
                        Circle()
                            .fill(.black.opacity(0.45))
                            .overlay {
                                Image(systemName: "camera")
                                    .foregroundStyle(.white)
                            }
                    }
                }
                .onHover { isHoveringAvatar = $0 }
                .onTapGesture { isChoosingPhoto = true }
                .contextMenu {
                    Button("Choose Photo…") { isChoosingPhoto = true }
                    if patient.avatarFilename != nil {
                        Button("Remove Photo", role: .destructive) {
                            Task { await store.clearAvatar() }
                        }
                    }
                }
                .help("Click to choose a photo")
                .animation(.easeOut(duration: 0.12), value: isHoveringAvatar)

            VStack(alignment: .leading, spacing: 5) {
                Text(patient.displayName)
                    .font(.system(size: 30, weight: .semibold))

                if let birth = patient.formattedDateOfBirth {
                    Text(patient.age.map { "\(birth) · \($0) years old" } ?? birth)
                        .font(.callout)
                        .foregroundStyle(Palette.secondaryText)
                }

                if !patient.languages.isEmpty {
                    Text(patient.languages.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(Palette.tertiaryText)
                }
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func alerts(_ alerts: [MedicalAlert]) -> some View {
        section("Medical Alerts") {
            if alerts.isEmpty {
                GroupedRows {
                    GroupedRow(showsDivider: false) { emptyRow("No alerts recorded") }
                }
            } else {
                VStack(spacing: Metrics.rowSpacing) {
                    ForEach(alerts) { alert in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: alert.level.symbol)
                                .foregroundStyle(alert.level.color)
                            Text(alert.text)
                                .font(.body.weight(.medium))
                            Spacer(minLength: 0)
                        }
                        .padding(Metrics.cardPadding)
                        .background(
                            alert.level.color.opacity(0.06),
                            in: .rect(cornerRadius: Metrics.cardRadius, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                                .strokeBorder(alert.level.color.opacity(0.25), lineWidth: 1)
                        }
                    }
                }
            }
        }
    }

    private func vitals(_ patient: Patient) -> some View {
        section("Vitals") {
            GroupedRows {
                GroupedRow { InfoRow("Blood Type", patient.bloodType?.title ?? "—") }
                GroupedRow { InfoRow("Height", patient.formattedHeight ?? "—") }
                GroupedRow(showsDivider: false) { InfoRow("Weight", patient.formattedWeight ?? "—") }
            }
        }
    }

    /// A section that is present but has nothing in it yet.
    ///
    /// It says so and stops there. Every one of these rows used to carry its own
    /// "Add…" link, all four opening the same editor the Edit button opens — a
    /// row of doors into one room.
    private func emptyRow(_ text: String) -> some View {
        HStack {
            Text(text).foregroundStyle(Palette.tertiaryText)
            Spacer(minLength: 12)
        }
    }

    @ViewBuilder
    private func allergies(_ allergies: [Allergy]) -> some View {
        section("Known Allergies") {
            GroupedRows {
                if allergies.isEmpty {
                    GroupedRow(showsDivider: false) { emptyRow("No allergies recorded") }
                }
                ForEach(Array(allergies.enumerated()), id: \.element.id) { index, allergy in
                    GroupedRow(showsDivider: index < allergies.count - 1) {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(allergy.substance)
                                if let reaction = allergy.reaction {
                                    Text(reaction)
                                        .font(.caption)
                                        .foregroundStyle(Palette.secondaryText)
                                }
                            }
                            Spacer(minLength: 12)
                            Chip(text: allergy.severity.title, tint: allergy.severity.color)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func conditions(_ conditions: [ChronicCondition]) -> some View {
        section("Chronic Conditions") {
            GroupedRows {
                if conditions.isEmpty {
                    GroupedRow(showsDivider: false) { emptyRow("No conditions recorded") }
                }
                ForEach(Array(conditions.enumerated()), id: \.element.id) { index, condition in
                    GroupedRow(showsDivider: index < conditions.count - 1) {
                        HStack(spacing: 10) {
                            Text(condition.name)
                            Spacer(minLength: 12)
                            if let since = condition.since {
                                Text("since \(since.medium)")
                                    .font(.caption)
                                    .foregroundStyle(Palette.tertiaryText)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func contacts(_ contacts: [EmergencyContact]) -> some View {
        section("Emergency Contacts") {
            GroupedRows {
                if contacts.isEmpty {
                    GroupedRow(showsDivider: false) { emptyRow("No contacts recorded") }
                }
                ForEach(Array(contacts.enumerated()), id: \.element.id) { index, contact in
                    GroupedRow(showsDivider: index < contacts.count - 1) {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(contact.name)
                                if let relationship = contact.relationship {
                                    Text(relationship)
                                        .font(.caption)
                                        .foregroundStyle(Palette.secondaryText)
                                }
                            }
                            Spacer(minLength: 12)
                            if let phone = contact.phone {
                                Text(phone)
                                    .foregroundStyle(Palette.secondaryText)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            SectionHeader(title)
            content()
        }
    }
}
