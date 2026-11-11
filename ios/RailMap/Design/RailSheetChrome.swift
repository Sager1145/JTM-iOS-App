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

/// The toolbar of an editing sheet (spec §6.5, D3): Cancel leading, optional
/// confirm trailing, inline title, system navigation bar.
///
/// Cancel always reads `localization.text("ios.cancel", fallback: "Cancel")`;
/// pass that as `cancelTitle` so every sheet says the same word in every
/// language. Callers keep their own dirty checks and dismissal inside the
/// closures. Pass `cancelTitle: nil` for a pushed screen that has no Cancel,
/// only a confirm. The confirm button is semibold before iOS 26 and the
/// prominent glass button on iOS 26.
struct RailEditingToolbar: ToolbarContent {
    var cancelTitle: Text?
    var cancelID: String?
    var cancelDisabled = false
    var onCancel: () -> Void = {}
    var confirmTitle: Text?
    var confirmID: String?
    var canConfirm = true
    var confirmShortcut: KeyboardShortcut?
    var onConfirm: (() -> Void)?

    var body: some ToolbarContent {
        // The conditions sit OUTSIDE the items: an item whose content is
        // empty still claims its slot, and on iOS 26 draws an empty glass
        // bubble (or crowds the back button on a pushed page).
        if let cancelTitle {
            ToolbarItem(placement: .cancellationAction) {
                Button(role: .cancel, action: onCancel) { cancelTitle }
                    .disabled(cancelDisabled)
                    .optionalIdentifier(cancelID)
            }
        }
        if let confirmTitle, let onConfirm {
            ToolbarItem(placement: .confirmationAction) {
                confirmButton(title: confirmTitle, action: onConfirm)
            }
        }
    }

    @ViewBuilder
    private func confirmButton(title: Text, action: @escaping () -> Void) -> some View {
        let button = Button(action: action) { title }
            .disabled(!canConfirm)
            .optionalShortcut(confirmShortcut)
            .optionalIdentifier(confirmID)
        if #available(iOS 26.0, *) {
            button.buttonStyle(.glassProminent)
        } else {
            button.fontWeight(.semibold)
        }
    }
}

private extension View {
    @ViewBuilder
    func optionalIdentifier(_ id: String?) -> some View {
        if let id { accessibilityIdentifier(id) } else { self }
    }

    @ViewBuilder
    func optionalShortcut(_ shortcut: KeyboardShortcut?) -> some View {
        if let shortcut { keyboardShortcut(shortcut) } else { self }
    }
}

enum RailSheetHeight {
    /// Opens at half height, expandable, with a visible grabber.
    case half
    /// Opens full height.
    case full
    /// Half height like ``half``, and the map or list behind it stays live and
    /// undimmed up to medium height. For sheets whose controls change the
    /// parent view (map layers, trip filters): the reader checks the result
    /// without dismissing the sheet. HIG Sheets, non-modal.
    case halfNonModal
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
        case .halfNonModal:
            railHalfSheetDetents()
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        #endif
    }
}
