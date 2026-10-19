import SwiftUI

/// The app-wide destinations at the end of every workspace utility menu.
/// Scope and data-source items remain with the calling destination; these two
/// always appear last in the same order.
struct WorkspaceUtilityMenuItems: View {
    @Environment(AppLocalization.self) private var localization

    let onOpenData: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        // Identifiers are language-independent because UI tests must not look
        // up the reader-facing translated labels.
        Button(action: onOpenData) {
            Label(
                localization.text(
                    UtilityDestination.data.localizationKey,
                    fallback: UtilityDestination.data.fallbackName),
                systemImage: UtilityDestination.data.systemImage)
        }
        .accessibilityIdentifier("utilityDataButton")
        Button(action: onOpenSettings) {
            Label(
                localization.text(
                    UtilityDestination.settings.localizationKey,
                    fallback: UtilityDestination.settings.fallbackName),
                systemImage: UtilityDestination.settings.systemImage)
        }
        .accessibilityIdentifier("utilitySettingsButton")
    }
}
