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
actor StationReadingsStore {

    static let shared = StationReadingsStore()

    /// A readable table, including a legal file with no rows. A missing
    /// resource and a damaged file are not stored as that table.
    enum Availability: Sendable {
        case ready(Localization.StationReadings)
        case missing
        case unavailable(String)
    }

    /// Successful reads and confirmed absences only. A damaged file is never
    /// entered, so the next explicit read can recover.
    private var cached: [String: Availability] = [:]
    private var overrides: [String: Data?] = [:]

    /// `AppCore.countrySuffixed("station-names", country)`.
    nonisolated static func resourceName(country: String) -> String {
        Region.countrySuffixed("station-names", country: country)
    }

    /// The readings for one country. `.missing` means the bundle has no file.
    /// `.unavailable` means the file exists but could not be read; that result
    /// is not cached. `.ready` includes a decoded table whose row maps are empty.
    func availability(for country: String) -> Availability {
        if let cached = cached[country] { return cached }
        let outcome = Self.read(country: country, override: overrides[country])
        switch outcome {
        case .unavailable:
            return outcome
        case .ready, .missing:
            cached[country] = outcome
            return outcome
        }
    }

    /// Replace the bundled bytes for one country. `nil` restores the bundle.
    /// The previous outcome is dropped, including a cached absence.
    func testingReplaceResource(_ data: Data?, for country: String) {
        cached[country] = nil
        if let data {
            overrides[country] = data
        } else {
            overrides[country] = nil
        }
    }

    func testingHasCachedTable(for country: String) -> Bool {
        if case .ready = cached[country] { return true }
        return false
    }

    private nonisolated static func read(country: String, override: Data??) -> Availability {
        if let override {
            guard let data = override else { return .missing }
            return interpret(data)
        }
        guard let url = Bundle.main.url(
            forResource: resourceName(country: country), withExtension: "json")
        else { return .missing }
        do {
            return interpret(try Data(contentsOf: url, options: .mappedIfSafe))
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    /// A decoded document is ready even when both maps are empty. Bytes that
    /// are not that document are a failure, not an empty Japan table.
    private nonisolated static func interpret(_ data: Data) -> Availability {
        do {
            let raw = try JSONDecoder().decode(RawTable.self, from: data)
            return .ready(Localization.StationReadings(
                country: raw.country,
                byCode: (raw.byCode ?? [:]).mapValues(\.row),
                byName: (raw.byName ?? [:]).mapValues(\.row)))
        } catch {
            return .unavailable("Station readings could not be read.")
        }
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
