import RailCore

/// Station titles and captions read the stored bracket split. Map labels do not.
@MainActor
enum BracketedStationText {
    static func title(
        officialName: String,
        localizedTitle: String,
        regionCode: String,
        localization: AppLocalization
    ) -> String {
        guard let parts = parts(officialName: officialName, regionCode: regionCode),
              parts.kind == .status else { return localizedTitle }
        return parts.base
    }

    static func secondary(
        officialName: String,
        regionCode: String,
        qualifier: String,
        localization: AppLocalization
    ) -> String {
        guard let parts = parts(officialName: officialName, regionCode: regionCode),
              parts.kind == .status else { return qualifier }
        return StationLabel.statusSecondary(
            bracket: parts.bracket,
            statusWord: statusWord(parts.status, localization: localization),
            qualifier: qualifier)
    }

    private static func parts(officialName: String, regionCode: String) -> StationNameRecord? {
        StationNameLookup.directory(forRegion: regionCode)?.parts(forOfficialName: officialName)
    }

    private static func statusWord(
        _ status: StationNameRecord.Status?, localization: AppLocalization
    ) -> String? {
        guard let status else { return nil }
        let key = "ios.station.status.\(status.rawValue)"
        let value = localization.text(key)
        return value == key ? nil : value
    }
}
