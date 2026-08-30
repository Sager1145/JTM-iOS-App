import Foundation
import RailCore
import RailPresentation

/// Which clock each station is on, for the two regions whose journeys can
/// change clock in the middle.
///
/// The five Asian packages need nothing here: each is one time zone from end
/// to end, so a journey's region names its clock and ``Region/clock`` answers.
/// The United States spans six zones and Canada six, and a single train
/// crosses them — the *Empire Builder* leaves Chicago on Central and arrives
/// in Seattle on Pacific — so for those two the clock is a property of the
/// STATION and has to be looked up.
///
/// ## Where the answer comes from
///
/// The operators', not ours. GTFS carries `stop_timezone` on a stop and
/// `agency_timezone` on the operator, the North American build copies whichever
/// applies onto every station it emits, and `stations-us.json` /
/// `stations-ca.json` carry it as `time_zone` beside the station's code. So
/// this file reads a fact each railway publishes about its own stations rather
/// than deciding one from a longitude — which would be wrong on the day it was
/// written for the several places where the zone boundary does not follow a
/// meridian at all.
///
/// ## Why it is a snapshot rather than an `await`
///
/// ``Train/journeyClock`` is a synchronous property read from view bodies and
/// from the statistics pass, and it existed before this file did. Making it
/// asynchronous would have pushed `await` into a dozen call sites to answer a
/// question that, for five of the seven regions, needs no lookup at all.
///
/// So the load is asynchronous and explicit — ``prime(regions:)``, called
/// where the rides are loaded — and the result is published into a snapshot
/// that the synchronous property reads. Before the snapshot arrives, a North
/// American journey answers its region's default clock, which is what it
/// answered before this file existed. Nothing is ever *wrong* while the table
/// is missing; it is only less specific.
///
/// This is deliberately the same shape as ``RegionCodeIndex``: read one field
/// out of the shipped station datasets, once, and never look at them again.
actor StationClockIndex {

    static let shared = StationClockIndex()

    /// The regions whose stations need a lookup at all. Everything else names
    /// its clock by naming its country.
    static let clockScopedRegions: Set<Region> = [.us, .ca]

    private var loaded: Set<Region> = []
    private var loading: [Region: Task<[String: String], Never>] = [:]

    /// Load the zone table for these regions, once, and publish the snapshot.
    ///
    /// A region that needs no table — every region but the two — is skipped
    /// without opening a file.
    func prime(regions: some Sequence<Region>) async {
        for region in regions where Self.clockScopedRegions.contains(region) {
            guard !loaded.contains(region) else { continue }
            let task = loading[region] ?? {
                let task = Task.detached(priority: .utility) {
                    Self.table(for: region)
                }
                loading[region] = task
                return task
            }()
            let table = await task.value
            loading[region] = nil
            loaded.insert(region)
            StationClockSnapshot.shared.merge(table, region: region)
        }
    }

    /// One region's `station code -> IANA zone identifier`.
    ///
    /// Both spellings of a station's identity are indexed — the operator's own
    /// code (`US-AMTRAK-CHI`) and the shared group code
    /// (`us-official-chicago-union`) — because a journey record may carry
    /// either, and a table that held one of them would answer for half the
    /// stops on a ride.
    private nonisolated static func table(for region: Region) -> [String: String] {
        guard let url = Bundle.main.url(
                forResource: Region.countrySuffixed("stations", country: region.code),
                withExtension: "json"),
              let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let decoded = try? JSONDecoder().decode(StationFile.self, from: data)
        else { return [:] }
        var built: [String: String] = [:]
        built.reserveCapacity(decoded.features.count * 2)
        for feature in decoded.features {
            let zone = feature.properties.timeZone
            guard let zone, !zone.isEmpty else { continue }
            if let code = feature.properties.stationCode, !code.isEmpty {
                built[code] = zone
            }
            if let group = feature.properties.groupCode, !group.isEmpty {
                // First writer wins: a group is one place and one clock, and a
                // later line's copy of it says the same thing.
                built[group] = built[group] ?? zone
            }
        }
        return built
    }

    /// Only the three fields this needs. Every other property of a 3 MB
    /// station file — the geometry, the operator, the class codes — is ignored
    /// by `Decodable`, which is what keeps this from decoding objects nobody
    /// reads.
    private struct StationFile: Decodable {
        struct Feature: Decodable {
            struct Properties: Decodable {
                let stationCode: String?
                let groupCode: String?
                let timeZone: String?
                enum CodingKeys: String, CodingKey {
                    case stationCode = "n02_station_code"
                    case groupCode = "n02_group_code"
                    case timeZone = "time_zone"
                }
            }
            let properties: Properties
        }
        let features: [Feature]
    }
}


/// The published answer, readable from anywhere without an `await`.
///
/// A class with a lock rather than an actor because its one reader is a
/// synchronous property (``Train/journeyClock``) called from view bodies. The
/// write happens once per region, at load; the reads are per journey and
/// frequent, so the lock is uncontended in the shape that matters.
final class StationClockSnapshot: @unchecked Sendable {

    static let shared = StationClockSnapshot()

    private let lock = NSLock()
    private var zonesByCode: [String: String] = [:]
    private var clocksByZone: [String: RegionClock] = [:]
    private var isEmpty = true

    fileprivate func merge(_ table: [String: String], region: Region) {
        guard !table.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        zonesByCode.merge(table) { existing, _ in existing }
        for zone in Set(table.values) where clocksByZone[zone] == nil {
            clocksByZone[zone] = .forZone(zone, regionCode: region.code)
        }
        isEmpty = zonesByCode.isEmpty
    }

    /// The clock one station code names, or `nil` when nothing here knows it.
    func clock(forStationCode code: String?) -> RegionClock? {
        guard let code, !code.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        guard !isEmpty, let zone = zonesByCode[code] else { return nil }
        return clocksByZone[zone]
    }

    /// Whether anything has been loaded yet — the cheap guard that keeps a
    /// Japanese journey from taking a lock per stop.
    var hasTable: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !isEmpty
    }
}
