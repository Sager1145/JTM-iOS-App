import Foundation
import Testing
@testable import RailCore

struct JunctionApproachTests {
    private struct JunctionDocument: Decodable {
        struct Record: Decodable {
            let id: String
            let region: String
            let station: String
            let validFrom: String?
        }
        let junctions: [Record]
    }

    private struct SampleManifest: Decodable {
        let parts: [String]
        let partTrainIDs: [String: String]

        enum CodingKeys: String, CodingKey {
            case parts
            case partTrainIDs = "part_train_ids"
        }
    }

    private struct SamplePart: Decodable { let train: Train }

    private struct BoundaryGap {
        let station: String
        let previous: String?
        let first: String?
    }

    private struct Census {
        var boundaryGapsByRide: [String: [BoundaryGap]] = [:]
        var zeroGapRides = 0
        var boundaryByStation: [String: Int] = [:]
        var remaining: [String] = []
        var nonBoundaryFailures = 0
        var failuresByCause: [String: Int] = [:]
        var gapsByRide: [String: PhysicalEndpointTrimTests.GapCounts] = [:]
    }

    private let originalJunctionIDs: Set<String> = [
        "oshiage-tobu-hanzomon", "oshiage-keisei-asakusa",
        "shibuya-denentoshi-hanzomon", "shibuya-toyoko-fukutoshin",
        "chayamachi-uno-honshi-bisan", "kojima-honshi-bisan-operator-boundary",
        "shiojiri-chuo-shinonoi", "iwanuma-joban-tohoku",
        "utazu-honshi-bisan-yosan-eastern-bypass",
        "utazu-honshi-bisan-yosan-station-arm",
    ]

    private func point(_ meters: Double) -> Coordinate {
        Coordinate(lon: 139 + meters / (111_320 * cos(35 * .pi / 180)), lat: 35)
    }

    private func identity(_ line: String) -> RouteGraph.TrackIdentity {
        .init(operatorName: "Operator", lineName: line, railwayClassCode: "")
    }

    private func key(_ meters: Double, _ line: String) -> String {
        RouteGraph.physicalNodeKey(point(meters), identity: identity(line))
    }

    private func rail(_ from: Double, _ to: Double, _ line: String,
                      validFrom: String? = nil) -> RouteGraph.SectionFeature {
        .init(properties: .init(lineName: line, operator: "Operator",
            institutionTypeCode: "1", validFrom: validFrom), lines: [[point(from), point(to)]])
    }

    private func junction(
        _ meters: Double, _ from: String, _ to: String,
        station: String? = nil, stationCode: String? = nil
    ) -> RouteGraph.PhysicalJunction {
        .init(id: "\(from)-\(to)", from: .init(identity: identity(from), coordinate: point(meters)),
            to: .init(identity: identity(to), coordinate: point(meters)), evidence: ["survey:reviewed"],
            validFrom: "2020-01-01", validTo: "2030-01-01",
            station: station, stationCode: stationCode)
    }

    private func station(
        _ point: Coordinate, code: String, name: String, group: String, line: String
    ) -> Stations.Feature {
        .init(properties: [
            "n02_station_code": .string(code), "n02_group_code": .string(group),
            "station_name": .string(name), "line_name": .string(line),
            "operator": .string("Operator"), "institution_type_code": .string("1"),
        ], geometry: .init(type: "Point", coordinates: .array([
            .number(point.lon), .number(point.lat),
        ])))
    }

    @Test("Reviewed junction approaches are bounded on both sides and date-valid")
    func approaches() {
        for (left, right, expected) in [(300.0, 300.0, true), (1600, 300, false), (300, 1600, false)] {
            let features = [rail(-left, 0, "West"), rail(0, right, "East")]
            let graph = RouteGraph.build(from: features, junctions: [junction(0, "West", "East")])
            for (from, to) in [(key(-left, "West"), key(right, "East")),
                               (key(right, "East"), key(-left, "West"))] {
                #expect(RouteSolver.physicalBoundaryIsProven(from: from, to: to,
                    graph: graph, rideDate: "2026-01-01") == expected)
                for date in ["2019-12-31", "2031-01-01"] {
                    #expect(!RouteSolver.physicalBoundaryIsProven(from: from, to: to,
                        graph: graph, rideDate: date))
                }
                #expect(!RouteSolver.physicalBoundaryIsProven(from: from, to: to,
                    graph: RouteGraph.build(from: features), rideDate: "2026-01-01"))
            }
        }
    }

    @Test("Connectors and unreviewed identity changes cannot prove an approach")
    func excludedEdges() {
        for connector in [false, true] {
            let graph = RouteGraph.build(from: [rail(-300, 0, "West"), rail(0, 300, "East")])
            graph.adjacency[key(0, "West"), default: []].append(.init(
                to: key(0, "East"), length: 0, institutionTypeCode: "1", railwayClassCode: "",
                lineName: "East", operator: "Operator", connector: connector
                    ? .init(institutionTypeCodes: ["1"], stationName: "Central", groupCode: "shared") : nil))
            #expect(!RouteSolver.physicalBoundaryIsProven(from: key(-300, "West"), to: key(300, "East"),
                graph: graph, rideDate: "2026-01-01"))
        }
        let graph = RouteGraph.build(from: [rail(-300, 0, "West", validFrom: "2027-01-01"),
            rail(0, 300, "East")], junctions: [junction(0, "West", "East")])
        #expect(!RouteSolver.physicalBoundaryIsProven(from: key(-300, "West"), to: key(300, "East"),
            graph: graph, rideDate: "2026-01-01"))
    }

    @Test("At most two junctions are allowed, with a bounded intervening span")
    func chains() {
        for span in [300.0, 1600.0] {
            let graph = RouteGraph.build(from: [rail(-300, 0, "West"), rail(0, span, "Middle"),
                rail(span, span + 300, "East"), rail(span + 300, span + 600, "Beyond")], junctions: [
                    junction(0, "West", "Middle"), junction(span, "Middle", "East"),
                    junction(span + 300, "East", "Beyond")])
            #expect(RouteSolver.physicalBoundaryIsProven(from: key(-300, "West"),
                to: key(span + 300, "East"), graph: graph, rideDate: "2026-01-01") == (span == 300))
            #expect(!RouteSolver.physicalBoundaryIsProven(from: key(-300, "West"),
                to: key(span + 600, "Beyond"), graph: graph, rideDate: "2026-01-01"))
        }
        let graph = RouteGraph.build(from: [rail(0, 600, "West")])
        #expect(!RouteSolver.physicalBoundaryIsProven(from: key(0, "West"), to: key(600, "West"),
            graph: graph, rideDate: nil))
    }

    @Test("Nanpu 28 sample sections prove boundaries at Utazu, Kojima and Chayamachi")
    func sampleRideBoundaries() throws {
        struct Store: Decodable { let trains: [Train] }
        let data = try PortFixtures.repositoryRoot().appending(path: "app/data")
        let store = try JSONDecoder().decode(Store.self, from: Data(contentsOf: data.appending(path: "train-store.json")))
        let train = try #require(store.trains.first { $0.id == "20260724_06_nanpu28" })
        let sections = try #require(train.routeSections)
        let features = try RouteGraph.SectionFeatureCollection.load(contentsOf: data.appending(path: "rail-sections.json")).features.filter {
            ["宇野線", "本四備讃線", "予讃線"].contains($0.properties.lineName)
        }
        let stations = Stations.Index(try Stations.FeatureCollection.load(contentsOf: data.appending(path: "stations.json")).features)
        let registry = try PhysicalRailJunctionRegistry(data: Data(contentsOf: data.appending(path: "physical-rail-junctions.json")))
        let graph = RouteGraph.build(from: features, junctions: registry.junctions(for: "jp"))
        for code in ["008252", "007919", "007663"] {
            let index = try #require(sections.indices.first { sections[$0].fromN02StationCode == code })
            try #require(index > 0)
            let context = RouteSolver.TrainContext(company: train.company ?? "", rideDate: train.date)
            let before = try #require(RouteSolver.solveSection(sections[index - 1], segmentIndex: index - 1,
                train: context, country: "jp", graph: graph, stations: stations))
            let after = try #require(RouteSolver.solveSection(sections[index], segmentIndex: index,
                train: context, country: "jp", graph: graph, stations: stations))
            let from = try #require(before.rawPathKeys.last)
            let to = try #require(after.rawPathKeys.first)
            #expect(RouteSolver.physicalBoundaryIsProven(from: from, to: to, graph: graph, rideDate: train.date))
        }
    }

    @Test("Expanded junction registry closes reviewed sample-ride boundary gaps")
    func realDataJunctionCensus() throws {
        let root = try PortFixtures.repositoryRoot()
        let dataRoot = root.appending(path: "app/data")
        let registryURL = dataRoot.appending(path: "physical-rail-junctions.json")
        let registryData = try Data(contentsOf: registryURL)
        let document = try JSONDecoder().decode(JunctionDocument.self, from: registryData)
        let registry = try PhysicalRailJunctionRegistry(data: registryData)
        let fullJunctions = registry.junctions(for: "jp")
        let baselineJunctions = fullJunctions.filter { originalJunctionIDs.contains($0.id) }
        let addedRecords = document.junctions.filter {
            $0.region == "jp" && !originalJunctionIDs.contains($0.id)
        }

        #expect(baselineJunctions.count == 10)
        #expect(addedRecords.count == 171)
        #expect(Set(addedRecords.map(\.station)).count == 143)

        try assertRegistryAccepted(dataRoot: dataRoot, junctions: fullJunctions)

        let manifest = try JSONDecoder().decode(SampleManifest.self, from: Data(contentsOf:
            dataRoot.appending(path: "sample-data/manifest.json")))
        let store = try JSONDecoder().decode(TrainStore.self, from: Data(contentsOf:
            dataRoot.appending(path: "train-store.json")))
        let indexedIDs = Set(store.trains.filter { $0.region == nil || $0.region == "jp" }.map(\.id))
        #expect(manifest.parts.count == indexedIDs.count)
        #expect(Set(manifest.partTrainIDs.values) == indexedIDs)

        let pipeline = PhysicalEndpointTrimTests()
        var trains: [Train] = []
        for partName in manifest.parts {
            let expectedID = try #require(manifest.partTrainIDs[partName])
            let part = try JSONDecoder().decode(SamplePart.self, from: Data(contentsOf:
                dataRoot.appending(path: "sample-data/\(partName).json")))
            #expect(part.train.id == expectedID)
            let normalized = pipeline.normalizedSampleTrain(part.train)
            try #require(normalized.routeSections?.isEmpty == false,
                "Sample pipeline produced no sections for \(expectedID)")
            trains.append(normalized)
        }

        let baseline = try census(trains: trains,
            data: pipeline.loadRealData(root: root, junctions: baselineJunctions), pipeline: pipeline)
        let expanded = try census(trains: trains,
            data: pipeline.loadRealData(root: root, junctions: fullJunctions), pipeline: pipeline,
            captureStations: Set(addedRecords.map(\.station)))
        printCensus("baseline (original 10 junctions)", census: baseline, total: trains.count)
        printCensus("expanded registry", census: expanded, total: trains.count)

        let oki = try #require(expanded.gapsByRide["20260719_03_super_oki5"])
        #expect(oki.boundaryStations.isEmpty)
        #expect(oki.nonBoundary == 0)

        let reviewedJunctions = try addedRecords.map { record in
            (station: record.station,
             validFrom: try #require(record.validFrom, "Missing validFrom for \(record.id)"),
             junction: try #require(fullJunctions.first { $0.id == record.id }))
        }
        for train in trains {
            let rideDate = try #require(Dates.normalizeDateString(train.date),
                "Missing ride date for \(train.id)")
            _ = try #require(expanded.gapsByRide[train.id])
            for gap in expanded.boundaryGapsByRide[train.id] ?? [] {
                guard let previous = physicalIdentityKey(gap.previous),
                      let first = physicalIdentityKey(gap.first) else { continue }
                for reviewed in reviewedJunctions where reviewed.station == gap.station
                    && rideDate >= reviewed.validFrom {
                    let from = physicalIdentityKey(RouteGraph.physicalNodeKey(
                        reviewed.junction.from.coordinate, identity: reviewed.junction.from.identity))
                    let to = physicalIdentityKey(RouteGraph.physicalNodeKey(
                        reviewed.junction.to.coordinate, identity: reviewed.junction.to.identity))
                    guard (previous == from && first == to)
                        || (previous == to && first == from) else { continue }
                    Issue.record("\(train.id) retains a boundary gap at \(gap.station) on \(rideDate); junction \(reviewed.junction.id) valid from \(reviewed.validFrom)")
                }
            }
        }
    }

    @Test("新大阪→大阪 and 大阪→天王寺 prove at the reviewed 大阪 vertex")
    func osakaSectionsProveAtReviewedVertex() throws {
        let root = try PortFixtures.repositoryRoot()
        let pipeline = PhysicalEndpointTrimTests()
        let data = try pipeline.loadRealData(root: root)
        let date = "2026-10-03"
        let tokaido = try #require(displayLine(data.network, name: "東海道線", stations: ["新大阪", "大阪"]))
        let loop = try #require(displayLine(data.network, name: "大阪環状線", stations: ["大阪", "天王寺"]))
        let shinOsaka = try #require(tokaido.compactLine?.stations.first { $0.name == "新大阪" }?.id)
        let tokaidoOsaka = try #require(tokaido.compactLine?.stations.first { $0.name == "大阪" }?.id)
        let loopOsaka = try #require(loop.compactLine?.stations.first { $0.name == "大阪" }?.id)
        let tennoji = try #require(loop.compactLine?.stations.first { $0.name == "天王寺" }?.id)
        let west = try #require(sourceKeys(
            line: tokaido, from: shinOsaka, to: tokaidoOsaka, data: data, pipeline: pipeline, date: date),
            "東海道線 \(shinOsaka)→\(tokaidoOsaka)")
        let east = try #require(sourceKeys(
            line: loop, from: loopOsaka, to: tennoji, data: data, pipeline: pipeline, date: date),
            "大阪環状線 \(loopOsaka)→\(tennoji)")
        let previousKey = try #require(west.keys.last)
        let firstKey = try #require(east.keys.first)
        let graph = pipeline.proofGraph(east.coordinates, store: data.graphStore)
        #expect(graph.nodes[previousKey] != nil)
        #expect(!RouteSolver.physicalBoundaryIsProven(
            from: previousKey, to: firstKey, graph: graph, rideDate: date))
        let previous = RouteSection(
            from: "新大阪", to: "大阪", fromN02StationCode: shinOsaka, toN02StationCode: loopOsaka,
            lineNames: ["東海道線"], operatorNames: ["西日本旅客鉄道"])
        let next = RouteSection(
            from: "大阪", to: "天王寺", fromN02StationCode: loopOsaka, toN02StationCode: tennoji,
            lineNames: ["大阪環状線"], operatorNames: ["西日本旅客鉄道"])
        let pair = try #require(RouteSolver.provenBoundaryContinuation(
            previous: previousKey, first: firstKey, previousSection: previous, nextSection: next,
            graph: graph, stations: data.stations, rideDate: date))
        let vertex = Grid.normalizeGraphCoord(Coordinate(lon: 135.48736, lat: 34.69757))
        let atVertex = graph.nodes.filter { $0.value == vertex }.map(\.key)
        let vertexPrevious = try #require(atVertex.first {
            physicalIdentityKey($0) == physicalIdentityKey(previousKey)
        })
        let vertexFirst = try #require(atVertex.first {
            physicalIdentityKey($0) == physicalIdentityKey(firstKey)
        })
        #expect(RouteSolver.physicalBoundaryIsProven(
            from: vertexPrevious, to: vertexFirst, graph: graph, rideDate: date))
        #expect(pair.previous == pair.first
            || RouteSolver.physicalBoundaryIsProven(
                from: pair.previous, to: pair.first, graph: graph, rideDate: date))
        var unmatched = next
        unmatched.fromN02StationCode = tokaidoOsaka == loopOsaka ? "007091" : tokaidoOsaka
        #expect(unmatched.fromN02StationCode != previous.toN02StationCode)
        #expect(RouteSolver.provenStationBoundaryPair(
            from: previousKey, to: firstKey, previousSection: previous, nextSection: unmatched,
            graph: graph, stations: data.stations, rideDate: date) == nil)
    }

    @Test("A distant reviewed vertex proves only when the stop code is shared")
    func stationBoundaryPairRetriesOnlyASharedCode() {
        let far = 2_000.0
        let features = [
            rail(0, 100, "West"), rail(0, -100, "East"),
            rail(far, far + 100, "West"), rail(far, far - 100, "East"),
        ]
        let joined = RouteGraph.build(from: features, junctions: [
            junction(far, "West", "East", station: "Central", stationCode: "S"),
        ])
        let stations = Stations.Index([
            station(point(0), code: "W", name: "Central", group: "S", line: "West"),
            station(point(0), code: "E", name: "Central", group: "S", line: "East"),
        ])
        let previous = RouteSection(
            to: "Central", toN02StationCode: "S", lineNames: ["West"], operatorNames: ["Operator"])
        let next = RouteSection(
            from: "Central", fromN02StationCode: "S", lineNames: ["East"], operatorNames: ["Operator"])
        let west = key(0, "West")
        let east = key(0, "East")
        let date = "2026-10-03"
        #expect(!RouteSolver.physicalBoundaryIsProven(from: west, to: east, graph: joined, rideDate: date))
        let pair = RouteSolver.provenStationBoundaryPair(
            from: west, to: east, previousSection: previous, nextSection: next,
            graph: joined, stations: stations, rideDate: date)
        #expect(pair?.previous == key(far, "West"))
        #expect(pair?.first == key(far, "East"))
        var otherCode = next
        otherCode.fromN02StationCode = "E"
        #expect(RouteSolver.provenStationBoundaryPair(
            from: west, to: east, previousSection: previous, nextSection: otherCode,
            graph: joined, stations: stations, rideDate: date) == nil)
        var unnamed = next
        unnamed.fromN02StationCode = nil
        #expect(RouteSolver.provenBoundaryContinuation(
            previous: west, first: east, previousSection: previous, nextSection: unnamed,
            graph: joined, stations: stations, rideDate: date) == nil)
        #expect(RouteSolver.provenStationBoundaryPair(
            from: west, to: east, previousSection: previous, nextSection: next,
            graph: joined, stations: stations, rideDate: "2019-01-01") == nil)
        let open = RouteGraph.build(from: features)
        #expect(RouteSolver.provenStationBoundaryPair(
            from: west, to: east, previousSection: previous, nextSection: next,
            graph: open, stations: stations, rideDate: date) == nil)
    }

    private func displayLine(
        _ network: RouteNetwork, name: String, stations: [String]
    ) -> RouteNetwork.Line? {
        network.lines.first { line in
            line.name == name && line.operator == "西日本旅客鉄道" && line.alignmentDirection == nil
                && stations.allSatisfy { station in
                    line.compactLine?.stations.contains { $0.name == station } == true
                }
        }
    }

    private func sourceKeys(
        line: RouteNetwork.Line, from: String, to: String,
        data: PhysicalEndpointTrimTests.RealData, pipeline: PhysicalEndpointTrimTests, date: String
    ) -> (keys: [String], coordinates: [Coordinate])? {
        guard let stations = line.compactLine?.stations.map(\.id),
              let start = stations.firstIndex(of: from), let end = stations.firstIndex(of: to),
              start != end else { return nil }
        let step = start < end ? 1 : -1
        var index = start
        var codes: [String] = []
        while index != end {
            let next = index + step
            guard line.intervals.indices.contains(min(index, next)) else { return nil }
            codes.append(line.intervals[min(index, next)].code)
            index = next
        }
        let section = RouteSection(
            fromN02StationCode: from, toN02StationCode: to,
            lineNames: line.name.map { [$0] }, operatorNames: line.operator.map { [$0] })
        let hints = RouteHints(
            requiredLineIDs: [line.lineId], sectionCodes: codes, fromStationCode: from, toStationCode: to)
        guard let source = data.network.sourceGeometry(for: hints) else { return nil }
        let coordinates = source.lines.flatMap { $0 }
        let graph = pipeline.proofGraph(coordinates, store: data.graphStore)
        guard let keys = RouteSolver.verifiedSourcePath(
            source.lines, graph: graph, context: .init(rideDate: date), section: section) else { return nil }
        return (keys, coordinates)
    }

    private func physicalIdentityKey(_ key: String?) -> String? {
        guard let key, let separator = key.lastIndex(of: "@") else { return nil }
        return String(key[..<separator])
    }

    private func assertRegistryAccepted(
        dataRoot: URL, junctions: [RouteGraph.PhysicalJunction]
    ) throws {
        var features = try RouteGraph.SectionFeatureCollection.load(
            contentsOf: dataRoot.appending(path: "rail-sections.json")).features
        var stationFeatures = try Stations.FeatureCollection.load(
            contentsOf: dataRoot.appending(path: "stations.json")).features
        let overlay = try RailHistoryOverlay.load(from: dataRoot.appending(path: "rail-history.json"))
        _ = RailHistory.apply(overlay, sections: &features, stations: &stationFeatures)
        let graph = RouteGraph.build(from: features, junctions: junctions)
        #expect(graph.rejectedPhysicalJunctionIDs.isEmpty,
            "Rejected registry junctions: \(graph.rejectedPhysicalJunctionIDs)")
    }

    private func census(
        trains: [Train], data: PhysicalEndpointTrimTests.RealData,
        pipeline: PhysicalEndpointTrimTests, captureStations: Set<String> = []
    ) throws -> Census {
        var result = Census()
        for train in trains {
            let counts = try pipeline.gapCounts(train: train, data: data)
            result.gapsByRide[train.id] = counts
            if !captureStations.isDisjoint(with: counts.boundaryStations) {
                let gaps = try boundaryGapIdentities(train: train, data: data, pipeline: pipeline)
                result.boundaryGapsByRide[train.id] = gaps
                #expect(gaps.map(\.station) == counts.boundaryStations)
                for gap in gaps where gap.station == "南千歳" {
                    print("Boundary identities \(train.id) at \(gap.station): previous=\(gap.previous ?? "nil"), first=\(gap.first ?? "nil")")
                }
            }
            if counts.boundaryStations.isEmpty && counts.nonBoundary == 0 {
                result.zeroGapRides += 1
            }
            result.nonBoundaryFailures += counts.nonBoundary
            for (reason, count) in counts.reasons {
                result.failuresByCause[reason, default: 0] += count
            }
            for station in counts.boundaryStations {
                result.boundaryByStation[station, default: 0] += 1
                result.remaining.append("\(train.id)@\(train.date ?? "unknown"):boundary:\(station)")
            }
            if counts.nonBoundary > 0 {
                result.remaining.append("\(train.id)@\(train.date ?? "unknown"):non-boundary:\(counts.nonBoundary)")
            }
        }
        return result
    }

    // Mirrors the sample pipeline to retain the exact keys used by its boundary proof.
    private func boundaryGapIdentities(
        train: Train, data: PhysicalEndpointTrimTests.RealData, pipeline: PhysicalEndpointTrimTests
    ) throws -> [BoundaryGap] {
        let sections = train.routeSections ?? []
        try #require(sections.isEmpty == false)
        let context = RouteSolver.TrainContext(
            id: train.id, number: train.number, trainType: train.trainType ?? "",
            company: train.company ?? "", origin: train.origin, destination: train.destination,
            preferredLineNames: train.routePolicy?.preferredLineNames ?? [],
            preferredOperatorNames: train.routePolicy?.preferredOperatorNames ?? [],
            allowedInstitutionTypeCodes: train.routePolicy?.allowedInstitutionTypeCodes,
            institutionFilterMode: train.routePolicy?.institutionFilterMode ?? "soft",
            rideDate: Dates.normalizeDateString(train.date))
        let allowedCodes = RouteGraph.allowedInstitutionTypeCodes(.init(
            trainType: context.trainType, company: context.company,
            preferredLineNames: context.preferredLineNames,
            preferredOperatorNames: context.preferredOperatorNames,
            allowedInstitutionTypeCodes: context.allowedInstitutionTypeCodes,
            institutionFilterMode: context.institutionFilterMode), country: "jp")
        let inferred = RouteSolver.inferStationSections(
            sections, resolver: data.resolver, network: data.network, eligibility: data.eligibility,
            allowedCodes: allowedCodes, hard: context.institutionFilterMode == "hard")

        var gaps: [BoundaryGap] = []
        var lastSolvedIndex: Int?
        var physicalKey: String?
        var continuity: Coordinate?
        var displayContinuity: Coordinate?
        var projectionCache = RouteProjectionCache()
        var boundaryGapIndices: Set<Int> = []

        for (index, section) in sections.enumerated() {
            let sharesBoundary = index > 0 && lastSolvedIndex == index - 1
                && RouteSolver.routeSectionBoundarySharesExplicitStop(sections[index - 1], section)
            let previousKey = sharesBoundary ? physicalKey : nil
            let anchor = sharesBoundary ? continuity : nil
            if inferred.ambiguous.contains(index) {
                lastSolvedIndex = nil
                physicalKey = nil
                continuity = nil
                displayContinuity = nil
                continue
            }
            let useSource = section.sectionCodes?.isEmpty == false || inferred.hints[index] != nil
            if useSource {
                try #require(section.sectionCodes?.isEmpty == false || inferred.hints[index] != nil)
                var hints = inferred.hints[index] ?? RouteHints(
                    requiredLineIDs: section.lineIDs ?? [], sectionCodes: section.sectionCodes ?? [],
                    fromStationCode: section.fromN02StationCode,
                    toStationCode: section.toN02StationCode)
                hints.fromStationCode = data.eligibility.stationCode(hints.fromStationCode)
                    ?? hints.fromStationCode
                hints.toStationCode = data.eligibility.stationCode(hints.toStationCode)
                    ?? hints.toStationCode
                let sourceResult = data.network.sourceGeometry(for: hints)
                let exactResult = data.network.canonicalizeRouteFeature(
                    RouteFeature(geometry: nil, hints: hints),
                    continueFrom: sharesBoundary ? displayContinuity : nil,
                    cache: &projectionCache)
                if let source = sourceResult, let exact = exactResult,
                   source.lines.count == exact.geometry.lines.count {
                    let graph = pipeline.proofGraph(source.lines.flatMap { $0 }, store: data.graphStore)
                    let keys = RouteSolver.verifiedSourcePath(
                        source.lines, graph: graph, context: context, section: section)
                    if sharesBoundary,
                       RouteSolver.provenBoundaryContinuation(
                           previous: previousKey, first: keys?.first,
                           previousSection: sections[index - 1], nextSection: section,
                           graph: graph, stations: data.stations, rideDate: context.rideDate) == nil {
                        if boundaryGapIndices.insert(index).inserted {
                            gaps.append(.init(station: section.from ?? "", previous: previousKey, first: keys?.first))
                        }
                    }
                    physicalKey = keys?.last
                    continuity = source.lines.last?.last
                    displayContinuity = exact.geometry.lines.last?.last
                    lastSolvedIndex = index
                    continue
                }
                lastSolvedIndex = nil
                physicalKey = nil
                continuity = nil
                displayContinuity = nil
                if inferred.hints[index] == nil { continue }
            } else {
                try #require(section.sectionCodes?.isEmpty != false && inferred.hints[index] == nil)
            }

            var solved = RouteSolver.solveOfficialInterval(
                section, segmentIndex: index, train: context, country: "jp",
                allowedCodes: allowedCodes, intervalIndex: data.intervals,
                stations: data.stations, continuityAnchor: anchor)
                ?? RouteSolver.solveSectionOnDemand(
                    section, segmentIndex: index, train: context, country: "jp",
                    graphStore: data.graphStore, stations: data.stations,
                    continuityAnchor: anchor, physicalContinuationKey: previousKey,
                    traversalPolicy: .physicalRail)
            if solved == nil, sharesBoundary {
                solved = RouteSolver.solveSectionOnDemand(
                    section, segmentIndex: index, train: context, country: "jp",
                    graphStore: data.graphStore, stations: data.stations,
                    traversalPolicy: .physicalRail)
            }
            guard var resolved = solved, resolved.coordinates.count >= 2 else {
                if sharesBoundary, boundaryGapIndices.insert(index).inserted {
                    gaps.append(.init(station: section.from ?? "", previous: previousKey, first: nil))
                }
                physicalKey = nil
                continuity = nil
                displayContinuity = nil
                lastSolvedIndex = nil
                continue
            }
            let solvedGraph = pipeline.proofGraph(resolved.coordinates, store: data.graphStore)
            if resolved.rawPathKeys.first?.contains("@") != true {
                resolved.rawPathKeys = RouteSolver.verifiedPhysicalPathKeys(
                    resolved.coordinates, graph: solvedGraph, rideDate: context.rideDate,
                    requiredLines: Set(section.lineNames ?? []),
                    requiredOperators: Set(section.operatorNames ?? [])) ?? []
            }
            if sharesBoundary,
               RouteSolver.provenBoundaryContinuation(
                   previous: previousKey, first: resolved.rawPathKeys.first,
                   previousSection: sections[index - 1], nextSection: section,
                   graph: pipeline.proofGraph([resolved.coordinates[0]], store: data.graphStore),
                   stations: data.stations, rideDate: context.rideDate) == nil {
                if boundaryGapIndices.insert(index).inserted {
                    gaps.append(.init(station: section.from ?? "", previous: previousKey, first: resolved.rawPathKeys.first))
                }
            }
            physicalKey = resolved.rawPathKeys.last
            continuity = resolved.coordinates.last

            let hints = RouteHints(
                requiredLineNames: (section.lineNames ?? []).map(Optional.some),
                preferredLineNames: context.preferredLineNames.map(Optional.some),
                requiredOperatorNames: (section.operatorNames ?? []).map(Optional.some),
                preferredOperatorNames: context.preferredOperatorNames.map(Optional.some),
                requiredLineIDs: section.lineIDs ?? [], sectionCodes: section.sectionCodes ?? [],
                fromStationCode: section.fromN02StationCode,
                toStationCode: section.toN02StationCode)
            let canonical = RouteGraph.TemporalKind.shouldCanonicalizeDisplayNetwork(
                resolved.temporalKind)
                ? data.network.canonicalizeRouteFeature(
                    RouteFeature(geometry: .lineString(resolved.coordinates), hints: hints),
                    continueFrom: sharesBoundary ? displayContinuity : nil, cache: &projectionCache)
                : nil
            var matchedSource: RouteGeometry?
            if let codes = canonical?.matchedSectionCodes, !codes.isEmpty {
                var matchedHints = hints
                matchedHints.sectionCodes = codes
                matchedHints.requiredLineIDs = canonical?.displayLineIds ?? []
                matchedSource = data.network.sourceGeometry(for: matchedHints)
            }
            if let matchedSource {
                let matchedGraph = pipeline.proofGraph(matchedSource.lines.flatMap { $0 }, store: data.graphStore)
                let keys = RouteSolver.verifiedSourcePath(
                    matchedSource.lines, graph: matchedGraph, context: context, section: section)
                if sharesBoundary,
                   RouteSolver.provenBoundaryContinuation(
                       previous: previousKey, first: keys?.first,
                       previousSection: sections[index - 1], nextSection: section,
                       graph: matchedGraph, stations: data.stations,
                       rideDate: context.rideDate) == nil, boundaryGapIndices.insert(index).inserted {
                    gaps.append(.init(station: section.from ?? "", previous: previousKey, first: keys?.first))
                }
                physicalKey = keys?.last
                continuity = matchedSource.lines.last?.last
            }
            displayContinuity = canonical?.geometry.lines.last?.last ?? resolved.coordinates.last
            lastSolvedIndex = index
        }
        return gaps
    }

    private func printCensus(_ label: String, census: Census, total: Int) {
        let stations = census.boundaryByStation.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        let causes = census.failuresByCause.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        let remaining = census.remaining.sorted().joined(separator: ", ")
        print("Junction census \(label): zero-gap rides \(census.zeroGapRides)/\(total); "
            + "boundary gaps [\(stations)]; non-boundary failures \(census.nonBoundaryFailures) "
            + "[\(causes)]")
        print("Junction census \(label) remaining: [\(remaining)]")
    }
}
