import RailPresentation
import SwiftUI

struct TabClearanceDiagnostic: ViewModifier {
    let occlusion: CGFloat
    @ViewBuilder func body(content: Content) -> some View {
        #if DEBUG
        if UITestLaunchConfiguration.current[.tabBarProbe] == "1" {
            content.accessibilityValue(Text(verbatim: "tabBarOcclusion:\(occlusion)"))
        } else { content }
        #else
        content
        #endif
    }
}
