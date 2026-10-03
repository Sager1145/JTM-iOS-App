#!/usr/bin/env python3
"""Verify the production AI request lifetime with local suspended actions."""
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
        let request = JourneyCompletionRequest()
        let gate = Gate()
        var failures: [String] = []
        var accepted = 0
        let began = request.start({
            await gate.wait()
            try Task.checkCancellation()
            accepted += 1
        }, onFailure: { failures.append($0) })
        precondition(began && request.isWorking)
        while !gate.entered { await Task.yield() }
        precondition(!request.start({ accepted += 10 }, onFailure: { _ in }))
        request.cancel()
        precondition(request.isWorking, "cancel waits for suspended cleanup")
        precondition(!request.start({ accepted += 10 }, onFailure: { _ in }))
        gate.release()
        while request.isWorking { await Task.yield() }
        precondition(accepted == 0 && failures.isEmpty)
        print("PASS cancellation prevents publication and overlapping requests")

        request.start({ throw CocoaError(.fileReadUnknown) }, onFailure: { failures.append($0) })
        while request.isWorking { await Task.yield() }
        precondition(failures.count == 1)
        request.start({ accepted += 1 }, onFailure: { failures.append($0) })
        while request.isWorking { await Task.yield() }
        precondition(accepted == 1 && failures.count == 1)
        print("PASS errors publish once and a later request can succeed")

        let failingGate = Gate()
        request.start({
            await failingGate.wait()
            throw CocoaError(.fileReadUnknown)
        }, onFailure: { failures.append($0) })
        while !failingGate.entered { await Task.yield() }
        request.cancel()
        failingGate.release()
        while request.isWorking { await Task.yield() }
        precondition(failures.count == 1)
        print("PASS canceled requests do not publish late service failures")
    }
}
'''

with tempfile.TemporaryDirectory(prefix="jtm-completion-request-") as temporary:
    folder = Path(temporary)
    checks = folder / "Checks.swift"
    checks.write_text(HARNESS)
    executable = folder / "checks"
    subprocess.run([
        "xcrun", "swiftc", "-swift-version", "6", "-parse-as-library",
        "-module-cache-path", str(folder / "modules"),
        str(ROOT / "ios/RailMap/JourneyCompletionRequest.swift"), str(checks),
        "-o", str(executable),
    ], check=True)
    subprocess.run([str(executable)], check=True, timeout=30)
