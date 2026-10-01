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
        .background(TabHostTransparency())
    }
}

/// Clears the opaque system background UIKit gives each tab's hosting view,
/// so the shared menu surface shows through without a second color layer.
/// Walks up only as far as the tab bar controller's own view.
private struct TabHostTransparency: UIViewRepresentable {
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ uiView: Probe, context: Context) {}

    final class Probe: UIView {
        private weak var tabBar: UITabBar?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            isUserInteractionEnabled = false
            var view = superview
            while let current = view {
                current.backgroundColor = .clear
                if let controller = current.next as? UITabBarController {
                    tabBar = controller.tabBar
                    break
                }
                view = current.superview
            }
            liftTabBar()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            liftTabBar()
        }

        /// A soft shadow in the shape of the system tab bar's glass capsule
        /// separates it from the opaque menu surface. The path is explicit
        /// because the glass renders nothing a layer shadow could trace.
        private func liftTabBar() {
            guard let bar = tabBar,
                  let platter = bar.subviews.first(where: { $0.frame.height < bar.bounds.height })
            else { return }
            bar.layer.shadowColor = UIColor.black.cgColor
            bar.layer.shadowOpacity = 0.16
            bar.layer.shadowRadius = 12
            bar.layer.shadowOffset = CGSize(width: 0, height: 4)
            bar.layer.shadowPath = UIBezierPath(
                roundedRect: platter.frame,
                cornerRadius: platter.frame.height / 2).cgPath
        }
    }
}
