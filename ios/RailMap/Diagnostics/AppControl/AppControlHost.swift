#if DEBUG
import Darwin
import RailCore
import RailPresentation
import SwiftUI
import UIKit
import os

/// The DEBUG app's end of the test control channel (see `AppControlProtocol`
/// and `.claude/skills/app-control/SKILL.md`).
///
/// Transport is files in the app's own container plus a URL to wake it:
/// no socket, nothing reachable from another machine. Requests arrive as
/// `railmap-test://run?json=…` / `?request=<id>` (Debug-only URL scheme), or
/// as `inbox/<id>.json` picked up by a poller that runs only when the app was
/// launched with `RAILMAP_APP_CONTROL=1`. Every result is written to
/// `results/result-<id>.json`, first as `running`, then final.
///
/// Commands run one at a time on the main actor, through the stores and the
/// handles the workspace and the editor register — never a parallel path.
@MainActor @Observable
final class AppControlHost: AppControlDriver {
    static let shared = AppControlHost()

    struct Stores {
        var network: RailNetworkStore
        var itineraries: ItineraryStore
        var library: RideLibrary
        var riddenRoutes: RiddenRouteStore
        var controller: RailMapController
        var tripHide: TripHideFilter
        var selection: Binding<PrimaryTab>
    }

    @ObservationIgnored var stores: Stores?
    @ObservationIgnored var workspace: AppControlWorkspaceHandle?
    @ObservationIgnored private(set) var editor: AppControlEditorHandle?
    /// `"<id>:<status>"` of the last finished request, for the UI smoke test.
    private(set) var lastResultSummary: String?

    @ObservationIgnored private var tail: Task<Void, Never>?
    @ObservationIgnored private var queued: Set<String> = []
    @ObservationIgnored private var poller: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: RailSignpost.subsystem, category: "app-control")

    nonisolated var isolatedStorageID: String? {
        guard let value = UITestLaunchConfiguration.current[.storageId], UUID(uuidString: value) != nil
        else { return nil }
        return value
    }

    static var root: URL {
        URL.applicationSupportDirectory.appending(path: AppControl.rootFolderName, directoryHint: .isDirectory)
    }
    private static func folder(_ name: String) -> URL {
        let url = root.appending(path: name, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: registration

    func register(editor handle: AppControlEditorHandle, token: UUID) {
        var handle = handle
        handle.token = token
        editor = handle
    }
    func unregister(editor token: UUID) {
        if editor?.token == token { editor = nil }
    }

    func startPollerIfRequested() {
        guard poller == nil,
              ProcessInfo.processInfo.environment[AppControl.pollEnvironmentKey] == "1" else { return }
        writeReadyMarker()
        poller = Task { [weak self] in
            while !Task.isCancelled {
                self?.scanInbox()
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    /// `ready.json`: lets the CLI see the app is up, which store it is on and where its root is.
    private func writeReadyMarker() {
        let marker: AppControlJSON = [
            "processID": .number(Double(ProcessInfo.processInfo.processIdentifier)),
            "storageID": isolatedStorageID.map { .string($0) } ?? .null,
            "root": .string(Self.root.path),
            "at": .string(Date().formatted(.iso8601)),
        ]
        if let data = try? JSONEncoder().encode(marker) {
            try? data.write(to: Self.folder("").appending(path: "ready.json"), options: .atomic)
        }
    }

    // MARK: intake

    func handle(url: URL) {
        guard url.scheme == AppControl.scheme else { return }
        writeReadyMarker()
        do {
            switch try AppControlURL.parse(url) {
            case .inline(let request): enqueue(request)
            case .file(let id): readInbox(id: id)
            }
        } catch {
            log.error("app-control URL refused: \(String(describing: error), privacy: .public)")
            let rejected = AppControlResult(
                id: "invalid-url", command: "", status: .rejected, error: String(describing: error),
                startedAt: Date().formatted(.iso8601), finishedAt: Date().formatted(.iso8601), elapsedMs: 0,
                storageID: isolatedStorageID, processID: ProcessInfo.processInfo.processIdentifier, data: nil)
            write(rejected)
        }
    }

    private func scanInbox() {
        let inbox = Self.folder(AppControl.inboxFolder)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: inbox.path) else { return }
        for name in names.sorted() where name.hasSuffix(".json") {
            readInbox(id: String(name.dropLast(5)))
        }
    }

    private func readInbox(id: String) {
        guard AppControl.isValidRequestID(id) else { return }
        let file = Self.folder(AppControl.inboxFolder).appending(path: "\(id).json")
        guard let data = try? Data(contentsOf: file) else {
            if !queued.contains(id) {
                write(failure(id: id, command: "", .notFound("inbox/\(id).json")))
            }
            return
        }
        try? FileManager.default.removeItem(at: file)
        do {
            var request = try JSONDecoder().decode(AppControlRequest.self, from: data)
            if request.id != id { request.id = id }
            enqueue(request)
        } catch {
            write(failure(id: id, command: "", .invalidRequest(error.localizedDescription)))
        }
    }

    private func enqueue(_ request: AppControlRequest) {
        guard AppControl.isValidRequestID(request.id), !queued.contains(request.id) else { return }
        // A request ID is run once: a re-sent URL for a finished request is ignored.
        if let data = try? Data(contentsOf: resultURL(request.id)),
           let previous = try? JSONDecoder().decode(AppControlResult.self, from: data),
           previous.status != .running { return }
        queued.insert(request.id)
        var pending = AppControlResult(
            id: request.id, command: request.command, status: .running, error: nil,
            startedAt: Date().formatted(.iso8601), finishedAt: nil, elapsedMs: nil,
            storageID: isolatedStorageID, processID: ProcessInfo.processInfo.processIdentifier, data: nil)
        pending.data = ["queued": true]
        write(pending)
        let previous = tail
        tail = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            let result = await AppControlDispatcher.run(request, driver: self)
            self.write(result)
            self.queued.remove(request.id)
            self.lastResultSummary = "\(result.id):\(result.status.rawValue)"
            self.log.notice("app-control \(result.command, privacy: .public) \(result.status.rawValue, privacy: .public) ms=\(result.elapsedMs ?? -1, privacy: .public)")
        }
    }

    private func failure(id: String, command: String, _ error: AppControlError) -> AppControlResult {
        let now = Date().formatted(.iso8601)
        return AppControlResult(
            id: id, command: command, status: error.status, error: error.description, startedAt: now,
            finishedAt: now, elapsedMs: 0, storageID: isolatedStorageID,
            processID: ProcessInfo.processInfo.processIdentifier, data: nil)
    }

    private func resultURL(_ id: String) -> URL {
        Self.folder(AppControl.resultsFolder).appending(path: AppControl.resultFileName(id))
    }

    private func write(_ result: AppControlResult) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(result) else { return }
        try? data.write(to: resultURL(result.id), options: .atomic)
    }

    // MARK: driver

    func perform(_ command: AppControlCommand, requestID: String) async throws -> AppControlJSON {
        guard let stores else { throw AppControlError.unavailable("app shell not mounted") }
        switch command {
        case .useStorage(let id):
            return ["storageID": .string(id), "root": .string(Self.root.path)]
        case .state(let includeTrips):
            return state(stores, includeTrips: includeTrips)
        case .loadSamples(let names):
            return try await loadSamples(names, stores)
        case .reloadAll(let wait, let timeoutMs):
            return try await reloadAll(stores, wait: wait, timeoutMs: timeoutMs)
        case .selectTrip(let id):
            let workspace = try requireWorkspace()
            let train = try trip(id, stores)
            workspace.selectTrip(train)
            return ["selectedTrip": optional(stores.itineraries.selectedTrainID), "sheet": optional(workspace.sheetID())]
        case .focusTrip(let id):
            let workspace = try requireWorkspace()
            _ = try trip(id, stores)
            workspace.focusTrip(id)
            return ["focused": .string(id)]
        case .openEditor(let id):
            let train = try trip(id, stores)
            let timing = try await openEditor(JourneyEditorLaunch(train: train, isNew: false, originalID: train.id))
            return ["editor": try requireEditor().snapshot().json, "timings": timing]
        case .addTrip(let spec):
            let workspace = try requireWorkspace()
            guard let region = Region(rawValue: spec.region ?? Region.jp.rawValue), region.isEnabled else {
                throw AppControlError.invalidArgument("region", spec.region ?? "")
            }
            let timing = try await openEditor(JourneyEditorLaunch(
                train: workspace.newTripScaffold(region), isNew: true, originalID: nil))
            return try await apply(spec, openTimings: timing, stores)
        case .editTrip(let id, let spec):
            var timing: AppControlJSON = ["openMs": 0]
            if editor?.trainID != id || editor?.isNew == true || workspace?.editorState().open != true {
                let train = try trip(id, stores)
                timing = try await openEditor(JourneyEditorLaunch(train: train, isNew: false, originalID: train.id))
            }
            return try await apply(spec, openTimings: timing, stores)
        case .saveEditor(let confirmRemoval, let timeoutMs):
            return try await saveEditor(confirmRemoval: confirmRemoval, timeoutMs: timeoutMs, stores)
        case .cancelEditor:
            try requireWorkspace().closeEditor()
            try await until("editorClosed", timeoutMs: 5000) { [weak self] in self?.workspace?.editorState().open != true }
            return ["editorOpen": false]
        case .deleteTrip(let id):
            _ = try trip(id, stores)
            let commit = stores.itineraries.delete(id)
            guard commit.outcome, let save = commit.save else { throw AppControlError.failed("delete refused") }
            let saved = await save.value
            guard saved.saved else { throw AppControlError.failed("delete save failed: \(saved.error ?? "")") }
            return ["deleted": .string(id), "trips": .number(Double(stores.itineraries.loaded?.trains.count ?? 0))]
        case .openStats:
            stores.selection.wrappedValue = .stats
            return ["tab": .string(workspace?.tab() ?? "stats")]
        case .setHideFilter(let filter):
            return try setHideFilter(filter, stores)
        case .screenshot(let name):
            return try screenshot(name: name ?? requestID)
        case .wait(let condition, let timeoutMs):
            let started = ContinuousClock.now
            try await until(condition, timeoutMs: timeoutMs) { [weak self] in
                guard let self, let stores = self.stores else { return false }
                return self.holds(condition, stores)
            }
            return ["condition": .string(condition), "waitedMs": .number(Self.ms(since: started))]
        }
    }

    // MARK: commands

    private func loadSamples(_ names: [String], _ stores: Stores) async throws -> AppControlJSON {
        try await until("store loaded", timeoutMs: 30_000) { stores.itineraries.loaded != nil }
        var loaded: [String: AppControlJSON] = [:]
        for name in names {
            guard let sample = RideLibrary.Sample.all.first(where: { $0.resource == name }) else {
                throw AppControlError.invalidArgument(
                    "samples", "\(name); known: \(RideLibrary.Sample.all.map(\.resource).joined(separator: ","))")
            }
            let started = ContinuousClock.now
            // The same merge the Settings sample buttons and the UI-test hook use.
            let incoming = try await stores.library.sample(sample.resource)
            let commit = try await stores.itineraries.merge(incoming, into: stores.library)
            let saved = await commit.save?.value
            guard case .committed(let ids) = commit.outcome else { throw AppControlError.failed("merge refused for \(name)") }
            if let saved, !saved.saved { throw AppControlError.failed("save failed for \(name): \(saved.error ?? "")") }
            loaded[name] = ["merged": .number(Double(ids.count)), "ms": .number(Self.ms(since: started))]
        }
        return ["samples": .object(loaded), "trips": .number(Double(stores.itineraries.loaded?.trains.count ?? 0))]
    }

    private func reloadAll(_ stores: Stores, wait: Bool, timeoutMs: Int) async throws -> AppControlJSON {
        let routes = stores.riddenRoutes
        try await until("routes requested", timeoutMs: 30_000) { !routes.requestedIsEmpty || stores.itineraries.loaded?.trains.isEmpty == true }
        guard !routes.requestedIsEmpty else { throw AppControlError.unavailable("no trips to reload") }
        let started = ContinuousClock.now
        await routes.reloadAll()
        if wait {
            try await until("reloadAll", timeoutMs: timeoutMs) { !routes.isLoading }
        }
        return ["ms": .number(Self.ms(since: started)), "rides": .number(Double(routes.rides.count)),
                "settled": .bool(!routes.isLoading)]
    }

    private func openEditor(_ launch: JourneyEditorLaunch) async throws -> AppControlJSON {
        let workspace = try requireWorkspace()
        if workspace.editorState().open {
            workspace.closeEditor()
            try await until("previous editor closed", timeoutMs: 5000) { [weak self] in self?.editor == nil }
        }
        let started = ContinuousClock.now
        workspace.presentEditor(launch)
        try await until("editor mounted", timeoutMs: 10_000) { [weak self] in self?.editor?.trainID == launch.train.id }
        let mounted = Self.ms(since: started)
        try await until("editor catalog", timeoutMs: 60_000) { [weak self] in self?.editor?.isReady() == true }
        let editor = try requireEditor()
        if editor.loadFailed() { throw AppControlError.failed("editor catalog failed to load") }
        return ["mountMs": .number(mounted), "readyMs": .number(Self.ms(since: started))]
    }

    private func apply(_ spec: AppControlTripSpec, openTimings: AppControlJSON, _ stores: Stores) async throws -> AppControlJSON {
        let editor = try requireEditor()
        func resolve(_ query: String, _ key: String) throws -> CatalogStation {
            let found = editor.station(query)
            guard let first = found.first else { throw AppControlError.notFound("\(key) station \(query) in \(editor.region())") }
            return first
        }
        let started = ContinuousClock.now
        let from = try spec.from.map { try resolve($0, "from") }
        let to = try spec.to.map { try resolve($0, "to") }
        let vias = try spec.via?.map { try resolve($0, "via") }
        if let day = spec.date { editor.setDay(day) }
        if from != nil || to != nil || vias != nil { editor.setRoute(from, to, vias) }
        // Let SwiftUI publish the new identity before waiting for the plan.
        try await Task.sleep(for: .milliseconds(50))
        try await until("editorPlanned", timeoutMs: spec.timeoutMs) { [weak self] in self?.editorPlanned() == true }
        let planMs = Self.ms(since: started)
        var choiceErrors: [AppControlJSON] = []
        for (index, id) in spec.sectionChoices.sorted(by: { $0.key < $1.key }) {
            if !editor.choose(id, index) { choiceErrors.append(.string("section \(index): \(id) not offered")) }
        }
        if !spec.sectionChoices.isEmpty {
            try await Task.sleep(for: .milliseconds(50))
            try await until("editorPlanned", timeoutMs: spec.timeoutMs) { [weak self] in self?.editorPlanned() == true }
        }
        var result: [String: AppControlJSON] = [
            "editor": editor.snapshot().json,
            "timings": .object((openTimings.object ?? [:]).merging(
                ["planMs": .number(planMs), "applyMs": .number(Self.ms(since: started))]) { _, new in new }),
        ]
        if !choiceErrors.isEmpty { result["choiceErrors"] = .array(choiceErrors) }
        if spec.save {
            result["save"] = try await saveEditor(confirmRemoval: spec.confirmRemoval, timeoutMs: 30_000, stores)
        }
        return .object(result)
    }

    private func editorPlanned() -> Bool {
        guard let snapshot = editor?.snapshot() else { return false }
        return snapshot.ready && !snapshot.searching && (snapshot.planned || !snapshot.routeEdited
            || snapshot.origin == nil || snapshot.destination == nil)
    }

    private func saveEditor(confirmRemoval: Bool, timeoutMs: Int, _ stores: Stores) async throws -> AppControlJSON {
        let workspace = try requireWorkspace()
        let editor = try requireEditor()
        let before = editor.snapshot()
        guard before.canSave else {
            return ["saved": false, "reason": "editor cannot save yet", "editor": before.json]
        }
        let started = ContinuousClock.now
        editor.commit(confirmRemoval)
        // `onSave` runs synchronously: the record id is set before the save is awaited.
        let recordID = workspace.editorState().recordID
        let after = self.editor?.snapshot()
        if let after, let pending = after.removalPending {
            return ["saved": false, "reason": "removal needs confirmRemoval", "removalPending": .array(pending.map { .string($0) })]
        }
        if let after, !after.saveIssues.isEmpty, !workspace.editorState().saving {
            return ["saved": false, "reason": "validation", "saveIssues": .array(after.saveIssues.map { .string($0) })]
        }
        try await until("save", timeoutMs: timeoutMs) {
            let state = workspace.editorState()
            return !state.open || state.saveFailure != nil
        }
        if let failure = workspace.editorState().saveFailure {
            return ["saved": false, "reason": "persistence", "error": .string(failure)]
        }
        return ["saved": true, "recordID": optional(recordID ?? stores.itineraries.selectedTrainID),
                "ms": .number(Self.ms(since: started)),
                "trips": .number(Double(stores.itineraries.loaded?.trains.count ?? 0))]
    }

    private func setHideFilter(_ filter: AppControlHideFilter, _ stores: Stores) throws -> AppControlJSON {
        let hide = stores.tripHide
        let regions = try filter.regions.map { code -> Region in
            guard let region = Region(rawValue: code) else { throw AppControlError.invalidArgument("regions", code) }
            return region
        }
        if filter.mode == .set || filter.mode == .showAll { hide.showAll() }
        let hidden = filter.mode != .remove
        if filter.mode != .showAll {
            for region in regions { hide.setRegion(region, hidden: hidden) }
            for year in filter.years { hide.setYear(year, hidden: hidden) }
            for month in filter.months { hide.setMonth(month, hidden: hidden) }
        }
        return [
            "hiddenRegions": .array(hide.hiddenRegions.sorted().map { .string($0) }),
            "hiddenYears": .array(hide.hiddenYears.sorted().map { .number(Double($0)) }),
            "hiddenMonths": .array(hide.hiddenMonths.sorted().map { .string($0) }),
        ]
    }

    private func screenshot(name: String) throws -> AppControlJSON {
        guard let window = Self.keyWindow() else { throw AppControlError.unavailable("no key window") }
        let started = ContinuousClock.now
        let format = UIGraphicsImageRendererFormat(for: window.traitCollection)
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        guard let data = image.pngData() else { throw AppControlError.failed("PNG encoding failed") }
        let file = Self.folder(AppControl.screenshotsFolder).appending(path: "\(name).png")
        try data.write(to: file, options: .atomic)
        return [
            "file": .string(file.path),
            "containerPath": .string("Library/Application Support/\(AppControl.rootFolderName)/\(AppControl.screenshotsFolder)/\(name).png"),
            "points": ["width": .number(window.bounds.width), "height": .number(window.bounds.height)],
            "scale": .number(format.scale), "bytes": .number(Double(data.count)), "ms": .number(Self.ms(since: started)),
        ]
    }

    // MARK: state

    private func state(_ stores: Stores, includeTrips: Bool) -> AppControlJSON {
        let routes = stores.riddenRoutes
        let phase: String = switch routes.state {
        case .idle: "idle"
        case .loading: "loading"
        case .loaded: "loaded"
        case .failed: "failed"
        }
        let trains = stores.itineraries.loaded?.trains
        var result: [String: AppControlJSON] = [
            "storageID": optional(isolatedStorageID),
            "root": .string(Self.root.path),
            "processID": .number(Double(ProcessInfo.processInfo.processIdentifier)),
            "inventory": [
                "storeLoaded": .bool(trains != nil),
                "registered": .number(Double(trains?.count ?? 0)),
                "phase": .string(phase),
                "rides": .number(Double(routes.rides.count)),
                "drawable": workspace.map { .number(Double($0.drawableRideCount())) } ?? .null,
                "reloadProgress": routes.reloadProgress.map { ["done": .number(Double($0.done)), "total": .number(Double($0.total))] } ?? .null,
            ],
            "map": [
                "ready": .bool(stores.controller.isMapReady),
                "renderStatus": optional(Self.renderStatusText()),
                "render": workspace?.renderStats().map { stats in
                    [
                        "zoom": .number((stats.zoom * 100).rounded() / 100), "visibleLines": .number(Double(stats.visibleLines)),
                        "overlays": .number(Double(stats.overlays)), "vertices": .number(Double(stats.vertices)),
                        "buildMs": .number(Double(stats.buildMilliseconds)), "culledOffScreen": .number(Double(stats.culledOffScreen)),
                    ]
                } ?? .null,
                "networkLines": .number(Double(stores.network.lines.count)),
            ],
            "selectedTrip": optional(stores.itineraries.selectedTrainID),
            "sheet": optional(workspace?.sheetID()),
            "stage": optional(workspace?.stage()),
            "tab": optional(workspace?.tab()),
            "hidden": [
                "regions": .array(stores.tripHide.hiddenRegions.sorted().map { .string($0) }),
                "years": .array(stores.tripHide.hiddenYears.sorted().map { .number(Double($0)) }),
                "months": .array(stores.tripHide.hiddenMonths.sorted().map { .string($0) }),
            ],
            "memory": Self.memory(),
            // RailSignpost intervals go to Instruments only; nothing records them in-process.
            "signposts": .null,
        ]
        if let state = workspace?.editorState() {
            var editorJSON: [String: AppControlJSON] = [
                "open": .bool(state.open), "isNew": .bool(state.isNew), "trainID": optional(state.trainID),
                "saving": .bool(state.saving), "saveFailure": optional(state.saveFailure),
            ]
            if state.open, let editor { editorJSON["draft"] = editor.snapshot().json }
            result["editor"] = .object(editorJSON)
        }
        if includeTrips, let trains {
            result["trips"] = .array(trains.prefix(500).map { train in
                [
                    "id": .string(train.id), "number": .string(train.number),
                    "origin": .string(train.origin), "destination": .string(train.destination),
                    "date": optional(train.date), "region": optional(train.region),
                    "visible": .bool(train.visible != false), "stops": .number(Double(train.stops.count)),
                ]
            })
        }
        return .object(result)
    }

    private func holds(_ condition: String, _ stores: Stores) -> Bool {
        switch condition {
        case "mapReady": return stores.controller.isMapReady
        case "routesLoaded":
            guard let trains = stores.itineraries.loaded?.trains else { return false }
            if trains.isEmpty { return true }
            if case .loaded = stores.riddenRoutes.state { return !stores.riddenRoutes.isLoading }
            return false
        case "editorReady": return editor?.isReady() == true
        case "editorPlanned": return editorPlanned()
        case "editorClosed": return workspace?.editorState().open != true
        case "idle":
            return holds("mapReady", stores) && holds("routesLoaded", stores) && workspace?.editorState().saving != true
        default:
            if condition.hasPrefix("trips>="), let count = Int(condition.dropFirst("trips>=".count)) {
                return (stores.itineraries.loaded?.trains.count ?? -1) >= count
            }
            return false
        }
    }

    // MARK: helpers

    private func requireWorkspace() throws -> AppControlWorkspaceHandle {
        guard let workspace else { throw AppControlError.unavailable("workspace not mounted") }
        return workspace
    }

    private func requireEditor() throws -> AppControlEditorHandle {
        guard let editor else { throw AppControlError.unavailable("no journey editor open") }
        return editor
    }

    private func trip(_ id: String, _ stores: Stores) throws -> Train {
        guard let train = stores.itineraries.loaded?.trains.first(where: { $0.id == id }) else {
            throw AppControlError.notFound("trip \(id)")
        }
        return train
    }

    private func optional(_ value: String?) -> AppControlJSON { value.map { .string($0) } ?? .null }

    private func until(_ what: String, timeoutMs: Int, _ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + .milliseconds(timeoutMs)
        while !condition() {
            guard ContinuousClock.now < deadline else { throw AppControlError.timeout(what) }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    static func ms(since start: ContinuousClock.Instant) -> Double {
        let elapsed = ContinuousClock.now - start
        let ms = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
        return (ms * 10).rounded() / 10
    }

    static func keyWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first
    }

    /// The map's render-status label (`railMapRenderStatus`), read from the view tree.
    static func renderStatusText() -> String? {
        func find(_ view: UIView) -> UILabel? {
            if view.accessibilityIdentifier == "railMapRenderStatus", let label = view as? UILabel { return label }
            for child in view.subviews { if let found = find(child) { return found } }
            return nil
        }
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        for window in windows { if let label = find(window) { return label.text } }
        return nil
    }

    static func memory() -> AppControlJSON {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return .null }
        func mb(_ bytes: UInt64) -> AppControlJSON { .number((Double(bytes) / 1_048_576 * 10).rounded() / 10) }
        return ["footprintMB": mb(info.phys_footprint), "residentMB": mb(UInt64(info.resident_size)),
                "peakFootprintMB": mb(UInt64(info.ledger_phys_footprint_peak))]
    }
}

/// The single registration point in `AppShell`: hands the stores over,
/// receives `railmap-test://` URLs, starts the opt-in inbox poller, and
/// exposes the last result for the UI smoke test.
struct AppControlRegistration: ViewModifier {
    let stores: AppControlHost.Stores
    @State private var host = AppControlHost.shared

    func body(content: Content) -> some View {
        content
            .onAppear {
                host.stores = stores
                host.startPollerIfRequested()
            }
            .onOpenURL { url in
                host.stores = host.stores ?? stores
                host.handle(url: url)
            }
            .overlay(alignment: .topTrailing) {
                if let summary = host.lastResultSummary {
                    Text(summary)
                        .font(.caption2)
                        .foregroundStyle(.clear)
                        .frame(width: 1, height: 1)
                        .clipped()
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("appControlLastResult")
                        .accessibilityLabel(summary)
                }
            }
    }
}
#endif
