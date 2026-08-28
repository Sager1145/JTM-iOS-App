import MapKit
import UIKit

/// Every stroke on the map, and the renderer MapKit built for it.
///
/// ## Why this is a type rather than two dictionaries on the coordinator
///
/// Four unrelated things write strokes to this map — the network rebuild, a
/// recorded ride's rebuild, the basemap veil, and the playback trail — and all
/// four have to agree about one thing: a style is stored as a full-scale TOKEN,
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
        /// dash and stroke down together.
        var dashed = false
    }

    private var styles: [String: Style] = [:]

    /// The renderers MapKit built, so a rescale can reach them. MapKit caches
    /// what `rendererFor` returns and never asks again, so a width written into
    /// a style after the fact would never be drawn.
    private var renderers: [String: MKOverlayRenderer] = [:]

    /// The style an overlay's title names, by that title.
    subscript(key: String) -> Style? {
        get { styles[key] }
        set { styles[key] = newValue }
    }

    /// Everything, forgotten — the whole-map teardown a rebuild begins with.
    func removeAll() {
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
        }
    }

    /// Forget one renderer while KEEPING its style — what a replacement stroke
    /// under the same key needs, since the replacement has already written its
    /// own style entry by the time the old overlay comes off.
    func forgetRenderer(forKey key: String) {
        renderers.removeValue(forKey: key)
    }

    func forgetStyle(forKey key: String) {
        styles.removeValue(forKey: key)
    }

    /// Keep the renderer MapKit just built, so ``rescale(to:)`` can reach it.
    func remember(_ renderer: MKOverlayRenderer, forKey key: String) {
        guard !key.isEmpty else { return }
        renderers[key] = renderer
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
    func rescale(to scale: CGFloat) {
        for (key, renderer) in renderers {
            let style = styles[key]
            let width = Self.drawnWidth(style, atScale: scale)
            let dash = style?.dashed == true ? RailStyle.dashPattern(atScale: scale) : nil
            if let polyline = renderer as? MKPolylineRenderer {
                polyline.lineWidth = width
                polyline.lineDashPattern = dash
            } else if let multi = renderer as? MKMultiPolylineRenderer {
                multi.lineWidth = width
                multi.lineDashPattern = dash
            } else {
                continue
            }
            renderer.setNeedsDisplay()
        }
    }
}
