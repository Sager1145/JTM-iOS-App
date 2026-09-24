import Foundation

/// Which Apple Maps PLACE a station on this map is, and the link that names it.
///
/// The station card's 「マップで開く」 used to hand Apple Maps a coordinate and
/// a caption — `maps.apple.com/?ll=35.681,139.766&q=東京駅`. That drops a pin at
/// the right spot wearing the right word, and it is not the same thing as the
/// station: the pin has no exits, no platforms, no departures, no walking time
/// and no name of its own, and a link to it arrives at the other end as a
/// dropped pin rather than as 東京駅. The whole reason to hand a reader over to
/// Apple Maps is that Apple Maps knows what is around a station, and a pin is
/// precisely the object that knows nothing.
///
/// So the station is resolved to a real map item first — `MKLocalSearch`, in
/// the app, because MapKit does not exist below this tier — and this type is
/// the part of that resolution that can be checked without a network: which
/// text to search for, which of the answers is actually this station, and what
/// URL names the winner.
///
/// ## Why the winner cannot simply be the first result
///
/// MapKit's ordering is relevance, not distance, and relevance around a station
/// is dominated by the things named after it. A live search for 臺北 inside a
/// four-kilometre box centred on the platform answered, in order:
///
///     台北银行(公交站)   1,643 m     台北车站            51 m
///     台北车站(地铁站)     134 m     台北车站(公交站)   114 m
///
/// The first answer is a bus stop outside a bank. Taking `mapItems.first` would
/// have sent every reader who tapped 臺北 to it.
///
/// ## Why the names have to be folded before they are compared
///
/// The service that answers is the one the reader's device is on, and it
/// answers in its own spelling: the same live search returned 台北车站 for a
/// package that spells the station 臺北, 金钟站 for 金鐘 and 妈阁 for 媽閣.
/// Comparing the two spellings directly matches none of them, so both sides go
/// through `normalize` — bracketed qualifiers off, width and case folded, the
/// word for "station" in five languages taken off the end, and Traditional
/// Chinese folded to Simplified so that 臺北 and 台北 are one string.
///
/// ## What it resolves, measured
///
/// `ios/tools/audit-station-places.swift` runs this rule over live searches.
/// On 2026-08-25, from a machine served by the China map service:
///
///     Macao        15 of 15   median   6 m
///     Hong Kong    60 of 60   median  42 m
///     Taiwan       49 of 60   median  34 m   (one more the service failed on)
///     Japan         0 of 40   the service answers nothing at all
///     Korea         0 of 40   the service answers nothing at all
///
/// Taiwan's ten are stations that service holds ONLY as the bus stop outside
/// them — 龙泉车站(公交站), 石龟车站(公交站) — which is not the station and is
/// refused. Japan and Korea are not a matching failure: that service returns
/// `MKError.placemarkNotFound` for every query outside Greater China, the
/// Eiffel Tower included, so there is nothing to match against and the card
/// sends the pin. Re-run the tool from a device on another service to measure
/// what it can see.
///
/// ## The DEVICE's language decides what comes back, not the app's
///
/// The same sweep on an English simulator resolved 11 of 12 in Macao, 7 of 12
/// in Hong Kong and 5 of 12 in Taiwan: the service answered Barra, Admiralty
/// and Taibei Station instead of 妈阁, 金钟 and 台北车站. Barra and Admiralty
/// still matched, because the packages carry them as the station's
/// romanisation; the rest did not.
///
/// That is why the caller hands over every spelling it has rather than the one
/// on screen — the card's own header is in the APP's language, which has
/// nothing to do with the device's. Both the package's romanisation and
/// `Localization.stationNameAliases` go in, the latter being the only source of
/// a station's kana, its zh_Hant/zh_Hans names and its official English one
/// when the reader has the reading toggles off.
///
/// What is left after that is romanisation systems disagreeing: Apple writes
/// Taiwan in Wade-Giles (Chiayi, Hsinchu) where the packages and the official
/// readings table both use Hanyu Pinyin (Jiayi, Xinzhu). No fold reaches across
/// that and inventing one would be guessing, so those stations keep the pin.
public enum StationPlaceLink {

    // MARK: - Inputs

    /// One station, in every spelling this app knows it by.
    ///
    /// All of them, rather than the one on screen: the reader's display
    /// language decides what the card's header says and has nothing to do with
    /// what Apple Maps calls the place. A Hong Kong station carries an official
    /// English name the reader may never see, and it is the name a device set
    /// to English will answer with.
    public struct Station: Sendable, Equatable {
        /// Every spelling, most authoritative first. The package's own name
        /// leads because it is the one the local map service uses.
        public var names: [String]
        /// The package's country code — `jp`, `tw`, `hk`, `mo`, `kr`. It
        /// decides which word for "station" a fallback query appends.
        public var country: String

        public init(names: [String], country: String) {
            self.names = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            self.country = country
        }
    }

    /// One place Apple Maps offered, reduced to the three things the rule reads.
    public struct Candidate: Sendable, Equatable {
        /// `MKMapItem.name`, exactly as the service spelled it.
        public var name: String
        /// Whether its point-of-interest category is public transport. A
        /// station that is not categorised as transport can still win — the
        /// second search pass runs without the category filter — but it never
        /// wins over one that is.
        public var isPublicTransport: Bool
        /// How far the result is from the station's own surveyed position, in
        /// metres, measured in whatever datum both sides are already in.
        public var metres: Double

        public init(name: String, isPublicTransport: Bool, metres: Double) {
            self.name = name
            self.isPublicTransport = isPublicTransport
            self.metres = metres
        }
    }

    /// How far an Apple Maps place may sit from the platform this map drew and
    /// still be the same station.
    ///
    /// A station is a building, not a point, and the two sides measure it from
    /// different places: the package's coordinate is one platform of a complex
    /// that may have a dozen, and Apple's is the place's own centre.
    ///
    /// 124 stations resolved in a live sweep of Taiwan, Hong Kong and Macao
    /// (`audit-station-places.swift`, 2026-08-25) came in at a median of 30 m,
    /// a 90th percentile of 150 m and a worst case of 534 m — 崇德, whose
    /// 台湾铁路管理局崇德火车站 the service places half a kilometre up the
    /// valley from the platform. 600 m clears that while staying far below the
    /// distance to the next station of the same name: the 同名 stations this
    /// map already worries about (中山, 大手町) are in different prefectures,
    /// not down the street.
    public static let maxMetres: Double = 600

    // MARK: - The search

    /// What to ask Apple Maps for, in the order to ask.
    ///
    /// The bare name first, because that is what the map services actually hold
    /// — 臺北 finds 台北车站 and 媽閣 finds 妈阁, and appending a word for
    /// "station" to either would have asked for a name neither service carries.
    /// The suffixed form second, for the stations whose bare name is a common
    /// noun or a district (新町, 中央) where the bare query drowns in unrelated
    /// transport.
    ///
    /// Two queries for every country but Japan, Taiwan, Hong Kong and Macao,
    /// which get a third: a live audit of 400 Japanese stations found 8 whose
    /// kanji an English-language map service answers nothing for at all —
    /// 新豊田, 本町, 近鉄名古屋 — while "<romaji> Station" found each of them
    /// at 2-187 m. The same English-service sweep found the Chinese query
    /// answering nothing for some Taiwan and Hong Kong stations too — 灣仔
    /// found only Admiralty, 動物園 only the gondola — while "Wan Chai
    /// Station" and "Taipei Zoo Station" found the station itself at 18-89 m.
    /// Korea's own packages already spell the word into the station's name
    /// (서울역), so there is nothing a third, English query would add there.
    public static func queries(for station: Station) -> [String] {
        guard let primary = station.names.first else { return [] }
        let word = stationWord(country: station.country)
        // Korea's packages spell the word into the station's own name (서울역),
        // and 東京駅前 is a Japanese name that ends in one without being one.
        // Either way a second query would ask for 서울역역.
        var plan = primary.hasSuffix(word) ? [primary] : [primary, primary + word]
        let countriesWithARomajiFallback: Set<String> = ["jp", "tw", "hk", "mo"]
        if countriesWithARomajiFallback.contains(station.country.lowercased()),
            let romaji = station.names.first(where: isLatinScript)
        {
            // `word` is the CJK/Hangul word for "station" and is never a
            // suffix of a Latin name, so the check has to read the Latin
            // spelling's own endings instead.
            // Whole last words only: "Costa" and "Vista" are not stations.
            let lowered = romaji.lowercased()
            let lastWord = lowered.split(whereSeparator: { $0 == " " || $0 == "-" }).last.map(String.init) ?? lowered
            let alreadyNamesAStation =
                ["station", "sta.", "stn", "sta", "terminus", "depot"].contains(lastWord)
            let suffixed = alreadyNamesAStation ? romaji : romaji + " Station"
            if !plan.contains(suffixed) {
                plan.append(suffixed)
            }
        }
        return plan
    }

    /// The local word for "station", appended only when the bare query failed.
    ///
    /// Korea's 역 and Japan's 駅 are suffixes of the station's own name in both
    /// countries' data; the Chinese-speaking regions write 站. There is no
    /// entry for a country this app does not carry, and the default is 站
    /// rather than an empty string so that a sixth package added later gets a
    /// query rather than a repeat of the first one.
    public static func stationWord(country: String) -> String {
        switch country.lowercased() {
        case "jp": return "駅"
        case "kr": return "역"
        default: return "站"
        }
    }

    // MARK: - Choosing the winner

    /// The index of the place that IS this station, or `nil` when none of them
    /// is.
    ///
    /// `nil` is a real answer and the common one outside the map service's own
    /// territory: a device on the China service returns
    /// `MKError.placemarkNotFound` for every Japanese and Korean query it is
    /// given. The caller falls back to the coordinate pin, which is what this
    /// card sent before any of this existed — the feature can only add a
    /// better link, never take the working one away.
    public static func best(_ candidates: [Candidate], for station: Station) -> Int? {
        bestMatch(candidates, for: station)?.index
    }

    /// The same winner as `best`, plus whether it is only a `.namedStop` —
    /// the tier ranked below every other one, and the one a caller running a
    /// multi-query plan must not settle for while a later step in
    /// that SAME plan might still answer with something stronger. A caller
    /// with only one step of candidates to offer can ignore `isWeak` and use
    /// `best` instead.
    ///
    /// `isTransport` says whether the winner carries Apple's transport
    /// category. A plan holding a weak `.namedStop` — itself always transport,
    /// within 150 m — must not trade it for an untyped winner from the
    /// filter-off pass: that pass returns the landmark a light-rail stop is
    /// named after (Kaohsiung Exhibition Center, the hall, 249 m away) ahead
    /// of the stop itself (0 m), and the hall is not where the train is.
    public static func bestMatch(_ candidates: [Candidate], for station: Station)
        -> (index: Int, isWeak: Bool, isTransport: Bool)?
    {
        let aliases = normalizedNames(of: station)
        guard !aliases.isEmpty else { return nil }
        var winner: (index: Int, tier: Tier, metres: Double)?
        for (index, candidate) in candidates.enumerated() {
            guard let tier = tier(of: candidate, aliases: aliases) else { continue }
            guard candidate.metres <= tier.maxMetres else { continue }
            if let current = winner,
                (current.tier.rawValue, current.metres) <= (tier.rawValue, candidate.metres)
            {
                continue
            }
            winner = (index, tier, candidate.metres)
        }
        guard let winner else { return nil }
        return (winner.index, winner.tier == .namedStop, candidates[winner.index].isPublicTransport)
    }

    /// How good a match one candidate is, best first.
    ///
    /// Named rather than numbered because the ORDER is the rule. A candidate
    /// whose own name is the station's always beats one that only mentions it,
    /// however much closer the second one is — which is what settles 金鐘, where
    /// the service offers the station itself at 137 m and a road stop called
    /// 金钟道(金钟港铁站)(东行方向) at 5 m. Distance alone picks the road stop.
    enum Tier: Int {
        /// Its own name, categorised as transport: 妈阁, 金钟站, 台北车站.
        case station = 0
        /// The same, wearing a bracket — Apple holds 台北车站 and
        /// 台北车站(地铁站) as separate places, and the one without the
        /// parenthesis is the station rather than one of its entrances.
        case qualifiedStation = 1
        /// Its own name, but the service gave it no transport category. Real
        /// for the second search pass, which drops the category filter.
        case untypedStation = 2
        case qualifiedUntypedStation = 3
        /// Its name only in a bracket, on a place named after something else:
        /// Hong Kong's street-running tram stops are held as
        /// 高士威道(信德街)(西行方向) — the road, then the stop, then which way
        /// the rails point.
        case namedInQualifier = 4
        case untypedNamedInQualifier = 5
        /// An English "Stop" on a name that is not otherwise the station's
        /// own — Hong Kong's tram network holds street furniture as "Whitty
        /// Street Stop" rather than under 屈地街 itself. Ranked below every
        /// other tier because "Stop" is also the English rendering of a bus
        /// stop's Chinese name, and the safer reading loses to any tier that
        /// matched the station more directly — not just within one response,
        /// but across an entire multi-query plan: `bestMatch` marks a
        /// `.namedStop` winner `isWeak`, and a caller running several queries
        /// for one station must keep it only as a fallback, in case a later
        /// query in the SAME plan answers with a stronger tier.
        case namedStop = 6

        /// How far this kind of match may sit from the platform.
        ///
        /// The bracket tiers are held to 150 m rather than the full budget
        /// because the shape they match is a street: 渣華道's own tram stop is
        /// 7 m away and four OTHER stops on the same road carry the same street
        /// name between 300 m and 1.2 km. The looser cap would pick whichever
        /// the service happened to list first. The named-stop tier is held to
        /// the same cap for the same reason.
        var maxMetres: Double {
            switch self {
            case .namedInQualifier, .untypedNamedInQualifier, .namedStop: return 150
            default: return StationPlaceLink.maxMetres
            }
        }
    }

    static func tier(of candidate: Candidate, aliases: Set<String>) -> Tier? {
        guard !isRoadTransport(candidate.name) else { return nil }
        let brackets = qualifiers(in: candidate.name)
        let name = normalize(candidate.name)
        let matchesWhole = !name.isEmpty && aliases.contains(name)
        if matchesWhole || matchesSegment(of: candidate.name, aliases: aliases) {
            switch (candidate.isPublicTransport, brackets.isEmpty) {
            case (true, true): return .station
            case (true, false): return .qualifiedStation
            case (false, true): return .untypedStation
            case (false, false): return .qualifiedUntypedStation
            }
        }
        if brackets.contains(where: { aliases.contains(normalize($0)) }) {
            return candidate.isPublicTransport ? .namedInQualifier : .untypedNamedInQualifier
        }
        return namedStopTier(of: candidate, aliases: aliases)
    }

    /// Whether one "/"-separated half of the candidate's bare name is one of
    /// the station's aliases — Apple's "Caoya / KRTC Station" only carries
    /// 草衙 in the first half, and Apple's "Xyz / KRTC Station" is not the
    /// station because the OTHER half is what it names.
    private static func matchesSegment(of rawName: String, aliases: Set<String>) -> Bool {
        let plain = bare(rawName)
        guard plain.contains("/") || plain.contains("／") else { return false }
        return plain.components(separatedBy: CharacterSet(charactersIn: "/／"))
            .map { normalize($0.trimmingCharacters(in: .whitespaces)) }
            .contains { !$0.isEmpty && aliases.contains($0) }
    }

    /// The lowest tier: an English "Stop" whose remainder is one of the
    /// station's aliases.
    ///
    /// The remainder is checked BEFORE it is normalized for one thing
    /// `normalize` would otherwise hide: whether it still ends in a station
    /// word of its own. "Taian Station Stop" is the English form of a bus
    /// stop's Chinese name, 泰安(公交站), and rejecting it here — rather than
    /// letting a plain "Stop" suffix waved it through — is what keeps this
    /// tier from re-admitting the road stops `isRoadTransport` was written to
    /// turn away.
    private static func namedStopTier(of candidate: Candidate, aliases: Set<String>) -> Tier? {
        guard candidate.isPublicTransport else { return nil }
        let plain = bare(candidate.name).trimmingCharacters(in: .whitespacesAndNewlines)
        guard plain.lowercased().hasSuffix(" stop") else { return nil }
        let remainder = String(plain.dropLast(" stop".count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remainder.isEmpty else { return nil }
        let strippedRemainder = remainder.lowercased().filter { $0.isLetter || $0.isNumber }
        let endsInAStationWord = stationWords.contains {
            strippedRemainder.count > $0.count && strippedRemainder.hasSuffix($0)
        }
        guard !endsInAStationWord else { return nil }
        let normalized = normalize(remainder)
        guard !normalized.isEmpty, aliases.contains(normalized) else { return nil }
        return .namedStop
    }

    /// Whether a result is a road stop rather than a railway station.
    ///
    /// Read off the RAW name, before `normalize` throws the qualifier away: the
    /// bus stop outside 台北车站 is called 台北车站(公交站) and normalises to
    /// exactly the same string as the station itself. Distance cannot separate
    /// them either — it stood 114 m from the platform, closer than several of
    /// the complex's own entrances.
    public static func isRoadTransport(_ raw: String) -> Bool {
        let text = raw.lowercased()
        return roadMarkers.contains { text.contains($0) }
    }

    // MARK: - Folding names

    /// One name reduced to the form both sides can be compared in.
    ///
    /// The order matters. Qualifiers come off first so that a parenthesis
    /// cannot survive as punctuation; the width and case folds run before
    /// anything is matched by text; the marks come off both before and after
    /// the Chinese fold, because 車站 folds to 车站 and only one of the two
    /// spellings can be listed first.
    ///
    /// A name that the marks would empty keeps its unstripped form: a station
    /// may be called nothing but 駅前, and answering "" would match it to every
    /// other station whose name is a bare station word.
    public static func normalize(_ raw: String) -> String {
        var text = bare(raw)
        text = foldWidth(text).lowercased()
        text = foldLatinDiacritics(text)
        text = text.filter { $0.isLetter || $0.isNumber }
        text = stripMarks(text)
        text = simplified(text)
        text = stripMarks(text)
        return text
    }

    /// Nishijō → nishijo, so either side's macroned romaji folds to the same
    /// string as the other's plain spelling. The direction is not fixed to one
    /// side: the packages carry macrons too — Kansai-Kūkō is the package's own
    /// name — and the fold runs the same way on both, so it does not matter
    /// which side wrote the macron.
    ///
    /// NFD-decomposes so a macron, acute or other diacritic separates out into
    /// its own combining mark, drops only the combining marks in the Latin
    /// range U+0300...U+036F, and NFC-recomposes what is left. This is a
    /// custom fold so exactly which marks are dropped is explicit: only
    /// U+0300–U+036F; kana voicing marks and Hangul jamo are outside that
    /// range.
    static func foldLatinDiacritics(_ text: String) -> String {
        let decomposed = text.decomposedStringWithCanonicalMapping
        let stripped = String(
            decomposed.unicodeScalars.filter { !(0x0300...0x036F).contains($0.value) })
        return stripped.precomposedStringWithCanonicalMapping
    }

    /// Whether a name's letters are all Latin, once macrons and the like are
    /// folded off. Used to find the romaji spelling among a Japanese
    /// station's names, whichever position it is carried in.
    static func isLatinScript(_ name: String) -> Bool {
        let folded = foldLatinDiacritics(name.lowercased())
        let letters = folded.filter { $0.isLetter }
        guard !letters.isEmpty else { return false }
        return letters.allSatisfy { $0.isASCII }
    }

    /// Every spelling of the station, folded — and, for a package name that
    /// is two names joined by "/", each half as well.
    ///
    /// The Taiwan package spells the Kaohsiung stops 凱旋/前鎮之星 and
    /// 凹子底/愛河之心 that way while Apple holds "Aozihdi Station" and
    /// "Kaisyuan Station (Light Rail Cianjhen Star Station)": only a half
    /// matches. The cost is that 台北101/世貿 also gains the alias
    /// "taipei101", which the tower could answer to on the filter-off pass;
    /// the station's whole name matches on the first pass, so the tower is
    /// never asked. A candidate's own "/" — "Caoya / KRTC Station" — is split
    /// on its side instead, in `matchesSegment(of:aliases:)`.
    static func normalizedNames(of station: Station) -> Set<String> {
        var names: [String] = []
        for name in station.names {
            names.append(name)
            let halves = name.split(whereSeparator: { $0 == "/" || $0 == "／" })
            if halves.count > 1 { names.append(contentsOf: halves.map(String.init)) }
        }
        return Set(names.map(normalize).filter { !$0.isEmpty })
    }

    /// The bracketed pieces of a name — `台北车站(地铁站)` has one.
    public static func qualifiers(in raw: String) -> [String] {
        var found: [String] = []
        var depth = 0
        var current = ""
        for character in raw {
            if openers.contains(character) {
                depth += 1
                if depth == 1 { current = "" ; continue }
            }
            if closers.contains(character), depth > 0 {
                depth -= 1
                if depth == 0 {
                    let trimmed = current.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty { found.append(trimmed) }
                    continue
                }
            }
            if depth > 0 { current.append(character) }
        }
        return found
    }

    /// A name with its bracketed pieces removed.
    static func bare(_ raw: String) -> String {
        var result = ""
        var depth = 0
        for character in raw {
            if openers.contains(character) { depth += 1; continue }
            if closers.contains(character), depth > 0 { depth -= 1; continue }
            if depth == 0 { result.append(character) }
        }
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? raw : trimmed
    }

    /// Ｊ→J and ７→7. Apple's Chinese data uses full-width Latin in operator
    /// prefixes and this app's packages do not.
    static func foldWidth(_ text: String) -> String {
        let mutable = NSMutableString(string: text) as CFMutableString
        guard
            CFStringTransform(
                mutable, nil, kCFStringTransformFullwidthHalfwidth, false)
        else { return text }
        return mutable as String
    }

    /// 臺北 → 台北, 金鐘 → 金钟, 媽閣 → 妈阁.
    ///
    /// One direction only, and towards Simplified, because the fold is
    /// many-to-one: every Traditional spelling has a Simplified form to land
    /// on, while going the other way has to guess between 髮 and 發. Applied to
    /// BOTH sides, so which script either of them started in stops mattering.
    /// Japanese kanji pass through it too — 東京 becomes 东京 — which is
    /// harmless for exactly the same reason.
    static func simplified(_ text: String) -> String {
        let mutable = NSMutableString(string: text) as CFMutableString
        guard CFStringTransform(mutable, nil, "Hant-Hans" as CFString, false) else {
            return text
        }
        return mutable as String
    }

    /// The word for "station" and the operator's mark taken off, as many times
    /// as they are there.
    ///
    /// Both ends, because both ends carry them and neither side of the
    /// comparison is consistent about which. Apple writes 台北车站, 金钟站,
    /// 서울역 and Tokyo Station for stations the packages call 臺北, 金鐘, 서울
    /// and 東京; it writes 港铁金钟站 where the package writes 金鐘; and Hong
    /// Kong's own package writes 金鐘港鐵站 for the station Apple simply calls
    /// 金钟. Stripping only suffixes left that last pair unmatched — the
    /// station resolved to nothing and the card fell back to a pin.
    static func stripMarks(_ text: String) -> String {
        var result = text
        var changed = true
        while changed {
            changed = false
            for word in stationWords where result.count > word.count && result.hasSuffix(word) {
                result.removeLast(word.count)
                changed = true
            }
            for mark in operatorMarks {
                if result.count > mark.count, result.hasSuffix(mark) {
                    result.removeLast(mark.count)
                    changed = true
                }
                if result.count > mark.count, result.hasPrefix(mark) {
                    result.removeFirst(mark.count)
                    changed = true
                }
            }
        }
        return result.isEmpty ? text : result
    }

    // MARK: - The links

    /// The place itself, by the identity Apple Maps gave it.
    ///
    /// `/place?place-id=` is the modern form of the link Apple Maps' own share
    /// sheet writes, and it is the only one that carries the PLACE rather than
    /// a position: opened on a device it lands on the station's card, and
    /// opened in a browser it lands on the same card on the web.
    ///
    /// The identifier travels between map services. A place id read off the
    /// China service — `H2710I3F9267AE5EC56`, the prefix that service stamps —
    /// resolves on maps.apple.com to the same station, which is what makes this
    /// safe to SEND: a link is worth nothing if it only works on the device
    /// that wrote it.
    ///
    /// Nothing else may be added to the query. A `place-id` Apple cannot
    /// resolve answers 「找不到你搜尋的頁面」 and does NOT fall back to a `ll`
    /// or `q` sitting next to it, so belt-and-braces parameters would buy
    /// nothing and a malformed identifier must be caught here rather than
    /// papered over.
    public static func placeURL(placeID: String) -> URL? {
        let trimmed = placeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
            trimmed.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" })
        else { return nil }
        var components = URLComponents(string: "https://maps.apple.com/place")
        components?.queryItems = [URLQueryItem(name: "place-id", value: trimmed)]
        return components?.url
    }

    /// The station's position, captioned — what this card sent before places
    /// were resolved at all, and what it still sends when none is.
    ///
    /// `maps.apple.com` rather than the `maps://` scheme, because this is a
    /// link someone is going to SEND: an https URL opens Apple Maps when it
    /// lands on a device that has it and a web map when it does not, while a
    /// custom scheme is dead text everywhere else.
    ///
    /// Both `ll` and `q` are given, and they do different jobs: `ll` is where
    /// the pin goes — the station's own surveyed position, which is the whole
    /// point of sending it — and `q` is what the pin is called. With `q` alone
    /// Apple Maps runs a SEARCH, and a search for a station name is not the
    /// same thing as a place: it can land on a bus stop of the same name two
    /// streets away, or on nothing at all outside Japan.
    public static func pinURL(name: String, latitude: Double, longitude: Double) -> URL {
        var components = URLComponents(string: "https://maps.apple.com/")!
        components.queryItems = [
            URLQueryItem(name: "ll", value: "\(latitude),\(longitude)"),
            URLQueryItem(name: "q", value: name),
        ]
        return components.url ?? URL(string: "https://maps.apple.com/")!
    }

    // MARK: - Tables

    /// Written 站 in Chinese, 駅 in Japanese, 역 in Korean and "station" in
    /// English, with the compounds listed so the loop can take them off whole.
    /// Both scripts of every Chinese compound appear because the strip runs
    /// once before the Simplified fold and once after it.
    static let stationWords: [String] = [
        "火車站", "火车站", "車站", "车站", "地鐵站", "地铁站",
        "捷運站", "捷运站", "輕軌站", "轻轨站",
        "站", "駅", "역", "mainstation", "railwaystation", "trainstation", "station", "stn",
    ]

    /// Operator marks either side glues to a station's name — 港铁金钟站 on
    /// Apple's, 金鐘港鐵站 in this app's own Hong Kong package.
    ///
    /// Longest first, because the loop takes the first match it finds and
    /// 澳門輕軌 would otherwise be left holding 澳門 after 輕軌 came off.
    static let operatorMarks: [String] = [
        "臺灣鐵路管理局", "台灣鐵路管理局", "台湾铁路管理局",
        "澳門輕軌", "澳门轻轨", "東京地鐵", "东京地铁", "台湾高铁", "臺灣高鐵",
        "港鐵", "港铁", "台鐵", "臺鐵", "台铁", "高鐵", "高铁",
        "捷運", "捷运", "地鐵", "地铁", "輕軌", "轻轨", "都營", "都营",
        "thsr", "mtr",
        "taiwanhighspeedrail", "highspeedrail", "hsr", "lightrail",
    ]

    /// What a road stop is called, in the languages the five packages are read
    /// in. Matched against the raw name, qualifier included.
    static let roadMarkers: [String] = [
        "公交", "巴士", "公車", "公车", "客運站", "客运站",
        "バス", "버스", "bus stop", "bus station",
    ]

    private static let openers: Set<Character> = ["(", "（", "[", "［", "【", "〔", "〈"]
    private static let closers: Set<Character> = [")", "）", "]", "］", "】", "〕", "〉"]
}
