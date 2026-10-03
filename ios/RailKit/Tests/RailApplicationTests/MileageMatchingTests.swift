import Foundation
import os
import RailApplication
import RailCore
import Testing

struct MileageMatchingTests {
    private let coordinates = [Coordinate(lon: 139, lat: 35), Coordinate(lon: 139.01, lat: 35)]

    private func index(validFrom: String? = nil) -> Statistics.EdgeIndex {
        Statistics.buildEdgeIndex(sections: [.init(properties: .init(
            n02_001: .string("11"), n02_002: .string("2"), n02_003: .string("test"),
            n02_004: .string("operator"), validFrom: validFrom), coordinates: coordinates)], country: "jp")
    }

    private func journey(
        id: String = "ride", digest: Int = 1, date: String = "2026-10-03", ridden: Bool = true
    ) -> MileageMatching.Journey {
        .init(train: .init(id: id, trainType: "local", date: date,
            stops: [.init(departure: "10:00", rideSegment: true),
                .init(arrival: "11:00", rideSegment: ridden)]), entryDigest: digest,
            segments: [.init(sourceCoordinates: coordinates, segmentIndex: 0, from: "A", to: "B")])
    }

    @Test func matchedEntryRetainsCanonicalGeometryAndRiddenBoundaryRules() throws {
        let network = index()
        let matched = try MileageMatching.match(journeys: [journey()], index: network, cache: [:])
        let expected = Statistics.collectTrainStatsEntry(features: [.init(
            lines: [coordinates], rideSegment: true, from: "A", to: "B")],
            index: network, rideDate: "2026-10-03")
        #expect(matched.entries[0].km > 0)
        #expect(matched.entries[0].km.bitPattern == expected.km.bitPattern)
        #expect(matched.entries[0].edges == expected.edges)
        #expect(matched.entries[0].segments.map(\.from) == ["A"])
        #expect(matched.entries[0].segments.map(\.to) == ["B"])
        let unRidden = try MileageMatching.match(journeys: [journey(ridden: false)], index: network, cache: [:])
        #expect(unRidden.entries[0].km == 0)
        #expect(unRidden.entries[0].segments.isEmpty)
    }

    @Test func cacheHitNeedsNoGeometryAndDeletedJourneysArePruned() throws {
        let network = index()
        let original = try MileageMatching.match(journeys: [journey(), journey(id: "deleted")], index: network, cache: [:])
        let updatedMetadata = MileageMatching.Journey(
            train: .init(id: "ride", trainType: "express", date: "2026-10-03"), entryDigest: 1, segments: [])
        let reused = try MileageMatching.match(journeys: [updatedMetadata], index: network, cache: original.cache)
        #expect(reused.entries[0].km.bitPattern == original.entries[0].km.bitPattern)
        #expect(reused.entries[0].edges == original.entries[0].edges)
        #expect(reused.trains[0].trainType == "express")
        #expect(Set(reused.cache.keys) == ["ride"])
        let empty = try MileageMatching.match(journeys: [], index: network, cache: reused.cache)
        #expect(empty.entries.isEmpty && empty.trains.isEmpty && empty.cache.isEmpty)
    }

    @Test func pendingRouteRejectsStaleGeometryAndCachedPreciseMileage() throws {
        let network = index()
        let confirmed = journey()
        let previous = try MileageMatching.match(journeys: [confirmed], index: network, cache: [:])
        #expect(previous.entries[0].km > 0)
        let pending = MileageMatching.Journey(train: confirmed.train, entryDigest: confirmed.entryDigest,
            segments: confirmed.segments, routeConfirmation: .pending)
        let result = try MileageMatching.match(journeys: [pending], index: network, cache: previous.cache)
        #expect(result.entries[0].km == 0)
        #expect(!result.entries[0].distanceIsKnown)
        #expect(result.entries[0].edges.isEmpty)
        #expect(result.entries[0].segments.isEmpty)
        #expect(result.cache[confirmed.train.id] == nil)
        let reconfirmed = try MileageMatching.match(journeys: [confirmed], index: network, cache: result.cache)
        #expect(reconfirmed.entries[0].km == previous.entries[0].km)
        #expect(reconfirmed.entries[0].distanceIsKnown)
    }

    @Test func disconnectedJourneyRetainsProvenPartsWithoutACompleteDistance() throws {
        let network = index()
        let complete = journey()
        let partial = MileageMatching.Journey(train: complete.train, entryDigest: 2,
            segments: complete.segments, fullDistanceKnown: false)
        let result = try MileageMatching.match(journeys: [partial], index: network, cache: [:])
        #expect(result.entries[0].km > 0)
        #expect(!result.entries[0].distanceIsKnown)
        #expect(result.entries[0].partialDistanceIsProven)
        let original = try MileageMatching.match(journeys: [complete], index: network, cache: [:])
        let cachedPartial = MileageMatching.Journey(train: complete.train, entryDigest: 1,
            segments: [], fullDistanceKnown: false)
        let reused = try MileageMatching.match(journeys: [cachedPartial], index: network, cache: original.cache)
        #expect(reused.entries[0].km == original.entries[0].km)
        #expect(!reused.entries[0].distanceIsKnown)
        #expect(reused.entries[0].partialDistanceIsProven)
        let noGeometry = MileageMatching.Journey(train: complete.train, entryDigest: 3,
            segments: [], fullDistanceKnown: false)
        let empty = try MileageMatching.match(journeys: [noGeometry], index: network, cache: [:])
        #expect(!empty.entries[0].distanceIsKnown)
        #expect(!empty.entries[0].partialDistanceIsProven)
        let future = try MileageMatching.match(journeys: [partial], index: index(validFrom: "2027-01-01"), cache: [:])
        #expect(!future.entries[0].partialDistanceIsProven)
        let pending = MileageMatching.Journey(train: complete.train, entryDigest: 2,
            segments: complete.segments, routeConfirmation: .pending, fullDistanceKnown: false)
        let unconfirmed = try MileageMatching.match(journeys: [pending], index: network, cache: result.cache)
        #expect(unconfirmed.entries[0].km == 0)
        #expect(!unconfirmed.entries[0].partialDistanceIsProven)
    }

    @Test func changedDigestRematchesIdenticalGeometryForHistoricalDate() throws {
        let network = index(validFrom: "2020-01-01")
        let original = try MileageMatching.match(journeys: [journey()], index: network, cache: [:])
        let earlier = try MileageMatching.match(
            journeys: [journey(digest: 2, date: "2010-01-01")], index: network, cache: original.cache)
        #expect(original.entries[0].edges == [0])
        #expect(earlier.entries[0].edges.isEmpty)
        #expect(earlier.cache["ride"]?.digest == 2)
        #expect(earlier.trains[0].date == "2010-01-01")
    }

    @Test func matchingPreservesInputOrderAndBlockProgressIncludingCacheHits() throws {
        let network = index()
        let inputs = (0..<26).map { journey(id: "ride-\(25 - $0)") }
        let original = try MileageMatching.match(journeys: inputs, index: network, cache: [:])
        let progress = MileageProgressRecorder()
        let reused = try MileageMatching.match(
            journeys: inputs, index: network, cache: original.cache, report: progress.record)
        #expect(reused.trains.map(\.id) == inputs.map { $0.train.id })
        #expect(reused.entries.map { $0.km.bitPattern } == original.entries.map { $0.km.bitPattern })
        #expect(progress.values == [25, 26])
    }

    @Test func cancelledMatchingDoesNotReportOrReturnPartialResult() async {
        let network = index()
        let input = journey()
        let progress = MileageProgressRecorder()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try MileageMatching.match(journeys: [input], index: network, cache: [:], report: progress.record)
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }
        #expect(await task.value)
        #expect(progress.values.isEmpty)
    }

    @Test func cancellationAfterProgressDoesNotReturnAPartialCache() async {
        let network = index()
        let inputs = (0..<26).map { journey(id: "ride-\($0)") }
        let progress = MileageProgressRecorder()
        let task = Task {
            do {
                _ = try MileageMatching.match(journeys: inputs, index: network, cache: [:]) { count in
                    progress.record(count)
                    withUnsafeCurrentTask { $0?.cancel() }
                }
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }
        #expect(await task.value)
        #expect(progress.values == [25])
    }
}

private final class MileageProgressRecorder: Sendable {
    private let storage = OSAllocatedUnfairLock(initialState: [Int]())

    func record(_ value: Int) { storage.withLock { $0.append(value) } }
    var values: [Int] { storage.withLock { $0 } }
}
