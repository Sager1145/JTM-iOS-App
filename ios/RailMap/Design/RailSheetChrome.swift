import SwiftUI

/// The close control for a view-only sheet (spec §6.5, D2/D4).
///
/// iOS 26 gets the system close button; earlier systems keep the app's
/// circular `SheetCloseButton`. Both answer Escape / Cmd-. and carry the label.
struct RailSheetCloseButton: View {
    var label: Text
    var action: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(role: .close, action: action)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel(label)
        } else {
            SheetCloseButton(accessibilityLabel: label, action: action)
        }
    }
}

extension View {
    /// Trailing close button for a view-only sheet. Edit sheets keep their
    /// Cancel / Save pair instead.
    func railSheetClose(
        _ label: Text, identifier: String, action: @escaping () -> Void
    ) -> some View {
        toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                RailSheetCloseButton(label: label, action: action)
                    .accessibilityIdentifier(identifier)
            }
        }
    }
}

enum RailSheetHeight {
    /// Opens at half height, expandable, with a visible grabber.
    case half
    /// Opens full height.
    case full
}

extension View {
    /// Standard sheet presentation. No-op on Mac Catalyst, where a form sheet
    /// is a window that ignores detents (see `railHalfSheetDetents`).
    @ViewBuilder
    func railSheet(_ height: RailSheetHeight) -> some View {
        #if targetEnvironment(macCatalyst)
        self
        #else
        switch height {
        case .half:
            railHalfSheetDetents().presentationDragIndicator(.visible)
        case .full:
            presentationDetents([.large])
        }
        #endif
    }
}
