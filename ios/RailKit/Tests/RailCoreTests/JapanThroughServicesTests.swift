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
        #expect(catalog.coverage.contains { $0.region == "Hokuriku" && $0.level == .checked })
        for pattern in catalog.patterns {
            #expect(!pattern.sourceURLs.isEmpty)
            let date = try representativeActiveDate(for: pattern)
            let legs = pattern.legs(on: date)
            for leg in legs {
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
            if pattern.notes.contains("physically discontinuous in the package:") { continue }
            for (a, b) in zip(legs, legs.dropFirst()) {
                let shared = a.toStationCode == b.fromStationCode
                let joined = !JapanThroughServices.continuationCodes(
                    fromLineID: a.lineID, toLineID: b.lineID,
                    atStationCode: a.toStationCode,
                    on: date,
                    patterns: [pattern], connectors: catalog.connectors).isEmpty
                #expect(shared || joined, "\(pattern.id): \(a.lineID) to \(b.lineID)")
            }
            let first = try #require(legs.first), last = try #require(legs.last)
            // choices intentionally rejects identical journey endpoints. For a closed
            // corridor, exercise the route through its final distinct anchor instead.
            let destinationCode = last.toStationCode == first.fromStationCode
                ? last.fromStationCode : last.toStationCode
            #expect(!pattern.choices(package: package, originCode: first.fromStationCode,
                                    destinationCode: destinationCode, on: date).isEmpty,
                    "\(pattern.id) on \(date ?? "current")")
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

    @Test("Rinkai connects to the Saikyo corridor at Osaki")
    func rinkaiSaikyoConnectivity() throws {
        let package = try PortFixtures.package(country: "jp")
        let rinkai = try #require(package.lines.first { $0.id == "jp-東京臨海高速鉄道-臨海副都心線" })
        let yamanote = try #require(package.lines.first { $0.id == "jp-東日本旅客鉄道-山手線" })
        #expect(TripConnectivity.link(from: rinkai, to: yamanote, atStationCode: "004135") == .throughService)
    }

    @Test("Adjacent through-service legs join only at their anchor, not at a shared intermediate station")
    func throughServiceLegsJoinOnlyAtAnchors() throws {
        let package = try PortFixtures.package(country: "jp")
        let sobu = try #require(package.lines.first { $0.id == "jp-東日本旅客鉄道-総武線-3" })
        let tokaido = try #require(package.lines.first { $0.id == "jp-東日本旅客鉄道-東海道線" })
        // 新橋 lies on both rows between 東京 and 品川; no train changes rows there.
        #expect(TripConnectivity.link(from: tokaido, to: sobu, atStationCode: "003872") == .none)
        #expect(TripConnectivity.link(from: sobu, to: tokaido, atStationCode: "003872") == .none)
        // The same pair still joins at a listed anchor (東京).
        #expect(TripConnectivity.link(from: sobu, to: tokaido, atStationCode: "003766") != .none)
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

    @Test("Service windows are ISO days inside coverage and their pattern interval")
    func datedSchema() throws {
        let catalog = try JapanThroughServices.loadBundled()
        #expect(catalog.schemaVersion == 2)
        let coverage = try #require(catalog.coverageFrom)
        #expect(coverage == "2005-01-01")
        #expect(isISODay(coverage))
        let legacy = #"{"checkedAt":"t","scope":"s","patterns":[{"id":"p","serviceCode":"P","name":"P","aliases":[],"kind":"throughRunning","legs":[{"lineID":"L","fromStationCode":"A","toStationCode":"B"}],"sourceURLs":["https://example.test"],"notes":""}],"coverage":[]}"#
        let decoded = try JSONDecoder().decode(JapanThroughServices.Catalog.self, from: Data(legacy.utf8))
        #expect(decoded.schemaVersion == nil)
        #expect(decoded.coverageFrom == nil)
        #expect(decoded.connectors.isEmpty)
        #expect(decoded.patterns[0].validFrom == nil)
        #expect(decoded.patterns[0].validTo == nil)
        #expect(decoded.patterns[0].legs[0].validFrom == nil)
        #expect(decoded.patterns[0].legs[0].validTo == nil)
        for pattern in catalog.patterns {
            assertWindow(pattern.validFrom, pattern.validTo, coverage: coverage)
            for leg in pattern.legs {
                assertWindow(leg.validFrom, leg.validTo, coverage: coverage)
                #expect(windowContains(outerFrom: pattern.validFrom, outerTo: pattern.validTo,
                                       innerFrom: leg.validFrom, innerTo: leg.validTo))
            }
        }
        for connector in catalog.connectors {
            assertWindow(connector.validFrom, connector.validTo, coverage: coverage)
        }
    }

    @Test("Active legs stay contiguous and on the bundled package at every boundary date")
    func activeLegsStayAnchored() throws {
        let catalog = try JapanThroughServices.loadBundled()
        let package = try PortFixtures.package(country: "jp")
        for pattern in catalog.patterns {
            var dates: Set<String?> = [nil]
            for value in [pattern.validFrom, pattern.validTo] + pattern.legs.flatMap({ [$0.validFrom, $0.validTo] }) {
                if let value { dates.insert(value) }
            }
            for date in dates {
                let active = pattern.legs(on: date)
                for pair in zip(active, active.dropFirst()) {
                    let shared = pair.0.toStationCode == pair.1.fromStationCode
                    let joined = !JapanThroughServices.continuationCodes(
                        fromLineID: pair.0.lineID, toLineID: pair.1.lineID,
                        atStationCode: pair.0.toStationCode, on: date,
                        patterns: [pattern], connectors: catalog.connectors).isEmpty
                    #expect(shared || joined)
                }
                for leg in active {
                    let line = try #require(package.lines.first { $0.id == leg.lineID })
                    #expect(line.stations.contains { $0.id == leg.fromStationCode })
                    #expect(line.stations.contains { $0.id == leg.toStationCode })
                    if let reverseID = leg.reverseLineID {
                        let mate = try #require(package.lines.first { $0.id == reverseID })
                        #expect(mate.stations.contains { $0.id == leg.fromStationCode })
                        #expect(mate.stations.contains { $0.id == leg.toStationCode })
                    }
                }
            }
        }
    }

    @Test("A leg ending 2013-03-16 is active the day before and inactive on that day and when undated")
    func halfOpenLegWindow() throws {
        let pattern = try decodePattern("""
        {"id":"dated","serviceCode":"DJ","name":"Dated","aliases":[],"kind":"throughRunning",
         "legs":[
           {"lineID":"line-a","fromStationCode":"a","toStationCode":"join","validTo":"2013-03-16"},
           {"lineID":"line-b","fromStationCode":"join","toStationCode":"b"}
         ],"sourceURLs":["https://example.test/dated"],"notes":""}
        """)
        #expect(pattern.legs(on: "2013-03-15").contains { $0.lineID == "line-a" })
        #expect(!pattern.legs(on: "2013-03-16").contains { $0.lineID == "line-a" })
        #expect(!pattern.legs(on: nil).contains { $0.lineID == "line-a" })
        #expect(JapanThroughServices.continuationCodes(
            fromLineID: "line-a", toLineID: "line-b", atStationCode: "join",
            on: "2013-03-15", patterns: [pattern]) == Set(["DJ"]))
        #expect(JapanThroughServices.continuationCodes(
            fromLineID: "line-a", toLineID: "line-b", atStationCode: "join",
            on: "2013-03-16", patterns: [pattern]).isEmpty)
        #expect(JapanThroughServices.continuationCodes(
            fromLineID: "line-a", toLineID: "line-b", atStationCode: "join",
            on: nil, patterns: [pattern]).isEmpty)
        let closed = try decodePattern("""
        {"id":"closed","serviceCode":"CL","name":"Closed","aliases":[],"kind":"throughRunning","validTo":"2013-03-16",
         "legs":[
           {"lineID":"line-a","fromStationCode":"a","toStationCode":"join"},
           {"lineID":"line-b","fromStationCode":"join","toStationCode":"b"}
         ],"sourceURLs":["https://example.test/closed"],"notes":""}
        """)
        #expect(closed.legs(on: "2013-03-15").count == 2)
        #expect(closed.legs(on: "2013-03-16").isEmpty)
        #expect(closed.legs(on: nil).isEmpty)
    }

    @Test("Dated catalog lookups exclude a pattern before validFrom")
    func datedCatalogLookups() throws {
        let catalog = try JSONDecoder().decode(JapanThroughServices.Catalog.self, from: Data("""
        {"checkedAt":"2020-01-01","scope":"test","patterns":[
          {"id":"synthetic","serviceCode":"SYN","name":"Synthetic","aliases":[],
           "kind":"throughRunning","validFrom":"2020-01-01","validTo":"2021-01-01",
           "legs":[{"lineID":"line-a","fromStationCode":"a","toStationCode":"c"}],
           "sourceURLs":["https://example.test/synthetic"],"notes":""}
        ],"coverage":[]}
        """.utf8))
        let pattern = try #require(catalog.patterns.first)
        let package = try fixture([line("line-a", "Alpha", ["a", "b", "c"])])
        let line = try #require(package.lines.first)

        #expect(pattern.legs(on: "2019-12-31").isEmpty)
        #expect(pattern.lineIDs(on: "2019-12-31").isEmpty)
        #expect(JapanThroughServices.patterns(
            on: "2019-12-31", patterns: catalog.patterns).isEmpty)
        #expect(JapanThroughServices.patterns(
            touchingLineID: "line-a", on: "2019-12-31", patterns: catalog.patterns).isEmpty)
        #expect(JapanThroughServices.serviceCodes(line: line,
            fromStationCode: "a", toStationCode: "b", on: "2019-12-31",
            patterns: catalog.patterns).isEmpty)

        #expect(pattern.lineIDs(on: "2020-01-01") == ["line-a"])
        #expect(JapanThroughServices.patterns(
            on: "2020-01-01", patterns: catalog.patterns).map(\.id) == ["synthetic"])
        #expect(JapanThroughServices.patterns(
            touchingLineID: "line-a", on: "2020-01-01",
            patterns: catalog.patterns).map(\.id) == ["synthetic"])
        #expect(JapanThroughServices.serviceCodes(line: line,
            fromStationCode: "a", toStationCode: "b", on: "2020-01-01",
            patterns: catalog.patterns) == Set(["SYN"]))
    }

    @Test("Dated alias junctions accept either adjacent leg endpoint code")
    func datedAliasJunction() throws {
        let pattern = try decodePattern("""
        {"id":"dated-alias","serviceCode":"DA","name":"Dated alias","aliases":[],
         "kind":"throughRunning","validFrom":"2020-01-01","validTo":"2021-01-01",
         "legs":[
           {"lineID":"line-a","fromStationCode":"a","toStationCode":"join-a"},
           {"lineID":"line-b","fromStationCode":"join-b","toStationCode":"b"}
         ],"sourceURLs":["https://example.test/alias"],"notes":""}
        """)
        let package = try fixture([
            line("line-a", "Alpha", ["a", "join-a"]),
            line("line-b", "Beta", ["join-b", "b"])
        ])
        let connector = try JSONDecoder().decode(JapanThroughServices.Connector.self, from: Data("""
        {"id":"alias-link","fromLineID":"line-a","fromStationCode":"join-a",
         "toLineID":"line-b","toStationCode":"join-b","validFrom":"2020-01-01",
         "validTo":"2021-01-01","notes":"test"}
        """.utf8))
        let from = try #require(package.lines.first { $0.id == "line-a" })
        let to = try #require(package.lines.first { $0.id == "line-b" })
        #expect(pattern.legs[0].toStationCode != pattern.legs[1].fromStationCode)
        for code in [pattern.legs[0].toStationCode, pattern.legs[1].fromStationCode] {
            #expect(TripConnectivity.link(from: from, to: to, atStationCode: code,
                on: "2020-06-01", patterns: [pattern], connectors: [connector]) == .throughService)
            #expect(TripConnectivity.link(from: from, to: to, atStationCode: code,
                on: "2019-12-31", patterns: [pattern], connectors: [connector]) == .none)
        }
        #expect(TripConnectivity.link(from: from, to: to, atStationCode: "join-a",
            on: "2020-06-01", patterns: [pattern], connectors: []) == .none)
        let choice = try #require(pattern.choices(
            package: package, originCode: "a", destinationCode: "b", on: "2020-06-01",
            connectors: [connector]).first)
        #expect(choice.sectionCodes.contains("connector:alias-link"))
        #expect(choice.stations.map(\.code) == ["a", "join-a", "join-b", "b"])
    }

    @Test("A dated-only junction is through service on that day and not when undated")
    func datedJunctionIsNotCurrent() throws {
        let pattern = try decodePattern("""
        {"id":"dated-junction","serviceCode":"DJ","name":"Dated junction","aliases":[],"kind":"throughRunning",
         "legs":[
           {"lineID":"line-a","fromStationCode":"a","toStationCode":"join","validTo":"2013-03-16"},
           {"lineID":"line-b","fromStationCode":"join","toStationCode":"e","validTo":"2013-03-16"}
         ],"sourceURLs":["https://example.test/junction"],"notes":""}
        """)
        let package = try fixture([
            line("line-a", "Alpha", ["a", "join", "c"]),
            line("line-b", "Beta", ["d", "join", "e"])
        ])
        let from = try #require(package.lines.first { $0.id == "line-a" })
        let to = try #require(package.lines.first { $0.id == "line-b" })
        #expect(TripConnectivity.link(from: from, to: to, atStationCode: "join",
                                      on: "2013-03-15", patterns: [pattern]) == .throughService)
        #expect(TripConnectivity.link(from: from, to: to, atStationCode: "join",
                                      on: "2013-03-16", patterns: [pattern]) != .throughService)
        #expect(TripConnectivity.link(from: from, to: to, atStationCode: "join",
                                      on: nil, patterns: [pattern]) != .throughService)
    }

    private func assertWindow(_ from: String?, _ to: String?, coverage: String) {
        if let from {
            #expect(isISODay(from))
            #expect(from >= coverage)
        }
        if let to {
            #expect(isISODay(to))
            #expect(to >= coverage)
        }
        if let from, let to { #expect(from < to) }
    }

    private func windowContains(outerFrom: String?, outerTo: String?, innerFrom: String?, innerTo: String?) -> Bool {
        if let outerFrom {
            guard (innerFrom ?? outerFrom) >= outerFrom else { return false }
        }
        if let outerTo {
            guard (innerTo ?? outerTo) <= outerTo else { return false }
        }
        return true
    }

    private func representativeActiveDate(for pattern: JapanThroughServices.Pattern) throws -> String? {
        if let validFrom = pattern.validFrom { return validFrom }
        guard let validTo = pattern.validTo else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        let end = try #require(formatter.date(from: validTo))
        let previousDay = try #require(formatter.calendar.date(byAdding: .day, value: -1, to: end))
        return formatter.string(from: previousDay)
    }

    private func isISODay(_ value: String) -> Bool {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value) else { return false }
        return formatter.string(from: date) == value
    }

    private func decodePattern(_ json: String) throws -> JapanThroughServices.Pattern {
        try JSONDecoder().decode(JapanThroughServices.Pattern.self, from: Data(json.utf8))
    }

    private func line(_ id: String, _ name: String, _ codes: [String]) -> [String: Any] {
        ["id": id, "name": name, "operator": name, "rank": 3, "kind": "private",
         "stations": codes.enumerated().map { [$0.element, $0.element, Double($0.offset), 0] as [Any] },
         "segments": (0..<(codes.count - 1)).map {
             [1.0, 0, [[Double($0), 0.0], [Double($0 + 1), 0.0]]] as [Any]
         }]
    }

    private func fixture(_ lines: [[String: Any]]) throws -> CompactPackage {
        let data = try JSONSerialization.data(withJSONObject: [
            "format": "compact-v1", "version": "test", "country": "jp", "lines": lines])
        return try JSONDecoder().decode(CompactPackage.self, from: data)
    }
}
