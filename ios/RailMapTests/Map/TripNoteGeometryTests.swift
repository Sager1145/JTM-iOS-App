import Foundation
import MapKit
import RailCore
import Testing

@testable import RailMap

@MainActor
struct TripNoteGeometryTests {

    private static let stops = [
        Stop(name: "A", departure: "10:00"), Stop(name: "B", arrival: "10:10", departure: "10:11"),
        Stop(name: "C", arrival: "10:20"),
    ]
    private static let lat = 35.0

    /// A → B → C due east along one parallel, 0.01° of longitude per interval.
    private static func ride(
        _ id: String = "r1", mapped: Bool = true, unprovenLast: Bool = false, visible: Bool = true
    ) -> RiddenRouteStore.DrawnRide {
        let train = Train(id: id, date: "2026-01-01", number: "1", origin: "A", destination: "C", stops: stops)
        let segments = [
            RiddenRouteStore.DrawnSegment(
                segmentIndex: 0, from: nil, to: nil,
                coordinates: [Coordinate(lon: 139.00, lat: lat), Coordinate(lon: 139.01, lat: lat)], country: "jp"),
            RiddenRouteStore.DrawnSegment(
                segmentIndex: 1, from: nil, to: nil,
                coordinates: [Coordinate(lon: 139.01, lat: lat), Coordinate(lon: 139.02, lat: lat)], country: "jp"),
        ]
        var ride = RiddenRouteStore.DrawnRide(
            id: id, trainType: nil, country: "jp", colorHex: "#111111", visible: visible,
            segments: segments, route: .resolved, stops: stops,
            daySpan: Dates.daySpan(train), geometryDigest: 1)
        if mapped {
            ride.recordedRouteMapping = RecordedRouteMapping(
                stops: stops, sections: [RouteSection(from: "A", to: "B"), RouteSection(from: "B", to: "C")])
            ride.sectionPartRanges = [0: 0...0, 1: 0...0]
        } else {
            ride.markerPositions = [1: Coordinate(lon: 139.01, lat: lat)]
        }
        if unprovenLast {
            ride.physicalGaps = [RiddenRouteStore.PhysicalGap(segmentIndex: 1, isBoundary: false, isUnproven: true)]
        }
        return ride
    }

    private static func note(_ id: String, _ anchor: TripNoteAnchor) -> TripNote {
        TripNote(id: id, category: "観察", text: "t", time: "10:05", anchor: anchor)
    }

    private static let a = TripNoteStation(name: "A"), b = TripNoteStation(name: "B"), c = TripNoteStation(name: "C")

    @Test("a mapped ride places interval notes by fraction and stacks station notes")
    func mappedPlacement() throws {
        let ride = Self.ride()
        #expect(ride.recordedRouteMapping != nil)
        let placed = TripNoteGeometry.place([
            Self.note("n1", .interval(from: Self.a, to: Self.b, fraction: 0.5, fallback: nil)),
            Self.note("n2", .station(Self.b, fallback: nil)),
            Self.note("n3", .station(Self.b, fallback: nil)),
        ], on: ride)
        #expect(placed.count == 3)
        #expect(abs(placed[0].coordinate.lon - 139.005) < 1e-6)
        #expect(!placed[0].isStation)
        #expect(placed[1].isStation && placed[1].stackPosition == 0)
        #expect(placed[2].isStation && placed[2].stackPosition == 1)
        #expect(abs(placed[1].coordinate.lon - 139.01) < 1e-9)
    }

    @Test("a ride without a route mapping finds its stops by projecting their beads")
    func unmappedPlacement() {
        let ride = Self.ride(mapped: false)
        let route = TripNoteGeometry.route(of: ride, datum: .display)
        #expect(route.stopArcs.count == 3)
        #expect(route.stopArcs.allSatisfy { $0 != nil })
        let placed = TripNoteGeometry.place(
            [Self.note("n1", .interval(from: Self.b, to: Self.c, fraction: 0.5, fallback: nil))], on: ride)
        #expect(placed.count == 1)
        #expect(abs((placed.first?.coordinate.lon ?? 0) - 139.015) < 1e-5)
        // The WGS84 route keeps the same stop shares.
        let wgs = TripNoteGeometry.route(of: ride, datum: .wgs84)
        #expect(wgs.stopArcs.count == 3)
    }

    @Test("an unproven section's far stop has no bead, so the note sits on the route")
    func unprovenSegmentStation() {
        let ride = Self.ride(unprovenLast: true)
        #expect(MapRideMarkers.stopPositions(of: ride)[2] == nil)
        let placed = TripNoteGeometry.place([Self.note("n1", .station(Self.c, fallback: nil))], on: ride)
        #expect(placed.count == 1)
        #expect(abs((placed.first?.coordinate.lon ?? 0) - 139.02) < 1e-9)
    }

    @Test("stations gone from the trip fall back to the stored coordinate; nothing to place is left out")
    func fallbackPlacement() {
        let ride = Self.ride()
        let gone = TripNoteStation(name: "Z")
        let placed = TripNoteGeometry.place([
            Self.note("n1", .station(gone, fallback: Coordinate(lon: 139.5, lat: 35.5))),
            Self.note("n2", .station(gone, fallback: nil)),
        ], on: ride)
        #expect(placed.map(\.noteID) == ["n1"])
        #expect(placed.first?.coordinate == Coordinate(lon: 139.5, lat: 35.5))
    }

    @Test("the centre pin on the line picks an interval, near a stop a station, off the line nothing")
    func centerPickAnchors() throws {
        let ride = Self.ride()
        let between = TripNoteGeometry.pick(
            at: Coordinate(lon: 139.0051, lat: Self.lat + 0.0001), on: ride,
            maxMeters: 50, stationSnapMeters: 60)
        guard case .interval(let from, let to, let fraction, let fallback)? = between?.anchor else {
            Issue.record("expected an interval anchor, got \(String(describing: between))"); return
        }
        #expect(from == Self.a && to == Self.b)
        #expect(abs(fraction - 0.51) < 0.002)
        // WGS84 fallback, read off the route: on the line, not the raw centre.
        #expect(abs((fallback?.lat ?? 0) - Self.lat) < 1e-9)
        #expect(between?.projection.nearStop == nil)

        let nearB = TripNoteGeometry.pick(
            at: Coordinate(lon: 139.0102, lat: Self.lat), on: ride, maxMeters: 50, stationSnapMeters: 60)
        guard case .station(let station, _)? = nearB?.anchor else {
            Issue.record("expected a station anchor, got \(String(describing: nearB))"); return
        }
        #expect(station == Self.b)
        #expect(nearB?.projection.nearStop == 1)

        #expect(TripNoteGeometry.pick(
            at: Coordinate(lon: 139.005, lat: Self.lat + 0.01), on: ride,
            maxMeters: 50, stationSnapMeters: 60) == nil)
    }

    @Test("a picked anchor maps back to the point the pin was on")
    func pickRoundTrip() throws {
        let ride = Self.ride()
        let pick = try #require(TripNoteGeometry.pick(
            at: Coordinate(lon: 139.0151, lat: Self.lat), on: ride, maxMeters: 50, stationSnapMeters: 60))
        let point = try #require(TripNoteGeometry.displayCoordinate(of: pick.anchor, on: ride))
        #expect(abs(point.lon - 139.0151) < 1e-5)
        #expect(abs(point.lat - Self.lat) < 1e-9)
    }

    @Test("a location too far from the route gives no anchor")
    func locationAnchor() {
        let ride = Self.ride()
        #expect(TripNoteGeometry.anchor(forLocation: Coordinate(lon: 139.005, lat: 35.1), on: ride) == nil)
        if case .interval? = TripNoteGeometry.anchor(
            forLocation: Coordinate(lon: 139.005, lat: Self.lat + 0.001), on: ride) {} else {
            Issue.record("expected an interval anchor")
        }
        if case .station(let station, _)? = TripNoteGeometry.stationAnchor(stopIndex: 2, stops: Self.stops, ride: ride) {
            #expect(station == Self.c)
        } else {
            Issue.record("expected a station anchor")
        }
    }

    @Test("the station menu works from the trip's own stops, with or without a drawn ride")
    func stationAnchorFromTripStops() {
        // No ride yet: still a station anchor, just without a fallback.
        guard case .station(let station, let fallback)? = TripNoteGeometry.stationAnchor(
            stopIndex: 1, stops: Self.stops, ride: nil) else {
            Issue.record("expected a station anchor"); return
        }
        #expect(station == Self.b)
        #expect(fallback == nil)
        // A drawn ride supplies the fallback, but only for the same station.
        guard case .station(_, let drawn)? = TripNoteGeometry.stationAnchor(
            stopIndex: 1, stops: Self.stops, ride: Self.ride()) else {
            Issue.record("expected a station anchor"); return
        }
        #expect(abs((drawn?.lon ?? 0) - 139.01) < 1e-9)
        let edited = [Self.stops[0], Stop(name: "X"), Self.stops[2]]
        guard case .station(let renamed, let none)? = TripNoteGeometry.stationAnchor(
            stopIndex: 1, stops: edited, ride: Self.ride()) else {
            Issue.record("expected a station anchor"); return
        }
        #expect(renamed.name == "X")
        #expect(none == nil)
        #expect(TripNoteGeometry.stationAnchor(stopIndex: 3, stops: Self.stops, ride: nil) == nil)
    }

    @Test("a pick finds the trip's solved ride from every ride, keeps its array, and has none before it is drawn")
    func pickRidesAndLifecycle() {
        let controller = RailMapController()
        let all = [Self.ride("other"), Self.ride("r1")]
        #expect(controller.tripNotePickRides(from: all) == nil)
        var finished: [TripNoteAnchor?] = []
        controller.beginTripNotePick(trainID: "r1", initial: nil) { finished.append($0) }
        let first = controller.tripNotePickRides(from: all) ?? []
        #expect(first.map(\.id) == ["r1"])
        #expect(ArrayGeneration.same(first, controller.tripNotePickRides(from: all) ?? []))
        // Not drawn yet: no ride, and the overlay falls back to the trip's stops.
        #expect(controller.tripNotePickRides(from: [Self.ride("other")])?.isEmpty == true)
        // A second begin for the same trip is ignored; the first stays in charge.
        controller.beginTripNotePick(trainID: "r1", initial: nil) { _ in Issue.record("second pick ran") }
        #expect(finished.isEmpty)
        controller.cancelTripNotePickIfOwned(trainID: "other")
        #expect(controller.tripNotePickTrainID == "r1")
        controller.cancelTripNotePickIfOwned(trainID: "r1")
        #expect(controller.tripNotePickTrainID == nil)
        #expect(finished.count == 1 && finished[0] == nil)
        controller.cancelTripNotePick()
        #expect(finished.count == 1, "cancel when idle calls nobody")
    }

    /// A → B → C whose drawn line runs 0.002° past each end station.
    private static func overhangingRide() -> RiddenRouteStore.DrawnRide {
        let train = Train(id: "o", date: "2026-01-01", number: "1", origin: "A", destination: "C", stops: stops)
        var ride = RiddenRouteStore.DrawnRide(
            id: "o", trainType: nil, country: "jp", colorHex: "#111111", visible: true,
            segments: [RiddenRouteStore.DrawnSegment(
                segmentIndex: 0, from: nil, to: nil,
                coordinates: [Coordinate(lon: 139.000, lat: lat), Coordinate(lon: 139.022, lat: lat)],
                country: "jp")],
            route: .resolved, stops: stops, daySpan: Dates.daySpan(train), geometryDigest: 2)
        ride.markerPositions = [0: Coordinate(lon: 139.002, lat: lat), 1: Coordinate(lon: 139.011, lat: lat),
                                2: Coordinate(lon: 139.020, lat: lat)]
        return ride
    }

    @Test("a pin past either end station snaps to it within the snap radius, otherwise clamps")
    func endStationSnapping() {
        let ride = Self.overhangingRide()
        // ~137 m before A, inside a 150 m snap.
        guard case .station(let first, _)? = TripNoteGeometry.pick(
            at: Coordinate(lon: 139.0005, lat: Self.lat), on: ride, maxMeters: 50,
            stationSnapMeters: 150)?.anchor else { Issue.record("expected A"); return }
        #expect(first == Self.a)
        // Same pin, 60 m snap: the clamped start of A → B.
        guard case .interval(let from, let to, let fraction, _)? = TripNoteGeometry.pick(
            at: Coordinate(lon: 139.0005, lat: Self.lat), on: ride, maxMeters: 50,
            stationSnapMeters: 60)?.anchor else { Issue.record("expected an interval"); return }
        #expect(from == Self.a && to == Self.b && fraction == 0)
        // ~137 m past C.
        guard case .station(let last, _)? = TripNoteGeometry.pick(
            at: Coordinate(lon: 139.0215, lat: Self.lat), on: ride, maxMeters: 50,
            stationSnapMeters: 150)?.anchor else { Issue.record("expected C"); return }
        #expect(last == Self.c)
    }

    @Test("the snapshot counts every trip's notes and carries only the selected trip's")
    func snapshotConstruction() {
        var noted = Train(id: "t1", number: "1", origin: "A", destination: "C", stops: Self.stops)
        noted.setTripNotes([Self.note("n1", .station(Self.a, fallback: nil)),
                            Self.note("n2", .station(Self.b, fallback: nil))])
        let plain = Train(id: "t2", number: "2", origin: "A", destination: "C", stops: Self.stops)
        let none = TripNoteMapSnapshot(trains: [noted, plain], selectedTrainID: nil)
        #expect(none.noteCounts == ["t1": 2])
        #expect(none.selectedNotes.isEmpty)
        let selected = TripNoteMapSnapshot(trains: [noted, plain], selectedTrainID: "t1")
        #expect(selected.selectedNotes.map(\.id) == ["n1", "n2"])
        // A trip without notes still hands the pick its own stops.
        let bare = TripNoteMapSnapshot(trains: [noted, plain], selectedTrainID: "t2")
        #expect(bare.selectedStops.map(\.name) == ["A", "B", "C"])
        #expect(bare.noteCounts["t2"] == nil)
        #expect(TripNoteMapSnapshot(trains: [noted, plain], selectedTrainID: "t2").selectedNotes.isEmpty)
    }

    @Test("badges show only with no selection, routes drawn, no playback, in scope and visible")
    func badgeVisibility() {
        let rides = [Self.ride("r1"), Self.ride("r2", visible: false), Self.ride("r3")]
        let counts = ["r1": 2, "r2": 1, "r3": 1]
        func badges(_ snapshot: TripNoteMapSnapshot, selected: String? = nil, routes: Bool = true,
                    playback: Bool = false,
                    inScope: @escaping (RiddenRouteStore.DrawnRide) -> Bool = { _ in true }) -> [MKAnnotation] {
            MapTripNoteLayer.annotations(snapshot, rides: rides, selectedTrainID: selected,
                                         routesDrawn: routes, playbackActive: playback, isInScope: inScope)
        }
        let overview = TripNoteMapSnapshot(noteCounts: counts)
        let shown = badges(overview).compactMap { $0 as? TripNoteBadgeAnnotation }
        #expect(shown.map(\.rideID) == ["r1", "r3"])
        #expect(shown.first?.count == 2)
        #expect(badges(overview, routes: false).isEmpty)
        #expect(badges(overview, playback: true).isEmpty)
        #expect(badges(overview, inScope: { $0.id != "r3" }).compactMap { ($0 as? TripNoteBadgeAnnotation)?.rideID } == ["r1"])

        let selectedSnapshot = TripNoteMapSnapshot(
            selectedTrainID: "r1",
            selectedNotes: [Self.note("n1", .station(Self.b, fallback: nil))], noteCounts: counts)
        let marks = badges(selectedSnapshot, selected: "r1")
        #expect(!marks.contains { $0 is TripNoteBadgeAnnotation })
        #expect(marks.compactMap { ($0 as? TripNoteAnnotation)?.noteID } == ["n1"])
        // A trip without notes draws nothing, selected or not.
        #expect(badges(TripNoteMapSnapshot(selectedTrainID: "r3", noteCounts: ["r1": 2]), selected: "r3").isEmpty)
        #expect(badges(TripNoteMapSnapshot(noteCounts: ["r1": 2])).compactMap {
            ($0 as? TripNoteBadgeAnnotation)?.rideID } == ["r1"])
        // A selection the snapshot is not yet about draws nothing at all.
        #expect(badges(overview, selected: "r3").isEmpty)
    }

    @Test("the reconciler keeps a note mark whose presentation is unchanged and replaces a changed badge")
    func reconcilerKeys() {
        let reconciler = MapAnnotationReconciler()
        let point = CLLocationCoordinate2D(latitude: Self.lat, longitude: 139.01)
        func mark(_ stack: Int) -> TripNoteAnnotation {
            TripNoteAnnotation(trainID: "r1", noteID: "n1", coordinate: point, isStation: true,
                               stackPosition: stack, accessibilityText: "Note: c", placeSummary: "At B")
        }
        let same = reconciler.plan([mark(0)], replacing: [mark(0)])
        #expect(same.retainedOldCount == 1 && same.addedCount == 0)
        let moved = reconciler.plan([mark(1)], replacing: [mark(0)])
        #expect(moved.addedCount == 1 && moved.removedCount == 1)

        let badge = TripNoteBadgeAnnotation(rideID: "r1", count: 1, coordinate: point, accessibilityText: "1")
        #expect(reconciler.plan([TripNoteBadgeAnnotation(rideID: "r1", count: 1, coordinate: point, accessibilityText: "1")],
                                replacing: [badge]).retainedOldCount == 1)
        #expect(reconciler.plan([TripNoteBadgeAnnotation(rideID: "r1", count: 2, coordinate: point, accessibilityText: "2")],
                                replacing: [badge]).addedCount == 1)
        // A moved note, or one whose place summary changed, is not kept.
        let moved2 = TripNoteAnnotation(
            trainID: "r1", noteID: "n1", coordinate: CLLocationCoordinate2D(latitude: Self.lat, longitude: 139.02),
            isStation: true, stackPosition: 0, accessibilityText: "Note: c", placeSummary: "At B")
        #expect(reconciler.plan([moved2], replacing: [mark(0)]).retainedOldCount == 0)
        let renamed = TripNoteAnnotation(
            trainID: "r1", noteID: "n1", coordinate: point,
            isStation: true, stackPosition: 0, accessibilityText: "Note: c", placeSummary: "At C")
        #expect(reconciler.plan([renamed], replacing: [mark(0)]).retainedOldCount == 0)
        // A note and a badge for the same trip never share an identity.
        #expect(reconciler.plan([badge], replacing: [mark(0)]).retainedOldCount == 0)
    }
}
