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
}
