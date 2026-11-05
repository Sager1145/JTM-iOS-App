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
            Button(localization.text("ios.editor.useSelectedDate")) {
                let formatted = RecordDate.text(from: pickerSelection.wrappedValue)
                if case .valid(_, _, _, let canonical) = EditorTime.parseDate(formatted) {
                    date = canonical
                }
            }
            if case .invalid = EditorTime.parseDate(date) {
                Text(localization.text("ios.editor.dateRule"))
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
        TextField(title, text: text, prompt: Text(localization.text("ios.newTrip.dateHint", fallback: "YYYY-MM-DD")))
            .keyboardType(.numbersAndPunctuation)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .accessibilityIdentifier(accessibilityID ?? "")
            // Short forms (1105, 11/5, 20261105) become the full date on Return.
            .onSubmit {
                let year = Calendar.current.component(.year, from: pickerSelection.wrappedValue)
                if case .valid(_, _, _, let canonical) = EditorTime.parseDateInput(date, defaultYear: year) {
                    date = canonical
                }
            }
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
    /// A journey has one service date. This picker presents the civil date at
    /// this stop, then stores it as the existing service-day clock offset.
    var serviceDate: String? = nil
    var accessibilityID: String? = nil
    @State private var pendingPickerTime: Date?
    @State private var pendingPickerDayOffset: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                timeTextField
            }
            .frame(minHeight: 44)
            if let dateBounds {
                DatePicker(
                    localization.text("ios.editor.date"),
                    selection: pickerDateSelection,
                    in: dateBounds,
                    displayedComponents: .date)
                    .accessibilityIdentifier("\(accessibilityID ?? "rideEditorTime")Date")
            } else {
                Picker(localization.text("ios.editor.serviceDay"), selection: pickerDay) {
                    Text(localization.text("ios.editor.today")).tag(ServiceDay.today)
                    Text(localization.text("ios.editor.nextServiceDay")).tag(ServiceDay.next)
                    Text(localization.text("ios.editor.later")).tag(ServiceDay.later)
                }
                if pickerDay.wrappedValue == .later {
                    Stepper(
                        localization.text("ios.editor.serviceDaysLater", params: [
                            "count": .number(Double(pickerDayOffset.wrappedValue))
                        ]),
                        value: pickerDayOffset,
                        in: 2...Self.maximumPickerDayOffset
                    )
                }
            }
            DatePicker(title, selection: pickerSelection, displayedComponents: .hourAndMinute)
            Button(localization.text("ios.editor.useSelectedTime")) {
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
                Text(localization.text("ios.editor.invalidClock"))
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let serviceDate,
               case .valid(_, let clock) = EditorTime.parseTime(time),
               clock.dayOffset > 0,
               let civilDate = Dates.addDays(serviceDate, clock.dayOffset) {
                Text("\(civilDate) " + String(
                    format: "%02d:%02d", clock.hour, clock.minute))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("\(accessibilityID ?? "rideEditorTime")Civil")
            }
        }
        .onChange(of: time) { _, _ in
            pendingPickerTime = nil
            pendingPickerDayOffset = nil
        }
        .onChange(of: serviceDate) { _, _ in pendingPickerDayOffset = nil }
    }

    private var timeTextField: some View {
        TextField(title, text: text, prompt: Text("H:MM"))
            .keyboardType(.numbersAndPunctuation)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .accessibilityIdentifier(accessibilityID ?? "")
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

    private var dateBounds: ClosedRange<Date>? {
        guard let serviceDate,
              case .valid(_, _, _, let base) = EditorTime.parseDate(serviceDate),
              let first = RecordDate.date(from: base),
              let lastText = Dates.addDays(base, Self.maximumPickerDayOffset),
              let last = RecordDate.date(from: lastText)
        else { return nil }
        return first...last
    }

    private var pickerDateSelection: Binding<Date> {
        Binding(
            get: {
                guard let serviceDate,
                      let date = Dates.addDays(serviceDate, pickerDayOffset.wrappedValue),
                      let selection = RecordDate.date(from: date)
                else { return Date() }
                return selection
            },
            set: { selected in
                guard let serviceDate,
                      let start = RecordDate.date(from: serviceDate)
                else { return }
                let offset = Self.pickerCalendar.dateComponents(
                    [.day], from: start, to: selected).day ?? 0
                pendingPickerDayOffset = min(Self.maximumPickerDayOffset, max(0, offset))
            }
        )
    }

    /// The same Gregorian device calendar `RecordDate` uses for the date picker.
    private static var pickerCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }
}

/// One typed date and time, the calendar one tap away. Used for every
/// date-and-time the journey editor edits.
///
/// Typing accepts the short forms of ``EditorTime/parseDateInput(_:defaultYear:)``
/// (`1105`, `11/5`, `20261105`; the year defaults to the value's own) and of
/// ``EditorTime/parseTime(_:)`` (`0930`, `9:30`). Text is checked as it is
/// typed but applied only on Return or when the field is left, so a
/// half-typed date (`11/1` on the way to `11/15`) never reaches the trip.
/// Leaving a field with text that does not parse puts the trip's value back.
struct TypedDateTimeField: View {
    @Environment(AppLocalization.self) private var localization
    let title: String
    @Binding var value: Date
    let identifier: String
    @State private var dateText = ""
    @State private var timeText = ""
    @State private var showsCalendar = false
    @FocusState private var focused: Part?

    private enum Part: Hashable { case date, time }

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(title)
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 4)
                TextField(localization.text("ios.newTrip.dateHint", fallback: "YYYY-MM-DD"), text: $dateText)
                    .keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .focused($focused, equals: .date)
                    .frame(minWidth: 96, maxWidth: 120)
                    .accessibilityLabel(title)
                    .accessibilityIdentifier("\(identifier)Date")
                    .onSubmit(normalize)
                TextField("9:30", text: $timeText)
                    .keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .focused($focused, equals: .time)
                    .frame(width: 56)
                    .accessibilityIdentifier("\(identifier)Time")
                    .onSubmit(normalize)
                Button {
                    // Typed text must not overwrite the calendar's pick later.
                    focused = nil
                    showsCalendar = true
                } label: {
                    Image(systemName: "calendar")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(localization.text("ios.newTrip.openCalendar", fallback: "Calendar"))
                .accessibilityIdentifier(identifier)
                .popover(isPresented: $showsCalendar) {
                    DatePicker(title, selection: $value, displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.graphical)
                        .padding()
                        .frame(minWidth: 320)
                        .presentationCompactAdaptation(.popover)
                }
            }
            if let problem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if focused == .date {
                Text(localization.text("ios.newTrip.dateForms", fallback: "e.g. 2026-11-05, 11/05 or 1105"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 44)
        .onAppear(perform: refresh)
        .onChange(of: value) { _, _ in if focused == nil { refresh() } }
        .onChange(of: focused) { old, part in if old != nil, part == nil { normalize() } }
        // A complete form ("2027-09-30", "9:30") is applied as it is typed;
        // a half-typed one ("11/1" on the way to "11/15") never is.
        .onChange(of: dateText) { _, text in
            if case .valid = EditorTime.parseDate(text) { apply() }
        }
        .onChange(of: timeText) { _, text in
            if text.contains(":"), text.split(separator: ":").last?.count == 2,
               case .valid = EditorTime.parseTime(text) { apply() }
        }
    }

    private var parsedDate: ServiceDateParse {
        EditorTime.parseDateInput(dateText, defaultYear: calendar.component(.year, from: value))
    }

    private var problem: String? {
        if case .invalid = parsedDate {
            return localization.text("ios.newTrip.dateInvalid", fallback: "Not a date. Try 2026-11-05, 11/05 or 1105.")
        }
        if case .invalid = EditorTime.parseTime(timeText) {
            return localization.text("ios.newTrip.timeInvalid", fallback: "Not a time. Try 9:30 or 0930.")
        }
        return nil
    }

    /// Writes the typed day and clock into `value` when both parse.
    private func apply() {
        guard case .valid(let year, let month, let day, _) = parsedDate,
              case .valid(_, let time) = EditorTime.parseTime(timeText),
              let start = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              let civil = calendar.date(byAdding: .day, value: time.dayOffset, to: start),
              let next = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: civil)
        else { return }
        // Same minute: nothing changed, and a seed's seconds stay untouched.
        guard !calendar.isDate(next, equalTo: value, toGranularity: .minute) else { return }
        value = next
    }

    /// Leaving a field shows the value in its canonical form.
    private func normalize() {
        apply()
        refresh()
    }

    private func refresh() {
        dateText = RecordDate.text(from: value)
        let parts = calendar.dateComponents([.hour, .minute], from: value)
        timeText = String(format: "%d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}
