import Foundation

public struct DraftStopPin: Hashable, Sendable, Identifiable {
    public var occurrenceID: UUID
    public var name: String
    public var stopType: String
    /// Already-formatted clock text, or empty when unknown.
    public var timeText: String
    public var dayOffset: Int
    public var latitude: Double?
    public var longitude: Double?
    public var id: UUID { occurrenceID }

    public init(
        occurrenceID: UUID,
        name: String,
        stopType: String,
        timeText: String,
        dayOffset: Int,
        latitude: Double?,
        longitude: Double?
    ) {
        self.occurrenceID = occurrenceID
        self.name = name
        self.stopType = stopType
        self.timeText = timeText
        self.dayOffset = dayOffset
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct DraftMapSnapshot: Hashable, Sendable {
    public var revision: Int
    public var pins: [DraftStopPin]

    public init(revision: Int, pins: [DraftStopPin]) {
        self.revision = revision
        self.pins = pins
    }
}

public enum DraftMapPins {
    /// One pin per occurrence. Never collapse two visits that share a station code.
    /// Missing coordinate stays on the pin with nil lat/lon (caller must not draw those).
    /// timeText empty means the bubble should say the time is unfilled; this function does not invent "00:00".
    /// Order of pins is the stop order given.
    public static func snapshot(revision: Int, pins: [DraftStopPin]) -> DraftMapSnapshot {
        DraftMapSnapshot(revision: revision, pins: pins)
    }

    /// Returns what changed, keyed by occurrenceID.
    public enum Change: Hashable, Sendable {
        case insert(DraftStopPin)
        case update(DraftStopPin)
        case remove(UUID)
    }

    /// Removes follow old order, then updates in new order, then inserts in new order.
    /// Identity is occurrenceID only — name and coordinate never match pins.
    public static func diff(from old: DraftMapSnapshot, to new: DraftMapSnapshot) -> [Change] {
        let oldByID = index(old.pins)
        let newByID = index(new.pins)
        var changes: [Change] = []
        changes.reserveCapacity(old.pins.count + new.pins.count)

        for pin in old.pins where newByID[pin.occurrenceID] == nil {
            changes.append(.remove(pin.occurrenceID))
        }
        for pin in new.pins {
            if let previous = oldByID[pin.occurrenceID], previous != pin {
                changes.append(.update(pin))
            }
        }
        for pin in new.pins where oldByID[pin.occurrenceID] == nil {
            changes.append(.insert(pin))
        }
        return changes
    }

    /// Last pin wins if a caller repeats an occurrenceID. Lookup must not trap.
    private static func index(_ pins: [DraftStopPin]) -> [UUID: DraftStopPin] {
        var map: [UUID: DraftStopPin] = [:]
        map.reserveCapacity(pins.count)
        for pin in pins {
            map[pin.occurrenceID] = pin
        }
        return map
    }
}
