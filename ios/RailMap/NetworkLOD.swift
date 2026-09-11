import MapKit
import RailCore
import RailPresentation

/// Native railway selection at the current MapKit scale.
///
/// High-speed backbones remain visible at overview. Other lines wait for
/// their complete-group length/rank tier; station density is gated separately.
/// Viewport culling and a post-simplification vertex budget bound rendering.
/// RailCore.Visibility retains the independent, fixture-tested Web contract.
enum NetworkLOD {

    /// Roughly what the renderer can submit without the frame budget showing.
    ///
    /// Derived from measurement, not taste: Japan at a national view drew
    /// 12,433 vertices in 98 ms, and the city view's 89,785 in 229 ms was
    /// already visible as a hitch when crossing a zoom bucket. 40,000 sits
    /// between them with room to spare.
    ///
    /// "Room to spare" is thinner since 2026-08-24, and deliberately so.
    /// Bringing decimation onto the web app's geometry contract — see
    /// `RailStyle.simplifyTolerance`, which was eight times too loose — raised
    /// the worst build measured anywhere in the five packages from 25,000
    /// drawn vertices to 38,698 (largest iPad, app zoom 8, over the Kansai and
    /// Chugoku density). That is still under the budget, so nothing is dropped
    /// today, but the backstop is now within a few per cent of binding, and if
    /// a denser package pushes it past, this is where it shows: branches shed
    /// first, ``fitToBudget`` reports the threshold it stopped at, and the
    /// diagnostics panel shows a threshold below the zoom. The measured lever
    /// if that happens is clipping each interval to the build rect before
    /// decimating rather than raising the number — it takes a city view from
    /// 22,185 vertices to 2,460, though it does little at the wide zooms where
    /// the worst case actually sits.
    static let vertexBudget = 40_000

    /// How far outside the visible rect to build, as a fraction of its size.
    ///
    /// Half a screen in each direction. Small enough that a nationwide view
    /// does not build the whole country twice over; large enough that ordinary
    /// panning stays inside what was already built, which is what keeps the
    /// pan gesture free of work.
    static let padding = 0.5

    /// One native policy supplies both lazy region loading and line rendering.
    /// High-speed backbones remain at overview; ordinary railways use the
    /// complete-group length/rank ladder. RailCore's web parity is unchanged.
    static func minZoomMapLibre(
        portedMinZoom: Int,
        rank: Int?,
        visibilityLengthKm: Double,
        region: String? = nil,
        operator: String? = nil,
        name: String? = nil
    ) -> Int {
        NetworkVisibilityPolicy.lineMinZoomMapLibre(
            portedMinZoom: portedMinZoom, rank: rank,
            visibilityLengthKm: visibilityLengthKm, region: region,
            operator: `operator`, name: name)
    }

    static func minZoom(
        portedMinZoom: Int,
        rank: Int?,
        visibilityLengthKm: Double,
        region: String? = nil,
        operator: String? = nil,
        name: String? = nil
    ) -> Double {
        RailStyle.zoom(fromMapLibre: Double(minZoomMapLibre(
            portedMinZoom: portedMinZoom, rank: rank,
            visibilityLengthKm: visibilityLengthKm, region: region,
            operator: `operator`, name: name)))
    }

    /// Stations wait for both their own density floor and their line. Keeping
    /// the station floor prevents globe-level backbone lines acquiring dots.
    static func stationMinZoomMapLibre(portedMinZoom: Int, lineMinZoomMapLibre: Int) -> Int {
        max(portedMinZoom, lineMinZoomMapLibre)
    }

    /// The same threshold in **this app's** zoom. The MapLibre one above is
    /// what the label election runs on — it compares platforms against each
    /// other, where the convention cancels — and this is what the map compares
    /// against the camera.
    static func stationMinZoom(portedMinZoom: Int, lineMinZoomMapLibre: Int) -> Double {
        RailStyle.zoom(
            fromMapLibre: Double(
                stationMinZoomMapLibre(
                    portedMinZoom: portedMinZoom, lineMinZoomMapLibre: lineMinZoomMapLibre)))
    }

    /// The rect to build for: the visible one, grown by ``padding``.
    static func buildRect(for visible: MKMapRect) -> MKMapRect {
        visible.insetBy(
            dx: -visible.size.width * padding,
            dy: -visible.size.height * padding
        )
    }

    /// Chooses which lines are eligible: near enough to be seen, and
    /// important enough for this zoom.
    ///
    /// The vertex budget is deliberately *not* applied here. What a line costs
    /// to draw is its decimated vertex count, which is not known until it has
    /// been decimated — and it varies by more than an order of magnitude with
    /// zoom. Budgeting on the raw count instead cut a national view of Japan
    /// from 262 lines to 7, because it was weighing 394,285 stored vertices
    /// against a budget meant for the ~12,000 actually drawn.
    static func select<Line: LODLine>(
        from lines: [Line],
        zoom: Double,
        buildRect: MKMapRect
    ) -> (lines: [Line], culledOffScreen: Int) {
        // Off-screen first: it is a cheap test and it shrinks everything after.
        let onScreen = lines.filter { $0.mapRect.intersects(buildRect) }
        return (onScreen.filter { $0.lodMinZoom <= zoom }, lines.count - onScreen.count)
    }

    /// Applies the vertex budget to what the decimation actually produced.
    ///
    /// Least important first, where importance is the threshold a line had to
    /// clear to be drawn at all — so a budget squeeze sheds branches and keeps
    /// trunks, which is the same ordering the zoom rule uses. Ties are broken
    /// by the cheaper line surviving, because at that point the only question
    /// left is how much map fits in the budget.
    ///
    /// Returns the kept builds and the threshold that was effectively in force,
    /// which is worth reporting: when it is below the zoom, the map is showing
    /// less than the zoom alone would allow, and that should be visible rather
    /// than silent.
    static func fitToBudget<Build: LODBuild>(
        _ builds: [Build],
        zoom: Double
    ) -> (kept: [Build], threshold: Double) {
        let total = builds.reduce(0) { $0 + $1.drawnVertexCount }
        guard total > vertexBudget else { return (builds, zoom) }

        let ordered = builds.sorted {
            $0.line.lodMinZoom == $1.line.lodMinZoom
                ? $0.drawnVertexCount < $1.drawnVertexCount
                : $0.line.lodMinZoom < $1.line.lodMinZoom
        }

        var kept: [Build] = []
        var spent = 0
        var threshold = zoom
        for build in ordered {
            let next = spent + build.drawnVertexCount
            if next > vertexBudget { break }
            spent = next
            kept.append(build)
            threshold = build.line.lodMinZoom
        }
        return (kept, threshold)
    }
}

/// What ``NetworkLOD`` needs to know about a line. A protocol so the policy can
/// be reasoned about — and tested — without the whole rendering stack.
protocol LODLine {
    var mapRect: MKMapRect { get }
    var lodMinZoom: Double { get }
}

/// One line after decimation: what it will actually cost to draw.
protocol LODBuild {
    associatedtype Line: LODLine
    var line: Line { get }
    var drawnVertexCount: Int { get }
}
