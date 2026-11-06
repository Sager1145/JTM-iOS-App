import Foundation
import Testing

@testable import RailCore

/// The same exact-survey index must serve native join discovery and cache inputs.
/// Host arrival, replacement and removal change branch pixels at a fixed zoom.
struct StrokeJunctionDependencyTests {
    private let junction = Coordinate(lon: 139, lat: 35)

    private func line(
        _ id: String, _ coordinates: [Coordinate],
        operatorName: String = "Test Rail", follows: [String] = []
    ) -> StrokeJunctionIndex.Line {
        .init(id: id, region: "jp", operatorName: operatorName,
              coordinates: coordinates, continuous: true, follows: follows)
    }

    @Test func throughHostArrivalInvalidatesOnlyItsBranch() {
        let branch = line("jp|branch#0", [junction, .init(lon: 139.01, lat: 35.001)])
        let host = line("jp|main#4", [.init(lon: 138.99, lat: 35), junction,
                                      .init(lon: 139.02, lat: 35)])
        let unrelated = line("jp|other#0", [.init(lon: 140, lat: 35), .init(lon: 140.01, lat: 35)])
        let before = StrokeJunctionIndex([branch, unrelated])
        let after = StrokeJunctionIndex([branch, host, unrelated])

        #expect(before.dependencyIDs(of: branch.id) != after.dependencyIDs(of: branch.id))
        #expect(after.dependencyIDs(of: branch.id).contains(host.id))
        #expect(before.dependencyIDs(of: unrelated.id) == after.dependencyIDs(of: unrelated.id))
        #expect(after.candidateIDs(sharing: junction, region: "jp", operatorName: "Test Rail")
            == [branch.id, host.id])
    }

    @Test func hostAdjacentLaneInputsBelongToBranchDependencies() {
        let branch = line("jp|branch#0", [junction, .init(lon: 139.01, lat: 35.001)])
        let host = line("jp|main#4", [.init(lon: 138.99, lat: 35), junction,
                                      .init(lon: 139.02, lat: 35)])
        let beforeHost = line("jp|main#3", [.init(lon: 138.98, lat: 35), .init(lon: 138.99, lat: 35)])
        let afterHost = line("jp|main#5", [.init(lon: 139.02, lat: 35), .init(lon: 139.03, lat: 35)])
        let index = StrokeJunctionIndex([branch, host, beforeHost, afterHost])
        let dependencies = index.dependencyIDs(of: branch.id)

        #expect(dependencies.isSuperset(of: [host.id, beforeHost.id, afterHost.id]))
        let oldVersion = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let newVersion = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        var contentIDs = Dictionary(uniqueKeysWithValues: [host.id, beforeHost.id, afterHost.id]
            .map { ($0, oldVersion) })
        let before = contentIDs.filter { dependencies.contains($0.key) }
        contentIDs[afterHost.id] = newVersion
        let after = contentIDs.filter { dependencies.contains($0.key) }
        #expect(before != after)
    }

    @Test func nonAdjacentForkPartIsACacheDependency() {
        let first = line("jp|fork#0", [.init(lon: 138.99, lat: 35), junction])
        let second = line("jp|fork#1", [junction, .init(lon: 139.01, lat: 35)])
        let branch = line("jp|fork#7", [junction, .init(lon: 139.01, lat: 35.001)])
        let index = StrokeJunctionIndex([first, second, branch])

        #expect(index.dependencyIDs(of: first.id).contains(branch.id))
        #expect(index.dependencyIDs(of: branch.id).isSuperset(of: [first.id, second.id]))
    }

    @Test func nearbyOrOtherOperatorVerticesDoNotBecomeJunctionDependencies() {
        let branch = line("jp|branch#0", [junction, .init(lon: 139.01, lat: 35.001)])
        let nearby = line("jp|nearby#0", [.init(lon: 138.99, lat: 35.000001),
                                          .init(lon: 139, lat: 35.000001),
                                          .init(lon: 139.01, lat: 35.000001)])
        let otherOperator = line("jp|other#0", [.init(lon: 138.99, lat: 35), junction,
                                                 .init(lon: 139.01, lat: 35)],
                                 operatorName: "Other Rail")
        let index = StrokeJunctionIndex([branch, nearby, otherOperator])

        #expect(!index.dependencyIDs(of: branch.id).contains(nearby.id))
        #expect(!index.dependencyIDs(of: branch.id).contains(otherOperator.id))
    }
}
