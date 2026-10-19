import Foundation
import Testing
import RailCore

struct RideRouteResolutionTests {
    private let a = Coordinate(lon: 139, lat: 35)
    private let bend = Coordinate(lon: 139.01, lat: 35.0008)
    private let b = Coordinate(lon: 139.02, lat: 35)
    private let c = Coordinate(lon: 139.0205, lat: 35)
    private let d = Coordinate(lon: 139.04, lat: 35)
    private let lineID = "jp-Operator-Rail"
    private let intervalCode = "jp-Operator-Rail@A:B"

    @Test("A solved ride retains the surveyed bend in source and drawing")
    func surveyedGeometry() throws {
        let coordinates = [a, bend, b]
        let section = leg("A", "B")
        var resolution = RideRouteResolution(inputs: inputs([rail(coordinates)]), country: "jp")
        let result = try resolution.resolve(.init(train: train([section])))

        #expect(result.disposition == .geometry)
        #expect(result.expectedSections == [section])
        #expect(result.segments.count == 1)
        let segment = try #require(result.segments.first)
        #expect(segment.segmentIndex == 0)
        #expect(segment.partIndex == 0)
        #expect(segment.sourceCoordinates == coordinates)
        #expect(segment.drawnCoordinates == coordinates)
        #expect(result.physicalGaps.isEmpty)
    }

    @Test("Disconnected surveyed rails cannot become a station-to-station chord")
    func missingPhysicalPath() throws {
        let sections = [rail([a, b], line: "West"), rail([c, d], line: "East")]
        let stations = [station(a, code: "A", line: "West"),
                        station(b, code: "B", line: "West"),
                        station(c, code: "B", line: "East"),
                        station(d, code: "D", line: "East")]
        let section = RouteSection(from: "A", to: "D", fromN02StationCode: "A",
            toN02StationCode: "D", lineNames: ["West", "East"], operatorNames: ["Operator"])
        var resolution = RideRouteResolution(inputs: inputs(sections, stations: stations), country: "jp")
        let result = try resolution.resolve(.init(train: train([section])))

        #expect(result.disposition == .unavailable)
        #expect(result.expectedSections == [section])
        #expect(result.segments.isEmpty)
    }

    @Test("Independent legs stay visible while their unproved physical boundary is marked")
    func independentSectionsKeepBoundaryGap() throws {
        let sections = [rail([a, bend, b], line: "West"), rail([c, d], line: "East")]
        let stations = [station(a, code: "A", line: "West"),
                        station(b, code: "B", line: "West"),
                        station(c, code: "B", line: "East"),
                        station(d, code: "D", line: "East")]
        let recorded = [leg("A", "B", line: "West"), leg("B", "D", line: "East")]
        var resolution = RideRouteResolution(inputs: inputs(sections, stations: stations), country: "jp")
        let result = try resolution.resolve(.init(train: train(recorded)))

        #expect(result.disposition == .geometry)
        #expect(result.expectedSections == recorded)
        #expect(result.segments.map(\.segmentIndex) == [0, 1])
        #expect(result.segments.map(\.sourceCoordinates) == [[a, bend, b], [c, d]])
        #expect(result.segments.map(\.drawnCoordinates) == [[a, bend, b], [c, d]])
        #expect(result.physicalGaps.count == 1)
        let gap = try #require(result.physicalGaps.first)
        #expect(gap.segmentIndex == 1)
        #expect(gap.isBoundary)
    }

    @Test("Future and expired rails fail closed at their half-open service bounds")
    func datedRailBounds() throws {
        let source = rail([a, bend, b], validFrom: "2020-01-01", validTo: "2030-01-01")
        var resolution = RideRouteResolution(inputs: inputs([source]), country: "jp")
        // Reuse the same worker and memo: a valid solve must not authorize another era.
        for (date, supported) in [("2020-01-01", true), ("2019-12-31", false),
                                  ("2029-12-31", true), ("2030-01-01", false)] {
            let result = try resolution.resolve(.init(train: train([leg("A", "B")], date: date)))
            #expect(result.disposition == (supported ? .geometry : .unavailable), "\(date)")
            #expect(result.segments.isEmpty == !supported, "\(date)")
            if supported {
                #expect(result.segments.first?.sourceCoordinates == [a, bend, b])
            }
        }
    }

    @Test("A missing authored interval is not replaced by an available legacy railway")
    func explicitSelectionCannotFallBack() throws {
        let coordinates = [a, bend, b]
        let source = inputs([rail(coordinates)])
        let network = try network(source: coordinates, drawn: coordinates)
        var resolution = RideRouteResolution(inputs: source, country: "jp",
            network: .init(network: network, inputs: source))
        let section = leg("A", "B", codes: ["missing-authored-interval"])
        let result = try resolution.resolve(.init(train: train([section])), allowLegacy: true)

        #expect(result.disposition == .unavailable)
        #expect(result.expectedSections == [section])
        #expect(result.segments.isEmpty)
    }

    @Test("A normalized corridor preference retains fallback permission after export and reload")
    func corridorPreferenceCanFallBackAfterReload() throws {
        let coordinates = [a, bend, b]
        let source = inputs([rail(coordinates)])
        let network = try network(source: coordinates, drawn: coordinates)
        var recorded = train([leg("A", "B", codes: ["missing-preference-interval"])])
        recorded.routeSections?[0].sectionCodesOrigin = .corridorPreference
        let saved = TrainValidation.normalizeExportTrain(recorded)
        let reopened = try JSONDecoder().decode(Train.self, from: JSONEncoder().encode(saved))
        var resolution = RideRouteResolution(inputs: source, country: "jp",
            network: .init(network: network, inputs: source))
        let result = try resolution.resolve(.init(train: reopened))
        #expect(result.disposition == .geometry)
        #expect(result.segments.first?.sourceCoordinates == coordinates)
        #expect(result.physicalGaps.isEmpty)
    }

    @Test("Recorded-only admission does not silently use an available surveyed fallback")
    func recordedOnlyReportsUnsupported() throws {
        var resolution = RideRouteResolution(inputs: inputs([rail([a, bend, b])]), country: "jp")
        let request = RideRouteResolution.Request(train: train([leg("A", "B")]))
        let recordedOnly = try resolution.resolve(request, allowLegacy: false)
        #expect(recordedOnly.disposition == .unsupported)
        #expect(recordedOnly.segments.isEmpty)
        let withFallback = try resolution.resolve(request)
        #expect(withFallback.disposition == .geometry)
        #expect(withFallback.segments.first?.sourceCoordinates == [a, bend, b])
    }

    @Test("Selected source coordinates remain distinct from drawing and retain timetable provenance")
    func selectedSourceAndDatabaseProvenance() throws {
        let rawBend = Coordinate(lon: 139.0100002, lat: 35.0008003)
        let sourceCoordinates = [a, rawBend, b]
        let drawnCoordinates = [a, Coordinate(lon: 139.01, lat: 35.0015), b]
        let source = inputs([rail(sourceCoordinates)])
        let network = try network(source: sourceCoordinates, drawn: drawnCoordinates)
        var resolution = RideRouteResolution(inputs: source, country: "jp",
            network: .init(network: network, inputs: source))
        let rawTrain = train([leg("A", "B")])
        let selected = leg("A", "B", codes: [intervalCode])
        let canonical = train([selected])
        let provenance = try JSONDecoder().decode(TimetablePhysicalRouteMatch.Provenance.self,
            from: Data(#"{"tripID":"surveyed-trip","serviceDate":"2026-07-01","timetableVersionID":"fixture-v1","calendarID":"fixture-calendar"}"#.utf8))
        let result = try resolution.resolve(.init(train: rawTrain, canonicalTrain: canonical,
            databaseSections: [0], databaseProvenance: provenance), allowLegacy: false)

        #expect(result.disposition == .geometry)
        #expect(result.expectedSections == [selected])
        #expect(result.segments.count == 1)
        let segment = try #require(result.segments.first)
        #expect(segment.sourceCoordinates == sourceCoordinates)
        #expect(segment.drawnCoordinates == drawnCoordinates)
        #expect(result.physicalGaps.isEmpty)
        let selection = try #require(segment.physicalRoute)
        #expect(selection.provenance == .database)
        #expect(selection.databaseProvenance == provenance)
        #expect(selection.fromStationCode == "A")
        #expect(selection.toStationCode == "B")
        #expect(selection.intervals.map(\.code) == [intervalCode])
        #expect(selection.lines.map(\.lineID) == [lineID])
    }

    @Test("Historical geometry and temporal provenance survive today's display network")
    func historicalGeometryIsNotRedrawn() throws {
        let historicalCoordinates = [a, bend, b]
        let currentCoordinates = [a, Coordinate(lon: 139.01, lat: 35.0015), b]
        let historical = rail(historicalCoordinates, validFrom: "2010-01-01", validTo: "2020-01-01",
            historyID: "fixture-relocation", temporalKind: .relocatedOld)
        let source = inputs([historical])
        let currentNetwork = try network(source: currentCoordinates, drawn: currentCoordinates)
        var resolution = RideRouteResolution(inputs: source, country: "jp",
            network: .init(network: currentNetwork, inputs: source))
        let result = try resolution.resolve(.init(train: train([leg("A", "B")], date: "2019-12-31")))

        #expect(result.disposition == .geometry)
        #expect(result.segments.count == 1)
        let segment = try #require(result.segments.first)
        #expect(segment.sourceCoordinates == historicalCoordinates)
        #expect(segment.drawnCoordinates == historicalCoordinates)
        #expect(segment.historyIDs == ["fixture-relocation"])
        #expect(segment.validFrom == "2010-01-01")
        #expect(segment.validTo == "2020-01-01")
        #expect(segment.temporalKind == .relocatedOld)
        #expect(segment.physicalRoute == nil)
        #expect(result.physicalGaps.isEmpty)
    }

    @Test("Unconfirmed recorded calls do not draw even when a canonical route is available")
    func awaitingConfirmationDoesNotDraw() throws {
        var resolution = RideRouteResolution(inputs: inputs([rail([a, bend, b])]), country: "jp")
        let confirmed = train([leg("A", "B")])
        var pending = confirmed
        pending.routeConfirmation = .pending
        let result = try resolution.resolve(.init(train: pending, canonicalTrain: confirmed))

        #expect(result.disposition == .awaitingConfirmation)
        #expect(result.segments.isEmpty)
        #expect(result.physicalGaps.isEmpty)
    }

    @Test("Name-only stops retain the solver's source station IDs as geometry-matched metadata")
    func nameOnlySourceStationIdentitySurvives() throws {
        let fromCode = "CN-OSM-N1588514426"
        let toCode = "CN-OSM-N1588514327"
        let coordinates = [a, bend, b]
        var from = station(a, code: fromCode)
        var to = station(b, code: toCode)
        from.properties["station_name"] = .string("刘沟")
        to.properties["station_name"] = .string("代湾")
        let source = inputs([rail(coordinates)], stations: [from, to])
        let network = try network(source: coordinates, drawn: coordinates,
                                  stationCodes: [fromCode, toCode])
        let section = RouteSection(from: "刘沟", to: "代湾")
        let recorded = Train(id: "name-only-source", date: "2026-10-18", number: "5619",
            company: "", origin: "刘沟", destination: "代湾", routeSections: [section],
            stops: [Stop(name: "刘沟", rideSegment: true), Stop(name: "代湾", rideSegment: false)],
            region: "cn")
        var resolution = RideRouteResolution(inputs: source, country: "cn",
            network: .init(network: network, inputs: source))
        let result = try resolution.resolve(.init(train: recorded))

        #expect(result.disposition == .geometry)
        #expect(result.expectedSections == [section])
        let segment = try #require(result.segments.first)
        #expect(segment.sourceCoordinates == coordinates)
        #expect(segment.drawnCoordinates == coordinates)
        let selection = try #require(segment.physicalRoute)
        #expect(selection.fromStationCode == fromCode)
        #expect(selection.toStationCode == toCode)
        #expect(selection.provenance == .matchedGeometry)
        #expect(selection.intervals.isEmpty)
    }

    @Test("Display-only geometry without known endpoints has no physical selection")
    func unknownDisplayEndpointsStayUnproven() throws {
        let coordinates = [a, bend, b]
        let network = try network(source: coordinates, drawn: coordinates)
        #expect(RideRouteResolution.displaySelection(lineIDs: [lineID], sectionCodes: [],
            hints: RouteHints(), network: network, sourceCoordinates: coordinates) == nil)
    }

    @Test("CN source-node paths cannot be redrawn or identified as a nearby untraversed metro")
    func sourceNodePathRejectsNearbyCanonicalIdentity() throws {
        var resolution = try sourceCanonicalFixture()
        let result = try resolution.resolve(.init(train: unconstrainedTrain(country: "cn")))
        let segment = try #require(result.segments.first)
        #expect(result.disposition == .geometry)
        #expect(result.physicalGaps.isEmpty)
        #expect(result.sourcePhysicalPathKeys[0]?.contains { $0.hasSuffix("@source-node:osm-node-2") } == true)
        #expect(segment.sourceCoordinates == [a, bend, b])
        #expect(segment.drawnCoordinates == [a, bend, b])
        #expect(segment.physicalRoute == nil)
    }

    @Test("A CN canonical line actually traversed by the source-node path keeps its drawing and identity")
    func sourceNodePathKeepsMatchingCanonicalIdentity() throws {
        var resolution = try sourceCanonicalFixture(canonicalIsSource: true)
        let result = try resolution.resolve(.init(train: unconstrainedTrain(country: "cn")))
        let segment = try #require(result.segments.first)
        #expect(segment.sourceCoordinates == [a, bend, b])
        #expect(segment.drawnCoordinates == [a, Coordinate(lon: 139.01, lat: 35.0015), b])
        #expect(segment.physicalRoute?.lines.map(\.lineID) == ["cn-rail"])
        #expect(segment.physicalRoute?.lines.map(\.operatorName) == ["Rail Operator"])
        #expect(result.physicalGaps.isEmpty)
    }

    @Test("CN paths without original node IDs retain the existing canonical display contract")
    func unqualifiedPathKeepsLegacyCanonicalDisplay() throws {
        var resolution = try sourceCanonicalFixture(sourceNodeIDs: false)
        let result = try resolution.resolve(.init(train: unconstrainedTrain(country: "cn")))
        let segment = try #require(result.segments.first)
        #expect(segment.drawnCoordinates == [a, Coordinate(lon: 139.01, lat: 35.0015), b])
        #expect(segment.physicalRoute?.lines.map(\.lineID) == ["cn-metro"])
    }

    @Test("Other countries retain their existing canonical display contract with source-node paths")
    func otherCountryKeepsLegacyCanonicalDisplay() throws {
        var resolution = try sourceCanonicalFixture(country: "jp")
        let result = try resolution.resolve(.init(train: unconstrainedTrain(country: "jp")))
        let segment = try #require(result.segments.first)
        #expect(segment.drawnCoordinates == [a, Coordinate(lon: 139.01, lat: 35.0015), b])
        #expect(segment.physicalRoute?.lines.map(\.lineID) == ["cn-metro"])
    }

    private func unconstrainedTrain(country: String) -> Train {
        var recorded = train([RouteSection(from: "A", to: "B", fromN02StationCode: "A", toN02StationCode: "B")])
        recorded.company = ""
        recorded.region = country
        return recorded
    }

    private func sourceCanonicalFixture(country: String = "cn", sourceNodeIDs: Bool = true,
                                        canonicalIsSource: Bool = false) throws -> RideRouteResolution {
        let sourceCoordinates = [a, bend, b]
        let drawn = [a, Coordinate(lon: 139.01, lat: 35.0015), b]
        let rail = RouteGraph.SectionFeature(properties: .init(lineName: "National Rail", operator: "Rail Operator",
            institutionTypeCode: "1", railwayClassCode: "12", trackID: "cn-rail"), lines: [sourceCoordinates],
            sourceNodeIDs: sourceNodeIDs ? [["osm-node-1", "osm-node-2", "osm-node-3"]] : nil)
        let metro = RouteGraph.SectionFeature(properties: .init(lineName: "Metro", operator: "Metro Operator",
            institutionTypeCode: "3", railwayClassCode: "11", trackID: "cn-metro"), lines: [drawn],
            sourceNodeIDs: sourceNodeIDs ? [["osm-node-4", "osm-node-5", "osm-node-6"]] : nil)
        let stations = [(a, "A", 1), (b, "B", 3)].map { coordinate, code, anchor in
            var feature = station(coordinate, code: code, line: "National Rail")
            feature.properties["operator"] = .string("Rail Operator")
            feature.properties["line_id"] = .string("cn-rail")
            feature.properties["railway_class_code"] = .string("12")
            if sourceNodeIDs { feature.properties["source_anchor_node_id"] = .number(Double(anchor)) }
            return feature
        }
        let source = inputs([rail, metro], stations: stations)
        let id = canonicalIsSource ? "cn-rail" : "cn-metro"
        let name = canonicalIsSource ? "National Rail" : "Metro"
        let op = canonicalIsSource ? "Rail Operator" : "Metro Operator"
        let row: [String: Any] = ["id": id, "name": name, "operator": op, "rank": 3,
            "stations": [["A", "A", a.lon, a.lat] as [Any], ["B", "B", b.lon, b.lat] as [Any]],
            "segments": [[1, 0, sourceCoordinates.map { [$0.lon, $0.lat] }] as [Any]]]
        let compact = try JSONDecoder().decode(CompactPackage.Line.self,
            from: JSONSerialization.data(withJSONObject: row))
        let network = RouteNetwork(lines: [.init(lineId: id, name: name, operator: op, isLoop: false,
            alignmentDirection: nil, parts: [drawn], intervals: RailIntervalCodes.intervals(for: compact))])
        return RideRouteResolution(inputs: source, country: country, network: .init(network: network, inputs: source))
    }

    private func rail(_ coordinates: [Coordinate], line: String = "Rail",
                      validFrom: String? = nil, validTo: String? = nil,
                      historyID: String? = nil, temporalKind: RouteGraph.TemporalKind = .current
    ) -> RouteGraph.SectionFeature {
        .init(properties: .init(lineName: line, operator: "Operator", institutionTypeCode: "1",
            validFrom: validFrom, validTo: validTo, historyId: historyID, temporalKind: temporalKind),
            lines: [coordinates])
    }

    private func station(_ coordinate: Coordinate, code: String, line: String = "Rail") -> Stations.Feature {
        .init(properties: ["n02_station_code": .string(code), "station_name": .string(code),
            "line_name": .string(line), "operator": .string("Operator"),
            "institution_type_code": .string("1")], geometry: .init(type: "Point",
                coordinates: .array([.number(coordinate.lon), .number(coordinate.lat)])))
    }

    private func inputs(_ sections: [RouteGraph.SectionFeature], stations: [Stations.Feature]? = nil
    ) -> RideRouteResolution.SourceInputs {
        .init(sections: sections,
            stationCollection: .init(features: stations ?? [station(a, code: "A"), station(b, code: "B")]))
    }

    private func leg(_ from: String, _ to: String, line: String = "Rail", codes: [String]? = nil) -> RouteSection {
        .init(from: from, to: to, fromN02StationCode: from, toN02StationCode: to,
            lineNames: [line], operatorNames: ["Operator"], lineIDs: codes == nil ? nil : [lineID],
            sectionCodes: codes)
    }

    private func train(_ sections: [RouteSection], date: String = "2026-07-01") -> Train {
        let names = [sections.first?.from ?? ""] + sections.map { $0.to ?? "" }
        return .init(id: "ride-resolution-fixture", date: date, number: "Local", company: "Operator",
            origin: names.first ?? "", destination: names.last ?? "", routeSections: sections,
            stops: names.enumerated().map { index, name in
                Stop(name: name, n02StationCode: name, rideSegment: index < names.count - 1)
            }, region: "jp")
    }

    private func network(source: [Coordinate], drawn: [Coordinate], stationCodes: [String] = ["A", "B"]) throws -> RouteNetwork {
        let row: [String: Any] = [
            "id": lineID, "name": "Rail", "operator": "Operator", "rank": 3,
            "stations": [[stationCodes[0], stationCodes[0], a.lon, a.lat] as [Any],
                         [stationCodes[1], stationCodes[1], b.lon, b.lat] as [Any]],
            "segments": [[1, 0, source.map { [$0.lon, $0.lat] }] as [Any]],
        ]
        let line = try JSONDecoder().decode(CompactPackage.Line.self,
            from: JSONSerialization.data(withJSONObject: row))
        let intervals = RailIntervalCodes.intervals(for: line)
        return .init(lines: [.init(lineId: lineID, name: "Rail", operator: "Operator", isLoop: false,
            alignmentDirection: nil, parts: [drawn], intervals: intervals)])
    }
}
