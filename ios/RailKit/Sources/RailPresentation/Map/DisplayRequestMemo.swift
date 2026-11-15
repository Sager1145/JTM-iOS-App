import Foundation

/// Remembers the last camera request the display store answered so an
/// identical one is skipped. `ensure(regionsIntersecting:cameraZoom:)` runs on
/// every rebuild and every moving-load pass; asked again for the same rect and
/// zoom with nothing resident, loading or failed having changed since, it
/// recomputes the whole needed set only to conclude the same thing.
///
/// `epoch` counts everything that can change that answer: a batch completing
/// or being cancelled, eviction, held-line changes, failures and resets.
public struct DisplayRequestMemo: Equatable, Sendable {
    private struct Key: Equatable, Sendable {
        var x: Double, y: Double, width: Double, height: Double
        var cameraZoom: Double
        var epoch: Int
    }

    private var last: Key?

    public init() {}

    /// True when the request equals the previous answered one. Otherwise the
    /// request is recorded as answered and false is returned.
    public mutating func shouldSkip(
        x: Double, y: Double, width: Double, height: Double, cameraZoom: Double, epoch: Int
    ) -> Bool {
        let key = Key(x: x, y: y, width: width, height: height, cameraZoom: cameraZoom, epoch: epoch)
        if last == key { return true }
        last = key
        return false
    }

    public mutating func reset() { last = nil }
}
