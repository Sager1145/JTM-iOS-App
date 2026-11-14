import Foundation
import Testing

@testable import RailPresentation

/// Map-lock run 3 guards: the landing rule works while zooming OUT (the old
/// rule only ever installed on the way in), the matching debounce skips a
/// load's final publish, and the ride-stroke split keeps shared work together.
struct MapLockLandingAndScheduleTests {
    // MARK: - landing rule, both directions

    private enum Rule { case readyAtCurrentPaddedRect, landingInstall }

    /// Width of the visible map at `zoom`, in arbitrary units.
    private static func visibleWidth(_ zoom: Double) -> Double { pow(2, -zoom) }

    /// A preparation covers the padded rect (visible plus half a screen each
    /// side, so twice the visible width) the camera had when it started; it
    /// takes longer the further out the camera is.
    private static func steps(startZoom: Double) -> Int { startZoom >= 8 ? 2 : 3 }

    /// Moves the camera from `from` to `to` in quarter steps, one preparation
    /// at a time, then rests. Returns the levels installed WHILE the camera
    /// moved and the level installed at the end.
    private func run(from: Double, to: Double, rule: Rule) -> (whileMoving: [Int], final: Int) {
        let direction: Double = to < from ? -1 : 1
        let moveSteps = Int(abs(to - from) / 0.25)
        var installed = GeometryZoomLevels.nearestLevel(zoom: from)
        var whileMoving: [Int] = []
        var inFlight: (level: Int, startZoom: Double, remaining: Int)?
        for step in 0..<(moveSteps + 20) {
            let moving = step <= moveSteps
            let zoom = from + direction * 0.25 * Double(min(step, moveSteps))
            if let flight = inFlight {
                if flight.remaining == 0 {
                    inFlight = nil
                    let wanted = GeometryZoomLevels.wantedLevel(zoom: zoom, installed: installed)
                    // The old test: ready against the CURRENT camera's padded rect.
                    let paddedReady = 2 * Self.visibleWidth(flight.startZoom) >= 2 * Self.visibleWidth(zoom) - 1e-12
                    let covers = 2 * Self.visibleWidth(flight.startZoom) >= Self.visibleWidth(zoom) - 1e-12
                    var install = false
                    switch rule {
                    case .readyAtCurrentPaddedRect:
                        install = (flight.level == wanted && paddedReady)
                            || GeometryZoomLevels.installsLanded(
                                landed: flight.level, installed: installed, zoom: zoom, ready: paddedReady)
                    case .landingInstall:
                        let wantedReady = flight.level == wanted && paddedReady
                        install = wantedReady
                            || GeometryZoomLevels.landingInstall(
                                landed: flight.level, installed: installed, zoom: zoom,
                                wantedReady: false, landedUsable: covers) == .installLanded
                    }
                    if install, flight.level != installed {
                        installed = flight.level
                        if moving { whileMoving.append(installed) }
                    }
                } else {
                    inFlight = (flight.level, flight.startZoom, flight.remaining - 1)
                }
            }
            if inFlight == nil {
                let wanted = GeometryZoomLevels.wantedLevel(zoom: zoom, installed: installed)
                if wanted != installed { inFlight = (wanted, zoom, Self.steps(startZoom: zoom)) }
            }
        }
        return (whileMoving, installed)
    }

    @Test func zoomingOutInstallsSteadilyUnderTheLandingRule() {
        let new = run(from: 12.25, to: 5, rule: .landingInstall)
        #expect(new.whileMoving.count >= 5, "installs while moving: \(new.whileMoving)")
        #expect(zip(new.whileMoving, new.whileMoving.dropFirst()).allSatisfy { $0 > $1 })
        #expect(new.final == GeometryZoomLevels.nearestLevel(zoom: 5))
    }

    @Test func theOldRuleInstallsNothingWhileZoomingOut() {
        let old = run(from: 12.25, to: 5, rule: .readyAtCurrentPaddedRect)
        #expect(old.whileMoving.isEmpty, "the old rule installed \(old.whileMoving)")
    }

    @Test func zoomingInStillInstallsSteadilyUnderBothRules() {
        for rule in [Rule.readyAtCurrentPaddedRect, .landingInstall] {
            let result = run(from: 5, to: 12.25, rule: rule)
            #expect(result.whileMoving.count >= 3, "\(rule): \(result.whileMoving)")
            #expect(zip(result.whileMoving, result.whileMoving.dropFirst()).allSatisfy { $0 < $1 })
            #expect(result.final == GeometryZoomLevels.nearestLevel(zoom: 12.25))
        }
    }

    @Test func landingInstallNeedsAnUnreadyWantedLevelAndAUsableNearerLanding() {
        // Camera z8.75; installed 14 (z7); landed 16 (z8).
        func decide(wantedReady: Bool, usable: Bool, landed: Int = 16, installed: Int? = 14) -> GeometryZoomLevels.LandingInstall {
            GeometryZoomLevels.landingInstall(
                landed: landed, installed: installed, zoom: 8.75, wantedReady: wantedReady, landedUsable: usable)
        }
        #expect(decide(wantedReady: false, usable: true) == .installLanded)
        #expect(decide(wantedReady: true, usable: true) == .ordinary)
        #expect(decide(wantedReady: false, usable: false) == .ordinary)
        #expect(decide(wantedReady: false, usable: true, landed: 14) == .ordinary)
        #expect(decide(wantedReady: false, usable: true, landed: 12) == .ordinary)
        #expect(decide(wantedReady: false, usable: true, installed: nil) == .ordinary)
    }

    @Test func followUpRebuildHasItsOwnTrigger() {
        #expect(MapRebuildTrigger.wantedLevelFollowUp.rawValue == 12)
        #expect(Set(MapRebuildTrigger.allCases.map(\.rawValue)).count == MapRebuildTrigger.allCases.count)
    }

    // MARK: - matching schedule

    @Test func aLoadsFinalPublishStartsMatchingAtOnce() {
        // Inside a burst: the debounce applies...
        #expect(MatchingSchedule.decide(sinceLastRequest: 0.7, sinceBurstStart: 1, loadJustFinished: false) == .after(seconds: 1))
        // ...except for the final publish.
        #expect(MatchingSchedule.decide(sinceLastRequest: 0.7, sinceBurstStart: 1, loadJustFinished: true) == .now)
    }

    @Test func theDebounceRulesAreUnchangedOtherwise() {
        #expect(MatchingSchedule.decide(sinceLastRequest: nil, sinceBurstStart: nil, loadJustFinished: false) == .now)
        #expect(MatchingSchedule.decide(sinceLastRequest: 1.5, sinceBurstStart: 2, loadJustFinished: false) == .now)
        #expect(MatchingSchedule.decide(sinceLastRequest: 1.4, sinceBurstStart: 4.5, loadJustFinished: false) == .after(seconds: 0.5))
        #expect(MatchingSchedule.decide(sinceLastRequest: 1.4, sinceBurstStart: 6, loadJustFinished: false) == .after(seconds: 0))
    }

    // MARK: - ride build partition

    @Test func partitionKeepsShareKeysTogetherAndEveryIndexOnce() {
        let keys: [String?] = (0..<1_000).map { $0 % 3 == 0 ? nil : "k\($0 % 40)" }
        let parts = RideBuildPartition.partition(shareKeys: keys, maxParts: 4)
        #expect(parts.count == 4)
        #expect(parts.flatMap { $0 }.sorted() == Array(0..<1_000))
        for part in parts { #expect(part == part.sorted()) }
        var owner: [String: Int] = [:]
        for (partIndex, part) in parts.enumerated() {
            for index in part {
                guard let key = keys[index] else { continue }
                #expect(owner[key, default: partIndex] == partIndex, "key \(key) split across parts")
                owner[key] = partIndex
            }
        }
        // Balanced to within the largest shared group.
        let sizes = parts.map(\.count)
        #expect((sizes.max() ?? 0) - (sizes.min() ?? 0) <= 40)
    }

    @Test func smallBatchesStayOnOneThread() {
        let keys: [String?] = Array(repeating: nil, count: RideBuildPartition.minimumPerPart * 2 - 1)
        #expect(RideBuildPartition.partition(shareKeys: keys, maxParts: 4).count == 1)
        #expect(RideBuildPartition.partition(shareKeys: [], maxParts: 4).isEmpty)
    }

    @Test func partitionIsDeterministic() {
        let keys: [String?] = (0..<500).map { "k\($0 % 17)" }
        #expect(RideBuildPartition.partition(shareKeys: keys, maxParts: 3)
            == RideBuildPartition.partition(shareKeys: keys, maxParts: 3))
    }
}
