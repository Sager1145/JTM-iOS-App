import Foundation
import RailCore

/// Seed for the resident journey editor. Edit keeps the id `replace` must target.
struct JourneyEditorLaunch: Identifiable {
    let id = UUID()
    var train: Train
    var isNew: Bool
    var originalID: String?
    /// Open in route repair: the card's Repair route lands here.
    var repairsRoute = false
}

