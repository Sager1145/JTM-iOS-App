import Foundation
import Observation
import RailCore

/// The one route-repair run, owned by the journey editor.
///
/// It walks the ride's failing spans in travel order. A span the package
/// decides alone is applied; the first span with several surveyed paths
/// pauses, and the editor shows that pause's choices on its map. Nothing is
/// persisted here: every result goes to the editor's draft through `apply`,
/// and the reader's Save or Cancel decides what is kept.
@MainActor
@Observable
final class RouteRepairController {
    /// A span waiting for the reader, with each choice's track for the map.
    struct Pause: Equatable {
        var fromVisitID: UUID
        var toVisitID: UUID
        var choices: [RailwayRouteChoices.Choice]
        var geometry: [[TripRouteGeometry.Piece]]
        var remaining: [RouteRepairFlow.Step]
    }

    private(set) var pause: Pause?
    private(set) var summary: String?
    private(set) var isRunning = false
    private var repaired = 0
    private var gaps: [RouteRepairFlow.GapName] = []
    /// The draft as this run last left it. A result is written only while
    /// the draft still equals it, so a reader's edit is never overwritten.
    @ObservationIgnored private var expected: Train?
    /// The ride the next step works on: `expected` plus editor-only visit
    /// ids, which are written into the draft only with a real route change.
    @ObservationIgnored private var working: Train?
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Writes a result into the draft. Returns false when the draft is no
    /// longer `expected`, which drops the result rather than overwriting edits.
    typealias Apply = @MainActor (_ expected: Train, _ result: Train) -> Bool
    typealias Text = @MainActor (String, [String: Localization.Param]) -> String

    func start(
        train: Train, gaps statusGaps: [RouteRepair.Gap], package: CompactPackage,
        geometry: TripRouteGeometry.Cache, text: @escaping Text, apply: @escaping Apply
    ) {
        let stepped = RouteRepairFlow.steps(
            RouteRepair.failingSpans(train: train, gaps: statusGaps), in: train)
        repaired = 0
        gaps = []
        summary = nil
        pause = nil
        expected = train
        working = stepped.train
        run(steps: stepped.steps, package: package, geometry: geometry, text: text, apply: apply)
    }

    /// The splice choosing `choice` would make, for a removal confirmation.
    func plan(for choice: RailwayRouteChoices.Choice) -> RailwayRouteEditing.Plan? {
        guard let pause, let working else { return nil }
        return RailwayRouteEditing.plan(
            train: RailwayRouteEditing.preparing(working), choice: choice,
            fromVisitID: pause.fromVisitID, toVisitID: pause.toVisitID)
    }

    /// Applies one of the paused span's choices, then continues the run.
    func choose(
        _ choice: RailwayRouteChoices.Choice, package: CompactPackage,
        geometry: TripRouteGeometry.Cache, text: @escaping Text, apply: @escaping Apply
    ) {
        guard let pause, !isRunning, let expected, let working else { return }
        self.pause = nil
        if let plan = plan(for: choice, pause: pause, in: working) {
            guard apply(expected, plan.updatedTrain) else { return interrupted(text) }
            self.expected = plan.updatedTrain
            self.working = plan.updatedTrain
            repaired += 1
        } else {
            gaps.append(gapName(pause, in: working))
        }
        run(steps: pause.remaining, package: package, geometry: geometry, text: text, apply: apply)
    }

    /// Leaves the paused span as it is and continues with the next one.
    func skip(
        package: CompactPackage, geometry: TripRouteGeometry.Cache,
        text: @escaping Text, apply: @escaping Apply
    ) {
        guard let pause, !isRunning, let working else { return }
        self.pause = nil
        gaps.append(gapName(pause, in: working))
        run(steps: pause.remaining, package: package, geometry: geometry, text: text, apply: apply)
    }

    private func plan(
        for choice: RailwayRouteChoices.Choice, pause: Pause, in train: Train
    ) -> RailwayRouteEditing.Plan? {
        RailwayRouteEditing.plan(
            train: RailwayRouteEditing.preparing(train), choice: choice,
            fromVisitID: pause.fromVisitID, toVisitID: pause.toVisitID)
    }

    func cancel() {
        task?.cancel()
        task = nil
        isRunning = false
        pause = nil
    }

    private func run(
        steps: [RouteRepairFlow.Step], package: CompactPackage,
        geometry cache: TripRouteGeometry.Cache, text: @escaping Text, apply: @escaping Apply
    ) {
        guard let train = working else { return }
        task?.cancel()
        isRunning = true
        task = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) { () throws -> (RouteRepairFlow.Advance, [[TripRouteGeometry.Piece]]) in
                let context = try loadJourneyAdmissionContext(
                    rideDate: Dates.normalizeDateString(train.date), package: package)
                let aliases = try loadJourneyStationAliases(
                    for: train.stops.compactMap(\.n02StationCode), package: package)
                let advance = RouteRepairFlow.advance(
                    train: train, package: package, aliases: aliases, steps: steps,
                    admissionContext: context)
                let geometry = advance.pause?.choices.prefix(JourneyEditorView.maximumDrawnRoutes).map {
                    TripRouteGeometry.pieces(for: $0, cache: cache)
                }.map(Array.init) ?? []
                return (advance, geometry)
            }
            let outcome: (RouteRepairFlow.Advance, [[TripRouteGeometry.Piece]])
            do {
                outcome = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: { worker.cancel() }
            } catch is CancellationError {
                return
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.isRunning = false
                self.summary = error.localizedDescription
                return
            }
            guard let self, !Task.isCancelled, let expected = self.expected else { return }
            let (advance, geometry) = outcome
            self.isRunning = false
            // Only a real route change reaches the draft; a run that fixed
            // nothing leaves the record exactly as it was opened.
            if advance.train != train {
                guard apply(expected, advance.train) else { return self.interrupted(text) }
                self.expected = advance.train
            }
            self.working = advance.train
            self.repaired += advance.repaired
            self.gaps += advance.gaps
            if let paused = advance.pause, !paused.choices.isEmpty {
                self.pause = Pause(
                    fromVisitID: paused.fromVisitID, toVisitID: paused.toVisitID,
                    choices: paused.choices, geometry: geometry, remaining: paused.remaining)
            }
            self.summary = RouteRepairFlow.summary(
                repaired: self.repaired, needsChoice: self.pause == nil ? 0 : 1,
                gaps: self.gaps, text: text)
        }
    }

    private func interrupted(_ text: Text) {
        cancel()
        summary = text("ios.journey.repairInterrupted", [:])
    }

    private func gapName(_ pause: Pause, in train: Train) -> RouteRepairFlow.GapName {
        RouteRepairFlow.GapName(
            from: train.stops.first { $0.routeEditing?.visitID == pause.fromVisitID }?.name ?? "",
            to: train.stops.first { $0.routeEditing?.visitID == pause.toVisitID }?.name ?? "")
    }
}
