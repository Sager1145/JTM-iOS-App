import XCTest
@testable import RailCore

final class DatasetManifestIndexTests: XCTestCase {
    private func decode(_ json: String) throws -> DatasetManifestIndex {
        try JSONDecoder().decode(DatasetManifestIndex.self, from: Data(json.utf8))
    }

    func testLegacyManifestRequestsPartScan() throws {
        let manifest = try decode(#"{"parts":["part-002","part-000"]}"#)
        XCTAssertEqual(manifest.parts, ["part-002", "part-000"])
        XCTAssertNil(manifest.indexedParts)
    }

    func testCompleteMapUsesManifestPositionsAndPreservesDuplicateTrainIDs() throws {
        let manifest = try decode(#"{"parts":["part-002","part-000","part-001"],"part_train_ids":{"part-001":"shared","part-000":"other","part-002":"shared"}}"#)
        XCTAssertEqual(manifest.indexedParts?["shared"], [
            .init(name: "part-002", position: 0),
            .init(name: "part-001", position: 2),
        ])
        XCTAssertEqual(manifest.indexedParts?["other"], [.init(name: "part-000", position: 1)])
    }

    func testMalformedOrIncompleteMapRequestsPartScan() throws {
        let maps = [
            "null", "[]", #""incorrect""#,
            #"{"part-000":5,"part-001":"second"}"#,
            #"{"part-000":"first"}"#,
            #"{"part-000":"first","unexpected":"second"}"#,
            #"{"part-000":"first","part-001":"second","extra":"third"}"#,
            #"{"part-000":"","part-001":"second"}"#,
            #"{"part-000":" \n ","part-001":"second"}"#,
        ]
        for map in maps {
            let manifest = try decode("{\"parts\":[\"part-000\",\"part-001\"],\"part_train_ids\":\(map)}")
            XCTAssertNil(manifest.indexedParts, map)
            XCTAssertEqual(manifest.parts, ["part-000", "part-001"])
        }
    }
}
