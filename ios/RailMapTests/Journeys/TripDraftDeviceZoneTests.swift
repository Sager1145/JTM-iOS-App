import Foundation
import RailCore
import Testing
@testable import RailMap

/// The phone's time zone never changes recorded data. The editor holds every
/// `Date` as an instant on the trip region's own calendar, so opening and
/// saving a record, editing a clock, starting a new trip and relabelling the
/// region give the same answer in every device zone, on every device DST night.
@MainActor
struct TripDraftDeviceZoneTests {
    private static let deviceZones = [
        "GMT", "Asia/Tokyo", "America/Los_Angeles", "Europe/London", "America/New_York",
        "Pacific/Kiritimati", "Asia/Kathmandu", "America/St_Johns",
    ]
    private static let regions: [Region] = [.jp, .tw, .hk, .mo, .kr]
    private static let days = ["2026-08-27", "2026-03-08", "2026-03-29", "2026-10-25", "2026-11-01"]

    private struct Variant {
        var name: String
        var departure: String?
        var arrival: String?
        var actualDeparture: String?
        var actualArrival: String?
    }

    private static let variants = [
        Variant(name: "overnight", departure: "23:40", arrival: "25:30"),
        Variant(name: "two-day", departure: "07:05", arrival: "31:27"),
        Variant(name: "actual", departure: "23:40", arrival: "25:30", actualDeparture: "23:48", actualArrival: "25:41"),
        Variant(name: "date-only"),
        Variant(name: "actual-only", actualDeparture: "10:07", actualArrival: "12:58"),
        Variant(name: "scheduled-only", departure: "10:30", arrival: "12:55"),
    ]

    private func record(_ region: Region, day: String, _ variant: Variant) -> Train {
        var train = StoreOperations.createBlankTrain(country: region.code)
        train.region = region.code
        train.date = day
        train.stops = [
            Stop(name: "A", departure: variant.departure,
                 actualDeparture: variant.actualDeparture, stopType: "origin"),
            Stop(name: "B", arrival: variant.arrival,
                 actualArrival: variant.actualArrival, stopType: "destination"),
        ]
        return train
    }

    /// What Save writes, through the header and actual-time paths `commit`
    /// uses (commit itself also runs the full ride validation, which these
    /// two-stop fixtures are not built to satisfy).
    private func saved(_ model: TripDraftModel, original: Train) -> Train {
        var result = model.currentResult(original: original)!
        model.applyActualTimes(to: &result)
        return result
    }

    private func same(_ a: Train, _ b: Train) -> Bool { json(a) == json(b) }

    /// Non-throwing so it can sit inside `#expect` in the zone closures; a
    /// record that fails to encode is reported and never compares equal.
    private func json(_ train: Train) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(train) else {
            Issue.record("could not encode \(train.id)")
            return UUID().uuidString
        }
        return String(decoding: data, as: UTF8.self)
    }

    @Test func anUntouchedRecordSavesByteIdenticalInEveryDeviceZone() {
        for zone in Self.deviceZones {
            withPhoneTimeZone(zone) {
                for region in Self.regions {
                    for day in Self.days {
                        for variant in Self.variants {
                            let original = record(region, day: day, variant)
                            let model = TripDraftModel(train: original, isNew: false)
                            let result = saved(model, original: original)
                            #expect(same(result, original),
                                    "\(zone) \(region.code) \(day) \(variant.name)")
                        }
                    }
                }
            }
        }
    }

    @Test func storedClocksReadBackUnchangedInEveryDeviceZone() {
        for zone in Self.deviceZones {
            withPhoneTimeZone(zone) {
                for region in Self.regions {
                    for day in Self.days {
                        for (departure, arrival) in [("23:40", "25:30"), ("07:05", "31:27")] {
                            let original = record(region, day: day, Variant(name: "", departure: departure, arrival: arrival))
                            let model = TripDraftModel(train: original, isNew: false)
                            #expect(model.dayString(model.departure) == day, "\(zone) \(region.code) \(day)")
                            #expect(model.clock(model.departure, extraDays: 0) == departure)
                            let extra = model.extraDays(from: model.departure, to: model.arrival)
                            #expect(model.clock(model.arrival, extraDays: extra) == arrival, "\(zone) \(region.code) \(day)")
                        }
                    }
                }
            }
        }
    }

    @Test func switchingTheDeviceZoneAfterOpeningChangesNothingSaved() {
        let zones = Self.deviceZones
        for (index, opened) in zones.enumerated() {
            let later = zones[(index + 3) % zones.count]
            for region in Self.regions {
                for day in Self.days {
                    let original = record(region, day: day, Self.variants[2])
                    let model = withPhoneTimeZone(opened) { TripDraftModel(train: original, isNew: false) }
                    withPhoneTimeZone(later) {
                        #expect(same(saved(model, original: original), original),
                                "\(opened) -> \(later) \(region.code) \(day)")
                    }
                }
            }
        }
    }

    @Test func aDepartureSetUnderAnotherZoneIsSavedAsTheWallClockSet() {
        let zones = Self.deviceZones
        for (index, opened) in zones.enumerated() {
            let later = zones[(index + 3) % zones.count]
            for region in Self.regions {
                for day in Self.days {
                    let original = record(region, day: day, Self.variants[0])
                    let model = withPhoneTimeZone(opened) { TripDraftModel(train: original, isNew: false) }
                    withPhoneTimeZone(later) {
                        let moved = model.timetableDate(day, time: "09:15")!
                        model.apply(TripDraftModel.Patch(departure: moved), source: .reader)
                        model.departureChanged(to: moved)
                        let expected = region.clock.serviceClock(of: moved, serviceDate: day)
                        #expect(expected == "09:15")
                        let result = saved(model, original: original)
                        #expect(result.date == day, "\(opened) -> \(later) \(region.code) \(day)")
                        #expect(result.stops[0].departure == expected, "\(opened) -> \(later) \(region.code) \(day)")
                    }
                }
            }
        }
    }

    @Test func aRecordWithoutAClockNeverGainsOne() {
        for zone in Self.deviceZones {
            withPhoneTimeZone(zone) {
                for region in Self.regions {
                    for day in Self.days {
                        let dateOnly = record(region, day: day, Self.variants[3])
                        let result = saved(TripDraftModel(train: dateOnly, isNew: false), original: dateOnly)
                        #expect(result.stops.allSatisfy {
                            $0.departure == nil && $0.arrival == nil
                                && $0.actualDeparture == nil && $0.actualArrival == nil
                        }, "date-only \(zone) \(region.code) \(day)")

                        let actualOnly = record(region, day: day, Self.variants[4])
                        let actual = saved(TripDraftModel(train: actualOnly, isNew: false), original: actualOnly)
                        #expect(actual.stops[0].departure == nil && actual.stops[1].arrival == nil,
                                "actual-only \(zone) \(region.code) \(day)")
                        #expect(same(actual, actualOnly))

                        let scheduledOnly = record(region, day: day, Self.variants[5])
                        let scheduled = saved(TripDraftModel(train: scheduledOnly, isNew: false), original: scheduledOnly)
                        #expect(scheduled.stops[0].actualDeparture == nil && scheduled.stops[1].actualArrival == nil,
                                "scheduled-only \(zone) \(region.code) \(day)")
                        #expect(same(scheduled, scheduledOnly))
                    }
                }
            }
        }
    }

    @Test func aNewTripStartsOnTheRegionsToday() {
        // 2026-08-27T15:30:00Z: 00:30 on the 28th in Japan and Korea, 23:30 on the 27th elsewhere.
        let now = Date(timeIntervalSince1970: 1_787_844_600)
        let expected: [Region: String] = [
            .jp: "2026-08-28", .kr: "2026-08-28", .tw: "2026-08-27", .hk: "2026-08-27", .mo: "2026-08-27",
        ]
        for zone in Self.deviceZones {
            withPhoneTimeZone(zone) {
                for region in Self.regions {
                    var train = StoreOperations.createBlankTrain(country: region.code)
                    train.region = region.code
                    let seed = EditorSeed(train: train, isNew: true, clock: region.clock, now: now)
                    #expect(RecordDate.text(from: seed.departure, in: region.clock) == expected[region], "\(zone) \(region.code)")
                    #expect(RecordDate.today(in: region.clock, at: now) == expected[region], "\(zone) \(region.code)")
                }
            }
        }
    }

    @Test func changingTheRegionKeepsTheWallClock() {
        let pairs: [(Region, Region)] = [(.jp, .tw), (.tw, .jp), (.kr, .hk), (.mo, .jp)]
        for zone in Self.deviceZones {
            withPhoneTimeZone(zone) {
                for (from, to) in pairs {
                    var train = StoreOperations.createBlankTrain(country: from.code)
                    train.region = from.code
                    let model = TripDraftModel(train: train, isNew: true)
                    let day = "2026-08-27"
                    model.apply(TripDraftModel.Patch(departure: model.timetableDate(day, time: "08:15")), source: .reader)
                    model.region = to
                    model.regionChanged(from: from)
                    #expect(to.clock.serviceClock(of: model.departure, serviceDate: day) == "08:15",
                            "\(zone) \(from.code) -> \(to.code)")
                    #expect(model.dayString(model.departure) == day)
                    #expect(model.previousDeparture == model.departure)
                }
            }
        }
    }

    /// Undoing a timetable on a region change restores header instants that
    /// were captured on the OLD region's clock; they must keep their wall
    /// clock too (regression: 10:30 JST came back as 09:30 in Taipei).
    @Test func aTimetableUndoneByARegionChangeKeepsTheReadersClock() {
        for zone in Self.deviceZones {
            withPhoneTimeZone(zone) {
                var train = StoreOperations.createBlankTrain(country: "jp")
                train.region = "jp"
                let model = TripDraftModel(train: train, isNew: true)
                let day = "2026-08-27"
                model.apply(TripDraftModel.Patch(departure: model.timetableDate(day, time: "10:30")), source: .reader)
                // What applying a timetable does to the header: snapshot, then fill.
                model.headerBeforeTimetable = TripDraftModel.HeaderSnapshot(
                    trainType: model.trainType, departure: model.departure, arrival: model.arrival,
                    previousDeparture: model.previousDeparture,
                    touched: model.touched, filledBy: model.filledBy)
                model.departure = model.timetableDate(day, time: "11:00")!
                model.region = .tw
                model.regionChanged(from: .jp)
                #expect(Region.tw.clock.serviceClock(of: model.departure, serviceDate: day) == "10:30", "\(zone)")
                #expect(model.dayString(model.departure) == day, "\(zone)")
            }
        }
    }

    @Test func movingTheDepartureMovesTheArrivalByExactlyThatManyMinutes() {
        for zone in Self.deviceZones {
            withPhoneTimeZone(zone) {
                for day in Self.days {
                    let original = record(.jp, day: day, Self.variants[0])
                    let model = TripDraftModel(train: original, isNew: false)
                    let before = model.arrival.timeIntervalSince(model.departure)
                    #expect(before == 110 * 60, "\(zone) \(day)")
                    let moved = model.region.clock.calendar.date(byAdding: .minute, value: 10, to: model.departure)!
                    model.apply(TripDraftModel.Patch(departure: moved), source: .reader)
                    model.departureChanged(to: moved)
                    #expect(model.arrival.timeIntervalSince(model.departure) == before, "\(zone) \(day)")
                    #expect(model.clock(model.departure, extraDays: 0) == "23:50")
                    let extra = model.extraDays(from: model.departure, to: model.arrival)
                    #expect(model.clock(model.arrival, extraDays: extra) == "25:40", "\(zone) \(day)")
                }
            }
        }
    }

    @Test func aTypedYearIsGregorianWhateverTheDeviceCalendar() {
        for zone in Self.deviceZones {
            withPhoneTimeZone(zone) {
                // A Japanese-calendar device reads year 2026 as Reiwa 8.
                guard case .valid(let year, _, _, let canonical) = EditorTime.parseDateInput("2026/08/28", defaultYear: 8) else {
                    Issue.record("typed date did not parse")
                    return
                }
                #expect(year == 2026 && canonical == "2026-08-28")
                for region in Self.regions {
                    let clock = region.clock
                    let date = RecordDate.date(from: canonical, in: clock)!
                    #expect(RecordDate.text(from: date, in: clock) == "2026-08-28", "\(zone) \(region.code)")
                    #expect(clock.calendar.component(.year, from: date) == 2026)
                }
            }
        }
    }
}
