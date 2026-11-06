import Foundation
import RailCore

// RegionClock itself lives in RailCore (`Utilities/RegionClock.swift`), where
// `Statistics` shares it. Only the presentation-tier naming stays here.

extension RegionClock {
    /// The zone's name as the interface should print it.
    public var name: PresentationText {
        PresentationText(key: nameKey, fallback: fallbackName)
    }
}
