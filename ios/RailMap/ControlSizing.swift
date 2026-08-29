import SwiftUI

extension View {
    /// Keeps a compact control's visual style while giving the control the
    /// minimum landing area used throughout the app.
    ///
    /// Apply this to the semantic control, after its style, rather than to a
    /// surrounding row. A row-sized frame does not enlarge the button inside
    /// it, and fixed heights can clip labels when Dynamic Type needs more room.
    func railMinimumTouchTarget() -> some View {
        frame(
            minWidth: RailStyle.minimumTouchTarget,
            minHeight: RailStyle.minimumTouchTarget)
            .contentShape(.rect)
    }
}
