import Foundation
import RailCore
import RailPresentation

// The benchmark suite for the pure tiers.
//
// Every number this prints is a median of nine runs on the machine it runs on,
// in release. It is not a substitute for a device trace — it cannot see MapKit,
// SwiftUI or storage — but it is the only kind of evidence available for the
// arithmetic those layers call into, and it is repeatable, which a hand-timed
// interaction is not.

let root = Repo.root()
let arguments = Set(CommandLine.arguments.dropFirst())
func runs(_ name: String) -> Bool { arguments.isEmpty || arguments.contains(name) }

print("RailBench — \(ProcessInfo.processInfo.hostName), \(root.path)")
print(String(repeating: "=", count: 104))

if runs("search") { benchmarkSearch(root: root); benchmarkLocalizedSearch(root: root) }
if runs("stations") { benchmarkStationPicker(root: root) }
if runs("predicates") { benchmarkStationPredicates(root: root) }
if runs("tap") { benchmarkTap(root: root) }
if runs("rebuild") { benchmarkMapRebuild(root: root) }
if runs("statistics") { benchmarkStatistics(root: root) }
if runs("routes") { benchmarkRouteLoad(root: root); benchmarkRouteCacheIO(root: root) }
if runs("editor") { benchmarkEditorValidation(root: root) }
if runs("launch") { benchmarkLaunchLoad(root: root) }
