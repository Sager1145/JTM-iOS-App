import Foundation

/// A trailing debounce that costs one task per quiet period, not one per call.
///
/// Camera callbacks arrive at up to 120 Hz. Cancelling and re-creating a
/// sleeping `Task` on each of them allocated two tasks per frame; here a call
/// only moves the deadline forward, and the single running task sleeps again
/// until the latest deadline has passed before it fires the latest action.
@MainActor
final class MapDeadlineTimer {
    private let delay: Duration
    private var deadline: ContinuousClock.Instant?
    private var action: (@MainActor () -> Void)?
    private var task: Task<Void, Never>?

    init(delay: Duration) {
        self.delay = delay
    }

    var isScheduled: Bool { task != nil }

    /// Fires `action` once `delay` has passed with no further call. A later
    /// call replaces the pending action and extends the deadline.
    func schedule(_ action: @escaping @MainActor () -> Void) {
        deadline = .now + delay
        self.action = action
        guard task == nil else { return }
        task = Task { @MainActor [weak self] in
            while true {
                guard let deadline = self?.deadline else { return }
                let remaining = deadline - .now
                if remaining <= .zero { break }
                do { try await Task.sleep(for: remaining) } catch { return }
            }
            guard let self, !Task.isCancelled else { return }
            let action = self.action
            self.task = nil
            self.deadline = nil
            self.action = nil
            action?()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        deadline = nil
        action = nil
    }
}
