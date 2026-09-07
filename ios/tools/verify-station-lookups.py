#!/usr/bin/env python3
"""Test StationPlaceStore against a controllable MapKit transport, without network.
Usage: DEVELOPER_DIR=... python3 ios/tools/verify-station-lookups.py <SPM scratch>
"""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[2]
libs = list(Path(sys.argv[1]).rglob('libRailCore.a'))
if not libs:
    raise SystemExit('Build RailKit in the supplied scratch directory first.')
products = libs[0].parent
source = (root / 'ios/RailMap/StationPlaceStore.swift').read_text()
source = source.replace('import MapKit', 'import Foundation\nimport CoreLocation').replace('import SwiftUI', '')
harness = r'''
import Foundation
import CoreLocation
import RailCore
import RailPresentation

enum Region: String { case jp; var code: String { rawValue } }
struct StationCard {
    let id: String
    var coordinate = Coordinate(lon: 139.767, lat: 35.681)
    var region = Region.jp
    var searchNames = ["東京"]
}
extension Coordinate { var clLocation: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) } }
struct MKCoordinateRegion {
    init(center: CLLocationCoordinate2D, latitudinalMeters: Double, longitudinalMeters: Double) {}
}
struct MKError: Error { enum Code { case placemarkNotFound }; let code: Code }
enum MKPointOfInterestCategory { case publicTransport }
struct MKPointOfInterestFilter { init(including: [MKPointOfInterestCategory]) {} }
@MainActor final class MKMapItem {
    struct Identifier { let rawValue: String }
    var name: String? = "東京"
    var pointOfInterestCategory: MKPointOfInterestCategory? = .publicTransport
    var identifier: Identifier? = Identifier(rawValue: "test-place")
    var location = CLLocation(latitude: 35.681, longitude: 139.767)
    var placemark: CLLocation { location }
}
@MainActor final class MKLocalSearch {
    final class Request {
        enum ResultType { case pointOfInterest }
        var naturalLanguageQuery: String?
        var region: MKCoordinateRegion?
        var resultTypes = ResultType.pointOfInterest
        var pointOfInterestFilter: MKPointOfInterestFilter?
    }
    struct Response { let mapItems: [MKMapItem] }
    enum Mode { case hold, empty, failure, notFound }
    static var mode = Mode.hold
    static var started = 0
    static var cancelled = 0
    static var active: [MKLocalSearch] = []
    var callback: (@MainActor (Response?, Error?) -> Void)?
    init(request: Request) {}
    func start(completionHandler: @escaping @MainActor (Response?, Error?) -> Void) {
        Self.started += 1
        callback = completionHandler
        Self.active.append(self)
        switch Self.mode {
        case .hold: break
        case .empty: completionHandler(Response(mapItems: []), nil)
        case .failure: completionHandler(nil, URLError(.notConnectedToInternet))
        case .notFound: completionHandler(nil, MKError(code: .placemarkNotFound))
        }
    }
    func cancel() { Self.cancelled += 1 }
    static func answer() { for search in active { search.callback?(Response(mapItems: [MKMapItem()]), nil) }; active = [] }
    static func reset(_ mode: Mode) { self.mode = mode; started = 0; cancelled = 0; active = [] }
}
@main struct Checks {
    @MainActor static func main() async throws {
        func waitForStart(_ count: Int = 1) async {
            while MKLocalSearch.started < count { await Task.yield() }
        }
        let store = StationPlaceStore()
        let card = StationCard(id: "shared")
        MKLocalSearch.reset(.hold)
        let first = Task { await store.place(for: card) }
        await waitForStart()
        let second = Task { await store.place(for: card) }
        // Register both waiters before cancellation; the shared actor turn
        // has no suspension between registration and awaiting the lookup.
        for _ in 0..<20 { await Task.yield() }
        first.cancel()
        for _ in 0..<20 { await Task.yield() }
        precondition(MKLocalSearch.started == 1 && MKLocalSearch.cancelled == 0)
        MKLocalSearch.answer()
        let one = await first.value, two = await second.value
        precondition(one == nil && two != nil)
        let cached = await store.place(for: card)
        precondition(cached != nil && MKLocalSearch.started == 1)
        print("PASS coalesced lookups survive one cancelled waiter and cache the hit")

        MKLocalSearch.reset(.hold)
        let cancelled = Task { await store.place(for: StationCard(id: "cancel")) }
        await waitForStart()
        cancelled.cancel()
        let result = await cancelled.value
        precondition(result == nil && MKLocalSearch.cancelled == 1)
        MKLocalSearch.answer() // Late callback must not resume twice.
        print("PASS last-waiter cancellation ends MapKit work and ignores a late callback")

        MKLocalSearch.reset(.empty)
        let missCard = StationCard(id: "miss")
        _ = await store.place(for: missCard)
        let attempts = MKLocalSearch.started
        _ = await store.place(for: missCard)
        precondition(attempts > 0 && attempts == MKLocalSearch.started)
        _ = await store.place(for: missCard, aliases: ["Tokyo"])
        precondition(MKLocalSearch.started > attempts)
        print("PASS definitive misses are cached and new aliases invalidate that cache")

        MKLocalSearch.reset(.notFound)
        let absent = StationCard(id: "placemark-not-found")
        _ = await store.place(for: absent)
        let absentAttempts = MKLocalSearch.started
        _ = await store.place(for: absent)
        precondition(absentAttempts == MKLocalSearch.started)
        print("PASS MapKit placemarkNotFound is cached as a definitive miss")

        MKLocalSearch.reset(.failure)
        let retryCard = StationCard(id: "retry")
        _ = await store.place(for: retryCard)
        let failedAttempts = MKLocalSearch.started
        _ = await store.place(for: retryCard)
        precondition(MKLocalSearch.started > failedAttempts)
        print("PASS a transient network failure remains retryable")

        MKLocalSearch.reset(.hold)
        let began = ContinuousClock.now
        let timeout = await store.place(for: StationCard(id: "timeout"))
        let elapsed = began.duration(to: .now)
        precondition(timeout == nil && elapsed >= .seconds(6) && elapsed < .seconds(8))
        precondition(MKLocalSearch.started == 1 && MKLocalSearch.cancelled == 1)
        MKLocalSearch.answer()
        print("PASS the entire lookup plan has one six-second deadline (\(elapsed))")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='jtm-station-lookups-') as temporary:
    folder = Path(temporary)
    implementation = folder / 'StationPlaceStore.swift'
    checks = folder / 'Checks.swift'
    implementation.write_text(source)
    checks.write_text(harness)
    executable = folder / 'checks'
    sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '6', '-parse-as-library',
                    '-sdk', sdk, '-I', str(products), str(implementation), str(checks),
                    str(libs[0]), str(products / 'libRailPresentation.a'),
                    '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True, timeout=30)
