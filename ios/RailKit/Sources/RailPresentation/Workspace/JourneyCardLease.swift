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

    /// Whether dismissing a sheet hands the selection back. The lease is kept
    /// only while the presented detail is the lease's owner (switching from one
    /// journey card to another through `pick` dismisses the first while the
    /// successor, which owns the lease, is presented). A detail some other
    /// path opened does not own it, so the lease is returned. The editor, when
    /// open, claims the selection too.
    public static func restoresOnDismiss(
        presentedDetail: String?, owner: String, editorOpen: Bool
    ) -> Bool {
        presentedDetail != owner && !editorOpen
    }
}
