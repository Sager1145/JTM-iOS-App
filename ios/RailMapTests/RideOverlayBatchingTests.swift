import MapKit
import RailCore
import RailPresentation
import Testing
@testable import RailMap

@MainActor
struct RideOverlayBatchingTests {
    private func line(_ lat: Double) -> MKPolyline {
        let points = [CLLocationCoordinate2D(latitude: lat, longitude: 139.0),
                      CLLocationCoordinate2D(latitude: lat, longitude: 139.1)]
        return MKPolyline(coordinates: points, count: points.count)
    }

    private func entry(
        _ id: String, color: String = "#FF0000", inScope: Bool = true, cell: Int = 0,
        solid: [MKPolyline]? = nil, crossDay: [MKPolyline] = [], unproven: [MKPolyline] = []
    ) -> RideOverlayBatching.RideEntry {
        .init(rideID: id, colorHex: color, inScope: inScope, cell: cell,
              solid: solid ?? [line(35)], crossDay: crossDay, unproven: unproven)
    }

    @Test func sameColourKindAndScopeShareOneBatch() {
        let plan = RideOverlayBatching.plan(
            entries: [entry("a"), entry("b")], selectedRideID: nil)
        #expect(plan.batches.count == 1)
        #expect(plan.batches[0].polylines.count == 2)
        #expect(plan.batches[0].key == "rides|ride|in|#FF0000|c0")
    }

    @Test func colourKindAndScopeSplitBatches() {
        let plan = RideOverlayBatching.plan(entries: [
            entry("a"), entry("b", color: "#00ff00"), entry("c", inScope: false),
            entry("d", crossDay: [line(36)]),
        ], selectedRideID: nil)
        let keys = plan.batches.map(\.key)
        #expect(Set(keys).count == keys.count)
        #expect(keys == [
            "rides|ride|off|#FF0000|c0", "rides|ride|in|#00FF00|c0", "rides|ride|in|#FF0000|c0",
            "rides|ride-xday|in|#FF0000|c0",
        ])
    }

    @Test func keyNormalisesColourCase() {
        let plan = RideOverlayBatching.plan(
            entries: [entry("a", color: "#abcdef"), entry("b", color: "#ABCDEF")], selectedRideID: nil)
        #expect(plan.batches.count == 1)
    }

    @Test func selectedRideIsExcludedFromBatches() {
        let plan = RideOverlayBatching.plan(
            entries: [entry("a"), entry("b")], selectedRideID: "a")
        #expect(plan.selected?.rideID == "a")
        #expect(plan.batches.count == 1)
        #expect(plan.batches[0].polylines.count == 1)
    }

    @Test func stackingOrderIsKindThenOffBeforeInThenColour() {
        let plan = RideOverlayBatching.plan(entries: [
            entry("a", color: "#BBBBBB", unproven: [line(37)]),
            entry("b", color: "#AAAAAA", inScope: false, crossDay: [line(36)]),
            entry("c", color: "#AAAAAA"),
            entry("d", color: "#CCCCCC", inScope: false),
        ], selectedRideID: nil)
        #expect(plan.batches.map(\.key) == [
            "rides|ride|off|#CCCCCC|c0", "rides|ride|in|#AAAAAA|c0", "rides|ride|in|#BBBBBB|c0",
            "rides|ride-xday|off|#AAAAAA|c0", "rides|ride-unproven|in|#BBBBBB|c0",
        ])
    }

    @Test func unchangedMembershipYieldsIdenticalPolylineArrays() {
        let a = entry("a"), b = entry("b")
        let first = RideOverlayBatching.plan(entries: [a, b], selectedRideID: nil)
        let second = RideOverlayBatching.plan(entries: [b, a], selectedRideID: nil)
        #expect(first.batches.count == second.batches.count)
        for (x, y) in zip(first.batches, second.batches) {
            #expect(x.polylines.count == y.polylines.count)
            #expect(zip(x.polylines, y.polylines).allSatisfy { $0 === $1 })
        }
    }

    @Test func addingARideLeavesOtherColoursUntouched() {
        let red = entry("a"), blue = entry("b", color: "#0000FF")
        let before = RideOverlayBatching.plan(entries: [red, blue], selectedRideID: nil)
        let after = RideOverlayBatching.plan(
            entries: [red, blue, entry("c")], selectedRideID: nil)
        let blueBefore = before.batches.first { $0.colorHex == "#0000FF" }!
        let blueAfter = after.batches.first { $0.colorHex == "#0000FF" }!
        #expect(zip(blueBefore.polylines, blueAfter.polylines).allSatisfy { $0 === $1 })
        #expect(blueBefore.polylines.count == blueAfter.polylines.count)
        let redAfter = after.batches.first { $0.colorHex == "#FF0000" }!
        #expect(redAfter.polylines.count == 2)
    }

    @Test func batchKeysAreNotRideCoreOrCasingKeys() {
        let key = RideOverlayBatching.batchKey(kind: .rideCrossDay, scopeClass: .off, colorHex: "#123456", cell: 3)
        #expect(MapOverlayStyles.isRideBatchKey(key))
        #expect(!MapOverlayStyles.isRideCoreKey(key))
        #expect(!MapOverlayStyles.isRideCasingKey(key))
        for key in ["ride|x", "ride-xday|x", "ride-unproven|x", "ride-casing|x", "ride-xday-casing|x"] {
            #expect(!MapOverlayStyles.isRideBatchKey(key))
        }
    }

    @Test func sameColourRidesInDifferentCellsSplitIntoBatches() {
        let plan = RideOverlayBatching.plan(
            entries: [entry("a", cell: 5), entry("b", cell: 2)], selectedRideID: nil)
        #expect(plan.batches.map(\.key) == ["rides|ride|in|#FF0000|c2", "rides|ride|in|#FF0000|c5"])
    }

    @Test func addingARideInOneCellLeavesAnotherCellsBatchIdentical() {
        let a = entry("a", cell: 1), b = entry("b", cell: 2)
        let before = RideOverlayBatching.plan(entries: [a, b], selectedRideID: nil)
        let after = RideOverlayBatching.plan(
            entries: [a, b, entry("c", cell: 1)], selectedRideID: nil)
        let cellB = { (plan: RideOverlayBatching.Plan) in plan.batches.first { $0.cell == 2 }! }
        let x = cellB(before), y = cellB(after)
        #expect(x.polylines.count == y.polylines.count)
        #expect(zip(x.polylines, y.polylines).allSatisfy { $0 === $1 })
        #expect(after.batches.first { $0.cell == 1 }!.polylines.count == 2)
    }

    @Test func cellIsStableGridIndexOfRectCentre() {
        let world = MKMapRect.world
        let origin = MKMapRect(x: 0, y: 0, width: 1, height: 1)
        #expect(RideOverlayBatching.cell(of: origin) == 0)
        let last = MKMapRect(x: world.width - 2, y: world.height - 2, width: 1, height: 1)
        #expect(RideOverlayBatching.cell(of: last) == 255)
        let centre = MKMapRect(x: world.width / 2, y: 0, width: 1, height: 1)
        #expect(RideOverlayBatching.cell(of: centre) == 8)
    }

    @Test func tapResolvesIndividualRidesSharingOneBatch() {
        let plan = RideOverlayBatching.plan(entries: [entry("a"), entry("b")], selectedRideID: nil)
        #expect(plan.batches.count == 1)

        let mapView = MKMapView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        mapView.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 35.0, longitude: 139.05),
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.2))
        mapView.layoutIfNeeded()
        // Two parallel strokes about 20 screen points apart.
        let mid = mapView.convert(CLLocationCoordinate2D(latitude: 35.0, longitude: 139.05), toPointTo: mapView)
        func coordinate(_ x: Double, _ y: Double) -> Coordinate {
            let c = mapView.convert(CGPoint(x: x, y: y), toCoordinateFrom: mapView)
            return Coordinate(lon: c.longitude, lat: c.latitude)
        }
        let strokeA = [coordinate(50, mid.y - 10), coordinate(350, mid.y - 10)]
        let strokeB = [coordinate(50, mid.y + 10), coordinate(350, mid.y + 10)]
        let index = RideTapIndex(snapshot: .init(ids: ["a", "b"], strokes: [[strokeA], [strokeB]]))
        let tap = CGPoint(x: 200, y: mid.y + 10)
        let candidates = index.candidates(at: tap, on: mapView) ?? index.allCandidates(on: mapView)
        let hits = RideTapResolver.hits(
            at: RideTapResolver.Point(x: tap.x, y: tap.y), among: candidates)
        #expect(hits.first == "b")
    }
}
