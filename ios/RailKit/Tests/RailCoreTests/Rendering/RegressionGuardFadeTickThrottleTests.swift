import Foundation
import RailTestSupport
import Testing
@testable import RailCore

/// Opacity fades mark every renderer dirty per display tick. They are capped
/// at 60 Hz so a 120 Hz display does not double the dirty marks per fade.
@Suite("RegressionGuardFadeTickThrottle")
struct RegressionGuardFadeTickThrottle {
    private func admitted(rate: Double, duration: TimeInterval) -> Int {
        var throttle = FadeTickThrottle()
        var count = 0
        var t = 1000.0
        let end = t + duration
        while t <= end {
            if throttle.admit(t) { count += 1 }
            t += 1 / rate
        }
        return count
    }

    @Test("a 0.3 s fade admits at most 20 ticks at any refresh rate")
    func capsTicksPerFade() {
        for rate in [60.0, 90, 120] {
            let n = admitted(rate: rate, duration: 0.3)
            #expect(n <= 20, "rate \(rate) admitted \(n)")
            // 90 Hz drops to every other tick (45 Hz) by this rule alone; the
            // link's own 60 Hz range keeps real devices nearer the cap.
            #expect(n >= (rate == 90 ? 13 : 17), "rate \(rate) admitted only \(n)")
        }
    }

    @Test("true 60 Hz ticks with jitter are all admitted")
    func sixtyHzUntouched() {
        var throttle = FadeTickThrottle()
        var t = 5.0
        for i in 0..<30 {
            let ok = throttle.admit(t)
            #expect(ok, "tick \(i) dropped")
            t += 1.0 / 60 + (i.isMultiple(of: 2) ? 0.0005 : -0.0005)
        }
    }

    @Test("reset admits the next fade's first tick")
    func resetAdmitsFirstTick() {
        var throttle = FadeTickThrottle()
        let first = throttle.admit(10)
        let tooSoon = throttle.admit(10.004)
        throttle.reset()
        let afterReset = throttle.admit(10.004)
        #expect(first)
        #expect(!tooSoon)
        #expect(afterReset)
    }

    @Test("both fade links cap the frame rate and gate ticks, and skip unchanged alpha")
    func sourceGuard() throws {
        for file in ["RailMap/Map/MapOverlayStyles.swift", "RailMap/Map/RideStationOverlay.swift"] {
            let text = try SourceFiles.text(file)
            #expect(text.contains("preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60"),
                    "\(file) must cap its fade link at 60 Hz")
            #expect(text.contains("tickThrottle.admit(link.timestamp)"),
                    "\(file) must gate ticks through FadeTickThrottle")
        }
        let styles = try SourceFiles.text("RailMap/Map/MapOverlayStyles.swift")
        #expect(styles.contains("renderer.alpha != alpha"), "applyAlpha must skip an unchanged alpha")
        let ride = try SourceFiles.text("RailMap/Map/RideStationOverlay.swift")
        #expect(ride.contains("circles[update.index].alpha != update.alpha"),
                "ride fade must skip an unchanged alpha")
    }
}
