#if DEBUG
import RailCore
import SwiftUI
import UIKit

/// The floating developer ball (DEBUG builds only).
///
/// A window of its own, above every app window and sheet. The window is
/// exactly the ball's frame while collapsed and the panel's frame while
/// expanded, so it never needs to pass touches through: everything outside
/// it reaches the app untouched. Dragging snaps the ball to the nearer side
/// edge; side, height, expanded state and page are kept in UserDefaults.
///
/// Hidden by `RAILMAP_DEVTOOLS=0`, and by default for any UI-test launch
/// (a `RAILMAP_UI_TEST_*` key) unless `RAILMAP_DEVTOOLS=1` says otherwise,
/// so UI tests and screenshots are unaffected.
@MainActor @Observable
final class DevToolsController {
    static let shared = DevToolsController()

    enum Page: String, CaseIterable, Identifiable {
        case performance = "Perf", triggers = "Triggers", state = "State", tools = "Tools", logs = "Logs"
        var id: String { rawValue }
    }

    private enum Keys {
        static let side = "devtools.ball.side"
        static let height = "devtools.ball.height"
        static let expanded = "devtools.expanded"
        static let page = "devtools.page"
    }

    static let ballSize: CGFloat = 46
    private static let margin: CGFloat = 6

    let sampler = DevPerfSampler()
    private(set) var isVisible = false
    private(set) var isExpanded = false
    var page: Page = .performance {
        didSet {
            UserDefaults.standard.set(page.rawValue, forKey: Keys.page)
            updateSampling()
        }
    }
    /// Trigger results shown under the buttons, newest first.
    var lastMessage: String?

    @ObservationIgnored private var window: DevToolsWindow?
    @ObservationIgnored private var sceneObserver: NSObjectProtocol?
    @ObservationIgnored private var installed = false
    /// `devtools action=recorderOn` or the launch flag keeps the recorder on regardless of the panel.
    @ObservationIgnored private var recorderRequested =
        ProcessInfo.processInfo.environment["RAILMAP_SIGNPOST_RECORDER"] == "1"

    static var isEnabledForLaunch: Bool {
        let environment = ProcessInfo.processInfo.environment
        switch environment["RAILMAP_DEVTOOLS"] {
        case "0": return false
        case "1": return true
        default:
            return !environment.keys.contains { $0.hasPrefix("RAILMAP_UI_TEST_") }
                && environment["XCTestConfigurationFilePath"] == nil
        }
    }

    func installIfEnabled() {
        guard !installed else { return }
        installed = true
        page = Page(rawValue: UserDefaults.standard.string(forKey: Keys.page) ?? "") ?? .performance
        isExpanded = UserDefaults.standard.bool(forKey: Keys.expanded)
        sceneObserver = NotificationCenter.default.addObserver(
            forName: UIScene.didActivateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.attachIfNeeded()
                self?.layout(animated: false)
            }
        }
        if Self.isEnabledForLaunch { setVisible(true) }
    }

    func setVisible(_ visible: Bool) {
        isVisible = visible
        if visible { attachIfNeeded() }
        if !visible, let window, window.isKeyWindow {
            window.windowScene?.windows.first(where: { $0 !== window && !$0.isHidden })?.makeKey()
        }
        window?.isHidden = !visible
        updateSampling()
    }

    func setExpanded(_ expanded: Bool) {
        isExpanded = expanded
        UserDefaults.standard.set(expanded, forKey: Keys.expanded)
        layout(animated: true)
        updateSampling()
    }

    /// Sampling (and the signpost recorder) run only while the Performance
    /// page is on screen, or while something else asked for the recorder.
    private func updateSampling() {
        let showing = isVisible && isExpanded
        if showing && page == .performance { sampler.start() } else { sampler.stop() }
        SignpostRecorder.shared.isActive = recorderRequested
            || (showing && (page == .performance || page == .state))
    }

    func setRecorder(_ on: Bool) {
        recorderRequested = on
        updateSampling()
    }

    // MARK: window

    private func attachIfNeeded() {
        guard isVisible else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else { return }
        if let window, window.windowScene === scene { return }
        let window = DevToolsWindow(windowScene: scene)
        window.windowLevel = .alert + 100
        window.backgroundColor = .clear
        let host = DevToolsHostingController(rootView: DevToolsRootView(controller: self))
        host.onSizeChange = { [weak self] in self?.layout(animated: false) }
        host.view.backgroundColor = .clear
        host.sizingOptions = []
        window.rootViewController = host
        window.isHidden = false
        let pan = UIPanGestureRecognizer(target: window, action: #selector(DevToolsWindow.handlePan(_:)))
        window.addGestureRecognizer(pan)
        window.panGesture = pan
        window.onDragEnded = { [weak self] in self?.snap() }
        self.window = window
        layout(animated: false)
    }

    private var bounds: CGRect {
        guard let scene = window?.windowScene else { return .zero }
        let insets = scene.windows.first(where: { $0 !== window })?.safeAreaInsets ?? .zero
        return scene.coordinateSpace.bounds.inset(by: insets)
    }

    private var side: CGFloat {
        UserDefaults.standard.object(forKey: Keys.side) == nil ? 1 : UserDefaults.standard.double(forKey: Keys.side)
    }

    private var height: CGFloat {
        UserDefaults.standard.object(forKey: Keys.height) == nil ? 0.62 : UserDefaults.standard.double(forKey: Keys.height)
    }

    private func ballFrame() -> CGRect {
        let area = bounds
        let size = Self.ballSize
        let x = side < 0.5 ? area.minX + Self.margin : area.maxX - size - Self.margin
        let y = area.minY + (area.height - size) * min(max(height, 0), 1)
        return CGRect(x: x, y: y, width: size, height: size)
    }

    private func panelFrame() -> CGRect {
        let area = bounds.insetBy(dx: Self.margin, dy: Self.margin)
        let width = min(390, area.width)
        let height = min(600, area.height)
        let ball = ballFrame()
        let x = side < 0.5 ? area.minX : area.maxX - width
        let y = min(max(ball.midY - height / 2, area.minY), area.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    func layout(animated: Bool) {
        guard let window else { return }
        let frame = isExpanded ? panelFrame() : ballFrame()
        window.panGesture?.isEnabled = !isExpanded
        window.allowsKey = isExpanded
        if !isExpanded, window.isKeyWindow {
            window.windowScene?.windows.first(where: { $0 !== window && !$0.isHidden })?.makeKey()
        }
        let apply = { window.frame = frame }
        if animated { UIView.animate(withDuration: 0.22, animations: apply) } else { apply() }
    }

    private func snap() {
        guard let window else { return }
        let area = bounds
        let center = window.frame.midY
        UserDefaults.standard.set(window.frame.midX < area.midX ? 0.0 : 1.0, forKey: Keys.side)
        let span = max(area.height - Self.ballSize, 1)
        UserDefaults.standard.set(Double(min(max((center - Self.ballSize / 2 - area.minY) / span, 0), 1)), forKey: Keys.height)
        layout(animated: true)
    }
}

/// Re-places the ball after a rotation. (On Mac Catalyst a window resize keeps
/// the ball's last frame until the next drag or scene activation.)
final class DevToolsHostingController: UIHostingController<DevToolsRootView> {
    var onSizeChange: (() -> Void)?

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in self?.onSizeChange?() }
    }
}

/// The ball's own window. Drags move the whole window (only while collapsed).
final class DevToolsWindow: UIWindow {
    var panGesture: UIPanGestureRecognizer?
    var onDragEnded: (() -> Void)?

    @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self)
        frame = frame.offsetBy(dx: translation.x, dy: translation.y)
        gesture.setTranslation(.zero, in: self)
        if gesture.state == .ended || gesture.state == .cancelled { onDragEnded?() }
    }

    /// Key only while the panel is open (its log filter takes typing);
    /// the collapsed ball never takes focus from the app.
    var allowsKey = false
    override var canBecomeKey: Bool { allowsKey }
}
#endif
