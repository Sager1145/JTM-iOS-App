import SwiftUI

/// §6.4's `radius-control`, a 44-point row, and the field's own clear button —
/// the three things that make this read as the system's search field rather
/// than as a text box that happens to filter a list.
///
/// A type of its own because it is the one part of the search destination that
/// owes the workspace nothing: two bindings and the reader's language, and no
/// knowledge of journeys, dates, stores or the map. It was 58 lines in the
/// middle of `RailWorkspaceView`, where the only thing separating it from the
/// statistics panel was a blank line.
struct JourneySearchField: View {
    @Binding var query: String

    /// The focus lives with the destination that owns the keyboard shortcut
    /// (⌘F focuses this field from anywhere), so it is bound in rather than
    /// declared here.
    @FocusState.Binding var isFocused: Bool

    @Environment(AppLocalization.self) private var localization

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(
                localization.countryText(
                    "ph.search", fallback: "Train, station, or identifier"),
                text: $query)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("journeySearchField")
            if !query.isEmpty { clearButton }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(
            Color(.tertiarySystemFill),
            in: RoundedRectangle(
                cornerRadius: RailStyle.controlCornerRadius,
                style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var clearButton: some View {
        Button {
            query = ""
            isFocused = true
        } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
                // Hit at 44, drawn at the glyph's own size — the same
                // two-numbers rule `SheetIconButton` states, and for the same
                // reason. A bare `Image` label gives the button the glyph's
                // bounds as its hit region, and `RailPressStyle` only scales
                // and dims, so this was a twenty-point target inside a field
                // whose whole job is to be typed in and cleared. The
                // `minHeight` on the row above binds the ROW, not the button
                // in it.
                .frame(width: 44, height: 44)
                .contentShape(.rect)
                // The enlarged target reclaims the field's own trailing inset
                // rather than pushing the glyph inward, so the mark stays
                // exactly where it was drawn. This is what UIKit's search
                // field does with its own clear button.
                .padding(.trailing, -12)
        }
        .buttonStyle(RailPressStyle(dims: false))
        .accessibilityLabel(
            Text(localization.text("ios.clear", fallback: "Clear search")))
    }
}
