#if DEBUG
import RailCore
import RailPresentation
import SwiftUI

/// What the workspace lends the control channel: its own private actions
/// (`pick`, `presentJourneyEditor`, …), so a command runs exactly the code a
/// tap would. Registered from `RailWorkspaceView` (see its DEBUG extension).
@MainActor
struct AppControlWorkspaceHandle {
    struct EditorState {
        var open: Bool
        var isNew: Bool
        var trainID: String?
        var recordID: String?
        var saving: Bool
        var saveFailure: String?
    }

    var selectTrip: (Train) -> Void
    var focusTrip: (String) -> Void
    var presentEditor: (JourneyEditorLaunch) -> Void
    var newTripScaffold: (Region) -> Train
    var closeEditor: () -> Void
    var editorState: () -> EditorState
    var sheetID: () -> String?
    var renderStats: () -> RailMapView.RenderStats?
    var drawableRideCount: () -> Int
    var stage: () -> String
    var tab: () -> String
}

/// What one open journey editor lends the control channel. Registered from
/// `JourneyEditorView` (see its DEBUG extension); every closure calls the
/// editor's own station assignment, planner, section choice and save.
@MainActor
struct AppControlEditorHandle {
    var token = UUID()
    var trainID: String
    var isNew: Bool
    /// Catalog and network package are loaded (or failed to load).
    var isReady: () -> Bool
    var loadFailed: () -> Bool
    var region: () -> String
    var station: (String) -> [CatalogStation]
    var setRoute: (_ from: CatalogStation?, _ to: CatalogStation?, _ vias: [CatalogStation]?) -> Void
    var setDay: (String) -> Void
    /// `false` when the section or the corridor is not on offer.
    var choose: (_ corridorID: String, _ section: Int) -> Bool
    var commit: (_ confirmedRemoval: Bool) -> Void
    var snapshot: () -> AppControlEditorSnapshot
    /// The `proposal` input for the selected corridor (see the editor's DEBUG extension).
    var autofillProbe: () -> AppControlJSON
}

/// The editor's planning state, as the control channel reports it.
struct AppControlEditorSnapshot {
    struct Station {
        var code: String
        var name: String
        var stationID: String? = nil
        var lineID: String? = nil
    }
    struct Candidate {
        var id: String
        var lineIDs: [String] = []
        var lines: [String]
        var operators: [String]
        var distanceKm: Double
        var passStationCount: Int
        var junctions: [String]
        var proven: Bool
        var historical: Bool
    }
    struct Section {
        var key: String = ""
        var index: Int
        var from: String
        var to: String
        var outcome: String
        var outcomeDetail: [String]
        var candidates: [Candidate]
        var chosen: String?
        var historicalNotice: String?
        var historicalProbe: String?
        var proofFailure: String?
        var removedByDate: Bool
    }

    var trainID: String
    var isNew: Bool
    var region: String
    var ready: Bool
    var searching: Bool
    var planned: Bool
    var routeEdited: Bool
    var canSave: Bool
    var date: String
    var origin: Station?
    var destination: Station?
    var vias: [Station]
    var sections: [Section]
    var pendingSections: [Int]
    var selectedCorridorID: String?
    var joinedOutcome: String?
    var passStations: [Station]
    var conflicts: [String]
    var removalPending: [String]?
    var notices: [String]
    var saveIssues: [String]
    var sectionChoices: [String: String] = [:]
    var allowUnverifiedConnections = false
    var physicallyResolvedCorridorIDs: [String] = []
    var trainType = ""
    var company = ""

    var json: AppControlJSON {
        func station(_ value: Station?) -> AppControlJSON {
            guard let value else { return .null }
            var json: [String: AppControlJSON] = ["code": .string(value.code), "name": .string(value.name)]
            if let id = value.stationID { json["stationID"] = .string(id) }
            if let line = value.lineID { json["lineID"] = .string(line) }
            return .object(json)
        }
        func strings(_ values: [String]) -> AppControlJSON { .array(values.map { .string($0) }) }
        func optional(_ value: String?) -> AppControlJSON { value.map { .string($0) } ?? .null }
        return [
            "trainID": .string(trainID), "isNew": .bool(isNew), "region": .string(region),
            "ready": .bool(ready), "searching": .bool(searching), "planned": .bool(planned),
            "routeEdited": .bool(routeEdited), "canSave": .bool(canSave), "date": .string(date),
            "origin": station(origin), "destination": station(destination),
            "vias": .array(vias.map { station($0) }),
            "sections": .array(sections.map { section in
                [
                    "index": .number(Double(section.index)), "from": .string(section.from), "to": .string(section.to),
                    "key": .string(section.key.replacingOccurrences(of: "\u{1f}", with: "|")),
                    "outcome": .string(section.outcome), "outcomeDetail": strings(section.outcomeDetail),
                    "chosen": optional(section.chosen),
                    "historicalNotice": optional(section.historicalNotice),
                    "historicalProbe": optional(section.historicalProbe),
                    "proofFailure": optional(section.proofFailure),
                    "removedByDate": .bool(section.removedByDate),
                    "candidates": .array(section.candidates.map { candidate in
                        [
                            "id": .string(candidate.id), "lines": strings(candidate.lines),
                            "lineIDs": strings(candidate.lineIDs),
                            "operators": strings(candidate.operators),
                            "distanceKm": .number((candidate.distanceKm * 10).rounded() / 10),
                            "passStationCount": .number(Double(candidate.passStationCount)),
                            "junctions": strings(candidate.junctions),
                            "proven": .bool(candidate.proven), "historical": .bool(candidate.historical),
                        ]
                    }),
                ]
            }),
            "pendingSections": .array(pendingSections.map { .number(Double($0)) }),
            "selectedCorridorID": optional(selectedCorridorID),
            "joinedOutcome": optional(joinedOutcome),
            "passStations": .array(passStations.map { station($0) }),
            "conflicts": strings(conflicts),
            "removalPending": removalPending.map(strings) ?? .null,
            "notices": strings(notices),
            "saveIssues": strings(saveIssues),
            "sectionChoices": .object(sectionChoices.mapValues { .string($0) }),
            "allowUnverifiedConnections": .bool(allowUnverifiedConnections),
            "physicallyResolvedCorridorIDs": strings(physicallyResolvedCorridorIDs),
            "trainType": .string(trainType), "company": .string(company),
        ]
    }

    static func outcomeName(_ outcome: TripRoutePlanner.Outcome) -> (String, [String]) {
        switch outcome {
        case .corridors(let corridors): ("corridors", ["\(corridors.count)"])
        case .disconnected(let junctions):
            ("disconnected", junctions.map { "\($0.stationName) (\($0.fromLineName) → \($0.toLineName))" })
        case .noRoute: ("noRoute", [])
        case .noCompanyRoute(let name): ("noCompanyRoute", [name])
        case .sameStation: ("sameStation", [])
        case .truncated: ("truncated", [])
        }
    }

    static func candidate(
        _ corridor: TripRoutePlanner.Corridor, proven: Set<String>, historical: Set<String>
    ) -> Candidate {
        Candidate(
            id: corridor.id, lineIDs: corridor.choice.lineIDs, lines: corridor.lineNames, operators: corridor.operatorNames,
            distanceKm: corridor.distanceKm, passStationCount: corridor.passStationCount,
            junctions: corridor.junctions.map { "\($0.stationName): \($0.fromLineName) → \($0.toLineName)" },
            proven: proven.contains(corridor.id), historical: historical.contains(corridor.id))
    }
}
#endif
