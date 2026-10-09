#!/usr/bin/env python3
"""Exercise extracted production graph/input lifetime plumbing with controlled data.

Usage: verify-input-plumbing.py [RiddenRouteStore.swift]
The immutable input decoder, graph owner and route solver are controlled doubles;
production batch ordering, both solver passes and input selection are unchanged.
This checks ownership/control flow, not physical routes or real memory footprint.
"""
from pathlib import Path
import subprocess,tempfile,sys
root = Path(__file__).resolve().parents[2]
source = (Path(sys.argv[1]) if len(sys.argv) > 1 else root / 'ios/RailMap/RiddenRouteStore.swift').read_text()
def section(a,b):
 x=source.index(a);return source[x:source.index(b,x)]
decode=section('    @concurrent private nonisolated static func decode(','    /// The shared inference, dataset, and solver pipeline')
uncached=section('    @concurrent private nonisolated static func decodeUncached(','    /// The rides one precomputed dataset can answer for.')
if '    @concurrent private nonisolated static func solveMissingConcurrently(' in source:
 missing=section('    @concurrent private nonisolated static func solveMissing(','    /// The legacy coordinator')
 concurrent=section('    @concurrent private nonisolated static func solveMissingConcurrently(','        let queue = JourneyWorkQueue(indices: indices)')+'        fatalError("Fixture must take production W=1 path")\n    }\n'
 name='solveMissingSequentialWithPermit'
else:
 missing=section('    @concurrent private nonisolated static func solveMissing(','    /// The load path awaits each pass in sequence')
 concurrent=''
 name='solveMissingWithPermit'
prologue=section('    @concurrent private nonisolated static func '+name+'(','        let stationIndex = inputs.stationIndex')
swift=r'''
import Foundation
import Synchronization
struct Train: Sendable { let id: String; let scope: String; var requiresRouteConfirmation: Bool { false } }
struct DrawnRide: Sendable { let id: String }
struct RouteScope: Hashable, Sendable {
 let code: String
 var home: String { code }
 init(_ train: Train) { code = train.scope }
 static func ordered<S: Sequence>(_ scopes: S) -> [Self] where S.Element == Self { scopes.sorted { $0.code < $1.code } }
}
final class InputOwner: Sendable { let scope: String; let id = UUID(); init(_ scope: String) { self.scope = scope } }
struct SolverInputs: Sendable { let owner: InputOwner }
final class Probe: Sendable {
 struct State { var decodes: [String] = []; var solves: [String] = []; var liveGraphs: Set<UUID> = []; var identities: [String: UUID] = [:] }
 let state = Mutex(State())
}
let probe = Probe()
enum RouteGraph {
 final class RouteGraphStore: Sendable {
  let inputs: SolverInputs; let id = UUID()
  init(_ inputs: SolverInputs) { self.inputs = inputs; probe.state.withLock { $0.liveGraphs.insert(id) } }
  deinit { probe.state.withLock { $0.liveGraphs.remove(id) } }
 }
}
struct UncheckedGraphStoreBox: Sendable { let store: RouteGraph.RouteGraphStore }
actor SolverInputCache {
 static let shared = SolverInputCache()
 var completed: SolverInputs?
 func reset() { completed = nil }
 func inputs(scope: RouteScope) -> SolverInputs {
  if let completed, completed.owner.scope == scope.code { return completed }
  let result = SolverInputs(owner: InputOwner(scope.code)); completed = result
  probe.state.withLock { $0.decodes.append(scope.code) }
  return result
 }
}
struct Network: Sendable { }
actor DisplayNetworkCache { static let shared = DisplayNetworkCache(); func network(scope: RouteScope) -> Network { Network() } }
actor RouteSolveLimiter {
 static let shared = RouteSolveLimiter()
 nonisolated func withPermit<T: Sendable>(_ operation: @Sendable () async throws -> T) async rethrows -> T { try await operation() }
}
enum RideLibrary { static func routeDatasets(for home: String) -> [Int] { [] } }
actor PrecomputedRouteRejections { func reject(_ id: String) {} ; func allowed(_ trains: [String: Train]) -> [String: Train] { trains } }
enum RiddenRouteStore {
 static let maximumJourneyWorkers = 1
 static func loadCachedConcurrently(_ trains: [Train], country: String) async -> (rides: [DrawnRide], missing: [Train]) { ([],trains) }
 static func fallbackGraphStore(inputs: SolverInputs, displayNetwork: Network?) -> RouteGraph.RouteGraphStore { .init(inputs) }
 static func datasetRides(dataset: Int, country: String, wanted: [String: Train], publish: @Sendable ([DrawnRide]) async -> Void) async throws -> [DrawnRide] { [] }
 static func run(_ trains: [Train], preferred: String?) async throws -> [DrawnRide] {
  try await decode(wanted: Dictionary(uniqueKeysWithValues: trains.map { ($0.id,$0) }), requestedOrder: trains.map(\.id), preferredTrainID: preferred)
 }
'''+decode+uncached+missing+concurrent+prologue+r'''
        guard let graphStore else { fatalError("Expected carried graph") }
        precondition(inputs.owner === graphStore.inputs.owner, "Graph/input owner identity diverged")
        precondition(inputs.owner.scope == scope.code)
        probe.state.withLock { state in
            if let original = state.identities[scope.code] { precondition(original == inputs.owner.id) }
            state.identities[scope.code] = inputs.owner.id
            state.solves.append(contentsOf: trains.map(\.id))
        }
        return allowLegacy ? trains.map { DrawnRide(id: $0.id) } : []
    }
}
@main struct Checks {
 static func run(_ trains: [Train], _ preferred: String?, decodes: [String], rides: [String]) async throws {
  await SolverInputCache.shared.reset(); probe.state.withLock { $0 = .init() }
  let result = try await RiddenRouteStore.run(trains, preferred: preferred)
  precondition(result.map(\.id) == rides)
  probe.state.withLock { state in
   precondition(state.decodes == decodes, "Unexpected decoder reentry: \(state.decodes)")
   precondition(state.liveGraphs.isEmpty, "Processed scope graph escaped decode")
  }
 }
 static func main() async throws {
  let trains = [Train(id:"a",scope:"a"),Train(id:"b",scope:"b"),Train(id:"z-preferred",scope:"z"),Train(id:"z-rest",scope:"z")]
  try await run(trains,"z-preferred",decodes:["z","a","b"],rides:["z-preferred","a","b","z-rest"])
  print("PASS production decode/uncached/dispatch/W=1/prologue plumbing preserves identical carried inputs after earlier ordered scopes evict preferred inputs; no second preferred decode")
  try await run(Array(trains.dropLast()),"z-preferred",decodes:["z","a","b"],rides:["z-preferred","a","b"])
  print("PASS empty preferred and processed scope graph/input contexts release; original route order preserved")
  try await run(trains,nil,decodes:["a","b","z"],rides:["a","b","z-preferred","z-rest"])
  print("PASS ordinary ordered multi-scope batches decode once per scope with both solver passes sharing original owner identity")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='jtm-input-plumbing-') as d:
 p=Path(d);(p/'Checks.swift').write_text(swift)
 subprocess.run(['xcrun','swiftc','-swift-version','6','-parse-as-library','-O','-module-cache-path',str(p/'modules'),str(p/'Checks.swift'),'-o',str(p/'checks')],check=True,timeout=90)
 subprocess.run([str(p/'checks')],check=True,timeout=20)
