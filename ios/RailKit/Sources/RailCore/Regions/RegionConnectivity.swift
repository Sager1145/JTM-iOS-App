import Foundation

/// Which regions the app supports and which pairs share a physical rail
/// network. Data lives in `Resources/region-connectivity.json`.
///
/// A route section, trip or editor selection that spans two regions is only
/// valid when `areConnected` holds. Two regions are connected only through an
/// explicit enabled link whose both ends are supported; no link means the
/// networks are separate (jp, kr, tw, hk, mo are mutually unconnected).
/// A missing resource falls back to "everything disconnected, cn unsupported".
public enum RegionConnectivity {
    struct Document: Decodable, Sendable {
        struct Region: Decodable, Sendable { let code: String; let supported: Bool }
        struct Link: Decodable, Sendable { let regions: [String]; let enabled: Bool }
        let regions: [Region]
        let links: [Link]
    }

    struct Table: Sendable {
        let supported: [String]
        let enabledLinks: Set<Set<String>>

        static let fallback = Table(supported: ["jp", "tw", "hk", "mo", "kr"], enabledLinks: [])
    }

    static let table: Table = {
        guard let url = Bundle.module.url(forResource: "region-connectivity", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let doc = try? JSONDecoder().decode(Document.self, from: data) else {
            return .fallback
        }
        return Table(
            supported: doc.regions.filter(\.supported).map(\.code),
            enabledLinks: Set(doc.links.filter(\.enabled).map { Set($0.regions) }))
    }()

    public static var supportedRegions: [String] { table.supported }

    public static func isSupported(_ region: String) -> Bool {
        table.supported.contains(region)
    }

    public static func areConnected(_ a: String, _ b: String) -> Bool {
        guard isSupported(a), isSupported(b) else { return false }
        if a == b { return true }
        return table.enabledLinks.contains([a, b])
    }

    public static func region(ofStationID id: String?) -> String? {
        SolverRegistryInput.regionCode(id)
    }

    /// Regions reachable from `region` (itself first, when supported).
    public static func connectedRegions(of region: String) -> [String] {
        table.supported.filter { areConnected(region, $0) }
    }

    /// The first pair of regions among the stops that is not connected, in
    /// stop order. Stops with unparseable IDs are ignored.
    public static func firstUnconnectedPair(stationIDs: [String?]) -> (String, String)? {
        let regions = stationIDs.compactMap(region(ofStationID:))
        var seen: [String] = []
        for r in regions where !seen.contains(r) {
            if let other = seen.first(where: { !areConnected($0, r) }) { return (other, r) }
            seen.append(r)
        }
        // A lone unsupported region has no pair but is still not connected to itself.
        return nil
    }
}
