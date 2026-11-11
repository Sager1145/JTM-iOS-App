import RailCore
import Testing
@testable import RailMap

/// A trip card never prints a placeholder clock: an actual
/// clock wins where recorded, else the scheduled one, and a side with neither is nil.
struct RideCardTimeTextTests {
    private func stops(
        dep: String? = nil, arr: String? = nil, actualDep: String? = nil, actualArr: String? = nil
    ) -> [Stop] {
        var first = Stop(name: "A", stopType: "origin", rideSegment: true)
        first.departure = dep
        first.actualDeparture = actualDep
        var last = Stop(name: "B", stopType: "destination", rideSegment: true)
        last.arrival = arr
        last.actualArrival = actualArr
        return [first, last]
    }

    @Test func scheduledOnly() {
        let s = stops(dep: "10:00", arr: "11:00")
        #expect(RideCardTimeText.departure(s) == "10:00")
        #expect(RideCardTimeText.arrival(s) == "11:00")
    }

    @Test func actualOnly() {
        let s = stops(actualDep: "10:05", actualArr: "11:07")
        #expect(RideCardTimeText.departure(s) == "10:05")
        #expect(RideCardTimeText.arrival(s) == "11:07")
    }

    @Test func mixedActualWinsOverScheduled() {
        let s = stops(dep: "10:00", actualDep: "10:05", actualArr: "11:07")
        #expect(RideCardTimeText.departure(s) == "10:05")
        #expect(RideCardTimeText.arrival(s) == "11:07")
    }

    @Test func dateOnlyHasNoTimes() {
        let s = stops()
        #expect(RideCardTimeText.departure(s) == nil)
        #expect(RideCardTimeText.arrival(s) == nil)
        #expect(RideCardTimeText.departure([]) == nil)
        #expect(RideCardTimeText.arrival([]) == nil)
    }

    @Test func oneSideOnlyAndEmptyStringsAreMissing() {
        let s = stops(dep: "", arr: "11:00", actualDep: "")
        #expect(RideCardTimeText.departure(s) == nil)
        #expect(RideCardTimeText.arrival(s) == "11:00")
    }

    private func midTrain(types: Bool, firstRidden: Int = 1) -> [Stop] {
        var stops = (0..<5).map { index -> Stop in
            var stop = Stop(name: "S\(index)")
            stop.departure = "0\(index):00"
            stop.arrival = "0\(index):00"
            stop.rideSegment = index >= firstRidden && index <= 3
            return stop
        }
        if types { stops[1].stopType = "origin"; stops[3].stopType = "destination" }
        return stops
    }

    @Test func midTrainBoardingShowsThatStopsActualAndScheduled() {
        var s = midTrain(types: true)
        s[1].actualDeparture = "01:07"
        s[3].actualArrival = "03:02"
        let dep = RideCardTimeText.departureDisplay(s)
        #expect(dep?.shown == "01:07" && dep?.scheduled == "01:00" && dep?.offsetMinutes == 7)
        let arr = RideCardTimeText.arrivalDisplay(s)
        #expect(arr?.shown == "03:02" && arr?.scheduled == "03:00")
        s[1].actualDeparture = nil
        #expect(RideCardTimeText.departure(s) == "01:00")
    }

    @Test func anImportWithoutTypesUsesTheFirstRiddenStop() {
        let s = midTrain(types: false, firstRidden: 2)
        #expect(RideCardTimeText.departure(s) == "02:00")
        #expect(RideCardTimeText.arrival(s) == "03:00")
    }
}
