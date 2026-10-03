#!/usr/bin/env python3
"""Exercise actual share acceptance across suspended and cancelled work."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HARNESS = r'''
import Foundation
@MainActor final class Gate {
    var entered = false
    var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        entered = true
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { continuation?.resume(); continuation = nil }
}
@main struct Checks {
    @MainActor static func main() async {
        let owner = ShareRequestController<String>()
        owner.begin("map")
        let first = owner.request!
        owner.begin("poster")
        precondition(owner.request == first, "only one active share")
        let result: String? = await owner.perform(first, isCurrent: { true }) { "file" }
        precondition(result == "file" && owner.request == nil && owner.isLatest(first))
        print("PASS successful share and deferred receipt")

        owner.begin("map")
        let staleScope = owner.request!
        let scopeGate = Gate()
        var scope = 1
        let task = Task { await owner.perform(staleScope, isCurrent: { scope == 1 }) {
            await scopeGate.wait(); return "stale-file"
        } }
        while !scopeGate.entered { await Task.yield() }
        scope = 2
        scopeGate.release()
        let obsolete = await task.value
        precondition(obsolete == nil && owner.request == nil)
        print("PASS scope changes during rendering reject file")

        owner.begin("map")
        let old = owner.request!
        let gate = Gate()
        let cancelled = Task { await owner.perform(old, isCurrent: { true }) {
            await gate.wait(); return "ignored-cancellation"
        } }
        while !gate.entered { await Task.yield() }
        cancelled.cancel()
        owner.cancel()
        owner.begin("poster")
        let newer = owner.request!
        gate.release()
        let late = await cancelled.value
        precondition(late == nil && owner.request == newer && !owner.isLatest(old))
        let newFile: String? = await owner.perform(newer, isCurrent: { true }) { "new-file" }
        precondition(newFile == "new-file" && owner.request == nil)
        print("PASS late cancellation cannot clear or present newer share")

        owner.begin("map")
        let invalid = owner.request!
        var called = false
        let noFile: String? = await owner.perform(invalid, isCurrent: { false }) {
            called = true; return "invalid"
        }
        precondition(noFile == nil && !called && owner.request == nil)
        owner.cancel()
        precondition(!owner.isLatest(newer), "deferred presentation invalidates after cancel")
        print("PASS invalid scope releases busy state without rendering")
    }
}
'''

with tempfile.TemporaryDirectory(prefix="jtm-share-request-") as temporary:
    folder = Path(temporary)
    checks = folder / "Checks.swift"
    checks.write_text(HARNESS)
    executable = folder / "checks"
    subprocess.run([
        "xcrun", "swiftc", "-swift-version", "6", "-parse-as-library",
        "-module-cache-path", str(folder / "modules"),
        str(ROOT / "ios/RailMap/ShareRequestController.swift"), str(checks),
        "-o", str(executable),
    ], check=True)
    subprocess.run([str(executable)], check=True, timeout=30)
