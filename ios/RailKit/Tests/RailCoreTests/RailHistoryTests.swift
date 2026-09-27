import XCTest
@testable import RailCore

final class RailHistoryTests: XCTestCase {
    private let overlayJSON = """
    {
      "schema_version": "1",
      "revision": "2026-09-23.1",
      "sections": [
        {
          "type": "Feature",
          "properties": {
            "history_id": "jp.rumoi.rumoi-mashike",
            "N02_003": "留萌線", "N02_004": "北海道旅客鉄道",
            "valid_to": "2016-12-05"
          },
          "geometry": { "type": "LineString", "coordinates": [[141.0, 43.0], [141.1, 43.1]] }
        }
      ],
      "stations": [
        {
          "type": "Feature",
          "properties": {
            "history_id": "jp.rumoi.mashike",
            "station_name": "増毛", "line_name": "留萌線", "operator": "北海道旅客鉄道",
            "valid_to": "2016-12-05"
          },
          "geometry": { "type": "Point", "coordinates": [141.1, 43.1] }
        }
      ],
      "retirements": [
        {
          "history_id": "jp.rumoi.fukagawa-ishikarinumata",
          "match": {
            "line_name": "留萌線", "operator": "北海道旅客鉄道",
            "bbox": [140.0, 43.0, 142.0, 44.0]
          },
          "valid_to": "2026-04-01"
        }
      ]
    }
    """

    func testDecodesOverlay() throws {
        let overlay = try RailHistoryOverlay.decode(Data(overlayJSON.utf8))
        XCTAssertEqual(overlay.schemaVersion, "1")
        XCTAssertEqual(overlay.revision, "2026-09-23.1")
        XCTAssertEqual(overlay.sections.count, 1)
        XCTAssertEqual(overlay.sections[0].properties.lineName, "留萌線")
        XCTAssertEqual(overlay.sections[0].properties.validTo, "2016-12-05")
        XCTAssertEqual(overlay.stations.count, 1)
        XCTAssertEqual(overlay.retirements.count, 1)
        XCTAssertEqual(overlay.retirements[0].historyId, "jp.rumoi.fukagawa-ishikarinumata")
        XCTAssertEqual(overlay.retirements[0].match.bbox, [140.0, 43.0, 142.0, 44.0])
    }

    func testDecodeFailsWithoutRevision() {
        let json = """
        { "schema_version": "1", "sections": [], "stations": [], "retirements": [] }
        """
        XCTAssertThrowsError(try RailHistoryOverlay.decode(Data(json.utf8)))
    }

    func testRejectsMalformedHistoryMetadata() {
        let cases = [
            overlayJSON.replacingOccurrences(of: "\"schema_version\": \"1\"", with: "\"schema_version\": \"2\""),
            overlayJSON.replacingOccurrences(of: "\"revision\": \"2026-09-23.1\"", with: "\"revision\": \" \""),
            overlayJSON.replacingOccurrences(of: "2016-12-05", with: "2016-02-30"),
            overlayJSON.replacingOccurrences(of: "[140.0, 43.0, 142.0, 44.0]", with: "[142.0, 43.0, 140.0, 44.0]"),
            overlayJSON.replacingOccurrences(of: "jp.rumoi.mashike", with: " "),
            "{",
        ]
        for json in cases {
            XCTAssertThrowsError(try RailHistoryOverlay.decode(Data(json.utf8)))
        }
    }

    func testRejectsEmptyOrReversedIntervals() {
        let reversed = overlayJSON.replacingOccurrences(
            of: "\"valid_to\": \"2016-12-05\"",
            with: "\"valid_from\": \"2017-01-01\", \"valid_to\": \"2016-12-05\"")
        XCTAssertThrowsError(try RailHistoryOverlay.decode(Data(reversed.utf8)))
        let empty = overlayJSON.replacingOccurrences(
            of: "\"valid_to\": \"2016-12-05\"", with: "\"valid_to\": \"\"")
        XCTAssertThrowsError(try RailHistoryOverlay.decode(Data(empty.utf8)))
    }

    func testHistoryRevisionSetUsesSortedRegions() {
        let revisions = RailHistoryRevisionSet(["us": "2026.2", "ca": nil])
        XCTAssertEqual(revisions.canonical, "ca:none|us:2026.2")
    }

    func testPrecomputedRouteRequiresItsOwnSolverContext() throws {
        let revisions = RailHistoryRevisionSet(["jp": "2026-09-23.2"])
        let contextJSON = """
        {"solver_version":"22","route_cache_digest":"expected","ride_date":"2015-08-01",
         "history_revisions":{"jp":"2026-09-23.2"}}
        """
        let context = try JSONDecoder().decode(
            RailPrecomputedSolverContext.self, from: Data(contextJSON.utf8))
        func accepts(_ context: RailPrecomputedSolverContext?) -> Bool {
            RailPrecomputedRouteGate.accepts(
                context, expectedDigest: "expected", solverVersion: "22",
                rideDate: "2015-08-01", revisions: revisions)
        }
        XCTAssertTrue(accepts(context))
        XCTAssertFalse(accepts(nil)) // legacy dated JP part falls back to on-demand solve
        XCTAssertFalse(RailPrecomputedRouteGate.accepts(
            context, expectedDigest: "other", solverVersion: "22",
            rideDate: "2015-08-01", revisions: revisions))
        XCTAssertFalse(RailPrecomputedRouteGate.accepts(
            context, expectedDigest: "expected", solverVersion: "22",
            rideDate: "2020-08-01", revisions: revisions))
        XCTAssertFalse(RailPrecomputedRouteGate.accepts(
            context, expectedDigest: "expected", solverVersion: "22",
            rideDate: "2015-08-01", revisions: .init(["jp": "2026-09-24.1"])))
        XCTAssertTrue(RailPrecomputedRouteGate.accepts(
            nil, expectedDigest: "expected", solverVersion: "22",
            rideDate: "2015-08-01", revisions: .init(["tw": nil])))
    }

    /// A dated ride whose revisions are not all `none` must not accept a legacy
    /// part with no solver context. Rejection is not the end of the path: the
    /// on-demand solver still returns the historical edge before `valid_to`.
    func testLegacyNilSolverContextRejectsDatedHistoryButOnDemandStillSolves() throws {
        let revisions = RailHistoryRevisionSet(["jp": "2026-09-23.2"])
        XCTAssertFalse(RailPrecomputedRouteGate.accepts(
            nil, expectedDigest: "expected", solverVersion: "22",
            rideDate: "2015-08-01", revisions: revisions))

        let start = Coordinate(lon: 135.0, lat: 35.0)
        let end = Coordinate(lon: 135.02, lat: 35.0)
        let bend = Coordinate(lon: 135.01, lat: 35.008)
        let retired = RouteGraph.SectionFeature(
            properties: .init(lineName: "L", operator: "O", validTo: "2016-01-01"),
            lines: [[start, end]])
        let current = RouteGraph.SectionFeature(
            properties: .init(lineName: "L", operator: "O"),
            lines: [[start, bend, end]])
        func station(_ name: String, _ coordinate: Coordinate) -> Stations.Feature {
            Stations.Feature(
                properties: [
                    "station_name": .string(name),
                    "line_name": .string("L"),
                    "operator": .string("O"),
                ],
                geometry: .init(
                    type: "Point",
                    coordinates: .array([.number(coordinate.lon), .number(coordinate.lat)])))
        }
        let stations = Stations.Index(.init(features: [
            station("A", start), station("B", end),
        ]))
        let store = RouteGraph.RouteGraphStore(sections: [retired, current])
        func solve(_ date: String) -> RouteSolver.SolvedSection? {
            RouteSolver.solveSectionOnDemand(
                RouteSection(from: "A", to: "B", lineNames: ["L"]),
                segmentIndex: 0,
                train: .init(
                    id: "legacy-gate", number: "", trainType: "", company: "",
                    origin: "A", destination: "B", preferredLineNames: [],
                    preferredOperatorNames: [], allowedInstitutionTypeCodes: nil,
                    institutionFilterMode: "soft", rideDate: date),
                country: "jp", graphStore: store, stations: stations)
        }
        let historical = try XCTUnwrap(solve("2015-08-01"))
        XCTAssertEqual(historical.coordinates, [start, end])
        let open = try XCTUnwrap(solve("2016-01-01"))
        XCTAssertEqual(open.coordinates, [start, bend, end])
    }

    func testInvalidOverlayIsNotAnAbsentRevisionNoneSoTheStoreMustNotSolveCurrentOnly() {
        let broken = Data("{".utf8)
        XCTAssertThrowsError(try RailHistoryOverlay.decode(broken))
        if let overlay = try? RailHistoryOverlay.decode(broken) {
            XCTFail("decoded revision \(overlay.revision); the store must not solve current-only")
            XCTAssertNotEqual(overlay.revision, "none")
            XCTAssertFalse(
                overlay.sections.isEmpty && overlay.stations.isEmpty && overlay.revision == "none")
        }
    }

    func testApplyStampsMatchingFeaturesAndAppendsOverlay() throws {
        let overlay = try RailHistoryOverlay.decode(Data(overlayJSON.utf8))

        let insideSection = RouteGraph.SectionFeature(
            properties: RouteGraph.SectionProperties(
                lineName: "留萌線", operator: "北海道旅客鉄道"),
            lines: [[Coordinate(lon: 141.5, lat: 43.5), Coordinate(lon: 141.6, lat: 43.6)]])
        let outsideSection = RouteGraph.SectionFeature(
            properties: RouteGraph.SectionProperties(
                lineName: "留萌線", operator: "北海道旅客鉄道"),
            lines: [[Coordinate(lon: 150.0, lat: 50.0)]])

        var sections: [RouteGraph.SectionFeature] = [insideSection, outsideSection]

        let matchingStation = Stations.Feature(
            properties: [
                "line_name": .string("留萌線"), "operator": .string("北海道旅客鉄道"),
            ],
            geometry: Stations.Geometry(type: "Point", coordinates: .array([.number(141.5), .number(43.5)])))
        var stations: [Stations.Feature] = [matchingStation]

        let report = RailHistory.apply(overlay, sections: &sections, stations: &stations)

        // Overlay's own section/station appended.
        XCTAssertEqual(report.sectionsAdded, 1)
        XCTAssertEqual(report.stationsAdded, 1)
        XCTAssertEqual(sections.count, 3)
        XCTAssertEqual(stations.count, 2)

        // Only the inside feature (section + station) got stamped.
        XCTAssertEqual(sections[0].properties.validTo, "2026-04-01")
        XCTAssertNil(sections[1].properties.validTo)
        XCTAssertEqual(stations[0].properties["valid_to"], .string("2026-04-01"))

        XCTAssertEqual(report.retirementsApplied["jp.rumoi.fukagawa-ishikarinumata"], 2)
        XCTAssertEqual(report.unmatchedRetirements, [])
    }

    func testLineStringStationRetirementMatches() throws {
        let overlay = try RailHistoryOverlay.decode(Data(overlayJSON.utf8))
        var sections: [RouteGraph.SectionFeature] = []
        let inside = Stations.Feature(
            properties: [
                "line_name": .string("留萌線"), "operator": .string("北海道旅客鉄道"),
            ],
            geometry: Stations.Geometry(
                type: "LineString",
                coordinates: .array([
                    .array([.number(141.5), .number(43.5)]),
                    .array([.number(141.501), .number(43.501)]),
                ])))
        let outside = Stations.Feature(
            properties: [
                "line_name": .string("留萌線"), "operator": .string("北海道旅客鉄道"),
            ],
            geometry: Stations.Geometry(
                type: "LineString",
                coordinates: .array([
                    .array([.number(150.0), .number(50.0)]),
                    .array([.number(150.001), .number(50.001)]),
                ])))
        var stations: [Stations.Feature] = [inside, outside]

        _ = RailHistory.apply(overlay, sections: &sections, stations: &stations)

        XCTAssertEqual(stations[0].properties["valid_to"], .string("2026-04-01"))
        XCTAssertNil(stations[1].properties["valid_to"])
    }

    func testUnmatchedRetirementIsReported() throws {
        let json = """
        {
          "schema_version": "1",
          "revision": "r1",
          "sections": [], "stations": [],
          "retirements": [
            {
              "history_id": "bogus.retirement",
              "match": { "line_name": "留萌線", "operator": "北海道旅客鉄道", "bbox": [0, 0, 1, 1] },
              "valid_to": "2026-04-01"
            }
          ]
        }
        """
        let overlay = try RailHistoryOverlay.decode(Data(json.utf8))
        var sections: [RouteGraph.SectionFeature] = [
            RouteGraph.SectionFeature(
                properties: RouteGraph.SectionProperties(
                    lineName: "留萌線", operator: "北海道旅客鉄道"),
                lines: [[Coordinate(lon: 141.5, lat: 43.5)]])
        ]
        var stations: [Stations.Feature] = []

        let report = RailHistory.apply(overlay, sections: &sections, stations: &stations)
        XCTAssertEqual(report.unmatchedRetirements, ["bogus.retirement"])
        XCTAssertEqual(report.retirementsApplied["bogus.retirement"], 0)
    }

    func testApplyClassifiesRelocatedHistoricalAndInPlaceClosure() throws {
        let json = """
        {
          "schema_version": "1",
          "revision": "r-phase2",
          "sections": [
            {
              "type": "Feature",
              "properties": {
                "history_id": "ex.old-bit",
                "line_name": "Line A", "operator": "Op",
                "valid_to": "2000-01-01"
              },
              "geometry": { "type": "LineString", "coordinates": [[10.0, 10.0], [10.1, 10.1]] }
            },
            {
              "type": "Feature",
              "properties": {
                "history_id": "ex.closed-span",
                "line_name": "Line C", "operator": "Op",
                "valid_to": "1990-01-01"
              },
              "geometry": { "type": "LineString", "coordinates": [[11.0, 11.0], [11.1, 11.1]] }
            }
          ],
          "stations": [],
          "retirements": [
            {
              "history_id": "ex.new-bit",
              "match": { "line_name": "Line A", "operator": "Op", "bbox": [0, 0, 1, 1] },
              "valid_from": "2000-01-01"
            },
            {
              "history_id": "ex.closed-inplace",
              "match": { "line_name": "Line B", "operator": "Op", "bbox": [2, 2, 3, 3] },
              "valid_to": "2010-01-01"
            }
          ]
        }
        """
        let overlay = try RailHistoryOverlay.decode(Data(json.utf8))
        var sections = [
            RouteGraph.SectionFeature(
                properties: .init(lineName: "Line A", operator: "Op"),
                lines: [[Coordinate(lon: 0.2, lat: 0.2), Coordinate(lon: 0.4, lat: 0.4)]]),
            RouteGraph.SectionFeature(
                properties: .init(lineName: "Line B", operator: "Op"),
                lines: [[Coordinate(lon: 2.2, lat: 2.2), Coordinate(lon: 2.4, lat: 2.4)]]),
        ]
        var stations: [Stations.Feature] = []
        _ = RailHistory.apply(overlay, sections: &sections, stations: &stations)

        XCTAssertEqual(sections[0].properties.temporalKind, .relocatedNew)
        XCTAssertEqual(sections[0].properties.historyId, "ex.new-bit")
        XCTAssertEqual(sections[0].properties.validFrom, "2000-01-01")
        XCTAssertEqual(sections[1].properties.temporalKind, .current)
        XCTAssertNil(sections[1].properties.historyId)
        XCTAssertEqual(sections[1].properties.validTo, "2010-01-01")
        XCTAssertEqual(sections[2].properties.temporalKind, .relocatedOld)
        XCTAssertEqual(sections[2].properties.historyId, "ex.old-bit")
        XCTAssertEqual(sections[3].properties.temporalKind, .historical)
        XCTAssertEqual(sections[3].properties.historyId, "ex.closed-span")
    }

    func testSolvedSectionCarriesNonCurrentEdgeKindAndHistoryID() throws {
        let start = Coordinate(lon: 135.0, lat: 35.0)
        let end = Coordinate(lon: 135.02, lat: 35.0)
        let feature = RouteGraph.SectionFeature(
            properties: .init(
                lineName: "L", operator: "O",
                validFrom: "2000-01-01", validTo: "2099-01-01",
                historyId: "ex.edge", temporalKind: .historical),
            lines: [[start, end]])
        func station(_ name: String, _ coordinate: Coordinate) -> Stations.Feature {
            Stations.Feature(
                properties: [
                    "station_name": .string(name),
                    "line_name": .string("L"),
                    "operator": .string("O"),
                ],
                geometry: .init(
                    type: "Point",
                    coordinates: .array([.number(coordinate.lon), .number(coordinate.lat)])))
        }
        let stations = Stations.Index(.init(features: [
            station("A", start), station("B", end),
        ]))
        let solved = try XCTUnwrap(RouteSolver.solveSection(
            RouteSection(from: "A", to: "B", lineNames: ["L"]),
            segmentIndex: 0,
            train: .init(
                id: "provenance", number: "", trainType: "", company: "",
                origin: "A", destination: "B", preferredLineNames: [],
                preferredOperatorNames: [], allowedInstitutionTypeCodes: nil,
                institutionFilterMode: "soft", rideDate: "2015-08-01"),
            country: "jp",
            graph: RouteGraph.build(from: [feature]),
            stations: stations))
        XCTAssertEqual(solved.temporalKind, .historical)
        XCTAssertEqual(solved.historyIDs, ["ex.edge"])
        XCTAssertEqual(solved.validFrom, "2000-01-01")
        XCTAssertEqual(solved.validTo, "2099-01-01")
    }

    func testMixedEdgesKeepTheMostSpecificKind() {
        func edge(
            _ kind: RouteGraph.TemporalKind, ids: [String],
            from: String? = nil, to: String? = nil
        ) -> RouteGraph.Edge {
            RouteGraph.Edge(
                to: "B", length: 1, institutionTypeCode: "", railwayClassCode: "",
                lineName: "", operator: "", connector: nil,
                validFrom: from, validTo: to, historyIDs: ids, temporalKind: kind)
        }
        let mixed = RouteGraph.TemporalProvenance.aggregate(edges: [
            edge(.current, ids: ["b"]),
            edge(.historical, ids: ["a"], from: "2001-01-01", to: "2010-01-01"),
            edge(.relocatedNew, ids: ["b"], from: "2005-01-01", to: "2008-01-01"),
        ])
        XCTAssertEqual(mixed.temporalKind, .relocatedNew)
        XCTAssertEqual(mixed.historyIDs, ["a", "b"])
        XCTAssertEqual(mixed.validFrom, "2005-01-01")
        XCTAssertEqual(mixed.validTo, "2008-01-01")
        let oldWins = RouteGraph.TemporalProvenance.aggregate(edges: [
            edge(.relocatedNew, ids: []),
            edge(.relocatedOld, ids: ["ex.old-bit"]),
            edge(.current, ids: []),
        ])
        XCTAssertEqual(oldWins.temporalKind, .relocatedOld)
        XCTAssertNotEqual(oldWins.temporalKind, .current)
    }

    func testExistingHistorySectionSolverBoundsStayTheLegacyPair() throws {
        let root = try PortFixtures.repositoryRoot()
        let overlay = try RailHistoryOverlay.load(
            from: root.appending(path: "app/data/rail-history.json"))
        let section = try XCTUnwrap(overlay.sections.first {
            $0.properties.historyId == "jp.jrh.rumoi.rumoi-mashike"
        })
        XCTAssertNil(section.properties.validFrom)
        XCTAssertEqual(section.properties.validTo, "2016-12-05")
        let edges = RouteGraph.build(from: [section]).adjacency.values.flatMap { $0 }
        XCTAssertFalse(edges.isEmpty)
        for edge in edges {
            XCTAssertNil(edge.validFrom)
            XCTAssertEqual(edge.validTo, "2016-12-05")
        }
    }

    func testServiceValidityIsWhatTheSolverReads() throws {
        let json = """
        {
          "schema_version": "1", "revision": "r",
          "sections": [{
            "properties": {
              "history_id": "svc", "N02_003": "L", "N02_004": "O",
              "valid_from": "2000-01-01", "valid_to": "2020-01-01",
              "service_validity": ["2010-01-01", "2011-01-01"],
              "infrastructure_validity": ["2000-01-01", "2020-01-01"],
              "kind": "suspension"
            },
            "geometry": { "type": "LineString", "coordinates": [[0, 0], [1, 0]] }
          }],
          "stations": [{
            "properties": {
              "history_id": "infra-only", "station_name": "S",
              "line_name": "L", "operator": "O",
              "infrastructure_validity": [null, "2019-11-01"],
              "kind": "suspension"
            },
            "geometry": { "type": "Point", "coordinates": [0, 0] }
          }],
          "retirements": []
        }
        """
        let overlay = try RailHistoryOverlay.decode(Data(json.utf8))
        XCTAssertEqual(overlay.sections[0].properties.validFrom, "2010-01-01")
        XCTAssertEqual(overlay.sections[0].properties.validTo, "2011-01-01")
        let edge = try XCTUnwrap(RouteGraph.build(from: overlay.sections).adjacency.values.flatMap { $0 }.first)
        XCTAssertEqual(edge.validFrom, "2010-01-01")
        XCTAssertEqual(edge.validTo, "2011-01-01")
        XCTAssertNil(Stations.stationValidFrom(overlay.stations[0]))
        XCTAssertEqual(Stations.stationValidTo(overlay.stations[0]), "2019-11-01")
    }

    func testRejectsUnknownKindAndBadDomainPair() {
        let badKind = overlayJSON.replacingOccurrences(
            of: "\"valid_to\": \"2016-12-05\"",
            with: "\"valid_to\": \"2016-12-05\", \"kind\": \"brt\"")
        XCTAssertThrowsError(try RailHistoryOverlay.decode(Data(badKind.utf8)))
        let badPair = overlayJSON.replacingOccurrences(
            of: "\"valid_to\": \"2016-12-05\"",
            with: "\"service_validity\": [\"2020-01-01\", \"2019-01-01\"]")
        XCTAssertThrowsError(try RailHistoryOverlay.decode(Data(badPair.utf8)))
    }

    func testStationTargetDoesNotDateTheOpenLine() throws {
        let json = """
        {
          "schema_version": "1", "revision": "r",
          "sections": [], "stations": [],
          "retirements": [{
            "history_id": "open.station",
            "kind": "station_opening",
            "match": {
              "line_name": "L", "operator": "O",
              "bbox": [0, 0, 1, 1], "targets": ["stations"]
            },
            "valid_from": "2011-01-01"
          }]
        }
        """
        let overlay = try RailHistoryOverlay.decode(Data(json.utf8))
        var sections = [RouteGraph.SectionFeature(
            properties: .init(lineName: "L", operator: "O"),
            lines: [[Coordinate(lon: 0.2, lat: 0.2), Coordinate(lon: 0.3, lat: 0.2)]])]
        var stations = [Stations.Feature(
            properties: [
                "line_name": .string("L"), "operator": .string("O"),
                "station_name": .string("S"),
            ],
            geometry: .init(type: "Point", coordinates: .array([.number(0.2), .number(0.2)])))]
        let report = RailHistory.apply(overlay, sections: &sections, stations: &stations)
        XCTAssertNil(sections[0].properties.validFrom)
        XCTAssertEqual(stations[0].properties["valid_from"], .string("2011-01-01"))
        XCTAssertEqual(report.retirementsApplied["open.station"], 1)
    }

    func testShouldCanonicalizeDisplayNetworkOnlyForCurrent() {
        XCTAssertTrue(RouteGraph.TemporalKind.shouldCanonicalizeDisplayNetwork(.current))
        XCTAssertFalse(RouteGraph.TemporalKind.shouldCanonicalizeDisplayNetwork(.historical))
        XCTAssertFalse(RouteGraph.TemporalKind.shouldCanonicalizeDisplayNetwork(.relocatedOld))
        XCTAssertFalse(RouteGraph.TemporalKind.shouldCanonicalizeDisplayNetwork(.relocatedNew))
    }
}
