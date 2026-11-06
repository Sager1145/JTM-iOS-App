import Testing
@testable import RailCore

struct PlaybackTrailTests {
    @Test("Mapped physical source spans retain geometry and only recorded station boundaries")
    func sourceBoundaryStopDistances() throws {
        let a = Coordinate(lon: 135, lat: 35)
        let bend = Coordinate(lon: 135.01, lat: 35.01)
        let b = Coordinate(lon: 135.02, lat: 35)
        let c = Coordinate(lon: 135.04, lat: 35)
        let d = Coordinate(lon: 135.05, lat: 35)
        let train = Train(id: "source-boundary", number: "", origin: "A", destination: "C",
            stops: [Stop(name: "A", stopType: "origin", rideSegment: true),
                    Stop(name: "C", stopType: "destination", rideSegment: true)])
        // A→B and B→C both belong to recorded interval A→C. B is
        // a physical boundary only; the first span also has two display parts.
        let features: [Playback.RiddenFeature] = [
            .init(geometry: .multiLineString([[a, bend], [bend, b]]), rideSegment: true, segmentIndex: 0),
            .init(geometry: .lineString([b, c]), rideSegment: true, segmentIndex: 0)
        ]
        let path = try #require(Playback.compile(train: train, features: features, preserveStationEndpoints: true))
        #expect(path.hops.count == 2)
        #expect(path.runs.count == 1)
        #expect(path.runs[0].coords == [a, bend, b, c])
        #expect(path.stations.map(\.name) == ["A", "C"])
        #expect(path.stations.map(\.coord) == [a, c])
        #expect(path.stations.map(\.s) == [0, path.totalMeters])
        #expect(path.stations[1].s > path.hops[0].s1)

        let legacy = try #require(Playback.compile(train: train, features: [
            .init(geometry: .lineString([a, bend, b, c]), rideSegment: true, segmentIndex: 0)
        ], preserveStationEndpoints: true))
        #expect(legacy.stations == path.stations)
        #expect(legacy.totalMeters == path.totalMeters)

        var nextTrain = train
        nextTrain.destination = "D"
        nextTrain.stops[1].stopType = "passenger_stop"
        nextTrain.stops.append(Stop(name: "D", stopType: "destination", rideSegment: true))
        let next = try #require(Playback.compile(train: nextTrain, features: features + [
            .init(geometry: .lineString([c, d]), rideSegment: true, segmentIndex: 1)
        ], preserveStationEndpoints: true))
        #expect(next.hops.count == 3)
        #expect(next.stations.map(\.name) == ["A", "C", "D"])
        #expect(next.stations.map(\.coord) == [a, c, d])
        #expect(next.stations.map(\.s) == [0, next.hops[1].s1, next.totalMeters])
    }

    private let points = [
        Coordinate(lon: 135, lat: 35),
        Coordinate(lon: 135.01, lat: 35.02),
        Coordinate(lon: 135.02, lat: 35),
        Coordinate(lon: 135.03, lat: 35.02),
    ]

    private var run: Playback.Run {
        Playback.Run(coords: points, cum: [0, 10, 20, 30], total: 30, offset: 100)
    }

    @Test("completed trails retain each bend rather than joining sampled endpoints")
    func completeTrail() {
        #expect(Playback.trailCoordinates(
            in: run, fromDistance: 100, throughDistance: 130) == points)
    }

    @Test("partial trails retain passed bends and meet the interpolated head")
    func partialTrail() {
        let trail = Playback.trailCoordinates(
            in: run, fromDistance: 105, throughDistance: 125)
        #expect(trail.count == 4)
        #expect(trail.first == Playback.position(in: [run], atDistance: 105))
        #expect(Array(trail.dropFirst().dropLast()) == Array(points[1...2]))
        #expect(trail.last == Playback.position(in: [run], atDistance: 125))
    }

    @Test("run boundaries clamp a trail without adding a chord across a geometry gap")
    func gapAndEmptyTrail() {
        #expect(Playback.trailCoordinates(
            in: run, fromDistance: 0, throughDistance: 1000) == points)
        #expect(Playback.trailCoordinates(
            in: run, fromDistance: 110, throughDistance: 110).isEmpty)
        #expect(Playback.trailCoordinates(
            in: run, fromDistance: 120, throughDistance: 110).isEmpty)
        let other = Playback.Run(
            coords: [Coordinate(lon: 140, lat: 40), Coordinate(lon: 140.01, lat: 40)],
            cum: [0, 10], total: 10, offset: 130)
        let trail = Playback.trailCoordinates(
            in: other, fromDistance: 0, throughDistance: 135)
        #expect(trail.first == other.coords.first)
        #expect(!trail.contains(points.last!))
    }

    @Test("native arrivals and next origins remain on opposite sides of an unridden gap")
    func stationEndpointsAcrossGap() throws {
        let firstStart = Coordinate(lon: 135, lat: 35)
        let arrival = Coordinate(lon: 135.01, lat: 35)
        let departure = Coordinate(lon: 136, lat: 36)
        let lastEnd = Coordinate(lon: 136.01, lat: 36)
        let train = Train(id: "gap", number: "Gap", origin: "A", destination: "D", stops: [
            Stop(name: "A", stopType: "origin", rideSegment: true),
            Stop(name: "B", stopType: "passenger_stop", rideSegment: false),
            Stop(name: "C", stopType: "passenger_stop", rideSegment: true),
            Stop(name: "D", stopType: "destination", rideSegment: true),
        ])
        let features: [Playback.RiddenFeature] = [
            .init(geometry: .lineString([firstStart, arrival]), rideSegment: true, segmentIndex: 0),
            .init(geometry: .lineString([arrival, departure]), rideSegment: false, segmentIndex: 1),
            .init(geometry: .lineString([departure, lastEnd]), rideSegment: true, segmentIndex: 2),
        ]
        let native = try #require(Playback.compile(
            train: train, features: features, preserveStationEndpoints: true))
        let web = try #require(Playback.compile(train: train, features: features))
        #expect(native.runs.count == 2)
        #expect(native.stations.map(\.name) == ["A", "B", "C", "D"])
        #expect(native.stations[1].s == native.stations[2].s)
        #expect(native.stations[1].coord == arrival)
        #expect(native.stations[2].coord == departure)
        #expect(web.stations[1].coord == departure, "the default remains the Web parity behavior")
        #expect(native.totalMeters == web.totalMeters)
        #expect(native.duration == web.duration)
    }
}
