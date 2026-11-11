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
                .padding(.horizontal, RailSpacing.s8)
                .padding(.vertical, RailSpacing.s4)
                .background(
                    platform == nil ? Color.accentColor.opacity(0.12) : Color(.tertiarySystemFill),
                    in: Capsule())
                .frame(minHeight: RailSize.touch)
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

    @ScaledMetric(relativeTo: .body) private var otherFieldWidth: CGFloat = 96
    private static let keyColumns = 5

    private let columns = Array(repeating: GridItem(.fixed(RailSize.touch), spacing: RailSpacing.s4),
                                count: PlatformPad.keyColumns)
    /// Key columns at touch size plus their gaps and the content padding.
    private let padWidth = CGFloat(PlatformPad.keyColumns) * RailSize.touch
        + CGFloat(PlatformPad.keyColumns - 1) * RailSpacing.s4 + 2 * RailSpacing.s12

    var body: some View {
        VStack(spacing: RailSpacing.s8) {
            LazyVGrid(columns: columns, spacing: RailSpacing.s4) {
                ForEach(1...20, id: \.self) { number in
                    Button {
                        platform = number
                        done()
                    } label: {
                        Text(String(number))
                            .font(.body.monospacedDigit())
                            .frame(minWidth: RailSize.touch, minHeight: RailSize.touch)
                            .background(
                                platform == number ? Color.accentColor : Color(.tertiarySystemFill),
                                in: RoundedRectangle(cornerRadius: RailRadius.control, style: .continuous))
                            .foregroundStyle(platform == number ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("platformPadKey-\(number)")
                }
            }
            HStack(spacing: RailSpacing.s8) {
                TextField(localization.text("ios.newTrip.platformOther", fallback: "Other"), text: $other)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: otherFieldWidth)
                    .onSubmit(commitOther)
                Button(localization.text("ios.done", fallback: "Done"), action: commitOther)
                    .lineLimit(1).fixedSize()
                    .disabled(Int(other) == nil)
                Spacer(minLength: 0)
                Button(localization.text("ios.newTrip.platformClear", fallback: "Clear"), role: .destructive) {
                    platform = nil
                    done()
                }
                .lineLimit(1).fixedSize()
                .disabled(platform == nil)
            }
        }
        .padding(RailSpacing.s12)
        // At least the key grid; wider when large text needs it for the bottom row.
        .frame(minWidth: padWidth)
    }

    private func commitOther() {
        // The record allows any whole number from 0; letters do not fit it.
        guard let value = Int(other.trimmingCharacters(in: .whitespaces)), value >= 0 else { return }
        platform = value
        done()
    }
}

/// A choice in a list: the title, and a trailing accent checkmark on the
/// selected row only. Local until the design system's shared choice row
/// exists; that component replaces this one.
struct EditorChoiceRow: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        HStack {
            Text(title).foregroundStyle(.primary)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: RailSize.touch)
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Vehicle type: suggestions for this trip first, then free text. A page
/// pushed in the editor's navigation stack.
struct VehiclePickerView: View {
    @Environment(AppLocalization.self) private var localization
    @Environment(\.dismiss) private var dismiss
    @Binding var vehicleType: String?
    let suggestions: [String]
    @State private var typed = ""

    var body: some View {
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
                            EditorChoiceRow(title: value, isSelected: vehicleType == value)
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
        .onAppear { typed = vehicleType ?? "" }
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
