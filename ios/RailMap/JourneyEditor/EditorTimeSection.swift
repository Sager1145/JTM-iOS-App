import RailApplication
import RailCore
import RailPresentation
import SwiftUI

/// Departure and arrival, typed or picked (`TypedDateTimeField`), the
/// observed clocks when the train ran early or late, and whether the ride is
/// done. Ridden follows the time (`TripListRules`) until the reader sets it.
/// The scheduled clocks are what a timetable or ticket fills; the actual ones
/// only the reader enters.
struct EditorTimeSection: View, JourneyEditorLabelling {
    @Environment(AppLocalization.self) var localization
    let model: TripDraftModel
    @FocusState private var focusedActual: Bool?

    var body: some View {
        Section {
            TypedDateTimeField(
                title: text("departure", fallback: "Departure"),
                value: model.timetableTimeSelection(isDeparture: true),
                clock: model.region.clock,
                identifier: "newTripDeparture")
            TypedDateTimeField(
                title: text("arrival", fallback: "Arrival"),
                value: model.timetableTimeSelection(isDeparture: false),
                clock: model.region.clock,
                identifier: "newTripArrival")
            if let source = timeSource {
                HStack(spacing: RailSpacing.s8) {
                    FillSourceBadge(source: source)
                    Text(text("timeFilled", fallback: "Check the time; changing it keeps your value."))
                        .railText(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("newTripTimeSource")
            }
            if model.showsActualTimes {
                actualRow(isDeparture: true)
                actualRow(isDeparture: false)
            } else {
                Button {
                    model.showsActualTimes = true
                } label: {
                    Label(text("addActualTimes", fallback: "Add actual times"), systemImage: "clock.arrow.2.circlepath")
                        .frame(maxWidth: .infinity, minHeight: RailSize.touch, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("newTripAddActualTimes")
            }
            if model.scheduledTimesConflict {
                Text(text(
                    "arrivalBeforeDeparture",
                    fallback: "Arrival is before departure."))
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Toggle(text("ridden", fallback: "I have ridden this journey"), isOn: Binding(
                get: { model.isRidden }, set: { model.riddenOverride = $0 }))
                .accessibilityIdentifier("newTripRidden")
        } header: {
            Text(text("time", fallback: "Time"))
        }
    }

    /// One observed clock, typed as H:MM, with how far it was from schedule.
    private func actualRow(isDeparture: Bool) -> some View {
        let id = isDeparture ? "newTripActualDeparture" : "newTripActualArrival"
        let raw = isDeparture ? model.actualDeparture : model.actualArrival
        let normalized = model.normalizedActual(raw, isDeparture: isDeparture)
        return VStack(alignment: .leading, spacing: RailSpacing.labelValueGap) {
            EditorCompactRow(title: localization.text(
                isDeparture ? "ios.editor.actualDeparture" : "ios.editor.actualArrival")) {
                TextField("H:MM", text: model.actualTimeText(isDeparture: isDeparture))
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($focusedActual, equals: isDeparture)
                    .accessibilityIdentifier(id)
            }
            if model.scheduledIsSet(isDeparture: isDeparture) { chipRow(isDeparture: isDeparture) }
            if raw != nil, normalized == nil {
                Text(localization.text("ios.editor.invalidClock"))
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else if model.scheduledIsSet(isDeparture: isDeparture), let status = StopTimingStatus.localizedLabel(
                scheduled: model.scheduledClock(isDeparture: isDeparture), actual: normalized,
                localization: localization) {
                // Compared with the scheduled clock above; a placeholder time has no delay.
                Text(status)
                    .railText(.secondary)
                    .accessibilityIdentifier(isDeparture ? "newTripActualDepartureStatus" : "newTripActualArrivalStatus")
            }
        }
    }

    /// On time, +5, +10, +15 and Custom. Borderless buttons with their own
    /// capsule: a Form row fires every default-style button on one tap.
    private func chipRow(isDeparture: Bool) -> some View {
        let typed = model.actualIsTyped(isDeparture: isDeparture)
        func chip(_ label: String, id: String, minutes: Int?) -> some View {
            Button {
                if let minutes {
                    model.applyActualChip(minutes: minutes, isDeparture: isDeparture)
                } else {
                    focusedActual = isDeparture
                }
            } label: {
                Text(label)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tint)
                    .padding(.horizontal, RailSpacing.s12)
                    .frame(minHeight: 34)
                    .background(.tint.opacity(0.14), in: Capsule())
                    // The capsule stays compact; the tap area is a full touch target.
                    .frame(minHeight: RailSize.touch)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(typed && minutes != nil)
            .accessibilityIdentifier(id)
        }
        func plus(_ n: Int) -> String {
            text("delayPlus", fallback: "+{minutes} min", ["minutes": .string(String(n))])
        }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: RailSpacing.s8) {
                chip(text("delayOnTime", fallback: "On time"),
                     id: isDeparture ? "newTripActualDepartureOnTime" : "newTripActualArrivalOnTime", minutes: 0)
                chip(plus(5), id: isDeparture ? "newTripActualDeparturePlus5" : "newTripActualArrivalPlus5", minutes: 5)
                chip(plus(10), id: isDeparture ? "newTripActualDeparturePlus10" : "newTripActualArrivalPlus10", minutes: 10)
                chip(plus(15), id: isDeparture ? "newTripActualDeparturePlus15" : "newTripActualArrivalPlus15", minutes: 15)
                chip(text("delayCustom", fallback: "Custom"),
                     id: isDeparture ? "newTripActualDepartureCustom" : "newTripActualArrivalCustom", minutes: nil)
            }
        }
    }

    /// The source of a clock or day the reader has not set themselves.
    private var timeSource: TripDraftModel.FillSource? {
        model.filledBy[.departure] ?? model.filledBy[.arrival] ?? model.filledBy[.date]
    }
}
