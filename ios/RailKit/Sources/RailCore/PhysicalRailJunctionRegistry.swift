import Foundation

/// The reviewed physical connection catalog. Service/display relationships are
/// deliberately not a source of graph edges.
public struct PhysicalRailJunctionRegistry: Sendable {
    private struct Document: Decodable {
        let format: String
        let junctions: [Record]
    }
    private struct Record: Decodable {
        struct Identity: Decodable {
            let operatorName: String
            let lineName: String
            let railwayClassCode: String
            let level: String?
            let trackID: String?
        }
        struct Endpoint: Decodable {
            let identity: Identity
            let coordinate: [Double]
            func value() throws -> RouteGraph.PhysicalJunction.Endpoint {
                guard let point = Coordinate(pair: coordinate), point.lon.isFinite, point.lat.isFinite,
                      (-180...180).contains(point.lon), (-90...90).contains(point.lat) else {
                    throw RegistryError.invalidCoordinate
                }
                return .init(identity: .init(operatorName: identity.operatorName,
                                            lineName: identity.lineName,
                                            railwayClassCode: identity.railwayClassCode,
                                            level: identity.level, trackID: identity.trackID), coordinate: point)
            }
        }
        struct Source: Decodable {
            let provider: String
            let license: String
            let ways: [Int]
            let retrieved: String
            let cache: String
            func value() -> RouteGraph.PhysicalJunction.Source {
                .init(provider: provider, license: license, ways: ways, retrieved: retrieved, cache: cache)
            }
        }
        struct Attach: Decodable {
            let from: Double
            let to: Double
            var value: RouteGraph.PhysicalJunction.AttachMeters { .init(from: from, to: to) }
        }
        struct Terminus: Decodable {
            let end: String
            let station: String
            let stationCode: String
            let coordinate: [Double]
            func value() throws -> RouteGraph.PhysicalJunction.Terminus {
                guard let end = RouteGraph.PhysicalJunction.Terminus.End(rawValue: end) else {
                    throw RegistryError.unsupportedTerminus
                }
                guard let point = Coordinate(pair: coordinate), point.lon.isFinite, point.lat.isFinite,
                      (-180...180).contains(point.lon), (-90...90).contains(point.lat) else {
                    throw RegistryError.invalidCoordinate
                }
                return .init(end: end, station: station, stationCode: stationCode, coordinate: point)
            }
        }
        let id: String
        let region: String
        let from: Endpoint
        let to: Endpoint
        let evidence: [String]
        let validFrom: String?
        let validTo: String?
        let kind: String?
        let linkMeters: Double?
        let path: [[Double]]?
        let source: Source?
        let attachMeters: Attach?
        let terminus: Terminus?
        func pathCoordinates() throws -> [Coordinate]? {
            guard let path else { return nil }
            return try path.map { pair in
                guard let point = Coordinate(pair: pair), point.lon.isFinite, point.lat.isFinite,
                      (-180...180).contains(point.lon), (-90...90).contains(point.lat) else {
                    throw RegistryError.invalidCoordinate
                }
                return point
            }
        }
    }
    public enum RegistryError: Error, Equatable { case unsupportedFormat, unsupportedRegion, invalidCoordinate, duplicateID, unsupportedKind, unsupportedTerminus }
    private let byRegion: [String: [RouteGraph.PhysicalJunction]]

    public init(data: Data) throws {
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.format == "jtm-physical-rail-junctions-v1" else { throw RegistryError.unsupportedFormat }
        var records: [String: [RouteGraph.PhysicalJunction]] = [:]
        var seen: Set<String> = []
        for row in document.junctions {
            guard Localization.supportedCountries.contains(row.region) else { throw RegistryError.unsupportedRegion }
            guard seen.insert(row.id).inserted else { throw RegistryError.duplicateID }
            guard let kind = RouteGraph.PhysicalJunction.Kind(rawValue: row.kind ?? "zeroLength") else {
                throw RegistryError.unsupportedKind
            }
            records[row.region, default: []].append(.init(
                id: row.id, from: try row.from.value(), to: try row.to.value(), evidence: row.evidence,
                validFrom: row.validFrom, validTo: row.validTo, kind: kind,
                path: try row.pathCoordinates(), source: row.source?.value(),
                attachMeters: row.attachMeters?.value, terminus: try row.terminus?.value()))
        }
        byRegion = records
    }

    public func junctions(for region: String) -> [RouteGraph.PhysicalJunction] { byRegion[region] ?? [] }
}
