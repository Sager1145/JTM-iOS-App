"""Render production map-detail fades with a deterministic clock on macOS."""
import ast
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
annotation = (root / "ios/RailMap/RailMapAnnotations.swift").read_text()
start = annotation.index("final class RideStationOverlay: NSObject, MKOverlay")
end = annotation.index("/// The NAME a marker won", start)
production = annotation[start:end].replace("CACurrentMediaTime()", "TestClock.now")
production = production.replace("private func advance(", "func advance(")
# Share only the platform doubles and bitmap utilities from the layering check.
# The production renderer itself is extracted independently, unchanged except
# for clock injection and access to its frame callback.
helper = ast.parse((root / "ios/tools/verify-ride-station-layering.py").read_text())
values = {node.targets[0].id: ast.literal_eval(node.value)
          for node in helper.body if isinstance(node, ast.Assign)
          and isinstance(node.targets[0], ast.Name)
          and node.targets[0].id in {"doubles", "checks"}}
doubles = values["doubles"]
motion = (root / "ios/RailMap/RailMotion.swift").read_text()
start = motion.index("    static func mapHighlightProgress(")
end = motion.index("    /// The Reduce Motion stand-in", start)
doubles = doubles[:doubles.index("enum RailMotion {")] + "enum RailMotion {\n" + motion[start:end] + "}\n" + doubles[doubles.index("final class RideStationAnnotation"):]
doubles = doubles.replace(
    "let coordinate = CLLocationCoordinate2D(latitude: 35, longitude: 139)",
    "let coordinate: CLLocationCoordinate2D")
doubles = doubles.replace("drawsInOverlay: Bool = true) {", "drawsInOverlay: Bool = true, longitude: Double = 139) {")
doubles = doubles.replace("self.alpha = alpha", "coordinate = CLLocationCoordinate2D(latitude: 35, longitude: longitude)\n        self.alpha = alpha")
utilities = values["checks"].split("@main struct Checks")[0]
styles = (root / "ios/RailMap/MapOverlayStyles.swift").read_text()
styles = styles.replace("import UIKit", "import AppKit")
styles = styles.replace("CACurrentMediaTime()", "TestClock.now")
styles = styles.replace("private func advanceOpacity(", "func advanceOpacity(")
network = (root / "ios/RailMap/MapNetworkRendering.swift").read_text()
start = network.index("@MainActor\nstruct MapOverlayReconciliation")
end = network.index("#if DEBUG", start)
network = network[start:end].replace("MKMapView", "TestMapView")
platform = r'''
enum RailStyle {
    static let railWidth: CGFloat = 2
    static let networkOpacity: CGFloat = 0.9
    static let withheldOpacity: CGFloat = 0.5
    static func dashPattern(atScale: CGFloat) -> [NSNumber] { [2, 2] }
    static func historyDot(atScale: CGFloat) -> [NSNumber] { [1, 2] }
}
enum MapLabelStyle {
    static func halo(dark: Bool) -> UIColor { .white }
}
@MainActor final class TestMapView {
    let styles: MapOverlayStyles
    var mounted: [MKOverlay] = []
    private var renderers: [ObjectIdentifier: MKOverlayRenderer] = [:]
    init(styles: MapOverlayStyles) { self.styles = styles }
    func overlays(in level: MKOverlayLevel) -> [MKOverlay] { mounted }
    func addOverlays(_ overlays: [MKOverlay], level: MKOverlayLevel) {
        mounted.append(contentsOf: overlays)
        for overlay in overlays {
            let renderer = MKMultiPolylineRenderer(multiPolyline: overlay as! MKMultiPolyline)
            renderers[ObjectIdentifier(overlay)] = renderer
            styles.remember(renderer, forKey: (overlay.title ?? nil)!)
        }
    }
    func removeOverlay(_ overlay: MKOverlay) {
        mounted.removeAll { $0 === overlay }
        renderers.removeValue(forKey: ObjectIdentifier(overlay))
    }
    func removeOverlays(_ overlays: [MKOverlay]) { overlays.forEach(removeOverlay) }
    func exchangeOverlay(_ first: MKOverlay, with second: MKOverlay) {
        mounted.swapAt(mounted.firstIndex { $0 === first }!, mounted.firstIndex { $0 === second }!)
    }
    func renderer(for overlay: MKOverlay) -> MKOverlayRenderer? { renderers[ObjectIdentifier(overlay)] }
}
@MainActor func checkNetworkFades() {
    let styles = MapOverlayStyles()
    let installer = MapOverlayInstaller(styles: styles)
    let map = TestMapView(styles: styles)
    func make(_ key: String) -> MKMultiPolyline {
        let points = [CLLocationCoordinate2D(latitude: 35, longitude: 139),
                      CLLocationCoordinate2D(latitude: 35.1, longitude: 139)]
        let multi = MKMultiPolyline([MKPolyline(coordinates: points, count: points.count)])
        multi.title = key
        styles[key] = .init(color: .red, widthToken: 2, alpha: 0.9)
        return multi
    }
    let base = make("network|red|lod:4")
    let detail = make("network|red|lod:12")
    installer.install([base], replacing: installer.reconciliation(on: map), scale: 1, on: map)
    installer.install([base, detail], replacing: installer.reconciliation(on: map), scale: 1,
                      on: map, detailTransitionDuration: 0.24)
    require(map.renderer(for: base)!.alpha == 0.9, "network arrival faded unchanged rails")
    require(map.renderer(for: detail)!.alpha == 0, "new network tier did not start transparent")
    TestClock.now += 0.12
    styles.advanceOpacity(at: TestClock.now)
    require(map.renderer(for: detail)!.alpha > 0 && map.renderer(for: detail)!.alpha < 0.9,
            "network arrival lacks intermediate opacity")
    TestClock.now += 0.13
    styles.advanceOpacity(at: TestClock.now)
    installer.install([base], replacing: installer.reconciliation(on: map), scale: 1,
                      on: map, detailTransitionDuration: 0.24)
    require(map.mounted.count == 2, "network tier removed before departure finished")
    require(installer.reconciliation(on: map).oldOverlays.count == 1,
            "retiring network tier entered active reconciliation")
    TestClock.now += 0.08
    styles.advanceOpacity(at: TestClock.now)
    let leaving = map.renderer(for: detail)!.alpha
    let returning = make("network|red|lod:12")
    installer.install([base, returning], replacing: installer.reconciliation(on: map), scale: 1,
                      on: map, detailTransitionDuration: 0.24)
    require(map.mounted.count == 2, "network reversal left duplicate outgoing geometry")
    require(map.renderer(for: returning)!.alpha == leaving, "network reversal jumped in opacity")
    TestClock.now += 0.25
    styles.advanceOpacity(at: TestClock.now)
    require(map.mounted.count == 2, "old removal callback removed a returning tier")
    installer.install([base], replacing: installer.reconciliation(on: map), scale: 1,
                      on: map, detailTransitionDuration: 0.16)
    TestClock.now += 0.17
    styles.advanceOpacity(at: TestClock.now)
    require(map.mounted.count == 1 && map.mounted[0] === base,
            "outgoing network tier did not leave after reduced-motion fade")
    require(map.renderer(for: base)!.alpha == 0.9, "network departure faded retained rails")
}
'''
checks = r'''
enum TestClock { static var now: TimeInterval = 100 }
func red(_ renderer: RideStationOverlayRenderer, at station: RideStationAnnotation) -> Int {
    let bitmap = Bitmap()
    let mapPoint = MKMapPoint(station.coordinate)
    let point = renderer.point(for: mapPoint)
    bitmap.context.translateBy(x: 32 - point.x, y: 32 - point.y)
    renderer.draw(MKMapRect(x: mapPoint.x - 64, y: mapPoint.y - 64, width: 128, height: 128),
                  zoomScale: 1, in: bitmap.context)
    return bitmap.pixel(32, 32)[0]
}
@main struct FadeChecks {
    @MainActor static func main() {
        checkNetworkFades()
        let persistent = RideStationAnnotation()
        let incoming = RideStationAnnotation(longitude: 139.01)
        let overlay = RideStationOverlay(rideID: "ride", stations: [persistent])
        let renderer = RideStationOverlayRenderer(overlay: overlay)
        renderer.applyScale(1, zoom: 14)
        require(red(renderer, at: persistent) == 255, "initial stationary dot was not opaque")
        overlay.stations = [persistent, incoming]
        renderer.updateStations(duration: 0.24)
        require(red(renderer, at: persistent) == 255, "adding detail faded a persistent dot")
        require(red(renderer, at: incoming) == 0, "new detail did not start transparent")
        TestClock.now += 0.12
        renderer.advance(at: TestClock.now)
        let middle = red(renderer, at: incoming)
        require(middle > 0 && middle < 255, "arrival lacks intermediate opacity")
        renderer.applyScale(0.75, zoom: 14.1)
        require(red(renderer, at: incoming) == middle, "resizing restarted an active fade")
        TestClock.now += 0.12
        renderer.advance(at: TestClock.now)
        require(red(renderer, at: incoming) == 255, "arrival did not finish")
        overlay.stations = [persistent]
        renderer.updateStations(duration: 0.24)
        require(red(renderer, at: incoming) == 255, "outgoing detail was removed before fading")
        TestClock.now += 0.08
        renderer.advance(at: TestClock.now)
        let departing = red(renderer, at: incoming)
        require(departing > 0 && departing < 255, "departure lacks intermediate opacity")
        overlay.stations = [persistent, incoming]
        renderer.updateStations(duration: 0.24)
        require(red(renderer, at: incoming) == departing, "zoom reversal jumped instead of retargeting")
        TestClock.now += 0.25
        renderer.advance(at: TestClock.now)
        require(red(renderer, at: incoming) == 255, "revived detail did not return to full opacity")
        overlay.stations = [persistent]
        renderer.updateStations(duration: 0.16)
        TestClock.now += 0.17
        renderer.advance(at: TestClock.now)
        require(red(renderer, at: incoming) == 0, "reduced-motion fade did not remove outgoing detail")
        require(red(renderer, at: persistent) == 255, "removal faded retained detail")
        overlay.stations = [persistent, incoming]
        renderer.updateStations(duration: 0)
        require(red(renderer, at: incoming) == 255, "immediate playback updates unexpectedly faded")
        print("Map network and dot fades pass: arrival, departure, retained opacity, resize, reversal, reduced motion, immediate updates")
    }
}
'''
with tempfile.TemporaryDirectory(prefix="jtm-map-detail-fades-", dir="/private/tmp") as directory:
    folder = Path(directory)
    swift = folder / "check.swift"
    binary = folder / "check"
    swift.write_text("import AppKit\nimport MapKit\n" + doubles + production + styles + network + platform + utilities + checks)
    subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-O", "-module-cache-path",
                    str(folder / "modules"), str(swift), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
