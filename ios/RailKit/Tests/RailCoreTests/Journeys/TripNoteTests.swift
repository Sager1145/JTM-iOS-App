import Foundation
import Testing

@testable import RailCore

// Trip event notes: stored on the trip as `trip_notes`, placed by stations and
// a fraction (so a re-solve cannot strand them), timed in the region's clock
// (so the phone's zone cannot move them).

@Suite("trip notes")
struct TripNoteTests {

    static let stops = [
        Stop(name: "東京", departure: "23:30", stopType: "origin", rideSegment: true, stationID: "st:jp:1"),
        Stop(name: "熱海", arrival: "24:20", departure: "24:22", stopType: "passenger_stop", rideSegment: true,
             stationID: "st:jp:2"),
        Stop(name: "静岡", arrival: "25:10", stopType: "destination", rideSegment: true, stationID: "st:jp:3"),
    ]

    static func train(notes: [TripNote]?) -> Train {
        var train = Train(
            id: "note_01", date: "2026-08-28", number: "サンライズ", trainType: "特急",
            origin: "東京", destination: "静岡", direction: "down", visible: true,
            stops: stops, region: "jp")
        train.tripNotes = notes
        return train
    }

    static let notes = [
        TripNote(id: "n1", category: "臨時停車", text: "信号待ち 5分", time: "24:05",
                 anchor: .interval(from: TripNoteStation(stop: stops[0]), to: TripNoteStation(stop: stops[1]),
                                   fraction: 0.37, fallback: Coordinate(lon: 139.3, lat: 35.3))),
        TripNote(id: "n2", category: "Crew change", text: "", time: nil,
                 anchor: .station(TripNoteStation(stop: stops[1]), fallback: nil)),
        TripNote(id: "n3", category: "", text: "fallback only", time: "23:59",
                 anchor: .coordinate(Coordinate(lon: 138.4, lat: 34.97))),
    ]

    // MARK: storage

    @Test("notes round-trip through export, canonical JSON and import")
    func storeRoundTrip() throws {
        let exported = TrainValidation.normalizeExportTrain(
            Self.train(notes: Self.notes), country: "jp", stations: .empty)
        let text = StoreOperations.stringify(StoreOperations.json(exported))
        #expect(text.contains("\"trip_notes\""))
        let reimported = try TrainValidation.normalizeImportedTrain(try TrainValidation.JSON.parse(text))
        #expect(reimported.tripNotes == Self.notes)
        var ids = Set<String>()
        try TrainValidation.validateTrain(reimported, index: 0, ids: &ids)
    }

    @Test("Codable writes trip_notes only when present and reads it back")
    func codableRoundTrip() throws {
        let plain = String(decoding: try JSONEncoder().encode(Self.train(notes: nil)), as: UTF8.self)
        #expect(!plain.contains("trip_notes"))
        let data = try JSONEncoder().encode(Self.train(notes: Self.notes))
        #expect(try JSONDecoder().decode(Train.self, from: data).tripNotes == Self.notes)
    }

    @Test("a trip without notes exports byte-identically to before")
    func noNotesNoKey() {
        let text = StoreOperations.stringify(StoreOperations.json(Self.train(notes: nil)))
        #expect(!text.contains("trip_notes"))
        var train = Self.train(notes: Self.notes)
        train.setTripNotes([])
        #expect(train.tripNotes == nil)
    }

    @Test("a malformed note is dropped, the trip survives")
    func malformedNoteDropped() throws {
        let json = try TrainValidation.JSON.parse("""
            {"id":"x","number":"1","origin":"A","destination":"B",
             "stops":[{"name":"A","departure":"06:00","stop_type":"origin","ride_segment":true},
                      {"name":"B","arrival":"07:00","stop_type":"destination","ride_segment":true}],
             "trip_notes":[{"id":"ok","category":"c","text":"t","anchor":{"type":"coordinate","lat":35,"lon":139}},
                           {"id":"bad","anchor":{"type":"interval"}}, 7,
                           {"id":"ok","category":"dup","anchor":{"type":"coordinate","lat":1,"lon":1}},
                           {"id":"t","time":"9:30:00","anchor":{"type":"coordinate","lat":1,"lon":1}}]}
            """)
        let train = try TrainValidation.normalizeImportedTrain(json)
        // A non-object is dropped, a duplicate id keeps the first, an
        // unreadable place survives as `.unknown`, an unreadable time is cleared.
        #expect(train.tripNotes?.map(\.id) == ["ok", "bad", "t"])
        #expect(train.tripNotes?[0].category == "c")
        #expect(train.tripNotes?[1].anchor == .unknown(type: "interval"))
        #expect(train.tripNotes?[2].time == nil)
        var ids = Set<String>()
        try TrainValidation.validateTrain(train, index: 0, ids: &ids)
        // And it writes back as found.
        let text = StoreOperations.stringify(StoreOperations.json(train))
        #expect(text.contains("\"type\":\"interval\""))
    }

    @Test("the native store never fails to load over one odd note")
    func codableIsLenient() throws {
        let json = """
            [{"id":"a","anchor":{"type":"teleport"}},
             {"id":"b","time":"noon","anchor":{"type":"interval","from":{"name":"A"},"to":{"name":"B"}}},
             {"id":"c","anchor":{"type":"station","station":{}},"lat":1}]
            """
        let notes = try JSONDecoder().decode([TripNote].self, from: Data(json.utf8))
        #expect(notes[0].anchor == .unknown(type: "teleport"))
        #expect(notes[1].time == nil)
        #expect(notes[1].anchor == .interval(from: TripNoteStation(name: "A"), to: TripNoteStation(name: "B"),
                                             fraction: 0.5, fallback: nil))
        #expect(notes[2].anchor == .unknown(type: "station"))
        let again = try JSONDecoder().decode([TripNote].self, from: JSONEncoder().encode(notes))
        #expect(again == notes)
        #expect(TripNotePlacement.resolve(notes[0].anchor, stops: Self.stops) == .unplaced)
    }

    @Test("a trip with odd notes still loads from the native store")
    func nativeStoreLossy() throws {
        let json = """
            {"id":"x","number":"1","origin":"A","destination":"B",
             "stops":[{"name":"A","departure":"06:00","stop_type":"origin","ride_segment":true}],
             "trip_notes":[7, {"text":"no id"}, {"id":"a","category":5,"anchor":"nope"},
                           {"id":"a","text":"dup"}, {"id":"b","text":"ok","anchor":{"type":"coordinate","lat":1,"lon":2}}]}
            """
        let train = try JSONDecoder().decode(Train.self, from: Data(json.utf8))
        #expect(train.tripNotes?.map(\.id) == ["a", "b"])
        #expect(train.tripNotes?[0].category == "")
        #expect(train.tripNotes?[0].anchor == .unknown(type: ""))
    }

    @Test("the suggested time uses the clock it is given")
    func suggestionClock() throws {
        var train = Self.train(notes: nil)
        train.region = nil
        let instant = try #require(TripNoteTime.instant(serviceDate: "2026-08-28", time: "24:15", clock: .taiwan))
        #expect(TripNoteTime.suggested(for: train, stopIndex: nil, now: instant, clock: .taiwan) == "24:15")
        #expect(TripNoteTime.suggested(for: train, stopIndex: nil, now: instant, clock: .japan) == "25:15")
    }

    @Test("validation rejects a duplicate id and an unreadable time")
    func validation() {
        var train = Self.train(notes: [Self.notes[0], Self.notes[0]])
        var ids = Set<String>()
        #expect(throws: (any Error).self) { try TrainValidation.validateTrain(train, index: 0, ids: &ids) }
        train.tripNotes = [TripNote(id: "t", category: "", text: "", time: "8pm", anchor: Self.notes[2].anchor)]
        ids = []
        #expect(throws: (any Error).self) { try TrainValidation.validateTrain(train, index: 0, ids: &ids) }
    }

    // MARK: placement

    @Test("anchors resolve to the trip's current stops, surviving edits")
    func placement() {
        #expect(TripNotePlacement.resolve(Self.notes[0].anchor, stops: Self.stops)
                == .interval(fromStopIndex: 0, toStopIndex: 1, fraction: 0.37))
        #expect(TripNotePlacement.resolve(Self.notes[1].anchor, stops: Self.stops) == .station(stopIndex: 1))
        // A stop inserted in between widens the interval rather than losing it.
        var edited = Self.stops
        edited.insert(Stop(name: "小田原", stopType: "passenger_stop", rideSegment: true, stationID: "st:jp:4"), at: 1)
        #expect(TripNotePlacement.resolve(Self.notes[0].anchor, stops: edited)
                == .interval(fromStopIndex: 0, toStopIndex: 2, fraction: 0.37))
        // Stations gone: the stored coordinate is the fallback.
        let gone = [Self.stops[2]]
        #expect(TripNotePlacement.resolve(Self.notes[0].anchor, stops: gone)
                == .coordinate(Coordinate(lon: 139.3, lat: 35.3)))
        #expect(TripNotePlacement.resolve(Self.notes[1].anchor, stops: gone) == .unplaced)
    }

    @Test("identity matching is by id, and name matching is separate")
    func identityVersusName() {
        let other = Stop(name: "熱海", stopType: "passenger_stop", rideSegment: true, stationID: "st:jp:9")
        #expect(!TripNoteStation(stop: Self.stops[1]).matchesIdentity(other))
        #expect(TripNoteStation(stop: Self.stops[1]).matchesName(other))
        #expect(!TripNoteStation(name: "熱海").matchesIdentity(other))
    }

    // MARK: time

    @Test("service-day times handle overnight trains")
    func overnight() throws {
        let clock = RegionClock.japan
        let instant = try #require(TripNoteTime.instant(serviceDate: "2026-08-28", time: "25:10", clock: clock))
        #expect(TripNoteTime.time(at: instant, serviceDate: "2026-08-28", clock: clock) == "25:10")
        #expect(clock.civilDate(at: instant) == "2026-08-29")
        #expect(TripNoteTime.display("25:10")! == ("01:10", 1))
        #expect(TripNoteTime.minutes("48:00") == nil)
        #expect(TripNoteTime.minutes("7:05") == 425)
        #expect(TripNoteTime.time(at: instant.addingTimeInterval(3 * 86_400),
                                  serviceDate: "2026-08-28", clock: clock) == nil)
    }

    @Test("the suggested time is now during the trip, else the anchor stop's time")
    func suggestion() throws {
        let train = Self.train(notes: nil)
        let during = try #require(TripNoteTime.instant(serviceDate: "2026-08-28", time: "24:15", clock: .japan))
        #expect(TripNoteTime.suggested(for: train, stopIndex: 1, now: during, clock: .japan) == "24:15")
        let later = during.addingTimeInterval(30 * 86_400)
        #expect(TripNoteTime.suggested(for: train, stopIndex: 1, now: later, clock: .japan) == "24:22")
        #expect(TripNoteTime.suggested(for: train, stopIndex: nil, now: later, clock: .japan) == "23:30")
    }

    @Test("stored and displayed values do not move with the phone's time zone")
    func phoneZoneInvariance() throws {
        let original = NSTimeZone.default
        defer { NSTimeZone.default = original }
        let instant = Date(timeIntervalSince1970: 1_787_929_500)  // 2026-08-28T15:05Z = 24:05 JST
        var results: [[String?]] = []
        for zone in ["Asia/Tokyo", "America/Los_Angeles", "Europe/London", "Pacific/Kiritimati", "GMT"] {
            NSTimeZone.default = try #require(TimeZone(identifier: zone))
            #expect(NSTimeZone.default.identifier == zone)
            let stored = TripNoteTime.time(at: instant, serviceDate: "2026-08-28", clock: .japan)
            let round = TripNoteTime.instant(serviceDate: "2026-08-28", time: stored, clock: .japan)
            let shown = TripNoteTime.display(stored)
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            let encoded = String(decoding: try encoder.encode(Self.notes[0]), as: UTF8.self)
            results.append([stored, round.map { String($0.timeIntervalSince1970) },
                            shown?.clock, shown.map { String($0.dayOffset) }, encoded])
        }
        #expect(results.first?[0] == "24:05")
        #expect(Set(results.map { $0.compactMap { $0 }.joined(separator: "|") }).count == 1)
    }

    @Test("note times follow the wall clock across summer-time changeovers")
    func summerTimeWallClock() throws {
        let clock = RegionClock.forZone("America/New_York", regionCode: nil)
        for date in ["2026-03-07", "2026-03-08", "2026-10-31", "2026-11-01"] {
            for time in ["00:30", "01:30", "03:30", "12:00", "23:59", "24:00", "25:30", "47:59"] {
                let instant = try #require(TripNoteTime.instant(serviceDate: date, time: time, clock: clock))
                #expect(instant == clock.instant(serviceDate: date, clock: time))
                #expect(TripNoteTime.time(at: instant, serviceDate: date, clock: clock) == time,
                        "\(date) \(time)")
            }
        }
    }

    // MARK: station name fallback

    @Test("a re-identified station resolves by name")
    func reidentifiedByName() {
        let anchor = TripNoteAnchor.station(
            TripNoteStation(name: "熱海", stationID: "st:jp:old"), fallback: nil)
        #expect(TripNotePlacement.resolve(anchor, stops: Self.stops) == .station(stopIndex: 1))
    }

    @Test("an identity match elsewhere beats a same-name stop")
    func identityBeatsName() {
        var stops = Self.stops
        stops.insert(Stop(name: "静岡", arrival: "24:50", stopType: "passenger_stop", rideSegment: true,
                          stationID: "st:jp:other"), at: 2)
        let anchor = TripNoteAnchor.station(
            TripNoteStation(name: "熱海", stationID: "st:jp:3"), fallback: nil)
        // "熱海" is a name match at index 1, but st:jp:3 is the true id-match at 3.
        #expect(TripNotePlacement.resolve(anchor, stops: stops) == .station(stopIndex: 3))
        let byName = TripNoteAnchor.station(
            TripNoteStation(name: "静岡", stationID: "st:jp:3"), fallback: nil)
        #expect(TripNotePlacement.resolve(byName, stops: stops) == .station(stopIndex: 3))
    }

    @Test("an interval resolves with one re-identified end")
    func intervalOneEndReidentified() {
        let anchor = TripNoteAnchor.interval(
            from: TripNoteStation(name: "東京", stationID: "st:jp:old"),
            to: TripNoteStation(name: "熱海", stationID: "st:jp:2"),
            fraction: 0.4, fallback: nil)
        #expect(TripNotePlacement.resolve(anchor, stops: Self.stops)
            == .interval(fromStopIndex: 0, toStopIndex: 1, fraction: 0.4))
    }

    // MARK: categories

    @Test("category suggestions put the reader's own first, then the starters")
    func categories() {
        let trains = [Self.train(notes: Self.notes),
                      Self.train(notes: [TripNote(id: "x", category: "Crew change", text: "",
                                                  anchor: Self.notes[2].anchor)])]
        let suggestions = TripNoteCategories.suggestions(from: trains, starters: ["事故", "Crew change"])
        #expect(suggestions == ["Crew change", "臨時停車", "事故"])
    }
}

@Suite("trip note share text")
struct TripNoteShareTextTests {
    @Test("header line, details, blank line, body kept verbatim")
    func compose() {
        let body = "- 信号待ち\n- [ ] 運転士に確認\nhttps://example.com\n\n  indented"
        let text = TripNoteShareText.compose(category: "臨時停車", time: "01:10 (+1) JST",
                                             place: "東京 → 熱海", trip: "サンライズ出雲 2026-08-28",
                                             body: body)
        #expect(text == "臨時停車 · 01:10 (+1) JST\n東京 → 熱海\nサンライズ出雲 2026-08-28\n\n" + body)
    }

    @Test("empty pieces are left out")
    func sparse() {
        #expect(TripNoteShareText.compose(category: "", time: nil, place: nil, trip: nil, body: "x") == "x")
        #expect(TripNoteShareText.compose(category: "A", time: nil, place: "", trip: nil, body: "") == "A")
    }
}
