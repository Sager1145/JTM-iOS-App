#!/usr/bin/env python3
"""Run production share render/export lifecycle with tiny host graphics doubles.

Extracts the actual controller; only ticket/dashboard rasterization is substituted.
UIKit drawing doubles record image order, and controllable snapshot/PNG awaits
ignore cancellation deliberately. No app/package build or simulator is used.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "ios/RailMap/ShareCardRendering.swift"


def controller_source():
    text = SOURCE.read_text()
    start = text.index("@MainActor @Observable\nfinal class ShareCardRenderController")
    end = text.index("\nprivate enum SharePNGWriter", start)
    controller = text[start:end].replace("@MainActor @Observable", "@MainActor")
    # Replace platform-only dashboard rasterization, leaving all acceptance,
    # cache, generation, cancel, ordered iteration and export code verbatim.
    raster = controller.index("    private func renderRecordTicket(")
    controller = controller[:raster] + r'''
    private func renderRecordTicket(
        model: ShareComposerModel, itineraries: ItineraryStore,
        memberIDs: Set<String>, localization: AppLocalization,
        journeyPresentation: @escaping (Train) -> JourneyPresentation,
        target: CGSize
    ) -> UIImage? { UIImage("dashboard-ticket") }
    private func renderDashboardCard(
        _ kind: StatisticsCardKind, model: ShareComposerModel,
        itineraries: ItineraryStore, memberIDs: Set<String>,
        localization: AppLocalization,
        journeyPresentation: @escaping (Train) -> JourneyPresentation,
        target: CGSize
    ) -> UIImage? { UIImage("dashboard-\(kind)") }
    var testCacheCount: Int { cache.count }
    var testPartialImages: [UIImage] {
        renderingBuffers.values.flatMap { $0.images.values }.filter { $0.name.hasPrefix("dashboard") }
    }
    var testBufferCount: Int { renderingBuffers.count }
    var testExportQueueCount: Int { exportWaiters.count }
    var testExportActive: Bool { exportOwner != nil }
    var testDashboardImage: UIImage? { cache.values.first { $0.name.hasPrefix("dashboard") } }
}
'''
    return controller

def view_export_source():
    text = (ROOT / "ios/RailMap/ShareComposerView.swift").read_text()
    assert ".onChange(of: renderKey) { _, _ in cancelExport() }" in text
    assert ".onDisappear { cancelExport(); renderer.cancel();" in text
    assert "|| renderer.completedKey != renderKey)" in text
    start = text.index("    private func export() {")
    end = text.index("    private func cardTitle(", start)
    # Extract both actual task acceptance and invalidation methods; wrappers
    # expose calls without duplicating their implementation.
    return r'''
@MainActor final class ExportViewDouble {
    var renderer: ShareCardRenderController
    var model: ShareComposerModel
    var itineraries = ItineraryStore()
    struct Rides { var rides: [RiddenRouteStore.DrawnRide] = [] }
    var riddenRoutes = Rides()
    var localization = AppLocalization()
    var journeyPresentation: (Train) -> JourneyPresentation = { _ in JourneyPresentation() }
    var renderKey = "scope"
    var exporting = false
    var exportTask: Task<Void, Never>?
    var exportTicket = 0
    var shareFile: StatisticsShareFile?
    init(_ renderer: ShareCardRenderController, _ model: ShareComposerModel) {
        self.renderer = renderer; self.model = model
    }
    func begin() { export() }
    func invalidate() { cancelExport() }
''' + text[start:end] + "}\n"


def view_load_key_source():
    text = (ROOT / "ios/RailMap/ShareComposerView.swift").read_text()
    scope_start = text.index("    private var scopedTrains: [Train] {")
    scope_end = text.index("    private var journeyGroups:", scope_start)
    key_start = text.index("    private var loadKey: String {")
    key_end = text.index("    private var renderKey:", key_start)
    # Execute both production getters verbatim. Only route membership and
    # selection model dependencies use the small controlled doubles below.
    return r'''
@MainActor final class LoadKeyViewDouble {
    let model = ShareComposerModel([])
    var itineraries = ItineraryStore()
    struct Rides { var rides: [RiddenRouteStore.DrawnRide] = [] }
    var riddenRoutes = Rides()
    var key: String { loadKey }
    var members: [String] { scopedTrains.map(\.id) }
''' + text[scope_start:scope_end] + text[key_start:key_end] + "}\n"


DOUBLES = r'''
import Foundation
import CoreGraphics

@MainActor final class UIImage {
    let name: String
    let size = CGSize(width: 10, height: 10)
    var drawn: [String]
    init(_ name: String, drawn: [String] = []) { self.name = name; self.drawn = drawn }
    func draw(in rect: CGRect) { DrawRecorder.names.append(name) }
}
@MainActor final class WeakImage {
    weak var image: UIImage?
    init(_ image: UIImage?) { self.image = image }
}
@MainActor enum DrawRecorder { static var names: [String] = [] }
@MainActor final class UIGraphicsImageRendererFormat {
    enum Range { case standard }
    var scale: CGFloat = 1
    var opaque = true
    var preferredRange: Range = .standard
}
@MainActor final class CGContextDouble {
    func saveGState() {}
    func restoreGState() {}
}
@MainActor final class RenderContext {
    let cgContext = CGContextDouble()
    func fill(_ rect: CGRect) {}
}
@MainActor final class UIGraphicsImageRenderer {
    init(size: CGSize, format: UIGraphicsImageRendererFormat) {}
    func image(actions: (RenderContext) -> Void) -> UIImage {
        DrawRecorder.names = []
        actions(RenderContext())
        return UIImage("canvas", drawn: DrawRecorder.names)
    }
}
enum ColorScheme { case light, dark }
enum UIUserInterfaceStyle { case light, dark }
struct UITraitCollection { let userInterfaceStyle: UIUserInterfaceStyle }
struct UIColor {
    static let systemBackground = UIColor()
    func resolvedColor(with traits: UITraitCollection) -> UIColor { self }
    func setFill() {}
}
struct UIBezierPath {
    init(roundedRect: CGRect, cornerRadius: CGFloat) {}
    func addClip() {}
}
struct Train {
    let id: String
    var year = 2026
    var date = "2026-07-03"
    var group = "selected-group"
    var ridden = true
}
struct JourneyPresentation {}
struct AppLocalization {}
struct StatisticsCardKind: Hashable, CustomStringConvertible {
    let raw: String
    static let recordTicket = Self(raw: "ticket")
    var description: String { raw }
}
struct Span { var columns = 1; var rows = 1 }
struct ShareCard {
    enum Kind: CustomStringConvertible {
        case ticket, stat(StatisticsCardKind), map(Area)
        var description: String {
            switch self { case .ticket: "ticket"; case .stat(let kind): "stat-\(kind)"; case .map(let area): "map-\(area.name)" }
        }
    }
    let id: UUID
    var kind: Kind
    var span = Span()
    var mapZoom: Double = 1
}
struct Scope {
    var name = "scope"
    var includedIDs: Set<String>?
    var requiresRide = false
    var key: String { name }
    func filter(_ trains: [Train], rides: [RiddenRouteStore.DrawnRide]) -> [Train] {
        trains.filter { train in
            (includedIDs?.contains(train.id) ?? true)
                && (!requiresRide || rides.contains { $0.id == train.id })
        }
    }
}
struct Area {
    let name: String
    var scope: Scope { Scope(name: name) }
    var mapExtent: Int? { nil }
    func localizedName(_ localization: AppLocalization) -> String { name }
}
struct Ratio { var rawValue = "square" }
struct CanvasSize {
    func pixelSize(for ratio: Ratio) -> CGSize { CGSize(width: 100, height: 100) }
}
struct Layout { var placements: [UUID: Int] }
struct Statistics {
    var selectedYear: Int?
    var selectedJourneyGroupID: String?
    var dateSelection = "all"
    func includesYear(_ train: Train) -> Bool { selectedYear == nil || selectedYear == train.year }
    func includesJourneyGroup(_ train: Train) -> Bool {
        selectedJourneyGroupID == nil || selectedJourneyGroupID == train.group
    }
    func includesDate(_ train: Train) -> Bool { dateSelection == "all" || dateSelection == train.date }
}
@MainActor final class ShareComposerModel {
    var cards: [ShareCard]
    var size = CanvasSize()
    var ratio = Ratio()
    var colorScheme = ColorScheme.light
    var effectiveScope = Scope()
    var statistics = Statistics()
    var layout: Layout { Layout(placements: Dictionary(uniqueKeysWithValues: cards.map { ($0.id, 1) })) }
    init(_ cards: [ShareCard]) { self.cards = cards }
}
@MainActor enum ShareCanvasGeometry {
    static func frames(model: ShareComposerModel, canvasSize: CGSize) -> [UUID: CGRect] {
        Dictionary(uniqueKeysWithValues: model.cards.map { ($0.id, CGRect(x: 0, y: 0, width: 100, height: 100)) })
    }
}
struct ItineraryStore {
    var loaded: Loaded? = Loaded()
    var storeGeneration = 0
    struct Loaded { var trains: [Train] = [] }
}
enum RiddenRouteStore {
    struct DrawnRide { let id: String; var geometryDigest = "original-geometry" }
}
enum RideLedger { static func hasBeenRidden(_ train: Train) -> Bool { train.ridden } }
@MainActor final class Gate {
    private var entered = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    func suspend() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            entered = true
            observer?.resume(); observer = nil
        }
    }
    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { observer = $0 }
    }
    func release() { continuation?.resume(); continuation = nil }
}
@MainActor enum StatisticsMapSnapshot {
    static var gates: [String: Gate] = [:]
    static var calls = 0
    static func render(rides: [RiddenRouteStore.DrawnRide], fallback: Int?, colorScheme: ColorScheme,
                       size: CGSize, zoom: Double, name: String) async -> UIImage? {
        calls += 1
        if let gate = gates[name] { await gate.suspend() }
        return UIImage(name)
    }
}
@MainActor struct StatisticsShareFile { let image: UIImage }
@MainActor enum SharePNGWriter {
    static var gate: Gate?
    static var calls = 0
    static var destinations: [URL?] = []
    static var active = 0
    static var peak = 0
    static func write(_ image: UIImage, to destination: URL? = nil) async -> StatisticsShareFile? {
        calls += 1
        destinations.append(destination)
        active += 1; peak = max(peak, active)
        defer { active -= 1 }
        if let gate { await gate.suspend() }
        return StatisticsShareFile(image: image)
    }
}
'''

CHECKS = r'''
@main struct Checks {
    @MainActor static func render(_ owner: ShareCardRenderController, _ model: ShareComposerModel, _ key: String) async {
        await owner.render(model: model, itineraries: ItineraryStore(), rides: [],
                           localization: AppLocalization(), journeyPresentation: { _ in JourneyPresentation() },
                           key: key, canvasSize: CGSize(width: 100, height: 100))
    }
    @MainActor static func export(_ owner: ShareCardRenderController, _ model: ShareComposerModel,
                                  key: String? = nil) async -> StatisticsShareFile? {
        await owner.export(model: model, itineraries: ItineraryStore(), rides: [],
                           localization: AppLocalization(), journeyPresentation: { _ in JourneyPresentation() },
                           key: key ?? owner.completedKey ?? "missing-key")
    }
    @MainActor static func wait(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() {
            precondition(ContinuousClock.now < deadline, "State synchronization timed out")
            await Task.yield()
        }
    }
    @MainActor static func main() async {
        var failures: [String] = []
        func check(_ condition: Bool, _ label: String) {
            if condition { print("PASS \(label)") }
            else { failures.append(label); print("FAIL \(label)") }
        }
        func card(_ name: String) -> ShareCard { ShareCard(id: UUID(), kind: .map(Area(name: name))) }
        let owner = ShareCardRenderController()
        let first = card("first"), second = card("second")
        let model = ShareComposerModel([second, first])
        await render(owner, model, "initial")
        check(Set(owner.images.keys) == Set([first.id, second.id]) && !owner.isRendering,
              "completed images retain current card identities")
        let callsBeforeReuse = StatisticsMapSnapshot.calls
        await render(owner, model, "initial")
        check(StatisticsMapSnapshot.calls == callsBeforeReuse, "unchanged key reuses current images")
        let priorPreview = WeakImage(owner.images[first.id])
        let file = await export(owner, model)
        check(file?.image.drawn == ["second", "first"], "export follows model card order")

        let old = card("old-scope"), replacement = card("new-scope")
        let oldGate = Gate(), newGate = Gate()
        StatisticsMapSnapshot.gates = ["old-scope": oldGate, "new-scope": newGate]
        let older = Task { await render(owner, ShareComposerModel([old]), "old-key") }
        await oldGate.waitUntilEntered()
        check(priorPreview.image == nil && owner.images.isEmpty,
              "prior cache and previews release before replacement allocation")
        let newerModel = ShareComposerModel([replacement])
        let newer = Task { await render(owner, newerModel, "new-key") }
        await newGate.waitUntilEntered()
        let delayedEntryGate = Gate()
        let delayedCancelled = Task {
            await delayedEntryGate.suspend()
            await render(owner, ShareComposerModel([old]), "already-cancelled")
        }
        await delayedEntryGate.waitUntilEntered()
        delayedCancelled.cancel()
        delayedEntryGate.release()
        await delayedCancelled.value
        check(owner.isRendering, "already-cancelled render cannot invalidate newer generation")
        let writes = SharePNGWriter.calls
        let blocked = await export(owner, newerModel)
        check(blocked == nil && SharePNGWriter.calls == writes, "export is blocked while render awaits")
        oldGate.release()
        await older.value
        check(owner.isRendering && owner.images[old.id] == nil,
              "old scope completion cannot publish or clear replacement busy")
        newGate.release()
        await newer.value
        check(Set(owner.images.keys) == [replacement.id] && !owner.isRendering,
              "replacement publishes only its current card")

        let cancelledCard = card("cancelled")
        let cancelGate = Gate()
        StatisticsMapSnapshot.gates = ["cancelled": cancelGate]
        let cancelled = Task { await render(owner, ShareComposerModel([cancelledCard]), "cancelled-key") }
        await cancelGate.waitUntilEntered()
        cancelled.cancel()
        owner.cancel()
        cancelGate.release()
        await cancelled.value
        check(owner.images[cancelledCard.id] == nil && !owner.isRendering,
              "late noncooperative snapshot is rejected after cancel")
        check(owner.images.isEmpty && owner.testCacheCount == 0,
              "cancel/disappear releases rendered images and cache")

        for replacesGeneration in [false, true] {
            let pendingOwner = ShareCardRenderController()
            let pendingMap = card("pending-map")
            let pendingGate = Gate()
            StatisticsMapSnapshot.gates = ["pending-map": pendingGate]
            let ticket = ShareCard(id: UUID(), kind: .ticket)
            let pendingModel = ShareComposerModel([ticket, pendingMap])
            let pendingTask = Task { await render(pendingOwner, pendingModel, "pending-key") }
            await pendingGate.waitUntilEntered()
            let pendingPixels = WeakImage(pendingOwner.testDashboardImage)
            check(pendingPixels.image != nil, "dashboard buffer exists before suspended map")
            if replacesGeneration {
                await render(pendingOwner, ShareComposerModel([]), "replacement-empty")
            } else {
                pendingTask.cancel()
                pendingOwner.cancel()
            }
            check(pendingPixels.image == nil,
                  "in-progress pixels release before map resumes after \(replacesGeneration ? "replacement" : "cancel")")
            pendingGate.release()
            await pendingTask.value
            check(pendingOwner.images.isEmpty && !pendingOwner.isRendering,
                  "late map cannot republish retired generation buffers")
        }

        StatisticsMapSnapshot.gates = [:]
        let bounded = ShareCardRenderController()
        let fixedModel = ShareComposerModel([card("cache")])
        for index in 0..<12 { await render(bounded, fixedModel, "scope-size-zoom-\(index)") }
        check(bounded.testCacheCount <= fixedModel.cards.count,
              "cache retains only current key and cards")

        let exportingOwner = ShareCardRenderController()
        let exportModel = ShareComposerModel([card("export")])
        await render(exportingOwner, exportModel, "export-before")
        let exportGate = Gate()
        SharePNGWriter.gate = exportGate
        let exporting = Task { await export(exportingOwner, exportModel) }
        await exportGate.waitUntilEntered()
        exporting.cancel()
        exportingOwner.cancel()
        exportGate.release()
        let staleFile = await exporting.value
        check(staleFile == nil, "export rejects late file after cancellation/disappear")
        SharePNGWriter.gate = nil

        let changedOwner = ShareCardRenderController()
        await render(changedOwner, exportModel, "scope-before")
        let scopeExportGate = Gate()
        SharePNGWriter.gate = scopeExportGate
        let scopeExport = Task { await export(changedOwner, exportModel) }
        await scopeExportGate.waitUntilEntered()
        await render(changedOwner, ShareComposerModel([card("changed")]), "scope-after")
        scopeExportGate.release()
        let oldFile = await scopeExport.value
        check(oldFile == nil, "export rejects file after replacement generation")
        SharePNGWriter.gate = nil
        let mismatchedWrites = SharePNGWriter.calls
        let mismatchedRenders = StatisticsMapSnapshot.calls
        let mismatch = await export(changedOwner, exportModel, key: "not-completed")
        check(mismatch == nil && SharePNGWriter.calls == mismatchedWrites
              && StatisticsMapSnapshot.calls == mismatchedRenders,
              "controller exact completed key blocks export raster and PNG")

        for replacesGeneration in [false, true] {
            let fullOwner = ShareCardRenderController()
            let fullMap = card("full-export-map")
            let ticket = ShareCard(id: UUID(), kind: .ticket)
            let fullModel = ShareComposerModel([ticket, fullMap])
            StatisticsMapSnapshot.gates = [:]
            await render(fullOwner, fullModel, "full-export")
            let fullGate = Gate()
            StatisticsMapSnapshot.gates = ["full-export-map": fullGate]
            let beforeFullCalls = StatisticsMapSnapshot.calls
            let fullTask = Task { await export(fullOwner, fullModel) }
            await fullGate.waitUntilEntered()
            let fullPixels = WeakImage(fullOwner.testPartialImages.first)
            check(fullPixels.image != nil && StatisticsMapSnapshot.calls == beforeFullCalls + 1,
                  "full-resolution export rerenders without preview cache")
            if replacesGeneration {
                await render(fullOwner, ShareComposerModel([]), "full-replacement")
            } else {
                fullOwner.cancel()
            }
            check(fullPixels.image == nil && fullOwner.testBufferCount == 0,
                  "full-resolution partial pixels release before map resumes after \(replacesGeneration ? "replacement" : "cancel")")
            fullGate.release()
            let rejectedFull = await fullTask.value
            check(rejectedFull == nil, "retired full-resolution export cannot publish")
        }

        let concurrentOwner = ShareCardRenderController()
        let concurrentModel = ShareComposerModel([
            ShareCard(id: UUID(), kind: .ticket), card("concurrent-export")])
        StatisticsMapSnapshot.gates = [:]
        await render(concurrentOwner, concurrentModel, "concurrent")
        let firstMapGate = Gate(), secondMapGate = Gate()
        StatisticsMapSnapshot.gates = ["concurrent-export": firstMapGate]
        let firstFull = Task { await export(concurrentOwner, concurrentModel) }
        await firstMapGate.waitUntilEntered()
        let firstFullPixels = WeakImage(concurrentOwner.testPartialImages.first)
        StatisticsMapSnapshot.gates = ["concurrent-export": secondMapGate]
        let secondFull = Task { await export(concurrentOwner, concurrentModel) }
        await wait { concurrentOwner.testExportQueueCount == 1 }
        check(concurrentOwner.testBufferCount == 1 && firstFullPixels.image != nil,
              "same-generation second export waits without allocating partial buffers")
        firstFull.cancel()
        firstMapGate.release()
        let discardedFirst = await firstFull.value
        await secondMapGate.waitUntilEntered()
        let secondFullPixels = WeakImage(concurrentOwner.testPartialImages.first)
        check(discardedFirst == nil && firstFullPixels.image == nil
              && secondFullPixels.image != nil && concurrentOwner.testBufferCount == 1,
              "one export cleanup cannot release the next admitted export buffer")
        secondMapGate.release()
        let secondFullFile = await secondFull.value
        check(secondFullFile?.image.drawn == ["dashboard-ticket", "concurrent-export"]
              && secondFullPixels.image == nil && concurrentOwner.testBufferCount == 0,
              "current full export preserves card order and releases partial buffers")
        StatisticsMapSnapshot.gates = [:]

        let admittedOwner = ShareCardRenderController()
        let admittedModel = ShareComposerModel([card("admitted")])
        await render(admittedOwner, admittedModel, "admitted")
        let activeWriteGate = Gate()
        SharePNGWriter.gate = activeWriteGate
        let beforeAdmissionWrites = SharePNGWriter.calls
        let beforeAdmissionRenders = StatisticsMapSnapshot.calls
        let activeExport = Task { await export(admittedOwner, admittedModel, key: "admitted") }
        await activeWriteGate.waitUntilEntered()
        let queuedCancelled = Task { await export(admittedOwner, admittedModel, key: "admitted") }
        await wait { admittedOwner.testExportQueueCount == 1 }
        check(SharePNGWriter.calls == beforeAdmissionWrites + 1
              && StatisticsMapSnapshot.calls == beforeAdmissionRenders + 1,
              "queued export performs neither full-resolution raster nor PNG work")
        queuedCancelled.cancel()
        let cancelledQueuedFile = await queuedCancelled.value
        check(cancelledQueuedFile == nil && admittedOwner.testExportQueueCount == 0
              && admittedOwner.testExportActive && SharePNGWriter.active == 1,
              "queued cancellation removes only its own ticket while writer retains admission")
        let staleQueued = Task { await export(admittedOwner, admittedModel, key: "admitted") }
        await wait { admittedOwner.testExportQueueCount == 1 }
        activeExport.cancel()
        admittedOwner.cancel()
        let staleQueuedFile = await staleQueued.value
        check(staleQueuedFile == nil && admittedOwner.testExportQueueCount == 0
              && admittedOwner.testExportActive && SharePNGWriter.active == 1,
              "generation invalidation discards old waiters without releasing noncooperative writer")
        await render(admittedOwner, admittedModel, "new-admitted")
        let nextWriteGate = Gate()
        SharePNGWriter.gate = nextWriteGate
        let replacementExport = Task { await export(admittedOwner, admittedModel, key: "new-admitted") }
        await wait { admittedOwner.testExportQueueCount == 1 }
        check(SharePNGWriter.calls == beforeAdmissionWrites + 1 && SharePNGWriter.active == 1,
              "replacement generation also waits for prior cancelled writer exit")
        activeWriteGate.release()
        let staleActiveFile = await activeExport.value
        await nextWriteGate.waitUntilEntered()
        check(staleActiveFile == nil && admittedOwner.testExportActive && SharePNGWriter.active == 1,
              "late active writer rejects output and transfers admission to current generation")
        nextWriteGate.release()
        let replacementFile = await replacementExport.value
        check(replacementFile != nil && !admittedOwner.testExportActive
              && admittedOwner.testExportQueueCount == 0 && SharePNGWriter.peak == 1,
              "full-resolution PNG admission never overlaps and releases after completion")
        SharePNGWriter.gate = nil

        let fifoOwner = ShareCardRenderController()
        await render(fifoOwner, admittedModel, "fifo")
        let fifoFirstGate = Gate(), fifoSecondGate = Gate(), fifoThirdGate = Gate()
        SharePNGWriter.gate = fifoFirstGate
        let fifoFirst = Task { await export(fifoOwner, admittedModel, key: "fifo") }
        await fifoFirstGate.waitUntilEntered()
        var fifoCompletions: [Int] = []
        let fifoSecond = Task { let file = await export(fifoOwner, admittedModel, key: "fifo"); fifoCompletions.append(2); return file }
        await wait { fifoOwner.testExportQueueCount == 1 }
        let fifoThird = Task { let file = await export(fifoOwner, admittedModel, key: "fifo"); fifoCompletions.append(3); return file }
        await wait { fifoOwner.testExportQueueCount == 2 }
        SharePNGWriter.gate = fifoSecondGate
        fifoFirstGate.release()
        _ = await fifoFirst.value
        await fifoSecondGate.waitUntilEntered()
        check(fifoOwner.testExportQueueCount == 1 && fifoCompletions.isEmpty,
              "FIFO admits the oldest waiter while later tickets remain queued")
        SharePNGWriter.gate = fifoThirdGate
        fifoSecondGate.release()
        _ = await fifoSecond.value
        await fifoThirdGate.waitUntilEntered()
        check(fifoCompletions == [2] && fifoOwner.testExportQueueCount == 0,
              "FIFO advances exactly one owner at a time")
        fifoThirdGate.release()
        _ = await fifoThird.value
        check(fifoCompletions == [2, 3] && !fifoOwner.testExportActive,
              "FIFO completion preserves queue order and releases final admission")
        SharePNGWriter.gate = nil

        let debugOwner = ShareCardRenderController()
        await render(debugOwner, admittedModel, "debug")
        let debugGate = Gate(), userAfterDebugGate = Gate()
        SharePNGWriter.gate = debugGate
        let debugWrites = SharePNGWriter.calls
        let debugURL = URL(fileURLWithPath: "/tmp/harness-only-debug.png")
        let debugExport = Task {
            await debugOwner.writeDebugExport(
                model: admittedModel, itineraries: ItineraryStore(), rides: [],
                localization: AppLocalization(), journeyPresentation: { _ in JourneyPresentation() },
                to: debugURL, key: "debug")
        }
        await debugGate.waitUntilEntered()
        let userExport = Task { await export(debugOwner, admittedModel, key: "debug") }
        await wait { debugOwner.testExportQueueCount == 1 }
        check(SharePNGWriter.calls == debugWrites + 1
              && SharePNGWriter.destinations.last! == debugURL,
              "DEBUG writes its destination through one admitted PNG encode")
        SharePNGWriter.gate = userAfterDebugGate
        debugGate.release()
        await debugExport.value
        await userAfterDebugGate.waitUntilEntered()
        check(debugOwner.debugExportedKey == "debug" && SharePNGWriter.calls == debugWrites + 2,
              "user export waits for DEBUG destination and DEBUG never re-encodes")
        userAfterDebugGate.release()
        _ = await userExport.value
        check(!debugOwner.testExportActive && SharePNGWriter.peak == 1,
              "DEBUG and user export share one full-resolution admission")
        SharePNGWriter.gate = nil

        let viewOwner = ShareCardRenderController()
        let view = ExportViewDouble(viewOwner, exportModel)
        let initialWrites = SharePNGWriter.calls
        view.begin()
        check(view.exportTask == nil && !view.exporting && view.exportTicket == 0
              && SharePNGWriter.calls == initialWrites,
              "initial view export blocks task and PNG before completed render")
        await render(viewOwner, exportModel, "view")
        view.renderKey = "new-model-before-debounce"
        view.begin()
        check(view.exportTask == nil && !view.exporting && view.exportTicket == 0
              && SharePNGWriter.calls == initialWrites,
              "old completed key blocks export during new model debounce")
        view.renderKey = "view"
        let firstWrite = Gate(), secondWrite = Gate()
        SharePNGWriter.gate = firstWrite
        view.begin()
        let firstTask = view.exportTask!
        await firstWrite.waitUntilEntered()
        view.renderKey = "replacement-view-scope"
        view.invalidate()
        await render(viewOwner, exportModel, view.renderKey)
        SharePNGWriter.gate = secondWrite
        view.begin()
        let secondTask = view.exportTask!
        await wait { viewOwner.testExportQueueCount == 1 }
        firstWrite.release()
        await firstTask.value
        await secondWrite.waitUntilEntered()
        check(view.exporting && view.shareFile == nil && view.exportTask != nil,
              "old view export cannot present or clear replacement busy")
        secondWrite.release()
        await secondTask.value
        check(!view.exporting && view.exportTask == nil && view.shareFile != nil,
              "current view export presents and releases task")

        view.shareFile = nil
        let disappearedWrite = Gate()
        SharePNGWriter.gate = disappearedWrite
        view.begin()
        let disappearedTask = view.exportTask!
        await disappearedWrite.waitUntilEntered()
        view.invalidate()
        viewOwner.cancel()
        disappearedWrite.release()
        await disappearedTask.value
        check(view.shareFile == nil && !view.exporting && view.exportTask == nil,
              "view disappearance rejects late export and releases busy")
        SharePNGWriter.gate = nil

        let loadView = LoadKeyViewDouble()
        loadView.model.effectiveScope = Scope(
            name: "selected-scope", includedIDs: ["member", "arrival", "wrong-date", "wrong-year", "wrong-group", "unridden"],
            requiresRide: true)
        loadView.model.statistics.selectedYear = 2026
        loadView.model.statistics.dateSelection = "2026-07-03"
        loadView.model.statistics.selectedJourneyGroupID = "selected-group"
        loadView.itineraries.loaded?.trains = [
            Train(id: "member"), Train(id: "arrival"), Train(id: "outside-scope"),
            Train(id: "wrong-date", date: "2026-07-04"),
            Train(id: "wrong-year", year: 2025),
            Train(id: "wrong-group", group: "other-group"),
            Train(id: "unridden", ridden: false),
        ]
        loadView.riddenRoutes.rides = [
            .init(id: "member"), .init(id: "outside-scope"), .init(id: "wrong-date"),
            .init(id: "wrong-year"), .init(id: "wrong-group"), .init(id: "unridden"),
        ]
        let originalLoadKey = loadView.key
        check(loadView.members == ["member"],
              "production scoped getter respects scope/date/year/group/ridden selection")
        loadView.riddenRoutes.rides.append(.init(id: "unrelated-publication"))
        check(loadView.key == originalLoadKey,
              "unrelated ride publication does not invalidate production load key")
        for index in loadView.riddenRoutes.rides.indices where loadView.riddenRoutes.rides[index].id != "member" {
            loadView.riddenRoutes.rides[index].geometryDigest = "changed-unrelated-geometry"
        }
        check(loadView.key == originalLoadKey,
              "excluded scope/date/year/group/unridden geometry does not invalidate load key")
        loadView.riddenRoutes.rides.append(.init(id: "arrival"))
        let arrivalKey = loadView.key
        check(arrivalKey != originalLoadKey && loadView.members == ["member", "arrival"],
              "scoped ride arrival invalidates production load key")
        loadView.riddenRoutes.rides[0].geometryDigest = "changed-member-geometry"
        let geometryKey = loadView.key
        check(geometryKey != arrivalKey,
              "scoped ride geometry change invalidates production load key")
        loadView.riddenRoutes.rides.removeAll { $0.id == "member" }
        var priorKey = loadView.key
        check(priorKey != geometryKey && loadView.members == ["arrival"],
              "scoped ride removal invalidates production load key")
        loadView.model.effectiveScope.name = "replacement-scope"
        check(loadView.key != priorKey, "scope change invalidates production load key")
        priorKey = loadView.key
        loadView.model.statistics.dateSelection = "2026-07-04"
        check(loadView.key != priorKey, "date change invalidates production load key")
        priorKey = loadView.key
        loadView.model.statistics.selectedYear = 2025
        check(loadView.key != priorKey, "year change invalidates production load key")
        priorKey = loadView.key
        loadView.model.statistics.selectedJourneyGroupID = "other-group"
        check(loadView.key != priorKey, "journey group change invalidates production load key")
        priorKey = loadView.key
        loadView.itineraries.storeGeneration += 1
        check(loadView.key != priorKey, "store generation change invalidates production load key")
        if !failures.isEmpty {
            print("Share rendering contracts failed: \(failures.joined(separator: "; "))")
            exit(1)
        }
    }
}
'''


def main():
    with tempfile.TemporaryDirectory(prefix="jtm-share-card-rendering-") as temporary:
        folder = Path(temporary)
        checks = folder / "Checks.swift"
        checks.write_text(DOUBLES + controller_source() + view_export_source() + view_load_key_source() + CHECKS)
        executable = folder / "checks"
        subprocess.run([
            "xcrun", "swiftc", "-swift-version", "6", "-parse-as-library", "-D", "DEBUG",
            "-module-cache-path", str(folder / "modules"), str(checks), "-o", str(executable),
        ], check=True)
        subprocess.run([str(executable)], check=True, timeout=30)


if __name__ == "__main__":
    main()
