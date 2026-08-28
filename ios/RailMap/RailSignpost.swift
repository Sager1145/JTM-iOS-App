import Foundation
import os

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
    func begin(_ name: StaticString) -> OSSignpostIntervalState? {
        guard isEnabled, !RailSignpost.isSuppressed else { return nil }
        return beginInterval(name, id: makeSignpostID())
    }

    @inline(__always)
    func end(_ name: StaticString, _ state: OSSignpostIntervalState?) {
        guard let state else { return }
        endInterval(name, state)
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
