import RailCore
import SwiftUI

/// Date text plus a date-only picker. The binding is the record's `Train.date`.
///
/// An empty field stores nil. Invalid text is kept and footnoted — the picker
/// may display today for layout, but only an explicit confirmation writes it.
struct EditorDateField: View {
    @Environment(AppLocalization.self) private var localization
    let title: String
    @Binding var date: String?
    let region: Region
    var focus: FocusState<RideDraftIssue.Field?>.Binding?
    var field: RideDraftIssue.Field?
    var accessibilityID: String?
    @State private var pendingPickerDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                dateTextField
            }
            .frame(minHeight: 44)
            DatePicker(title, selection: pickerSelection, displayedComponents: .date)
            Button(localization.editorText("ios.editor.useSelectedDate")) {
                let formatted = RecordDate.text(from: pickerSelection.wrappedValue)
                if case .valid(_, _, _, let canonical) = EditorTime.parseDate(formatted) {
                    date = canonical
                }
            }
            if case .invalid = EditorTime.parseDate(date) {
                Text(localization.editorText("ios.editor.dateRule"))
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: date) { _, _ in pendingPickerDate = nil }
    }

    @ViewBuilder private var dateTextField: some View {
        if let focus, let field {
            baseTextField.focused(focus, equals: field)
        } else {
            baseTextField
        }
    }

    private var baseTextField: some View {
        TextField(title, text: text, prompt: Text("YYYY-MM-DD"))
            .keyboardType(.numbersAndPunctuation)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .accessibilityIdentifier(accessibilityID ?? "")
    }

    private var text: Binding<String> {
        Binding(
            get: { date ?? "" },
            set: { raw in
                switch EditorTime.parseDate(raw) {
                case .unset:
                    date = nil
                case .invalid:
                    date = raw
                case .valid(_, _, _, let canonical):
                    date = canonical
                }
            }
        )
    }

    /// Today is only the wheel's layout seed. `RecordDate` is the device
    /// calendar the picker draws, so the civil day is not shifted into the
    /// region zone.
    private var pickerSelection: Binding<Date> {
        Binding(
            get: {
                if let pendingPickerDate { return pendingPickerDate }
                if case .valid(let year, let month, let day, _) = EditorTime.parseDate(date) {
                    return RecordDate.date(from: (year: year, month: month, day: day))
                }
                return RecordDate.date(from: RecordDate.todayParts(in: region.clock))
            },
            set: { pendingPickerDate = $0 }
        )
    }
}

/// Clock text plus an hour/minute picker. Empty stores nil. Invalid text is
/// kept — never rewritten to 00:00 — and 25:10 stays 25:10.
struct EditorTimeField: View {
    /// Must stay aligned with RailCore's `Dates.maxDayOffset`, which is
    /// internal to that module. `EditorTime.confirmPicker` remains the final
    /// grammar check when this bound changes.
    private static let maximumPickerDayOffset = 366

    private enum ServiceDay: Hashable {
        case today
        case next
        case later
    }

    @Environment(AppLocalization.self) private var localization
    let title: String
    @Binding var time: String?
    @State private var pendingPickerTime: Date?
    @State private var pendingPickerDayOffset: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                TextField(title, text: text, prompt: Text("H:MM"))
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .frame(minHeight: 44)
            Picker(localization.editorText("ios.editor.serviceDay"), selection: pickerDay) {
                Text(localization.editorText("ios.editor.today")).tag(ServiceDay.today)
                Text(localization.editorText("ios.editor.nextServiceDay")).tag(ServiceDay.next)
                Text(localization.editorText("ios.editor.later")).tag(ServiceDay.later)
            }
            if pickerDay.wrappedValue == .later {
                Stepper(
                    localization.editorText("ios.editor.serviceDaysLater", [
                        "count": .number(Double(pickerDayOffset.wrappedValue))
                    ]),
                    value: pickerDayOffset,
                    in: 2...Self.maximumPickerDayOffset
                )
            }
            DatePicker(title, selection: pickerSelection, displayedComponents: .hourAndMinute)
            Button(localization.editorText("ios.editor.useSelectedTime")) {
                let parts = Self.pickerCalendar.dateComponents(
                    [.hour, .minute], from: pickerSelection.wrappedValue)
                let confirmed = EditorTime.confirmPicker(
                    dayOffset: pickerDayOffset.wrappedValue,
                    hour: parts.hour ?? 0,
                    minute: parts.minute ?? 0)
                if case .valid(_, let clock) = confirmed.parsed {
                    time = EditorTime.canonical(clock)
                }
            }
            if case .invalid = EditorTime.parseTime(time) {
                Text(localization.editorText("ios.editor.invalidClock"))
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: time) { _, _ in
            pendingPickerTime = nil
            pendingPickerDayOffset = nil
        }
    }

    private var text: Binding<String> {
        Binding(
            get: { time ?? "" },
            set: { raw in
                switch EditorTime.parseTime(raw) {
                case .unset:
                    time = nil
                case .invalid:
                    time = raw
                case .valid(_, let clock):
                    time = EditorTime.canonical(clock)
                }
            }
        )
    }

    /// The wheel shows the folded hour (25:10 looks like 01:10). Only the
    /// confirmation button writes, retaining the service-day offset.
    private var pickerSelection: Binding<Date> {
        Binding(
            get: {
                if let pendingPickerTime { return pendingPickerTime }
                if case .valid(_, let clock) = EditorTime.parseTime(time),
                   let date = Self.pickerCalendar.date(
                    from: DateComponents(hour: clock.hour, minute: clock.minute)) {
                    return date
                }
                return Date()
            },
            set: { pendingPickerTime = $0 }
        )
    }

    /// The day selector has three compact choices. Selecting “Later” starts
    /// at two days and exposes the exact offset, while existing multi-day
    /// values retain their own offset until confirmation.
    private var pickerDay: Binding<ServiceDay> {
        Binding(
            get: {
                switch pickerDayOffset.wrappedValue {
                case 0: .today
                case 1: .next
                default: .later
                }
            },
            set: { selection in
                switch selection {
                case .today: pendingPickerDayOffset = 0
                case .next: pendingPickerDayOffset = 1
                case .later: pendingPickerDayOffset = max(2, pickerDayOffset.wrappedValue)
                }
            }
        )
    }

    private var pickerDayOffset: Binding<Int> {
        Binding(
            get: {
                if let pendingPickerDayOffset { return pendingPickerDayOffset }
                if case .valid(_, let clock) = EditorTime.parseTime(time) {
                    return clock.dayOffset
                }
                return 0
            },
            set: { pendingPickerDayOffset = $0 }
        )
    }

    /// The same Gregorian device calendar `RecordDate` uses for the date picker.
    private static var pickerCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }
}
