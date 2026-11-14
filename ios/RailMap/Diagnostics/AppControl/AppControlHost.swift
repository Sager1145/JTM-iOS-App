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
    /// Newest first; the developer panel lists these.
    private(set) var recentResults: [AppControlResult] = []

    @ObservationIgnored private var tail: Task<Void, Never>?
    @ObservationIgnored private var queued: Set<String> = []
    @ObservationIgnored private var poller: Task<Void, Never>?
    /// The `perf` command's own sampler; the developer panel keeps its own.
    @ObservationIgnored private let perfSampler = DevPerfSampler()
    @ObservationIgnored private let log = Logger(subsystem: RailSignpost.subsystem, category: "app-control")

    /// The store this launch uses (`DevStorage`): `nil` is the real store.
    nonisolated var isolatedStorageID: String? { DevStorage.launchID }

    nonisolated static var root: URL {
        URL.applicationSupportDirectory.appending(path: AppControl.rootFolderName, directoryHint: .isDirectory)
    }
    nonisolated private static func folder(_ name: String) -> URL {
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
        // Requests left from before this launch (a CLI that gave up, a locked
        // device) belong to a previous store and session: never run them now.
        let inbox = Self.folder(AppControl.inboxFolder)
        for name in (try? FileManager.default.contentsOfDirectory(atPath: inbox.path)) ?? [] {
            try? FileManager.default.removeItem(at: inbox.appending(path: name))
        }
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
        for name in names.sorted() where name.hasSuffix(".json") || name.hasSuffix(".req") {
            readInbox(id: String(name.prefix(upTo: name.lastIndex(of: ".")!)))
        }
    }

    private func readInbox(id: String) {
        guard AppControl.isValidRequestID(id) else { return }
        let inbox = Self.folder(AppControl.inboxFolder)
        // `.req` is what the CLI copies to a device, where the copy is not
        // atomic: a file that does not decode yet is left for the next scan.
        let candidates = [inbox.appending(path: "\(id).json"), inbox.appending(path: "\(id).req")]
        guard let file = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let data = try? Data(contentsOf: file) else {
            // The poller usually takes the file before its URL arrives: a
            // request already queued or answered is not missing.
            let answered = FileManager.default.fileExists(atPath: resultURL(id).path)
            if !queued.contains(id), !answered {
                write(failure(id: id, command: "", .notFound("inbox/\(id).json")))
            }
            return
        }
        let request: AppControlRequest
        do {
            request = try JSONDecoder().decode(AppControlRequest.self, from: data)
        } catch {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, Date().timeIntervalSince(modified) < 15 { return }  // still arriving
            try? FileManager.default.removeItem(at: file)
            write(failure(id: id, command: "", .invalidRequest(error.localizedDescription)))
            return
        }
        try? FileManager.default.removeItem(at: file)
        var adopted = request
        if adopted.id != id { adopted.id = id }
        enqueue(adopted)
    }

    /// The developer panel's entry point: the same queue, dispatcher and
    /// result file as a URL request, with the result handed back as well.
    func submit(_ command: String, args: [String: AppControlJSON] = [:],
                completion: (@MainActor (AppControlResult) -> Void)? = nil) {
        let id = "dev-\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(6))"
        enqueue(AppControlRequest(id: id, command: command, args: args), completion: completion)
    }

    /// A command the panel queued before relaunching onto a fresh store.
    func runPendingCommand() {
        guard let request = DevStorage.takePendingCommand() else { return }
        Task { [weak self] in
            for _ in 0..<600 {
                if self?.stores?.controller.isMapReady == true { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            self?.enqueue(request)
        }
    }

    private func enqueue(_ request: AppControlRequest, completion: (@MainActor (AppControlResult) -> Void)? = nil) {
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
            self.recentResults.insert(result, at: 0)
            if self.recentResults.count > 20 { self.recentResults.removeLast() }
            completion?(result)
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
        case .reloadAll(let wait, let timeoutMs, let force):
            return try await reloadAll(stores, wait: wait, timeoutMs: timeoutMs, force: force)
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
            // An editor already open on this id (a saved trip, or the new draft `addTrip` returned) is edited in place.
            if editor?.trainID != id || workspace?.editorState().open != true {
                let train = try trip(id, stores)
                timing = try await openEditor(JourneyEditorLaunch(train: train, isNew: false, originalID: train.id))
            }
            return try await apply(spec, openTimings: timing, stores)
        case .saveEditor(let confirmRemoval, let timeoutMs):
            return try await saveEditor(confirmRemoval: confirmRemoval, timeoutMs: timeoutMs, stores)
        case .cancelEditor:
            let workspace = try requireWorkspace()
            // The editor's own Cancel is disabled while a save is in flight.
            guard !workspace.editorState().saving else { throw AppControlError.failed("a save is in flight") }
            workspace.closeEditor()
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
        case .devtools(let action):
            return devtools(action)
        case .exportDiagnostics:
            var snapshot = state(stores, includeTrips: true).object ?? [:]
            snapshot["caches"] = await Task.detached(priority: .utility) { AppControlHost.caches() }.value
            return try await DevDiagnostics.export(state: .object(snapshot))
        case .clearRouteCaches:
            return await clearRouteCaches()
        case .memoryWarning:
            let before = Self.memory()
            NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: UIApplication.shared)
            try await Task.sleep(for: .seconds(1))
            return ["before": before, "after": Self.memory()]
        case .setLayer(let name, let on):
            let controller = stores.controller
            switch name {
            case "routes": controller.layers.routes = on
            case "stops": controller.layers.stops = on
            case "terminals": controller.layers.terminals = on
            case "pass": controller.layers.passThrough = on
            case "hsr": controller.layers.categories.hsr = on
            case "jr": controller.layers.categories.jr = on
            case "metro": controller.layers.categories.metro = on
            case "priv": controller.layers.categories.priv = on
            case "network": controller.showsNetwork = on
            default: throw AppControlError.invalidArgument("name", name)
            }
            return ["layer": .string(name), "on": .bool(on), "layers": Self.layers(controller)]
        case .camera(let action):
            return try await AppControlCameraRun(
                controller: stores.controller, renderStats: { [weak self] in self?.workspace?.renderStats() }
            ).run(action)
        case .perf(let action):
            return perf(action)
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

    private func reloadAll(_ stores: Stores, wait: Bool, timeoutMs: Int, force: Bool) async throws -> AppControlJSON {
        let routes = stores.riddenRoutes
        try await until("routes requested", timeoutMs: 30_000) { !routes.requestedIsEmpty || stores.itineraries.loaded?.trains.isEmpty == true }
        guard !routes.requestedIsEmpty else { throw AppControlError.unavailable("no trips to reload") }
        let started = ContinuousClock.now
        await routes.reloadAll(mode: force ? .rebuild : .repair)
        if wait {
            try await until("reloadAll", timeoutMs: timeoutMs) { !routes.isLoading }
        }
        return ["ms": .number(Self.ms(since: started)), "rides": .number(Double(routes.rides.count)),
                "settled": .bool(!routes.isLoading)]
    }

    private func openEditor(_ launch: JourneyEditorLaunch) async throws -> AppControlJSON {
        let workspace = try requireWorkspace()
        if workspace.editorState().open {
            guard !workspace.editorState().saving else { throw AppControlError.failed("a save is in flight") }
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
        let ticketFill = spec.ticket.map { editor.fillTicket($0) }
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
        if let ticketFill { result["ticket"] = ticketFill }
        if spec.save {
            do {
                result["save"] = try await saveEditor(confirmRemoval: spec.confirmRemoval, timeoutMs: 30_000, stores)
            } catch let error as AppControlError {
                // Keep the plan in the failure: it names the sections still to choose.
                let pending = editor.snapshot().sections.filter { $0.candidates.count > 1 && $0.chosen == nil }
                let hint = pending.map { "section \($0.index) \($0.from)→\($0.to): \($0.candidates.count) candidates" }
                var state = result
                if case .failedWithState(_, let saveState) = error { state["saveState"] = saveState }
                state["editor"] = editor.snapshot().json
                throw AppControlError.failedWithState(
                    "\(error.description)\(hint.isEmpty ? "" : "; choose with sectionChoices (editTrip id=\(editor.trainID)): " + hint.joined(separator: ", "))",
                    .object(state))
            }
        }
        return .object(result)
    }

    private func editorPlanned() -> Bool {
        guard let snapshot = editor?.snapshot() else { return false }
        // A planner error ends the search without a plan; report it rather than wait.
        let failed = snapshot.notices.contains { $0.hasPrefix("routeProofFailure") || $0 == "loadFailed" }
        return snapshot.ready && !snapshot.searching && (snapshot.planned || failed || !snapshot.routeEdited
            || snapshot.origin == nil || snapshot.destination == nil)
    }

    /// Every outcome that is not a save throws, so the CLI exits non-zero.
    private func saveEditor(confirmRemoval: Bool, timeoutMs: Int, _ stores: Stores) async throws -> AppControlJSON {
        let workspace = try requireWorkspace()
        let editor = try requireEditor()
        let before = editor.snapshot()
        guard before.canSave else {
            throw AppControlError.failedWithState("not saved: the editor cannot save yet (\(Self.describe(before)))", ["editor": before.json])
        }
        let started = ContinuousClock.now
        editor.commit(confirmRemoval)
        // `onSave` runs synchronously: the record id and the save attempt are set before the save is awaited.
        let state = workspace.editorState()
        let recordID = state.recordID
        if !state.saving, state.open {
            let after = self.editor?.snapshot()
            let state: AppControlJSON = [
                "editor": after?.json ?? before.json, "editorBefore": before.json,
                "autofillProbe": (self.editor ?? editor).autofillProbe(),
            ]
            if let pending = after?.removalPending {
                throw AppControlError.failedWithState("not saved: removes recorded stops \(pending); pass confirmRemoval=true", state)
            }
            if let issues = after?.saveIssues, !issues.isEmpty {
                throw AppControlError.failedWithState("not saved: validation \(issues)", state)
            }
            throw AppControlError.failedWithState(
                "not saved: the editor or the store refused the commit (\(after.map(Self.describe) ?? ""))", state)
        }
        try await until("save", timeoutMs: timeoutMs) {
            let state = workspace.editorState()
            return !state.open || state.saveFailure != nil
        }
        if let failure = workspace.editorState().saveFailure {
            throw AppControlError.failed("not saved: persistence failed: \(failure)")
        }
        return ["saved": true, "recordID": optional(recordID ?? stores.itineraries.selectedTrainID),
                "ms": .number(Self.ms(since: started)),
                "trips": .number(Double(stores.itineraries.loaded?.trains.count ?? 0))]
    }

    private static func describe(_ snapshot: AppControlEditorSnapshot) -> String {
        "planned=\(snapshot.planned) searching=\(snapshot.searching) pending=\(snapshot.pendingSections) notices=\(snapshot.notices)"
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

    /// Cache sizes walk directories; only the diagnostics export asks for them (off the main actor).
    func state(_ stores: Stores, includeTrips: Bool, includeCaches: Bool = false) -> AppControlJSON {
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
                "ridesInTabScope": workspace.map { .number(Double($0.scopedRideCount())) } ?? .null,
                "routeCacheHits": .number(Double(RiddenRouteStore.loadCounters.cacheHits)),
                "routeSolveAttemptsThisLaunch": .number(Double(RiddenRouteStore.loadCounters.solved)),
                "storedFailures": .number(Double(RiddenRouteStore.loadCounters.storedFailures)),
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
                "totalOverlays": .number(Double(MapRenderProbe.totalOverlays)),
                "rideOverlays": .number(Double(MapRenderProbe.rideOverlays)),
                "droppedFrames": .number(Double(MapRenderProbe.droppedFrames)),
                "geometryLevel": Self.geometryLevel(),
                "networkLines": .number(Double(stores.network.lines.count)),
                "rideStationDots": MapRenderProbe.rideStationDots.map { dots in
                    [
                        "drawn": .number(Double(dots.drawn)), "stations": .number(Double(dots.stations)),
                        "overlayStations": .number(Double(dots.overlayStations)),
                    ]
                } ?? .null,
                "matching": [
                    "runs": .number(Double(MapRenderProbe.matchingRuns)),
                    "skipped": .number(Double(MapRenderProbe.matchingSkipped)),
                    "deferred": .number(Double(MapRenderProbe.matchingDeferred)),
                ],
                "geometryWait": [
                    "count": .number(Double(MapRenderProbe.geometryWaits)),
                    "lastMs": .number(Double(MapRenderProbe.lastGeometryWaitMilliseconds)),
                    "maxMs": .number(Double(MapRenderProbe.maxGeometryWaitMilliseconds)),
                ],
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
            "window": Self.window(),
            "build": ["commit": optional(Self.buildCommit())],
            "storageSource": .string(DevStorage.launch.source.rawValue),
            "layers": Self.layers(stores.controller),
            // The in-process copy of RailSignpost intervals (SignpostRecorder);
            // active when launched with RAILMAP_SIGNPOST_RECORDER=1, while the
            // panel's Performance page is open, or after `devtools action=recorderOn`.
            "signposts": Self.signposts(),
            "devtools": ["visible": .bool(DevToolsController.shared.isVisible),
                         "expanded": .bool(DevToolsController.shared.isExpanded)],
        ]
        if includeCaches { result["caches"] = Self.caches() }
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

    private func devtools(_ action: String) -> AppControlJSON {
        let tools = DevToolsController.shared
        switch action {
        case "show": tools.setVisible(true)
        case "hide": tools.setVisible(false)
        case "expand": tools.setVisible(true); tools.setExpanded(true)
        case "collapse": tools.setExpanded(false)
        case "recorderOn": tools.setRecorder(true)
        case "recorderOff": tools.setRecorder(false)
        case "resetSignposts": SignpostRecorder.shared.reset()
        default: break
        }
        return ["visible": .bool(tools.isVisible), "expanded": .bool(tools.isExpanded),
                "recorder": .bool(SignpostRecorder.shared.isActive)]
    }

    /// `perf start|stop|read`: the panel's sampler (1 Hz FPS, hitches, footprint, CPU) without the panel.
    private func perf(_ action: String) -> AppControlJSON {
        switch action {
        case "start":
            perfSampler.stop()
            perfSampler.clear()
            perfSampler.start()
        case "stop": perfSampler.stop()
        default: break
        }
        let samples = perfSampler.samples
        func mean(_ values: [Double]) -> AppControlJSON {
            values.isEmpty ? .null : .number((values.reduce(0, +) / Double(values.count) * 10).rounded() / 10)
        }
        return [
            "running": .bool(perfSampler.isRunning), "count": .number(Double(samples.count)),
            "summary": [
                "fpsMean": mean(samples.map(\.fps)),
                "fpsMin": samples.map(\.fps).min().map { .number(($0 * 10).rounded() / 10) } ?? .null,
                "hitches": .number(Double(samples.reduce(0) { $0 + $1.hitches })),
                "longestFrameMs": samples.map(\.longestFrameMs).max().map { .number(($0 * 10).rounded() / 10) } ?? .null,
                "memoryMBMax": samples.map(\.memoryMB).max().map { .number(($0 * 10).rounded() / 10) } ?? .null,
                "cpuPercentMean": mean(samples.map(\.cpuPercent)),
            ],
            "samples": perfSampler.json,
        ]
    }

    /// The solved-route cache on disk plus the process memos a memory warning
    /// releases (the same calls `AppShell` makes then).
    func clearRouteCaches() async -> AppControlJSON {
        let routes = RiddenRouteStore.routeCacheFolder
        let bytes = await Task.detached(priority: .utility) { AppControlHost.directorySize(routes) }.value
        // The store's own discard (disk cache, solved-journey memo, solver memos), as Reload all uses.
        await RiddenRouteStore.discardSolvedRoutes()
        await EdgeIndexCache.shared.releaseForMemoryPressure()
        return ["removedDiskBytes": .number(Double(bytes)), "memory": Self.memory()]
    }

    static func layers(_ controller: RailMapController) -> AppControlJSON {
        let layers = controller.layers
        return [
            "routes": .bool(layers.routes), "stops": .bool(layers.stops), "terminals": .bool(layers.terminals),
            "pass": .bool(layers.passThrough), "hsr": .bool(layers.categories.hsr), "jr": .bool(layers.categories.jr),
            "metro": .bool(layers.categories.metro), "priv": .bool(layers.categories.priv),
            "network": .bool(controller.showsNetwork),
        ]
    }

    nonisolated static func signposts(recent: Int = 20) -> AppControlJSON {
        let recorder = SignpostRecorder.shared
        func round(_ value: Double) -> AppControlJSON { .number((value * 100).rounded() / 100) }
        return [
            "active": .bool(recorder.isActive),
            "byName": .array(recorder.aggregates().prefix(40).map { item in
                ["name": .string(item.name), "count": .number(Double(item.count)), "lastMs": round(item.lastMs),
                 "maxMs": round(item.maxMs), "meanMs": round(item.meanMs)]
            }),
            "recent": .array(recorder.recent(recent).map { entry in
                ["name": .string(entry.name), "ms": round(entry.milliseconds),
                 "at": .string(entry.endedAt.formatted(.iso8601))]
            }),
        ]
    }

    /// Bytes on disk under the app's own folders (enumerated, so call it off the hot path).
    nonisolated static func caches() -> AppControlJSON {
        let fm = FileManager.default
        var result: [String: AppControlJSON] = [:]
        // Unsandboxed Mac Catalyst: the user-domain Caches and Documents
        // folders are the whole `~/Library/Caches` and `~/Documents`, which
        // this walk never finishes. Use the app's own caches folder and skip
        // Documents (the isolated store lives under Application Support).
        #if targetEnvironment(macCatalyst)
        let cachesRoot = fm.urls(for: .cachesDirectory, in: .userDomainMask).first.map {
            $0.appending(path: Bundle.main.bundleIdentifier ?? "com.JRM.RailMap", directoryHint: .isDirectory)
        }
        let documentsRoot: URL? = nil
        #else
        let cachesRoot = fm.urls(for: .cachesDirectory, in: .userDomainMask).first
        let documentsRoot = fm.urls(for: .documentDirectory, in: .userDomainMask).first
        #endif
        let roots: [(String, URL?)] = [
            ("caches", cachesRoot),
            ("routeCache", RiddenRouteStore.routeCacheFolder),
            ("applicationSupport", URL.applicationSupportDirectory),
            ("documents", documentsRoot),
            ("tmp", URL.temporaryDirectory),
            ("appControl", root),
        ]
        for (name, url) in roots {
            guard let url else { continue }
            result[name + "MB"] = .number((Double(directorySize(url)) / 1_048_576 * 10).rounded() / 10)
        }
        return .object(result)
    }

    nonisolated static func directorySize(_ url: URL) -> Int64 {
        guard let walker = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in walker {
            let values = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true { total += Int64(values?.totalFileAllocatedSize ?? 0) }
        }
        return total
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

    nonisolated static func ms(since start: ContinuousClock.Instant) -> Double {
        let elapsed = ContinuousClock.now - start
        let ms = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
        return (ms * 10).rounded() / 10
    }

    static func keyWindow() -> UIWindow? {
        // The app's own window, never the developer ball's.
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows).filter { !($0 is DevToolsWindow) }
        return windows.first(where: \.isKeyWindow) ?? windows.first
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

    /// The commit stamped into Info.plist at build time (`JTMBuildCommit`, set by
    /// `app-control.py build`); nil for a build that was not stamped.
    nonisolated static func buildCommit() -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "JTMBuildCommit") as? String,
              !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
    }

    /// `map.geometryLevel`: the level on screen, the one the camera wants, the one being
    /// prepared, a landed one waiting to install, the camera zoom, and ms since the last install.
    static func geometryLevel() -> AppControlJSON {
        let levels = MapRenderProbe.geometryLevels
        func level(_ value: Int?) -> AppControlJSON { value.map { .number(Double($0)) } ?? .null }
        return [
            "installed": level(levels.installed), "wanted": level(levels.wanted),
            "preparing": level(levels.preparing), "pending": level(levels.pending),
            "cameraZoom": .number((levels.cameraZoom * 100).rounded() / 100),
            "sinceInstallMs": levels.installedAt.map { .number(Double((ContinuousClock.now - $0).milliseconds)) } ?? .null,
        ]
    }

    /// Scene and application activation, so a poll shows a window hidden mid-sweep
    /// (a hidden window stops MapKit drawing and changes every memory number).
    static func window() -> AppControlJSON {
        func name(_ state: UIScene.ActivationState) -> String {
            switch state {
            case .foregroundActive: return "foregroundActive"
            case .foregroundInactive: return "foregroundInactive"
            case .background: return "background"
            case .unattached: return "unattached"
            @unknown default: return "unknown"
            }
        }
        // `connectedScenes` is an unordered set and Catalyst can open several windows:
        // report every scene, and keep `sceneState` as the most foreground one.
        let states = UIApplication.shared.connectedScenes.map { name($0.activationState) }.sorted()
        let rank = ["foregroundActive", "foregroundInactive", "background", "unattached", "unknown"]
        let scene = rank.first(where: states.contains) ?? "none"
        let application: String
        switch UIApplication.shared.applicationState {
        case .active: application = "active"
        case .inactive: application = "inactive"
        case .background: application = "background"
        @unknown default: application = "unknown"
        }
        return ["sceneState": .string(scene), "scenes": .array(states.map { .string($0) }),
                "applicationState": .string(application)]
    }

    nonisolated static func memory() -> AppControlJSON {
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
                DevToolsController.shared.installIfEnabled()
                host.runPendingCommand()
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
