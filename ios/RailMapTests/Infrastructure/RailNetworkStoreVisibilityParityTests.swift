import Foundation
import Testing

@testable import RailMap

/// The map's fragments, the canonical lines, the station thresholds and the
/// label election must all read ONE visibility tier. The builder's visibility
/// groups (`build-display-network.py` `visibility_groups`) also join a corridor
/// split across operators, which the package's operator+name grouping cannot
/// see, so the store takes the tier from the manifest. For every Japanese line
/// the native threshold of the decoded line must equal the one the manifest's
/// own fragments draw at, and no station may precede its line.
struct RailNetworkStoreVisibilityParityTests {
    @Test func decodedLineThresholdEqualsManifestFragmentThresholdForEveryJapaneseLine() async throws {
        let manifest = try RailDisplayNetwork.manifest()
        let decoded = try await RailNetworkStore.decode(region: .jp, catalog: manifest.lines)
        #expect(!decoded.lines.isEmpty)
        var lodByLine: [String: Double] = [:]
        for line in decoded.lines {
            let entry = try #require(manifest.lines["jp|\(line.lineID)"], "no manifest entry for \(line.lineID)")
            let expected = RailStyle.zoom(fromMapLibre: Double(entry.nativeMinZoomMapLibre))
            #expect(line.lodMinZoom == expected, "\(line.lineID): decoded \(line.lodMinZoom) manifest \(expected)")
            lodByLine[line.lineID] = line.lodMinZoom
        }
        for station in decoded.stations {
            if let lineLod = lodByLine[station.lineID] {
                #expect(station.lodMinZoom >= lineLod, "\(station.id) precedes line \(station.lineID)")
            }
        }
    }
}
