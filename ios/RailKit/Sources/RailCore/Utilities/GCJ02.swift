import Foundation

/// The public GCJ-02 forward transform used by Chinese digital maps.
///
/// Constants and series terms intentionally stay spelled out: replacing them with a
/// fitted translation would align one station and drift along the rest of the network.
///
/// This is the body that used to sit in the app's `AppleMapDatum`. Which regions are shifted
/// on a given device is the app's per-device decision (`AppleMapDatum.gcj02Countries`); the rail
/// pack is always WGS84 on disk and the reader shifts it when a level is mounted
/// (`RailPackReader(data:display:)`), using ``fromWGS84(_:)`` for points and ``toWGS84(_:)`` to find
/// where in the file a display-space rectangle lies.
public enum GCJ02 {
    /// The regions whose Apple basemap can be served in GCJ-02. Japan is never a candidate.
    public static let candidateRegions: Set<String> = ["tw", "hk", "mo", "kr", "cn"]

    public static func fromWGS84(_ coordinate: Coordinate) -> Coordinate {
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

    /// The WGS84 coordinate whose GCJ-02 image is `coordinate`: three rounds of fixed-point iteration on
    /// ``fromWGS84(_:)`` (the shift is smooth, its gradient well under 1%, so each round gains about
    /// two orders of magnitude; the result is within 1e-9 degrees over the candidate regions).
    public static func toWGS84(_ coordinate: Coordinate) -> Coordinate {
        var guess = coordinate
        for _ in 0..<3 {
            let shifted = fromWGS84(guess)
            guess = Coordinate(lon: guess.lon - (shifted.lon - coordinate.lon), lat: guess.lat - (shifted.lat - coordinate.lat))
        }
        return guess
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
