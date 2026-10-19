import Foundation
import Testing
@testable import RailCore

struct JapanThroughServicesTests {
    @Test func bundledCatalogFailureIsNotAnEmptySuccessOrPhysicalDependency() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "through-services-\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "japan-through-services.json")
        try Data("invalid JSON".utf8).write(to: url)
        let bundle = try #require(Bundle(url: directory))
        #expect(throws: (any Error).self) { try JapanThroughServices.loadBundled(bundle: bundle) }
        let package = try sparsePackage()
        let line = try #require(package.lines.first)
        #expect(TripConnectivity.allows(from: line, to: line, atStationCode: "a"))
        #expect(!TripConnectivity.allows(from: line, to: package.lines[1], atStationCode: "join"))
        let catalog = JapanThroughServices.Catalog(checkedAt: "fixture", scope: "fixture", patterns: [], coverage: [])
        try JSONEncoder().encode(catalog).write(to: url)
        #expect(try JapanThroughServices.loadBundled(bundle: bundle).checkedAt == "fixture")
        try Data("changed after immutable snapshot loaded".utf8).write(to: url)
        #expect(try JapanThroughServices.loadBundled(bundle: bundle).checkedAt == "fixture")
    }

    @Test func missingSelectedThroughServiceBundleDoesNotReadAnotherCopy() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "through-services-missing-\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bundle = try #require(Bundle(url: directory))
        #expect(throws: CocoaError.self) { try JapanThroughServices.loadBundled(bundle: bundle) }
    }

    @Test("Musashino passenger arms bypass Futamata-Shinmachi without inventing a stop")
    func keiyoPassengerArms() throws {
        let package = try PortFixtures.package(country: "jp")
        let catalog = try JapanThroughServices.loadBundled()
        for (id, branch, junction, destination) in [
            ("musashino-keiyo-tokyo", "jp-東日本旅客鉄道-京葉線-3", "003870", "003785"),
            ("musashino-keiyo-makuhari", "jp-東日本旅客鉄道-京葉線-2", "003761", "003984")
        ] {
            let pattern = try #require(catalog.patterns.first { $0.id == id })
            let legs = pattern.legs(on: "2026-10-10")
            #expect(legs[1].lineID == branch)
            #expect(legs[1].toStationCode == junction)
            #expect(legs[2].fromStationCode == junction)
            for reverse in [false, true] {
                let choices = pattern.choices(package: package,
                    originCode: reverse ? destination : "003547",
                    destinationCode: reverse ? "003547" : destination, on: "2026-10-10", connectors: (try JapanThroughServices.loadBundled()).connectors)
                let choice = try #require(choices.first)
                #expect(choice.stations.contains { $0.code == junction })
                #expect(!choice.stations.contains { $0.code == "003682" })
            }
            #expect(pattern.choices(package: package, originCode: "003547",
                destinationCode: "003682", on: "2026-10-10", connectors: (try JapanThroughServices.loadBundled()).connectors).isEmpty)
        }
    }

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
                                    destinationCode: destinationCode, on: date, connectors: (try JapanThroughServices.loadBundled()).connectors).isEmpty,
                    "\(pattern.id) on \(date ?? "current")")
        }
    }

    @Test("JK follows the surface and Negishi corridor rather than the Tokyo tunnel", arguments: [false, true])
    func keihinTohoku(reverse: Bool) throws {
        let package = try PortFixtures.package(country: "jp")
        let pattern = try #require((try JapanThroughServices.loadBundled()).patterns.first { $0.id == "JK" })
        let choice = try #require(pattern.choices(package: package,
            originCode: reverse ? "004961" : "002914", destinationCode: reverse ? "002914" : "004961", connectors: (try JapanThroughServices.loadBundled()).connectors).first)
        #expect(choice.stations.contains { $0.name == "浜松町" })
        #expect(choice.stations.contains { $0.name == "関内" })
        #expect(!choice.lineIDs.contains("jp-東日本旅客鉄道-総武線-3"))
        #expect(choice.sectionCodes.count == choice.stations.count - 1)
    }

    @Test("JS retains the Shinjuku corridor and its branch identity", arguments: [false, true])
    func shonanShinjuku(reverse: Bool) throws {
        let package = try PortFixtures.package(country: "jp")
        let pattern = try #require((try JapanThroughServices.loadBundled()).patterns.first { $0.id == "JS-utsunomiya-zushi" })
        let choice = try #require(pattern.choices(package: package,
            originCode: reverse ? "005121" : "002914", destinationCode: reverse ? "002914" : "005121", connectors: (try JapanThroughServices.loadBundled()).connectors).first)
        #expect(choice.stations.contains { $0.name == "新宿" })
        #expect(choice.stations.contains { $0.name == "武蔵小杉" })
        #expect(!choice.stations.contains { $0.name == "東京" })
        #expect(!choice.lineIDs.contains("jp-東日本旅客鉄道-東北線-5"))
        #expect(pattern.choices(package: package, originCode: "003766", destinationCode: "005121", connectors: (try JapanThroughServices.loadBundled()).connectors).isEmpty)
        #expect(JapanThroughServices.matches(query: "ＪＳ", patterns: (try JapanThroughServices.loadBundled()).patterns).count == 2)
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
            fromStationCode: "004235", toStationCode: "004135", patterns: (try JapanThroughServices.loadBundled()).patterns).isEmpty)
        #expect(!JapanThroughServices.serviceCodes(line: mate,
            fromStationCode: "004235", toStationCode: "004135", patterns: (try JapanThroughServices.loadBundled()).patterns).isEmpty)
        #expect(JapanThroughServices.serviceCodes(line: mate,
            fromStationCode: "004135", toStationCode: "004235", patterns: (try JapanThroughServices.loadBundled()).patterns).isEmpty)
        let pattern = try #require((try JapanThroughServices.loadBundled()).patterns.first { $0.id == "JS-utsunomiya-zushi" })
        let north = try #require(pattern.choices(package: package,
            originCode: "004235", destinationCode: "004135", connectors: (try JapanThroughServices.loadBundled()).connectors).first)
        #expect(north.lineIDs == [mateID])
        #expect(north.sectionCodes == RailIntervalCodes.intervals(for: mate).map(\.code))
        #expect(!JapanThroughServices.continuationCodes(fromLineID: mateID,
            toLineID: "jp-東日本旅客鉄道-山手線", atStationCode: "004135", patterns: (try JapanThroughServices.loadBundled()).patterns, connectors: (try JapanThroughServices.loadBundled()).connectors).isEmpty)
        #expect(JapanThroughServices.continuationCodes(fromLineID: mateID,
            toLineID: "jp-東日本旅客鉄道-山手線", atStationCode: "004235", patterns: (try JapanThroughServices.loadBundled()).patterns, connectors: (try JapanThroughServices.loadBundled()).connectors).isEmpty)
        let sotetsu = try #require((try JapanThroughServices.loadBundled()).patterns.first { $0.id == "sotetsu-jr-shinjuku" })
        let outward = try #require(sotetsu.choices(package: package,
            originCode: "004672", destinationCode: "003700", connectors: (try JapanThroughServices.loadBundled()).connectors).first)
        let inward = try #require(sotetsu.choices(package: package,
            originCode: "003700", destinationCode: "004672", connectors: (try JapanThroughServices.loadBundled()).connectors).first)
        #expect(outward.lineIDs.contains(mateID))
        #expect(inward.lineIDs.contains(mainID))
    }

    @Test("Reverse corridors require an explicitly reviewed physical pair")
    func reversePairMustBeDeclared() throws {
        let package = try PortFixtures.package(country: "jp")
        let source = try #require((try JapanThroughServices.loadBundled()).patterns.first { $0.id == "JS-utsunomiya-zushi" })
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(source)) as? [String: Any])
        var legs = try #require(json["legs"] as? [[String: Any]])
        let index = try #require(legs.firstIndex { $0["lineID"] as? String == "jp-東日本旅客鉄道-大崎支線" })
        legs[index].removeValue(forKey: "reverseLineID")
        json["legs"] = legs
        let undeclared = try JSONDecoder().decode(JapanThroughServices.Pattern.self,
            from: JSONSerialization.data(withJSONObject: json))
        #expect(undeclared.choices(package: package, originCode: "004235", destinationCode: "004135", connectors: (try JapanThroughServices.loadBundled()).connectors).isEmpty)
        legs[index]["reverseLineID"] = "jp-東日本旅客鉄道-山手線"
        json["legs"] = legs
        let unrelated = try JSONDecoder().decode(JapanThroughServices.Pattern.self,
            from: JSONSerialization.data(withJSONObject: json))
        #expect(unrelated.choices(package: package, originCode: "004235", destinationCode: "004135", connectors: (try JapanThroughServices.loadBundled()).connectors).isEmpty)
    }

    @Test("Rinkai connects to the Saikyo corridor at Osaki")
    func rinkaiSaikyoConnectivity() throws {
        let package = try PortFixtures.package(country: "jp")
        let rinkai = try #require(package.lines.first { $0.id == "jp-東京臨海高速鉄道-臨海副都心線" })
        let yamanote = try #require(package.lines.first { $0.id == "jp-東日本旅客鉄道-山手線" })
        #expect(TripConnectivity.link(from: rinkai, to: yamanote, atStationCode: "004135", patterns: (try JapanThroughServices.loadBundled()).patterns, connectors: (try JapanThroughServices.loadBundled()).connectors) == .throughService)
    }

    @Test("Adjacent through-service legs join only at their anchor, not at a shared intermediate station")
    func throughServiceLegsJoinOnlyAtAnchors() throws {
        let package = try PortFixtures.package(country: "jp")
        let sobu = try #require(package.lines.first { $0.id == "jp-東日本旅客鉄道-総武線-3" })
        let tokaido = try #require(package.lines.first { $0.id == "jp-東日本旅客鉄道-東海道線" })
        // 新橋 lies on both rows between 東京 and 品川; no train changes rows there.
        #expect(TripConnectivity.link(from: tokaido, to: sobu, atStationCode: "003872", patterns: (try JapanThroughServices.loadBundled()).patterns, connectors: (try JapanThroughServices.loadBundled()).connectors) == .none)
        #expect(TripConnectivity.link(from: sobu, to: tokaido, atStationCode: "003872", patterns: (try JapanThroughServices.loadBundled()).patterns, connectors: (try JapanThroughServices.loadBundled()).connectors) == .none)
        // The same pair still joins at a listed anchor (東京).
        #expect(TripConnectivity.link(from: sobu, to: tokaido, atStationCode: "003766", patterns: (try JapanThroughServices.loadBundled()).patterns, connectors: (try JapanThroughServices.loadBundled()).connectors) != .none)
    }

    @Test("Keisei to Keikyu crosses only the anchored Asakusa corridor")
    func asakusa() throws {
        let package = try PortFixtures.package(country: "jp")
        let pattern = try #require((try JapanThroughServices.loadBundled()).patterns.first { $0.id == "asakusa-keisei-keikyu" })
        let choice = try #require(pattern.choices(package: package, originCode: "003203", destinationCode: "004368", connectors: (try JapanThroughServices.loadBundled()).connectors).first)
        #expect(choice.lineIDs.contains("jp-東京都-1号線浅草線"))
        #expect(choice.stations.contains { $0.code == "003526" })
        #expect(choice.stations.contains { $0.code == "004042" })
        #expect(!JapanThroughServices.continuationCodes(fromLineID: "jp-京成電鉄-押上線",
            toLineID: "jp-東京都-1号線浅草線", atStationCode: "003526", patterns: (try JapanThroughServices.loadBundled()).patterns, connectors: (try JapanThroughServices.loadBundled()).connectors).isEmpty)
        #expect(JapanThroughServices.continuationCodes(fromLineID: "jp-京成電鉄-押上線",
            toLineID: "jp-東京地下鉄-11号線半蔵門線", atStationCode: "003526", patterns: (try JapanThroughServices.loadBundled()).patterns, connectors: (try JapanThroughServices.loadBundled()).connectors).isEmpty)
    }

    @Test("Membership is bounded to operational leg anchors, not an entire physical row")
    func boundedMembership() throws {
        let package = try PortFixtures.package(country: "jp")
        let line = try #require(package.lines.first { $0.id == "jp-東日本旅客鉄道-東海道線" })
        #expect(JapanThroughServices.serviceCodes(line: line, fromStationCode: "003766", toStationCode: "003795", patterns: (try JapanThroughServices.loadBundled()).patterns).contains("JK"))
        #expect(!JapanThroughServices.serviceCodes(line: line, fromStationCode: "004961", toStationCode: "004997", patterns: (try JapanThroughServices.loadBundled()).patterns).contains("JK"))
        let fukuoka = try #require((try JapanThroughServices.loadBundled()).patterns.first { $0.id == "fukuoka-kuko-chikuhi" })
        #expect(!fukuoka.choices(package: package, originCode: "009015", destinationCode: "009278", connectors: (try JapanThroughServices.loadBundled()).connectors).isEmpty)
    }

    @Test("Reviewed Osaka through services use the west arc, including the Kyobashi seam",
           arguments: ["haruka", "kuroshio", "kansai-airport-rapid", "kishuji-rapid"])
    func osakaWestArc(id: String) throws {
        let package = try PortFixtures.package(country: "jp")
        let line = try #require(package.lines.first { $0.id == "jp-西日本旅客鉄道-大阪環状線" })
        let pattern = try #require((try JapanThroughServices.loadBundled()).patterns.first { $0.id == id })
        let leg = try #require(pattern.legs(on: nil).first { $0.lineID == line.id })
        #expect(leg.loopTraversal == "forward")
        #expect(!(leg.loopTraversalSourceURLs ?? []).isEmpty)
        // 福島→野田 is west of Osaka; 寺田町→桃谷 is on the unused east arc.
        #expect(JapanThroughServices.serviceCodes(line: line, fromStationCode: "007091",
            toStationCode: "007159", on: nil, patterns: [pattern]) == Set([pattern.serviceCode]))
        #expect(JapanThroughServices.serviceCodes(line: line, fromStationCode: "007434",
            toStationCode: "007380", on: nil, patterns: [pattern]).isEmpty)
        let south = try #require(pattern.choices(package: package,
            originCode: leg.fromStationCode, destinationCode: leg.toStationCode, connectors: (try JapanThroughServices.loadBundled()).connectors).first)
        let north = try #require(pattern.choices(package: package,
            originCode: leg.toStationCode, destinationCode: leg.fromStationCode, connectors: (try JapanThroughServices.loadBundled()).connectors).first)
        let expected = (leg.fromStationCode == "007093" ? ["京橋", "桜ノ宮", "天満"] : [])
            + ["大阪", "福島", "野田", "西九条", "弁天町", "大正", "芦原橋", "今宮", "新今宮", "天王寺"]
        #expect(south.stations.map(\.name) == expected)
        #expect(north.stations.map(\.name) == Array(expected.reversed()))
        if leg.fromStationCode == "007093" {
            let seam = try #require(RailIntervalCodes.intervals(for: line).last)
            #expect(south.sectionCodes.first == seam.code)
            #expect(north.sectionCodes.last == seam.code)
            #expect(JapanThroughServices.serviceCodes(line: line, fromStationCode: "007093",
                toStationCode: "007050", on: nil, patterns: [pattern]) == Set([pattern.serviceCode]))
        }
    }

    @Test("A reverse loop hint wraps the closing interval and preserves both journey orders")
    func reverseLoopTraversal() throws {
        let package = try loopPackage()
        let line = try #require(package.lines.first)
        let pattern = try loopPattern(from: "a", to: "e", hint: "reverse")
        let outbound = try #require(pattern.choices(package: package, originCode: "a", destinationCode: "e", connectors: (try JapanThroughServices.loadBundled()).connectors).first)
        let inbound = try #require(pattern.choices(package: package, originCode: "e", destinationCode: "a", connectors: (try JapanThroughServices.loadBundled()).connectors).first)
        #expect(outbound.stations.map(\.code) == ["a", "f", "e"])
        #expect(inbound.stations.map(\.code) == ["e", "f", "a"])
        #expect(JapanThroughServices.serviceCodes(line: line, fromStationCode: "a", toStationCode: "f",
            on: nil, patterns: [pattern]) == Set(["LP"]))
        #expect(JapanThroughServices.serviceCodes(line: line, fromStationCode: "a", toStationCode: "b",
            on: nil, patterns: [pattern]).isEmpty)
    }

    @Test("An invalid or unproved loop hint cannot supply a corridor", arguments: ["sideways", ""])
    func invalidLoopHint(hint: String) throws {
        let package = try loopPackage()
        let line = try #require(package.lines.first)
        let pattern = try loopPattern(from: "f", to: "c", hint: hint)
        #expect(pattern.choices(package: package, originCode: "f", destinationCode: "c", connectors: (try JapanThroughServices.loadBundled()).connectors).isEmpty)
        #expect(JapanThroughServices.serviceCodes(line: line, fromStationCode: "b", toStationCode: "c",
            on: nil, patterns: [pattern]).isEmpty)
        let unproved = try loopPattern(from: "f", to: "c", hint: "forward", sources: [])
        #expect(unproved.choices(package: package, originCode: "f", destinationCode: "c", connectors: (try JapanThroughServices.loadBundled()).connectors).isEmpty)
    }

    @Test("Unhinted loops retain the existing anchored linear interval")
    func unhintedLoopTraversal() throws {
        let package = try loopPackage()
        let pattern = try loopPattern(from: "f", to: "c", hint: nil)
        let choice = try #require(pattern.choices(package: package, originCode: "f", destinationCode: "c", connectors: (try JapanThroughServices.loadBundled()).connectors).first)
        #expect(choice.stations.map(\.code) == ["f", "e", "d", "c"])
        let nonloop = try fixture([line("loop", "Loop", ["a", "b", "c", "d", "e", "f"])])
        #expect(try loopPattern(from: "f", to: "c", hint: "forward")
            .choices(package: nonloop, originCode: "f", destinationCode: "c", connectors: (try JapanThroughServices.loadBundled()).connectors).isEmpty)
    }

    @Test("Service windows are ISO days inside their pattern interval")
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
        #expect(decoded.patterns[0].legVariants == nil)
        #expect(decoded.patterns[0].legs[0].validFrom == nil)
        #expect(decoded.patterns[0].legs[0].validTo == nil)
        for pattern in catalog.patterns {
            assertWindow(pattern.validFrom, pattern.validTo)
            for leg in pattern.legs {
                assertWindow(leg.validFrom, leg.validTo)
                #expect(windowContains(outerFrom: pattern.validFrom, outerTo: pattern.validTo,
                                       innerFrom: leg.validFrom, innerTo: leg.validTo))
            }
            for variant in pattern.legVariants ?? [] {
                assertWindow(variant.validFrom, variant.validTo)
                #expect(!variant.sourceURLs.isEmpty)
                if variant.suspended == true {
                    #expect(variant.legIndices.isEmpty)
                    #expect(variant.validFrom != nil && variant.validTo != nil)
                } else {
                    #expect(!variant.legIndices.isEmpty)
                }
                #expect(Set(variant.legIndices).count == variant.legIndices.count)
                #expect(variant.legIndices.allSatisfy { pattern.legs.indices.contains($0) })
            }
        }
        for connector in catalog.connectors {
            assertWindow(connector.validFrom, connector.validTo)
        }
    }

    @Test("Active legs stay contiguous and on the bundled package at every boundary date")
    func activeLegsStayAnchored() throws {
        let catalog = try JapanThroughServices.loadBundled()
        let package = try PortFixtures.package(country: "jp")
        for pattern in catalog.patterns {
            var dates: Set<String?> = [nil]
            for value in [pattern.validFrom, pattern.validTo]
                + pattern.legs.flatMap({ [$0.validFrom, $0.validTo] })
                + (pattern.legVariants ?? []).flatMap({ [$0.validFrom, $0.validTo] }) {
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
            on: "2013-03-15", patterns: [pattern], connectors: (try JapanThroughServices.loadBundled()).connectors) == Set(["DJ"]))
        #expect(JapanThroughServices.continuationCodes(
            fromLineID: "line-a", toLineID: "line-b", atStationCode: "join",
            on: "2013-03-16", patterns: [pattern], connectors: (try JapanThroughServices.loadBundled()).connectors).isEmpty)
        #expect(JapanThroughServices.continuationCodes(
            fromLineID: "line-a", toLineID: "line-b", atStationCode: "join",
            on: nil, patterns: [pattern], connectors: (try JapanThroughServices.loadBundled()).connectors).isEmpty)
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

    @Test("Removing an interior leg cannot invent a through junction or choice")
    func interiorFilteringRejectsPath() throws {
        let pattern = try sparsePattern()
        let package = try sparsePackage()
        #expect(pattern.legs(on: "2019-12-31").isEmpty)
        #expect(pattern.lineIDs(on: "2019-12-31").isEmpty)
        #expect(JapanThroughServices.continuationCodes(
            fromLineID: "line-a", toLineID: "line-b", atStationCode: "join",
            on: "2019-12-31", patterns: [pattern], connectors: []).isEmpty)
        #expect(pattern.choices(package: package, originCode: "a", destinationCode: "b",
            on: "2019-12-31", connectors: []).isEmpty)
        #expect(pattern.legs(on: "2020-01-01").count == 4)
    }

    @Test("Expired interior legs cannot invent a current through junction")
    func expiredInteriorRejectsCurrentPath() throws {
        let source = try sparsePattern()
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(source)) as? [String: Any])
        var legs = try #require(json["legs"] as? [[String: Any]])
        for index in [1, 2] {
            legs[index].removeValue(forKey: "validFrom")
            legs[index]["validTo"] = "2020-01-01"
        }
        json["legs"] = legs
        let pattern = try JSONDecoder().decode(JapanThroughServices.Pattern.self,
            from: JSONSerialization.data(withJSONObject: json))
        #expect(pattern.legs(on: "2019-12-31").count == 4)
        for date: String? in ["2020-01-01", nil] {
            #expect(pattern.legs(on: date).isEmpty)
            #expect(JapanThroughServices.continuationCodes(
                fromLineID: "line-a", toLineID: "line-b", atStationCode: "join",
                on: date, patterns: [pattern], connectors: []).isEmpty)
            #expect(pattern.choices(package: try sparsePackage(), originCode: "a",
                destinationCode: "b", on: date, connectors: []).isEmpty)
        }
    }

    @Test("An explicit historical variant permits a reviewed sparse path and selects the current path")
    func explicitSparseVariant() throws {
        let pattern = try sparsePattern(variants: """
        [{"validTo":"2020-01-01","legIndices":[0,3],"sourceURLs":["https://example.test/history"],"notes":"Reviewed direct junction"},
         {"validFrom":"2020-01-01","legIndices":[0,1,2,3],"sourceURLs":["https://example.test/current"],"notes":"Reviewed detour"}]
        """)
        let package = try sparsePackage()
        #expect(pattern.legs(on: "2019-12-31").map(\.lineID) == ["line-a", "line-b"])
        #expect(pattern.legs(on: "2020-01-01").map(\.lineID)
            == ["line-a", "line-detour", "line-return", "line-b"])
        #expect(pattern.legs(on: nil).map(\.lineID)
            == ["line-a", "line-detour", "line-return", "line-b"])
        #expect(JapanThroughServices.continuationCodes(
            fromLineID: "line-a", toLineID: "line-b", atStationCode: "join",
            on: "2019-12-31", patterns: [pattern], connectors: []) == Set(["SP"]))
        #expect(JapanThroughServices.continuationCodes(
            fromLineID: "line-a", toLineID: "line-b", atStationCode: "join",
            on: "2020-01-01", patterns: [pattern], connectors: []).isEmpty)
        let historical = try #require(pattern.choices(package: package, originCode: "a",
            destinationCode: "b", on: "2019-12-31", connectors: []).first)
        #expect(historical.stations.map(\.code) == ["a", "join", "b"])
        let current = try #require(pattern.choices(package: package, originCode: "a",
            destinationCode: "b", connectors: []).first)
        #expect(current.stations.map(\.code) == ["a", "join", "via", "join", "b"])
    }

    @Test("Variant windows are half open and an unmatched day never falls back to base legs")
    func unmatchedVariantDoesNotFallback() throws {
        let pattern = try sparsePattern(variants: """
        [{"validFrom":"2019-01-01","validTo":"2020-01-01","legIndices":[0,3],
          "sourceURLs":["https://example.test/history"],"notes":"Historical only"}]
        """)
        #expect(pattern.legs(on: "2018-12-31").isEmpty)
        #expect(pattern.legs(on: "2019-01-01").count == 2)
        #expect(pattern.legs(on: "2019-12-31").count == 2)
        #expect(pattern.legs(on: "2020-01-01").isEmpty)
        #expect(pattern.legs(on: nil).isEmpty)
    }

    @Test("A sourced one-day suspension has no base fallback and resumes the next day")
    func suspendedVariantDoesNotFallback() throws {
        let pattern = try sparsePattern(variants: """
        [{"validTo":"2023-02-12","legIndices":[0,1,2,3],"sourceURLs":["https://example.test/before"],"notes":"Before works"},
         {"validFrom":"2023-02-12","validTo":"2023-02-13","legIndices":[],"suspended":true,
          "sourceURLs":["https://example.test/works"],"notes":"Full-day suspension"},
         {"validFrom":"2023-02-13","legIndices":[0,1,2,3],"sourceURLs":["https://example.test/after"],"notes":"Resumed"}]
        """)
        let package = try sparsePackage()
        #expect(pattern.legs(on: "2023-02-11").count == 4)
        #expect(pattern.legs(on: "2023-02-12").isEmpty)
        #expect(pattern.lineIDs(on: "2023-02-12").isEmpty)
        #expect(pattern.choices(package: package, originCode: "a", destinationCode: "b",
            on: "2023-02-12", connectors: []).isEmpty)
        #expect(JapanThroughServices.continuationCodes(fromLineID: "line-a", toLineID: "line-detour",
            atStationCode: "join", on: "2023-02-12", patterns: [pattern], connectors: []).isEmpty)
        let line = try #require(package.lines.first { $0.id == "line-a" })
        #expect(JapanThroughServices.serviceCodes(line: line, fromStationCode: "a", toStationCode: "join",
            on: "2023-02-12", patterns: [pattern]).isEmpty)
        #expect(pattern.legs(on: "2023-02-13").count == 4)
        #expect(pattern.legs(on: nil).count == 4)
    }

    @Test("Overlapping variants invalidate the path even outside their overlap")
    func overlappingVariantsRejectPath() throws {
        let pattern = try sparsePattern(variants: """
        [{"validTo":"2021-01-01","legIndices":[0,3],"sourceURLs":["https://example.test/history"],"notes":""},
         {"validFrom":"2020-01-01","legIndices":[0,1,2,3],"sourceURLs":["https://example.test/current"],"notes":""}]
        """)
        for date: String? in ["2019-12-31", "2020-01-01", "2021-01-01", nil] {
            #expect(pattern.legs(on: date).isEmpty)
        }
    }

    @Test("Malformed variants cannot select any path", arguments: [
        #"{"legIndices":[],"sourceURLs":["https://example.test"],"notes":""}"#,
        #"{"suspended":true,"legIndices":[],"sourceURLs":["https://example.test"],"notes":""}"#,
        #"{"suspended":true,"validFrom":"2020-01-01","legIndices":[],"sourceURLs":["https://example.test"],"notes":""}"#,
        #"{"suspended":true,"validTo":"2020-01-02","legIndices":[],"sourceURLs":["https://example.test"],"notes":""}"#,
        #"{"suspended":true,"validFrom":"2020-01-01","validTo":"2020-01-02","legIndices":[0,3],"sourceURLs":["https://example.test"],"notes":""}"#,
        #"{"legIndices":[0,0,3],"sourceURLs":["https://example.test"],"notes":""}"#,
        #"{"legIndices":[-1,3],"sourceURLs":["https://example.test"],"notes":""}"#,
        #"{"legIndices":[0,4],"sourceURLs":["https://example.test"],"notes":""}"#,
        #"{"validFrom":"2020-02-30","legIndices":[0,3],"sourceURLs":["https://example.test"],"notes":""}"#,
        #"{"validFrom":"1900-02-29","legIndices":[0,3],"sourceURLs":["https://example.test"],"notes":""}"#,
        #"{"validFrom":"2020-1-1","legIndices":[0,3],"sourceURLs":["https://example.test"],"notes":""}"#,
        #"{"validTo":"2020-13-01","legIndices":[0,3],"sourceURLs":["https://example.test"],"notes":""}"#,
        #"{"validFrom":"2020-01-01","validTo":"2020-01-01","legIndices":[0,3],"sourceURLs":["https://example.test"],"notes":""}"#,
        #"{"validFrom":"2021-01-01","validTo":"2020-01-01","legIndices":[0,3],"sourceURLs":["https://example.test"],"notes":""}"#,
        #"{"legIndices":[0,3],"sourceURLs":[],"notes":""}"#,
        #"{"legIndices":[0,3],"sourceURLs":["file:///tmp/history"],"notes":""}"#
    ])
    func invalidVariantRejectsPath(variant: String) throws {
        let pattern = try sparsePattern(variants: "[\(variant)]")
        for date: String? in ["2019-12-31", "2020-01-01", nil] {
            #expect(pattern.legs(on: date).isEmpty)
        }
    }

    @Test("Variants still obey pattern and leg windows without inventing another interior junction")
    func variantRespectsOtherWindows() throws {
        let source = try sparsePattern(variants: """
        [{"legIndices":[0,1,2,3],"sourceURLs":["https://example.test/current"],"notes":""}]
        """)
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(source)) as? [String: Any])
        json["validFrom"] = "2019-01-01"
        json["validTo"] = "2021-01-01"
        let pattern = try JSONDecoder().decode(JapanThroughServices.Pattern.self,
            from: JSONSerialization.data(withJSONObject: json))
        #expect(pattern.legs(on: "2018-12-31").isEmpty)
        #expect(pattern.legs(on: "2019-12-31").isEmpty)
        #expect(pattern.legs(on: "2020-01-01").count == 4)
        #expect(pattern.legs(on: "2021-01-01").isEmpty)
        #expect(pattern.legs(on: nil).isEmpty)
    }

    @Test("Filtering dated prefixes and suffixes retains a contiguous interior path")
    func filteringEndLegsRetainsPath() throws {
        let pattern = try decodePattern("""
        {"id":"trim","serviceCode":"TR","name":"Trim","aliases":[],"kind":"throughRunning",
         "legs":[
           {"lineID":"prefix","fromStationCode":"p","toStationCode":"a","validTo":"2020-01-01"},
           {"lineID":"line-a","fromStationCode":"a","toStationCode":"join"},
           {"lineID":"line-b","fromStationCode":"join","toStationCode":"b"},
           {"lineID":"suffix","fromStationCode":"b","toStationCode":"s","validTo":"2020-01-01"}
         ],"sourceURLs":["https://example.test"],"notes":""}
        """)
        #expect(pattern.legs(on: "2020-01-01").map(\.lineID) == ["line-a", "line-b"])
        #expect(pattern.legs(on: nil).map(\.lineID) == ["line-a", "line-b"])
        #expect(JapanThroughServices.continuationCodes(
            fromLineID: "line-a", toLineID: "line-b", atStationCode: "join",
            on: nil, patterns: [pattern], connectors: []) == Set(["TR"]))
        #expect(!pattern.choices(package: try sparsePackage(), originCode: "a",
            destinationCode: "b", connectors: []).isEmpty)
    }

    @Test("Catalog coverage limits unspecified starts without concealing explicit earlier evidence")
    func coverageBoundsUnspecifiedStarts() throws {
        let catalog = try JSONDecoder().decode(JapanThroughServices.Catalog.self, from: Data("""
        {"coverageFrom":"2005-01-01","checkedAt":"2020-01-01","scope":"test","patterns":[
          {"id":"JK","serviceCode":"JK","name":"Unspecified start","aliases":[],"kind":"throughRunning",
           "legs":[{"lineID":"line-a","fromStationCode":"a","toStationCode":"b"}],
           "sourceURLs":["https://example.test/current"],"notes":""},
          {"id":"early","serviceCode":"EARLY","name":"Explicit start","aliases":[],"kind":"throughRunning","validFrom":"1997-01-01",
           "legs":[{"lineID":"line-a","fromStationCode":"a","toStationCode":"b"}],
           "sourceURLs":["https://example.test/early"],"notes":""}
        ],"coverage":[]}
        """.utf8))
        let constructed = JapanThroughServices.Catalog(coverageFrom: "2005-01-01", checkedAt: "test",
            scope: "test", patterns: catalog.patterns, coverage: [])
        for candidate in [catalog, constructed] {
            let unspecified = try #require(candidate.patterns.first { $0.id == "JK" })
            let explicit = try #require(candidate.patterns.first { $0.id == "early" })
            #expect(unspecified.legs(on: "1996-12-31").isEmpty)
            #expect(unspecified.legs(on: "2004-12-31").isEmpty)
            #expect(unspecified.legs(on: "2005-01-01").count == 1)
            #expect(unspecified.legs(on: nil).count == 1)
            #expect(explicit.legs(on: "1996-12-31").isEmpty)
            #expect(explicit.legs(on: "1997-01-01").count == 1)
            #expect(JapanThroughServices.patterns(on: "1997-01-01", patterns: candidate.patterns).map(\.id)
                == ["early"])
        }
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(catalog)) as? [String: Any])
        let encodedPatterns = try #require(json["patterns"] as? [[String: Any]])
        #expect(encodedPatterns.allSatisfy { $0["catalogCoverageFrom"] == nil })
        let standalone = try JSONDecoder().decode(JapanThroughServices.Pattern.self,
            from: JSONSerialization.data(withJSONObject: encodedPatterns[0]))
        #expect(standalone.legs(on: "1996-12-31").count == 1)
        let boundedStandalone = JapanThroughServices.Catalog(coverageFrom: "2005-01-01",
            checkedAt: "test", scope: "test", patterns: [standalone], coverage: [])
        #expect(boundedStandalone.patterns[0].legs(on: "1996-12-31").isEmpty)
        #expect(boundedStandalone.patterns[0].legs(on: "2005-01-01").count == 1)
        json.removeValue(forKey: "coverageFrom")
        let legacy = try JSONDecoder().decode(JapanThroughServices.Catalog.self,
            from: JSONSerialization.data(withJSONObject: json))
        #expect(legacy.patterns[0].legs(on: "1996-12-31").count == 1)
        let withoutCoverage = JapanThroughServices.Catalog(checkedAt: "test", scope: "test",
            patterns: catalog.patterns, coverage: [])
        #expect(withoutCoverage.patterns[0].legs(on: "1996-12-31").count == 1)
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
                                      on: "2013-03-15", patterns: [pattern], connectors: (try JapanThroughServices.loadBundled()).connectors) == .throughService)
        #expect(TripConnectivity.link(from: from, to: to, atStationCode: "join",
                                      on: "2013-03-16", patterns: [pattern], connectors: (try JapanThroughServices.loadBundled()).connectors) != .throughService)
        #expect(TripConnectivity.link(from: from, to: to, atStationCode: "join",
                                      on: nil, patterns: [pattern], connectors: (try JapanThroughServices.loadBundled()).connectors) != .throughService)
    }

    private func assertWindow(_ from: String?, _ to: String?) {
        if let from {
            #expect(isISODay(from))
        }
        if let to {
            #expect(isISODay(to))
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

    private func sparsePattern(variants: String? = nil) throws -> JapanThroughServices.Pattern {
        try decodePattern("""
        {"id":"sparse","serviceCode":"SP","name":"Sparse","aliases":[],"kind":"throughRunning",
         "legs":[
           {"lineID":"line-a","fromStationCode":"a","toStationCode":"join"},
           {"lineID":"line-detour","fromStationCode":"join","toStationCode":"via","validFrom":"2020-01-01"},
           {"lineID":"line-return","fromStationCode":"via","toStationCode":"join","validFrom":"2020-01-01"},
           {"lineID":"line-b","fromStationCode":"join","toStationCode":"b"}
         ],"sourceURLs":["https://example.test/sparse"],"notes":""
         \(variants.map { ",\"legVariants\":\($0)" } ?? "")}
        """)
    }

    private func sparsePackage() throws -> CompactPackage {
        try fixture([
            line("line-a", "Alpha", ["a", "join"]),
            line("line-detour", "Detour", ["join", "via"]),
            line("line-return", "Return", ["via", "join"]),
            line("line-b", "Beta", ["join", "b"])
        ])
    }

    private func loopPattern(from: String, to: String, hint: String?,
                             sources: [String] = ["https://example.test/loop"]) throws -> JapanThroughServices.Pattern {
        JapanThroughServices.Pattern(id: "loop-pattern", serviceCode: "LP", name: "Loop", aliases: [],
            kind: .throughRunning, legs: [.init(lineID: "loop", fromStationCode: from, toStationCode: to,
                loopTraversal: hint, loopTraversalSourceURLs: sources)], sourceURLs: ["https://example.test/loop"],
            notes: "", validFrom: nil, validTo: nil)
    }

    private func loopPackage() throws -> CompactPackage {
        var row = line("loop", "Loop", ["a", "b", "c", "d", "e", "f"])
        row["isLoop"] = 1
        var segments = try #require(row["segments"] as? [[Any]])
        segments.append([1.0, 0, [[5.0, 0.0], [0.0, 0.0]]])
        row["segments"] = segments
        return try fixture([row])
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
