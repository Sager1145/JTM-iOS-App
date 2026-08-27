/// Level-of-detail policy for the stations attached to a recorded journey.
///
/// Network stations already derive their visibility from line density in
/// ``Visibility/stationMinZoom(lineMinZoom:totalKm:stationCount:)``. Journey
/// markers use the local-service timing for every train type, so a Shinkansen,
/// limited express and rapid service declutter at the same scale as an ordinary
/// train. Station spacing still adjusts that shared floor locally.
public enum RideMarkerVisibility {
    /// The MapLibre zoom at which a marker starts drawing, or `nil` when it is
    /// a journey boundary and therefore remains visible at every scale.
    ///
    /// `densityMinZoom` comes from the same 22-pixel station-spacing ladder as
    /// the network. It is applied as a bounded adjustment instead of an
    /// absolute floor. `trainType` and `country` remain in the interface so the
    /// invariant that every service uses the same timing can be tested directly.
    public static func minimumMapLibreZoom(
        role: String,
        trainType: String?,
        country: String,
        densityMinZoom: Int
    ) -> Double? {
        if role == "terminal" || role == "xday" { return nil }

        // Deliberately independent of `trainType` and `country`: these are the
        // previous local-service floors, now shared by every service.
        let base = role == "pass" ? 10.5 : 8.5

        let densityAdjustment = min(2.5, max(0, Double(densityMinZoom - 8) * 0.5))
        return base + densityAdjustment
    }

}
