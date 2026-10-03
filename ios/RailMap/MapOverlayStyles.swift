import MapKit
import UIKit

/// Every stroke on the map, and the renderer MapKit built for it.
///
/// ## Why this is a type rather than two dictionaries on the coordinator
///
/// Three unrelated things write strokes to this map — the network rebuild, a
/// recorded ride's rebuild, and the playback trail — and all
/// three have to agree about one thing: a style is stored as a full-scale TOKEN,
/// and ``drawnWidth(_:atScale:)`` is the only place that token becomes points.
/// That is a contract between the writers, not a detail of any one of them, and
/// it was previously held by two `private var`s in the middle of a 2,600-line
/// coordinator where nothing named it.
///
/// Making it a type is also what lets the playback trail move out of that
/// coordinator: playback registers strokes and forgets them again on every
/// restart, so it needs this registry — and passing one object is a dependency
/// that can be stated, where reaching into two of a sibling's stored properties
/// is not.
@MainActor
final class MapOverlayStyles {

    /// What one overlay is drawn with — a colour, an opacity, and a weight
    /// expressed as its FULL-SCALE token rather than as points on screen.
    ///
    /// Storing the token is the whole of the weight contract on this side:
    /// nothing here may hold a width that has already had a ramp applied to it,
    /// because then a rescale would have to know which factor to divide out.
    /// ``drawnWidth(_:atScale:)`` is the only place a token becomes points.
    struct Style {
        var color: UIColor
        var widthToken: CGFloat
        var alpha: CGFloat
        /// Dashed strokes carry the pair in LINE WIDTHS, so it is derived from
        /// the token and needs no ramp of its own — the same factor carries
        /// dash and stroke down together. Cross-day rides and withheld
        /// casings. Not the historical network mark.
        var dashed = false
        /// Historical and relocated-old network strokes. A different on/off
        /// from ``dashed`` (`RailStyle.historyDot`, not `dashPattern`).
        var historical = false
    }

    private var styles: [String: Style] = [:]

    /// The renderers MapKit built, so a rescale can reach them. MapKit caches
    /// what `rendererFor` returns and never asks again, so a width written into
    /// a style after the fact would never be drawn.
    private var renderers: [String: MKOverlayRenderer] = [:]

    private struct OpacityTransition {
        var start: CGFloat
        var target: CGFloat
        var startedAt: CFTimeInterval
        var duration: TimeInterval
        var completion: (() -> Void)?

        func alpha(at time: CFTimeInterval) -> CGFloat {
            let progress = RailMotion.mapHighlightProgress((time - startedAt) / duration)
            return start + (target - start) * progress
        }
    }

    private var opacityTransitions: [String: OpacityTransition] = [:]
    private var displayLink: CADisplayLink?

    @MainActor
    private final class OpacityClock: NSObject {
        weak var owner: MapOverlayStyles?
        init(owner: MapOverlayStyles) { self.owner = owner }
        @objc func tick(_ link: CADisplayLink) {
            guard let owner else { link.invalidate(); return }
            owner.advanceOpacity(at: CACurrentMediaTime())
        }
    }

    private func stopClockIfIdle() {
        guard opacityTransitions.isEmpty else { return }
        displayLink?.invalidate()
        displayLink = nil
    }

    private func advanceOpacity(at time: CFTimeInterval) {
        var completions: [() -> Void] = []
        for (key, transition) in opacityTransitions {
            let finished = time - transition.startedAt >= transition.duration
            renderers[key]?.alpha = finished ? transition.target : transition.alpha(at: time)
            if finished {
                opacityTransitions.removeValue(forKey: key)
                if let completion = transition.completion { completions.append(completion) }
            }
        }
        stopClockIfIdle()
        for completion in completions { completion() }
    }

    /// Animate one stored opacity. Retargeting cancels its previous completion
    /// and starts at the currently presented alpha. Missing renderers can join
    /// later via `remember`, which is how a newly installed casing fades in.
    func animateOpacity(
        forKey key: String, duration: TimeInterval, fromAlpha: CGFloat? = nil,
        completion: (() -> Void)? = nil
    ) {
        guard let style = styles[key] else { return }
        let now = CACurrentMediaTime()
        let start = renderers[key]?.alpha
            ?? opacityTransitions[key]?.alpha(at: now) ?? fromAlpha ?? style.alpha
        opacityTransitions.removeValue(forKey: key)
        guard duration > 0, start != style.alpha else {
            renderers[key]?.alpha = style.alpha
            stopClockIfIdle()
            completion?()
            return
        }
        renderers[key]?.alpha = start
        opacityTransitions[key] = OpacityTransition(
            start: start, target: style.alpha, startedAt: now,
            duration: duration, completion: completion)
        if displayLink == nil {
            let link = CADisplayLink(target: OpacityClock(owner: self), selector: #selector(OpacityClock.tick(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }

    /// The style an overlay's title names, by that title.
    subscript(key: String) -> Style? {
        get { styles[key] }
        set { styles[key] = newValue }
    }

    /// Everything, forgotten — the whole-map teardown a rebuild begins with.
    func removeAll() {
        opacityTransitions.removeAll(keepingCapacity: true)
        stopClockIfIdle()
        styles.removeAll(keepingCapacity: true)
        renderers.removeAll(keepingCapacity: true)
    }

    /// Forget the style and the renderer of every overlay being taken off the
    /// map. Overlays with no title carry no entry and are skipped.
    func forget(_ overlays: [MKOverlay]) {
        for overlay in overlays {
            guard let key = overlay.title ?? nil else { continue }
            styles.removeValue(forKey: key)
            renderers.removeValue(forKey: key)
            opacityTransitions.removeValue(forKey: key)
        }
        stopClockIfIdle()
    }

    /// Forget one renderer while KEEPING its style — what a replacement stroke
    /// under the same key needs, since the replacement has already written its
    /// own style entry by the time the old overlay comes off.
    func forgetRenderer(forKey key: String) {
        renderers.removeValue(forKey: key)
        // A geometry replacement keeps this key and its presentation fade.
        // An exit callback belongs to the removed overlay, so discard it.
        if var transition = opacityTransitions[key] {
            transition.completion = nil
            opacityTransitions[key] = transition
        }
    }

    func forgetStyle(forKey key: String) {
        styles.removeValue(forKey: key)
        opacityTransitions.removeValue(forKey: key)
        stopClockIfIdle()
    }

    func presentedAlpha(forKey key: String) -> CGFloat? {
        renderers[key]?.alpha ?? opacityTransitions[key]?.alpha(at: CACurrentMediaTime())
            ?? styles[key]?.alpha
    }

    /// Give an exiting batch its own key so a returning tier can mount while
    /// the old renderer finishes its fade.
    func rekey(from oldKey: String, to newKey: String) {
        styles[newKey] = styles.removeValue(forKey: oldKey)
        renderers[newKey] = renderers.removeValue(forKey: oldKey)
        opacityTransitions[newKey] = opacityTransitions.removeValue(forKey: oldKey)
    }

    /// Keep the renderer MapKit just built, so ``rescale(to:)`` can reach it.
    func remember(_ renderer: MKOverlayRenderer, forKey key: String) {
        guard !key.isEmpty else { return }
        renderers[key] = renderer
        if let style = styles[key] {
            // Keep style opacity separate from colour so a fade changes only
            // compositor alpha, never stroke geometry or per-frame paint.
            if let polyline = renderer as? MKPolylineRenderer { polyline.strokeColor = style.color }
            if let multi = renderer as? MKMultiPolylineRenderer { multi.strokeColor = style.color }
            renderer.alpha = opacityTransitions[key]?.alpha(at: CACurrentMediaTime()) ?? style.alpha
        }
    }

    /// Cross-day dash and the historical dot are different patterns. A style
    /// that sets neither is solid.
    static func dashPattern(_ style: Style?, atScale scale: CGFloat) -> [NSNumber]? {
        if style?.dashed == true { return RailStyle.dashPattern(atScale: scale) }
        if style?.historical == true { return RailStyle.historyDot(atScale: scale) }
        return nil
    }

    /// The one place a stored token becomes points on screen.
    static func drawnWidth(_ style: Style?, atScale scale: CGFloat) -> CGFloat {
        (style?.widthToken ?? RailStyle.railWidth) * scale
    }

    /// Re-applies the shared factor to every stroke already on screen.
    ///
    /// Measured at **0 ms for 323 renderers**: writing a width and a dash
    /// pattern and asking each to redraw only marks them dirty. The cost in a
    /// rescale was never here — see `RailMapView.Surface.Coordinator`'s
    /// `displayedAnnotationViews`, which is about the station marks.
    func rescale(to scale: CGFloat, alphaTransitionDuration: TimeInterval? = nil) {
        for (key, renderer) in renderers {
            let style = styles[key]
            let width = Self.drawnWidth(style, atScale: scale)
            let dash = Self.dashPattern(style, atScale: scale)
            let color = style?.color ?? .systemBlue
            let targetAlpha = style?.alpha ?? 1
            if let duration = alphaTransitionDuration {
                if duration == 0 || opacityTransitions[key]?.target != targetAlpha {
                    animateOpacity(forKey: key, duration: duration)
                }
            } else if let transition = opacityTransitions[key] {
                if transition.target != targetAlpha {
                    // A new nonanimated write cancels any old destination.
                    opacityTransitions.removeValue(forKey: key)
                    renderer.alpha = targetAlpha
                }
            } else {
                renderer.alpha = targetAlpha
            }
            if let polyline = renderer as? MKPolylineRenderer {
                guard polyline.strokeColor != color || polyline.lineWidth != width
                    || polyline.lineDashPattern != dash else { continue }
                polyline.strokeColor = color
                polyline.lineWidth = width
                polyline.lineDashPattern = dash
            } else if let multi = renderer as? MKMultiPolylineRenderer {
                guard multi.strokeColor != color || multi.lineWidth != width
                    || multi.lineDashPattern != dash else { continue }
                multi.strokeColor = color
                multi.lineWidth = width
                multi.lineDashPattern = dash
            } else {
                continue
            }
            renderer.setNeedsDisplay()
        }
        stopClockIfIdle()
    }
}
