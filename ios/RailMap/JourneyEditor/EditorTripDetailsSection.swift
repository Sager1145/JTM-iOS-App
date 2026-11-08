import RailApplication
import RailCore
import RailPresentation
import SwiftUI

/// What was ridden: the series, the set and its cars, the car ridden, the
/// livery and the two platforms that matter most. A timetable's published
/// formation and a ticket's car fill these; other stops' platforms are on
/// their rows.
struct EditorVehicleSection: View, JourneyEditorLabelling {
    @Environment(AppLocalization.self) var localization
    @Bindable var model: TripDraftModel
    let suggestions: [TripDraftModel.Field: String]

    var body: some View {
        let missing = model.missingDetails
        Section {
            Button { model.showsVehiclePicker = true } label: {
                EditorCompactRow(title: localization.text("ios.editor.vehicleType"),
                                 source: model.filledBy[.vehicleType]) {
                    Text(model.draft.vehicleType.flatMap { $0.isEmpty ? nil : $0 }
                         ?? text("vehicleAdd", fallback: "Add"))
                        .foregroundStyle(missing.vehicleType ? Color.accentColor : Color.primary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("newTripVehicleType")
            if model.draft.vehicleType?.isEmpty ?? true, let suggested = suggestions[.vehicleType] {
                EditorSuggestionChip(value: suggested, identifier: "newTripSuggestVehicle") {
                    model.optionalText(.vehicleType, \.vehicleType).wrappedValue = suggested
                }
            }
            HStack(spacing: RailSpacing.s12) {
                compactNumber(text("setNumber", fallback: "Set"), field: .setNumber,
                              binding: model.stockText(.setNumber, \.setNumber), keyboard: .asciiCapable,
                              identifier: "newTripSetNumber")
                Divider()
                compactNumber(text("carCount", fallback: "Cars"), field: .carCount,
                              binding: model.stockNumber(.carCount, \.carCount), keyboard: .numberPad,
                              identifier: "newTripCarCount")
                Divider()
                compactNumber(text("riddenCar", fallback: "Car ridden"), field: .riddenCar,
                              binding: model.stockNumber(.riddenCar, \.riddenCar), keyboard: .numberPad,
                              identifier: "newTripRiddenCar")
            }
            if model.draft.rollingStock?.setNumber == nil, let suggested = suggestions[.setNumber] {
                EditorSuggestionChip(value: suggested, identifier: "newTripSuggestSet") {
                    model.stockText(.setNumber, \.setNumber).wrappedValue = suggested
                }
            }
            NavigationLink {
                EditorCarNumbersView(model: model)
            } label: {
                EditorCompactRow(title: text("carNumbers", fallback: "Car numbers"),
                                 source: model.filledBy[.carNumbers]) {
                    Text(carNumbersSummary)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .accessibilityIdentifier("newTripCarNumbers")
            EditorCompactRow(title: text("livery", fallback: "Livery"), source: model.filledBy[.livery]) {
                EditorInlineTextField(title: text("livery", fallback: "Livery"),
                                      text: model.stockText(.livery, \.livery))
                    .accessibilityIdentifier("newTripLivery")
            }
            if model.draft.rollingStock?.livery == nil, let suggested = suggestions[.livery] {
                EditorSuggestionChip(value: suggested, identifier: "newTripSuggestLivery") {
                    model.stockText(.livery, \.livery).wrappedValue = suggested
                }
            }
            HStack {
                Text(text("platforms", fallback: "Platforms"))
                Spacer()
                Text(text("departureShort", fallback: "Dep.")).font(.caption).foregroundStyle(.secondary)
                PlatformEntryBadge(platform: model.departurePlatform, identifier: "newTripDeparturePlatform")
                Text(text("arrivalShort", fallback: "Arr.")).font(.caption).foregroundStyle(.secondary)
                PlatformEntryBadge(platform: model.arrivalPlatform, identifier: "newTripArrivalPlatform")
            }
            if !missing.isEmpty {
                Label(missingText(missing), systemImage: "square.and.pencil")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("newTripNeedsDetails")
            }
        } header: {
            Text(text("vehicle", fallback: "Train and car"))
        }
    }

    /// A short stacked field for the set/cars/car row: caption above value.
    private func compactNumber(
        _ title: String, field: TripDraftModel.Field, binding: Binding<String>,
        keyboard: UIKeyboardType, identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: RailSpacing.s4) {
                Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if model.filledBy[field] != nil {
                    Image(systemName: model.filledBy[field]?.symbol ?? "")
                        .font(.caption2)
                        .foregroundStyle(.tint)
                        .accessibilityLabel(localization.text(
                            "ios.newTrip.fillSource.\(model.filledBy[field]?.rawValue ?? "")", fallback: ""))
                }
            }
            TextField(title, text: binding)
                .keyboardType(keyboard)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
                .accessibilityIdentifier(identifier)
        }
        .frame(maxWidth: .infinity, minHeight: RailSize.touch, alignment: .leading)
    }

    private var carNumbersSummary: String {
        let numbers = (model.draft.rollingStock?.cars ?? []).compactMap(\.number)
        if numbers.isEmpty { return text("vehicleAdd", fallback: "Add") }
        return numbers.count == 1 ? numbers[0] : "\(numbers[0]) … \(numbers[numbers.count - 1])"
    }
}

/// One number per car of the set, in order. The rows follow Cars; a car
/// without a number is not stored.
struct EditorCarNumbersView: View, JourneyEditorLabelling {
    @Environment(AppLocalization.self) var localization
    @Bindable var model: TripDraftModel

    var body: some View {
        Form {
            Section {
                ForEach(model.carSequences, id: \.self) { sequence in
                    EditorCompactRow(title: text("carRow", fallback: "Car {n}", ["n": .string(String(sequence))])) {
                        EditorInlineTextField(title: text("carNumber", fallback: "Number"),
                                              text: model.carNumber(sequence), keyboard: .asciiCapable)
                            .accessibilityIdentifier("newTripCarNumber-\(sequence)")
                    }
                }
            } footer: {
                Text(text("carNumbersNote", fallback: "Set Cars first to list every car of the set."))
            }
        }
        .navigationTitle(text("carNumbers", fallback: "Car numbers"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Seat, class, fare and kind, from the ticket or typed.
struct EditorTicketSection: View, JourneyEditorLabelling {
    @Environment(AppLocalization.self) var localization
    @Bindable var model: TripDraftModel

    private static let kinds = ["ticket", "expressSupplement", "seatReservation"]

    var body: some View {
        Section {
            HStack(spacing: RailSpacing.s12) {
                stacked(text("seat", fallback: "Seat"), field: .seat) {
                    TextField(text("seat", fallback: "Seat"), text: model.ticketText(.seat, \.seat))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("newTripSeat")
                }
                Divider()
                stacked(text("seatClass", fallback: "Class"), field: .seatClass) {
                    TextField(text("seatClass", fallback: "Class"), text: model.ticketText(.seatClass, \.seatClass))
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("newTripSeatClass")
                }
            }
            EditorCompactRow(title: text("fare", fallback: "Fare"), source: model.filledBy[.fare]) {
                HStack(spacing: RailSpacing.s4) {
                    EditorInlineTextField(title: "0", text: model.fareText, keyboard: .numberPad)
                        .accessibilityIdentifier("newTripFare")
                    if let currency = model.draft.ticket?.currency ?? model.regionCurrency {
                        Text(currency).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            EditorCompactRow(title: text("ticketKind", fallback: "Ticket"), source: model.filledBy[.ticketKind]) {
                Picker(text("ticketKind", fallback: "Ticket"), selection: model.readerBinding(
                    .ticketKind, get: { model.draft.ticket?.kind ?? "" },
                    set: { value in model.updateTicket { $0.kind = value.isEmpty ? nil : value } })) {
                    Text(text("ticketKindNone", fallback: "Not set")).tag("")
                    ForEach(kindOptions, id: \.self) { kind in
                        Text(kindLabel(kind)).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .accessibilityIdentifier("newTripTicketKind")
            }
        } header: {
            Text(text("ticket", fallback: "Ticket"))
        }
    }

    /// A kind from another source stays choosable.
    private var kindOptions: [String] {
        let current = model.draft.ticket?.kind ?? ""
        return current.isEmpty || Self.kinds.contains(current) ? Self.kinds : Self.kinds + [current]
    }

    private func kindLabel(_ kind: String) -> String {
        Self.kinds.contains(kind) ? localization.text("ios.ticket.kind.\(kind)", fallback: kind) : kind
    }

    private func stacked<Content: View>(
        _ title: String, field: TripDraftModel.Field, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: RailSpacing.s8) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                FillSourceBadge(source: model.filledBy[field])
            }
            content()
        }
        .frame(maxWidth: .infinity, minHeight: RailSize.touch, alignment: .leading)
    }
}
