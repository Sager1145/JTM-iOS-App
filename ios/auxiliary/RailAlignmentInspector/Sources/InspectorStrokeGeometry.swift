import MapKit
import RailCore

/// The inspector's isolated, zero-lane centreline contract. Build every
/// complete DisplayParts chain before clipping or drawing a selected viewport.
/// Exact shared survey vertices permit tangent inheritance; proximity alone
/// never creates a join or changes railway connectivity.
enum InspectorStrokeGeometry {
    static let revision = "inspector-centreline-v5-preserve-small-survey-curves"
    static var joinContract: String {
        "exact-interior-or-same-line-three-way-endpoints;ownLane=0;mainLane=0;angle=\(ContinuousStroke.joinMaxTangentDegrees);blend=\(ContinuousStroke.joinBlendMetres);fraction=\(ContinuousStroke.joinBlendIntervalFraction);deviationPx=\(ContinuousStroke.joinBlendDeviationPx);deviationMetres=\(ContinuousStroke.joinBlendDeviationMetres)"
    }

    static func build(display: [[Coordinate]], stations: [Coordinate],
                      mapPointsPerPoint scale: Double, zoom: Double) -> [[Coordinate]] {
        guard scale.isFinite, scale > 0 else { return display }
        let weight = RailStyle.scale(atZoom: zoom)
        let stationKeys = Set(stations.map(stationKey))
        // Project all unmodified chains first. Join discovery must not depend
        // on which smoothed chain happened to be built first.
        let chains = display.map { part in
            part.map { coordinate -> ContinuousStroke.Point in
                let p = MKMapPoint(coordinate.native)
                return .init(x: p.x / scale, y: p.y / scale)
            }
        }
        var interiorParts: [Coordinate: [Int]] = [:]
        for (partIndex, part) in display.enumerated() where part.count > 2 {
            var seen: Set<Coordinate> = []
            for coordinate in part.dropFirst().dropLast() where seen.insert(coordinate).inserted {
                interiorParts[coordinate, default: []].append(partIndex)
            }
        }
        var endpointParts: [Coordinate: [Int]] = [:]
        for (index, part) in display.enumerated() where part.count > 1 {
            for coordinate in Set([part[0], part[part.count - 1]]) {
                endpointParts[coordinate, default: []].append(index)
            }
        }
        func join(partIndex: Int, atEnd: Bool) -> ContinuousStroke.Join? {
            let part = display[partIndex]
            guard part.count > 1, let coordinate = atEnd ? part.last : part.first else { return nil }
            if let fork = endpointParts[coordinate], fork.count >= 3 {
                for mainIndex in fork where mainIndex != partIndex {
                    if let join = ContinuousStroke.tangentJoin(
                        chains[partIndex], mainChain: chains[mainIndex], atEnd: atEnd,
                        lane: 0, mainLane: 0, allowMainEndpoint: true) { return join }
                }
                return nil // Keep the surveyed direction at a genuinely steep fork.
            }
            // Candidate order is the original DisplayParts order, shared by
            // live and saved captures. No nearest-track or rounded-key lookup.
            for mainIndex in interiorParts[coordinate] ?? [] where mainIndex != partIndex {
                if let join = ContinuousStroke.tangentJoin(chains[partIndex], mainChain: chains[mainIndex],
                                                           atEnd: atEnd, lane: 0, mainLane: 0) {
                    return join
                }
            }
            return nil
        }
        return display.indices.map { partIndex -> [Coordinate] in
            let part = display[partIndex]
            guard part.count > 1 else { return part }
            var measures = [Double](repeating: 0, count: part.count)
            for i in 1..<part.count {
                measures[i] = measures[i - 1] + Geometry.distanceMeters(part[i - 1], part[i])
            }
            let anchors = part.indices.filter {
                $0 == 0 || $0 == part.count - 1 || stationKeys.contains(stationKey(part[$0]))
            }
            let stroke = ContinuousStroke.buildStroke(chains[partIndex], options: .init(
                measures: measures, rows: [], totalMetres: measures.last ?? 0,
                laneGapPx: Double(RailStyle.parallelLaneCentreDistance * weight),
                minRampPx: RailStyle.strokeMinRamp,
                cornerRadiusPx: Double(RailStyle.strokeCornerRadius * weight),
                minCornerRadiusPx: Double(RailStyle.minimumCornerRadius(atScale: weight)),
                anchors: anchors, joinStart: join(partIndex: partIndex, atEnd: false),
                joinEnd: join(partIndex: partIndex, atEnd: true), enforceMinimumCornerRadius: true))
            return stroke.points.map {
                let coordinate = MKMapPoint(x: $0.x * scale, y: $0.y * scale).coordinate
                return Coordinate(lon: coordinate.longitude, lat: coordinate.latitude)
            }
        }
    }

    // Preserve the inspector's existing station-anchor contract. These rounded
    // keys protect vertices; they are never used to discover branch joins.
    private static func stationKey(_ coordinate: Coordinate) -> String {
        "\(Int64((coordinate.lon * 1e7).rounded())):\(Int64((coordinate.lat * 1e7).rounded()))"
    }
}
