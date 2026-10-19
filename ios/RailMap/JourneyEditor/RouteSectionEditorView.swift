import RailCore
import SwiftUI

struct RouteSectionLabel: View {
    let section: RouteSection?
    let index: Int
    let train: Train
    let localization: AppLocalization

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(localization.text("ios.editor.sectionIndex", params: ["index": .number(Double(index))]))
            // Lean archive sections can recover an omitted name from the
            // matching adjacent stop through the shared naming rule.
            Text("\(localization.sectionEndpoint(name: section?.from, code: section?.fromN02StationCode, in: train, stopIndex: index - 1)) → "
                + "\(localization.sectionEndpoint(name: section?.to, code: section?.toN02StationCode, in: train, stopIndex: index))")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }
}

struct RouteSectionEditorView: View {
    @Environment(AppLocalization.self) private var localization
    @Binding var section: RouteSection
    let region: Region
    var rideDate: String? = nil

    var body: some View {
        Form {
            Section(localization.text("ios.editor.endpoints")) {
                EditorTextField(
                    title: localization.text("ios.editor.fromStation"),
                    text: endpointText(\.from, code: \.fromN02StationCode))
                NavigationLink {
                    StationPickerView(
                        regionCode: region.code,
                        onSelect: { station in
                            section.from = station.name
                            section.fromN02StationCode = station.key.sourceCode
                        },
                        rideDate: rideDate,
                        onSelectRetired: { station in
                            section.from = station.name
                            section.fromN02StationCode = station.certifiedCode
                        })
                    .environment(localization)
                } label: {
                    LabeledContent(
                        localization.text("ios.editor.chooseStation"),
                        value: section.from ?? "")
                }
                EditorTextField(
                    title: localization.text("ios.editor.toStation"),
                    text: endpointText(\.to, code: \.toN02StationCode))
                NavigationLink {
                    StationPickerView(
                        regionCode: region.code,
                        onSelect: { station in
                            section.to = station.name
                            section.toN02StationCode = station.key.sourceCode
                        },
                        rideDate: rideDate,
                        onSelectRetired: { station in
                            section.to = station.name
                            section.toN02StationCode = station.certifiedCode
                        })
                    .environment(localization)
                } label: {
                    LabeledContent(
                        localization.text("ios.editor.chooseStation"),
                        value: section.to ?? "")
                }
            }

            Section(localization.text("ios.editor.constraints")) {
                EditorTextField(
                    title: localization.text("ios.editor.lineNames"),
                    text: commaSeparated(\.lineNames),
                    prompt: localization.text("ios.editor.onePerComma"))
                EditorTextField(
                    title: localization.text("ios.editor.operatorNames"),
                    text: commaSeparated(\.operatorNames),
                    prompt: localization.text("ios.editor.onePerComma"))
            }

            Section(localization.text("ios.editor.sectionService")) {
                EditorTextField(
                    title: localization.countryText("field.number", fallback: "Train number"),
                    text: optionalText(\.number))
                EditorTextField(
                    title: localization.text("ios.editor.displayName"),
                    text: optionalText(\.name))
            }
        }
        .navigationTitle(localization.text("ios.routeSection", fallback: "Route section"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func optionalText(_ keyPath: WritableKeyPath<RouteSection, String?>) -> Binding<String> {
        EditorBindings.optionalText($section, keyPath)
    }

    private func endpointText(
        _ keyPath: WritableKeyPath<RouteSection, String?>,
        code: WritableKeyPath<RouteSection, String?>
    ) -> Binding<String> {
        Binding(
            get: { section[keyPath: keyPath] ?? "" },
            set: { value in
                if value != section[keyPath: keyPath] { section[keyPath: code] = nil }
                section[keyPath: keyPath] = value.isEmpty ? nil : value
            }
        )
    }

    private func commaSeparated(
        _ keyPath: WritableKeyPath<RouteSection, [String]?>
    ) -> Binding<String> {
        EditorBindings.commaSeparated($section, keyPath)
    }
}

