#!/usr/bin/env python3
"""Compile the production station-picker search owner with controlled suspension.

Usage: script <RailKit swift-test scratch>. No simulator, catalog resource or
user data is read. The production filter runs against synthetic Core values;
request/debounce doubles allow canceled work to complete after replacements.
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

# The view still owns loading. Check that each suspended phase accepts only
# its current load before changing the view's rows, groups, or error state.
view = (root / 'ios/RailMap/RideEditorView.swift').read_text()
picker = view[view.index('private struct StationPickerView:'):view.index('private struct RetiredStationLabel:')]
load = picker[picker.index('.task(id: loadIdentity)'):picker.index('.onChange(of: query)')]
assert load.count('}.value') == 3
assert load.count('guard !Task.isCancelled, search.acceptsLoad(loadID) else { return }') == 4
assert 'search.install(rows: result.rows, retired: retired, loadID: loadID, query: query)' in load

checks = r'''
import Foundation
import RailCore

actor SearchProbe {
    private var pending: [String: CheckedContinuation<StationPickerSearchController.Result, Never>] = [:]
    private(set) var started: Set<String> = []
    private(set) var returned: Set<String> = []

    func search(_ input: StationPickerSearchController.Input) async -> StationPickerSearchController.Result {
        started.insert(input.needle)
        let result: StationPickerSearchController.Result = await withCheckedContinuation {
            pending[input.needle] = $0
        }
        returned.insert(input.needle)
        return result
    }

    func finish(_ needle: String, rows: [CatalogStationRow], retired: [RetiredStation] = []) {
        guard let continuation = pending.removeValue(forKey: needle) else { preconditionFailure("not pending") }
        continuation.resume(returning: .init(rows: rows, retired: retired))
    }
}

actor DebounceProbe {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var started = false
    func wait() async {
        started = true
        await withCheckedContinuation { continuation = $0 }
    }
    func finish() { continuation?.resume(); continuation = nil }
}

@main struct Checks {
    static func row(_ code: String, _ name: String, aliases: [String] = []) -> CatalogStationRow {
        .init(station: .init(key: .init(regionCode: "jp", sourceCode: code), name: name,
            aliases: aliases, longitude: 139, latitude: 35), subtitle: "subtitle")
    }

    static func retired() throws -> [RetiredStation] {
        let json = #"{"schema_version":"1","revision":"synthetic","sections":[],"retirements":[],"stations":[{"type":"Feature","properties":{"history_id":"history-code","station_name":"Old Harbor","line_name":"Other Line","operator":"Owner","valid_to":"2016-12-05"},"geometry":{"type":"Point","coordinates":[139,35]}}]}"#
        return RailHistoryStations.directory(try RailHistoryOverlay.decode(Data(json.utf8)))
    }

    @MainActor static func until(_ condition: @escaping @MainActor () async -> Bool) async {
        for _ in 0..<3000 {
            if await condition() { return }
            await Task.yield()
        }
        preconditionFailure("controlled operation did not settle")
    }

    @MainActor static func main() async throws {
        let a = row("code-1", "Alpha", aliases: ["Port"])
        let b = row("code-2", "Beta")
        let historic = try retired()
        precondition(historic.count == 1)
        for needle in ["alpha", "PORT", "code-1"] {
            let result = StationPickerSearchController.filter(.init(rows: [b, a], retired: historic, needle: needle))
            precondition(result.rows == [a])
        }
        precondition(StationPickerSearchController.filter(.init(rows: [b, a], retired: historic, needle: "code")).rows == [b, a])
        precondition(StationPickerSearchController.filter(.init(rows: [], retired: historic, needle: "harbor")).retired == historic)
        for needle in ["history-code", "Other Line"] {
            precondition(StationPickerSearchController.filter(.init(rows: [], retired: historic, needle: needle)).retired.isEmpty)
        }
        print("PASS production name/alias/code filters, retired name-only filter and input ordering")

        let probe = SearchProbe()
        let owner = StationPickerSearchController(search: { await probe.search($0) }, debounce: {})
        let initialLoad = owner.beginLoad()
        precondition(owner.install(rows: [b, a], retired: historic, loadID: initialLoad, query: "  \n"))
        precondition(owner.matches == [b, a] && owner.matchedRetired == historic)
        owner.apply(query: "first")
        await until { await probe.started.contains("first") }
        owner.apply(query: "second")
        await until { await probe.started.contains("second") }
        await probe.finish("second", rows: [b])
        await until { owner.matches == [b] }
        await probe.finish("first", rows: [a])
        await until { await probe.returned.contains("first") }
        for _ in 0..<20 { await Task.yield() }
        precondition(owner.matches == [b])
        print("PASS late replaced query cannot overwrite current matches")

        owner.apply(query: "clear")
        await until { await probe.started.contains("clear") }
        owner.apply(query: " \n ")
        precondition(owner.matches == [b, a] && owner.matchedRetired == historic)
        await probe.finish("clear", rows: [])
        await until { await probe.returned.contains("clear") }
        for _ in 0..<20 { await Task.yield() }
        precondition(owner.matches == [b, a])
        print("PASS empty query restores full snapshots and rejects late worker")

        owner.apply(query: "dismiss")
        await until { await probe.started.contains("dismiss") }
        owner.cancel()
        await probe.finish("dismiss", rows: [a])
        await until { await probe.returned.contains("dismiss") }
        for _ in 0..<20 { await Task.yield() }
        precondition(owner.matches == [b, a] && !owner.acceptsLoad(initialLoad))
        print("PASS dismissal cancels search and invalidates suspended catalog load")

        let oldLoad = owner.beginLoad()
        let newLoad = owner.beginLoad()
        precondition(!owner.install(rows: [a], retired: historic, loadID: oldLoad, query: ""))
        precondition(owner.install(rows: [b], retired: [], loadID: newLoad, query: ""))
        precondition(!owner.install(rows: [a], retired: historic, loadID: oldLoad, query: ""))
        precondition(owner.prepared == [b] && owner.retired.isEmpty && owner.matches == [b])
        print("PASS late prepared/retired snapshot cannot replace current load")

        let debounce = DebounceProbe()
        let waiting = StationPickerSearchController(search: { await probe.search($0) }, debounce: { await debounce.wait() })
        let waitingLoad = waiting.beginLoad()
        precondition(waiting.install(rows: [a], retired: [], loadID: waitingLoad, query: "debounced"))
        await until { await debounce.started }
        waiting.apply(query: "")
        await debounce.finish()
        for _ in 0..<30 { await Task.yield() }
        let starts = await probe.started
        precondition(!starts.contains("debounced") && waiting.matches == [a])
        print("PASS canceled debounce never submits a worker")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='jtm-station-picker-lifecycle-') as temporary:
    folder = Path(temporary)
    source = folder / 'Checks.swift'
    source.write_text(checks)
    executable = folder / 'checks'
    environment = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(folder / 'ModuleCache'))
    subprocess.run(['xcrun', 'swiftc', '-disable-sandbox', '-swift-version', '6', '-parse-as-library',
                    '-module-cache-path', str(folder / 'ModuleCache'), '-I', str(library.parent),
                    str(root / 'ios/RailMap/StationPickerSearchController.swift'), str(source),
                    str(library), '-o', str(executable)], check=True, env=environment)
    subprocess.run([str(executable)], check=True, timeout=30)
print('PASS picker guards every catalog/preparation/retired await and canceled errors')
