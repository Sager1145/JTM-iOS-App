import SwiftUI
import UIKit

/// When the app may ask for its next presentation.
///
/// Every alert, confirmation and sheet the workspace puts over itself is
/// presented by ONE controller — the resident sheet's, see
/// `RailWorkspaceView.withPresentations` — and a controller that is already
/// presenting cannot present again. UIKit does not queue the second request:
/// it drops it, writes *"Attempt to present … which is already presenting"* to
/// the console, and the surface the reader asked for never appears. Nothing
/// about that failure is visible in the app. It is a tap that did nothing.
///
/// Two view files had grown the same private helper for this, and both waited
/// a fixed 350 ms — long enough for the menu whose callback they run inside,
/// but a guess about the alert underneath it. How long a dismissal takes is
/// not ours to know: an alert on iOS 26 animates out over the best part of a
/// second, and a duration measured on this simulator is not a promise about a
/// device or about the next release. So the wait is on the CONDITION as well —
/// UIKit is asked whether anything is still on screen or mid-transition, and
/// the action is published the moment nothing is.
@MainActor @Observable
final class PresentationHost {
    /// The delay every menu, context-menu and alert action callback needs
    /// before it may publish state that starts a presentation: they all run
    /// while UIKit is still tearing their own controller down.
    private let teardown = Duration.milliseconds(350)

    /// The one request still waiting for the host. Only one surface can take
    /// the slot, so a newer request replaces an older one the reader has
    /// already moved past.
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private weak var window: UIWindow?

    var anchor: some View { Anchor(host: self).frame(width: 0, height: 0) }

    func cancel() {
        pending?.cancel()
        pending = nil
    }

    func attach(to window: UIWindow?) {
        self.window = window
        if window == nil { cancel() }
    }

    /// Publishes state that will start a presentation, once the controller
    /// that would present it is free to.
    ///
    /// Only presentation state belongs in `action`. Work the reader has
    /// confirmed — a delete, a restore — runs at the call site straight away:
    /// a newer request cancels this one, and confirmed work must never be
    /// cancelled by a later tap.
    ///
    /// There is no timeout. Publishing while an alert still holds the slot is
    /// the dropped presentation this type exists to end; the request waits
    /// until that alert leaves, however long the reader keeps it open.
    func afterTeardown(_ action: @escaping @MainActor () -> Void) {
        pending?.cancel()
        pending = Task { @MainActor in
            do {
                try await Task.sleep(for: teardown)
                while !isIdle { try await Task.sleep(for: .milliseconds(16)) }
            } catch {
                return
            }
            pending = nil
            action()
        }
    }

    /// Whether the host can present right now.
    ///
    /// An alert — `UIAlertController`, which is what SwiftUI's `.alert` and
    /// `.confirmationDialog` both become — is the one thing that takes the
    /// slot the workspace needs and then leaves on its own. A sheet does not
    /// count: the sheets here are driven by state SwiftUI swaps for itself,
    /// and waiting for one to close would hold the next surface back for as
    /// long as the reader keeps it open.
    var isIdle: Bool {
        guard window != nil, let top = topmost else { return false }
        if top.isBeingPresented || top.isBeingDismissed { return false }
        return !(top is UIAlertController)
    }

    private var topmost: UIViewController? {
        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }

    private struct Anchor: UIViewRepresentable {
        let host: PresentationHost
        func makeUIView(context: Context) -> WindowAnchor {
            let view = WindowAnchor()
            view.host = host
            view.isUserInteractionEnabled = false
            return view
        }
        func updateUIView(_ view: WindowAnchor, context: Context) { view.host = host }
    }

    private final class WindowAnchor: UIView {
        weak var host: PresentationHost?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            host?.attach(to: window)
        }
    }
}
