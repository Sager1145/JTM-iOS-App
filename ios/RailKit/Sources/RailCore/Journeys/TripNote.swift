import Foundation

/// A small event note the reader attaches to one trip: an incident, an
/// observation, an unscheduled stop, a crew change — anything. Stored on the
/// trip as `trip_notes` (see ``Train/tripNotes``) and written only when the
/// trip has at least one.
///
/// Placement is kept as stations and a fraction, never as drawn geometry, so a
/// note survives the route being solved again: the map recomputes where the
/// "!" sits from the trip's current route each time it draws.
///
/// The time is a service-day clock string relative to ``Train/date``, the same
/// rule as ``Stop/arrival``: `"HH:MM"`, with hours past 24 for the next day.
/// It is civil time in the trip's region (``RegionClock/forRegionCode(_:)``)
/// and carries no instant, so the phone's own time zone can neither shift
/// what is stored nor what is shown.
public struct TripNote: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    /// Free text the reader chose, e.g. "事故" or "Crew change". Never a
    /// fixed list; see ``TripNoteCategories``.
    public var category: String
    public var text: String
    public var time: String?
    public var anchor: TripNoteAnchor

    public init(id: String, category: String, text: String, time: String? = nil,
                anchor: TripNoteAnchor) {
        self.id = id
        self.category = category
        self.text = text
        self.time = time
        self.anchor = anchor
    }

    private enum CodingKeys: String, CodingKey { case id, category, text, time, anchor }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        category = (try? container.decodeIfPresent(String.self, forKey: .category)) ?? ""
        text = (try? container.decodeIfPresent(String.self, forKey: .text)) ?? ""
        // An unreadable time is dropped, not fatal: one odd note must never
        // stop the whole library from loading.
        time = (try? container.decodeIfPresent(String.self, forKey: .time))
            .flatMap { TripNoteTime.minutes($0) == nil ? nil : $0 }
        anchor = (try? container.decode(TripNoteAnchor.self, forKey: .anchor)) ?? .unknown(type: "")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(category, forKey: .category)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(time, forKey: .time)
        try container.encode(anchor, forKey: .anchor)
    }
}

/// A station as a note names it: the identifiers the trip's own ``Stop``
/// carries, with the name as the last resort.
public struct TripNoteStation: Codable, Equatable, Sendable {
    public var name: String
    public var stationID: String?
    public var n02StationCode: String?

    public init(name: String, stationID: String? = nil, n02StationCode: String? = nil) {
        self.name = name
        self.stationID = stationID
        self.n02StationCode = n02StationCode
    }

    public init(stop: Stop) {
        self.init(name: stop.name, stationID: stop.stationID, n02StationCode: stop.n02StationCode)
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case stationID = "station_id"
        case n02StationCode = "n02_station_code"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        stationID = try container.decodeIfPresent(String.self, forKey: .stationID)
        n02StationCode = try container.decodeIfPresent(String.self, forKey: .n02StationCode)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(stationID, forKey: .stationID)
        try container.encodeIfPresent(n02StationCode, forKey: .n02StationCode)
    }

    /// Whether `stop` is this station by identity: a stop with a station id
    /// matches only that id; otherwise the n02 code decides.
    public func matchesIdentity(_ stop: Stop) -> Bool {
        if let stationID, let other = stop.stationID { return stationID == other }
        if let n02StationCode, let other = stop.n02StationCode, n02StationCode == other {
            return true
        }
        return false
    }

    /// Whether `stop` carries this station's name, by UTF-16 code unit as
    /// ``RecordedRouteMapping/sameStation(code:name:otherCode:otherName:)``.
    public func matchesName(_ stop: Stop) -> Bool {
        !name.isEmpty && !stop.name.isEmpty && name.utf16.elementsEqual(stop.name.utf16)
    }

    /// The test to find this station among `stops`: identity when any stop
    /// matches by identity (a re-identified station elsewhere never beats the
    /// true match), otherwise the name.
    func matcher(in stops: [Stop]) -> (Stop) -> Bool {
        let byIdentity = stops.contains { matchesIdentity($0) }
        return { byIdentity ? self.matchesIdentity($0) : self.matchesName($0) }
    }
}

/// Where a note sits.
///
/// JSON: `{"type":"station","station":{…},"lat":…,"lon":…}`,
/// `{"type":"interval","from":{…},"to":{…},"fraction":0.4,"lat":…,"lon":…}` or
/// `{"type":"coordinate","lat":…,"lon":…}`. The coordinate on a station or
/// interval anchor is the place it was put, kept only as a fallback for when
/// the stations are no longer on the trip.
public enum TripNoteAnchor: Equatable, Sendable {
    case station(TripNoteStation, fallback: Coordinate?)
    /// Between two stations of the trip, `fraction` (0…1) of the way along
    /// the solved route from `from` to `to`.
    case interval(from: TripNoteStation, to: TripNoteStation, fraction: Double,
                  fallback: Coordinate?)
    case coordinate(Coordinate)
    /// A place this build cannot read (a newer kind, or a broken record).
    /// Kept by type name so it is written back as found rather than lost;
    /// such a note is listed but not drawn.
    case unknown(type: String)

    public var fallbackCoordinate: Coordinate? {
        switch self {
        case .station(_, let fallback), .interval(_, _, _, let fallback): fallback
        case .coordinate(let coordinate): coordinate
        case .unknown: nil
        }
    }
}

extension TripNoteAnchor: Codable {
    private enum CodingKeys: String, CodingKey { case type, station, from, to, fraction, lat, lon }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var coordinate: Coordinate?
        if let lat = try? container.decodeIfPresent(Double.self, forKey: .lat),
           let lon = try? container.decodeIfPresent(Double.self, forKey: .lon) {
            coordinate = Coordinate(lon: lon, lat: lat)
        }
        // Never throws past this point: a note whose place cannot be read
        // degrades (fallback coordinate, then `.unknown`) instead of failing
        // the trip — and with it the whole store — on load.
        let type = (try? container.decodeIfPresent(String.self, forKey: .type)) ?? ""
        let station = try? container.decodeIfPresent(TripNoteStation.self, forKey: .station)
        let from = try? container.decodeIfPresent(TripNoteStation.self, forKey: .from)
        let to = try? container.decodeIfPresent(TripNoteStation.self, forKey: .to)
        let fraction = try? container.decodeIfPresent(Double.self, forKey: .fraction)
        if type == "station", let station, !station.name.isEmpty {
            self = .station(station, fallback: coordinate)
        } else if type == "interval", let from, let to,
                  !from.name.isEmpty, !to.name.isEmpty {
            let f = fraction.flatMap { $0.isFinite ? min(max($0, 0), 1) : nil } ?? 0.5
            self = .interval(from: from, to: to, fraction: f, fallback: coordinate)
        } else if let coordinate {
            self = .coordinate(coordinate)
        } else {
            self = .unknown(type: type)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .station(let station, _):
            try container.encode("station", forKey: .type)
            try container.encode(station, forKey: .station)
        case .interval(let from, let to, let fraction, _):
            try container.encode("interval", forKey: .type)
            try container.encode(from, forKey: .from)
            try container.encode(to, forKey: .to)
            try container.encode(fraction, forKey: .fraction)
        case .coordinate:
            try container.encode("coordinate", forKey: .type)
        case .unknown(let type):
            try container.encode(type, forKey: .type)
        }
        if let coordinate = fallbackCoordinate {
            try container.encode(coordinate.lat, forKey: .lat)
            try container.encode(coordinate.lon, forKey: .lon)
        }
    }
}

/// Which stops of a trip an anchor names today, after whatever edits and
/// re-solves happened since it was put there.
public enum TripNotePlacement: Equatable, Sendable {
    /// At the stop with this index in ``Train/stops``.
    case station(stopIndex: Int)
    /// Between these two stop indices (`from < to`), `fraction` of the way.
    case interval(fromStopIndex: Int, toStopIndex: Int, fraction: Double)
    /// The stations are gone: only the stored coordinate is left.
    case coordinate(Coordinate)
    /// Nothing to place.
    case unplaced

    public static func resolve(_ anchor: TripNoteAnchor, stops: [Stop]) -> TripNotePlacement {
        switch anchor {
        case .station(let station, let fallback):
            if let index = stops.firstIndex(where: station.matcher(in: stops)) {
                return .station(stopIndex: index)
            }
            return fallback.map(TripNotePlacement.coordinate) ?? .unplaced
        case .interval(let from, let to, let fraction, let fallback):
            // The first `from` followed by a later `to`; a stop edited in
            // between widens the span rather than losing the note.
            let isFrom = from.matcher(in: stops)
            let isTo = to.matcher(in: stops)
            for start in stops.indices where isFrom(stops[start]) {
                if let end = stops[(start + 1)...].firstIndex(where: isTo) {
                    return .interval(fromStopIndex: start, toStopIndex: end, fraction: fraction)
                }
            }
            if let fallback { return .coordinate(fallback) }
            if let index = stops.firstIndex(where: isFrom) ?? stops.firstIndex(where: isTo) {
                return .station(stopIndex: index)
            }
            return .unplaced
        case .coordinate(let coordinate):
            return .coordinate(coordinate)
        case .unknown:
            return .unplaced
        }
    }
}

/// Service-day clock arithmetic for note times, done entirely in the trip's
/// region clock so the phone's zone is never consulted.
public enum TripNoteTime {
    /// Two service days: a note on an overnight train can sit up to 47:59.
    public static let maximumMinutes = 48 * 60 - 1

    /// Minutes after the service day's midnight, for `"HH:MM"` with hours
    /// 0…47. Nil for anything else.
    public static func minutes(_ text: String?) -> Int? {
        guard let text else { return nil }
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[1].count == 2, (1...2).contains(parts[0].count),
              let hours = Int(parts[0]), let minutes = Int(parts[1]),
              hours >= 0, (0..<60).contains(minutes) else { return nil }
        let total = hours * 60 + minutes
        return total <= maximumMinutes ? total : nil
    }

    public static func text(minutes: Int) -> String {
        let clamped = min(max(minutes, 0), maximumMinutes)
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }

    /// The instant `time` names on `serviceDate` in `clock`'s zone. Used only
    /// to drive a date picker that is itself pinned to that zone.
    public static func instant(serviceDate: String?, time: String?, clock: RegionClock) -> Date? {
        guard let minutes = minutes(time) else { return nil }
        let printed = String(format: "%02d:%02d", minutes / 60, minutes % 60)
        return clock.instant(serviceDate: serviceDate, clock: printed)
    }

    /// The service-day time `instant` falls on, or nil outside the two-day
    /// window. Without a service date, the plain civil time of day.
    public static func time(at instant: Date, serviceDate: String?, clock: RegionClock) -> String? {
        guard clock.startOfDay(serviceDate) != nil else {
            let parts = clock.calendar.dateComponents([.hour, .minute], from: instant)
            return text(minutes: (parts.hour ?? 0) * 60 + (parts.minute ?? 0))
        }
        return clock.serviceClock(of: instant, serviceDate: serviceDate)
    }

    /// The time a new note starts with: now, when now falls on the trip's
    /// service window; otherwise the anchor stop's own time, then the trip's
    /// departure.
    /// `clock` is the trip's resolved region clock. Required on purpose:
    /// `train.region` is absent on legacy records and would fall back to Japan.
    public static func suggested(for train: Train, stopIndex: Int?, now: Date,
                                 clock: RegionClock) -> String? {
        if let current = time(at: now, serviceDate: train.date, clock: clock) {
            if train.date != nil { return current }
        }
        let stop = stopIndex.flatMap { train.stops.indices.contains($0) ? train.stops[$0] : nil }
        for candidate in [stop?.departure, stop?.arrival, train.stops.first?.departure,
                          train.stops.first?.arrival] {
            if let candidate, let minutes = minutes(candidate) { return text(minutes: minutes) }
        }
        return train.date == nil ? time(at: now, serviceDate: nil, clock: clock) : nil
    }

    /// `"01:10"` and a day offset (1 for `"25:10"`), for display. Pure string
    /// arithmetic: identical under every device zone.
    public static func display(_ time: String?) -> (clock: String, dayOffset: Int)? {
        guard let minutes = minutes(time) else { return nil }
        return (text(minutes: minutes % (24 * 60)), minutes / (24 * 60))
    }
}

/// Category suggestions: what the reader typed before, most used first, then
/// the starter list for whatever is not covered yet.
public enum TripNoteCategories {
    public static func suggestions(from trains: [Train], starters: [String], limit: Int = 12) -> [String] {
        var counts: [String: Int] = [:]
        var firstSeen: [String: Int] = [:]
        var order = 0
        for train in trains {
            for note in train.tripNotes ?? [] {
                let category = note.category.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !category.isEmpty else { continue }
                counts[category, default: 0] += 1
                if firstSeen[category] == nil { firstSeen[category] = order; order += 1 }
            }
        }
        var result = counts.keys.sorted {
            counts[$0]! != counts[$1]! ? counts[$0]! > counts[$1]! : firstSeen[$0]! < firstSeen[$1]!
        }
        for starter in starters where !result.contains(starter) { result.append(starter) }
        return Array(result.prefix(limit))
    }
}

extension Train {
    /// The notes, or nil when there are none, so an emptied list stops being
    /// written rather than leaving `"trip_notes": []` behind.
    public mutating func setTripNotes(_ notes: [TripNote]) {
        tripNotes = notes.isEmpty ? nil : notes
    }
}

// MARK: - the store's dynamic-JSON path

extension TrainValidation {
    /// Lenient reading, like ``ticket(_:)``: a malformed note is dropped rather
    /// than sinking the whole trip, and an empty list reads as none.
    static func tripNotes(_ value: JSON?) -> [TripNote]? {
        guard case .array(let rows)? = value else { return nil }
        // Duplicate ids keep the first, so validation never rejects an import
        // over a hand-edited note list.
        var seen = Set<String>()
        let notes = rows.compactMap(tripNote).filter { seen.insert($0.id).inserted }
        return notes.isEmpty ? nil : notes
    }

    static func tripNote(_ value: JSON) -> TripNote? {
        guard case .object = value, let id = value["id"]?.stringOrNilIfNotString, !id.isEmpty,
              let anchor = tripNoteAnchor(value["anchor"]) else { return nil }
        return TripNote(
            id: id,
            category: value["category"]?.stringOrNilIfNotString ?? "",
            text: value["text"]?.stringOrNilIfNotString ?? "",
            // An unreadable time is dropped rather than failing the trip.
            time: value["time"]?.stringOrNilIfNotString.flatMap { TripNoteTime.minutes($0) == nil ? nil : $0 },
            anchor: anchor)
    }

    private static func number(_ value: JSON?) -> Double? {
        if case .number(let number)? = value, number.isFinite { return number }
        return nil
    }

    private static func tripNoteStation(_ value: JSON?) -> TripNoteStation? {
        guard let value, case .object = value,
              let name = value["name"]?.stringOrNilIfNotString else { return nil }
        return TripNoteStation(
            name: name,
            stationID: value["station_id"]?.stringOrNilIfNotString,
            n02StationCode: value["n02_station_code"]?.stringOrNilIfNotString)
    }

    private static func tripNoteAnchor(_ value: JSON?) -> TripNoteAnchor? {
        guard let value, case .object = value else { return nil }
        var coordinate: Coordinate?
        if let lat = number(value["lat"]), let lon = number(value["lon"]) {
            coordinate = Coordinate(lon: lon, lat: lat)
        }
        switch value["type"]?.stringOrNilIfNotString {
        case "station":
            guard let station = tripNoteStation(value["station"]), !station.name.isEmpty else {
                return coordinate.map { .coordinate($0) } ?? .unknown(type: "station")
            }
            return .station(station, fallback: coordinate)
        case "interval":
            guard let from = tripNoteStation(value["from"]), let to = tripNoteStation(value["to"]),
                  !from.name.isEmpty, !to.name.isEmpty else {
                return coordinate.map { .coordinate($0) } ?? .unknown(type: "interval")
            }
            let fraction = number(value["fraction"]).map { min(max($0, 0), 1) } ?? 0.5
            return .interval(from: from, to: to, fraction: fraction, fallback: coordinate)
        default:
            if let coordinate { return .coordinate(coordinate) }
            return .unknown(type: value["type"]?.stringOrNilIfNotString ?? "")
        }
    }

    static func json(_ notes: [TripNote]) -> JSON {
        .array(notes.map { note in
            var pairs: [(String, JSON)] = [
                ("id", .string(note.id)),
                ("category", .string(note.category)),
                ("text", .string(note.text)),
            ]
            if let time = note.time { pairs.append(("time", .string(time))) }
            pairs.append(("anchor", json(note.anchor)))
            return .object(JSON.Object(pairs))
        })
    }

    private static func json(_ station: TripNoteStation) -> JSON {
        var pairs: [(String, JSON)] = [("name", .string(station.name))]
        if let id = station.stationID { pairs.append(("station_id", .string(id))) }
        if let code = station.n02StationCode { pairs.append(("n02_station_code", .string(code))) }
        return .object(JSON.Object(pairs))
    }

    private static func json(_ anchor: TripNoteAnchor) -> JSON {
        var pairs: [(String, JSON)]
        switch anchor {
        case .station(let station, _):
            pairs = [("type", .string("station")), ("station", json(station))]
        case .interval(let from, let to, let fraction, _):
            pairs = [("type", .string("interval")), ("from", json(from)), ("to", json(to)),
                     ("fraction", .number(fraction))]
        case .coordinate:
            pairs = [("type", .string("coordinate"))]
        case .unknown(let type):
            pairs = [("type", .string(type))]
        }
        if let coordinate = anchor.fallbackCoordinate {
            pairs.append(("lat", .number(coordinate.lat)))
            pairs.append(("lon", .number(coordinate.lon)))
        }
        return .object(JSON.Object(pairs))
    }

    /// Facts a stored note must satisfy: unique ids and a readable time.
    static func tripNoteDiagnostics(_ train: Train) -> [Diagnostic] {
        var issues: [Diagnostic] = []
        var seen = Set<String>()
        for (offset, note) in (train.tripNotes ?? []).enumerated() {
            if !seen.insert(note.id).inserted {
                issues.append(Diagnostic(path: "trip_notes[\(offset)].id",
                                         reason: "trip_notes ids must be unique within a train."))
            }
            if let time = note.time, TripNoteTime.minutes(time) == nil {
                issues.append(Diagnostic(path: "trip_notes[\(offset)].time",
                                         reason: "trip_notes time must be HH:MM, 00:00–47:59."))
            }
        }
        return issues
    }
}

/// The text a note is shared as, shaped for Apple Notes: the first line
/// (which Notes takes as the title) is "Category · 01:10 (+1) JST", then
/// the place and the trip, a blank line, and the body exactly as stored.
/// The body is plain text with light Markdown habits ("- ", "- [ ]", bare
/// links), which Notes keeps as written.
public enum TripNoteShareText {
    public static func compose(category: String, time: String?, place: String?, trip: String?,
                               body: String) -> String {
        let headline = [category.trimmingCharacters(in: .whitespacesAndNewlines), time ?? ""]
            .filter { !$0.isEmpty }.joined(separator: " · ")
        var lines: [String] = []
        if !headline.isEmpty { lines.append(headline) }
        for detail in [place, trip] {
            if let detail, !detail.isEmpty { lines.append(detail) }
        }
        let trimmedBody = body.trimmingCharacters(in: .newlines)
        guard !trimmedBody.isEmpty else { return lines.joined(separator: "\n") }
        return lines.isEmpty ? trimmedBody : lines.joined(separator: "\n") + "\n\n" + trimmedBody
    }
}

// MARK: - lossy decoding of the native store

/// `Train`'s synthesized decoder reads `trip_notes` through this overload, so
/// a note that cannot be read at all (not an object, no id) is skipped and a
/// repeated id keeps the first — instead of one bad element failing the trip
/// and with it the whole store load. Mirrors `TrainValidation.tripNotes(_:)`.
extension KeyedDecodingContainer {
    func decodeIfPresent(_ type: [TripNote].Type, forKey key: Key) throws -> [TripNote]? {
        guard contains(key), (try? decodeNil(forKey: key)) == false,
              var list = try? nestedUnkeyedContainer(forKey: key) else { return nil }
        var notes: [TripNote] = []
        var seen = Set<String>()
        while !list.isAtEnd {
            if let note = try? list.decode(TripNote.self) {
                if seen.insert(note.id).inserted { notes.append(note) }
            } else if (try? list.decode(SkippedElement.self)) == nil {
                break
            }
        }
        return notes.isEmpty ? nil : notes
    }
}

/// Consumes one element of any shape, so a failed note decode still advances.
private struct SkippedElement: Decodable {
    init(from decoder: Decoder) throws {}
}
