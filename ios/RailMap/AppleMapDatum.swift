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
/// Japan and North America are never candidates.
nonisolated enum AppleMapDatum {
    /// The regions whose Apple basemap can be served in GCJ-02.
    static let candidateCountries: Set<String> = ["tw", "hk", "mo", "kr"]

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

    /// The public GCJ-02 forward transform used by Chinese digital maps.
    /// Constants and series terms intentionally stay spelled out: replacing
    /// them with a fitted translation would align one station and drift along
    /// the rest of the network.
    static func gcj02(fromWGS84 coordinate: Coordinate) -> Coordinate {
        let longitude = coordinate.lon
        let latitude = coordinate.lat
        let semiMajorAxis = 6_378_245.0
        let eccentricitySquared = 0.00669342162296594323
        let x = longitude - 105
        let y = latitude - 35

        var latitudeOffset = transformLatitude(x: x, y: y)
        var longitudeOffset = transformLongitude(x: x, y: y)
        let radians = latitude * .pi / 180
        let sine = sin(radians)
        let magic = 1 - eccentricitySquared * sine * sine
        let squareRoot = sqrt(magic)
        latitudeOffset = latitudeOffset * 180
            / ((semiMajorAxis * (1 - eccentricitySquared))
                / (magic * squareRoot) * .pi)
        longitudeOffset = longitudeOffset * 180
            / (semiMajorAxis / squareRoot * cos(radians) * .pi)
        return Coordinate(
            lon: longitude + longitudeOffset,
            lat: latitude + latitudeOffset)
    }

    private static func transformLatitude(x: Double, y: Double) -> Double {
        var result = -100 + 2 * x + 3 * y + 0.2 * y * y
            + 0.1 * x * y + 0.2 * sqrt(abs(x))
        result += (20 * sin(6 * x * .pi) + 20 * sin(2 * x * .pi)) * 2 / 3
        result += (20 * sin(y * .pi) + 40 * sin(y / 3 * .pi)) * 2 / 3
        result += (160 * sin(y / 12 * .pi) + 320 * sin(y * .pi / 30)) * 2 / 3
        return result
    }

    private static func transformLongitude(x: Double, y: Double) -> Double {
        var result = 300 + x + 2 * y + 0.1 * x * x
            + 0.1 * x * y + 0.1 * sqrt(abs(x))
        result += (20 * sin(6 * x * .pi) + 20 * sin(2 * x * .pi)) * 2 / 3
        result += (20 * sin(x * .pi) + 40 * sin(x / 3 * .pi)) * 2 / 3
        result += (150 * sin(x / 12 * .pi) + 300 * sin(x / 30 * .pi)) * 2 / 3
        return result
    }
}
