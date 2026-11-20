import CoreLocation
import Foundation
import MapKit
import Testing

@testable import RailMap

/// `RailDisplayNetwork.closure` must give the same ordered array as the
/// full-manifest scan it replaced (kept verbatim below), and must only walk
/// regions that hold a selected line.
@Suite("RegressionGuardDisplayClosureBehaviour")
struct RegressionGuardDisplayClosureBehaviourTests {
    /// The previous implementation, verbatim.
    private static func legacyClosure(
        of entries: [RailDisplayNetworkIndex.Entry],
        in index: RailDisplayNetworkIndex
    ) -> [RailDisplayNetworkIndex.Entry] {
        let allEntries = index.entryByID
        var selected = Set(entries.map(\.id))
        var frontier = Array(selected)
        while !frontier.isEmpty {
            var next: [String] = []
            for id in frontier {
                guard let entry = allEntries[id] else { continue }
                for dependencyID in entry.dependsOn where !selected.contains(dependencyID) {
                    guard allEntries[dependencyID] != nil else { continue }
                    selected.insert(dependencyID)
                    next.append(dependencyID)
                }
            }
            frontier = next
        }
        return index.orderedRegions.flatMap { region in
            (index.entriesByRegion[region] ?? []).filter { selected.contains($0.id) }
        }
    }

    private func rect(lat: Double, lon: Double, span: Double) -> MKMapRect {
        let a = MKMapPoint(CLLocationCoordinate2D(latitude: lat + span, longitude: lon - span))
        let b = MKMapPoint(CLLocationCoordinate2D(latitude: lat - span, longitude: lon + span))
        return MKMapRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
    }

    @Test("same ordered result as the full scan, and no unselected region walked")
    func matchesLegacyAndSkipsUnselectedRegions() throws {
        let index = RailDisplayNetworkIndex.lineIndex(for: try RailDisplayNetwork.manifest())
        // One rect per region (centre of its extent), several sizes, plus the whole world.
        var rects: [MKMapRect] = [.world]
        for record in index.recordsByRegion.values where !record.mapRect.isNull {
            let c = MKMapPoint(x: record.mapRect.midX, y: record.mapRect.midY)
            let coordinate = c.coordinate
            for span in [0.05, 0.4, 3.0] {
                rects.append(rect(lat: coordinate.latitude, lon: coordinate.longitude, span: span))
            }
        }
        var nonEmpty = 0
        for r in rects {
            for zoom in [4.0, 9.0, 13.0] {
                let base = RailDisplayNetwork.lines(intersecting: r, cameraZoom: zoom, in: index)
                let legacy = Self.legacyClosure(of: base, in: index)
                let new = RailDisplayNetwork.closureScanningRegions(of: base, in: index)
                #expect(new.entries.map(\.id) == legacy.map(\.id))
                #expect(RailDisplayNetwork.closure(of: base, in: index).map(\.id) == legacy.map(\.id))
                let resultRegions = Set(new.entries.map(\.region))
                #expect(Set(new.scannedRegions) == resultRegions,
                        "closure walked a region that holds no selected line")
                if !new.entries.isEmpty { nonEmpty += 1 }
            }
        }
        #expect(nonEmpty > 0)
    }

    @Test("a dependsOn chain across regions keeps its order")
    func dependencyChainOrder() throws {
        let index = RailDisplayNetworkIndex.lineIndex(for: try RailDisplayNetwork.manifest())
        let dependents = index.entryByID.values.filter { !$0.dependsOn.isEmpty }
        let sample = Array(dependents.sorted { $0.id < $1.id }.prefix(200))
        #expect(!sample.isEmpty)
        let new = RailDisplayNetwork.closure(of: sample, in: index).map(\.id)
        #expect(new == Self.legacyClosure(of: sample, in: index).map(\.id))
    }
}
