import Foundation
import Testing
@testable import RailInspection

struct AreaSelectionTests {
    private func decode(_ json: String) throws -> AreaSelection {
        try JSONDecoder().decode(AreaSelection.self, from: Data(json.utf8))
    }

    @Test func fourKindsRoundTripThroughJSON() throws {
        let cases: [(String, AreaSelection)] = [
            (#"{"kind":"rect","minLon":131.42,"minLat":33.47,"maxLon":131.48,"maxLat":33.51,"marginMetres":250}"#,
             .init(mode: .rect(minLon: 131.42, minLat: 33.47, maxLon: 131.48, maxLat: 33.51), marginMetres: 250)),
            (#"{"kind":"stationPair","lineID":"jp-a","fromStationID":"009241","toStationID":"009262"}"#,
             .init(mode: .stationPair(lineID: "jp-a", fromStationID: "009241", toStationID: "009262"))),
            (#"{"kind":"lineSection","lineID":"jp-a","firstInterval":26,"lastInterval":27}"#,
             .init(mode: .lineSection(lineID: "jp-a", firstInterval: 26, lastInterval: 27))),
            (#"{"kind":"centre","lon":131.45,"lat":33.49,"radiusMetres":1200}"#,
             .init(mode: .centre(lon: 131.45, lat: 33.49, radiusMetres: 1200)))
        ]
        for (json, expected) in cases {
            let decoded = try decode(json)
            #expect(decoded == expected)
            try decoded.validate()
            let again = try JSONDecoder().decode(AreaSelection.self, from: JSONEncoder().encode(decoded))
            #expect(again == expected)
        }
        #expect(try decode(cases[1].0).marginMetres == 500)
    }

    @Test func unknownAndForeignKeysAreRejected() {
        #expect(throws: DecodingError.self) {
            try decode(#"{"kind":"centre","lon":1,"lat":2,"radiusMetres":3,"zoom":17}"#)
        }
        // A key that belongs to another kind is still unknown here.
        #expect(throws: DecodingError.self) {
            try decode(#"{"kind":"rect","minLon":1,"minLat":2,"maxLon":3,"maxLat":4,"lineID":"a"}"#)
        }
        #expect(throws: DecodingError.self) { try decode(#"{"kind":"polygon"}"#) }
        #expect(throws: DecodingError.self) { try decode(#"{"kind":"stationPair","lineID":"a","fromStationID":"1"}"#) }
    }

    @Test func validateRejectsBadValues() {
        let bad: [AreaSelection] = [
            .init(mode: .rect(minLon: 2, minLat: 1, maxLon: 1, maxLat: 2)),
            .init(mode: .rect(minLon: .nan, minLat: 1, maxLon: 2, maxLat: 2)),
            .init(mode: .centre(lon: 1, lat: 1, radiusMetres: 0)),
            .init(mode: .centre(lon: 1, lat: 1, radiusMetres: 20_001)),
            .init(mode: .centre(lon: 1, lat: 91, radiusMetres: 10)),
            .init(mode: .centre(lon: 1, lat: 1, radiusMetres: 10), marginMetres: 5_001),
            .init(mode: .centre(lon: 1, lat: 1, radiusMetres: 10), marginMetres: -1),
            .init(mode: .lineSection(lineID: "a", firstInterval: 3, lastInterval: 2)),
            .init(mode: .lineSection(lineID: "a", firstInterval: -1, lastInterval: 2)),
            .init(mode: .lineSection(lineID: " ", firstInterval: 0, lastInterval: 2)),
            .init(mode: .stationPair(lineID: "a", fromStationID: "", toStationID: "b")),
            .init(mode: .stationPair(lineID: "a", fromStationID: "b", toStationID: "b"))
        ]
        for selection in bad {
            #expect(throws: DiagnosticError.self) { try selection.validate() }
        }
    }

    @Test func shorthandParses() throws {
        #expect(try AreaSelection.parse(shorthand: "stations:jp-九州旅客鉄道-日豊線:009241-009262")
                == .init(mode: .stationPair(lineID: "jp-九州旅客鉄道-日豊線", fromStationID: "009241", toStationID: "009262")))
        #expect(try AreaSelection.parse(shorthand: "line:jp-a:26-27@100")
                == .init(mode: .lineSection(lineID: "jp-a", firstInterval: 26, lastInterval: 27), marginMetres: 100))
        #expect(try AreaSelection.parse(shorthand: "centre:131.45,33.49,800").mode == .centre(lon: 131.45, lat: 33.49, radiusMetres: 800))
        #expect(throws: DiagnosticError.self) { try AreaSelection.parse(shorthand: "rect:1,2,3") }
        #expect(throws: DiagnosticError.self) { try AreaSelection.parse(shorthand: "polygon:1") }
    }
}
