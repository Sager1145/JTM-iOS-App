import CoreLocation
import Foundation
import MapKit
import RailCore
import RailPresentation

/// The seven regional packages, and how an itinerary is matched to one.
///
/// **This is not a port.** The web app has a region *switch*: one package is
/// loaded, one store is open, and everything downstream simply uses "the
/// current country". This app draws all seven networks at once, so the
/// question "which package is this ride measured against?" has to be answered
/// per itinerary. That answer lives here.
///
/// It is kept out of `RailCore` for the reason `NetworkLOD` is: there is no
/// JavaScript to check it against, and mixing a policy of our own into the
/// ported tier would make the parity fixtures meaningless. What `RailCore`
/// carries is only the stored field — `Train.region` — because that is part of
/// the document, not part of the policy.
///
/// ## How a ride is matched
///
/// In order, stopping at the first that answers:
///
/// 1. **What the file says.** `Train.region`, when the store carries one.
/// 2. **The stops' station codes, when they name a region.** Japan's are the
///    six-digit `N02_005c`, and the packages' own group ids are spelled
///    `"<region>-official-…"`. Either answers outright.
/// 3. **The route sections' endpoint codes**, by the same rule. The sections'
///    `line_names` are deliberately NOT consulted: they are names, not ids,
///    and carry no region.
///
/// A ride that answers none of these is Japanese, which is the same fallback
/// `StoreOperations.createBlankTrain(country:)` makes for an unrecognised
/// country: the JavaScript's `if`-chain with no `else`.
///
/// ## And a ride that answers more than one
///
/// The first five packages could not produce one: none of those networks
/// reaches another. The United States and Canada do — the *Maple Leaf* runs
/// Toronto to New York, the *Adirondack* Montréal to New York, the *Cascades*
/// Eugene to Vancouver — and their packages are split at the border like every
/// other package family, so a stop list really does name two regions.
///
/// ``matched(_:)`` still answers ONE, the region the journey starts in,
/// because a ride is dated, listed and filed under one country and the country
/// it set out from is the one that says which. What the crossing changes is
/// which network it is *solved* against, and that is ``regionsTouched(_:)``:
/// the set of packages whose track the ride can legitimately use. Asking the
/// solver for one region's graph when the ride ends in another is how a
/// journey to Montréal comes back 無法繪製路線.
///
/// ## What the ride stores actually carry, and why (2) is not enough
///
/// The codes in a train store are `n02_station_code`, not the packages' group
/// ids, and outside Japan they are the OPERATOR's own spelling — `TYMC-A13`
/// (a TDX StationUID), `AEL-MTR-HOK`, `MLM-TAIPA-MLM-BARRA`,
/// `KR-GYEONGBUSEON-BUSAN`. Only Korea's happens to begin with its region.
/// Nothing in the string says Taiwan or Hong Kong, and a rule invented from
/// the operator prefixes that ship today would be a guess that breaks on the
/// next operator.
///
/// So the real answer for those codes comes from the data: the four non-Japanese
/// `stations-*.json` carry `n02_station_code` beside `n02_group_code`, and
/// ``RegionCodeIndex`` reads the pairing. That lookup is asynchronous and runs
/// ONCE, over the rides a store arrives untagged with — after which every ride
/// carries `region` and this synchronous path is exact.
enum Region: String, CaseIterable, Identifiable, Sendable, Hashable {
    case jp
    case tw
    case hk
    case mo
    case kr
    case us
    case ca

    var id: String { rawValue }

    /// The string every `RailCore` entry point calls `country`.
    var code: String { rawValue }

    /// The regions in the order the interface offers them — smallest network
    /// first, which is also least to most demanding on the renderer.
    static let ordered: [Region] = [.mo, .hk, .tw, .kr, .ca, .jp, .us]

    /// The catalog key for this region's name, so the interface reads in the
    /// reader's language rather than in Chinese for everybody.
    var localizationKey: String { "country.\(rawValue)" }

    /// The untranslated fallback, for the moment before a catalog is loaded.
    var fallbackName: String {
        switch self {
        case .jp: "日本 Japan"
        case .tw: "臺灣 Taiwan"
        case .hk: "香港 Hong Kong"
        case .mo: "澳門 Macao"
        case .kr: "한국 Korea"
        case .us: "美國 United States"
        case .ca: "加拿大 Canada"
        }
    }

    /// A bundled dataset's name for one country, under the web app's own
    /// naming: Japan's carries no suffix, and every other country's is the
    /// family plus `-<code>` — `stations.json`, `stations-tw.json`.
    ///
    /// One rule rather than four. `copy-rail-packages.sh` ships these files
    /// under exactly this spelling, and the route store, the edge index and
    /// the readings store had each grown their own `country == "jp" ? "" :
    /// "-\(country)"` beside a call that used it. A naming rule with four
    /// authors is a rule that drifts on the first family that is added.
    ///
    /// Takes a country string rather than a `Region` because the callers hold
    /// one, and because a country this enum does not carry must still resolve
    /// to the name it resolved to before rather than to nothing.
    static func countrySuffixed(_ family: String, country: String) -> String {
        country == "jp" ? family : "\(family)-\(country)"
    }

    /// The rail package in the app bundle.
    ///
    /// The only family that is not country-suffixed: a package is named for
    /// the year it was surveyed, so Japan's is `jp-2025` and carries its code
    /// like every other.
    static func packageResource(country: String) -> String { "\(country)-2025" }

    /// The rail package in the app bundle, for a region already in hand.
    var packageResource: String { Self.packageResource(country: rawValue) }

    // MARK: - how much country there is to read

    /// How large this region's shipped data is, as a decision rather than a
    /// number.
    ///
    /// The seven regions are not seven of a kind. Measured on the files this
    /// build ships:
    ///
    ///     region   package    sections   stations
    ///     mo         8 KB        7 KB        7 KB
    ///     hk       164 KB      188 KB      204 KB
    ///     tw       481 KB      529 KB      228 KB
    ///     kr       846 KB      949 KB      648 KB
    ///     ca      1464 KB     1538 KB      634 KB
    ///     us      6689 KB     7147 KB     3375 KB
    ///     jp      9321 KB    11824 KB     3180 KB
    ///
    /// Japan and the United States are an order of magnitude away from the
    /// other five and two orders from Macao, and every read of them is
    /// hundreds of milliseconds of host time — several times that on a phone.
    /// Treating all seven the same means either making Macao wait for Japan's
    /// policy or giving Japan Macao's, and the app did the second: it read
    /// every region eagerly, concurrently, at launch, because when the app had
    /// five networks totalling 10 MB that was affordable and nobody had to
    /// decide.
    ///
    /// So the split is named here, once, and the three places whose strategy
    /// depends on it ask this rather than each keeping a list of country
    /// codes: the launch badge index, the statistics edge index, and the
    /// journey solver's datasets.
    ///
    /// **The boundary is a fact about the DATA, not a tuning knob.** A region
    /// is `large` when reading one of its files is a wait a reader would
    /// notice on its own; ~1.5 MB (Canada) is not and ~6.5 MB is. A new
    /// country belongs on whichever side its files put it, and `verify.sh`
    /// checks that the classification still matches the shipped bytes.
    enum DataWeight: Sendable {
        /// Read whole, concurrently with its peers. The whole class together
        /// is smaller than either `large` region alone.
        case compact
        /// Read on demand and one at a time.
        case large
    }

    var dataWeight: DataWeight {
        switch self {
        case .jp, .us: .large
        case .mo, .hk, .tw, .kr, .ca: .compact
        }
    }

    /// The same answer for a country string, which is what the caches key on.
    ///
    /// A country this catalog does not carry is `large`: an unknown package
    /// has no measured size, and the cautious reading of a file of unknown
    /// length is the one that does not start six others beside it.
    static func dataWeight(country: String) -> DataWeight {
        Region(rawValue: country)?.dataWeight ?? .large
    }

    /// The regions of one weight, in catalog order.
    static func ordered(_ weight: DataWeight) -> [Region] {
        ordered.filter { $0.dataWeight == weight }
    }

    // MARK: - matching a ride to a region

    /// The string rule behind every match below.
    ///
    /// The rule itself is `RailPresentation.RegionScopeRule`, one tier down,
    /// where `swift test` can reach it — the app target has no test target
    /// under it, and "which two packages does the *Adirondack* need, and in
    /// what order is their shared graph laid down" is exactly the kind of
    /// claim that has to be checked rather than reviewed. This is the same
    /// arrangement ``clock`` makes with ``RegionClock``, for the same reason.
    ///
    /// What stays HERE is what only the catalog knows: which regions exist,
    /// what order they are in, and that a ride naming none of them is
    /// Japanese. `allCases` rather than ``ordered``, because this order is
    /// part of a persisted-looking key (``scopeKey(_:)``) rather than of a
    /// menu.
    static let scopeRule = RegionScopeRule(
        regionCodes: Region.allCases.map(\.code),
        numericCodeRegion: Region.jp.code,
        fallback: Region.jp.code)

    /// The region a station code names, when it names one at all.
    ///
    /// Japan's `N02_005c` is six ASCII digits, and the packages' group ids
    /// begin `"<region>-official-"`. An operator's own code — which is what a
    /// train store actually carries outside Japan — names no region, and this
    /// answers `nil` for it rather than guessing. See the type's note.
    static func fromStationCode(_ code: String?) -> Region? {
        scopeRule.regionCode(forStationCode: code).flatMap(Region.init(rawValue:))
    }

    /// The region an itinerary belongs to, or `nil` when nothing in it says.
    ///
    /// Deliberately returns the *first* region any part of the ride names
    /// rather than a majority vote: a through service that crosses no border
    /// (and none of these five networks touch each other) has one region in
    /// every part, and a store that somehow mixed them would be a data fault
    /// worth seeing rather than averaging away.
    static func matched(_ train: Train) -> Region? {
        scopeRule.matched(train).flatMap(Region.init(rawValue:))
    }

    /// The region an itinerary is drawn and measured in — matched, or Japan.
    static func resolved(_ train: Train) -> Region { matched(train) ?? .jp }

    /// Every region this itinerary's stops and sections name, in the order the
    /// ride reaches them.
    ///
    /// One entry for all but a handful of journeys, and that is what makes it
    /// safe to hand to the solver: a single-region answer loads exactly the
    /// resources ``resolved(_:)`` would have loaded, and only a genuine
    /// crossing pays for two.
    ///
    /// Order is the ride's own — first stop first — rather than the enum's,
    /// because the first region is the one the journey is filed under. A ride
    /// that names none is `[.jp]`, the same fallback ``resolved(_:)`` makes.
    /// What a shared graph is BUILT in is ``RouteScope/graphRegions``, which
    /// is not this order and must not be.
    static func regionsTouched(_ train: Train) -> [Region] {
        let matched = scopeRule.regionCodesTouched(train).compactMap(Region.init(rawValue:))
        return matched.isEmpty ? [.jp] : matched
    }

    /// The key one merged solver graph is cached under.
    ///
    /// `"us"` for a journey inside the United States, `"us+ca"` for one that
    /// crosses into Canada. Sorted by the enum's own order rather than by the
    /// ride's, so that a Toronto→New York journey and a New York→Toronto one
    /// share a graph instead of building it twice.
    static func scopeKey(_ regions: [Region]) -> String {
        scopeRule.scopeKey(regions.map(\.code))
    }

    // MARK: - what time it is here

    /// The clock this region's journeys are dated on.
    ///
    /// The table itself is `RailPresentation.RegionClock`, one tier down,
    /// where `swift test` can reach it — the app target has no test target
    /// under it, and "which day is it in Macao" is exactly the kind of claim
    /// that has to be checked rather than reviewed. This property is only the
    /// bridge from the region catalog to that table.
    var clock: RegionClock { .forRegionCode(code) }

    // MARK: - where the country is

    /// The whole of this region's railway, as a region a camera can be set to
    /// — the 国家全图 the map opens on. See
    /// ``RailMapController/frameAtLaunch(_:)``.
    ///
    /// **Written down rather than measured**, and that is the whole point of
    /// it. Every other "frame this" in the app reduces `RailNetworkStore.lines`
    /// to a rect, which is exact and which is useless here: the five packages
    /// decode independently and Japan's 9.5 MB lands seconds behind Macao's
    /// 8 KB, so a camera that waits for lines before framing a country is a
    /// camera that MOVES seconds after launch — over whatever the reader has
    /// pinched to by then. A constant is answerable the moment the rides are,
    /// which is what lets the opening view be the opening view and not an
    /// interruption of one.
    ///
    /// The numbers are the exact extent of the shipped packages — every
    /// coordinate of every segment, not just the stations:
    ///
    /// ```sh
    /// python3 - <<'PY'
    /// import glob, json
    /// for path in sorted(glob.glob('app/public/rail/*-2025.json')):
    ///     points = [point
    ///               for line in json.load(open(path))['lines']
    ///               for segment in line.get('segments', [])
    ///               for point in segment[2]]
    ///     print(path,
    ///           min(p[1] for p in points), min(p[0] for p in points),
    ///           max(p[1] for p in points), max(p[0] for p in points))
    /// PY
    /// ```
    ///
    /// so this agrees with `store.lines` to the metre today, and is allowed to
    /// drift by a kilometre if a package is resurveyed without it: what it
    /// decides is where a camera opens, not what is drawn there.
    var networkExtent: MKCoordinateRegion {
        let box = Self.networkBounds(of: self)
        // Through the same shift the drawn network takes. `AppleMapDatum`'s
        // note has the sizes — half a kilometre in Taiwan, Hong Kong, Macao
        // and Korea — which is nothing across a country and everything across
        // Macao's five. A box measured in one datum and framed in the other
        // is the kind of quiet mismatch this app keeps at one boundary.
        let southWest = AppleMapDatum.display(
            Coordinate(lon: box.west, lat: box.south), country: code)
        let northEast = AppleMapDatum.display(
            Coordinate(lon: box.east, lat: box.north), country: code)
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (southWest.lat + northEast.lat) / 2,
                longitude: (southWest.lon + northEast.lon) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: northEast.lat - southWest.lat,
                longitudeDelta: northEast.lon - southWest.lon))
    }

    /// The five East Asian networks together.
    ///
    /// This is the neutral automatic-launch fallback: it is deliberately not
    /// any single country's extent, and it excludes the North American
    /// packages so an empty journey store still opens where this app's
    /// original network family lives.
    static var eastAsiaNetworkExtent: MKCoordinateRegion {
        combinedNetworkExtent(of: [.jp, .tw, .hk, .mo, .kr])
    }

    /// Every network at once — what "the whole world" means to an app whose
    /// world is seven networks.
    ///
    /// Not the globe, and with five networks it was not close to one: a camera
    /// showing the Earth would have been showing the reader four fifths of an
    /// ocean to make a point about scale. With North America in it the union
    /// really is most of a hemisphere, which is a fact about the data rather
    /// than a change of mind — this is still the union of the boxes, and it is
    /// still the view the map used to arrive at by accident once every package
    /// had decoded.
    ///
    /// The longitudes are folded on a CIRCLE, not on the number line, and that
    /// is not a nicety since the North American packages arrived: East Asia
    /// runs from 113°E to 146°E and North America from 150°W to 52°W, and a
    /// plain `min`/`max` puts the west edge at −150 and the east edge at +146.
    /// The box that describes is 295° wide and centred over Africa. It does
    /// contain both networks, so nothing was ever *missing* from it — the
    /// reader was simply shown the Atlantic in the middle of a view of the
    /// Pacific rim. Taking the smallest arc that covers every region instead
    /// gives 195° centred over the Pacific, which is the map somebody with
    /// journeys in Tokyo and Chicago is asking for.
    /// The longitude band is `RailPresentation.LongitudeArc`, one tier down,
    /// for the reason ``scopeRule`` and ``clock`` are: the app target has no
    /// test target under it, and "which way round the world is the short way
    /// from Vancouver to Wakkanai" is arithmetic rather than a judgement.
    static var everyNetworkExtent: MKCoordinateRegion {
        combinedNetworkExtent(of: Array(allCases))
    }

    /// One stable box for a set of catalog regions.
    ///
    /// Keeping the reduction here makes the empty-store East Asia fallback
    /// and the explicit “all networks” setting use exactly the same longitude
    /// wrapping rule.
    private static func combinedNetworkExtent(of regions: [Region]) -> MKCoordinateRegion {
        var south = 90.0, north = -90.0
        var edges: [LongitudeArc.Edges] = []
        for region in regions {
            let extent = region.networkExtent
            south = min(south, extent.center.latitude - extent.span.latitudeDelta / 2)
            north = max(north, extent.center.latitude + extent.span.latitudeDelta / 2)
            edges.append(LongitudeArc.Edges(
                west: extent.center.longitude - extent.span.longitudeDelta / 2,
                east: extent.center.longitude + extent.span.longitudeDelta / 2))
        }
        let arc = LongitudeArc.smallest(edges)
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (south + north) / 2, longitude: arc.center),
            span: MKCoordinateSpan(
                latitudeDelta: north - south, longitudeDelta: arc.span))
    }

    /// The package's own bounding box, in the WGS84 it is surveyed in.
    private static func networkBounds(
        of region: Region
    ) -> (south: Double, west: Double, north: Double, east: Double) {
        switch region {
        // Yonaguni is not on it and Okinawa's monorail is, so the south edge
        // is Naha rather than the southern tip of the country; the north is
        // Wakkanai and the east is Nemuro.
        case .jp: (26.193150, 127.652285, 45.416341, 145.598010)
        case .tw: (22.265252, 120.211958, 25.201089, 121.957939)
        case .hk: (22.240175, 113.935773, 22.528167, 114.274552)
        case .mo: (22.131407, 113.529403, 22.183615, 113.575406)
        case .kr: (34.615526, 126.386565, 38.257434, 129.430039)
        // The contiguous network: Key West to Vancouver's own Cascades
        // terminus, and the Olympic Peninsula to Bar Harbor.
        //
        // The Alaska Railroad and Honolulu's Skyline are in the package and
        // deliberately outside this box, which is the same decision the
        // comment above describes for Naha. Reaching Fairbanks would open the
        // map on the Gulf of Alaska and reaching O‘ahu on four thousand
        // kilometres of Pacific, in both cases to include a dozen stations —
        // and what this constant decides is where a camera OPENS, not what is
        // drawn there. Both draw exactly as they always would once the reader
        // is looking at them.
        case .us: (25.685313, -123.853418, 49.285105, -69.965602)
        // Vancouver Island to Halifax, and north to Churchill on the Hudson
        // Bay line.
        case .ca: (42.295547, -130.359435, 58.767690, -63.269876)
        }
    }
}

/// The networks one journey is solved against.
///
/// Almost always one, and the type exists for the few that are not. A journey
/// inside a country is solved against that country's `rail-sections` and
/// `stations` exactly as it always was; one that crosses is solved against
/// both countries' at once, because the alternative is asking the United
/// States' graph to find Montréal.
///
/// The two members answer two different questions and must not be confused:
///
/// * ``home`` is what `RailCore` is told the `country` is. It decides
///   normalisation, the institution-type filter and the route cache digest,
///   and it is the region the journey STARTS in — the one it is filed under.
/// * ``key`` names the working set: `"us"` for a journey inside the United
///   States, `"us+ca"` for one that crosses. It is what a cached graph is
///   filed under, so that the two Toronto–New York journeys in a log share the
///   graph they both need instead of building it twice.
///
/// The two countries whose journeys can be cross-border share one official
/// code space (`institution_type_code` / `railway_class_code`), so solving a
/// crossing under the home region's rules is not an approximation: the rules
/// are the same on both sides of the border.
struct RouteScope: Hashable, Sendable {

    /// Every region the journey reaches, in the order it reaches them.
    let regions: [Region]

    /// The region the journey is filed under, and whose rules solve it.
    var home: Region { regions.first ?? .jp }

    /// The same regions in the CATALOG's order — what a shared working set is
    /// built out of.
    ///
    /// Not ``regions``, and the difference is the whole point. Two journeys
    /// that cross the same border in opposite directions — the *Maple Leaf*
    /// Toronto to New York, the *Adirondack* New York to Montréal — reach
    /// their two packages in opposite orders and share one ``key``. Building
    /// the working set filed under that key in the ASKING journey's order
    /// would mean the graph `"us+ca"` names depends on which of the two
    /// happened to be solved first in a given launch: a `RouteNetwork`'s
    /// line-name index is insertion-ordered and load-bearing — the *Maple
    /// Leaf* is one name over two lines, one per country, and the first to
    /// reach a given score wins — so the same hop could canonicalise onto the
    /// American line one launch and the Canadian one the next.
    var graphRegions: [Region] {
        Region.scopeRule.canonicalOrder(regions.map(\.code))
            .compactMap(Region.init(rawValue:))
    }

    /// The string `RailCore` calls `country`.
    var code: String { home.code }

    /// The name of the working set. See the type's note.
    var key: String { Region.scopeKey(regions) }

    /// Whether this journey needs more than one package's track.
    var crossesBorder: Bool { regions.count > 1 }

    init(regions: [Region]) {
        self.regions = regions.isEmpty ? [.jp] : regions
    }

    /// The scope one itinerary is solved in.
    init(_ train: Train) {
        self.init(regions: Region.regionsTouched(train))
    }

    /// The heaviest region this scope has to read — what a caller ordering
    /// work by cost sorts on.
    ///
    /// A crossing is as expensive as its larger half: the *Maple Leaf* reads
    /// Canada's 1.8 MB of sections and the United States' 7.3, and there is no
    /// order of those two in which it finishes like a Canadian journey.
    var dataWeight: Region.DataWeight {
        regions.contains { $0.dataWeight == .large } ? .large : .compact
    }

    /// Scopes in the order the work should be done: the ones whose datasets
    /// are small first, and within each class the catalog's own order.
    ///
    /// Deterministic, which the thing it replaces was not. Grouping journeys
    /// by scope produces a `Dictionary`, and Swift seeds its hashing per
    /// process — so the order the scopes were walked in, and therefore the
    /// order the rides reached the map and the order they were drawn over one
    /// another, was different on every launch.
    static func ordered(_ scopes: some Sequence<RouteScope>) -> [RouteScope] {
        scopes.sorted { left, right in
            if left.dataWeight != right.dataWeight { return left.dataWeight == .compact }
            let leftHome = Region.ordered.firstIndex(of: left.home) ?? 0
            let rightHome = Region.ordered.firstIndex(of: right.home) ?? 0
            if leftHome != rightHome { return leftHome < rightHome }
            return left.key < right.key
        }
    }
}

extension Train {

    /// The clock this journey's dates are read on — its region's.
    ///
    /// Every "is this still ahead of me", "did this happen" and "what day is
    /// it" about a ride goes through here rather than through `Date()` and the
    /// device's zone. See ``JourneyClock`` for what a journey on more than one
    /// clock will change, and for why nothing here converts a printed stop
    /// time.
    var journeyClock: JourneyClock {
        let fallback = Region.resolved(self).clock
        // Five of the seven regions are one zone from end to end, so the
        // lookup below cannot change the answer for them and the table is
        // never even loaded. The guard is what keeps a Japanese journey from
        // taking a lock once per stop to be told what its region already said.
        guard StationClockSnapshot.shared.hasTable else {
            return JourneyClock(home: fallback)
        }
        let snapshot = StationClockSnapshot.shared
        let perStop = stops.map { stop in
            snapshot.clock(forStationCode: stop.n02StationCode) ?? fallback
        }
        guard !perStop.isEmpty else { return JourneyClock(home: fallback) }
        // On the journey's own day. Whether two of these stops are the same
        // clock is a question about a particular date — seven of the nine
        // North American zones move an hour twice a year — and the record
        // carries the day it ran. See ``JourneyClock/init(stops:fallback:on:)``.
        return JourneyClock(stops: perStop, fallback: fallback, on: date)
    }

    /// The same train with its region written down — when the ride actually
    /// says which one it is.
    ///
    /// A ride that says nothing is left ALONE rather than tagged Japanese.
    /// `Region.resolved` falls back to Japan because something has to be drawn
    /// and solved right now, but writing that fallback into the record would
    /// turn a guess into a stated fact, and the Taiwanese ride whose codes
    /// this pass could not read would be Japanese for ever. Those rides are
    /// resolved properly, once, by ``RegionCodeIndex``.
    func taggingRegion() -> Train {
        guard let region = Region.matched(self) else { return self }
        var copy = self
        copy.region = region.code
        return copy
    }
}


/// Which region a station code belongs to, read out of the shipped station
/// datasets rather than guessed from the string.
///
/// Only exists for rides that arrive without a `region` of their own: a store
/// written by the web app, or by a build of this app from before the merge —
/// and the five bundled samples, which ARE web-app stores (`copy-rail-packages.sh`
/// ships `app/data/train-store-*.json` unchanged, and none of them carries a
/// `region`). One pass tags them, they are saved with the answer, and this is
/// never consulted for them again.
///
/// It has to run BEFORE a ride is published, not as a correction afterwards.
/// An untagged ride is `Region.resolved`-as-Japanese, which means it is drawn
/// against Japan's package and solved against Japan's station table — so the
/// Macanese sample asks Japan's solver for 媽閣, and twenty seconds later the
/// journey card says 無法繪製路線.
///
/// Japan is deliberately absent from the index. Its own codes are recognisable
/// on sight (six digits), `stations.json` is 3.1 MB against 1.1 MB for the
/// other four together, and Japan is the fallback anyway — so loading it would
/// be three megabytes of work to confirm what not finding a code already says.
actor RegionCodeIndex {

    static let shared = RegionCodeIndex()

    private var codes: [String: Region]?

    /// The same rides, each carrying the region it belongs to.
    ///
    /// ``Train/taggingRegion()`` runs first and answers for everything it can
    /// read on sight — a ride that already says, and every Japanese one. Only
    /// what is left pays for the index, so a store this app saved never opens
    /// a dataset at all.
    ///
    /// A ride nothing can place is returned untagged, for the reason
    /// `taggingRegion()` leaves it alone: `Region.resolved` will draw it as
    /// Japanese either way, and writing that guess into the record would make
    /// it permanent.
    func tagging(_ trains: [Train]) -> [Train] {
        let known = trains.map { $0.taggingRegion() }
        guard known.contains(where: { $0.region == nil }) else { return known }
        let table = table()
        guard !table.isEmpty else { return known }
        return known.map { train in
            guard train.region == nil else { return train }
            let region = train.stops.lazy
                .compactMap { $0.n02StationCode.flatMap { table[$0] } }
                .first
            guard let region else { return train }
            var copy = train
            copy.region = region.code
            return copy
        }
    }

    /// The regions this index has to open a file for.
    ///
    /// Japan is absent because its codes are recognisable on sight (six
    /// digits), `stations.json` is 3.1 MB, and Japan is the fallback anyway.
    /// The United States and Canada are absent for the same reason and not for
    /// the size one: the North American build prefixes every station code with
    /// its region (`US-AMTRAK-CHI`, `CA-VIA-TRTO`), so
    /// ``Region/fromStationCode(_:)`` has already answered for them before
    /// this index is consulted. Loading their tables would be several
    /// megabytes of decoding to confirm what the string already said.
    private static let indexedRegions: [Region] =
        Region.allCases.filter { $0 != .jp && $0 != .us && $0 != .ca }

    private func table() -> [String: Region] {
        if let codes { return codes }
        var built: [String: Region] = [:]
        for region in Self.indexedRegions {
            guard let url = Bundle.main.url(
                    forResource: "stations-\(region.rawValue)", withExtension: "json"),
                  let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                  let decoded = try? JSONDecoder().decode(StationFile.self, from: data)
            else { continue }
            for feature in decoded.features {
                guard let code = feature.properties.n02StationCode, !code.isEmpty else { continue }
                built[code] = region
            }
        }
        codes = built
        return built
    }

    /// Only the one field this needs. Every other property — the geometry, the
    /// operator, the class codes — is ignored by `Decodable`, which is what
    /// keeps a 650 KB file from being decoded into objects nobody reads.
    private struct StationFile: Decodable {
        struct Feature: Decodable {
            struct Properties: Decodable {
                let n02StationCode: String?
                enum CodingKeys: String, CodingKey {
                    case n02StationCode = "n02_station_code"
                }
            }
            let properties: Properties
        }
        let features: [Feature]
    }
}


/// What the map opens on — the reader's own answer, or none.
///
/// The app has one opinion (``RailWorkspaceView/launchExtent``: the country of
/// the first journey ahead, else of the first in the log, else East Asia) and
/// it is a guess about somebody's plans, however well founded. This is the
/// setting that says it need not guess — 設定 › 啟動地圖範圍.
///
/// A `String` raw value because that is what `@AppStorage` can carry, and
/// because a stored preference outlives the build that wrote it: a mode this
/// build does not recognise reads back as ``auto`` rather than trapping.
enum LaunchMapScope: String, CaseIterable, Identifiable, Sendable {
    /// Decide from the rides. The default, and the only mode that can answer
    /// differently on two consecutive launches.
    case auto
    /// Every network at once — ``Region/everyNetworkExtent``.
    case world
    /// One country, named by a second preference. Which one is NOT stored in
    /// this enum: a reader who switches to 全球 and back should find the
    /// country they picked still there, and folding it in here would forget it.
    case region

    var id: String { rawValue }

    var localizationKey: String { "ios.launchScope.\(rawValue)" }

    var fallbackName: String {
        switch self {
        case .auto: "Automatic"
        case .world: "All networks"
        case .region: "One country or area"
        }
    }
}
