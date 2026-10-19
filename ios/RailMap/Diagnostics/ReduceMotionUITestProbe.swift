import RailPresentation
import SwiftUI

/// A debug-only observation point for the UI test that is run after the
/// simulator's *system* Reduce Motion setting has been enabled. It never
/// changes application behavior and is absent from release accessibility.
struct ReduceMotionUITestProbe: ViewModifier {
    var enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        #if DEBUG
        if UITestLaunchConfiguration.current[.reportReduceMotion] == "1" {
            content.accessibilityValue(Text(enabled ? "enabled" : "disabled"))
        } else {
            content
        }
        #else
        content
        #endif
    }
}

