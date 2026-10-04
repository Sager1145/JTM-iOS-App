import Foundation
import Testing
@testable import RailCore

struct TravelDirectionTests {
    @Test("An explicit down station order calls forward travel down and reverse travel up")
    func explicitDown() throws {
        let package = try fixture([line("main", ["A", "B", "C", "D"], kilometers: 10, order: "down")])
        let forward = try #require(TravelDirection.infer(train: ride(["A", "B", "C", "D"]), package: package))
        #expect(forward.direction == .down)
        #expect(forward.lineID == "main")
        #expect(forward.kilometers == 30)
        let reverse = try #require(TravelDirection.infer(train: ride(["D", "C", "B", "A"]), package: package))
        #expect(reverse.direction == .up)
        #expect(reverse.kilometers == 30)
    }

    @Test("A non-JR line with no up or down order casts no vote")
    func missingOrderDoesNotVote() throws {
        for order in [String?.none, "unassigned"] {
            let package = try fixture([line("main", ["A", "B", "C", "D"], kilometers: 10, order: order)])
            #expect(TravelDirection.infer(train: ride(["A", "B", "C", "D"]), package: package) == nil)
        }
    }

    @Test("An explicit up station order flips the word")
    func explicitUp() throws {
        let package = try fixture([line("main", ["A", "B", "C"], kilometers: 5, order: "up")])
        let forward = try #require(TravelDirection.infer(train: ride(["A", "B", "C"]), package: package))
        #expect(forward.direction == .up)
        #expect(forward.kilometers == 10)
        let reverse = try #require(TravelDirection.infer(train: ride(["C", "B", "A"]), package: package))
        #expect(reverse.direction == .down)
    }

    @Test("The heavier direction wins at 60 percent, and a tie or a minority loses")
    func majority() throws {
        let lines = [
            line("long", ["A", "B", "C", "D", "E", "F", "G"], kilometers: 1, order: "down"),
            line("short", ["G", "H", "I", "J", "K"], kilometers: 1, order: "up"),
        ]
        let winner = try #require(TravelDirection.infer(
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
        #expect(TravelDirection.infer(train: ride(["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K"]), package: tied) == nil)

        let minority = try fixture([
            line("east", ["A", "B", "C", "D", "E", "F"], kilometers: 1, order: "down"),
            line("west", ["F", "G", "H", "I", "J"], kilometers: 1, order: "up"),
        ])
        // 5 down versus 4 up is 5/9, under 60%.
        #expect(TravelDirection.infer(train: ride(["A", "B", "C", "D", "E", "F", "G", "H", "I", "J"]), package: minority) == nil)
    }

    @Test("A loop, including a line named 環状, does not vote")
    func loopsAreNil() throws {
        let looped = try fixture([line("circle", ["A", "B", "C", "D"], kilometers: 3, loop: true)])
        #expect(TravelDirection.infer(train: ride(["A", "B", "C"]), package: looped) == nil)
        let named = try fixture([line("大阪環状線", ["A", "B", "C", "D"], kilometers: 3)])
        #expect(TravelDirection.infer(train: ride(["A", "C"]), package: named) == nil)
    }

    @Test("Alignment that forbids the traveled sign contributes no distance")
    func alignmentFilter() throws {
        let blocked = try fixture([
            line("main", ["A", "B", "C", "D"], kilometers: 8, order: "down", alignment: "up"),
        ])
        #expect(TravelDirection.infer(train: ride(["A", "B", "C", "D"]), package: blocked) == nil)
        let reverse = try #require(TravelDirection.infer(train: ride(["D", "C", "B", "A"]), package: blocked))
        #expect(reverse.direction == .up)
        #expect(reverse.kilometers == 24)
    }

    @Test("The line that covers more of the ride casts the section's vote")
    func prefersTheLineWithMoreStops() throws {
        let package = try fixture([
            line("local", ["A", "B"], kilometers: 10, order: "up"),
            line("trunk", ["A", "B", "C", "D"], kilometers: 10, order: "down"),
        ])
        let result = try #require(TravelDirection.infer(train: ride(["A", "B", "C", "D"]), package: package))
        #expect(result.direction == .down)
        #expect(result.lineID == "trunk")
        #expect(result.kilometers == 30)
    }

    @Test("北斗21 toward 札幌 is down, with 室蘭線 carrying the most of that vote")
    func hokuto() throws {
        let result = try #require(TravelDirection.infer(train: try stored("20260713_07_hokuto21"), package: try PortFixtures.package(country: "jp")))
        // 函館→札幌 leaves Tokyo behind. 函館線's explicit order, and the Tokyo
        // rule on 室蘭線 and 千歳線, all call that 下り. 室蘭線 is the longest part.
        #expect(result.direction == .down)
        #expect(result.lineID.contains("室蘭線"))
        #expect(result.kilometers > 200)
    }

    @Test("スーパーおき5号 米子→新山口 is down on the 山陰線 majority")
    func superOki() throws {
        let result = try #require(TravelDirection.infer(train: try stored("20260719_03_super_oki5"), package: try PortFixtures.package(country: "jp")))
        // 山陰線 is stored 幡生→京都. 京都 is the terminal nearer 東京, so
        // 米子→益田, away from Kyoto, is 下り. 山口線 is the shorter part.
        #expect(result.direction == .down)
        #expect(result.lineID.contains("山陰線"))
        #expect(result.kilometers > 150)
    }

    @Test("こだま 新大阪→三島 is up, and 東京→新大阪 is down")
    func kodamaAndTokaido() throws {
        let package = try PortFixtures.package(country: "jp")
        let kodama = try #require(TravelDirection.infer(
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
        let westbound = try #require(TravelDirection.infer(train: tokyo, package: package))
        #expect(westbound.direction == .down)
        #expect(westbound.lineID.contains("東海道新幹線"))
        #expect(westbound.kilometers > 500)
    }

    @Test("ソニック 博多→大分 is down, with 日豊線 carrying the most of that vote")
    func sonic() throws {
        var train = try stored("20260722_06_sonic44")
        train.stops.reverse()
        train.routeSections = nil
        let result = try #require(TravelDirection.infer(train: train, package: try PortFixtures.package(country: "jp")))
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
        let result = try #require(TravelDirection.infer(train: train, package: try PortFixtures.package(country: "jp")))
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
        let eastbound = try #require(TravelDirection.infer(train: ride(["West", "East"]), package: toward))
        #expect(eastbound.direction == .up)
        let westbound = try #require(TravelDirection.infer(train: ride(["East", "West"]), package: toward))
        #expect(westbound.direction == .down)

        let tied = try fixture([line(
            "balanced", ["West", "East"], kilometers: 10,
            operatorName: "東日本旅客鉄道",
            coordinates: [(138.7671, 35.6812), (140.7671, 35.6812)])])
        #expect(TravelDirection.infer(train: ride(["West", "East"]), package: tied) == nil)
    }

    @Test("A calibrated private railway follows its timetable down sign")
    func calibratedPrivateRailway() throws {
        let root = try PortFixtures.repositoryRoot()
        let url = root.appending(path: "ios/RailKit/Sources/RailCore/Resources/line-direction-calibration.json")
        let rows = try JSONDecoder().decode([String: CalibrationRow].self, from: Data(contentsOf: url))
        let package = try PortFixtures.package(country: "jp")
        let jr = [
            "北海道旅客鉄道", "東日本旅客鉄道", "東海旅客鉄道",
            "西日本旅客鉄道", "四国旅客鉄道", "九州旅客鉄道",
        ]
        let candidates = package.lines.filter { line in
            guard let row = rows[line.id], row.downSign == 1 || row.downSign == -1 else { return false }
            guard let name = line.`operator`, !jr.contains(where: { name.contains($0) }) else { return false }
            return !line.isLoop && !line.name.contains("環状")
        }
        guard !candidates.isEmpty else { return }
        var owners: [String: Int] = [:]
        for line in package.lines {
            for station in Set(line.stations.map(\.id)) {
                owners[station, default: 0] += 1
            }
        }
        var matched = false
        for line in candidates {
            guard let row = rows[line.id] else { continue }
            let unique = line.stations.filter { owners[$0.id] == 1 }
            guard let from = unique.first, let to = unique.last, from.id != to.id else { continue }
            let train = Train(
                id: "private", number: "t", origin: from.name, destination: to.name,
                stops: [
                    Stop(name: from.name, n02StationCode: from.id),
                    Stop(name: to.name, n02StationCode: to.id),
                ])
            guard let result = TravelDirection.infer(train: train, package: package) else { continue }
            let expected: TravelDirection.Direction = row.downSign == 1 ? .down : .up
            #expect(result.lineID == line.id)
            #expect(result.direction == expected)
            matched = true
            break
        }
        #expect(matched)
    }

    private func ride(_ codes: [String], sections: [RouteSection]? = nil) -> Train {
        Train(
            id: "direction", number: "Test", origin: codes.first ?? "", destination: codes.last ?? "",
            routeSections: sections, stops: codes.map { Stop(name: $0, n02StationCode: $0) })
    }

    private struct CalibrationRow: Decodable {
        var downSign: Int
        var votes: Int
        var agreement: Double
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
