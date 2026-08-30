//
//  RegionScope.swift — which packages one journey is solved against.
//

import Foundation
import RailCore

/// The rule that reads a journey's own codes and answers which regional
/// packages it needs.
///
/// **This is not a port**, for the reason ``RegionClock`` is not one: the web
/// app has a region switch and one active country, so it never has to ask
/// which of seven packages a ride belongs to. This app draws all seven at
/// once, and the question is per journey.
///
/// It lives one tier down from the app's `Region` catalog for the reason
/// `RegionClock` does — the app target has no test target under it, and
/// "which two packages does the *Adirondack* need?" is exactly the kind of
/// claim that has to be checked rather than reviewed. The catalog keeps what
/// only it can know (the enum, the localisation keys, the bounding boxes, the
/// `Bundle` lookups) and delegates the string rule to this.
///
/// ## Why the rule is written on strings
///
/// Because the facts it reads are strings. A stop carries
/// `n02_station_code`, a section carries two of them, and a record carries
/// `region` — all three arrive from a JSON document written by another
/// program, and none of them is guaranteed to name a region this build knows.
/// A rule expressed over an enum would have to invent an answer for those;
/// this one answers `nil` and lets the caller apply its own fallback.
///
/// ## The order the regions come back in
///
/// Two different orders are wanted and they must not be confused:
///
/// * ``regionCodesTouched(_:)`` answers in the JOURNEY's order — the region
///   it set out from first. That is the region the journey is filed under,
///   dated on and measured in, and the caller reads `.first` for it.
/// * ``canonicalOrder(_:)`` answers in the CATALOG's order, and it is what a
///   shared working set has to be built in. A Toronto→New York journey and a
///   New York→Toronto one touch the same two packages in opposite orders and
///   share one cache key (``scopeKey(_:)`` sorts); if the working set filed
///   under that key were built in the asking journey's order, then *which*
///   graph the key names would depend on which journey happened to be solved
///   first in a given launch. The line-name index inside a `RouteNetwork` is
///   insertion-ordered and load-bearing — the *Maple Leaf* is one name over
///   two lines, one per country, and the first to reach a given score wins —
///   so that is a route that could canonicalise differently between two
///   launches of the same build over the same store.
public struct RegionScopeRule: Sendable {

    /// Every region this build ships a package for, in the catalog's own
    /// order. It is the order ``canonicalOrder(_:)`` and ``scopeKey(_:)``
    /// answer in, so it must be stable across launches — it is part of a
    /// cache key.
    public let regionCodes: [String]

    /// The one region whose station codes are bare digits.
    ///
    /// Japan's N02 codes are six ASCII digits (`N02_005c` reaches a record as
    /// `005853`) and name no region on their face. Every other region's codes
    /// carry a prefix before the first dash, which is what
    /// ``regionCode(forStationCode:)`` reads. `nil` for a catalog with no such
    /// region.
    public let numericCodeRegion: String?

    /// How many digits such a code has. Six, and written down rather than
    /// "any length" so that a Korean or American code that happens to be all
    /// digits cannot be read as Japanese.
    public let numericCodeLength: Int

    /// The region a journey that names none belongs to.
    ///
    /// Not consulted by any of the lookups — they answer `nil` and let the
    /// caller decide — except ``regionCodesTouched(_:)``, which must return a
    /// non-empty list because its answer is the set of packages to load.
    public let fallback: String

    public init(
        regionCodes: [String],
        numericCodeRegion: String?,
        numericCodeLength: Int = 6,
        fallback: String
    ) {
        self.regionCodes = regionCodes
        self.numericCodeRegion = numericCodeRegion
        self.numericCodeLength = numericCodeLength
        self.fallback = fallback
    }

    /// A rule over no catalog at all — every lookup answers `nil` and every
    /// scope is the fallback. Present so a caller can be constructed in a
    /// context that has not been handed a catalog yet.
    public static let empty = RegionScopeRule(
        regionCodes: [], numericCodeRegion: nil, fallback: "")

    // MARK: - one station code

    /// The region a station code names, when it names one at all.
    ///
    /// Japan's is ``numericCodeLength`` ASCII digits; every other region's
    /// begins with something before a dash. Both spellings a record can carry
    /// are read by the same rule: the packages' own group ids are
    /// `"<region>-official-…"`, and the North American build prefixes the
    /// operator's code with the region too — `US-AMTRAK-RSP`, `CA-AMTRAK-RSP`,
    /// which is the pair of station codes the *Adirondack* crosses the border
    /// on, and is precisely why a Windsor in Ontario cannot answer for a
    /// Windsor in Connecticut when both packages are in one graph.
    ///
    /// An operator's own code that names no region — `TYMC-A13`,
    /// `AEL-MTR-HOK`, `MLM-TAIPA-MLM-BARRA` — answers `nil` rather than a
    /// guess. Those are placed from the shipped station tables instead; see
    /// the app's `RegionCodeIndex`.
    public func regionCode(forStationCode code: String?) -> String? {
        guard let code, !code.isEmpty else { return nil }
        if let numericCodeRegion, code.count == numericCodeLength,
            code.allSatisfy({ $0.isASCII && $0.isNumber })
        {
            return numericCodeRegion
        }
        guard let dash = code.firstIndex(of: "-") else { return nil }
        let head = String(code[code.startIndex..<dash]).lowercased()
        // `kr-official-busan` names Korea; `KR-GYEONGBUSEON-BUSAN` is an
        // operator code that merely starts with the same two letters, and it
        // happens to name Korea too. Both are accepted, and no region's
        // operator codes begin with another region's code, so this cannot
        // claim a region that is wrong.
        return regionCodes.contains(head) ? head : nil
    }

    // MARK: - one journey

    /// The region an itinerary belongs to, or `nil` when nothing in it says.
    ///
    /// In order, stopping at the first that answers: what the file says
    /// (`region`), the stops' station codes, then the route sections'
    /// endpoint codes. The sections' `line_names` are deliberately not
    /// consulted — they are names, not ids, and carry no region.
    ///
    /// Deliberately the FIRST region any part of the ride names rather than a
    /// majority vote. A journey is filed, dated and listed under one country,
    /// and the country it set out from is the one that says which.
    public func matched(_ train: Train) -> String? {
        if let declared = train.region, regionCodes.contains(declared) { return declared }
        for stop in train.stops {
            if let region = regionCode(forStationCode: stop.n02StationCode) { return region }
        }
        for section in train.routeSections ?? [] {
            if let region = regionCode(forStationCode: section.fromN02StationCode) {
                return region
            }
            if let region = regionCode(forStationCode: section.toN02StationCode) {
                return region
            }
        }
        return nil
    }

    /// Every region this itinerary's stops and sections name, in the order the
    /// ride reaches them.
    ///
    /// One entry for all but a handful of journeys, and that is what makes it
    /// safe to hand to the solver: a single-region answer loads exactly the
    /// resources ``matched(_:)`` would have loaded, and only a genuine
    /// crossing pays for two. A ride that names none answers `[fallback]`.
    ///
    /// The declared region comes first because it is what the record says
    /// about itself, and a store written by this app carries it.
    public func regionCodesTouched(_ train: Train) -> [String] {
        var seen: [String] = []
        func add(_ region: String?) {
            guard let region, !seen.contains(region) else { return }
            seen.append(region)
        }
        if let declared = train.region, regionCodes.contains(declared) { add(declared) }
        for stop in train.stops { add(regionCode(forStationCode: stop.n02StationCode)) }
        for section in train.routeSections ?? [] {
            add(regionCode(forStationCode: section.fromN02StationCode))
            add(regionCode(forStationCode: section.toN02StationCode))
        }
        return seen.isEmpty ? [fallback] : seen
    }

    // MARK: - the working set

    /// These regions in the catalog's order, with anything the catalog does
    /// not carry dropped.
    ///
    /// What a shared graph is BUILT in. See the type's note for why it may not
    /// be the asking journey's order.
    public func canonicalOrder(_ regions: [String]) -> [String] {
        regionCodes.filter { regions.contains($0) }
    }

    /// The key one merged working set is cached under.
    ///
    /// `"us"` for a journey inside the United States, `"us+ca"` for one that
    /// crosses into Canada — in the catalog's order rather than the ride's, so
    /// that a Toronto→New York journey and a New York→Toronto one share a
    /// graph instead of building it twice.
    public func scopeKey(_ regions: [String]) -> String {
        guard regions.count > 1 else { return regions.first ?? fallback }
        let ordered = canonicalOrder(regions)
        return ordered.isEmpty ? fallback : ordered.joined(separator: "+")
    }
}
