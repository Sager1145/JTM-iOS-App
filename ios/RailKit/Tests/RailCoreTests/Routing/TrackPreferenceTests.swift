import Foundation
import Testing
@testable import RailCore

/// A passenger can force the other track of a confirmed one-direction track
/// pair (日豊線 / 日豊線-p1 at 立石). It is a Swift-only section field: absent
/// data reads exactly as before, and a branch is never a track pair.
@Suite(.serialized)
struct TrackPreferenceTests {
    static let parentID = PairedSeamCertificationTests.parentID
    static let pairedID = PairedSeamCertificationTests.pairedID

    // MARK: Coding

    @Test("Old JSON decodes with no preference and a nil preference is not encoded")
    func codingDefaults() throws {
        let old = Data(#"{"from":"A","to":"B","from_n02_station_code":null,"to_n02_station_code":null}"#.utf8)
        let section = try JSONDecoder().decode(RouteSection.self, from: old)
        #expect(section.trackPreference == nil)
        let encoded = String(decoding: try JSONEncoder().encode(section), as: UTF8.self)
        #expect(!encoded.contains("track_preference"))
    }

    @Test("A set preference round-trips; an unknown or mistyped value becomes nil")
    func codingValues() throws {
        var section = RouteSection(from: "A", to: "B")
        section.trackPreference = .down
        let data = try JSONEncoder().encode(section)
        #expect(String(decoding: data, as: UTF8.self).contains(#""track_preference":"down""#))
        #expect(try JSONDecoder().decode(RouteSection.self, from: data).trackPreference == .down)
        for bad in [#""sideways""#, "7", "null", "[]"] {
            let json = Data(#"{"from":"A","to":"B","track_preference":\#(bad)}"#.utf8)
            #expect(try JSONDecoder().decode(RouteSection.self, from: json).trackPreference == nil, "\(bad)")
        }
    }

    @Test("Import accepts up and down and rejects anything else; export keeps the field")
    func importAndExport() throws {
        for value in [TrackPreference.up, .down] {
            let json = try TrainValidation.JSON.parse(#"{"from":"A","to":"B","track_preference":"\#(value.rawValue)"}"#)
            let imported = try TrainValidation.normalizeImportedRouteSection(json)
            #expect(imported.trackPreference == value)
            var section = RouteSection(from: "A", to: "B", fromN02StationCode: "A", toN02StationCode: "B",
                                       lineNames: ["l"], operatorNames: ["o"])
            section.trackPreference = value
            let train = Train(id: "t", date: "2026-07-27", number: "T", origin: "A", destination: "B",
                routeSections: [section],
                stops: [Stop(name: "A", n02StationCode: "A", departure: "10:00", stopType: "origin"),
                        Stop(name: "B", n02StationCode: "B", arrival: "10:30", stopType: "destination")])
            #expect(TrainValidation.normalizeExportTrain(train).routeSections?.first?.trackPreference == value)
            #expect(try TrainValidation.normalizeImportedRouteSection(StoreOperations.json(imported)).trackPreference == value)
        }
        let bad = try TrainValidation.JSON.parse(#"{"from":"A","to":"B","track_preference":"left"}"#)
        #expect(throws: (any Error).self) { try TrainValidation.normalizeImportedRouteSection(bad) }
        let plain = try TrainValidation.JSON.parse(#"{"from":"A","to":"B"}"#)
        #expect(try TrainValidation.normalizeImportedRouteSection(plain).trackPreference == nil)
    }

    @Test("The template key moves only when a preference is set")
    func templateKey() {
        let plain = RailCore.RouteSection(from: "A", to: "B", fromN02StationCode: "1", toN02StationCode: "2")
        var forced = plain
        forced.trackPreference = .up
        let base = RouteGraph.templateKey(sections: [.init(plain)])
        #expect(!base.contains("track"))
        #expect(RouteGraph.templateKey(sections: [.init(forced)]) == base + "|track:up")
    }

    // MARK: Solver

    private func load() throws -> (PhysicalEndpointTrimTests, PhysicalEndpointTrimTests.RealData) {
        let pipeline = PhysicalEndpointTrimTests()
        return (pipeline, try pipeline.loadRealData(root: try PortFixtures.repositoryRoot()))
    }

    @Test("杵築→中津 forced down selects the parent row and certifies")
    func kitsukiToNakatsuDown() throws {
        let (pipeline, data) = try load()
        let ride = try #require(PairedSeamCertificationTests.ride(
            "杵築", "中津", trackPreference: .down, data: data, pipeline: pipeline))
        #expect(ride.keys != nil, "杵築→中津 forced down does not certify")
        #expect(ride.selected.contains(Self.parentID))
        #expect(!ride.selected.contains(Self.pairedID), "forced down must leave 日豊線-p1")
    }

    @Test("杵築→中津 forced up keeps the paired row")
    func kitsukiToNakatsuUp() throws {
        let (pipeline, data) = try load()
        let ride = try #require(PairedSeamCertificationTests.ride(
            "杵築", "中津", trackPreference: .up, data: data, pipeline: pipeline))
        #expect(ride.keys != nil)
        #expect(ride.selected.contains(Self.pairedID))
    }

    @Test("中津→杵築 forced up selects 日豊線-p1 and certifies through the seam splice")
    func nakatsuToKitsukiUp() throws {
        let (pipeline, data) = try load()
        let automatic = try #require(PairedSeamCertificationTests.ride("中津", "杵築", data: data, pipeline: pipeline))
        #expect(!automatic.selected.contains(Self.pairedID))
        let ride = try #require(PairedSeamCertificationTests.ride(
            "中津", "杵築", trackPreference: .up, data: data, pipeline: pipeline))
        #expect(ride.selected.contains(Self.pairedID), "forced up must use 日豊線-p1")
        let keys = try #require(ride.keys, "中津→杵築 forced up does not certify")
        #expect(!PairedSeamCertificationTests.hasReversal(keys))
    }

    @Test("A preference on a section outside the pair's span changes nothing")
    func nonPairSection() throws {
        let (pipeline, data) = try load()
        for (from, to) in [("中津", "宇佐"), ("宇佐", "中津")] {
            let automatic = PairedSeamCertificationTests.ride(from, to, data: data, pipeline: pipeline)
            for preference in [TrackPreference.up, .down] {
                let forced = PairedSeamCertificationTests.ride(
                    from, to, trackPreference: preference, data: data, pipeline: pipeline)
                #expect(forced?.keys == automatic?.keys, "\(from)→\(to) changed by \(preference.rawValue)")
                #expect(forced?.selected == automatic?.selected)
            }
        }
    }

    @Test("A branch row ignores the preference: 函館線-2 allows what it allowed")
    func branchUnchanged() throws {
        let (_, data) = try load()
        let branch = "jp-北海道旅客鉄道-函館線-2"
        let line = try #require(data.network.lines.first { $0.lineId == branch })
        #expect(!line.intervals.isEmpty)
        for interval in line.intervals {
            for preference in [TrackPreference.up, .down] {
                #expect(data.network.allowedDirections(for: interval.code, trackPreference: preference)
                    == data.network.allowedDirections(for: interval.code),
                    "\(branch) \(interval.code) changed by \(preference.rawValue)")
            }
        }
        let codes = try #require(line.compactLine?.stations.map(\.id))
        let automatic = data.resolver.resolve(stationCodes: [codes[0], codes[codes.count - 1]], requiredLineIDs: [branch])
        for preference in [TrackPreference.up, .down] {
            #expect(data.resolver.resolve(stationCodes: [codes[0], codes[codes.count - 1]],
                requiredLineIDs: [branch], trackPreference: preference) == automatic)
        }
    }

    @Test("The resolver offers only the forced row inside the span, in both travel directions")
    func resolverFiltering() throws {
        let (_, data) = try load()
        let pair = try #require(data.network.pairedTracks.pair(forRow: Self.pairedID))
        for (preference, row) in [(TrackPreference.up, Self.pairedID), (.down, Self.parentID)] {
            for codes in [[pair.from.code, pair.to.code], [pair.to.code, pair.from.code]] {
                let result = data.resolver.resolve(
                    stationCodes: codes, requiredLineIDs: [Self.parentID, Self.pairedID], trackPreference: preference)
                guard case .resolved(let selection) = result else {
                    Issue.record("\(preference.rawValue) \(codes) did not resolve: \(result)"); continue
                }
                #expect(selection.lineIDs == [row], "\(preference.rawValue) \(codes) used \(selection.lineIDs)")
            }
        }
    }

    @Test("A pair whose directions are not confirmed offers no override")
    func unconfirmedDirectionIsIgnored() throws {
        let (_, data) = try load()
        let real = try #require(data.network.pairedTracks.pair(forRow: Self.pairedID))
        let unclear = PairedTracks.Pair(
            pairedLineID: real.pairedLineID, parentLineID: real.parentLineID, line: real.line,
            operator: real.operator, from: real.from, to: real.to, upTrack: real.upTrack,
            downTrack: real.downTrack, sharedTrack: real.sharedTrack, pairStatus: real.pairStatus,
            directionStatus: .unclear, sources: real.sources, note: real.note)
        let catalog = PairedTracks.Catalog(pairs: [unclear])
        for preference in [TrackPreference.up, .down] {
            #expect(catalog.forcedTrack(preference, pair: unclear) == nil)
        }
    }

    // MARK: Applicability

    private static func rows(_ package: CompactPackage) -> [CompactPackage.Line] { package.lines }

    @Test("The override is offered only where it can work")
    func overridablePairs() throws {
        let package = try DisplayParts.LoadedPackage.load(
            contentsOf: try PortFixtures.repositoryRoot().appending(path: "app/public/rail/jp-2025.json")).package
        let catalog = PairedTracks.Catalog.bundled.validated(against: package)
        func code(_ name: String, row: String) throws -> String {
            try #require(package.lines.first { $0.id == row }?.stations.first { $0.name == name }?.id)
        }
        let nikkou = Self.parentID
        func section(_ from: String, _ to: String, row: String, ids: [String]? = nil, codes: [String]? = nil) throws -> RouteSection {
            RouteSection(from: from, to: to, fromN02StationCode: try code(from, row: row),
                         toN02StationCode: try code(to, row: row), lineIDs: ids, sectionCodes: codes)
        }
        #expect(!catalog.overridablePairs(for: try section("杵築", "中津", row: nikkou), rows: package.lines).isEmpty)
        #expect(!catalog.overridablePairs(for: try section("杵築", "中津", row: nikkou, ids: [Self.parentID, Self.pairedID]),
                                          rows: package.lines).isEmpty)
        #expect(catalog.overridablePairs(for: try section("杵築", "中津", row: nikkou, ids: [Self.parentID]),
                                         rows: package.lines).isEmpty, "line ids exclude the paired row")
        #expect(catalog.overridablePairs(for: try section("杵築", "中津", row: nikkou, codes: ["x"]),
                                         rows: package.lines).isEmpty, "authored interval codes")
        #expect(catalog.overridablePairs(for: try section("中津", "宇佐", row: nikkou), rows: package.lines).isEmpty,
                "outside the span")
        let tokaido = "jp-東海旅客鉄道-東海道線-2"
        #expect(!catalog.overridablePairs(for: try section("大垣", "関ヶ原", row: tokaido), rows: package.lines).isEmpty)
        #expect(catalog.overridablePairs(for: try section("大垣", "垂井", row: tokaido), rows: package.lines).isEmpty,
                "垂井 is strictly inside the span the down bypass skips")
        #expect(catalog.overridablePairs(for: try section("垂井", "関ヶ原", row: tokaido), rows: package.lines).isEmpty)
    }

    // MARK: Through RideRouteResolution

    private struct Resolved {
        var inputs: RideRouteResolution.SourceInputs
        var prepared: RideRouteResolution.NetworkInputs
        var graphStore: RouteGraph.RouteGraphStore
    }

    private func resolved() throws -> (Resolved, PhysicalEndpointTrimTests.RealData) {
        let root = try PortFixtures.repositoryRoot()
        let data = try PhysicalEndpointTrimTests().loadRealData(root: root)
        let dataRoot = root.appending(path: "app/data")
        var sections = try RouteGraph.SectionFeatureCollection.load(
            contentsOf: dataRoot.appending(path: "rail-sections.json")).features
        var stations = try Stations.FeatureCollection.load(
            contentsOf: dataRoot.appending(path: "stations.json")).features
        let overlay = try RailHistoryOverlay.load(from: dataRoot.appending(path: "rail-history.json"))
        _ = RailHistory.apply(overlay, sections: &sections, stations: &stations)
        let registry = try PhysicalRailJunctionRegistry(data: Data(contentsOf:
            dataRoot.appending(path: "physical-rail-junctions.json")))
        let inputs = RideRouteResolution.SourceInputs(
            sections: sections, stationCollection: Stations.FeatureCollection(features: stations),
            physicalJunctions: registry.junctions(for: "jp"), identityPeriods: overlay.identityPeriods)
        return (Resolved(inputs: inputs, prepared: .init(network: data.network, inputs: inputs),
                         graphStore: data.graphStore), data)
    }

    private func solve(
        _ section: RouteSection, _ r: Resolved
    ) throws -> RideRouteResolution.Result {
        let train = Train(id: "tp", date: "2026-10-03", number: "T", origin: section.from ?? "", destination: section.to ?? "",
            routeSections: [section],
            stops: [Stop(name: section.from ?? "", n02StationCode: section.fromN02StationCode, departure: "10:00", stopType: "origin"),
                    Stop(name: section.to ?? "", n02StationCode: section.toN02StationCode, arrival: "10:30", stopType: "destination")])
        var resolution = RideRouteResolution(inputs: r.inputs, country: "jp", network: r.prepared,
            officialIntervals: r.inputs.officialIntervals, graphStore: r.graphStore)
        return try resolution.resolve(.init(train: train), allowLegacy: true)
    }

    private func section(
        _ from: String, _ to: String, data: PhysicalEndpointTrimTests.RealData, row: String = parentID,
        preference: TrackPreference? = nil
    ) throws -> RouteSection {
        let stations = try #require(data.network.lines.first { $0.lineId == row }?.compactLine?.stations)
        return RouteSection(from: from, to: to,
            fromN02StationCode: try #require(stations.first { $0.name == from }?.id),
            toN02StationCode: try #require(stations.first { $0.name == to }?.id),
            lineNames: ["日豊線"], operatorNames: ["九州旅客鉄道"], trackPreference: preference)
    }

    private func same(_ a: RideRouteResolution.Result, _ b: RideRouteResolution.Result) -> Bool {
        a.disposition == b.disposition && a.physicalGaps == b.physicalGaps
            && a.segments.map(\.drawnCoordinates) == b.segments.map(\.drawnCoordinates)
    }

    @Test("Through RideRouteResolution: a valid override takes the other track")
    func resolutionValidOverride() throws {
        let (r, data) = try resolved()
        let automatic = try solve(try section("中津", "杵築", data: data), r)
        let forced = try solve(try section("中津", "杵築", data: data, preference: .up), r)
        let usedAutomatic = Set(automatic.segments.flatMap { $0.physicalRoute?.lines.map(\.lineID) ?? [] })
        let usedForced = Set(forced.segments.flatMap { $0.physicalRoute?.lines.map(\.lineID) ?? [] })
        #expect(!forced.segments.isEmpty && forced.physicalGaps.isEmpty, "forced up must still draw: \(forced.disposition) \(forced.physicalGaps)")
        #expect(!usedAutomatic.contains(Self.pairedID))
        #expect(usedForced.contains(Self.pairedID), "forced up must ride 日豊線-p1, got \(usedForced)")
    }

    @Test("Through RideRouteResolution: authored interval codes ignore the preference")
    func resolutionAuthoredCodes() throws {
        let (r, data) = try resolved()
        let network = data.network
        let parent = try #require(network.lines.first { $0.lineId == Self.parentID })
        let stations = try #require(parent.compactLine?.stations)
        let from = try #require(stations.first { $0.name == "中津" }?.id)
        let to = try #require(stations.first { $0.name == "杵築" }?.id)
        let ids = stations.map(\.id)
        let low = try #require(ids.firstIndex(of: from)), high = try #require(ids.firstIndex(of: to))
        let slice = Array(parent.intervals[min(low, high)..<max(low, high)].map(\.code))
        let codes = low < high ? slice : slice.reversed()
        var plain = RouteSection(from: "中津", to: "杵築", fromN02StationCode: from, toN02StationCode: to,
            lineNames: ["日豊線"], operatorNames: ["九州旅客鉄道"], lineIDs: [Self.parentID], sectionCodes: codes)
        let automatic = try solve(plain, r)
        #expect(!automatic.segments.isEmpty)
        for preference in [TrackPreference.up, .down] {
            plain.trackPreference = preference
            #expect(same(try solve(plain, r), automatic), "\(preference.rawValue) changed an authored section")
        }
    }

    @Test("Through RideRouteResolution: 函館→新函館北斗 forced down is ignored")
    func resolutionHakodate() throws {
        let (r, data) = try resolved()
        let row = "jp-北海道旅客鉄道-函館線"
        let stations = try #require(data.network.lines.first { $0.lineId == row }?.compactLine?.stations)
        func base(_ preference: TrackPreference?) throws -> RouteSection {
            RouteSection(from: "函館", to: "新函館北斗",
                fromN02StationCode: try #require(stations.first { $0.name == "函館" }?.id),
                toN02StationCode: try #require(stations.first { $0.name == "新函館北斗" }?.id),
                lineNames: ["函館線"], operatorNames: ["北海道旅客鉄道"], trackPreference: preference)
        }
        let automatic = try solve(try base(nil), r)
        for preference in [TrackPreference.up, .down] {
            #expect(same(try solve(try base(preference), r), automatic), "\(preference.rawValue) changed 函館→新函館北斗")
        }
    }
}
