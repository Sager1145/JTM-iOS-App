import Foundation
import Testing
@testable import RailCore

struct KeishinDisplayCurveTests {
    @Test("Keishin rounded display curve preserves the physical N02 interval and other display intervals")
    func physicalAndDisplayGeometryRemainSeparate() throws {
        let root = try PortFixtures.repositoryRoot()
        let loaded = try DisplayParts.LoadedPackage.load(
            contentsOf: root.appending(path: "app/public/rail/jp-2025.json"))
        let line = try #require(loaded.package.lines.first { $0.id == "jp-京阪電気鉄道-京津線" })
        let physical = CompactPackage.decodeIntervals(line)
        let display = CompactPackage.decodeDisplayIntervals(line)
        let override = try #require(line.displayIntervalCoordinates[4])
        let n02Apex = Coordinate(lon: 135.85919, lat: 35.00058)
        let start = Coordinate(lon: 135.85879, lat: 35.00019)
        let end = Coordinate(lon: 135.85877, lat: 35.00142)
        let surveyedCurve = [
            Coordinate(lon: 135.8588544, lat: 35.0002907),
            Coordinate(lon: 135.8588961, lat: 35.0003642),
            Coordinate(lon: 135.8589369, lat: 35.0004617),
            Coordinate(lon: 135.8589583, lat: 35.000544),
            Coordinate(lon: 135.8589637, lat: 35.0006217),
            Coordinate(lon: 135.8589557, lat: 35.0007271),
            Coordinate(lon: 135.8589246, lat: 35.0008753),
            Coordinate(lon: 135.8588923, lat: 35.0009618),
            Coordinate(lon: 135.8588502, lat: 35.0010637),
            Coordinate(lon: 135.8588288, lat: 35.0011158),
            Coordinate(lon: 135.8587988, lat: 35.0011888),
            Coordinate(lon: 135.8587602, lat: 35.0012836),
            Coordinate(lon: 135.8587231, lat: 35.0013891),
        ]
        #expect(Set(line.displayIntervalCoordinates.keys) == [4])
        #expect(physical[4].contains(n02Apex))
        #expect(line.segments[4].distanceKm == 1.655)
        #expect(line.stations[4].id == "006037")
        #expect(line.stations[5].id == "005987")
        #expect(!override.contains(n02Apex))
        let first = try #require(physical[4].firstIndex(of: start))
        let last = try #require(physical[4].firstIndex(of: end))
        #expect(override == Array(physical[4][...first]) + surveyedCurve + Array(physical[4][last...]))
        #expect(display[4] == override)
        #expect(display[4].first == line.stations[4].coordinate)
        #expect(display[4].last == line.stations[5].coordinate)
        for index in physical.indices where index != 4 {
            #expect(display[index] == physical[index], "Unchanged Keishin interval \(index)")
        }
    }
}
