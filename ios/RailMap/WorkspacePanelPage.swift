import SwiftUI
import UIKit

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
/// The viewport still draws under that glass. Only scroll content receives
/// the measured obstruction, so its final row can move clear of the bar.
private struct WorkspacePanelViewport<Content: View>: View {
    let content: Content
    @Environment(PanelMorph.self) private var morph: PanelMorph?
    @State private var tabBarOcclusion: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            // Compact shows only the header, while the mounted viewport keeps
            // its scroll position. Expanded content also needs usable space
            // above the full measured tab-bar clearance.
            let clearance = SystemTabBarScrollClearance(occlusion: tabBarOcclusion)
            let showsContent = morph?.stage != .compact
                && geometry.size.height - clearance.bottomMargin > 1
            content
                .frame(
                    width: geometry.size.width,
                    height: geometry.size.height,
                    alignment: .top)
                .modifier(clearance)
                // Keep the content mounted, including its scroll position.
                // Compact leaves this viewport under the system tab bar.
                .allowsHitTesting(showsContent)
                .disabled(morph?.stage == .compact)
                .accessibilityHidden(!showsContent)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("workspaceMenuViewport")
                .modifier(TabClearanceDiagnostic(occlusion: tabBarOcclusion))
                .background {
                    if #available(iOS 26.0, *) {
                        SystemTabBarOcclusionReader { value in
                            if abs(value - tabBarOcclusion) > 0.5 { tabBarOcclusion = value }
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                }
        }
        .modifier(SystemTabBarContentEdge())
    }
}

/// Content margins change the scrollable extent, not the viewport or the
/// header. Older solid tab bars already provide their own safe-area edge.
private struct SystemTabBarScrollClearance: ViewModifier {
    let occlusion: CGFloat

    var bottomMargin: CGFloat {
        if #available(iOS 26.0, *) { return occlusion + 13 }
        return 0
    }

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            // One extra point preserves the required 12-point gap when the
            // system bar and scroll-content edges land on fractional points.
            content.contentMargins(.bottom, bottomMargin, for: .scrollContent)
        } else {
            content
        }
    }
}

/// Measures the public system tab bar in the viewport's coordinate space.
/// No detent depends on this value; only descendant scroll content reads it.
private struct SystemTabBarOcclusionReader: UIViewControllerRepresentable {
    let report: @MainActor (CGFloat) -> Void

    func makeUIViewController(context: Context) -> Probe { Probe(report: report) }

    func updateUIViewController(_ controller: Probe, context: Context) {
        controller.report = report
        controller.requestMeasurement()
    }

    @MainActor
    final class Probe: UIViewController {
        var report: @MainActor (CGFloat) -> Void
        private var measurementScheduled = false
        private var lastReported: CGFloat?

        init(report: @escaping @MainActor (CGFloat) -> Void) {
            self.report = report
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { nil }

        override func loadView() {
            let measurementView = MeasurementView()
            measurementView.requestMeasurement = { [weak self] in self?.requestMeasurement() }
            view = measurementView
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
            view.isAccessibilityElement = false
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            requestMeasurement()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            requestMeasurement()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            requestMeasurement()
        }

        override func viewSafeAreaInsetsDidChange() {
            super.viewSafeAreaInsetsDidChange()
            requestMeasurement()
        }

        private final class MeasurementView: UIView {
            var requestMeasurement: (() -> Void)?
            override func didMoveToWindow() {
                super.didMoveToWindow()
                requestMeasurement?()
            }
            override func layoutSubviews() {
                super.layoutSubviews()
                requestMeasurement?()
            }
        }

        func requestMeasurement() {
            guard !measurementScheduled else { return }
            measurementScheduled = true
            // Read after UIKit finishes this layout pass. The weak capture
            // leaves no pending callback retaining a removed tab page.
            Task { @MainActor [weak self] in
                await Task.yield()
                guard let self else { return }
                self.measurementScheduled = false
                self.measure()
            }
        }

        private func measure() {
            guard let window = view.window, view.bounds.height > 0 else { return }
            guard let tabBar = tabBarController?.tabBar, tabBar.window === window else { return }
            let barFrame = view.convert(tabBar.bounds, from: tabBar)
            #if DEBUG
            if ProcessInfo.processInfo.environment["RAILMAP_UI_TEST_TAB_BAR_PROBE"] == "1" {
                let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("tab-bar-probe.txt")
                let detail = "viewport=\(view.bounds) windowRect=\(view.convert(view.bounds, to: window)) controller=\(String(describing: tabBarController)) bar=\(barFrame)\n"
                try? detail.write(to: url, atomically: true, encoding: .utf8)
            }
            #endif
            let overlapsHorizontally = barFrame.maxX > view.bounds.minX
                && barFrame.minX < view.bounds.maxX
            let occlusion = tabBar.isHidden || !overlapsHorizontally ? 0
                : min(view.bounds.height, max(0, view.bounds.maxY - barFrame.minY))
            guard lastReported.map({ abs($0 - occlusion) > 0.5 }) ?? true else { return }
            lastReported = occlusion
            report(occlusion)
        }
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

private struct TabClearanceDiagnostic: ViewModifier {
    let occlusion: CGFloat
    @ViewBuilder func body(content: Content) -> some View {
        #if DEBUG
        if ProcessInfo.processInfo.environment["RAILMAP_UI_TEST_TAB_BAR_PROBE"] == "1" {
            content.accessibilityValue(Text(verbatim: "tabBarOcclusion:\(occlusion)"))
        } else { content }
        #else
        content
        #endif
    }
}
