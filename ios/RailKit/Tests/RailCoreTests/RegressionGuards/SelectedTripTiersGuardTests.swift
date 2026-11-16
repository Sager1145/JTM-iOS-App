import Foundation
import RailTestSupport
import Testing

/// Source-structure guards for the selected trip's station tiers: the pure
/// rule (`RailPresentation.SelectedTripStationTiers`) is tested on its own;
/// these pin that the map's markers still come from it, and that no marker
/// label prints the registry-identity word ("unresolved").
@Suite("RegressionGuardSelectedTripTiers")
struct RegressionGuardSelectedTripTiers {
    private static let coordinator = SourceFiles.textRecording("RailMap/Map/RailMapCoordinator.swift")
    private static let labels = SourceFiles.textRecording("RailMap/Map/MapStationLabelCoordinator.swift")
    private static let markers = SourceFiles.textRecording("RailMap/Map/MapRideMarkers.swift")

    private static func body(_ source: String, from start: String, to end: String) throws -> Substring {
        let from = try #require(source.range(of: start))
        let to = try #require(source.range(of: end, range: from.upperBound..<source.endIndex))
        return source[from.lowerBound..<to.lowerBound]
    }

    private static func occurrences(of needle: String, in source: some StringProtocol) -> Int {
        source.components(separatedBy: needle).count - 1
    }

    @Test func theSelectedTripsMarksAndNamesComeFromTheRule() throws {
        let loop = try Self.body(
            Self.coordinator, from: "for recordIndex in recordCandidates {",
            to: "finishMarkerPhase(\"rideDotLoop\")")
        // The layer switches gate the record before the rule is asked.
        let gate = try #require(loop.range(of: "guard layers.draws(role: feature.role)"))
        let mark = try #require(loop.range(of: "let tierMark = selected ? selectedTiers?.mark("))
        #expect(gate.lowerBound < mark.lowerBound)
        #expect(loop.contains("let drawsDot = tierMark?.drawsDot ?? MapRideMarkers.drawsDot("))
        #expect(loop.contains("if selected && !drawsDot { continue }"))
        #expect(loop.contains("tierMark?.offersName ?? true"))
        #expect(loop.contains("SelectedTripStationTiers.labelPriority("))
        // An on-route station is drawn neutral and is never tagged a pass.
        #expect(loop.contains("let onRoute = tierMark?.stationClass == .onRoute"))
        #expect(loop.contains("stroke: onRoute ? .systemGray :"))
        #expect(loop.contains("(onRoute ? \"\" : feature.role == \"pass\" ? naming.passTag"))
    }

    @Test func theRankingIsBuiltOncePerTripNotPerPass() throws {
        // The marker pass only reads the cached ranking.
        #expect(Self.occurrences(of: "stationLabels.selectedTripTiers(", in: Self.coordinator) == 1)
        #expect(!Self.coordinator.contains("SelectedTripStationTiers.rank("))
        let cache = try Self.body(
            Self.labels, from: "private func selected(", to: "static func markerKey(")
        #expect(cache.contains("selectedCache.key == key"))
        // The key also covers what a class reads beyond the geometry digest.
        #expect(cache.contains("MapRideMarkers.tierClassDigest(of: ride)"))
        #expect(cache.contains("SelectedTripStationTiers.rank(MapRideMarkers.tierStations(of: ride, drawn: drawn))"))
        #expect(cache.contains("RailwayLinePreview.isPreviewRide(ride.id) ? .empty"))
        #expect(Self.occurrences(of: "SelectedTripStationTiers.rank(", in: Self.labels) == 1)
        // With a ranking, the pass does not walk every trip's records to
        // count the selected trip's calls.
        #expect(Self.coordinator.contains(
            "let selectedCallCount = selectedTrainID == nil || selectedTiers != nil ? 0 :"))
    }

    @Test func stationClassesComeFromTheTimelinesStopFields() throws {
        let stations = try Self.body(
            Self.markers, from: "static func tierStations(", to: "static func drawn(assembling")
        #expect(stations.contains("SelectedTripStationTiers.stationClass("))
        #expect(stations.contains("stopType: stop?.stopType"))
        #expect(stations.contains("isGenerated: stop?.routeEditing?.generatedBy != nil"))
        #expect(stations.contains("MapStationLabelCoordinator.markerKey(item.record)"))
        // The timeline reads the same two fields for its pass rows.
        let timeline = SourceFiles.textRecording("RailMap/Journeys/RideDetailView.swift")
        #expect(timeline.contains("stop.stopType == \"pass_through\""))
        #expect(timeline.contains("stop.routeEditing?.generatedBy != nil"))
    }

    @Test func noMapMarkerLabelPrintsTheIdentityWord() throws {
        // Trip station names beside their dots.
        let label = try Self.body(
            Self.coordinator, from: "func mapStationLabel(", to: "private let cameraRebuildTimer")
        #expect(!label.contains("unresolved"))
        #expect(label.contains("guard let stationID, !stationID.isEmpty else { return name }"))
        let loop = try Self.body(
            Self.coordinator, from: "for recordIndex in recordCandidates {",
            to: "finishMarkerPhase(\"rideDotLoop\")")
        #expect(loop.contains("let stationName = mapStationLabel("))
        #expect(!loop.contains("unresolved"))
        // The Start/End cards.
        let card = try Self.body(
            Self.coordinator, from: "private func endpointSpec(", to: "private func layoutEndpointLabels(")
        #expect(!card.contains("unresolvedKey"))
        #expect(!card.contains("\"unresolved\""))
        #expect(card.contains("readings: unresolved ? [] : named.readings.map(\\.text))"))
        // "Unresolved" covers an id the registry cannot name, not only a missing one.
        #expect(card.contains("|| RegistryStationDisplay.resolve("))
        // No name is built with the word appended.
        #expect(!Self.coordinator.contains("name + \"\\n\" + word"))
        // What is left in the coordinator is the station CARD's readings.
        #expect(Self.occurrences(of: "RegistryStationDisplay.unresolvedKey", in: Self.coordinator) == 3)
        // Playback's station captions.
        let playback = SourceFiles.textRecording("RailMap/Playback/PlaybackController.swift")
        #expect(!playback.contains("unresolvedKey"))
        #expect(!playback.contains("\"unresolved\""))
        for path in [
            "RailMap/Map/MapEndpointLabels.swift", "RailMap/Map/JourneyLabelAnnotations.swift",
            "RailMap/Map/JourneyLabelAnnotationViews.swift", "RailMap/Map/StationAnnotations.swift",
            "RailMap/Map/StationAnnotationViews.swift", "RailMap/Map/PlaybackAnnotations.swift",
        ] {
            #expect(!SourceFiles.textRecording(path).contains("unresolved"), "\(path)")
        }
    }

    @Test func theControlChannelReportsTheSelectedTripsMarks() {
        let host = SourceFiles.textRecording("RailMap/Diagnostics/AppControl/AppControlHost.swift")
        #expect(host.contains("\"selectedTripMarks\": MapRenderProbe.selectedTripMarks.map"))
        #expect(Self.coordinator.contains("MapRenderProbe.selectedTripMarks = selectedTiers == nil ? nil : selectedTripMarks"))
    }
}
