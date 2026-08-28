import RailCore
import SwiftUI
import UIKit

/// One attempt at filming a playback run: the reader's choices, the recorder,
/// and the length the options sheet quotes before they commit to it.
///
/// Modelled on ``ImportFlow``, and for the same reason its note gives: the
/// store owns the journeys, and a *flow* owns one attempt at doing something
/// with them — including the attempts that are abandoned, which never produce a
/// file at all. `PlaybackController` owns the run; this owns the film of it.
///
/// ## Why the three were worth collecting
///
/// They were three `@State`s on `RailWorkspaceView` — the exporter, the
/// settings, and a bare `Double` — and nothing in the file said they belonged
/// together. The `Double` is the clearest case: `videoPlanSeconds` was written
/// at the transport bar's button and read in the options sheet, two places
/// several hundred lines apart, with no name for the fact that it is only
/// meaningful between those two moments.
///
/// The workspace keeps what this genuinely cannot know: which rectangle of
/// which `MKMapView` is being filmed, and which journeys are in scope. Those
/// are the map's and the destination's, and they arrive as arguments.
@MainActor
@Observable
final class VideoExportFlow {

    /// The recorder. Handed whole to the transport bar, which draws its state.
    let exporter = PlaybackVideoExporter()

    /// The reader's choices, and their persistence. Handed whole to the options
    /// sheet, which edits them.
    let settings = VideoExportSettings()

    /// How long the film would run, in seconds.
    ///
    /// §5.6's summary has to state a length before the reader commits to a run
    /// that takes minutes. `private(set)` because it is an answer, not a
    /// setting: it comes from the transport's own plan and nothing else may
    /// assert it.
    private(set) var plannedSeconds = 0.0

    var isRecording: Bool { exporter.isRecording }

    /// Quote a length for the run currently in scope.
    ///
    /// `estimate`, not `prepare`: this is called while a run is playing, and
    /// `prepare` freezes the queue. See ``PlaybackController/estimate(trains:rides:)``.
    func plan(
        playback: PlaybackController,
        trains: [Train],
        rides: [RiddenRouteStore.DrawnRide]
    ) {
        plannedSeconds = playback.estimate(trains: trains, rides: rides).seconds
    }

    /// Commit: persist the choices that produced this film, then record.
    ///
    /// The persist happens here rather than at the button because it is part of
    /// starting — a film the reader began is the evidence that these were the
    /// settings they meant.
    func start(
        playback: PlaybackController,
        mapView: UIView,
        filming rect: CGRect,
        trains: [Train],
        rides: [RiddenRouteStore.DrawnRide],
        reducedMotion: Bool
    ) {
        settings.persist()
        exporter.start(
            playback: playback, mapView: mapView, filming: rect,
            trains: trains, rides: rides,
            reducedMotion: reducedMotion, settings: settings)
    }

    /// Abandon the file, keep the run.
    ///
    /// The recording cannot survive the workspace leaving the screen: it
    /// captures a `MKMapView`, and one that has left renders nothing worth
    /// writing. `clearPlayback: false` is what keeps the run itself going while
    /// the file is abandoned — §5.3.5 gives Passport its own replay entry point
    /// over the same transport, so stopping the run here would kill a chase the
    /// reader walked to another destination to keep watching.
    func abandonRecording() {
        exporter.cancel(clearPlayback: false)
    }
}
