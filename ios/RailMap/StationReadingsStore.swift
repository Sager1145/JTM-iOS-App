import Foundation
import RailCore

/// The derived station-name table, read out of the app bundle.
///
/// `station-names` joins the curated readings with the station English
/// database, retaining exact platform and line membership identities.
///
/// `RailCore.Localization` owns the code-before-name lookup and display rules;
/// this actor decodes the country-scoped projection once per region.
/// Japan retains Japanese base names with optional kana, English/romaji and
/// Chinese sublines. Other countries localise the base station name itself.
/// Detail cards retain all stored name fields independently of reading toggles.
///
/// Resource names follow the web app's `countrySuffixed` rule: Japan uses
/// `station-names.json`, other countries use `station-names-{country}.json`.
/// US and Canada retain their existing `station-readings` resources.
actor StationReadingsStore {

    static let shared = StationReadingsStore()

    /// Every regional table may be needed while all regions are on screen.
    private var tables: [String: Localization.StationReadings] = [:]

    /// `AppCore.countrySuffixed("station-names", country)`.
    nonisolated static func resourceName(country: String) -> String {
        Region.countrySuffixed(
            country == "us" || country == "ca" ? "station-readings" : "station-names",
            country: country)
    }

    /// The table for a country, or `.empty` when the bundle has no such file.
    ///
    /// `.empty` is not a silent failure that looks like success: it declares
    /// country `"JP"`, so names are annotated with whatever the gloss
    /// dictionaries hold and never replaced with a wrong language's name.
    func table(for country: String) -> Localization.StationReadings {
        if let cached = tables[country] { return cached }
        let table = Self.decode(country: country) ?? .empty
        tables[country] = table
        return table
    }

    private nonisolated static func decode(country: String) -> Localization.StationReadings? {
        guard
            let url = Bundle.main.url(
                forResource: resourceName(country: country), withExtension: "json"),
            let data = try? Data(contentsOf: url, options: .mappedIfSafe),
            let raw = try? JSONDecoder().decode(RawTable.self, from: data)
        else { return nil }
        return Localization.StationReadings(
            country: raw.country,
            byCode: (raw.byCode ?? [:]).mapValues(\.row),
            byName: (raw.byName ?? [:]).mapValues(\.row)
        )
    }

    /// The file as shipped. Every unknown key — `note`, `languages`, `stats`,
    /// `sources`, and the rows' own `name` — is ignored by
    /// `Decodable`, which is what keeps this loader from having to track the
    /// generators that write those files.
    private struct RawTable: Decodable {
        let country: String?
        let byCode: [String: RawRow]?
        let byName: [String: RawRow]?
    }

    private struct RawRow: Decodable {
        let kana: String?
        let katakana: String?
        let romaji: String?
        let zhHant: String?
        let zhHans: String?
        let ja: String?
        let en: String?

        enum CodingKeys: String, CodingKey {
            case kana, katakana, romaji, ja, en
            case zhHant = "zh_Hant"
            case zhHans = "zh_Hans"
        }

        /// The shipped tables store an unavailable translation as `""` rather
        /// than by omitting the field. They are carried through as-is:
        /// `Localization` tests every one of them for emptiness rather than
        /// for presence, so a blank can never win over a fallback.
        var row: Localization.StationReadingRow {
            Localization.StationReadingRow(
                kana: kana, romaji: romaji,
                zhHant: zhHant, zhHans: zhHans,
                ja: ja, en: en, katakana: katakana)
        }
    }
}
