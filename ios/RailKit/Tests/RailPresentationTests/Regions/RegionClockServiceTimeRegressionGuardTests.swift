import Foundation
import RailCore
import Testing

@testable import RailPresentation

/// Recorded train times must never depend on the phone's time zone or
/// calendar. These are permanent guards for `RegionClock`'s service-clock API.
@Suite("RegionClock service time regression guard")
struct RegionClockServiceTimeRegressionGuardTests {

    private static let deviceZones = [
        "UTC", "Asia/Tokyo", "America/Los_Angeles", "Europe/London",
        "America/New_York", "Pacific/Kiritimati", "Asia/Kathmandu", "America/St_Johns",
    ]

    /// Includes a midnight-adjacent day and the device DST transition nights.
    private static let dates = [
        "2026-01-01", "2026-08-27", "2026-03-08", "2026-03-29", "2026-11-01", "2026-10-25",
    ]

    private static let clocks = ["00:00", "05:07", "23:59", "24:00", "25:30", "31:27"]

    @MainActor
    private func underDeviceZone<T>(_ name: String, _ body: () -> T) -> T? {
        guard let zone = TimeZone(identifier: name) else {
            Issue.record("no time zone \(name)")
            return nil
        }
        let previous = NSTimeZone.default
        NSTimeZone.default = zone
        defer { NSTimeZone.default = previous }
        return body()
    }

    @Test("round trip and instant are identical under every device zone")
    @MainActor
    func deviceZoneMatrix() {
        for region in RegionClock.all {
            for date in Self.dates {
                for clock in Self.clocks {
                    let reference = underDeviceZone("UTC") {
                        region.instant(serviceDate: date, clock: clock)
                    } ?? nil
                    #expect(reference != nil, "\(region.timeZone.identifier) \(date) \(clock)")
                    for zone in Self.deviceZones {
                        underDeviceZone(zone) {
                            let instant = region.instant(serviceDate: date, clock: clock)
                            #expect(
                                instant == reference,
                                "\(region.timeZone.identifier) \(date) \(clock) under \(zone)")
                            if let instant {
                                #expect(
                                    region.serviceClock(of: instant, serviceDate: date) == clock,
                                    "\(region.timeZone.identifier) \(date) \(clock) under \(zone)")
                            }
                        }
                    }
                }
            }
        }
    }

    @Test("changing the device zone between write and read changes nothing")
    @MainActor
    func zoneChangeBetweenWriteAndRead() {
        for region in RegionClock.all {
            for date in Self.dates {
                for clock in Self.clocks {
                    for (a, b) in zip(Self.deviceZones, Self.deviceZones.dropFirst() + ["UTC"]) {
                        let instant = underDeviceZone(a) {
                            region.instant(serviceDate: date, clock: clock)
                        } ?? nil
                        guard let instant else {
                            Issue.record("nil instant \(date) \(clock)")
                            continue
                        }
                        let back = underDeviceZone(b) {
                            region.serviceClock(of: instant, serviceDate: date)
                        } ?? nil
                        #expect(back == clock, "\(date) \(clock) written \(a) read \(b)")
                    }
                }
            }
        }
    }

    @Test("an overnight arrival is 110 minutes after departure on device DST nights")
    @MainActor
    func arrivalStableAcrossDeviceDST() {
        let japan = RegionClock.japan
        for date in ["2026-03-08", "2026-03-29", "2026-11-01", "2026-10-25"] {
            for zone in Self.deviceZones {
                underDeviceZone(zone) {
                    guard let dep = japan.instant(serviceDate: date, clock: "23:40"),
                        let arr = japan.instant(serviceDate: date, clock: "25:30")
                    else {
                        Issue.record("nil instant \(date) under \(zone)")
                        return
                    }
                    #expect(arr.timeIntervalSince(dep) == 110 * 60, "\(date) under \(zone)")
                }
            }
        }
    }

    @Test("malformed clocks and dates are rejected")
    func parseRejects() {
        let japan = RegionClock.japan
        let bad: [String?] = ["", "7", "1:5", "48:00", "12:60", "ab:cd", "１２:００", nil]
        for clock in bad {
            #expect(RegionClock.parseServiceClock(clock) == nil, "\(clock ?? "nil")")
            #expect(japan.instant(serviceDate: "2026-08-27", clock: clock) == nil)
        }
        #expect(japan.instant(serviceDate: "not a date", clock: "12:00") == nil)
        #expect(japan.instant(serviceDate: nil, clock: "12:00") == nil)

        guard let noon = japan.instant(serviceDate: "2026-08-27", clock: "12:00") else {
            Issue.record("nil noon")
            return
        }
        #expect(japan.serviceClock(of: noon, serviceDate: "2026-08-28") == nil)
        #expect(japan.serviceClock(of: noon, serviceDate: "garbage") == nil)
        #expect(japan.serviceClock(of: noon, serviceDate: nil) == nil)
    }

    @Test("a short hour reads back in the canonical zero-padded spelling")
    func canonicalSpelling() {
        let japan = RegionClock.japan
        guard let instant = japan.instant(serviceDate: "2026-08-27", clock: "7:05") else {
            Issue.record("nil instant")
            return
        }
        #expect(japan.serviceClock(of: instant, serviceDate: "2026-08-27") == "07:05")
    }

    @Test("an instant two days after the service date has no service clock")
    func beyondNextDayIsNil() {
        let japan = RegionClock.japan
        guard let later = japan.instant(serviceDate: "2026-08-29", clock: "12:00") else {
            Issue.record("nil instant")
            return
        }
        #expect(japan.serviceClock(of: later, serviceDate: "2026-08-27") == nil)
        guard let nextDay = japan.instant(serviceDate: "2026-08-28", clock: "01:10") else {
            Issue.record("nil instant")
            return
        }
        #expect(japan.serviceClock(of: nextDay, serviceDate: "2026-08-27") == "25:10")
    }

    @Test("the region calendar is Gregorian, not era-based")
    func regionCalendarIsGregorianNotEraBased() {
        let japan = RegionClock.japan
        #expect(japan.calendar.identifier == .gregorian)
        guard let instant = japan.instant(serviceDate: "2026-08-27", clock: "12:00") else {
            Issue.record("nil instant")
            return
        }
        #expect(japan.posixFormatter("yyyy-MM-dd").string(from: instant) == "2026-08-27")
        #expect(japan.civilDate(of: instant) == "2026-08-27")
        #expect(japan.civilDate(of: instant).hasPrefix("2026"))

        // The hazard being guarded against: a device calendar of these kinds
        // numbers the same instant differently (Reiwa 8, Buddhist 2569).
        var imperial = Calendar(identifier: .japanese)
        imperial.timeZone = japan.timeZone
        #expect(imperial.component(.year, from: instant) == 8)
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = japan.timeZone
        #expect(buddhist.component(.year, from: instant) == 2569)
    }

    @Test("civilDate(of:) agrees with civilDate(at:)")
    @MainActor
    func civilDateAgrees() {
        let instants = [
            Date(timeIntervalSince1970: 0), Date(timeIntervalSince1970: 1_788_000_000),
            Date(timeIntervalSince1970: 1_793_000_000),
        ]
        for region in RegionClock.all {
            for zone in Self.deviceZones {
                underDeviceZone(zone) {
                    for instant in instants {
                        #expect(region.civilDate(of: instant) == region.civilDate(at: instant))
                    }
                }
            }
        }
    }
}
