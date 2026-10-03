#if DEBUG
import Foundation
import Observation
import RailCore
import SwiftUI
import UIKit

/// Opt-in driver for the production store and map. It never saves the stress
/// document to the library. Copies retain the sample's station codes, route
/// choices, dates and times; only their record identity changes.
@MainActor
@Observable
final class RouteStressHarness {
    static var enabled: Bool { ProcessInfo.processInfo.environment["RAILMAP_UI_TEST_STRESS"] == "1" }
    let count = max(50, min(20_000, Int(ProcessInfo.processInfo.environment["RAILMAP_STRESS_COUNT"] ?? "") ?? 1_000))
    let additions = max(1, min(1_000, Int(ProcessInfo.processInfo.environment["RAILMAP_STRESS_ADDITIONS"] ?? "") ?? 100))
    let switches = max(10, min(2_000, Int(ProcessInfo.processInfo.environment["RAILMAP_STRESS_SWITCHES"] ?? "") ?? 60))
    private(set) var phase = "idle"
    private(set) var expectedCount = 0
    private(set) var requestedID = "none"
    private(set) var requestedDate = Dates.allDates
    private(set) var completedSwitches = 0
    private(set) var roundtrip = false
    private(set) var exportBytes = 0
    private(set) var elapsedMilliseconds = 0
    private(set) var error = "none"
    @ObservationIgnored private var sources: [Train] = []
    @ObservationIgnored private var targets: [Train] = []
    @ObservationIgnored private var probe = MapGestureFrameProbe()
    @ObservationIgnored private var didAutorun = false

    func status(_ store: ItineraryStore) -> String {
        let loaded = store.loaded
        return "phase:\(phase);expected:\(expectedCount);stored:\(store.store?.trains.count ?? -1)"
            + ";loaded:\(loaded?.trains.count ?? -1);countries:\(loaded?.regions.count ?? 0)"
            + ";dates:\(loaded?.days.count ?? 0);selected:\(store.selectedTrainID ?? "none")"
            + ";requested:\(requestedID);date:\(requestedDate);switches:\(completedSwitches)"
            + ";roundtrip:\(roundtrip ? 1 : 0);bytes:\(exportBytes);elapsedMs:\(elapsedMilliseconds)"
            + ";frames:\(probe.frames);maxFrameGapMs:\(Int(probe.maximumGapMilliseconds));error:\(error)"
    }

    func prepare(store: ItineraryStore, library: RideLibrary) async {
        guard phase == "idle", store.loaded != nil else { return }
        phase = "importing"
        let started = ContinuousClock.now
        probe.start()
        do {
            var regional: [[Train]] = []
            for sample in RideLibrary.Sample.all where sample.resource.hasPrefix("train-store") {
                let document = try await library.sample(sample.resource)
                let trains = document.trains.filter { $0.stops.count > 1 }.map { train in
                    var tagged = train
                    tagged.region = sample.region.code
                    tagged.visible = true
                    return tagged
                }
                guard !trains.isEmpty else { throw HarnessError("empty sample \(sample.resource)") }
                regional.append(trains)
            }
            // Interleave countries, while traversing every source itinerary.
            sources = (0..<(regional.map(\.count).max() ?? 0)).flatMap { index in
                regional.compactMap { index < $0.count ? $0[index] : nil }
            }
            let input = await Task.detached(priority: .userInitiated) { [sources, count] in
                let trains = (0..<count).map { index in
                    var copy = sources[index % sources.count]
                    copy.id += "_stress_\(index)"
                    return copy
                }
                return (trains, MergedStore.export(TrainStore(trains: trains)))
            }.value
            expectedCount = count
            _ = try await store.runImport(text: input.1, region: .jp, mode: .replaceAll,
                                         sourceLabel: "Stress samples", onProgress: { _ in })
            // The first entries are one real route per country; Japanese
            // date changes also use the final source (a different sample day).
            let loaded = store.loaded?.trains ?? []
            targets = ["jp", "tw", "hk", "mo", "kr"].compactMap { region in
                loaded.first { $0.region == region }
            }
            if let first = targets.first,
               let anotherDay = loaded.first(where: { $0.region == "jp" && Dates.trainDate($0.forDates) != Dates.trainDate(first.forDates) }) {
                targets.append(anotherDay)
            }
            elapsedMilliseconds = (ContinuousClock.now - started).milliseconds
            phase = "ready"
        } catch { fail(error) }
        probe.stop()
    }

    func addBurst(store: ItineraryStore, controller: RailMapController) async {
        guard phase == "ready", !sources.isEmpty else { return }
        phase = "adding"
        probe = MapGestureFrameProbe()
        probe.start()
        let started = ContinuousClock.now
        for index in 0..<additions {
            var train = sources[index % sources.count]
            train.id += "_stress_added_\(index)"
            guard let id = store.add(train) else { fail(HarnessError("add refused at \(index)")); break }
            expectedCount += 1
            requestedID = id
            // Multiple commits per frame stress cancellation/coalescing while
            // still letting the live UI and display link run between batches.
            if index % 5 == 4 { await Task.yield() }
        }
        if phase != "failed" {
            controller.requestAutoFocus(.journey(requestedID), enabled: true, playbackIsActive: false)
        }
        elapsedMilliseconds = (ContinuousClock.now - started).milliseconds
        if phase != "failed" { phase = "added" }
        // Continue measuring until XCTest observes the settled map and stops
        // the probe explicitly. Returning from add is not render completion.
    }

    func switchBurst(store: ItineraryStore, controller: RailMapController,
                     selectDate: (String) -> Void) async {
        guard ["ready", "added", "roundtripped", "finished"].contains(phase), !targets.isEmpty else { return }
        phase = "switching"
        completedSwitches = 0
        probe.stop()
        probe = MapGestureFrameProbe()
        probe.start()
        let started = ContinuousClock.now
        do {
            for index in 0..<switches {
                try Task.checkCancellation()
                let train = targets[index % targets.count]
                requestedID = train.id
                requestedDate = index % 3 == 0 ? Dates.allDates : Dates.trainDate(train.forDates)
                selectDate(requestedDate)
                store.selectedTrainID = train.id
                controller.requestAutoFocus(.journey(train.id), enabled: true, playbackIsActive: false)
                completedSwitches += 1
                // A deliberately faster-than-animation request stream, with
                // a real SwiftUI/MapKit turn between requests.
                try await Task.sleep(for: .milliseconds(25))
            }
            elapsedMilliseconds = (ContinuousClock.now - started).milliseconds
            phase = "switched"
        } catch { fail(error); probe.stop() }
    }

    func exportRoundtrip(store: ItineraryStore) async {
        guard ["ready", "added", "finished", "switched"].contains(phase) else { return }
        phase = "exporting"
        probe.stop()
        probe = MapGestureFrameProbe()
        probe.start()
        do {
            guard let text = await store.exportJSON() else { throw HarnessError("export missing") }
            exportBytes = text.utf8.count
            let before = try await Task.detached(priority: .userInitiated) {
                try TrainValidation.parseImportedCanonicalStore(text: text)
            }.value
            _ = try await store.runImport(text: text, region: .jp, mode: .replaceAll,
                                         sourceLabel: "Stress roundtrip", onProgress: { _ in })
            guard let afterText = await store.exportJSON() else { throw HarnessError("second export missing") }
            let equivalent = try await Task.detached(priority: .userInitiated) {
                before == (try TrainValidation.parseImportedCanonicalStore(text: afterText))
            }.value
            guard equivalent, store.store?.trains.count == expectedCount else {
                throw HarnessError("canonical roundtrip changed journeys")
            }
            roundtrip = true
            phase = "roundtripped"
        } catch { fail(error) }
        probe.stop()
    }

    func finish() { probe.stop(); phase = "finished" }

    /// Fallback for hosts where XCTest cannot discover the booted destination.
    /// It observes the same mounted MapKit state as the UI tests and records
    /// submissions/renderers, without making a claim about GPU raster pixels.
    func autorun(store: ItineraryStore, controller: RailMapController,
                 selectDate: (String) -> Void) async {
        guard ProcessInfo.processInfo.environment["RAILMAP_STRESS_AUTORUN"] == "1",
              !didAutorun, phase == "ready" || phase == "failed" else { return }
        didAutorun = true
        var observations: [AutorunObservation] = []
        var passed = false
        let started = ContinuousClock.now
        do {
            try require(phase == "ready", "initial import failed: \(error)")
            try require(store.store?.trains.count == count && store.loaded?.trains.count == count,
                        "initial store/group count mismatch")
            try require(store.loaded?.regions.count == 5 && (store.loaded?.days.count ?? 0) >= 5,
                        "initial import lost countries or dates")
            observations.append(observation("importCommitted", store: store, map: [:], started: started))
            await writeAutorunReport(store: store, observations: observations, passed: false, complete: false)
            let importedMap = try await waitForMap(controller, seconds: 300, label: "all imported geometry") {
                Int($0["rides"] ?? "") == self.count && (Int($0["rebuilds"] ?? "") ?? 0) > 0
                    && (Int($0["nonemptyRides"] ?? "") ?? 0) > 0
                    && (Int($0["installedRideOverlays"] ?? "") ?? 0) > 0
            }
            observations.append(observation("import", store: store, map: importedMap, started: started))
            await writeAutorunReport(store: store, observations: observations, passed: false, complete: false)

            await addBurst(store: store, controller: controller)
            try await waitUntil(seconds: 90, label: "rapid add grouping") {
                store.loaded?.trains.count == self.expectedCount && store.store?.trains.count == self.expectedCount
                    && store.selectedTrainID == self.requestedID
            }
            let addedMap = try await waitForMap(controller, seconds: 90, label: "rapid add selection", condition: selectionIsSettled)
            finish()
            observations.append(observation("rapidAdd", store: store, map: addedMap, started: started))
            await writeAutorunReport(store: store, observations: observations, passed: false, complete: false)

            await switchBurst(store: store, controller: controller, selectDate: selectDate)
            let switchedMap = try await waitForMap(controller, seconds: 30, label: "latest highlight/date", condition: selectionIsSettled)
            finish()
            observations.append(observation("rapidSwitch", store: store, map: switchedMap, started: started))
            try require(completedSwitches == switches && probe.frames > 20,
                        "switch stream/display-link sample incomplete")
            let limit = Int(ProcessInfo.processInfo.environment["RAILMAP_STRESS_MAX_FRAME_GAP_MS"] ?? "") ?? 500
            try require(Int(probe.maximumGapMilliseconds) <= limit,
                        "switch display link gap \(Int(probe.maximumGapMilliseconds))ms exceeds \(limit)ms")
            await writeAutorunReport(store: store, observations: observations, passed: false, complete: false)

            await exportRoundtrip(store: store)
            try require(phase == "roundtripped" && roundtrip && exportBytes > 100_000,
                        "canonical export/reimport failed: \(error)")
            try require(store.store?.trains.count == expectedCount && store.loaded?.trains.count == expectedCount
                        && store.loaded?.regions.count == 5, "roundtrip store/group mismatch")
            observations.append(observation("roundtrip", store: store, map: switchedMap, started: started))
            phase = "autorunPassed"
            passed = true
        } catch { fail(error) }
        probe.stop()
        await writeAutorunReport(store: store, observations: observations, passed: passed, complete: true)
    }

    private func selectionIsSettled(_ fields: [String: String]) -> Bool {
        let expected = Int(fields["selectionExpectedParts"] ?? "") ?? 0
        return fields["submittedSelection"] == requestedID && fields["submittedDate"] == requestedDate
            && expected > 0 && Int(fields["selectionParts"] ?? "") == expected
            && Int(fields["selectionCasingParts"] ?? "") == expected
            && (Int(fields["selectionRenderers"] ?? "") ?? 0) > 0 && fields["selectionSettled"] == "1"
    }

    private func waitForMap(_ controller: RailMapController, seconds: Int, label: String,
                            condition: ([String: String]) -> Bool) async throws -> [String: String] {
        var latest: [String: String] = [:]
        do {
            try await waitUntil(seconds: seconds, label: label) {
                guard let view = controller.mapView,
                      let status = self.findStatusLabel(in: view) else { return false }
                latest = Self.fields(status.accessibilityLabel ?? status.text ?? "")
                return condition(latest)
            }
        } catch {
            throw HarnessError("\(label): \(error.localizedDescription); last map fields \(latest)")
        }
        return latest
    }

    private func waitUntil(seconds: Int, label: String, condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
        repeat {
            try Task.checkCancellation()
            try require(phase != "failed", "\(label): \(error)")
            if condition() { return }
            try await Task.sleep(for: .milliseconds(100))
        } while ContinuousClock.now < deadline
        throw HarnessError("timed out waiting for \(label)")
    }

    private func findStatusLabel(in view: UIView) -> UILabel? {
        if view.accessibilityIdentifier == "railMapRenderStatus", let label = view as? UILabel { return label }
        for child in view.subviews {
            if let label = findStatusLabel(in: child) { return label }
        }
        return nil
    }

    private static func fields(_ text: String) -> [String: String] {
        Dictionary(text.split(separator: ";").compactMap { field in
            let pair = field.split(separator: ":", maxSplits: 1).map(String.init)
            return pair.count == 2 ? (pair[0], pair[1]) : nil
        }, uniquingKeysWith: { _, last in last })
    }

    private struct AutorunObservation: Codable, Sendable {
        var stage: String
        var elapsedMilliseconds: Int
        var harness: [String: String]
        var map: [String: String]
    }
    private struct AutorunReport: Codable, Sendable {
        var complete: Bool
        var passed: Bool
        var phase: String
        var error: String
        var count: Int
        var additions: Int
        var switches: Int
        var observations: [AutorunObservation]
        var finalStatus: [String: String]
    }
    private func observation(_ stage: String, store: ItineraryStore, map: [String: String],
                             started: ContinuousClock.Instant) -> AutorunObservation {
        .init(stage: stage, elapsedMilliseconds: (ContinuousClock.now - started).milliseconds,
              harness: Self.fields(status(store)), map: map)
    }
    private func writeAutorunReport(store: ItineraryStore, observations: [AutorunObservation],
                                    passed: Bool, complete: Bool) async {
        let report = AutorunReport(complete: complete, passed: passed, phase: phase, error: error,
                                   count: count, additions: additions, switches: switches,
                                   observations: observations, finalStatus: Self.fields(status(store)))
        let url = URL.cachesDirectory.appending(path: "route-stress-result.json")
        do {
            try await Task.detached(priority: .utility) {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(report).write(to: url, options: .atomic)
            }.value
            NSLog("railmap stress: phase=%@ complete=%@ passed=%@ result=%@", phase,
                  complete ? "true" : "false", passed ? "true" : "false", url.path)
        } catch { fail(error); NSLog("railmap stress: result write failed: %@", error.localizedDescription) }
    }

    private func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw HarnessError(message) }
    }
    private func fail(_ failure: Error) {
        error = failure.localizedDescription.replacingOccurrences(of: ";", with: ",")
        phase = "failed"
    }
    private struct HarnessError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}

/// Accessibility reads the *current* probe values, without publishing SwiftUI
/// state 60 times a second and changing the performance being measured.
@MainActor
final class RouteStressStatusLabel: UILabel {
    var readStatus: (() -> String)?
    override var accessibilityLabel: String? {
        get { readStatus?() ?? super.accessibilityLabel }
        set { super.accessibilityLabel = newValue }
    }
}

private struct RouteStressStatus: UIViewRepresentable {
    var read: () -> String
    func makeUIView(context: Context) -> RouteStressStatusLabel {
        let label = RouteStressStatusLabel()
        label.isAccessibilityElement = true
        label.accessibilityIdentifier = "routeStressStatus"
        label.text = " "
        label.textColor = .clear
        label.readStatus = read
        return label
    }
    func updateUIView(_ uiView: RouteStressStatusLabel, context: Context) { uiView.readStatus = read }
}

struct RouteStressHarnessPanel: View {
    @State private var harness = RouteStressHarness()
    var itineraries: ItineraryStore
    var library: RideLibrary
    var controller: RailMapController
    var selectDate: (String) -> Void
    var body: some View {
        VStack(spacing: 4) {
            RouteStressStatus { harness.status(itineraries) }.frame(width: 1, height: 1)
            HStack {
                Button("Add") { Task { await harness.addBurst(store: itineraries, controller: controller) } }
                    .accessibilityIdentifier("routeStressAdd")
                Button("Switch") { Task { await harness.switchBurst(store: itineraries, controller: controller, selectDate: selectDate) } }
                    .accessibilityIdentifier("routeStressSwitch")
                Button("Roundtrip") { Task { await harness.exportRoundtrip(store: itineraries) } }
                    .accessibilityIdentifier("routeStressRoundtrip")
                Button("Finish") { harness.finish() }.accessibilityIdentifier("routeStressFinish")
            }
            .buttonStyle(.borderedProminent)
            .font(.caption)
        }
        .padding(4)
        .task(id: itineraries.loaded != nil) {
            await harness.prepare(store: itineraries, library: library)
            await harness.autorun(store: itineraries, controller: controller, selectDate: selectDate)
        }
    }
}
#endif
