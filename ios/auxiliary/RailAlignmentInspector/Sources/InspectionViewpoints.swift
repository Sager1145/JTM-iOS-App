import RailCore

/// Camera targets along one selected interval. These samples never replace or
/// simplify the rail geometry. Interpolation is linear in WGS84 coordinates,
/// suitable for the short local segments in the Japan inspection package.
struct InspectionViewpoints {
    static func points(input: [Coordinate], spacingMetres: Double = 350) -> [Coordinate] {
        guard spacingMetres.isFinite, spacingMetres > 0,
              input.allSatisfy({ coordinate in
                  coordinate.lon.isFinite && coordinate.lat.isFinite
                      && (-180...180).contains(coordinate.lon)
                      && (-90...90).contains(coordinate.lat)
              }), let first = input.first else { return [] }
        guard input.count > 1 else { return input }

        var result = [first]
        var travelled = 0.0
        var nextSample = spacingMetres
        for (start, end) in zip(input, input.dropFirst()) {
            let length = Geometry.distanceMeters(start, end)
            guard length.isFinite else { return [] }
            guard length > 0 else { continue }
            let segmentEnd = travelled + length
            while nextSample < segmentEnd {
                let fraction = (nextSample - travelled) / length
                result.append(Coordinate(lon: start.lon + (end.lon - start.lon) * fraction,
                                         lat: start.lat + (end.lat - start.lat) * fraction))
                nextSample += spacingMetres
            }
            travelled = segmentEnd
        }
        // Retain the tail even when the final remainder is shorter than the
        // requested spacing. Closed intervals may end at their starting point.
        if let last = input.last, result.count == 1 || result.last != last {
            result.append(last)
        }
        return result
    }
}
