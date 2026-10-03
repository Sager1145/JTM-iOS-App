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
        let id: String
        let region: String
        let from: Endpoint
        let to: Endpoint
        let evidence: [String]
        let validFrom: String?
        let validTo: String?
    }
    public enum RegistryError: Error { case unsupportedFormat, unsupportedRegion, invalidCoordinate, duplicateID }
    private let byRegion: [String: [RouteGraph.PhysicalJunction]]

    public init(data: Data) throws {
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.format == "jtm-physical-rail-junctions-v1" else { throw RegistryError.unsupportedFormat }
        var records: [String: [RouteGraph.PhysicalJunction]] = [:]
        var seen: Set<String> = []
        for row in document.junctions {
            guard Localization.supportedCountries.contains(row.region) else { throw RegistryError.unsupportedRegion }
            guard seen.insert(row.id).inserted else { throw RegistryError.duplicateID }
            records[row.region, default: []].append(.init(id: row.id, from: try row.from.value(),
                                                        to: try row.to.value(), evidence: row.evidence,
                                                        validFrom: row.validFrom, validTo: row.validTo))
        }
        byRegion = records
    }

    public func junctions(for region: String) -> [RouteGraph.PhysicalJunction] { byRegion[region] ?? [] }
}
