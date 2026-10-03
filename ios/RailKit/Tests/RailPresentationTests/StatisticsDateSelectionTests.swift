import Testing
@testable import RailPresentation

struct StatisticsDateSelectionTests {
    @Test func emptySelectionAndFirstAnchorToggle() {
        let occupied: Set<String> = ["2026-09-02", "2026-09-05"]
        var selection = StatisticsDateSelection()
        #expect(selection.isEmpty)
        #expect(selection.start == nil)
        #expect(selection.end == nil)
        #expect(!selection.contains("2026-09-02"))
        #expect(selection.canSelect("2026-09-02", availableDates: occupied))
        #expect(!selection.canSelect("2026-09-03", availableDates: occupied))

        selection.tap("2026-09-02", availableDates: occupied)
        #expect(selection.start == "2026-09-02")
        #expect(selection.end == "2026-09-02")
        #expect(selection.contains("2026-09-02"))
        #expect(!selection.contains("2026-09-05"))
        #expect(!selection.isRangeComplete)
        selection.tap("2026-09-02", availableDates: occupied)
        #expect(selection == StatisticsDateSelection())
    }

    @Test(arguments: [false, true])
    func secondOccupiedTapSelectsInclusiveRange(reversed: Bool) {
        let occupied: Set<String> = ["2026-09-02", "2026-09-05"]
        var selection = StatisticsDateSelection()
        selection.tap(reversed ? "2026-09-05" : "2026-09-02", availableDates: occupied)
        selection.tap(reversed ? "2026-09-02" : "2026-09-05", availableDates: occupied)
        #expect(selection.start == "2026-09-02")
        #expect(selection.end == "2026-09-05")
        #expect(selection.isRangeComplete)
        #expect(["2026-09-02", "2026-09-03", "2026-09-04", "2026-09-05"].allSatisfy {
            selection.contains($0)
        })
        #expect(!selection.contains("2026-09-01"))
        #expect(!selection.contains("2026-09-06"))
    }

    @Test func grayDaysCannotStartOrEndARange() {
        let occupied: Set<String> = ["2026-09-02", "2026-09-05"]
        var selection = StatisticsDateSelection()
        selection.tap("2026-09-03", availableDates: occupied)
        #expect(selection.isEmpty)
        selection.tap("2026-09-02", availableDates: occupied)
        let anchor = selection
        selection.tap("2026-09-03", availableDates: occupied)
        #expect(selection == anchor)
        selection.tap("2026-09-05", availableDates: occupied)
        let range = selection
        selection.tap("2026-09-06", availableDates: occupied)
        #expect(selection == range)
        #expect(!selection.canSelect("2026-09-06", availableDates: occupied))
    }

    @Test func interiorDaysCanBeExcludedAndReselected() {
        let occupied: Set<String> = ["2026-09-02", "2026-09-04", "2026-09-06"]
        var selection = StatisticsDateSelection()
        selection.tap("2026-09-02", availableDates: occupied)
        selection.tap("2026-09-06", availableDates: occupied)
        #expect(selection.canSelect("2026-09-03", availableDates: occupied))
        selection.tap("2026-09-03", availableDates: occupied)
        selection.tap("2026-09-04", availableDates: occupied)
        #expect(selection.excludedDates == ["2026-09-03", "2026-09-04"])
        #expect(!selection.contains("2026-09-03"))
        #expect(!selection.contains("2026-09-04"))
        #expect(selection.contains("2026-09-05"))
        #expect(selection.start == "2026-09-02")
        #expect(selection.end == "2026-09-06")
        #expect(selection.canSelect("2026-09-03", availableDates: occupied))
        selection.tap("2026-09-03", availableDates: occupied)
        selection.tap("2026-09-04", availableDates: occupied)
        #expect(selection.excludedDates.isEmpty)
        #expect(selection.contains("2026-09-03"))
        #expect(selection.contains("2026-09-04"))
    }

    @Test func endpointRemovalSkipsUnoccupiedAndExcludedDays() {
        let occupied: Set<String> = ["2026-09-02", "2026-09-04", "2026-09-07", "2026-09-10"]
        var selection = StatisticsDateSelection()
        selection.tap("2026-09-02", availableDates: occupied)
        selection.tap("2026-09-10", availableDates: occupied)
        selection.tap("2026-09-04", availableDates: occupied)
        selection.tap("2026-09-08", availableDates: occupied)
        selection.tap("2026-09-02", availableDates: occupied)
        #expect(selection.start == "2026-09-07")
        #expect(selection.end == "2026-09-10")
        #expect(!selection.contains("2026-09-03"))
        #expect(selection.excludedDates == ["2026-09-08"])
        selection.tap("2026-09-10", availableDates: occupied)
        #expect(selection.start == "2026-09-07")
        #expect(selection.end == "2026-09-07")
        #expect(selection.isRangeComplete)
        selection.tap("2026-09-07", availableDates: occupied)
        #expect(selection == StatisticsDateSelection())
    }

    @Test func lastOccupiedRemovalClearsEvenWhenGrayDaysRemain() {
        let occupied: Set<String> = ["2026-09-02", "2026-09-06"]
        var selection = StatisticsDateSelection()
        selection.tap("2026-09-02", availableDates: occupied)
        selection.tap("2026-09-06", availableDates: occupied)
        selection.tap("2026-09-02", availableDates: occupied)
        #expect(selection.start == "2026-09-06")
        #expect(selection.end == "2026-09-06")
        selection.tap("2026-09-06", availableDates: occupied)
        #expect(selection.isEmpty)
        #expect(selection.excludedDates.isEmpty)
    }

    @Test func occupiedDayOutsideRangeStartsNewAnchor() {
        let occupied: Set<String> = ["2026-09-02", "2026-09-05", "2026-09-10"]
        var selection = StatisticsDateSelection()
        selection.tap("2026-09-02", availableDates: occupied)
        selection.tap("2026-09-05", availableDates: occupied)
        selection.tap("2026-09-03", availableDates: occupied)
        selection.tap("2026-09-10", availableDates: occupied)
        #expect(selection.start == "2026-09-10")
        #expect(selection.end == "2026-09-10")
        #expect(!selection.isRangeComplete)
        #expect(selection.excludedDates.isEmpty)
        #expect(!selection.contains("2026-09-02"))
        selection.clear()
        #expect(selection == StatisticsDateSelection())
    }

    @Test func rangeIncludesMonthYearAndLeapDayTransitions() {
        let occupied: Set<String> = ["2023-12-30", "2024-03-01"]
        var selection = StatisticsDateSelection()
        selection.tap("2024-03-01", availableDates: occupied)
        selection.tap("2023-12-30", availableDates: occupied)
        #expect(selection.start == "2023-12-30")
        #expect(selection.end == "2024-03-01")
        for date in ["2023-12-31", "2024-01-01", "2024-01-31", "2024-02-01", "2024-02-29"] {
            #expect(selection.contains(date))
        }
        selection.tap("2024-02-29", availableDates: occupied)
        #expect(!selection.contains("2024-02-29"))
        #expect(selection.contains("2024-02-28"))
    }
}
