import Foundation
import Testing

@testable import RailCore

struct EditorTimeTests {
    @Test func emptyAndWhitespaceAreUnset() {
        #expect(EditorTime.parseTime(nil) == .unset)
        #expect(EditorTime.parseTime("") == .unset)
        #expect(EditorTime.parseTime("   ") == .unset)
        #expect(EditorTime.parseTime("\n\t") == .unset)
        #expect(EditorTime.parseDate(nil) == .unset)
        #expect(EditorTime.parseDate("") == .unset)
        #expect(EditorTime.parseDate(" \t") == .unset)
    }

    @Test func serviceHourTwentyFiveTenFoldsAndStaysCanonical() {
        let time = ServiceClockTime(dayOffset: 1, hour: 1, minute: 10)
        #expect(EditorTime.parseTime("25:10") == .valid(raw: "25:10", time: time))
        #expect(time.serviceMinutes == 1510)
        #expect(EditorTime.canonical(time) == "25:10")
        #expect(EditorTime.canonical(ServiceClockTime(dayOffset: 1, hour: 1, minute: 10)) == "25:10")
    }

    @Test func morningTimesDropALeadingHourZero() {
        let nineThirty = ServiceClockTime(dayOffset: 0, hour: 9, minute: 30)
        #expect(EditorTime.parseTime("9:30") == .valid(raw: "9:30", time: nineThirty))
        #expect(EditorTime.parseTime("09:30") == .valid(raw: "09:30", time: nineThirty))
        let picked = EditorTime.confirmPicker(dayOffset: 0, hour: 9, minute: 30)
        #expect(picked.raw == "9:30")
        #expect(picked.parsed == .valid(raw: "9:30", time: nineThirty))
        #expect(EditorTime.canonical(nineThirty) == "9:30")
    }

    @Test func compactDigitsAndFullwidthDigits() {
        #expect(
            EditorTime.parseTime("930")
                == .valid(raw: "930", time: ServiceClockTime(dayOffset: 0, hour: 9, minute: 30))
        )
        #expect(
            EditorTime.parseTime("９３１")
                == .valid(raw: "９３１", time: ServiceClockTime(dayOffset: 0, hour: 9, minute: 31))
        )
        #expect(
            EditorTime.parseTime("2510")
                == .valid(raw: "2510", time: ServiceClockTime(dayOffset: 1, hour: 1, minute: 10))
        )
    }

    @Test func rejectedTimesKeepTheOriginalText() {
        for raw in ["9:99", "9:60", "abc", "9:30pm", "9", "99", "100:00"] {
            #expect(EditorTime.parseTime(raw) == .invalid(raw: raw))
        }
        let typed = EditorTime.input("9:99", confirmed: true)
        #expect(typed.raw == "9:99")
        #expect(typed.parsed == .invalid(raw: "9:99"))
        #expect(typed.unlocksAI == false)
    }

    @Test func onlyAConfirmedValidTimeUnlocksAI() {
        #expect(EditorTime.input("25:10", confirmed: false).unlocksAI == false)
        #expect(EditorTime.input("25:10", confirmed: true).unlocksAI == true)
        #expect(EditorTime.confirmPicker(dayOffset: 0, hour: 9, minute: 30).unlocksAI == true)
        let overnight = EditorTime.confirmPicker(dayOffset: 1, hour: 1, minute: 10)
        #expect(overnight.raw == "25:10")
        #expect(overnight.unlocksAI == true)
    }

    @Test func addedDayOffsetStacksOnTheFoldedHour() {
        let twiceFolded = ServiceClockTime(dayOffset: 2, hour: 1, minute: 10)
        #expect(
            EditorTime.parseTime("25:10+1")
                == .valid(raw: "25:10+1", time: twiceFolded)
        )
        #expect(EditorTime.canonical(twiceFolded) == "49:10")
        #expect(EditorTime.parseTime(EditorTime.canonical(twiceFolded))
            == .valid(raw: "49:10", time: twiceFolded))
        #expect(
            EditorTime.parseTime("9:30 + 1")
                == .valid(raw: "9:30 + 1", time: ServiceClockTime(dayOffset: 1, hour: 9, minute: 30))
        )
    }

    @Test func largeOffsetsCanonicalizeToRuntimeCompatibleSuffixes() {
        let fourDays = ServiceClockTime(dayOffset: 4, hour: 9, minute: 30)
        let canonical = EditorTime.canonical(fourDays)

        #expect(canonical == "9:30+4")
        #expect(EditorTime.parseTime(canonical) == .valid(raw: canonical, time: fourDays))
        #expect(Dates.parseTimeToMinutes(canonical) == Double(fourDays.serviceMinutes))
    }

    @Test func multiDigitOffsetsMatchTheRuntimeLimit() {
        let tenDays = ServiceClockTime(dayOffset: 10, hour: 9, minute: 30)
        #expect(EditorTime.parseTime("9:30+10") == .valid(raw: "9:30+10", time: tenDays))
        #expect(EditorTime.canonical(tenDays) == "9:30+10")
        #expect(Dates.parseTimeToMinutes("9:30+10") == Double(tenDays.serviceMinutes))

        let maximum = EditorTime.parseTime("99:00+\(Dates.maxDayOffset)")
        guard case .valid(_, let maximumTime) = maximum else {
            Issue.record("The runtime's maximum day offset should be accepted")
            return
        }
        let maximumCanonical = EditorTime.canonical(maximumTime)
        #expect(maximumCanonical == "99:00+\(Dates.maxDayOffset)")
        #expect(EditorTime.parseTime(maximumCanonical) == maximum)
        #expect(EditorTime.parseTime("9:30+\(Dates.maxDayOffset + 1)")
            == .invalid(raw: "9:30+\(Dates.maxDayOffset + 1)"))
    }

    @Test func calendarDatesRejectDaysThatDoNotExist() {
        #expect(EditorTime.parseDate("2026-02-29") == .invalid(raw: "2026-02-29"))
        #expect(EditorTime.parseDate("2026-06-31") == .invalid(raw: "2026-06-31"))
        #expect(EditorTime.parseDate("2026-02-30") == .invalid(raw: "2026-02-30"))
        #expect(
            EditorTime.parseDate("2024-02-29")
                == .valid(year: 2024, month: 2, day: 29, canonical: "2024-02-29")
        )
        #expect(
            EditorTime.parseDate("2026/03/01")
                == .valid(year: 2026, month: 3, day: 1, canonical: "2026-03-01")
        )
    }

    @Test func stationAndConfirmedTimeOnTheSameStopAllows() {
        let denial = EditorAIEligibility.denial(
            stops: [stop(resolved: true, departure: EditorTime.input("25:10", confirmed: true))],
            providerAvailable: true,
            requestInFlight: false
        )
        #expect(denial == nil)
    }

    @Test func denialPriority() {
        #expect(
            EditorAIEligibility.denial(
                stops: [stop(resolved: true)],
                providerAvailable: true,
                requestInFlight: false
            ) == .noExplicitTime
        )
        #expect(
            EditorAIEligibility.denial(
                stops: [stop(resolved: false, departure: EditorTime.input("9:30", confirmed: true))],
                providerAvailable: true,
                requestInFlight: false
            ) == .noResolvedStation
        )
        #expect(
            EditorAIEligibility.denial(
                stops: [
                    stop(resolved: true),
                    stop(resolved: false, departure: EditorTime.input("9:30", confirmed: true)),
                ],
                providerAvailable: true,
                requestInFlight: false
            ) == .timeNotOnThatStation
        )
        #expect(
            EditorAIEligibility.denial(
                stops: [stop(resolved: true, departure: EditorTime.input("25:10", confirmed: false))],
                providerAvailable: true,
                requestInFlight: false
            ) == .noExplicitTime
        )
        #expect(
            EditorAIEligibility.denial(
                stops: [stop(resolved: true, departure: EditorTime.input("9:99", confirmed: true))],
                providerAvailable: true,
                requestInFlight: false
            ) == .invalidTime
        )
        let anchor = stop(resolved: true, departure: EditorTime.confirmPicker(dayOffset: 0, hour: 9, minute: 30))
        #expect(
            EditorAIEligibility.denial(stops: [anchor], providerAvailable: true, requestInFlight: true)
                == .requestInFlight
        )
        #expect(
            EditorAIEligibility.denial(stops: [anchor], providerAvailable: false, requestInFlight: false)
                == .providerUnavailable
        )
        #expect(
            EditorAIEligibility.denial(stops: [anchor], providerAvailable: false, requestInFlight: true)
                == .requestInFlight
        )
    }

    private func stop(
        resolved: Bool,
        arrival: EditorTimeInput? = nil,
        departure: EditorTimeInput? = nil
    ) -> EditorAIStop {
        EditorAIStop(
            occurrenceID: UUID(),
            stationResolved: resolved,
            arrival: arrival ?? EditorTime.input("", confirmed: false),
            departure: departure ?? EditorTime.input("", confirmed: false)
        )
    }
}
