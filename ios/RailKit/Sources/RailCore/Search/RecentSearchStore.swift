import Foundation

/// The last searches a reader typed and acted on, per region and search box,
/// most recent first. Shown as the empty-box suggestions of the station picker
/// and the journey search.
public enum RecentSearchStore {
    public static let limit = 8

    /// Which search box a list belongs to.
    public enum Box: String, Sendable { case stationPicker, journeys }

    public static func key(_ box: Box, regionCode: String) -> String {
        "search.recent.\(box.rawValue).\(regionCode)"
    }

    public static func load(_ box: Box, regionCode: String, defaults: UserDefaults = .standard) -> [String] {
        Array((defaults.stringArray(forKey: key(box, regionCode: regionCode)) ?? []).prefix(limit))
    }

    /// Put `query` first, dropping an equal earlier spelling. Blank and
    /// one-character queries are not worth keeping. Returns the new list.
    @discardableResult
    public static func record(
        _ query: String, box: Box, regionCode: String, defaults: UserDefaults = .standard
    ) -> [String] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var list = load(box, regionCode: regionCode, defaults: defaults)
        guard text.count >= 2 else { return list }
        let canonical = SearchNormalizer.canonical(text)
        list.removeAll { SearchNormalizer.canonical($0) == canonical }
        list.insert(text, at: 0)
        list = Array(list.prefix(limit))
        defaults.set(list, forKey: key(box, regionCode: regionCode))
        return list
    }

    public static func clear(_ box: Box, regionCode: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(box, regionCode: regionCode))
    }
}
