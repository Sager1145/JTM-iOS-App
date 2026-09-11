import SwiftUI

/// The panel's layout boundary. The header stays top-aligned at the compact
/// stop; content receives the safe area directly so it scrolls under the tab
/// bar while its final row still scrolls clear. No clipping/GeometryReader here.
struct WorkspacePanelPage<Header: View, Content: View>: View {
    @Environment(PanelMorph.self) private var morph: PanelMorph?
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            header().layoutPriority(1)
            if (morph?.stage ?? .expanded) != .compact {
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
