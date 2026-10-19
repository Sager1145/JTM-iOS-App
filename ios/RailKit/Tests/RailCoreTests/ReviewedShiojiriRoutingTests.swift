import Foundation
import Testing
import RailCore

struct ReviewedShiojiriRoutingTests {
    @Test("Current Enrei approach continues onto surveyed Shinonoi rail at Shiojiri")
    func actualSourceBoundary() throws {
        let snapshot = try ReviewedCorridorFixtures.snapshot(history: false)
        let sections = snapshot.sections.filter {
                $0.properties.operator == "東日本旅客鉄道"
                    && ["中央線", "篠ノ井線"].contains($0.properties.lineName)
            }
        let junction = try #require(snapshot.junctions.first { $0.id == "shiojiri-chuo-shinonoi" })
        let independent = RouteGraph.build(from: sections)
        let joined = RouteGraph.build(from: sections, junctions: [junction])
        #expect(joined.rejectedPhysicalJunctionIDs.isEmpty)
        let forward = RouteSection(from: "上諏訪", to: "松本",
                                   fromN02StationCode: "002706", toN02StationCode: "002506")
        let reverse = RouteSection(from: "松本", to: "上諏訪",
                                   fromN02StationCode: "002506", toN02StationCode: "002706")
        var worker = ReviewedCorridorWorker(sections: sections, stations: snapshot.stations,
            junctions: [junction])
        func solve(_ reviewed: Bool, _ section: RouteSection,
                   _ date: String) throws -> ReviewedCorridorWorker.Proof? {
            try worker.solve(reviewed: reviewed, section: section, company: "東日本旅客鉄道", date: date)
        }
        for section in [forward, reverse] {
            #expect(try solve(false, section, "2026-10-03") == nil)
            #expect(try solve(true, section, "1983-07-04") == nil)
            for day in ["1983-07-05", "2026-10-03"] {
                let solved = try #require(try solve(true, section, day))
                #expect(solved.coordinates == solved.rawPathKeys.compactMap { joined.nodes[$0] })
                var boundaries = 0
                var lines = Set<String>()
                for (from, to) in zip(solved.rawPathKeys, solved.rawPathKeys.dropFirst()) {
                    let edge = try #require(joined.adjacency[from]?.first { $0.to == to })
                    #expect(edge.connector == nil)
                    if let boundary = edge.physicalJunction {
                        #expect(boundary.junction.id == junction.id)
                        #expect(edge.length == 0)
                        #expect(joined.nodes[from] == joined.nodes[to])
                        boundaries += 1
                    } else {
                        lines.insert(edge.lineName)
                    }
                }
                #expect(boundaries == 1)
                #expect(lines == ["中央線", "篠ノ井線"])
            }
        }
    }
}
