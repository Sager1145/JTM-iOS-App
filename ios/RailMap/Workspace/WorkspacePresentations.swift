import RailCore
import RailPresentation
import SwiftUI

/// A single dialog slot prevents simultaneous alert and confirmation requests.
enum WorkspaceDialog {
    case addDate
    case delete(Train)
    /// A committed change whose disk write failed; the detail may be nil.
    case saveFailed(String?)
}

/// Attached to the resident chrome's host, outside compact size-class overrides.
/// The workspace owns the slots and mutations; this modifier owns presentation.
struct WorkspacePresentations<SheetContent: View>: ViewModifier {
    @Binding var dialog: WorkspaceDialog?
    @Binding var sheet: WorkspaceSheet?
    /// The layout and hinge state the sheet's host is decided for. Sheets the
    /// policy hosts in the panel never reach the system sheet below; the
    /// panel presents them.
    let layoutMode: WorkspaceLayoutMode
    let isHinged: Bool
    let onAddDate: (String) -> Void
    let onDelete: (Train) -> Void
    let onSheetDismiss: () -> Void
    @ViewBuilder var sheetContent: (WorkspaceSheet) -> SheetContent
    @Environment(AppLocalization.self) private var localization
    @Environment(PresentationHost.self) private var presentationHost

    func body(content: Content) -> some View {
        content
            .addDateAlert(isPresented: addDateIsPresented, add: onAddDate)
            .alert(
                localization.countryText(
                    "ios.journey.saveFailedTitle", fallback: "Could not save this journey"),
                isPresented: saveFailedIsPresented
            ) {
                Button(localization.text("ios.done", fallback: "Done"), role: .cancel) {}
            } message: {
                if case .saveFailed(let detail?) = dialog { Text(detail) }
            }
            .confirmationDialog(
                confirmationTitle, isPresented: confirmationIsPresented,
                titleVisibility: .visible
            ) {
                if case .delete(let train) = dialog {
                    Button(localization.countryText("btn.delete", fallback: "Delete"),
                           role: .destructive) {
                        dialog = nil
                        // Confirmed work, not a presentation: it runs now.
                        onDelete(train)
                    }
                }
            } message: {
                if case .delete = dialog {
                    Text(localization.countryText(
                        "ios.journey.deleteDetail",
                        fallback: "The journey is removed from the data on this device."))
                }
            }
            .sheet(item: systemSheet, onDismiss: onSheetDismiss) { presented in
                // Catalyst may host this presentation outside the resident
                // tab tree. Supply the same required object at the sheet root
                // so WorkspaceSheetContent and StationCardView never read an
                // absent AppLocalization from the new host's environment.
                sheetContent(presented)
                    .environment(localization)
                    .environment(presentationHost)
                    .workspaceSheetHeight(presented)
            }
    }

    private func hostsInSystemSheet(_ presented: WorkspaceSheet) -> Bool {
        presented.host(mode: layoutMode, isHinged: isHinged) == .systemSheet
    }

    /// The workspace's sheet, nil while a panel-hosted sheet is open. Closing
    /// the system sheet clears the workspace's sheet only if it is still the
    /// system-hosted one.
    private var systemSheet: Binding<WorkspaceSheet?> {
        Binding(
            get: {
                guard let presented = sheet, hostsInSystemSheet(presented) else { return nil }
                return presented
            },
            set: { newValue in
                guard newValue == nil, let presented = sheet,
                      hostsInSystemSheet(presented) else { return }
                sheet = nil
            })
    }

    private var addDateIsPresented: Binding<Bool> {
        Binding(
            get: {
                if case .some(.addDate) = dialog { return true }
                return false
            },
            set: { presented in
                if !presented, case .some(.addDate) = dialog { dialog = nil }
            })
    }

    private var saveFailedIsPresented: Binding<Bool> {
        Binding(
            get: {
                if case .some(.saveFailed) = dialog { return true }
                return false
            },
            set: { presented in
                if !presented, case .some(.saveFailed) = dialog { dialog = nil }
            })
    }

    private var confirmationIsPresented: Binding<Bool> {
        Binding(
            get: {
                switch dialog {
                case .some(.delete): true
                case .some(.addDate), .some(.saveFailed), .none: false
                }
            },
            set: { presented in
                guard !presented else { return }
                switch dialog {
                case .some(.delete): dialog = nil
                case .some(.addDate), .some(.saveFailed), .none: break
                }
            })
    }

    private var confirmationTitle: String {
        switch dialog {
        case .some(.delete(let train)):
            localization.countryText(
                "ios.journey.deleteConfirm",
                params: ["train": .string(train.number)],
                fallback: "Delete {train}?")
        case .some(.addDate), .some(.saveFailed), .none:
            ""
        }
    }

}

private extension View {
    /// D4 detents for the sheets this host presents. The journey menu
    /// (`.detail`), map info/layers, the chooser, the hide sheet, utility and
    /// the station card own theirs.
    @ViewBuilder
    func workspaceSheetHeight(_ sheet: WorkspaceSheet) -> some View {
        switch sheet {
        case .importData, .transferGuide:
            railSheet(.full)
        // `.detail` presents WorkspaceJourneyMenu, which owns hand-built
        // detents (compact/medium/large, hidden grabber); a second detent set
        // here would fight its `selection`.
        case .detail, .hideTrips, .mapInfo, .mapLayers, .station, .chooseRide, .line, .chooseLine, .groupPicker, .utility:
            self
        }
    }
}
