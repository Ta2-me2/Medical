import SwiftUI

// Declared at file scope rather than nested in the view: Swift 6.3's IR
// generation crashes on a private nested enum passed through a `Binding`
// setter here, and a file-scope type sidesteps it at no cost to the design.
private enum BoosterMode: String, CaseIterable, Identifiable {
    case none
    case interval
    case date

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "No repeat"
        case .interval: "Repeat after"
        case .date: "Repeat on"
        }
    }
}

/// Says when a dose needs repeating: never, after an interval, or on a date.
///
/// Three answers rather than a free-form field, because "in ten years" and "on
/// 1 April 2035" are genuinely different facts. An interval follows the dose
/// that was actually given; a date is a date a clinic named and does not move.
struct BoosterField: View {
    @Binding var schedule: BoosterSchedule?

    private var mode: BoosterMode {
        guard let schedule else { return .none }
        if schedule.onDate != nil { return .date }
        if schedule.afterMonths != nil { return .interval }
        return .none
    }

    var body: some View {
        HStack(spacing: 8) {
            Picker("", selection: Binding(get: { mode }, set: { apply($0) })) {
                ForEach(BoosterMode.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .labelsHidden()
            .fixedSize()

            switch mode {
            case .none:
                EmptyView()

            case .interval:
                Picker("", selection: monthsBinding) {
                    ForEach(BoosterSchedule.presets, id: \.months) { preset in
                        Text(preset.title).tag(preset.months)
                    }
                    // Anything a clinic actually says that is not on the list.
                    if !BoosterSchedule.presets.contains(where: { $0.months == monthsBinding.wrappedValue }) {
                        Text("\(monthsBinding.wrappedValue) months").tag(monthsBinding.wrappedValue)
                    }
                }
                .labelsHidden()
                .fixedSize()

                Stepper("", value: monthsBinding, in: 1...600, step: 6)
                    .labelsHidden()

            case .date:
                DatePicker("", selection: dateBinding, displayedComponents: .date)
                    .labelsHidden()
            }

            Spacer(minLength: 0)
        }
    }

    private func apply(_ mode: BoosterMode) {
        switch mode {
        case .none:
            schedule = nil
        case .interval:
            schedule = BoosterSchedule(afterMonths: schedule?.afterMonths ?? 120)
        case .date:
            let existing = schedule?.onDate?.date
                ?? Calendar.current.date(byAdding: .year, value: 1, to: .now)
                ?? .now
            schedule = BoosterSchedule(onDate: DateValue(existing, precision: .day))
        }
    }

    private var monthsBinding: Binding<Int> {
        Binding(
            get: { schedule?.afterMonths ?? 120 },
            set: { schedule = BoosterSchedule(afterMonths: max(1, $0)) }
        )
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { schedule?.onDate?.date ?? .now },
            set: { schedule = BoosterSchedule(onDate: DateValue($0, precision: .day)) }
        )
    }
}

/// The due line shown wherever a vaccination appears.
struct BoosterDueLabel: View {
    let due: VaccinationDue
    var showsName: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: due.isOverdue() ? "exclamationmark.circle.fill" : "clock")
                .imageScale(.small)
            if showsName {
                Text(due.name).lineLimit(1)
                Text("·")
            }
            Text(due.description())
            Text("·")
            Text(due.dueOn.formatted(.dateTime.month(.abbreviated).year()))
                .monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(due.isOverdue() ? Palette.critical : Palette.warning)
    }
}
