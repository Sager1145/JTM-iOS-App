"""Exercise the production ride station renderer in a macOS bitmap context."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / "ios/RailMap/RailMapAnnotations.swift").read_text()
start = source.index("final class RideStationOverlay: NSObject, MKOverlay")
end = source.index("/// The NAME a marker won", start)
production = source[start:end]
view = (root / "ios/RailMap/RailMapView.swift").read_text()
start = view.index("            private func installRideStationOverlays(")
end = view.index("            /// The marker records", start)
# Replace only the map boundary with a capture double; ordering and reuse logic
# execute directly from the production helper.
installation = view[start:end].replace("private func", "func", 1).replace(
    "on mapView: MKMapView", "on mapView: TestMapView", 1)

# Only the annotation's inputs are doubled; the overlay and drawing code are
# extracted unchanged so paint-order, opacity and sizing regressions fail here.
doubles = r'''
typealias UIColor = NSColor
// macOS compatibility double. Checks use zero-duration updates; no clock fires.
final class CADisplayLink: NSObject {
    let timestamp: TimeInterval = 0
    init(target: AnyObject, selector: Selector) { super.init() }
    func add(to runLoop: RunLoop, forMode mode: RunLoop.Mode) {}
    func invalidate() {}
}
enum RailMotion {
    static func mapHighlightProgress(_ fraction: Double) -> CGFloat { CGFloat(fraction) }
}
final class RideStationAnnotation: NSObject, MKAnnotation {
    struct Core { let radius: CGFloat; let color: UIColor }
    let coordinate = CLLocationCoordinate2D(latitude: 35, longitude: 139)
    let fill: UIColor = .red
    let stroke: UIColor = .white
    let alpha: CGFloat
    let rideID: String
    let drawsInOverlay: Bool
    let role = "stop"
    let rawName = "station"
    let core: Core? = nil
    init(alpha: CGFloat = 1, rideID: String = "lower", drawsInOverlay: Bool = true) {
        self.alpha = alpha
        self.rideID = rideID
        self.drawsInOverlay = drawsInOverlay
    }
    func drawnRadiusToken(atZoom zoom: Double) -> CGFloat { 12 }
    func drawnLineWidthToken(atZoom zoom: Double) -> CGFloat { 3 }
}
'''

installer_doubles = r'''
final class TestMapView {
    var overlays: [MKOverlay] = []
    func renderer(for overlay: MKOverlay) -> MKOverlayRenderer? { nil }
    func removeOverlay(_ overlay: MKOverlay) {
        overlays.removeAll { $0 === overlay }
    }
}
struct TestReconciliation { let oldOverlays: [MKOverlay] }
struct TestInstaller {
    func reconciliation(on mapView: TestMapView) -> TestReconciliation {
        TestReconciliation(oldOverlays: mapView.overlays)
    }
    func install(_ desired: [MKOverlay], replacing: TestReconciliation,
                 scale: CGFloat, on mapView: TestMapView) {
        mapView.overlays = desired
    }
}
struct TestRide { let id: String }
final class TestCoordinator {
    let overlayInstaller = TestInstaller()
    let detailDuration: TimeInterval = 0
    var selectedTrainID: String? = nil
    var retiringStationOverlays: [ObjectIdentifier: UUID] = [:]
    var rideStationAnnotations: [MKAnnotation] = []
    var rides: [TestRide] = [.init(id: "a"), .init(id: "b")]
'''

installation_checks = r'''
func lineOverlay(_ title: String) -> MKPolyline {
    let points = [CLLocationCoordinate2D(latitude: 35, longitude: 139),
                  CLLocationCoordinate2D(latitude: 35.1, longitude: 139)]
    let overlay = MKPolyline(coordinates: points, count: points.count)
    overlay.title = title
    return overlay
}
func titles(_ map: TestMapView) -> [String] {
    map.overlays.map { ($0.title ?? nil) ?? "" }
}
func checkInstallation() {
    let coordinator = TestCoordinator()
    let map = TestMapView()
    let network = lineOverlay("network|base")
    let a = lineOverlay("ride|a")
    let aCrossDay = lineOverlay("ride-xday|a")
    let b = lineOverlay("ride|b")
    let playback = lineOverlay("playback-trail")
    let dotA = RideStationAnnotation(rideID: "a")
    let dotB = RideStationAnnotation(rideID: "b")
    coordinator.rideStationAnnotations = [dotA, dotB]
    // The formerly selected a core is last. Deselection must restore deck order.
    map.overlays = [network, b, a, aCrossDay, playback]
    coordinator.installRideStationOverlays(on: map, scale: 1)
    let expected = ["network|base", "ride|a", "ride-xday|a", "ride-stations|a",
                    "ride|b", "ride-stations|b", "playback-trail"]
    require(titles(map) == expected,
            "deselection did not restore each ride's solid/cross-day/circle stack")
    let retained = map.overlays.compactMap { $0 as? RideStationOverlay }
    coordinator.installRideStationOverlays(on: map, scale: 0.75)
    let reused = map.overlays.compactMap { $0 as? RideStationOverlay }
    require(zip(retained, reused).allSatisfy { $0 === $1 },
            "unchanged station identities replaced overlays")

    let replacement = RideStationAnnotation(rideID: "a")
    coordinator.rideStationAnnotations = [replacement, dotB]
    coordinator.installRideStationOverlays(on: map, scale: 1)
    let changed = map.overlays.compactMap { $0 as? RideStationOverlay }
    require(changed[1] === retained[1]
                && changed[0].stations.count == 1
                && changed[0].stations.first === replacement
                && changed[1].stations.first === dotB,
            "changed stations must update only their ride's overlay contents")

    // Selection uses annotation paint and removes the obsolete overlay paint.
    coordinator.rideStationAnnotations = [
        RideStationAnnotation(rideID: "a", drawsInOverlay: false),
        RideStationAnnotation(rideID: "b", drawsInOverlay: false),
    ]
    coordinator.selectedTrainID = "a"
    let casing = lineOverlay("ride-casing|a")
    map.overlays = [network, b] + changed + [casing, a, aCrossDay, playback]
    coordinator.installRideStationOverlays(on: map, scale: 1)
    require(!map.overlays.contains { $0 is RideStationOverlay },
            "selection left duplicate station overlay paint installed")
    require(titles(map) == ["network|base", "ride|b", "ride-casing|a",
                           "ride|a", "ride-xday|a", "playback-trail"],
            "removing station overlays lowered the selected casing or cores")

    // The route master can hide line ink while retaining station dots.
    coordinator.selectedTrainID = nil
    coordinator.rideStationAnnotations = [dotA, dotB]
    map.overlays = [network, playback]
    coordinator.installRideStationOverlays(on: map, scale: 1)
    require(titles(map) == ["network|base", "ride-stations|a", "ride-stations|b", "playback-trail"],
            "hidden routes also hid their station dots")
}
'''

checks = r'''
final class Bitmap {
    let context: CGContext
    init() {
        context = CGContext(data: nil, width: 64, height: 64,
            bitsPerComponent: 8, bytesPerRow: 64 * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                | CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.black.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
    }
    func pixel(_ x: Int, _ y: Int) -> [Int] {
        context.flush()
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        let offset = y * context.bytesPerRow + x * 4
        return (0..<4).map { Int(bytes[offset + $0]) }
    }
    func line() {
        context.setFillColor(NSColor.green.cgColor)
        context.fill(CGRect(x: 0, y: 29, width: 64, height: 6))
    }
}
func require(_ condition: Bool, _ message: String) {
    precondition(condition, message)
}
func paint(_ bitmap: Bitmap, alpha: CGFloat = 1,
           scale: CGFloat = 1, zoomScale: CGFloat = 1,
           clippedRect: MKMapRect? = nil) {
    let station = RideStationAnnotation(alpha: alpha)
    let overlay = RideStationOverlay(rideID: "lower", stations: [station])
    let renderer = RideStationOverlayRenderer(overlay: overlay)
    renderer.applyScale(scale, zoom: 14)
    let mapPoint = MKMapPoint(station.coordinate)
    let point = renderer.point(for: mapPoint)
    bitmap.context.saveGState()
    bitmap.context.scaleBy(x: zoomScale, y: zoomScale)
    bitmap.context.translateBy(x: 32 / zoomScale - point.x,
                              y: 32 / zoomScale - point.y)
    renderer.draw(clippedRect ?? MKMapRect(x: mapPoint.x - 64,
        y: mapPoint.y - 64, width: 128, height: 128),
        zoomScale: zoomScale, in: bitmap.context)
    bitmap.context.restoreGState()
}
@main struct Checks {
    @MainActor static func main() {
        checkInstallation()
        let lowerFirst = Bitmap()
        paint(lowerFirst)
        lowerFirst.line()
        require(lowerFirst.pixel(32, 32) == [0, 255, 0, 255],
                "a later upper line must cover the lower circle")
        let upperFirst = Bitmap()
        upperFirst.line()
        paint(upperFirst)
        require(upperFirst.pixel(32, 32) == [255, 0, 0, 255],
                "reversing layer order must expose the circle")
        require(upperFirst.pixel(42, 32) == [255, 255, 255, 255],
                "circle's inward white keyline was lost")
        require(upperFirst.pixel(45, 40) == [0, 0, 0, 255],
                "circle escaped its radius")

        let translucent = Bitmap()
        paint(translucent, alpha: 0.5)
        let centre = translucent.pixel(32, 32)
        let rim = translucent.pixel(42, 32)
        require((126...129).contains(centre[0]) && centre[1] == 0 && centre[2] == 0,
                "circle fill opacity changed")
        require(rim.prefix(3).allSatisfy { (126...129).contains($0) },
                "keyline opacity must composite once with the fill")

        let smaller = Bitmap()
        paint(smaller, scale: 0.5)
        require(smaller.pixel(32, 32) == [255, 0, 0, 255], "scaled fill vanished")
        require(smaller.pixel(42, 32) == [0, 0, 0, 255], "scale did not shrink radius")
        let zoomed = Bitmap()
        paint(zoomed, zoomScale: 2)
        require(zoomed.pixel(42, 32) == upperFirst.pixel(42, 32),
                "MapKit zoomScale changed the screen-point radius or rim")

        let culled = Bitmap()
        paint(culled, clippedRect: MKMapRect(x: 0, y: 0, width: 1, height: 1))
        require(culled.pixel(32, 32) == [0, 0, 0, 255], "off-tile circle was drawn")
        print("PASS: production stack installation, deselection order, selection cleanup, hidden-route dots, overlay reuse/update, circle occlusion, reversed stack, rim, grouped alpha, style scale, MapKit zoom scale and tile culling (zero-duration updates; fade clock not exercised)")
    }
}
'''

with tempfile.TemporaryDirectory(prefix="jtm-ride-station-layering-", dir="/private/tmp") as directory:
    folder = Path(directory)
    swift = folder / "check.swift"
    binary = folder / "check"
    swift.write_text("import AppKit\nimport MapKit\n" + doubles + production
                     + installer_doubles + installation + "\n}\n"
                     + installation_checks + checks)
    subprocess.run([
        "xcrun", "swiftc", "-parse-as-library", "-O", "-module-cache-path",
        str(folder / "modules"), str(swift), "-o", str(binary),
    ], check=True)
    subprocess.run([str(binary)], check=True)
