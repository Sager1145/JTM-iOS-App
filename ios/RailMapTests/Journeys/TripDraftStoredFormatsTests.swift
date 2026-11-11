import Foundation
import RailCore
import Testing
@testable import RailMap

/// Every spelling a stop time can be stored in opens as a known clock and is
/// never rewritten unless the reader edits that field. The spellings are the
/// ones the stop editor, legacy records and the timetable database produce.
@MainActor
struct TripDraftStoredFormatsTests {
    private static let deviceZones = ["GMT", "Asia/Tokyo", "America/Los_Angeles"]
    private static let regions: [Region] = [.jp, .tw]
    private static let day = "2026-08-27"
    private static let nextDay = "2026-08-28"

    private struct Format {
        var name: String
        var departure: String
        var arrival: String
    }

    private static let formats = [
        Format(name: "padded", departure: "10:30", arrival: "12:55"),
        Format(name: "unpadded", departure: "7:05", arrival: "9:30"),
        Format(name: "seconds", departure: "10:30:00", arrival: "12:55:00"),
        Format(name: "seconds-nonzero", departure: "10:30:15", arrival: "12:55:40"),
        Format(name: "extended-hours", departure: "23:40", arrival: "25:30"),
        Format(name: "stop-editor-two-days", departure: "49:10", arrival: "50:20"),
        Format(name: "legacy-suffix", departure: "10:00+1", arrival: "11:15+1"),
        Format(name: "short-suffix", departure: "1:05+1", arrival: "2:10+1"),
    ]

    private func record(_ region: Region, _ departure: String?, _ arrival: String?) -> Train {
        var train = StoreOperations.createBlankTrain(country: region.code)
        train.region = region.code
        train.date = Self.day
        train.stops = [
            Stop(name: "A", departure: departure, stopType: "origin"),
            Stop(name: "B", arrival: arrival, stopType: "destination"),
        ]
        return train
    }

    /// What Save writes, through the header and actual-time paths `commit` uses.
    private func saved(_ model: TripDraftModel, original: Train) -> Train {
        var result = model.currentResult(original: original)!
        model.applyActualTimes(to: &result)
        return result
    }

    /// Non-throwing so it can sit inside `#expect` in the zone closures.
    private func json(_ train: Train) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(train) else {
            Issue.record("could not encode \(train.id)")
            return UUID().uuidString
        }
        return String(decoding: data, as: UTF8.self)
    }

    @Test func everyStoredFormatOpensKnown() {
        for zone in Self.deviceZones {
            withPhoneTimeZone(zone) {
                for region in Self.regions {
                    for format in Self.formats {
                        let original = record(region, format.departure, format.arrival)
                        let seed = EditorSeed(train: original, isNew: false, clock: region.clock)
                        #expect(seed.departureKnown, "\(zone) \(region.code) \(format.name) departure")
                        #expect(seed.arrivalKnown, "\(zone) \(region.code) \(format.name) arrival")
                    }
                }
            }
        }
    }

    @Test func everyStoredFormatSavesUntouchedByteIdentical() {
        for zone in Self.deviceZones {
            withPhoneTimeZone(zone) {
                for region in Self.regions {
                    for format in Self.formats {
                        let original = record(region, format.departure, format.arrival)
                        let model = TripDraftModel(train: original, isNew: false)
                        let result = saved(model, original: original)
                        #expect(json(result) == json(original),
                                "\(zone) \(region.code) \(format.name)")
                    }
                }
            }
        }
    }

    @Test func editingOnlyTheDateKeepsTheTimes() {
        for zone in Self.deviceZones {
            withPhoneTimeZone(zone) {
                for region in Self.regions {
                    for format in Self.formats {
                        let original = record(region, format.departure, format.arrival)
                        let model = TripDraftModel(train: original, isNew: false)
                        let calendar = region.clock.calendar
                        let moved = calendar.date(byAdding: .day, value: 1, to: model.departure)!
                        model.apply(TripDraftModel.Patch(departure: moved), source: .reader)
                        model.departureChanged(to: moved)
                        let result = saved(model, original: original)
                        let label = Comment(rawValue: "\(zone) \(region.code) \(format.name)")
                        #expect(result.date == Self.nextDay, label)
                        // The departure is rewritten in the canonical spelling
                        // (seconds dropped), at the same service minute.
                        #expect(
                            Dates.parseTimeToMinutes(result.stops[0].departure)
                                == Dates.parseTimeToMinutes(format.departure), label)
                        // The arrival was not touched: its string is kept as stored.
                        #expect(result.stops[1].arrival == format.arrival, label)
                    }
                }
            }
        }
    }

    @Test func midnightOnAnUnreadableRecordApplies() {
        for zone in Self.deviceZones {
            withPhoneTimeZone(zone) {
                for region in Self.regions {
                    let original = record(region, "soon", "later")
                    let model = TripDraftModel(train: original, isNew: false)
                    #expect(!model.seed.departureKnown && !model.seed.arrivalKnown, "\(zone) \(region.code)")
                    // An unreadable record's untouched save keeps its text.
                    #expect(json(saved(model, original: original)) == json(original), "\(zone) \(region.code)")

                    let midnight = model.timetableDate(Self.day, time: "00:00")!
                    model.apply(TripDraftModel.Patch(departure: midnight, arrival: midnight), source: .reader)
                    model.departureChanged(to: midnight)
                    let result = saved(model, original: original)
                    // Known issue until TripDraftModel records a reader-chosen clock
                    // apart from its seed (fix owned by the add-trip work). When it
                    // lands this reports "known issue was not recorded": delete the
                    // wrapper so the expectations guard the fix.
                    withKnownIssue("a reader-set 00:00 equals the unreadable record's placeholder") {
                        #expect(result.stops[0].departure == "00:00", "\(zone) \(region.code) departure")
                        #expect(result.stops[1].arrival == "00:00", "\(zone) \(region.code) arrival")
                    }
                }
            }
        }
    }
}
