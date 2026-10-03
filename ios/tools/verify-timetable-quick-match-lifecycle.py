#!/usr/bin/env python3
"""Run the production timetable lookup controller with controlled suspension.

Usage: script <RailKit swift-test scratch>. The real controller and Observation
macro compile unchanged. Only the asynchronous local lookup and debounce are
replaced so canceled requests can complete after their replacements. RailCore
readiness and draft models are linked from the existing package build.
"""
from pathlib import Path
import os
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[2]
library = next(Path(sys.argv[1]).resolve().rglob('libRailCore.a'), None)
if library is None:
    raise SystemExit('Run the RailKit package build first; libRailCore.a is missing')

checks = r'''
import Foundation
import RailCore

// Region resolution itself is unchanged app policy; these scenarios use
// explicit region inputs so the collaborator has no station-data side effects.
enum Region: String, Sendable {
    case jp, tw
    var code: String { rawValue }
    static func resolved(_ train: Train) -> Region { Region(rawValue: train.region ?? "jp") ?? .jp }
}

enum LookupFailure: Error, LocalizedError {
    case named(String)
    var errorDescription: String? { switch self { case .named(let value): value } }
}

actor LookupProbe {
    typealias Output = Result<TimetableQuickMatchController.Matches, Error>
    private var pending: [String: CheckedContinuation<Output, Never>] = [:]
    private(set) var started: [String] = []
    private(set) var returned: Set<String> = []
    private(set) var regions: [String: String?] = [:]

    func lookup(_ input: TimetableQuickMatchController.Input) async -> Output {
        let key = input.serviceName
        started.append(key)
        regions[key] = input.train.region
        let result: Output = await withCheckedContinuation { pending[key] = $0 }
        returned.insert(key)
        return result
    }

    func finish(_ key: String, failure: String? = nil) {
        guard let continuation = pending.removeValue(forKey: key) else {
            preconditionFailure("lookup was never admitted: \(key)")
        }
        if let failure { continuation.resume(returning: .failure(LookupFailure.named(failure))) }
        else { continuation.resume(returning: .success(.init(trips: [], sourcesByTripID: [key: []]))) }
    }
}

actor DebounceProbe {
    private var pending: [Int: CheckedContinuation<Void, Never>] = [:]
    private(set) var started = 0

    func delay() async throws {
        let id = started
        started += 1
        await withCheckedContinuation { pending[id] = $0 }
        try Task.checkCancellation()
    }
    func release(_ id: Int) { pending.removeValue(forKey: id)?.resume() }
}

@main struct Checks {
    @MainActor static func input(_ name: String, region: String? = nil) -> TimetableQuickMatchController.Input {
        .init(train: Train(id: "draft", date: "2026-09-30", number: "1", origin: "A", destination: "B",
            stops: [Stop(name: "A", n02StationCode: "000001", departure: "08:00", stopType: "origin"),
                    Stop(name: "B", n02StationCode: "000002", arrival: "09:00", stopType: "destination")],
            region: region), serviceName: name)
    }

    static func started(_ name: String, on probe: LookupProbe) async {
        for _ in 0..<10_000 {
            if await probe.started.contains(name) { return }
            await Task.yield()
        }
        preconditionFailure("lookup did not start: \(name)")
    }

    static func returned(_ name: String, on probe: LookupProbe) async {
        for _ in 0..<10_000 {
            if await probe.returned.contains(name) {
                // Let the owner consume the resumed service result on MainActor.
                for _ in 0..<10 { await Task.yield() }
                return
            }
            await Task.yield()
        }
        preconditionFailure("lookup did not finish: \(name)")
    }

    @MainActor static func settled(_ owner: TimetableQuickMatchController) async {
        for _ in 0..<10_000 {
            if !owner.isSearching { return }
            await Task.yield()
        }
        preconditionFailure("lookup did not publish")
    }

    static func delayed(_ count: Int, on probe: DebounceProbe) async {
        for _ in 0..<10_000 {
            if await probe.started >= count { return }
            await Task.yield()
        }
        preconditionFailure("automatic debounce did not start")
    }

    @MainActor static func main() async {
        precondition(input("ready").isReady)
        precondition(!input("foreign", region: "tw").isReady)
        var missingTime = input("missing-time").train
        missingTime.stops[0].departure = nil
        precondition(!TimetableQuickMatchController.Input(train: missingTime, serviceName: "x").isReady)

        let probe = LookupProbe()
        let delay = DebounceProbe()
        let owner = TimetableQuickMatchController(lookup: { await probe.lookup($0) },
            debounce: { try await delay.delay() })
        let original = input("old"), replacement = input("new")
        owner.search(original)
        await started("old", on: probe)
        owner.search(replacement)
        await started("new", on: probe)
        await probe.finish("new")
        await settled(owner)
        precondition(owner.searched && owner.sourcesByTripID.keys.sorted() == ["new"])
        await probe.finish("old", failure: "stale failure")
        await returned("old", on: probe)
        precondition(owner.failure == nil && owner.sourcesByTripID.keys.sorted() == ["new"])
        let submittedRegion = await probe.regions["new"]
        precondition(submittedRegion == "jp", "legacy input was not normalized at submission")
        print("PASS replacement result wins when a canceled service returns late; submission normalizes region")

        owner.search(input("closed"))
        await started("closed", on: probe)
        owner.cancel()
        precondition(!owner.isSearching && !owner.searched && owner.sourcesByTripID.isEmpty)
        await probe.finish("closed", failure: "closed response")
        await returned("closed", on: probe)
        precondition(owner.failure == nil && !owner.searched)
        print("PASS disappearance cancels publication and clears staged choices/sources/errors")

        owner.updateInput(input("automatic-old"))
        await delayed(1, on: delay)
        owner.updateInput(input("automatic-new"))
        await delayed(2, on: delay)
        await delay.release(0)
        for _ in 0..<10 { await Task.yield() }
        let automaticStarts = await probe.started
        precondition(!automaticStarts.contains("automatic-old"))
        await delay.release(1)
        await started("automatic-new", on: probe)
        await probe.finish("automatic-new", failure: "database unavailable")
        await settled(owner)
        precondition(owner.failure == "database unavailable" && owner.searched && !owner.isSearching)
        print("PASS changed input cancels pending debounce; live lookup failure reaches the UI")

        owner.updateInput(input("manual-auto"))
        await delayed(3, on: delay)
        owner.search(input("manual"))
        await started("manual", on: probe)
        await probe.finish("manual")
        await settled(owner)
        owner.didSelectMatch()
        precondition(!owner.searched && owner.matches.isEmpty)
        precondition(owner.sourcesByTripID.keys.sorted() == ["manual"], "selection clearing semantics changed")
        await delay.release(2)
        await started("manual-auto", on: probe)
        await probe.finish("manual-auto")
        await settled(owner)
        precondition(owner.sourcesByTripID.keys.sorted() == ["manual-auto"])
        print("PASS manual search, selection clearing and independently pending automatic lookup keep their lifetimes")

        owner.updateInput(input("not-ready", region: "tw"))
        precondition(!owner.isSearching && !owner.searched && owner.sourcesByTripID.isEmpty)
        owner.search(input("blocked", region: "tw"))
        for _ in 0..<10 { await Task.yield() }
        let blockedStarts = await probe.started
        precondition(!blockedStarts.contains("blocked"))
        owner.cancel()
        print("PASS unsupported input clears previous results and cannot submit a lookup")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='jtm-timetable-lifecycle-') as temporary:
    folder = Path(temporary)
    source = folder / 'Checks.swift'
    source.write_text(checks)
    executable = folder / 'checks'
    environment = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(folder / 'ModuleCache'))
    subprocess.run(['xcrun', 'swiftc', '-disable-sandbox', '-swift-version', '6', '-parse-as-library',
                    '-module-cache-path', str(folder / 'ModuleCache'), '-I', str(library.parent),
                    str(root / 'ios/RailMap/TimetableQuickMatchController.swift'), str(source),
                    str(library), '-o', str(executable)], check=True, env=environment)
    subprocess.run([str(executable)], check=True, timeout=30)
