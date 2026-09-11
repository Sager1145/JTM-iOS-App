/// Camera intent outlives a map view. Recreating a renderer or restoring a
/// selection cannot manufacture another request to move the reader's camera.
public struct MapCameraPolicy: Sendable {
    public enum FocusTarget: Equatable, Sendable {
        case journey(String)
        case date(String)
    }

    public struct FocusRequest: Equatable, Sendable {
        public let target: FocusTarget
        fileprivate let revision: UInt64
    }

    public private(set) var hasOpened = false
    public private(set) var readerOwnsCamera = false
    private var revision: UInt64 = 0
    private var pendingFocus: FocusRequest?

    public var pendingFocusRequest: FocusRequest? { pendingFocus }

    public init() {}

    /// Gestures, keyboard zoom, location requests and explicit framing all
    /// supersede launch framing and any automatic move queued before them.
    public mutating func claimCamera() {
        readerOwnsCamera = true
        cancelFocus()
    }

    public mutating func cancelFocus() {
        revision &+= 1
        pendingFocus = nil
    }

    @discardableResult
    public mutating func openAtLaunch() -> Bool {
        guard !hasOpened, !readerOwnsCamera else { return false }
        hasOpened = true
        return true
    }

    @discardableResult
    public mutating func requestFocus(
        _ target: FocusTarget, enabled: Bool, playbackIsActive: Bool
    ) -> FocusRequest? {
        // Even a disabled request invalidates an older, queued selection.
        cancelFocus()
        guard enabled, !playbackIsActive else { return nil }
        readerOwnsCamera = true
        let request = FocusRequest(target: target, revision: revision)
        pendingFocus = request
        return request
    }

    /// Consume on the next render update, even if geometry is unavailable.
    /// A later route solve must not become a delayed navigation command.
    public mutating func takeFocusRequest() -> FocusRequest? {
        defer { pendingFocus = nil }
        return pendingFocus
    }

    public func isCurrent(_ request: FocusRequest) -> Bool {
        request.revision == revision
    }
}
