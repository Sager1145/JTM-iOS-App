import Foundation

/// Elects a visible station bead for a shared landlord/tenant family.
/// The caller supplies actual viewport/LOD admission; this never connects tracks.
public enum StationBeadPolicy {
    public struct Window: Sendable {
        public let groupID: String
        public let isLandlord: Bool
        public let from: Double
        public let to: Double
        public init(groupID: String, isLandlord: Bool, from: Double, to: Double) {
            self.groupID = groupID; self.isLandlord = isLandlord
            self.from = from; self.to = to
        }
    }

    public struct Station: Sendable {
        public let region: String
        public let stationCode: String
        public let lineID: String
        public let isDrawn: Bool
        public let anchorMeasure: Double?
        public let windows: [Window]
        public init(region: String, stationCode: String, lineID: String, isDrawn: Bool,
                    anchorMeasure: Double?, windows: [Window]) {
            self.region = region; self.stationCode = stationCode; self.lineID = lineID
            self.isDrawn = isDrawn; self.anchorMeasure = anchorMeasure; self.windows = windows
        }
        fileprivate var tenantGroup: String? {
            guard let anchorMeasure else { return nil }
            return windows.first {
                !$0.isLandlord && $0.from <= anchorMeasure && anchorMeasure <= $0.to
            }?.groupID
        }
    }

    public static func isSuppressed(_ station: Station, siblings: [Station]) -> Bool {
        guard let group = station.tenantGroup else { return false }
        let samePlace = siblings.filter {
            $0.region == station.region && $0.stationCode == station.stationCode
        }
        if samePlace.contains(where: { sibling in
            guard sibling.lineID != station.lineID, sibling.isDrawn,
                  let measure = sibling.anchorMeasure else { return false }
            return sibling.windows.contains {
                $0.isLandlord && $0.groupID == group && $0.from <= measure && measure <= $0.to
            }
        }) { return true }
        // Names below the dot floor may still restore a supporting bead after
        // collision admission. With no drawn tenant, do not suppress that offer.
        let elected = samePlace.filter { $0.isDrawn && $0.tenantGroup == group }.map(\.lineID).min()
        return elected.map { station.lineID != $0 } ?? false
    }
}
