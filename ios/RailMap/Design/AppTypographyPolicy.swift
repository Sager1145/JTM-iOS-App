import SwiftUI
import UIKit

/// The app's one text-size ceiling, for every surface.
///
/// `maximumSize` is the single hard-coded cap. Everything else derives from
/// it: the SwiftUI range applied once at the scene root, the UIKit content
/// size category set on every window (which also covers sheets, popovers,
/// full-screen covers, alerts and `UIHostingController`s presented in it),
/// and the clamped `UIFont`s the map's UIKit annotations measure with. There
/// is deliberately no second value anywhere.
///
/// Why `.xLarge`: it is the largest size at which the densest screens still
/// lay out — the resident sheet's header row (title, subtitle and up to four
/// 44 pt actions on a 402 pt iPhone; `BottomChromeMetrics` measures its rows
/// at this size), the History/Upcoming journey rows with date, number and
/// endpoints on one line each, and the Stats ticket's fixed artboard. From
/// `.xxLarge` up, those rows wrap into the next row's space or truncate
/// station names. Every size at or below the cap still follows the reader's
/// setting; `.xSmall` is the system's smallest, so nothing below is limited.
enum AppTypographyPolicy {
    /// THE cap. Change it here and nowhere else.
    static let maximumSize: DynamicTypeSize = .xLarge

    static let supportedSizes: ClosedRange<DynamicTypeSize> = .xSmall ... maximumSize

    /// The same cap, in UIKit's terms.
    static var maximumContentSizeCategory: UIContentSizeCategory {
        UIContentSizeCategory(maximumSize)
    }

    static func preferredFont(forTextStyle style: UIFont.TextStyle) -> UIFont {
        let requested = UIFont.preferredFont(forTextStyle: style)
        let maximum = UIFont.preferredFont(forTextStyle: style,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: maximumContentSizeCategory))
        return requested.withSize(min(maximum.pointSize, requested.pointSize))
    }
}

/// Puts the cap on the hosting window scene, so UIKit text anywhere in it
/// stops at the same size SwiftUI does.
///
/// The scene's trait override is what reaches PRESENTED controllers: a
/// SwiftUI `.sheet`, popover or full-screen cover takes its text size from
/// UIKit traits, not from the `.dynamicTypeSize` set at the root, so without
/// this the resident sheet's journey list grew to accessibility sizes while
/// the root stopped at the cap. Re-applied when the reader changes their
/// setting, so every size at or below the cap still follows it.
struct AppTypographyWindowCap: UIViewRepresentable {
    func makeUIView(context: Context) -> CapView { CapView() }
    func updateUIView(_ view: CapView, context: Context) { view.apply() }

    final class CapView: UIView {
        private var observing = false
        private var applied: UIContentSizeCategory?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
            guard !observing, window != nil else { return }
            observing = true
            // Selector-based: removed automatically with the view.
            NotificationCenter.default.addObserver(
                self, selector: #selector(contentSizeChanged),
                name: UIContentSizeCategory.didChangeNotification, object: nil)
        }

        @objc private func contentSizeChanged() { apply() }

        func apply() {
            guard let window else { return }
            let cap = AppTypographyPolicy.maximumContentSizeCategory
            if window.maximumContentSizeCategory != cap { window.maximumContentSizeCategory = cap }
            guard let scene = window.windowScene else { return }
            let requested = UIApplication.shared.preferredContentSizeCategory
            let capped = requested > cap ? cap : requested
            // Reading an override that was never set asserts in UIKit, so the
            // last value written is remembered rather than read back.
            guard applied != capped else { return }
            applied = capped
            scene.traitOverrides.preferredContentSizeCategory = capped
        }
    }
}
