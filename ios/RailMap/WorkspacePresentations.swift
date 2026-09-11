import RailCore
import SwiftUI

/// A single dialog slot prevents simultaneous alert and confirmation requests.
enum WorkspaceDialog {
    case addDate
    case delete(Train)
}

/// Attached to the resident chrome's host, outside compact size-class overrides.
/// The workspace owns the slots and mutations; this modifier owns presentation.
struct WorkspacePresentations<SheetContent: View>: ViewModifier {
    @Binding var dialog: WorkspaceDialog?
    @Binding var sheet: WorkspaceSheet?
    let onAddDate: (String) -> Void
    let onDelete: (Train) -> Void
    @ViewBuilder var sheetContent: (WorkspaceSheet) -> SheetContent
    @Environment(AppLocalization.self) private var localization

    func body(content: Content) -> some View {
        content
            .addDateAlert(isPresented: addDateIsPresented, add: onAddDate)
            .confirmationDialog(
                confirmationTitle, isPresented: confirmationIsPresented,
                titleVisibility: .visible
            ) {
                if case .delete(let train) = dialog {
                    Button(localization.countryText("btn.delete", fallback: "Delete"),
                           role: .destructive) {
                        dialog = nil
                        PresentationHost.afterTeardown { onDelete(train) }
                    }
                }
            } message: {
                if case .delete = dialog {
                    Text(localization.journeyText(
                        "ios.journey.deleteDetail",
                        fallback: "The journey is removed from the data on this device."))
                }
            }
            .sheet(item: $sheet) { presented in
                // Catalyst may host this presentation outside the resident
                // tab tree. Supply the same required object at the sheet root
                // so WorkspaceSheetContent and StationCardView never read an
                // absent AppLocalization from the new host's environment.
                sheetContent(presented)
                    .environment(localization)
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

    private var confirmationIsPresented: Binding<Bool> {
        Binding(
            get: {
                switch dialog {
                case .some(.delete): true
                case .some(.addDate), .none: false
                }
            },
            set: { presented in
                guard !presented else { return }
                switch dialog {
                case .some(.delete): dialog = nil
                case .some(.addDate), .none: break
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
        case .some(.addDate), .none:
            ""
        }
    }

}
