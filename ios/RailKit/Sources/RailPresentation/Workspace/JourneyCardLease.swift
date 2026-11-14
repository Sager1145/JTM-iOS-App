import Foundation

/// The selection a journey card took over, and what it replaced. The card may
/// hand the previous selection back on close only while nothing else has
/// claimed it since.
public struct JourneyCardLease: Equatable, Sendable {
    /// The journey whose card currently owns the selection.
    public var owner: String
    public var previous: String?
    public var revision: Int

    public init(owner: String, previous: String?, revision: Int) {
        self.owner = owner
        self.previous = previous
        self.revision = revision
    }

    /// Whether dismissing a sheet hands the selection back. Switching from
    /// one journey card to another dismisses the first while the successor is
    /// already presented: the successor owns the lease, so nothing is
    /// restored. The editor, when open, claims the selection too.
    public static func restoresOnDismiss(presentedDetail: String?, editorOpen: Bool) -> Bool {
        presentedDetail == nil && !editorOpen
    }
}
