import RailCore
import SwiftUI

struct RoutePolicyEditorView: View {
    @Environment(AppLocalization.self) private var localization
    @Binding var policy: RoutePolicy

    var body: some View {
        Form {
            Section(localization.text("ios.editor.solver")) {
                Picker(
                    localization.text("ios.editor.institutionFilter"),
                    selection: optionalText(\.institutionFilterMode)
                ) {
                    Text(localization.text("ios.editor.automatic")).tag("")
                    Text(localization.text("ios.editor.softPreference")).tag("soft")
                    Text(localization.text("ios.editor.hardConstraint")).tag("hard")
                }
                Toggle(
                    localization.text("ios.editor.jrOnlyHint"), isOn: optionalBool(\.jrOnly))
                // Schema constants, shown so the reader can see they are off
                // rather than wonder. jsonspec §13.5: a straight line between
                // two stations is forbidden under all circumstances.
                LabeledContent(
                    localization.text("ios.editor.routeAlternatives"),
                    value: localization.text("ios.editor.disabled"))
                LabeledContent(
                    localization.text("ios.editor.straightLineFallback"),
                    value: localization.text("ios.editor.disabled"))
            }

            Section {
                EditorTextField(
                    title: localization.text("ios.editor.institutionCodes"),
                    text: commaSeparated(\.allowedInstitutionTypeCodes),
                    prompt: "1, 2, 3"
                )
                EditorTextField(
                    title: localization.text("ios.editor.preferredLines"),
                    text: commaSeparated(\.preferredLineNames),
                    prompt: localization.text("ios.editor.onePerComma")
                )
                EditorTextField(
                    title: localization.text("ios.editor.preferredOperators"),
                    text: commaSeparated(\.preferredOperatorNames),
                    prompt: localization.text("ios.editor.onePerComma")
                )
            } header: {
                Text(localization.text("ios.editor.preferences"))
            } footer: {
                Text(localization.text("ios.editor.policyFooter"))
            }
        }
        .navigationTitle(localization.text("ios.routePolicy", fallback: "Route policy"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func optionalText(_ keyPath: WritableKeyPath<RoutePolicy, String?>) -> Binding<String> {
        EditorBindings.optionalText($policy, keyPath)
    }

    private func optionalBool(_ keyPath: WritableKeyPath<RoutePolicy, Bool?>) -> Binding<Bool> {
        Binding(
            get: { policy[keyPath: keyPath] ?? false },
            set: { policy[keyPath: keyPath] = $0 }
        )
    }

    private func commaSeparated(
        _ keyPath: WritableKeyPath<RoutePolicy, [String]?>
    ) -> Binding<String> {
        EditorBindings.commaSeparated($policy, keyPath)
    }

}

