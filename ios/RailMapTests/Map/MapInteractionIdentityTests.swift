import MapKit
import RailCore
import Testing
@testable import RailMap

@MainActor
struct MapInteractionIdentityTests {
    @Test func knownRegionDoesNotResolveToAnotherRegionsCoincidentCode() throws {
        let interaction = MapInteractionCoordinator()
        interaction.replaceStations([
            .init(id: "foreign-platform", region: .kr, lineID: "line", stationCode: "shared",
                name: "Foreign station", nameRoma: "", coordinate: .init(lon: 139, lat: 35),
                colorHex: "#000000", minZoom: 0, lodMinZoom: 0,
                isTerminal: false, showsLabel: true,
                popup: .init(name: "Foreign station", nameRoma: "", readings: [], lines: []),
                lane: 0, laneBearing: nil),
        ])
        func annotation(region: Region?) -> RideStationAnnotation {
            RideStationAnnotation(rideID: "ride", drawsInOverlay: false,
                coordinate: .init(latitude: 35, longitude: 139), name: "Recorded station",
                rawName: "Recorded station", stationCode: "shared", region: region, role: "stop",
                radius: 3, lineWidth: 1, ordinaryRadius: 3, ordinaryLineWidth: 1,
                focusScale: 1, fill: .white, stroke: .black, alpha: 1,
                focusBoost: 1, selected: false)
        }
        let card = try #require(interaction.stationCard(for: annotation(region: .jp), named: { name, _ in (name, nil) }))
        #expect(card.region == .jp)
        #expect(card.rawName == "Recorded station")
        let unknown = try #require(interaction.stationCard(for: annotation(region: nil), named: { name, _ in (name, nil) }))
        #expect(unknown.region == .kr)
        #expect(unknown.rawName == "Foreign station")
    }
}
