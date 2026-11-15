import Foundation

/// Trips are not held back by the network level. When the view outgrows the
/// area trips were last built for, trips are extended at the installed level
/// over the camera's padded rect. Pure and map-free.
public enum TripAreaExtension {
    public typealias Rect = MapBuildArea.Rect

    /// The union of `installed` and `cameraPadded`, or nil when `installed`
    /// already contains `cameraPadded`.
    public static func area(installed: Rect, cameraPadded: Rect) -> Rect? {
        let eps = 1e-9
        let contained = installed.x <= cameraPadded.x + eps
            && installed.y <= cameraPadded.y + eps
            && installed.x + installed.width >= cameraPadded.x + cameraPadded.width - eps
            && installed.y + installed.height >= cameraPadded.y + cameraPadded.height - eps
        guard !contained else { return nil }
        let minX = min(installed.x, cameraPadded.x)
        let minY = min(installed.y, cameraPadded.y)
        let maxX = max(installed.x + installed.width, cameraPadded.x + cameraPadded.width)
        let maxY = max(installed.y + installed.height, cameraPadded.y + cameraPadded.height)
        return Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Whether an extension pass is due; same cadence as the moving load pass.
    public static func isDue(now: Double, last: Double?) -> Bool {
        MapLoadAhead.isDue(now: now, lastPass: last)
    }
}
