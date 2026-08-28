//
//  RideLedger.swift — whether a journey has been ridden, as a stated fact.
//

import Foundation
import RailCore

/// Has this journey actually been ridden?
///
/// ## Why this is not a question about the calendar
///
/// It could be. A record carries a date, the app knows what day it is in each
/// of the five regions, and comparing the two answers "has it happened" for
/// nothing. That answer was wrong in the way that matters: it is the app
/// deciding, from a clock, that the reader travelled — so a trip written down
/// and then cancelled, a booking moved, a ticket never used and a plan kept as
/// a note all walk into the passport by themselves on their own date, and the
/// total moves on a day nobody touched the app. A rail passport is a record of
/// what somebody did. Nothing may enter it that they did not say they did.
///
/// So this reads a stored fact and never a clock. The clock still decides what
/// is *upcoming* (§5.1) — that genuinely is a question about the calendar, and
/// it changes nothing about the record — but what is *counted* (§5.3) is only
/// ever what the record itself says.
///
/// ## The fact was already in the document
///
/// Every stop carries `ride_segment`, which is jsonspec's own per-call flag
/// for "this interval was ridden" — the editor has always toggled it, the
/// ported statistics have always honoured it (`Statistics.isRideSegment`), and
/// `TransferGuide.build(options:ridden:)` already writes a whole journey as a
/// plan by setting every one of them false. So confirming a ride needed no new
/// field, no schema version and no migration: a store written by an older
/// build has `ride_segment: true` throughout and is read here, correctly, as
/// a journey that was ridden.
///
/// What this type adds is the journey-level reading of those flags, in one
/// place, so that the passport, the coverage map, the journey log and the
/// editor cannot come to different conclusions about the same record.
public enum RideLedger {

    /// What a journey's stops say about it, as one word.
    public enum Confirmation: Sendable, Equatable {
        /// Every call is marked ridden — the whole journey was travelled, and
        /// what a store from an older build always says.
        case ridden
        /// Some of it was. The per-stop editor can leave a journey like this
        /// on purpose: boarding halfway, or getting off early.
        case partly
        /// No interval of it counts. Either the reader has not confirmed it
        /// yet, or they have said outright that it did not happen.
        case notRidden
    }

    /// Whether this journey contributes anything at all to the statistics.
    ///
    /// The test is over SEGMENTS rather than over stops, because a segment is
    /// what carries distance: `Statistics.isRideSegment` reads the calls at
    /// both of its ends, so two ridden stops with an unridden one between them
    /// bound no ridden interval and no kilometre. A journey like that would
    /// otherwise be counted in 旅程數 while adding nothing to the total beside
    /// it, which is the screen disagreeing with itself.
    public static func hasBeenRidden(_ train: Train) -> Bool {
        riddenSegmentCount(train.stops) > 0
    }

    /// The same question of a bare stop list, for callers that hold one.
    public static func hasBeenRidden(stops: [Stop]) -> Bool {
        riddenSegmentCount(stops) > 0
    }

    public static func confirmation(of train: Train) -> Confirmation {
        confirmation(of: train.stops)
    }

    public static func confirmation(of stops: [Stop]) -> Confirmation {
        // Order matters. "No ridden interval" is checked first so that a
        // journey whose scattered flags bound nothing reads as what it is —
        // uncounted — rather than as partly ridden.
        guard riddenSegmentCount(stops) > 0 else { return .notRidden }
        return stops.allSatisfy(\.rideSegment) ? .ridden : .partly
    }

    /// How many of the journey's intervals count as ridden.
    ///
    /// Public because the editor says so out loud: a reader who has switched
    /// individual calls off is told how much of the journey is still being
    /// counted, rather than being shown a toggle that reads "off" over a
    /// record that is contributing distance.
    public static func riddenSegmentCount(_ stops: [Stop]) -> Int {
        guard stops.count >= 2 else { return 0 }
        let mapped = stops.map {
            Statistics.Stop(
                arrival: $0.arrival, departure: $0.departure,
                stopType: $0.stopType, rideSegment: $0.rideSegment)
        }
        return (0..<(mapped.count - 1)).reduce(into: 0) { total, index in
            if Statistics.isRideSegment(mapped, segmentIndex: index) { total += 1 }
        }
    }

    /// The journey with every call marked ridden, or every call marked not.
    ///
    /// This is what the confirm button commits, and it is deliberately a whole
    /// journey rather than a per-call edit: the reader pressing 「確認已乘坐」
    /// is saying they made the journey, and leaving some interval of it
    /// untouched because it happened to be switched off would be answering a
    /// question they did not ask. The per-call editor is still there for the
    /// journey that was only partly ridden.
    ///
    /// Pass-through calls are set too. They carry the flag in the document
    /// like any other stop, and `Statistics.effectiveStopRide` lets a
    /// pass-through inherit its interval — leaving them behind would write a
    /// record whose flags disagree with the ride it describes.
    public static func setRidden(_ train: Train, _ ridden: Bool) -> Train {
        var updated = train
        for index in updated.stops.indices {
            updated.stops[index].rideSegment = ridden
        }
        return updated
    }
}
