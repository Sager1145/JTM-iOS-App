import XCTest
@preconcurrency import MapKit
@preconcurrency import UIKit

/// Opt-in public static-image diagnostic in the UIKit XCTest runner.
/// Synthetic paths are not railway evidence. This does not test native gestures,
/// pitch, refresh throughput, iOS production performance, or fixed attribution.
@MainActor
final class MapSnapshotCompositorFeasibilityTests: XCTestCase {
    private let viewport = CGSize(width: 402, height: 874)
    private let tokyo = CLLocationCoordinate2D(latitude: 35.681236, longitude: 139.767125)

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RAILMAP_SNAPSHOT_COMPOSITOR_PROBE"] == "1",
            "Static snapshot feasibility diagnostic; opt in with RAILMAP_SNAPSHOT_COMPOSITOR_PROBE=1 in the test runner.")
    }

    func testPublicSnapshotEpochAndFiniteCoverageDiagnostic() throws {
        let requests = [
            Request(name: "normal", center: tokyo, overscan: 1),
            Request(name: "overscan2", center: tokyo, overscan: 2),
            Request(name: "newcenter", center: CLLocationCoordinate2D(
                latitude: 35.686236, longitude: 139.777125), overscan: 1),
        ]
        attach([
            "scope": "Three serial UIKit-runner public MapKit requests; fixed public Tokyo coordinates only.",
            "claims": "Static image/projection/coverage evidence only. Synthetic red path is not railway evidence. No native gesture, pitch, refresh-throughput, production-performance, or attribution-parity claim.",
            "host": "UIKit XCTest runner, not the production live map.",
            "requestedScale": 3,
            "timeoutSecondsPerRequest": 30,
            "attribution": "Original PNGs are attached unchanged. Diagnostic bitmap transforms/clipping can move or omit embedded credits; no credit extraction/redrawing or fixed legal UI is implemented.",
        ], named: "snapshot-probe-scope")

        // An error/timeout throws out of this one method. No retry, camera/option
        // permutation, app launch, or further request follows a failed request.
        var epochs: [(Request, MKMapSnapshotter.Snapshot)] = []
        for request in requests {
            let snapshot = try capture(request)
            try verifyCardinalOrientation(snapshot, request: request)
            epochs.append((request, snapshot))
        }

        for (request, snapshot) in epochs where request.name != "newcenter" {
            let states: [State] = request.overscan == 1 ? [
                State(name: "rest", scale: 1, pan: .zero),
                State(name: "pan", scale: 1, pan: CGPoint(x: 80, y: 110)),
            ] : [
                State(name: "rest", scale: 1, pan: .zero),
                State(name: "pan", scale: 1, pan: CGPoint(x: 80, y: 110)),
                State(name: "exhaust-pan", scale: 1, pan: CGPoint(x: 300, y: 500)),
                State(name: "exhaust-zoomout", scale: 0.4, pan: .zero),
            ]
            for state in states {
                let image = diagnostic(snapshot, state: state, request: request)
                try attachPNG(image, named: "synthetic-\(request.name)-\(state.name)")
            }
        }
    }

    private struct Request {
        let name: String
        let center: CLLocationCoordinate2D
        let overscan: CGFloat
    }

    private struct State {
        let name: String
        let scale: CGFloat
        let pan: CGPoint
    }

    /// Callback is requested on .main; the synchronous XCTest waiter pumps the
    /// runner's run loop. The box has no cross-queue writer or reader.
    private final class CompletionBox: @unchecked Sendable {
        var snapshot: MKMapSnapshotter.Snapshot?
        var error: Error?
        var completed = false
    }

    private enum ProbeError: Error {
        case timeout(String)
        case snapshot(String)
        case invalidProjection(String)
        case missingPNG
        case requestedScaleNotHonored
    }

    private func capture(_ request: Request) throws -> MKMapSnapshotter.Snapshot {
        // Same size/mapRect/light-trait/main-queue completion pattern used by
        // StatisticsMapSnapshot. Native iOS scale is requested and recorded.
        let options = MKMapSnapshotter.Options()
        options.size = CGSize(width: viewport.width * request.overscan,
                              height: viewport.height * request.overscan)
        options.traitCollection = UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: .light),
            UITraitCollection(displayScale: 3),
        ])
        options.scale = 3
        let center = MKMapPoint(request.center)
        let width = 6_000 * MKMapPointsPerMeterAtLatitude(request.center.latitude) * Double(request.overscan)
        let height = width * Double(viewport.height / viewport.width)
        options.mapRect = MKMapRect(x: center.x - width / 2, y: center.y - height / 2,
                                    width: width, height: height)
        let configuration = MKStandardMapConfiguration(emphasisStyle: .default)
        configuration.pointOfInterestFilter = .excludingAll
        options.preferredConfiguration = configuration
        let snapshotter = MKMapSnapshotter(options: options)
        let box = CompletionBox()
        let ready = expectation(description: "public-snapshot-\(request.name)")
        let start = ProcessInfo.processInfo.systemUptime
        snapshotter.start(with: .main) { snapshot, error in
            box.snapshot = snapshot
            box.error = error
            box.completed = true
            ready.fulfill()
        }
        let waitResult = XCTWaiter.wait(for: [ready], timeout: 30)
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        var receipt: [String: Any] = [
            "request": request.name,
            "center": [request.center.latitude, request.center.longitude],
            "requestedLogicalSize": [options.size.width, options.size.height],
            "requestedScale": 3,
            "framing": "mapRect; top-down heading0/pitch0",
            "mapRect": [options.mapRect.origin.x, options.mapRect.origin.y,
                        options.mapRect.size.width, options.mapRect.size.height],
            "elapsedSeconds": elapsed,
            "timingMeaning": "One completion/wait latency; no sustainable throughput or production-performance guarantee.",
            "waiterResult": String(describing: waitResult),
        ]
        guard waitResult == .completed, box.completed else {
            snapshotter.cancel()
            receipt["error"] = "30s request deadline; cancelled; no more requests"
            attach(receipt, named: "snapshot-\(request.name)-receipt")
            throw ProbeError.timeout(request.name)
        }
        guard let snapshot = box.snapshot, box.error == nil else {
            receipt["error"] = box.error.map { String(describing: $0) } ?? "Missing snapshot"
            attach(receipt, named: "snapshot-\(request.name)-receipt")
            throw ProbeError.snapshot(request.name)
        }
        let image = snapshot.image
        receipt["returnedLogicalSize"] = [image.size.width, image.size.height]
        receipt["returnedImageScale"] = image.scale
        receipt["pixelSize"] = [image.cgImage?.width ?? 0, image.cgImage?.height ?? 0]
        receipt["cardinalControls"] = cardinalCoordinates(request.center).map { name, coordinate in
            let point = snapshot.point(for: coordinate)
            return ["label": name, "latitude": coordinate.latitude,
                    "longitude": coordinate.longitude, "x": point.x, "y": point.y] as [String: Any]
        }
        attach(receipt, named: "snapshot-\(request.name)-receipt")
        // PNG-encode the untouched snapshot image before any diagnostic rendering.
        try attachPNG(image, named: "original-snapshot-\(request.name)")
        guard image.scale == 3 else {
            XCTFail("Native requested3x snapshot scale was not honored; see untouched image receipt.")
            throw ProbeError.requestedScaleNotHonored
        }
        return snapshot
    }

    private func cardinalCoordinates(_ center: CLLocationCoordinate2D)
        -> [(String, CLLocationCoordinate2D)] {
        [
            ("center", center),
            ("north", CLLocationCoordinate2D(latitude: center.latitude + 0.001, longitude: center.longitude)),
            ("south", CLLocationCoordinate2D(latitude: center.latitude - 0.001, longitude: center.longitude)),
            ("east", CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude + 0.001)),
            ("west", CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude - 0.001)),
        ]
    }

    private func verifyCardinalOrientation(_ snapshot: MKMapSnapshotter.Snapshot, request: Request) throws {
        // Independent geographic controls establish UIKit's image orientation
        // before any compositor transform. No transform fit or self-displacement
        // calculation is used as the reference.
        let points = Dictionary(uniqueKeysWithValues: cardinalCoordinates(request.center).map {
            ($0.0, snapshot.point(for: $0.1))
        })
        let imageBounds = CGRect(origin: .zero, size: snapshot.image.size)
        let valid = points.values.allSatisfy { $0.x.isFinite && $0.y.isFinite && imageBounds.contains($0) }
            && points["north"]!.y < points["center"]!.y
            && points["south"]!.y > points["center"]!.y
            && points["east"]!.x > points["center"]!.x
            && points["west"]!.x < points["center"]!.x
        attach([
            "request": request.name,
            "orientationCheckPassed": valid,
            "reference": "Known geographic cardinal coordinates, compared to untouched snapshot projection before synthetic transform.",
            "expectedImageOrientation": "UIKit: north above center; south below; east right; west left; all finite and inside image.",
        ], named: "cardinal-orientation-\(request.name)")
        guard valid else {
            XCTFail("Public cardinal projections disagree with the expected top-down UIKit image orientation.")
            throw ProbeError.invalidProjection(request.name)
        }
    }

    private func diagnostic(_ snapshot: MKMapSnapshotter.Snapshot, state: State, request: Request) -> UIImage {
        let header: CGFloat = 112
        let imageSize = snapshot.image.size
        let mapViewport = CGRect(x: 0, y: header, width: viewport.width, height: viewport.height)
        let imageRect = CGRect(
            x: viewport.width / 2 + state.pan.x - imageSize.width * state.scale / 2,
            y: viewport.height / 2 + state.pan.y - imageSize.height * state.scale / 2,
            width: imageSize.width * state.scale, height: imageSize.height * state.scale)
        let intersection = imageRect.intersection(CGRect(origin: .zero, size: viewport))
        let coveredArea = intersection.isNull ? 0 : intersection.width * intersection.height
        let coverage = coveredArea / (viewport.width * viewport.height)
        attach([
            "request": request.name, "state": state.name,
            "syntheticScale": state.scale, "syntheticPan": [state.pan.x, state.pan.y],
            "transformedImageRectInViewport": [imageRect.minX, imageRect.minY, imageRect.width, imageRect.height],
            "finiteImageCoverageFraction": coverage,
            "coverageMeaning": "Geometric bitmap-rectangle coverage only; magenta is outside the retained image, not missing-tile detection.",
            "veil": "One stationary viewport rectangle, black alpha0.1, above base image and below synthetic red path.",
            "attribution": "Any embedded credit is transformed/clipped with the entire bitmap. Originals are attached unchanged; no fixed attribution control or parity is claimed.",
        ], named: "synthetic-\(request.name)-\(state.name)-receipt")
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: viewport.width, height: viewport.height + header),
                                       format: format).image { renderer in
            let cg = renderer.cgContext
            UIColor(white: 0.08, alpha: 1).setFill()
            cg.fill(CGRect(x: 0, y: 0, width: viewport.width, height: viewport.height + header))
            let title = "STATIC SNAPSHOT / SYNTHETIC RED PATH ONLY\n\(request.name) / \(state.name): scale \(state.scale), pan \(Int(state.pan.x)),\(Int(state.pan.y))\nFixed viewport veil10%; native requested snapshot3x\nNo railway, gesture, pitch, throughput or parity claim\nMagenta marks outside the retained bitmap\nAny embedded credit moves/crops with that bitmap\nUnmodified originals attached; fixed legal UI unresolved"
            (title as NSString).draw(in: CGRect(x: 8, y: 8, width: 386, height: 96), withAttributes: [
                .font: UIFont.monospacedSystemFont(ofSize: 9, weight: .medium),
                .foregroundColor: UIColor.white,
            ])
            cg.saveGState()
            cg.clip(to: mapViewport)
            cg.setFillColor(UIColor.magenta.cgColor)
            cg.fill(mapViewport)
            func applyOwnedTransform() {
                cg.translateBy(x: viewport.width / 2 + state.pan.x,
                               y: header + viewport.height / 2 + state.pan.y)
                cg.scaleBy(x: state.scale, y: state.scale)
                cg.translateBy(x: -imageSize.width / 2, y: -imageSize.height / 2)
            }
            cg.saveGState()
            applyOwnedTransform()
            snapshot.image.draw(at: .zero)
            cg.restoreGState()
            // This veil stays in viewport coordinates, outside the owned transform.
            cg.setFillColor(UIColor.black.withAlphaComponent(0.1).cgColor)
            cg.fill(mapViewport)
            cg.saveGState()
            applyOwnedTransform()
            let syntheticCoordinates = [
                CLLocationCoordinate2D(latitude: 35.660, longitude: 139.753),
                CLLocationCoordinate2D(latitude: 35.673, longitude: 139.761),
                tokyo,
                CLLocationCoordinate2D(latitude: 35.693, longitude: 139.779),
                CLLocationCoordinate2D(latitude: 35.707, longitude: 139.772),
            ]
            let points = syntheticCoordinates.map { snapshot.point(for: $0) }
            cg.beginPath()
            cg.move(to: points[0])
            for point in points.dropFirst() { cg.addLine(to: point) }
            cg.setStrokeColor(UIColor.red.cgColor)
            cg.setLineWidth(5 / state.scale)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            cg.strokePath()
            cg.restoreGState()
            cg.restoreGState()
        }
    }

    private func attachPNG(_ image: UIImage, named name: String) throws {
        guard let png = image.pngData() else { throw ProbeError.missingPNG }
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attach(_ receipt: [String: Any], named name: String) {
        let data = try? JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
        let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? String(describing: receipt)
        print("[\(name)] \(text)")
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
