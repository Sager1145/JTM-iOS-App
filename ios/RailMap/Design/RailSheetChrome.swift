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
        ToolbarItem(placement: .cancellationAction) {
            if let cancelTitle {
                Button(role: .cancel, action: onCancel) { cancelTitle }
                    .disabled(cancelDisabled)
                    .optionalIdentifier(cancelID)
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            if let confirmTitle, let onConfirm {
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
