import Foundation

/// The reader's Tokyo corridor default: without a recorded surface-only
/// station, use Sobu/Yokosuka. This is a preference, not a uniqueness proof.
/// Explicit physical choices and other railway families take precedence.
public enum TokyoConventionalRouteInference {
    public static let tunnelLineID = "jp-東日本旅客鉄道-総武線-3"
    public static let surfaceLineID = "jp-東日本旅客鉄道-東海道線"
    private static let tunnelCodes = ["003766", "003872", "004095"]
    private static let surfaceCodes: Set<String> = ["003795", "003949", "004000", "004061"]

    /// Used at the common native normalization boundary so cached, live and
    /// imported sparse journeys all receive the same physical identities.
    public static func applying(to train: Train) -> Train {
        guard eligible(train), let sections = train.routeSections else { return train }
        var result = train
        result.routeSections = sections.map { section($0, in: train) }
        return result
    }

    public static func section(_ value: RouteSection, in train: Train) -> RouteSection {
        guard eligible(train), value.sectionCodes?.isEmpty != false,
              permitsTunnel(value),
              let from = stationCode(value.fromN02StationCode, name: value.from),
              let to = stationCode(value.toN02StationCode, name: value.to),
              let start = tunnelCodes.firstIndex(of: from),
              let end = tunnelCodes.firstIndex(of: to), start != end else { return value }
        var indices = Array(min(start, end)..<max(start, end))
        if start > end { indices.reverse() }
        var result = value
        result.fromN02StationCode = from
        result.toN02StationCode = to
        result.lineIDs = [tunnelLineID]
        if result.lineNames?.isEmpty != false { result.lineNames = ["総武線"] }
        if result.operatorNames?.isEmpty != false { result.operatorNames = ["東日本旅客鉄道"] }
        result.sectionCodes = indices.map {
            "\(tunnelLineID)@\(tunnelCodes[$0]):\(tunnelCodes[$0 + 1])"
        }
        return result
    }

    /// An editor may fill a complete local corridor, including Shimbashi,
    /// without removing an authored visit or overriding a selected pathway.
    public static func choice(in train: Train, package: CompactPackage) -> RailwayRouteChoices.Choice? {
        guard eligible(train), train.stops.count >= 2,
              train.routeSections?.contains(where: { $0.sectionCodes?.isEmpty == false }) != true,
              (train.routeSections ?? []).allSatisfy(permitsTunnel),
              let first = train.stops.first, let last = train.stops.last,
              let from = stationCode(first.n02StationCode, name: first.name),
              let to = stationCode(last.n02StationCode, name: last.name),
              tunnelCodes.contains(from), tunnelCodes.contains(to), from != to else { return nil }
        let choices = RailwayRouteChoices.choices(
            package: package, originCode: from, destinationCode: to,
            trainType: train.trainType)
        let authored = train.stops.filter { !RailwayRouteEditing.isUntouchedGenerated($0) }
            .compactMap { stationCode($0.n02StationCode, name: $0.name) }
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

    private static func stationCode(_ code: String?, name: String?) -> String? {
        if let code, !code.isEmpty { return code }
        switch (name ?? "").lowercased() {
        case "東京", "东京", "tokyo": return "003766"
        case "新橋", "新桥", "shimbashi", "shinbashi": return "003872"
        case "品川", "shinagawa": return "004095"
        case "有楽町", "有乐町", "yurakucho", "yūrakuchō": return "003795"
        case "浜松町", "滨松町", "hamamatsucho": return "003949"
        case "田町", "tamachi": return "004000"
        case "高輪ゲートウェイ", "高轮gateway", "takanawa gateway": return "004061"
        default: return nil
        }
    }
}
