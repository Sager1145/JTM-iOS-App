import RailCore
import SwiftUI

/// The alert that collects a date the reader means to travel on.
///
/// ## Why the draft lives here
///
/// It was `@State private var newManualDate` on `RailWorkspaceView`, and the
/// workspace had to remember to blank it in the menu button that raises this
/// alert — a reset written three hundred lines away from the field it resets,
/// and one that a second entry point would have had to remember too. A text
/// field's contents are meaningless once its alert closes, so they belong to
/// the alert: this owns its draft and clears it on the way in, which is the
/// same behaviour with nobody left to forget it.
///
/// What it does not own is what a date MEANS. The string goes back out through
/// ``add``, and `ManualDates` decides whether it is a date at all.
struct AddDateAlert: ViewModifier {
    @Binding var isPresented: Bool

    /// Called with the raw text. The caller normalises, stores and selects it.
    let add: (String) -> Void

    @State private var draft = ""
    @Environment(AppLocalization.self) private var localization

    func body(content: Content) -> some View {
        content
            .alert(
                localization.journeyText("ios.journey.addDateTitle", fallback: "Add a date"),
                isPresented: $isPresented
            ) {
                TextField("YYYY-MM-DD", text: $draft)
                Button(localization.text("ios.cancel", fallback: "Cancel"), role: .cancel) {}
                Button(localization.journeyText("btn.add", fallback: "Add")) { add(draft) }
                    // The same test `ManualDates.add` applies, asked early so
                    // the button is dim rather than silent. Duplicated on
                    // purpose: a disabled control and a refused action are two
                    // different jobs, and only one of them may be skipped.
                    .disabled(Dates.normalizeDateString(draft) == nil)
            } message: {
                Text(
                    localization.journeyText(
                        "ios.journey.addDateDetail",
                        fallback: "Create an empty date to add journeys to later."))
            }
            // Cleared on the way IN rather than on the way out: a cancel that
            // leaves text behind is invisible until the alert is opened again,
            // and by then the reader has forgotten typing it.
            .onChange(of: isPresented) { _, presented in
                if presented { draft = "" }
            }
    }
}

extension View {
    /// See ``AddDateAlert``.
    func addDateAlert(
        isPresented: Binding<Bool>, add: @escaping (String) -> Void
    ) -> some View {
        modifier(AddDateAlert(isPresented: isPresented, add: add))
    }
}
