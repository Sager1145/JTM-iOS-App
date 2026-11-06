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
        let known: [String]
        let supported: [String]
        let enabledLinks: Set<Set<String>>

        static let fallback = Table(known: ["jp", "tw", "hk", "mo", "kr", "cn"], supported: ["jp", "tw", "hk", "mo", "kr"], enabledLinks: [])
    }

    static let table: Table = {
        guard let url = Bundle.module.url(forResource: "region-connectivity", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let doc = try? JSONDecoder().decode(Document.self, from: data) else {
            return .fallback
        }
        return Table(
            known: doc.regions.map(\.code),
            supported: doc.regions.filter(\.supported).map(\.code),
            enabledLinks: Set(doc.links.filter(\.enabled).map { Set($0.regions) }))
    }()

    /// Test-only: replaces the supported set for the current task tree, so a
    /// disabled region's retained behaviour can still be exercised.
    @TaskLocal public static var supportedOverride: Set<String>?

    public static var supportedRegions: [String] {
        guard let override = supportedOverride else { return table.supported }
        return table.known.filter(override.contains)
    }

    public static func isSupported(_ region: String) -> Bool {
        let region = region.lowercased()
        if let override = supportedOverride { return override.contains(region) }
        return table.supported.contains(region)
    }

    public static func areConnected(_ a: String, _ b: String) -> Bool {
        let a = a.lowercased(), b = b.lowercased()
        guard isSupported(a), isSupported(b) else { return false }
        if a == b { return true }
        return table.enabledLinks.contains([a, b])
    }

    public static func region(ofStationID id: String?) -> String? {
        SolverRegistryInput.regionCode(id)
    }

    /// The region any station identity names: a `st:`/`op:` id, a six-digit
    /// Japanese code, or a source code such as `CN-OSM-...` / `kr-official-...`.
    public static func region(ofCode code: String?) -> String? {
        guard let code, !code.isEmpty else { return nil }
        if let region = region(ofStationID: code)?.lowercased(), table.known.contains(region) {
            return region
        }
        if code.count == 6, code.allSatisfy({ $0.isASCII && $0.isNumber }) { return "jp" }
        guard let dash = code.firstIndex(of: "-") else { return nil }
        let head = code[code.startIndex..<dash].lowercased()
        return table.known.contains(head) ? head : nil
    }

    /// Regions reachable from `region` (itself first, when supported).
    public static func connectedRegions(of region: String) -> [String] {
        supportedRegions.filter { areConnected(region, $0) }
    }

    /// Whether every region is supported and each pair is connected.
    public static func allConnected(_ regions: [String]) -> Bool {
        for (i, a) in regions.enumerated() {
            guard isSupported(a) else { return false }
            for b in regions[(i + 1)...] where !areConnected(a, b) { return false }
        }
        return true
    }

    /// The first pair of regions among the stops that is not connected, in
    /// stop order. Identities that name no region are ignored.
    public static func firstUnconnectedPair(stationIDs: [String?]) -> (String, String)? {
        firstUnconnectedPair(regions: stationIDs.compactMap(region(ofCode:)))
    }

    public static func firstUnconnectedPair(regions: [String]) -> (String, String)? {
        var seen: [String] = []
        for r in regions where !seen.contains(r) {
            if let other = seen.first(where: { !areConnected($0, r) }) { return (other, r) }
            seen.append(r)
        }
        return nil
    }
}
