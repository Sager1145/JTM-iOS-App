import Foundation
import Testing
import RailCore
@testable import RailPresentation

/// The pack ladder counts zoom in the stroke engine's 512-point convention; the camera and
/// `GeometryZoomLevels` count the app's 256-point zoom, one higher. `RailPackLadder.appZoomOffset` is
/// the one mapping; these tests pin that the level the reader picks for a camera zoom is the level
/// `GeometryZoomLevels` picks, and that both cover the same scale (`mapPointsPerPoint`).
@Suite("RailPackLadder zoom mapping")
struct RailPackLadderZoomTests {

    static let ladder = RailPackLadder.default
    static let lowest = ladder.appZoom(level: 0), highest = ladder.appZoom(level: ladder.levelCount - 1)

    @Test("the nearest level for a camera zoom is the level GeometryZoomLevels wants, on and off the grid")
    func nearestLevelMatches() {
        var checked = 0
        // Off the grid (steps of 0.013) and exactly on half-way ties (steps of 0.25).
        for step in Array(stride(from: 3.0, through: 20.0, by: 0.013)) + Array(stride(from: 3.0, through: 20.0, by: 0.25)) {
            let wanted = GeometryZoomLevels.nominalZoom(level: GeometryZoomLevels.nearestLevel(zoom: step))
            let level = Self.ladder.nearestLevel(cameraZoom: step)
            #expect(Self.ladder.appZoom(level: level) == min(max(wanted, Self.lowest), Self.highest), "camera zoom \(step)")
            checked += 1
        }
        #expect(checked > 1_000)
    }

    @Test("the level's scale is the scale the geometry level draws at")
    func scalesMatch() {
        for level in 0..<Self.ladder.levelCount {
            let appZoom = Self.ladder.appZoom(level: level)
            // App zoom z draws 256-point tiles: worldSize / (256 * 2^z) map points per point.
            let appScale = StrokeProjection.worldSize / (256 * pow(2, GeometryZoomLevels.nominalZoom(level: Int((appZoom * 2).rounded()))))
            #expect(abs(appScale - Self.ladder.mapPointsPerPoint(level: level)) < 1e-9 * appScale, "level \(level)")
        }
    }

    @Test("a camera moving through the ladder keeps and changes levels where GeometryZoomLevels does")
    func hysteresisMatches() {
        for installed in 0..<Self.ladder.levelCount {
            let geometryInstalled = Int((Self.ladder.appZoom(level: installed) * 2).rounded())
            for step in stride(from: Self.lowest - 0.7, through: Self.highest + 0.7, by: 0.0137) {
                let wanted = GeometryZoomLevels.wantedLevel(zoom: step, installed: geometryInstalled)
                let chosen = Self.ladder.chooseLevel(cameraZoom: step, installed: installed)
                let expected = min(max(Double(wanted) * 0.5, Self.lowest), Self.highest)
                #expect(Self.ladder.appZoom(level: chosen) == expected, "installed \(installed), camera zoom \(step)")
            }
        }
    }
}
