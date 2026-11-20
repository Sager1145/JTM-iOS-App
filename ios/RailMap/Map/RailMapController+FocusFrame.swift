import MapKit
import RailPresentation
import UIKit

/// The free map area every fit centres its content in: between the docked
/// menu card and the column of map control buttons. The rule itself is
/// `FocusFramePolicy` (RailPresentation, pure and tested); this file only
/// measures the live map and adapts the types.
///
/// Every fit reaches the rule through two properties and nothing else:
/// - ``framingInsets`` — the free area as insets from the map view's edges
///   (what `fitIfNeeded`, the playback chase and the trip-note pick read);
/// - ``fitPadding`` — the same area as the `edgePadding` MapKit needs.
///
/// Nothing here moves the camera. The frames are only read when a fit is
/// requested, so opening or closing a popup inside the docked panel, or the
/// card breathing between its stops, never reframes the map.
extension RailMapController {
    /// The room a framed subject is given, as insets from the map view's
    /// edges. See `FocusFramePolicy` for the rule.
    var framingInsets: UIEdgeInsets {
        Self.edgeInsets(focusFramePolicy.insets)
    }

    /// `framingInsets` as the edge padding for `setVisibleMapRect` and
    /// `mapRectThatFits`.
    ///
    /// Not the same numbers: MapKit fits into an inner area (the view less
    /// its layout margins, which carry the docked menu's width), and measures
    /// padding from there. Handing it `framingInsets` counted the menu twice.
    var fitPadding: UIEdgeInsets {
        fitPadding(for: framingInsets)
    }

    /// Edge padding for a caller with its own top and bottom (the trip-note
    /// pick) and the fit's sides.
    func fitPadding(for insets: UIEdgeInsets) -> UIEdgeInsets {
        let policy = focusFramePolicy
        guard policy.usesFreeArea, let area = fittingSpan else { return insets }
        let sides = policy.mapPadding(fittingArea: area)
        return UIEdgeInsets(top: insets.top, left: sides.left, bottom: insets.bottom, right: sides.right)
    }

    /// The free area in the map view's coordinates.
    var focusFreeRect: CGRect {
        let rect = focusFramePolicy.freeRect
        return CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }

    /// The rule, fed with the frames as they are right now.
    var focusFramePolicy: FocusFramePolicy {
        let fallback = baseFramingInsets
        let bounds = mapView?.bounds ?? .zero
        return FocusFramePolicy(
            mapWidth: bounds.width, mapHeight: bounds.height,
            dockedMenu: dockedMenuSpan(in: bounds),
            controlColumn: controlColumnSpan(in: bounds),
            fallback: FocusFramePolicy.Insets(
                top: fallback.top, left: fallback.left, bottom: fallback.bottom, right: fallback.right))
    }

    /// The docked card's extent: from the map's leading edge to the card's
    /// far edge, on whichever side leading is.
    private func dockedMenuSpan(in bounds: CGRect) -> FocusFramePolicy.Span? {
        guard let edge = dockedMenuEdge, edge > 0, bounds.width > 0 else { return nil }
        let rightToLeft = mapView?.effectiveUserInterfaceLayoutDirection == .rightToLeft
        return rightToLeft
            ? FocusFramePolicy.Span(minX: bounds.width - edge, maxX: bounds.width)
            : FocusFramePolicy.Span(minX: 0, maxX: edge)
    }

    /// The control column's extent, from the frame SwiftUI measured in window
    /// coordinates.
    private func controlColumnSpan(in bounds: CGRect) -> FocusFramePolicy.Span? {
        guard let frame = controlColumnFrame, frame.width > 0,
              let mapView, mapView.window != nil else { return nil }
        let local = mapView.convert(frame, from: nil)
        guard local.minX.isFinite, local.maxX.isFinite, local.intersects(bounds) else { return nil }
        return FocusFramePolicy.Span(minX: local.minX, maxX: local.maxX)
    }

    /// The horizontal extent of the area MapKit fits into, in the map view's
    /// coordinates.
    ///
    /// The area depends on the view's geometry, not on the camera, so there
    /// are two candidates: the view less its layout margins (what MapKit does
    /// on every layout seen so far) and the whole view. The current
    /// `visibleMapRect`'s corners, put back through the map's own conversion,
    /// say which one it is; the answer is kept for as long as the bounds and
    /// margins stay the same, so the playback chase does not measure per
    /// frame. A turned or tilted map, a camera in flight or a world-wide view
    /// gives a measurement that matches neither: it is dropped, nothing is
    /// kept, and the view less its layout margins is used.
    private var fittingSpan: FocusFramePolicy.Span? {
        guard let mapView, mapView.bounds.width > 0, mapView.bounds.height > 0 else { return nil }
        let bounds = mapView.bounds
        let layoutMargins = mapView.layoutMargins
        if let kept = fittingSpanCache, kept.bounds == bounds, kept.margins == layoutMargins {
            return FocusFramePolicy.Span(minX: kept.minX, maxX: kept.maxX)
        }
        let margins = bounds.inset(by: layoutMargins)
        let byMargins = FocusFramePolicy.Span(minX: margins.minX, maxX: margins.maxX)
        let camera = mapView.camera
        let heading = abs(camera.heading.truncatingRemainder(dividingBy: 360))
        guard min(heading, 360 - heading) < 0.5, camera.pitch < 0.5 else { return byMargins }
        let visible = mapView.visibleMapRect
        guard !visible.isNull, !visible.isEmpty else { return byMargins }
        let a = mapView.convert(MKMapPoint(x: visible.minX, y: visible.minY).coordinate, toPointTo: mapView)
        let b = mapView.convert(MKMapPoint(x: visible.maxX, y: visible.maxY).coordinate, toPointTo: mapView)
        let minX = min(a.x, b.x)
        let maxX = max(a.x, b.x)
        guard minX.isFinite, maxX.isFinite else { return byMargins }
        let whole = FocusFramePolicy.Span(minX: bounds.minX, maxX: bounds.maxX)
        for candidate in [byMargins, whole]
        where abs(minX - candidate.minX) <= 2 && abs(maxX - candidate.maxX) <= 2 {
            fittingSpanCache = (bounds, layoutMargins, candidate.minX, candidate.maxX)
            return candidate
        }
        return byMargins
    }

    private static func edgeInsets(_ insets: FocusFramePolicy.Insets) -> UIEdgeInsets {
        UIEdgeInsets(top: insets.top, left: insets.left, bottom: insets.bottom, right: insets.right)
    }

#if DEBUG
    /// Where the last explicit fit's subject is on screen now, in the map
    /// view's coordinates — for the app-control `state`, so the centring can
    /// be checked without looking at the screen.
    var lastFitSubjectViewRect: CGRect? {
        guard let mapView, let rect = lastExplicitFitRect, !rect.isNull else { return nil }
        let a = mapView.convert(MKMapPoint(x: rect.minX, y: rect.minY).coordinate, toPointTo: mapView)
        let b = mapView.convert(MKMapPoint(x: rect.maxX, y: rect.maxY).coordinate, toPointTo: mapView)
        guard a.x.isFinite, a.y.isFinite, b.x.isFinite, b.y.isFinite else { return nil }
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }
#endif
}
