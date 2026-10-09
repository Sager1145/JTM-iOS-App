#!/usr/bin/env python3
"""Exercise the production selected-record completion query with tiny inputs.

No graph, route, confirmation or graphics implementation is replaced by this
query. The test double supplies only existing completion/ticket dictionaries.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
source = (ROOT / 'ios/RailMap/RiddenRouteStore.swift').read_text()
start = source.index('    func hasSettledRoutes(')
end = source.index('    /// Solve and draw every ride', start)
query = source[start:end]
swift = r'''
import Foundation
struct Train: Equatable {
    let id: String
    var date: String = "2026-07-03"
    var region: String = "jp"
    var version: Int = 0
}
final class Store {
    enum LoadState { case idle, loading, loaded, failed }
    var state: LoadState = .loading
    var completedInputs: [String: Train] = [:]
    var resolutionTickets: [String: UUID] = [:]
''' + query + r'''
}
let store = Store()
let member = Train(id: "member")
let arrival = Train(id: "arrival")
let otherDate = Train(id: "other-date", date: "2026-07-04")
let otherRegion = Train(id: "other-region", region: "tw")
let inputs = [member, arrival, otherDate, otherRegion]
let selected: (Train) -> Bool = { $0.date == "2026-07-03" && $0.region == "jp" }
var checks = 0
func check(_ result: Bool, _ description: String) {
    precondition(result, description)
    checks += 1
    print("PASS \(description)")
}
check(!store.hasSettledRoutes(in: inputs, matching: selected),
      "cold selected inputs cannot expose an incomplete export")
store.completedInputs[member.id] = member
check(!store.hasSettledRoutes(in: inputs, matching: selected),
      "first selected partial cannot stand in for the pending arrival")
store.completedInputs[arrival.id] = arrival
check(store.hasSettledRoutes(in: inputs, matching: selected),
      "selected completion does not wait for unrelated dates or countries")
store.resolutionTickets[arrival.id] = UUID()
check(!store.hasSettledRoutes(in: inputs, matching: selected),
      "active same-record resolution cannot reuse its old completion")
store.resolutionTickets.removeValue(forKey: arrival.id)
check(store.hasSettledRoutes(in: inputs, matching: selected),
      "terminal unavailable completion needs no drawn-ride presence")
var edited = arrival
edited.version += 1
check(!store.hasSettledRoutes(in: [member, edited], matching: selected),
      "same-ID edited record cannot reuse a stale completed input")
store.completedInputs[edited.id] = edited
check(store.hasSettledRoutes(in: [member, edited], matching: selected),
      "exact edited-record completion restores selected readiness")
store.resolutionTickets[otherDate.id] = UUID()
check(store.hasSettledRoutes(in: [member, edited, otherDate], matching: selected),
      "unrelated active ticket does not block selected export")
check(store.hasSettledRoutes(in: [], matching: selected),
      "empty candidate set has no pending record")
check(store.hasSettledRoutes(in: inputs, matching: { _ in false }),
      "selection excluding all inputs has no pending record")
store.completedInputs.removeValue(forKey: edited.id)
store.state = .failed
check(store.hasSettledRoutes(in: [member, edited], matching: selected),
      "terminal batch failure permits existing unknown-distance presentation")
check(store.completedInputs[edited.id] == nil,
      "failed input is not marked completed or suppressed from explicit retry")
store.state = .loading
check(!store.hasSettledRoutes(in: [member, edited], matching: selected),
      "explicit retry blocks its unfinished selected input again")
print("\(checks) selected-route readiness checks PASS")
'''
with tempfile.TemporaryDirectory(prefix='jtm-selected-readiness-') as folder:
    path = Path(folder)
    (path / 'main.swift').write_text(swift)
    subprocess.run(['swiftc', str(path / 'main.swift'), '-o', str(path / 'checks')], check=True)
    subprocess.run([str(path / 'checks')], check=True)
