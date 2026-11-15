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
    /// A framing animation started by a focus request is still running.
    public private(set) var focusFitRunning = false
    private var revision: UInt64 = 0
    private var pendingFocus: FocusRequest?

    /// Passive viewport restoration must not overwrite a newer camera intent.
    public var intentRevision: UInt64 { revision }

    public var pendingFocusRequest: FocusRequest? { pendingFocus }

    public init() {}

    /// Gestures, keyboard zoom, location requests and explicit framing all
    /// supersede launch framing and any automatic move queued before them.
    /// Returns whether a running focus fit must be stopped.
    @discardableResult
    public mutating func claimCamera() -> Bool {
        readerOwnsCamera = true
        return cancelFocus()
    }

    /// Returns whether a running focus fit must be stopped: it belongs to an
    /// older request than whatever just cancelled focus.
    @discardableResult
    public mutating func cancelFocus() -> Bool {
        revision &+= 1
        pendingFocus = nil
        defer { focusFitRunning = false }
        return focusFitRunning
    }

    /// A focus request's own fit starts. Call after the fit has been issued:
    /// issuing it claims the camera first, which stops any OLDER fit but
    /// never this one.
    public mutating func beginFocusFit() { focusFitRunning = true }

    /// The framing animation ended (the map reported its settled region).
    public mutating func endFocusFit() { focusFitRunning = false }

    @discardableResult
    public mutating func openAtLaunch() -> Bool {
        guard !hasOpened, !readerOwnsCamera else { return false }
        hasOpened = true
        revision &+= 1
        return true
    }

    @discardableResult
    public mutating func requestFocus(
        _ target: FocusTarget, enabled: Bool, playbackIsActive: Bool
    ) -> FocusRequest? {
        // Even a disabled request invalidates an older, queued selection and
        // an older fit still animating (read `focusFitRunning` first to stop it).
        cancelFocus()
        guard enabled, !playbackIsActive else { return nil }
        readerOwnsCamera = true
        let request = FocusRequest(target: target, revision: revision)
        pendingFocus = request
        return request
    }

    /// Consume when framing commits. A direct journey pick can wait for route
    /// geometry; newer camera intent cancels it while that geometry loads.
    public mutating func takeFocusRequest() -> FocusRequest? {
        defer { pendingFocus = nil }
        return pendingFocus
    }

    public func isCurrent(_ request: FocusRequest) -> Bool {
        request.revision == revision
    }
}
