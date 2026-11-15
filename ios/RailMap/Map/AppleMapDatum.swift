import Foundation
import os
import RailCore

/// Converts source WGS84 geometry into the datum used by Apple's basemap.
///
/// Which datum that is depends on the MapKit service the device is served,
/// not on the country being drawn. On the China service Taiwan, Hong Kong,
/// Macao and Korea came back with the GCJ-02 displacement: a direct lookup on
/// 2026-08-25 placed Barra station at 113.534528, 22.180786 against its DSCC
/// WGS84 anchor 113.529427, 22.183681 (the conversion below lands 4.6 m from
/// MapKit instead of 625 m). On the global service the same lookups come back
/// in WGS84: on 2026-09-17, 26 Taiwan Railway stations matched their package
/// anchors with a 35 m median residual and the GCJ-02 shift moved them to a
/// 500 m median — the whole Taiwanese network drawn half a kilometre off the
/// basemap's track. Hong Kong (26–110 m against 490–640 m), Macao (Barra 39 m,
/// Cotai East 9 m) and Korea read the same way.
///
/// So the shift is a per-device decision, taken by `AppleMapDatumProbe` from
/// MapKit's own answers and persisted here. The rail packages remain WGS84 —
/// they are also consumed by the WebUI — so whichever datum wins is applied at
/// the native presentation boundary rather than in the packages or `RailCore`.
/// Japan is never a candidate.
nonisolated enum AppleMapDatum {
    /// The regions whose Apple basemap can be served in GCJ-02.
    static let candidateCountries: Set<String> = GCJ02.candidateRegions

    /// Where the probe's last verdict is kept. Unset means no verdict yet,
    /// which draws WGS84 — the datum of the global service.
    static let defaultsKey = "AppleMapDatum.gcj02Countries"

    private static let scope = OSAllocatedUnfairLock<Set<String>>(
        initialState: persistedScope())

    /// The regions currently drawn with the GCJ-02 displacement.
    static var gcj02Countries: Set<String> { scope.withLock { $0 } }

    /// Whether the probe has ever finished on this device, verdict or not.
    /// Only the very first launch waits for it.
    static var hasProbed: Bool {
        UserDefaults.standard.bool(forKey: probedKey)
    }

    private static let probedKey = "AppleMapDatum.probed"

    /// Records the probe's verdict for the NEXT build of the map: what is
    /// already drawn stays in one datum. `nil` records only that it ran.
    static func adopt(gcj02Countries next: Set<String>?) {
        UserDefaults.standard.set(true, forKey: probedKey)
        guard let next else { return }
        UserDefaults.standard.set(
            next.intersection(candidateCountries).sorted(), forKey: defaultsKey)
    }

    /// Applies the saved verdict. Called once, before anything is drawn.
    static func applySavedVerdict() {
        let saved = persistedScope()
        scope.withLock { $0 = saved }
    }

    private static func persistedScope() -> Set<String> {
        let stored = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        return Set(stored).intersection(candidateCountries)
    }

    static func display(_ coordinate: Coordinate, country: String) -> Coordinate {
        guard gcj02Countries.contains(country) else { return coordinate }
        return gcj02(fromWGS84: coordinate)
    }

    static func display(_ coordinates: [Coordinate], country: String) -> [Coordinate] {
        guard gcj02Countries.contains(country) else { return coordinates }
        return coordinates.map(gcj02(fromWGS84:))
    }

    /// The public GCJ-02 forward transform used by Chinese digital maps. The body lives in
    /// `RailCore.GCJ02`, so the host-side bake applies the very same shift.
    static func gcj02(fromWGS84 coordinate: Coordinate) -> Coordinate {
        GCJ02.fromWGS84(coordinate)
    }
}
