import RailCore

/// Seed for the resident journey editor. Edit keeps the id `replace` must target.
struct JourneyEditorLaunch {
    var train: Train
    var isNew: Bool
    var originalID: String?
}

