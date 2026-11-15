import Foundation

/// How the map answers a selection change: from state the last rebuild
/// already cached, or with a full rebuild.
///
/// A deselection, and a pick of the ride already drawn standalone, only
/// change paint. A new pick also needs that ride's cores and casings built
/// and the previous standalone ride returned to its batch, which is only
/// possible when its whole route is already cached in the installed frame and
/// the ride batches are still the ones that frame drew.
public enum SelectionApplyPlan: Equatable, Sendable {
    /// Answer in place. `rebatch` is true when the pick moves a ride out of
    /// its batch (and the previous standalone ride back into one).
    case selectionOnly(rebatch: Bool)
    case rebuild

    /// - Parameters:
    ///   - selected: the new selection.
    ///   - standalone: the ride the installed overlays draw standalone.
    ///   - routeAvailableInFrame: every drawable segment of the selected ride
    ///     has its polyline cached in the installed frame, or is known to
    ///     build to nothing there (the whole route, not only the part inside
    ///     the built rect).
    ///   - batchCacheCurrent: the batch cache is the one the installed frame
    ///     drew, with every input unchanged but the selection.
    ///   - contextValid: the marker context and installed build are usable.
    public static func decide(
        selected: String?, standalone: String?,
        routeAvailableInFrame: Bool, batchCacheCurrent: Bool, contextValid: Bool
    ) -> SelectionApplyPlan {
        guard contextValid else { return .rebuild }
        guard let selected else { return .selectionOnly(rebatch: false) }
        if selected == standalone { return .selectionOnly(rebatch: false) }
        guard routeAvailableInFrame, batchCacheCurrent else { return .rebuild }
        return .selectionOnly(rebatch: true)
    }
}
