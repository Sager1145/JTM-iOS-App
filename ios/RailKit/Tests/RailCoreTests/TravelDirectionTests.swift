import Foundation
import Testing
@testable import RailCore

struct TravelDirectionTests {
    @Test("A missing or malformed calibration resource cannot authorize fallback direction")
    func calibrationFailureDoesNotUseAlternativeInference() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "direction-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let package = try fixture([line("main", ["A", "B"], kilometers: 10, order: "down",
            operatorName: "東日本旅客鉄道", coordinates: [(139.7671, 35.6812), (130.0, 35.0)])])
        let contents: [String?] = [nil, "invalid json", #"{"main":{"downSign":0}}"#]
        for (index, contents) in contents.enumerated() {
            let directory = root.appending(path: "case-\(index).bundle")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let contents {
                try Data(contents.utf8).write(to: directory.appending(path: "line-direction-calibration.json"))
            }
            let bundle = try #require(Bundle(url: directory))
            #expect(throws: (any Error).self) {
                try TravelDirection.infer(train: ride(["A", "B"]), package: package, calibrationBundle: bundle)
            }
        }
    }

    @Test("A successfully loaded table without this line retains explicit and JR direction inference")
    func successfulUncalibratedTableRetainsInference() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "direction-\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("{}".utf8).write(to: directory.appending(path: "line-direction-calibration.json"))
        let bundle = try #require(Bundle(url: directory))
        for order in [String?.some("down"), nil] {
            let package = try fixture([line("main", ["A", "B"], kilometers: 10, order: order,
                operatorName: "東日本旅客鉄道", coordinates: [(139.7671, 35.6812), (130.0, 35.0)])])
            let result = try #require(try TravelDirection.infer(
                train: ride(["A", "B"]), package: package, calibrationBundle: bundle))
            #expect(result.direction == .down)
        }
    }

    @Test("A station id is placed by its registry codes and does not fall back to the stored name")
    func stationIDPrefersRegistryCodes() throws {
        let package = try fixture([line("main", ["A", "B"], kilometers: 10, order: "down")])
        let byCode = ride(["B", "A"])
        let reverse = try #require(try TravelDirection.infer(train: byCode, package: package))
        #expect(reverse.direction == .up)
        try RegistryIdentityTestGate.withProvider({ region in
            guard region == "jp" else { return nil }
            return RegistryIdentity(bundle: RegistryBundle(
                region: "jp", run: 1,
                stations: [
                    "st:jp:1": RegistryStationRecord(
                        cx: "cx:jp:1", group: "A", codes: ["A"], op: "op:jp:1", name: "A", lines: []),
                    "st:jp:2": RegistryStationRecord(
                        cx: "cx:jp:1", group: "B", codes: ["B"], op: "op:jp:1", name: "B", lines: []),
                ]))
        }) {
            var byID = byCode
            byID.stops[0].stationID = "st:jp:1"
            byID.stops[1].stationID = "st:jp:2"
            let forward = try #require(try TravelDirection.infer(train: byID, package: package))
            #expect(forward.direction == .down)
            byID.stops[0].stationID = "st:jp:missing"
            #expect(try TravelDirection.infer(train: byID, package: package) == nil)
        }
    }

    @Test("An explicit down station order calls forward travel down and reverse travel up")
    func explicitDown() throws {
        let package = try fixture([line("main", ["A", "B", "C", "D"], kilometers: 10, order: "down")])
        let forward = try #require(try TravelDirection.infer(train: ride(["A", "B", "C", "D"]), package: package))
        #expect(forward.direction == .down)
        #expect(forward.lineID == "main")
        #expect(forward.kilometers == 30)
        let reverse = try #require(try TravelDirection.infer(train: ride(["D", "C", "B", "A"]), package: package))
        #expect(reverse.direction == .up)
        #expect(reverse.kilometers == 30)
    }

    @Test("A non-JR line with no up or down order casts no vote")
    func missingOrderDoesNotVote() throws {
        for order in [String?.none, "unassigned"] {
            let package = try fixture([line("main", ["A", "B", "C", "D"], kilometers: 10, order: order)])
            #expect(try TravelDirection.infer(train: ride(["A", "B", "C", "D"]), package: package) == nil)
        }
    }

    @Test("An explicit up station order flips the word")
    func explicitUp() throws {
        let package = try fixture([line("main", ["A", "B", "C"], kilometers: 5, order: "up")])
        let forward = try #require(try TravelDirection.infer(train: ride(["A", "B", "C"]), package: package))
        #expect(forward.direction == .up)
        #expect(forward.kilometers == 10)
        let reverse = try #require(try TravelDirection.infer(train: ride(["C", "B", "A"]), package: package))
        #expect(reverse.direction == .down)
    }

    @Test("The heavier direction wins at 60 percent, and a tie or a minority loses")
    func majority() throws {
        let lines = [
            line("long", ["A", "B", "C", "D", "E", "F", "G"], kilometers: 1, order: "down"),
            line("short", ["G", "H", "I", "J", "K"], kilometers: 1, order: "up"),
        ]
        let winner = try #require(try TravelDirection.infer(
            train: ride(["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K"]),
            package: try fixture(lines)))
        // 6 km down on long, 4 km up on short. 6/10 is exactly the threshold.
        #expect(winner.direction == .down)
        #expect(winner.lineID == "long")
        #expect(winner.kilometers == 6)

        let tied = try fixture([
            line("east", ["A", "B", "C", "D", "E", "F"], kilometers: 1, order: "down"),
            line("west", ["F", "G", "H", "I", "J", "K"], kilometers: 1, order: "up"),
        ])
        #expect(try TravelDirection.infer(train: ride(["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K"]), package: tied) == nil)

        let minority = try fixture([
            line("east", ["A", "B", "C", "D", "E", "F"], kilometers: 1, order: "down"),
            line("west", ["F", "G", "H", "I", "J"], kilometers: 1, order: "up"),
        ])
        // 5 down versus 4 up is 5/9, under 60%.
        #expect(try TravelDirection.infer(train: ride(["A", "B", "C", "D", "E", "F", "G", "H", "I", "J"]), package: minority) == nil)
    }

    @Test("A loop, including a line named 環状, does not vote")
    func loopsAreNil() throws {
        let looped = try fixture([line("circle", ["A", "B", "C", "D"], kilometers: 3, loop: true)])
        #expect(try TravelDirection.infer(train: ride(["A", "B", "C"]), package: looped) == nil)
        let named = try fixture([line("大阪環状線", ["A", "B", "C", "D"], kilometers: 3)])
        #expect(try TravelDirection.infer(train: ride(["A", "C"]), package: named) == nil)
    }

    @Test("Alignment that forbids the traveled sign contributes no distance")
    func alignmentFilter() throws {
        let blocked = try fixture([
            line("main", ["A", "B", "C", "D"], kilometers: 8, order: "down", alignment: "up"),
        ])
        #expect(try TravelDirection.infer(train: ride(["A", "B", "C", "D"]), package: blocked) == nil)
        let reverse = try #require(try TravelDirection.infer(train: ride(["D", "C", "B", "A"]), package: blocked))
        #expect(reverse.direction == .up)
        #expect(reverse.kilometers == 24)
    }

    @Test("The line that covers more of the ride casts the section's vote")
    func prefersTheLineWithMoreStops() throws {
        let package = try fixture([
            line("local", ["A", "B"], kilometers: 10, order: "up"),
            line("trunk", ["A", "B", "C", "D"], kilometers: 10, order: "down"),
        ])
        let result = try #require(try TravelDirection.infer(train: ride(["A", "B", "C", "D"]), package: package))
        #expect(result.direction == .down)
        #expect(result.lineID == "trunk")
        #expect(result.kilometers == 30)
    }

    @Test("北斗21 toward 札幌 is down, with 室蘭線 carrying the most of that vote")
    func hokuto() throws {
        let result = try #require(try TravelDirection.infer(train: try stored("20260713_07_hokuto21"), package: try PortFixtures.package(country: "jp")))
        // 函館→札幌 leaves Tokyo behind. 函館線's explicit order, and the Tokyo
        // rule on 室蘭線 and 千歳線, all call that 下り. 室蘭線 is the longest part.
        #expect(result.direction == .down)
        #expect(result.lineID.contains("室蘭線"))
        #expect(result.kilometers > 200)
    }

    @Test("スーパーおき5号 米子→新山口 is down on the 山陰線 majority")
    func superOki() throws {
        let result = try #require(try TravelDirection.infer(train: try stored("20260719_03_super_oki5"), package: try PortFixtures.package(country: "jp")))
        // 山陰線 is stored 幡生→京都. 京都 is the terminal nearer 東京, so
        // 米子→益田, away from Kyoto, is 下り. 山口線 is the shorter part.
        #expect(result.direction == .down)
        #expect(result.lineID.contains("山陰線"))
        #expect(result.kilometers > 150)
    }

    @Test("こだま 新大阪→三島 is up, and 東京→新大阪 is down")
    func kodamaAndTokaido() throws {
        let package = try PortFixtures.package(country: "jp")
        let kodama = try #require(try TravelDirection.infer(
            train: try stored("20260703_02_tokaido_shinkansen_hikari_kodama"), package: package))
        // 東海道新幹線 is stored 新大阪→東京. 東京 is the 上り end, so
        // 新大阪→三島 is 上り.
        #expect(kodama.direction == .up)
        #expect(kodama.lineID.contains("東海道新幹線"))
        #expect(kodama.kilometers > 300)

        let tokyo = Train(
            id: "tokyo-shin-osaka", number: "下り", origin: "東京", destination: "新大阪",
            stops: [
                Stop(name: "東京", n02StationCode: "003766"),
                Stop(name: "新大阪", n02StationCode: "006911"),
            ])
        let westbound = try #require(try TravelDirection.infer(train: tokyo, package: package))
        #expect(westbound.direction == .down)
        #expect(westbound.lineID.contains("東海道新幹線"))
        #expect(westbound.kilometers > 500)
    }

    @Test("ソニック 博多→大分 is down, with 日豊線 carrying the most of that vote")
    func sonic() throws {
        var train = try stored("20260722_06_sonic44")
        train.stops.reverse()
        train.routeSections = nil
        let result = try #require(try TravelDirection.infer(train: train, package: try PortFixtures.package(country: "jp")))
        // Stored ソニック44 is 大分→博多. Reversed, 博多→小倉 is 上り on 鹿児島線
        // and 小倉→大分 is 下り on 日豊線. 日豊線 is the longer part, just over 60%.
        #expect(result.direction == .down)
        #expect(result.lineID.contains("日豊線"))
        #expect(result.kilometers > 100)
    }

    @Test("南風 岡山→高知 is down, with 土讃線 carrying the most of that vote")
    func nanpu() throws {
        var train = try stored("20260724_06_nanpu28")
        train.stops.reverse()
        train.routeSections = nil
        let result = try #require(try TravelDirection.infer(train: train, package: try PortFixtures.package(country: "jp")))
        // Stored 南風28 is 高知→岡山. Reversed, the 土讃線 run toward 高知 is 下り.
        #expect(result.direction == .down)
        #expect(result.lineID.contains("土讃線"))
        #expect(result.kilometers > 100)
    }

    @Test("On a JR line with no other source, 上り is toward 東京駅")
    func jrTowardTokyo() throws {
        let toward = try fixture([line(
            "tokaido", ["West", "East"], kilometers: 10,
            operatorName: "東日本旅客鉄道",
            coordinates: [(130.0, 35.0), (139.70, 35.68)])])
        let eastbound = try #require(try TravelDirection.infer(train: ride(["West", "East"]), package: toward))
        #expect(eastbound.direction == .up)
        let westbound = try #require(try TravelDirection.infer(train: ride(["East", "West"]), package: toward))
        #expect(westbound.direction == .down)

        let tied = try fixture([line(
            "balanced", ["West", "East"], kilometers: 10,
            operatorName: "東日本旅客鉄道",
            coordinates: [(138.7671, 35.6812), (140.7671, 35.6812)])])
        #expect(try TravelDirection.infer(train: ride(["West", "East"]), package: tied) == nil)
    }

    @Test("Recorded calibration overrides station-order and heuristic direction")
    func recordedCalibrationTakesPrecedence() throws {
        // The reviewed bundled 久大線 record has downSign = -1. Both the
        // explicit order and the JR Tokyo heuristic below would otherwise
        // call increasing index down, so losing calibration must fail.
        let lineID = "jp-九州旅客鉄道-久大線"
        for order in [String?.some("down"), nil] {
            let package = try fixture([line(
                lineID, ["A", "B"], kilometers: 10, order: order,
                operatorName: "九州旅客鉄道",
                coordinates: [(139.7671, 35.6812), (130.0, 35.0)])])
            let forward = try #require(try TravelDirection.infer(train: ride(["A", "B"]), package: package))
            #expect(forward.lineID == lineID)
            #expect(forward.direction == .up)
            let reverse = try #require(try TravelDirection.infer(train: ride(["B", "A"]), package: package))
            #expect(reverse.lineID == lineID)
            #expect(reverse.direction == .down)
        }
    }

    private func ride(_ codes: [String], sections: [RouteSection]? = nil) -> Train {
        Train(
            id: "direction", number: "Test", origin: codes.first ?? "", destination: codes.last ?? "",
            routeSections: sections, stops: codes.map { Stop(name: $0, n02StationCode: $0) })
    }

    private func line(
        _ id: String, _ codes: [String], kilometers: Double, order: String? = nil,
        alignment: String? = nil, loop: Bool = false,
        operatorName: String = "Operator",
        coordinates: [(Double, Double)]? = nil
    ) -> [String: Any] {
        let points = coordinates ?? codes.enumerated().map { (Double($0.offset), 0.0) }
        var row: [String: Any] = [
            "id": id, "name": id, "operator": operatorName, "rank": 3, "kind": "jr_conventional",
            "stations": codes.enumerated().map { index, code in
                let point = points[index]
                return [code, code, point.0, point.1] as [Any]
            },
            "segments": (0..<(codes.count - 1)).map { index in
                [kilometers, 0, [[Double(index), 0], [Double(index + 1), 0]]] as [Any]
            },
        ]
        if loop { row["isLoop"] = 1 }
        if let order { row["stationOrderDirection"] = order }
        if let alignment { row["alignmentDirection"] = alignment }
        return row
    }

    private func fixture(_ lines: [[String: Any]]) throws -> CompactPackage {
        try JSONDecoder().decode(CompactPackage.self, from: JSONSerialization.data(withJSONObject: [
            "format": "compact-v1", "version": "test", "country": "jp", "lines": lines,
        ]))
    }

    private func stored(_ id: String) throws -> Train {
        let url = try PortFixtures.repositoryRoot().appending(path: "app/data/train-store.json")
        let store = try JSONDecoder().decode(TrainStore.self, from: Data(contentsOf: url))
        return try #require(store.trains.first { $0.id == id })
    }
}
