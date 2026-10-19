import Foundation
import Testing
@testable import RailCore

struct LineServiceCatalogTests {
    @Test func bundledCatalogRetainsOnlySuccessfulDecode() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "line-catalog-\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "line-service-catalog.json")
        try Data("invalid json".utf8).write(to: url)
        let bundle = try #require(Bundle(url: directory))
        #expect(throws: (any Error).self) { try LineServiceCatalog.loadBundled(bundle: bundle) }
        let data = Data(#"{"schemaVersion":1,"inventoryVersion":"fixture","observedOn":"2026-10-01","lines":[],"trips":[]}"#.utf8)
        try data.write(to: url)
        let first = try LineServiceCatalog.loadBundled(bundle: bundle)
        try Data("broken after the immutable snapshot loaded".utf8).write(to: url)
        let second = try LineServiceCatalog.loadBundled(bundle: bundle)
        #expect(first.inventoryVersion == "fixture")
        #expect(second.inventoryVersion == first.inventoryVersion)
    }

    @Test func nationalInventoryHasExplicitUnknowns() throws {
        let catalog = try LineServiceCatalog.loadBundled()
        #expect(catalog.lines.count == 658)
        #expect(Set(catalog.lines.map(\.lineID)).count == catalog.lines.count)
        #expect(catalog.lines.contains { $0.coverage == .unknown && $0.kinds.isEmpty })
        #expect(catalog.lines.allSatisfy { $0.kinds.isEmpty == ($0.coverage == .unknown) })
        #expect(catalog.coverage(lineID: "not-a-line") == nil)
    }

    @Test func classesUseExactLineAndOperatorIdentity() throws {
        let catalog = try LineServiceCatalog.loadBundled()
        let lineID = "jp-西日本旅客鉄道-東海道線"
        let classes = Set(catalog.serviceKinds(lineID: lineID, operatorName: "西日本旅客鉄道").map(\.trainType))
        #expect(classes.isSuperset(of: ["普通", "快速", "新快速"]))
        #expect(catalog.coverage(lineID: lineID, operatorName: "東日本旅客鉄道") == nil)
        // Osaka–Fukushima physical branch has no inferred JR Kyoto rapid classes.
        #expect(!catalog.serviceKinds(lineID: "jp-西日本旅客鉄道-東海道線-2").contains { $0.trainType == "新快速" })
        #expect(catalog.coverage(lineID: lineID)?.aliases.contains("JR京都線") == true)
    }

    @Test func researchedRegionalAndOperatingClassesAreScoped() throws {
        let catalog = try LineServiceCatalog.loadBundled()
        let airport = catalog.serviceKinds(lineID: "jp-北海道旅客鉄道-千歳線")
        #expect(Set(airport.map(\.trainType)).isSuperset(of: ["普通", "快速", "特別快速", "区間快速"]))
        #expect(airport.filter { $0.trainType == "特別快速" }.allSatisfy {
            $0.fromStationCode != nil && $0.toStationCode != nil
        })
        #expect(catalog.serviceKinds(lineID: "jp-四国旅客鉄道-本四備讃線").contains { $0.trainType == "快速" })
        let js = catalog.serviceKinds(lineID: "jp-東日本旅客鉄道-大崎支線")
        #expect(Set(js.map(\.trainType)).isSuperset(of: ["普通", "快速", "特別快速"]))
        #expect(!catalog.serviceKinds(lineID: "jp-東日本旅客鉄道-横須賀線").contains { $0.trainType == "特別快速" })
        #expect(catalog.serviceKinds(lineID: "jp-仙台空港鉄道-仙台空港線").contains { $0.trainType == "普通" })
        #expect(catalog.serviceKinds(lineID: "jp-山陽電気鉄道-本線").contains { $0.trainType == "直通特急" })
    }

    @Test func validityNeverExtrapolatesAnObservation() throws {
        let catalog = try LineServiceCatalog.loadBundled()
        let rapid = try #require(catalog.serviceKinds(lineID: "jp-西日本旅客鉄道-東海道線")
            .first { $0.trainType == "快速" })
        #expect(rapid.applies(on: "2026-03-14"))
        #expect(!rapid.applies(on: "2026-10-03"))
        #expect(!rapid.applies(on: "2026-02-30"))
        #expect(!rapid.applies(on: "2026-3-14"))
        #expect(catalog.serviceKinds(lineID: "jp-西日本旅客鉄道-湖西線", serviceDate: "1900-01-01").isEmpty)
    }

    @Test func timetableUsesOnlyExplicitServiceDates() throws {
        let catalog = try LineServiceCatalog.loadBundled()
        let lineID = "jp-西日本旅客鉄道-東海道線"
        let trips = catalog.timetableTrips(lineID: lineID, serviceDate: "2026-10-04")
        #expect(Set(trips.map(\.trainType)).isSuperset(of: ["普通", "新快速", "快速"]))
        #expect(catalog.timetableTrips(lineID: lineID, serviceDate: "2026-10-11").isEmpty)
        let local = try #require(trips.first { $0.trainNumber == "102C" })
        #expect(local.coverage == .partial)
        #expect(local.stops.count == 2)
        #expect(local.stops.first?.departureSeconds == 6 * 3600 + 12 * 60)
        #expect(local.stops.last?.stationName == "新大阪")
        let rapid = try #require(trips.first { $0.trainNumber == "3408M" })
        #expect(rapid.stops.last?.arrivalSeconds == 7 * 3600 + 59 * 60)
    }

    @Test func reviewedPublicInputsRetainDatedCallsAndThroughNumberChanges() throws {
        let catalog = try LineServiceCatalog.loadBundled()
        let ordinary = try #require(catalog.trips.first { $0.trainNumber == "1541E" })
        #expect(ordinary.serviceDates == ["2026-10-02"])
        #expect(ordinary.trainType == "普通")
        #expect(ordinary.stops.count >= 3)
        let parent = try #require(catalog.trips.first { $0.trainNumber == "3438M" })
        let child = try #require(catalog.trips.first { $0.trainNumber == "3138M" })
        #expect(parent.nextTrainIDs?.contains(child.id) == true)
        #expect(child.previousTrainIDs?.contains(parent.id) == true)
        #expect(parent.serviceDates == child.serviceDates)
        #expect(parent.stops.last?.stationCode == child.stops.first?.stationCode)
        #expect(catalog.continuations(for: parent).contains { $0.id == child.id })
        let meitetsu = try #require(catalog.trips.first { $0.trainNumber == "645B" })
        #expect(meitetsu.trainType == "準急")
        #expect(meitetsu.serviceDates == ["2026-10-02"])
    }

    @Test func continuationsRequireExplicitIdentitySharedDateAndEndpoint() throws {
        func trip(_ id: String, from: String = "B", date: String = "2026-10-01") -> [String: Any] {
            ["id": id, "trainNumber": id, "trainType": "local", "operatorName": "Operator",
             "lineIDs": [], "serviceDates": [date], "sourceURL": "https://example.com/timetable",
             "coverage": "partial", "note": "", "stops": [
                ["stationCode": from, "stationName": from, "departureSeconds": 0],
                ["stationCode": "B", "stationName": "B", "arrivalSeconds": 60]
             ]]
        }
        var parent = trip("parent", from: "A")
        parent["nextTrainIDs"] = ["later", "wrong-date", "wrong-endpoint", "missing", "first", "first"]
        let data = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1, "inventoryVersion": "fixture", "observedOn": "2026-10-01", "lines": [],
            "trips": [parent, trip("first"), trip("later"), trip("wrong-date", date: "2026-10-02"),
                      trip("wrong-endpoint", from: "C"), trip("unlinked")]
        ])
        let catalog = try LineServiceCatalog(data: data)
        let reopened = try JSONDecoder().decode(LineServiceCatalog.self, from: JSONEncoder().encode(catalog))
        for value in [catalog, reopened] {
            let parent = try #require(value.trips.first { $0.id == "parent" })
            #expect(value.continuations(for: parent).map(\.id) == ["first", "later"])
            let unlinked = try #require(value.trips.first { $0.id == "unlinked" })
            #expect(value.continuations(for: unlinked).isEmpty)
        }
    }

    @Test func importerRejectsInvalidTimesAndDuplicateIdentities() throws {
        let source = try LineServiceCatalog.loadBundled()
        let encoder = JSONEncoder()
        let encoded = try encoder.encode(source)
        var artifact = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var trips = try #require(artifact["trips"] as? [[String: Any]])
        var stops = try #require(trips[0]["stops"] as? [[String: Any]])
        stops[1]["arrivalSeconds"] = 1
        trips[0]["stops"] = stops
        artifact["trips"] = trips
        let invalid = try JSONSerialization.data(withJSONObject: artifact)
        #expect(throws: LineServiceCatalog.CatalogError.self) { try LineServiceCatalog(data: invalid) }
        var duplicate = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var lines = try #require(duplicate["lines"] as? [[String: Any]])
        lines.append(lines[0]); duplicate["lines"] = lines
        let duplicateData = try JSONSerialization.data(withJSONObject: duplicate)
        #expect(throws: LineServiceCatalog.CatalogError.self) { try LineServiceCatalog(data: duplicateData) }
    }
}
