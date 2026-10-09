#!/usr/bin/env python3
"""Execute the production snapshot lifecycle owner with controlled async loads."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
owner = root / "ios/RailMap/MapSelectedStationSnapshotController.swift"
checks = r'''
import Foundation

actor MapRideStationImportance {
    static let shared = MapRideStationImportance()
    struct Snapshot: Sendable {
        var lineCounts: [String: Int] = [:]
        var endpointPositions: [String: Int] = [:]
    }
    func snapshot(for country: String) async -> Snapshot { Snapshot() }
}

// Checked continuations deliberately ignore cancellation. Old requests are
// released after their replacement, selection clearing or map teardown.
actor Loads {
    var waiting: [String: [CheckedContinuation<MapRideStationImportance.Snapshot, Never>]] = [:]
    var counts: [String: Int] = [:]
    func load(_ country: String) async -> MapRideStationImportance.Snapshot {
        counts[country, default: 0] += 1
        return await withCheckedContinuation { waiting[country, default: []].append($0) }
    }
    func count(_ country: String) -> Int { counts[country, default: 0] }
    func finish(_ country: String, value: Int) {
        precondition(!(waiting[country] ?? []).isEmpty)
        waiting[country]!.removeFirst().resume(returning: .init(
            lineCounts: [country: value], endpointPositions: [country: value]))
    }
}

@MainActor final class Mount {
    var current = true
    var callbacks = 0
    func prepare(_ country: String?, on owner: MapSelectedStationSnapshotController) {
        owner.prepare(country: country, isCurrentMount: { [weak self] in
            self?.current == true
        }, didLoad: { [weak self] in self?.callbacks += 1 })
    }
}

@main struct Checks {
    @MainActor static func wait(_ condition: () async -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(5)
        while !(await condition()) {
            precondition(ContinuousClock.now < deadline, "Controlled lookup timed out")
            await Task.yield()
        }
    }
    @MainActor static func drain() async {
        for _ in 0..<100 { await Task.yield() }
    }
    @MainActor static func main() async {
        let loads = Loads()
        let owner = MapSelectedStationSnapshotController(load: { await loads.load($0) })
        let mount = Mount()
        mount.prepare("jp", on: owner)
        await wait { await loads.count("jp") == 1 }
        mount.prepare("jp", on: owner)
        await loads.finish("jp", value: 1)
        await wait { mount.callbacks == 1 }
        precondition(owner.snapshot(for: "jp")?.lineCounts["jp"] == 1)
        precondition(owner.snapshot(for: "jp")?.endpointPositions["jp"] == 1)
        mount.prepare("jp", on: owner)
        await drain()
        let jpLoads = await loads.count("jp")
        precondition(jpLoads == 1)
        precondition(mount.callbacks == 1)

        mount.prepare("tw", on: owner)
        await wait { await loads.count("tw") == 1 }
        mount.prepare("kr", on: owner)
        await wait { await loads.count("kr") == 1 }
        await loads.finish("kr", value: 2)
        await wait { mount.callbacks == 2 }
        await loads.finish("tw", value: 99)
        await drain()
        precondition(owner.snapshot(for: "tw") == nil && mount.callbacks == 2)

        // A cached-country pick preserves the already pending other country,
        // matching the original coordinator's early-return behavior.
        mount.prepare("tw", on: owner)
        await wait { await loads.count("tw") == 2 }
        mount.prepare("jp", on: owner)
        await loads.finish("tw", value: 3)
        await wait { mount.callbacks == 3 }
        precondition(owner.snapshot(for: "tw")?.lineCounts["tw"] == 3)

        mount.prepare("cn", on: owner)
        await wait { await loads.count("cn") == 1 }
        mount.prepare(nil, on: owner)
        await loads.finish("cn", value: 99)
        await drain()
        precondition(owner.snapshot(for: "cn") == nil && mount.callbacks == 3)

        mount.prepare("au", on: owner)
        await wait { await loads.count("au") == 1 }
        mount.current = false
        await loads.finish("au", value: 99)
        await drain()
        precondition(owner.snapshot(for: "au") == nil && mount.callbacks == 3)

        owner.tearDown()
        precondition(owner.snapshot(for: "jp") == nil && owner.snapshot(for: "tw") == nil)
        let replacement = Mount()
        replacement.prepare("jp", on: owner)
        await wait { await loads.count("jp") == 2 }
        owner.tearDown()
        replacement.prepare("jp", on: owner)
        await wait { await loads.count("jp") == 3 }
        await loads.finish("jp", value: 99) // Same-country stale ticket.
        await drain()
        precondition(owner.snapshot(for: "jp") == nil && replacement.callbacks == 0)
        await loads.finish("jp", value: 4)
        await wait { replacement.callbacks == 1 }
        precondition(owner.snapshot(for: "jp")?.lineCounts["jp"] == 4)
        owner.tearDown()
        print("PASS actual selected-station owner: cache/coalescing, country change, cleared selection, mount replacement, teardown, noncooperative stale completion and exactly-once callback")
    }
}
'''
with tempfile.TemporaryDirectory(prefix="jtm-selected-station-") as directory:
    folder = Path(directory)
    source = folder / "Checks.swift"
    binary = folder / "checks"
    source.write_text(checks)
    subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-parse-as-library",
                    "-module-cache-path", str(folder / "modules"), str(source),
                    str(owner), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=30)
