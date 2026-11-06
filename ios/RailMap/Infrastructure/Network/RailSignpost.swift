import Foundation
import os
#if DEBUG
import RailCore
#endif

/// The app's one signpost surface.
///
/// ## Why this exists rather than `NSLog` or a `#if DEBUG` timer
///
/// The map rebuild already carried a `DEBUG`-only `NSLog`, and its own comment
/// says why it is gated: `NSLog` formats, takes a lock and writes to both the
/// unified log and stderr, on the calling thread, before the frame it belongs
/// to can be presented. That makes it useless for the thing most worth
/// measuring — a **release** build on a device, during a gesture.
///
/// `OSSignposter` is the opposite trade. When no tool is recording,
/// `isEnabled` is false and a begin/end pair is a load, a branch and a
/// return with no log write at all; Instruments is what turns the writes on.
/// So the instrumentation ships, and "how long does a rebuild take on this
/// phone" stops needing a special build.
///
/// ## Recording one
///
///     xcrun xctrace record --template 'Blank' --instrument 'os_signpost' \
///         --device-name '<device>' --attach RailMap --output map.trace
///
/// then filter on the subsystem below. `RAILMAP_SIGNPOSTS=0` in the
/// environment switches every interval off even while a tool is recording,
/// which is how the instrumentation's own cost is measured without building
/// the app twice.
///
/// ## The one rule for callers
///
/// **Never format on a hot path.** The message argument is an
/// `OSLogMessage`, whose interpolations are only evaluated while a tool is
/// recording — but only when they are written as interpolations. `"\(count)"`
/// inside the literal is free; `String(count)` outside it is not.
enum RailSignpost {

    static let subsystem = "com.jtm.railmap"

    /// The map: rebuild, restyle, tap resolution, playback frames.
    static let map = OSSignposter(subsystem: subsystem, category: "map")
    /// Loading and solving: packages, route cache, dataset parts, the solver.
    static let data = OSSignposter(subsystem: subsystem, category: "data")
    /// The interface: list filtering, derived snapshots, search.
    static let ui = OSSignposter(subsystem: subsystem, category: "ui")
    /// Long jobs the reader watches a progress bar for: OCR, video export,
    /// statistics.
    static let jobs = OSSignposter(subsystem: subsystem, category: "jobs")

    /// Whether intervals are emitted at all.
    ///
    /// Two gates rather than one. `isEnabled` is the tool's, and is
    /// what keeps the cost at zero in ordinary use. This one is ours, so the
    /// same build can be recorded twice — once with the instrumentation live
    /// and once without — and the difference attributed to the
    /// instrumentation itself rather than assumed to be zero.
    static let isSuppressed: Bool =
        ProcessInfo.processInfo.environment["RAILMAP_SIGNPOSTS"] == "0"
}

#if DEBUG
/// DEBUG: the Instruments interval plus its in-process recording
/// (`SignpostRecorder`, shown by the developer panel). Release keeps the
/// bare `OSSignpostIntervalState`, so nothing changes there.
struct RailSignpostInterval {
    var state: OSSignpostIntervalState?
    var recorded: SignpostRecorder.Token?
}
#else
typealias RailSignpostInterval = OSSignpostIntervalState
#endif

extension OSSignposter {

    /// Open an interval, or answer `nil` when nothing is listening.
    ///
    /// Paired with ``end(_:_:)`` through `defer`, which is deliberate: an
    /// interval left open is not a missing measurement, it is a measurement
    /// that swallows everything after it, and `defer` is the one spelling that
    /// survives every early `return` a `guard` can take.
    ///
    ///     let interval = RailSignpost.map.begin("map.rebuild")
    ///     defer { RailSignpost.map.end("map.rebuild", interval) }
    @inline(__always)
    func begin(_ name: StaticString) -> RailSignpostInterval? {
#if DEBUG
        let recorded = SignpostRecorder.shared.begin(name)
        let state = isEnabled && !RailSignpost.isSuppressed ? beginInterval(name, id: makeSignpostID()) : nil
        guard state != nil || recorded != nil else { return nil }
        return RailSignpostInterval(state: state, recorded: recorded)
#else
        guard isEnabled, !RailSignpost.isSuppressed else { return nil }
        return beginInterval(name, id: makeSignpostID())
#endif
    }

    @inline(__always)
    func end(_ name: StaticString, _ interval: RailSignpostInterval?) {
#if DEBUG
        guard let interval else { return }
        SignpostRecorder.shared.end(interval.recorded)
        if let state = interval.state { endInterval(name, state) }
#else
        guard let state = interval else { return }
        endInterval(name, state)
#endif
    }

    /// An interval the tools treat as an animation: Instruments' Animation
    /// Hitches and XCTest's `XCTOSSignpostMetric` count the frames dropped
    /// inside it. For gestures the reader watches frame by frame, such as
    /// the docked card's header drag. Ended with ``end(_:_:)`` like any other.
    @inline(__always)
    func beginAnimation(_ name: StaticString) -> RailSignpostInterval? {
#if DEBUG
        let recorded = SignpostRecorder.shared.begin(name)
        let state = isEnabled && !RailSignpost.isSuppressed ? beginAnimationInterval(name, id: makeSignpostID()) : nil
        guard state != nil || recorded != nil else { return nil }
        return RailSignpostInterval(state: state, recorded: recorded)
#else
        guard isEnabled, !RailSignpost.isSuppressed else { return nil }
        return beginAnimationInterval(name, id: makeSignpostID())
#endif
    }

    /// A count rather than a duration — how many overlays a rebuild produced,
    /// how many vertices a tap had to project.
    @inline(__always)
    func mark(_ name: StaticString, _ value: Int) {
        guard isEnabled, !RailSignpost.isSuppressed else { return }
        emitEvent(name, "\(value)")
    }

    @inline(__always)
    func mark(_ name: StaticString, _ first: Int, _ second: Int) {
        guard isEnabled, !RailSignpost.isSuppressed else { return }
        emitEvent(name, "\(first) \(second)")
    }
}
