import RailCore
import SwiftUI

/// What a trip still lacks after the automatic sources ran. Counted, never
/// filled: the reader enters what is left by hand.
struct MissingTripDetails: Equatable {
    var vehicleType: Bool
    var departurePlatform: Bool
    var arrivalPlatform: Bool
    /// Ridden stops between the ends with no platform.
    var otherPlatforms: Int

    init(train: Train, departurePlatform: Int?, arrivalPlatform: Int?) {
        vehicleType = (train.vehicleType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        self.departurePlatform = departurePlatform == nil
        self.arrivalPlatform = arrivalPlatform == nil
        otherPlatforms = train.stops.count > 2
            ? train.stops.dropFirst().dropLast().filter {
                $0.platformNumber == nil && $0.rideSegment && $0.stopType != "pass"
            }.count
            : 0
    }

    var isEmpty: Bool { !vehicleType && !departurePlatform && !arrivalPlatform && otherPlatforms == 0 }
    var platformCount: Int { (departurePlatform ? 1 : 0) + (arrivalPlatform ? 1 : 0) + otherPlatforms }
}

/// A platform badge that opens a number pad in place: one tap to open,
/// one tap to choose. No screen per stop.
struct PlatformEntryBadge: View {
    @Environment(AppLocalization.self) private var localization
    @Binding var platform: Int?
    let identifier: String
    @State private var showsPad = false

    var body: some View {
        Button {
            showsPad = true
        } label: {
            Text(platform.map { localization.text(
                "ios.detail.platformValue", params: ["number": .number(Double($0))]) }
                ?? localization.text("ios.newTrip.platformAdd", fallback: "+ Platform"))
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(platform == nil ? Color.accentColor : Color.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    platform == nil ? Color.accentColor.opacity(0.12) : Color(.tertiarySystemFill),
                    in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier(identifier)
        .popover(isPresented: $showsPad) {
            PlatformPad(platform: $platform) { showsPad = false }
                .presentationCompactAdaptation(.popover)
        }
    }
}

/// 1–20 as one grid of keys, an "other number" field, and Clear.
private struct PlatformPad: View {
    @Environment(AppLocalization.self) private var localization
    @Binding var platform: Int?
    let done: () -> Void
    @State private var other = ""

    private let columns = Array(repeating: GridItem(.fixed(44), spacing: 6), count: 5)

    var body: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(1...20, id: \.self) { number in
                    Button {
                        platform = number
                        done()
                    } label: {
                        Text(String(number))
                            .font(.body.monospacedDigit())
                            .frame(width: 44, height: 40)
                            .background(
                                platform == number ? Color.accentColor : Color(.tertiarySystemFill),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .foregroundStyle(platform == number ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("platformPadKey-\(number)")
                }
            }
            HStack(spacing: 8) {
                TextField(localization.text("ios.newTrip.platformOther", fallback: "Other"), text: $other)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 96)
                    .onSubmit(commitOther)
                Button(localization.text("ios.done", fallback: "Done"), action: commitOther)
                    .disabled(Int(other) == nil)
                Spacer(minLength: 0)
                Button(localization.text("ios.newTrip.platformClear", fallback: "Clear"), role: .destructive) {
                    platform = nil
                    done()
                }
                .disabled(platform == nil)
            }
        }
        .padding(14)
        .frame(width: 290)
    }

    private func commitOther() {
        // The record allows any whole number from 0; letters do not fit it.
        guard let value = Int(other.trimmingCharacters(in: .whitespaces)), value >= 0 else { return }
        platform = value
        done()
    }
}

/// Vehicle type: suggestions for this trip first, then free text.
struct VehiclePickerView: View {
    @Environment(AppLocalization.self) private var localization
    @Environment(\.dismiss) private var dismiss
    @Binding var vehicleType: String?
    let suggestions: [String]
    @State private var typed = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField(localization.text("ios.editor.vehicleType"), text: $typed)
                            .submitLabel(.done)
                            .onSubmit(commitTyped)
                            .accessibilityIdentifier("vehiclePickerField")
                        Button(localization.text("ios.done", fallback: "Done"), action: commitTyped)
                            .disabled(typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                if !suggestions.isEmpty {
                    Section(localization.text("ios.newTrip.vehicleSuggestions", fallback: "Suggestions")) {
                        ForEach(suggestions, id: \.self) { value in
                            Button {
                                vehicleType = value
                                dismiss()
                            } label: {
                                HStack {
                                    Text(value).foregroundStyle(.primary)
                                    Spacer()
                                    if vehicleType == value {
                                        Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                    }
                                }
                                .frame(minHeight: 44)
                            }
                            .accessibilityIdentifier("vehiclePickerSuggestion-\(value)")
                        }
                    }
                }
                if vehicleType != nil {
                    Section {
                        Button(localization.text("ios.newTrip.platformClear", fallback: "Clear"), role: .destructive) {
                            vehicleType = nil
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(localization.text("ios.editor.vehicleType"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localization.text("ios.cancel", fallback: "Cancel")) { dismiss() }
                }
            }
            .onAppear { typed = vehicleType ?? "" }
        }
    }

    private func commitTyped() {
        let value = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        vehicleType = value
        dismiss()
    }

    /// Vehicle types the reader used on the same lines or the same train,
    /// most frequent first, then any they used recently.
    static func suggestions(for train: Train, among saved: [Train]) -> [String] {
        let lines = Set((train.routeSections ?? []).flatMap { $0.lineIDs ?? [] })
        let number = train.number.trimmingCharacters(in: .whitespacesAndNewlines)
        var near: [String: Int] = [:]
        var recent: [String] = []
        for other in saved where other.id != train.id {
            guard let value = other.vehicleType?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { continue }
            let otherLines = Set((other.routeSections ?? []).flatMap { $0.lineIDs ?? [] })
            if (!number.isEmpty && other.number == number) || !lines.isDisjoint(with: otherLines) {
                near[value, default: 0] += 1
            }
            if !recent.contains(value) { recent.append(value) }
        }
        let ranked = near.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
        return Array((ranked + recent.filter { !ranked.contains($0) }).prefix(12))
    }
}
