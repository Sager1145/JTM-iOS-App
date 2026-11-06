import XCTest
@testable import RailCore

final class RailHistoryStationsTests: XCTestCase {
    private func overlay(_ stationsJSON: String) throws -> RailHistoryOverlay {
        let json = """
        {
          "schema_version": "1",
          "revision": "2026-09-23.1",
          "sections": [],
          "stations": [\(stationsJSON)],
          "retirements": []
        }
        """
        return try RailHistoryOverlay.decode(Data(json.utf8))
    }

    private func mashikeFeature(
        historyId: String = "jp.rumoi.mashike", validFrom: String? = nil,
        validTo: String = "2016-12-05", n02Code: String? = nil, basis: String? = nil
    ) -> String {
        var props = """
        "history_id": "\(historyId)",
            "station_name": "増毛", "line_name": "留萌線", "operator": "北海道旅客鉄道",
            "valid_to": "\(validTo)"
        """
        if let validFrom {
            props += ",\n            \"valid_from\": \"\(validFrom)\""
        }
        if let n02Code {
            props += ",\n            \"n02_station_code\": \"\(n02Code)\""
        }
        if let basis {
            props += ",\n            \"station_code_basis\": \"\(basis)\""
        }
        return """
        {
          "type": "Feature",
          "properties": { \(props) },
          "geometry": { "type": "Point", "coordinates": [141.1, 43.1] }
        }
        """
    }

    func testUndatedEmptyGarbageDateNotOpen() throws {
        let overlay = try overlay(mashikeFeature())
        let directory = RailHistoryStations.directory(overlay)
        XCTAssertEqual(directory.count, 1)
        let station = directory[0]
        XCTAssertFalse(station.isOpen(on: nil))
        XCTAssertFalse(station.isOpen(on: ""))
        XCTAssertFalse(station.isOpen(on: "not-a-date"))
    }

    func testHalfOpenBoundary() throws {
        let overlay = try overlay(mashikeFeature(validTo: "2016-12-05"))
        let directory = RailHistoryStations.directory(overlay)
        let station = directory[0]
        XCTAssertTrue(station.isOpen(on: "2016-12-04"))
        XCTAssertFalse(station.isOpen(on: "2016-12-05"))
    }

    func testValidFromLowerBound() throws {
        let overlay = try overlay(
            mashikeFeature(validFrom: "2010-01-01", validTo: "2016-12-05"))
        let directory = RailHistoryStations.directory(overlay)
        let station = directory[0]
        XCTAssertFalse(station.isOpen(on: "2009-12-31"))
        XCTAssertTrue(station.isOpen(on: "2010-01-01"))
        XCTAssertTrue(station.isOpen(on: "2016-12-04"))
        XCTAssertFalse(station.isOpen(on: "2016-12-05"))
    }

    func testTwoFeaturesSameNameLineOperatorMergeIntoOnePeriodList() throws {
        let feature1 = mashikeFeature(historyId: "jp.rumoi.mashike.1", validTo: "2010-01-01")
        let feature2 = mashikeFeature(historyId: "jp.rumoi.mashike.2", validTo: "2016-12-05")
        let overlay = try overlay("\(feature1), \(feature2)")
        let directory = RailHistoryStations.directory(overlay)
        XCTAssertEqual(directory.count, 1)
        let station = directory[0]
        XCTAssertEqual(station.periods.count, 2)
        XCTAssertEqual(station.id, RailHistoryStations.codePrefix + "jp.rumoi.mashike.1")
        XCTAssertTrue(station.isOpen(on: "2009-01-01"))
        XCTAssertTrue(station.isOpen(on: "2016-01-01"))
        XCTAssertFalse(station.isOpen(on: "2016-12-05"))
    }

    func testCertifiedCodeOnlyWhenBasisMatches() throws {
        let withBasis = mashikeFeature(
            historyId: "jp.rumoi.mashike.a", n02Code: "123456",
            basis: "exact_current_geometry_identity")
        let withoutBasis = mashikeFeature(
            historyId: "jp.rumoi.mashike.b", n02Code: "654321")

        let overlayWithBasis = try overlay(withBasis)
        let directoryWithBasis = RailHistoryStations.directory(overlayWithBasis)
        XCTAssertEqual(directoryWithBasis[0].certifiedCode, "123456")

        let overlayWithoutBasis = try overlay(withoutBasis)
        let directoryWithoutBasis = RailHistoryStations.directory(overlayWithoutBasis)
        XCTAssertNil(directoryWithoutBasis[0].certifiedCode)
    }

    func testIsHistoryCode() {
        XCTAssertTrue(RailHistoryStations.isHistoryCode("history:jp.rumoi.mashike"))
        XCTAssertFalse(RailHistoryStations.isHistoryCode("123456"))
        XCTAssertFalse(RailHistoryStations.isHistoryCode(nil))
    }
}
