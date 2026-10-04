import Foundation

/// The reader's Tokyo corridor default: without a recorded surface-only
/// station, use Sobu/Yokosuka. This is a preference, not a uniqueness proof.
/// Explicit physical choices and other railway families take precedence.
public enum TokyoConventionalRouteInference {
    public static let tunnelLineID = "jp-東日本旅客鉄道-総武線-3"
    public static let surfaceLineID = "jp-東日本旅客鉄道-東海道線"
    /// Corridor order used only when no package is in hand. 品川's id is not
    /// an independent fact: ``tunnelStationIDs(in:)`` reads it from the
    /// 総武線-3 row. The shipped row currently stores 004095.
    private static let fallbackTunnelCodes = ["003766", "003872", "004095"]
    private static let surfaceCodes: Set<String> = ["003795", "003949", "004000", "004061"]

    /// 東京, 新橋, 品川 station ids on the 総武線-3 package row, in that order.
    static func tunnelStationIDs(in package: CompactPackage) -> [String]? {
        guard let line = package.lines.first(where: { $0.id == tunnelLineID }) else { return nil }
        let names = ["東京", "新橋", "品川"]
        let ids = names.compactMap { name in line.stations.first { $0.name == name }?.id }
        return ids.count == names.count ? ids : nil
    }

    private static func corridorCodes(package: CompactPackage?) -> [String] {
        if let package, let ids = tunnelStationIDs(in: package) { return ids }
        return fallbackTunnelCodes
    }

    /// Used at the common native normalization boundary so cached, live and
    /// imported sparse journeys all receive the same physical identities.
    public static func applying(to train: Train, package: CompactPackage? = nil) -> Train {
        guard eligible(train), let sections = train.routeSections else { return train }
        var result = train
        result.routeSections = sections.map { section($0, in: train, package: package) }
        return result
    }

    public static func section(
        _ value: RouteSection, in train: Train, package: CompactPackage? = nil
    ) -> RouteSection {
        let corridor = corridorCodes(package: package)
        guard eligible(train), value.sectionCodes?.isEmpty != false,
              permitsTunnel(value),
              let from = stationCode(value.fromN02StationCode, name: value.from, corridor: corridor),
              let to = stationCode(value.toN02StationCode, name: value.to, corridor: corridor),
              let start = corridor.firstIndex(of: from),
              let end = corridor.firstIndex(of: to), start != end else { return value }
        var indices = Array(min(start, end)..<max(start, end))
        if start > end { indices.reverse() }
        var result = value
        result.fromN02StationCode = from
        result.toN02StationCode = to
        result.lineIDs = [tunnelLineID]
        if result.lineNames?.isEmpty != false { result.lineNames = ["総武線"] }
        if result.operatorNames?.isEmpty != false { result.operatorNames = ["東日本旅客鉄道"] }
        result.sectionCodes = indices.map {
            "\(tunnelLineID)@\(corridor[$0]):\(corridor[$0 + 1])"
        }
        return result
    }

    /// An editor may fill a complete local corridor, including Shimbashi,
    /// without removing an authored visit or overriding a selected pathway.
    public static func choice(in train: Train, package: CompactPackage) -> RailwayRouteChoices.Choice? {
        let corridor = corridorCodes(package: package)
        guard eligible(train), train.stops.count >= 2,
              train.routeSections?.contains(where: { $0.sectionCodes?.isEmpty == false }) != true,
              (train.routeSections ?? []).allSatisfy(permitsTunnel),
              let first = train.stops.first, let last = train.stops.last,
              let from = stationCode(first.n02StationCode, name: first.name, corridor: corridor),
              let to = stationCode(last.n02StationCode, name: last.name, corridor: corridor),
              corridor.contains(from), corridor.contains(to), from != to else { return nil }
        let choices = RailwayRouteChoices.choices(
            package: package, originCode: from, destinationCode: to,
            trainType: train.trainType)
        let authored = train.stops.filter { !RailwayRouteEditing.isUntouchedGenerated($0) }
            .compactMap { stationCode($0.n02StationCode, name: $0.name, corridor: corridor) }
        return choices.first { candidate in
            guard candidate.lineIDs == [tunnelLineID] else { return false }
            var cursor = 0
            for code in authored {
                guard let index = candidate.stations.indices.dropFirst(cursor)
                    .first(where: { candidate.stations[$0].code == code }) else { return false }
                cursor = index + 1
            }
            return true
        }
    }

    private static func eligible(_ train: Train) -> Bool {
        guard !train.requiresRouteConfirmation else { return false }
        guard (train.region ?? "jp") == "jp" else { return false }
        let type = (train.trainType ?? "").lowercased()
        guard !["highspeed", "high speed", "high-speed", "shinkansen", "新幹線", "新干线", "高速"]
            .contains(where: type.contains) else { return false }
        let company = (train.company ?? "").lowercased()
        guard company.isEmpty || company.contains("jr") || company.contains("東日本旅客鉄道")
            || company.contains("东日本旅客铁道") else { return false }
        // An authored surface stop proves that this is not the sparse default
        // case. Automatic stops remain consequences of the current suggestion.
        guard !train.stops.contains(where: {
            !RailwayRouteEditing.isUntouchedGenerated($0)
                && surfaceCodes.contains(stationCode($0.n02StationCode, name: $0.name) ?? "")
        }) else { return false }
        // An explicit surface assignment elsewhere in this corridor also
        // constrains the adjacent legs, including partially coded old records.
        return !(train.routeSections ?? []).contains { value in
            let ids = value.lineIDs ?? []
            let codes = value.sectionCodes ?? []
            return ids.contains(surfaceLineID) || codes.contains { $0.hasPrefix(surfaceLineID + "@") }
        }
    }

    private static func permitsTunnel(_ section: RouteSection) -> Bool {
        if let ids = section.lineIDs, !ids.isEmpty { return ids.allSatisfy { $0 == tunnelLineID } }
        return (section.lineNames ?? []).allSatisfy { name in
            ["総武", "总武", "横須賀", "横须贺", "sobu", "sōbu", "yokosuka"]
                .contains { name.lowercased().contains($0) }
        }
    }

    private static func stationCode(
        _ code: String?, name: String?, corridor: [String]? = nil
    ) -> String? {
        if let code, !code.isEmpty { return code }
        let codes = corridor ?? fallbackTunnelCodes
        switch (name ?? "").lowercased() {
        case "東京", "东京", "tokyo": return codes.first
        case "新橋", "新桥", "shimbashi", "shinbashi": return codes.count > 1 ? codes[1] : nil
        case "品川", "shinagawa": return codes.count > 2 ? codes[2] : nil
        case "有楽町", "有乐町", "yurakucho", "yūrakuchō": return "003795"
        case "浜松町", "滨松町", "hamamatsucho": return "003949"
        case "田町", "tamachi": return "004000"
        case "高輪ゲートウェイ", "高轮gateway", "takanawa gateway": return "004061"
        default: return nil
        }
    }
}
