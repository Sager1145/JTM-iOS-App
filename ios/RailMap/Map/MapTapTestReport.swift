#if DEBUG
import RailPresentation

/// What `RailMapController.answerTapForUITest` measured and answered at a view
/// point, for the app-control `tapMap` command.
struct MapTapTestReport {
    var answer: MapTapAnswer
    var hits: MapTapHits
    /// A double tap dropped the station or line answer the first tap banked.
    var cancelledByDoubleTap = false
}
#endif
