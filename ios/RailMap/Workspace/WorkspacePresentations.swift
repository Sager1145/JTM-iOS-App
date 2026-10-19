import RailCore
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
                localization.journeyText(
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
                    Text(localization.journeyText(
                        "ios.journey.deleteDetail",
                        fallback: "The journey is removed from the data on this device."))
                }
            }
            .sheet(item: $sheet, onDismiss: onSheetDismiss) { presented in
                // Catalyst may host this presentation outside the resident
                // tab tree. Supply the same required object at the sheet root
                // so WorkspaceSheetContent and StationCardView never read an
                // absent AppLocalization from the new host's environment.
                sheetContent(presented)
                    .environment(localization)
                    .environment(presentationHost)
            }
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
            localization.journeyText(
                "ios.journey.deleteConfirm",
                ["train": .string(train.number)],
                fallback: "Delete {train}?")
        case .some(.addDate), .some(.saveFailed), .none:
            ""
        }
    }

}
