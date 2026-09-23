import Foundation

/// What the selected-journey card is a card OF, which is what decides when
/// the workspace takes one card down and mounts another.
///
/// A card is built when a journey is selected and taken down when it is
/// not, and its arrival is state that changes after it is mounted. So the
/// question "does choosing this journey arrive?" is the question "is this a
/// different card?", and that is the identity below.
///
/// A reader's choice is a card of that journey: choosing another one is a new
/// card, and it arrives. A run is one card for the whole run: the transport
/// hands the selection from journey to journey every few seconds, and none of
/// those is the reader choosing, so the card keeps one identity while the
/// transport is on screen and only its content moves. It arrives once when
/// the run takes the selection over and once more when stopping gives the
/// selection back.
public enum JourneyHeroIdentity: Hashable, Sendable {
    /// The card of one journey the reader chose.
    case journey(String)
    /// The one card of a run, whichever journey it is showing.
    case run

    /// - Parameters:
    ///   - selectedTrainID: The journey the card is showing.
    ///   - transportOnScreen: Whether the run's transport is on screen — a
    ///     run in progress, or one that has ended and is keeping its last
    ///     frame until the reader stops it.
    public static func resolve(selectedTrainID: String, transportOnScreen: Bool) -> Self {
        transportOnScreen ? .run : .journey(selectedTrainID)
    }
}
