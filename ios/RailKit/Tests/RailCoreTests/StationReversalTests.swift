import Foundation
import Testing
@testable import RailCore

struct StationReversalTests {
    @Test func surveyedReturnKeepsBothApproachTangents() {
        // Pacific Surfliner's actual Union Station platform and shared tail.
        let station = Coordinate(lon: -118.234202, lat: 34.055782)
        let a = Coordinate(lon: -118.233599, lat: 34.05848)
        let b = Coordinate(lon: -118.233478, lat: 34.058779)
        var arriving = [b, a, station]
        var leaving = [station, a, b]
        DisplayParts.dropStationRepeat(&arriving, &leaving)
        #expect(arriving == [b, a, station])
        #expect(leaving == [station, a, b])
    }

    @Test func singleDuplicateNeighbourIsStillRemoved() {
        let p = (0...4).map { Coordinate(lon: Double($0) * 0.001, lat: 35) }
        var arriving = [p[0], p[1], p[2]]
        var leaving = [p[2], p[1], p[4]]
        DisplayParts.dropStationRepeat(&arriving, &leaving)
        #expect(arriving.count + leaving.count == 5)
    }

    @Test func sharedReversalNeverExtendsPastStation() {
        typealias Point = ContinuousStroke.Point
        for degrees in [150.01, 178.39, 179.1727, 179.963, 180] {
            let radians = degrees * .pi / 180
            let outgoing = Point(x: cos(radians), y: sin(radians))
            for lane in [-3.5, -0.5, 0.5, 2.5] {
                let join = ContinuousStroke.Join(lane: lane, incoming: .init(x: 1, y: 0), outgoing: outgoing)
                for strict in [false, true] {
                    func build(_ points: [Point], start: Bool) -> ContinuousStroke.Stroke {
                        ContinuousStroke.buildStroke(points, options: .init(
                            measures: [0, 50, 100], rows: [.init(from: 0, to: 100, lane: lane)],
                            totalMetres: 100, laneGapPx: 2.7, minRampPx: 24,
                            cornerRadiusPx: 3.6, minCornerRadiusPx: 3, anchors: [0, 2],
                            joinStart: start ? join : nil, joinEnd: start ? nil : join,
                            enforceMinimumCornerRadius: strict))
                    }
                    let arriving = build([.init(x: -100, y: 0), .init(x: -50, y: 0), .init(x: 0, y: 0)], start: false)
                    let leaving = build([.init(x: 0, y: 0), .init(x: outgoing.x * 50, y: outgoing.y * 50),
                                         .init(x: outgoing.x * 100, y: outgoing.y * 100)], start: true)
                    #expect(arriving.points.last == leaving.points.first)
                    #expect(abs(arriving.points.last!.x) < 1e-9)
                    #expect(abs(arriving.points.last!.y - lane * 2.7) < 1e-9)
                }
            }
        }
    }
}
