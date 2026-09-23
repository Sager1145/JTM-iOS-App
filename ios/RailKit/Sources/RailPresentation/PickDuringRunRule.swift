import Foundation

/// What a reader's pick of a journey does to a run that is on screen.
///
/// The web app's `Playback.notifyExternalRender`, narrowed to its selection
/// half: a selection the reader makes while a run is on screen stops the run,
/// and stops it WITHOUT restoring the selection the run interrupted — the
/// reader has just said which journey they want, and putting an earlier one
/// back would answer them with something else. An ended run counts: it keeps
/// its last frame on the map until the reader stops it, and a pick is the
/// reader moving on from it.
///
/// A run being filmed is the one run a pick does not end. Nothing stops a
/// finger reaching the map or the list while a film records, and a tap that
/// discarded ninety seconds of recording with no way back would be a
/// destructive act done by accident. The pick is declined whole rather than
/// half-applied: a selection written under a run is overwritten at the next
/// hand-off anyway, so writing it would only be a flicker.
public enum PickDuringRunRule {
    public enum Outcome: Equatable, Sendable {
        /// No run is on screen; the pick is an ordinary pick.
        case proceed
        /// Stop the run, keep no selection to restore, then pick.
        case stopRunThenProceed
        /// A film is recording; do nothing.
        case decline
    }

    /// - Parameters:
    ///   - runOnScreen: A run in progress, or one that has ended and is
    ///     keeping its last frame until the reader stops it.
    ///   - filming: Whether the run is being recorded to a video.
    public static func resolve(runOnScreen: Bool, filming: Bool) -> Outcome {
        guard runOnScreen else { return .proceed }
        return filming ? .decline : .stopRunThenProceed
    }
}
