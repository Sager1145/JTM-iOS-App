import SwiftUI

/// The panel's layout boundary. The header stays top-aligned at the compact
/// stop. Content stays mounted in the remaining viewport, preserving scroll
/// position and revealing existing rows immediately as the sheet grows.
struct WorkspacePanelPage<Header: View, Content: View>: View {
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            header().layoutPriority(1)
            WorkspacePanelViewport(content: content())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(TabHostTransparency())
    }
}

/// Takes the proposed height so intrinsic content cannot push the header out
/// of a compact sheet. Measuring only here does not feed back into detents.
/// The system tab bar supplies the bottom edge: transparent glass over the
/// menu on iOS 26+, and a solid bar with the page laid out above it earlier.
/// Another inset or clip would leave a margin the system did not ask for.
private struct WorkspacePanelViewport<Content: View>: View {
    let content: Content

    var body: some View {
        GeometryReader { geometry in
            content
                .frame(
                    width: geometry.size.width,
                    height: geometry.size.height,
                    alignment: .top)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("workspaceMenuViewport")
        }
        .modifier(SystemTabBarContentEdge())
    }
}

/// iOS 26+ lays tab content edge to edge under the transparent system bar.
/// Earlier systems keep the page in the safe area, above their solid bar.
private struct SystemTabBarContentEdge: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.ignoresSafeArea(edges: .bottom)
        } else {
            content
        }
    }
}

/// On iOS 26+ the system tab bar is transparent. UIKit still gives each tab's
/// hosting view an opaque background, which would sit behind that glass and
/// hide the menu. Clear only those hosting backgrounds, and leave the bar
/// itself to the system. Earlier systems keep the solid bar and the views
/// behind it.
private struct TabHostTransparency: UIViewRepresentable {
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ uiView: Probe, context: Context) {}

    final class Probe: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            isUserInteractionEnabled = false
            guard #available(iOS 26.0, *) else { return }
            var view = superview
            while let current = view {
                current.backgroundColor = .clear
                if current.next is UITabBarController { break }
                view = current.superview
            }
        }
    }
}
