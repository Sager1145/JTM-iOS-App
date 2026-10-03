import Foundation
import Testing
@testable import RailCore

struct JapanThroughServicesTests {
    @Test("Bundled corridors have exact physical line and anchor identities")
    func inventory() throws {
        let catalog = try JapanThroughServices.loadBundled()
        let package = try PortFixtures.package(country: "jp")
        #expect(catalog.patterns.count >= 40)
        #expect(Set(catalog.patterns.map(\.id)).count == catalog.patterns.count)
        #expect(catalog.coverage.contains { $0.region == "Hokuriku" && $0.level == .unknown })
        for pattern in catalog.patterns {
            #expect(!pattern.sourceURLs.isEmpty)
            for leg in pattern.legs {
                let line = try #require(package.lines.first { $0.id == leg.lineID })
                #expect(line.stations.contains { $0.id == leg.fromStationCode })
                #expect(line.stations.contains { $0.id == leg.toStationCode })
                if let reverseID = leg.reverseLineID {
                    let mate = try #require(package.lines.first { $0.id == reverseID })
                    #expect(mate.alignmentOf == line.id || line.alignmentOf == mate.id)
                    #expect(mate.stations.contains { $0.id == leg.fromStationCode })
                    #expect(mate.stations.contains { $0.id == leg.toStationCode })
                }
            }
            for (a, b) in zip(pattern.legs, pattern.legs.dropFirst()) {
                #expect(a.toStationCode == b.fromStationCode)
            }
            let first = try #require(pattern.legs.first), last = try #require(pattern.legs.last)
            #expect(!pattern.choices(package: package, originCode: first.fromStationCode,
                                    destinationCode: last.toStationCode).isEmpty)
        }
    }

    @Test("JK follows the surface and Negishi corridor rather than the Tokyo tunnel", arguments: [false, true])
    func keihinTohoku(reverse: Bool) throws {
        let package = try PortFixtures.package(country: "jp")
        let pattern = try #require(JapanThroughServices.patterns.first { $0.id == "JK" })
        let choice = try #require(pattern.choices(package: package,
            originCode: reverse ? "004961" : "002914", destinationCode: reverse ? "002914" : "004961").first)
        #expect(choice.stations.contains { $0.name == "浜松町" })
        #expect(choice.stations.contains { $0.name == "関内" })
        #expect(!choice.lineIDs.contains("jp-東日本旅客鉄道-総武線-3"))
        #expect(choice.sectionCodes.count == choice.stations.count - 1)
    }

    @Test("JS retains the Shinjuku corridor and its branch identity", arguments: [false, true])
    func shonanShinjuku(reverse: Bool) throws {
        let package = try PortFixtures.package(country: "jp")
        let pattern = try #require(JapanThroughServices.patterns.first { $0.id == "JS-utsunomiya-zushi" })
        let choice = try #require(pattern.choices(package: package,
            originCode: reverse ? "005121" : "002914", destinationCode: reverse ? "002914" : "005121").first)
        #expect(choice.stations.contains { $0.name == "新宿" })
        #expect(choice.stations.contains { $0.name == "武蔵小杉" })
        #expect(!choice.stations.contains { $0.name == "東京" })
        #expect(!choice.lineIDs.contains("jp-東日本旅客鉄道-東北線-5"))
        #expect(pattern.choices(package: package, originCode: "003766", destinationCode: "005121").isEmpty)
        #expect(JapanThroughServices.matches(query: "ＪＳ").count == 2)
        #expect(choice.lineIDs.contains(reverse
            ? "jp-東日本旅客鉄道-大崎支線-p1" : "jp-東日本旅客鉄道-大崎支線"))
        #expect(!choice.lineIDs.contains(reverse
            ? "jp-東日本旅客鉄道-大崎支線" : "jp-東日本旅客鉄道-大崎支線-p1"))
    }

    @Test("Northbound Osaki corridors retain the surveyed pair and strict directions")
    func directedOsakiPair() throws {
        let package = try PortFixtures.package(country: "jp")
        let mainID = "jp-東日本旅客鉄道-大崎支線"
        let mateID = mainID + "-p1"
        let main = try #require(package.lines.first { $0.id == mainID })
        let mate = try #require(package.lines.first { $0.id == mateID })
        #expect(RailwayDirection.allowedDirections(for: main, intervalIndex: 0) == [1])
        #expect(RailwayDirection.allowedDirections(for: mate, intervalIndex: 0) == [-1])
        #expect(JapanThroughServices.serviceCodes(line: main,
            fromStationCode: "004235", toStationCode: "004135").isEmpty)
        #expect(!JapanThroughServices.serviceCodes(line: mate,
            fromStationCode: "004235", toStationCode: "004135").isEmpty)
        #expect(JapanThroughServices.serviceCodes(line: mate,
            fromStationCode: "004135", toStationCode: "004235").isEmpty)
        let pattern = try #require(JapanThroughServices.patterns.first { $0.id == "JS-utsunomiya-zushi" })
        let north = try #require(pattern.choices(package: package,
            originCode: "004235", destinationCode: "004135").first)
        #expect(north.lineIDs == [mateID])
        #expect(north.sectionCodes == RailIntervalCodes.intervals(for: mate).map(\.code))
        #expect(!JapanThroughServices.continuationCodes(fromLineID: mateID,
            toLineID: "jp-東日本旅客鉄道-山手線", atStationCode: "004135").isEmpty)
        #expect(JapanThroughServices.continuationCodes(fromLineID: mateID,
            toLineID: "jp-東日本旅客鉄道-山手線", atStationCode: "004235").isEmpty)
        let sotetsu = try #require(JapanThroughServices.patterns.first { $0.id == "sotetsu-jr-shinjuku" })
        let outward = try #require(sotetsu.choices(package: package,
            originCode: "004672", destinationCode: "003700").first)
        let inward = try #require(sotetsu.choices(package: package,
            originCode: "003700", destinationCode: "004672").first)
        #expect(outward.lineIDs.contains(mateID))
        #expect(inward.lineIDs.contains(mainID))
    }

    @Test("Reverse corridors require an explicitly reviewed physical pair")
    func reversePairMustBeDeclared() throws {
        let package = try PortFixtures.package(country: "jp")
        let source = try #require(JapanThroughServices.patterns.first { $0.id == "JS-utsunomiya-zushi" })
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(source)) as? [String: Any])
        var legs = try #require(json["legs"] as? [[String: Any]])
        let index = try #require(legs.firstIndex { $0["lineID"] as? String == "jp-東日本旅客鉄道-大崎支線" })
        legs[index].removeValue(forKey: "reverseLineID")
        json["legs"] = legs
        let undeclared = try JSONDecoder().decode(JapanThroughServices.Pattern.self,
            from: JSONSerialization.data(withJSONObject: json))
        #expect(undeclared.choices(package: package, originCode: "004235", destinationCode: "004135").isEmpty)
        legs[index]["reverseLineID"] = "jp-東日本旅客鉄道-山手線"
        json["legs"] = legs
        let unrelated = try JSONDecoder().decode(JapanThroughServices.Pattern.self,
            from: JSONSerialization.data(withJSONObject: json))
        #expect(unrelated.choices(package: package, originCode: "004235", destinationCode: "004135").isEmpty)
    }

    @Test("Keisei to Keikyu crosses only the anchored Asakusa corridor")
    func asakusa() throws {
        let package = try PortFixtures.package(country: "jp")
        let pattern = try #require(JapanThroughServices.patterns.first { $0.id == "asakusa-keisei-keikyu" })
        let choice = try #require(pattern.choices(package: package, originCode: "003203", destinationCode: "004368").first)
        #expect(choice.lineIDs.contains("jp-東京都-1号線浅草線"))
        #expect(choice.stations.contains { $0.code == "003526" })
        #expect(choice.stations.contains { $0.code == "004042" })
        #expect(!JapanThroughServices.continuationCodes(fromLineID: "jp-京成電鉄-押上線",
            toLineID: "jp-東京都-1号線浅草線", atStationCode: "003526").isEmpty)
        #expect(JapanThroughServices.continuationCodes(fromLineID: "jp-京成電鉄-押上線",
            toLineID: "jp-東京地下鉄-11号線半蔵門線", atStationCode: "003526").isEmpty)
    }

    @Test("Membership is bounded to operational leg anchors, not an entire physical row")
    func boundedMembership() throws {
        let package = try PortFixtures.package(country: "jp")
        let line = try #require(package.lines.first { $0.id == "jp-東日本旅客鉄道-東海道線" })
        #expect(JapanThroughServices.serviceCodes(line: line, fromStationCode: "003766", toStationCode: "003795").contains("JK"))
        #expect(!JapanThroughServices.serviceCodes(line: line, fromStationCode: "004961", toStationCode: "004997").contains("JK"))
        let fukuoka = try #require(JapanThroughServices.patterns.first { $0.id == "fukuoka-kuko-chikuhi" })
        #expect(!fukuoka.choices(package: package, originCode: "009015", destinationCode: "009278").isEmpty)
    }
}
