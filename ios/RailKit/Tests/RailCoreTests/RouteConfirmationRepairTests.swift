import Foundation
import Testing
import RailCore

struct RouteConfirmationRepairTests {
    private func ride(id: String, confirmation: RouteConfirmation?, codes: [String?]) -> Train {
        Train(
            id: id,
            number: id,
            origin: "A",
            destination: "B",
            stops: codes.enumerated().map { index, code in
                Stop(name: "S\(index)", n02StationCode: code)
            },
            routeConfirmation: confirmation)
    }

    @Test func pendingWithStationCodesClearsConfirmation() {
        let first = ride(id: "coded", confirmation: .pending, codes: ["004759", "008477"])
        let second = ride(id: "coded-three", confirmation: .pending, codes: ["1", "2", "3"])
        let result = RouteConfirmationRepair.clearInferredPending([first, second])

        #expect(result.changed == 2)
        var expectedFirst = first
        expectedFirst.routeConfirmation = nil
        var expectedSecond = second
        expectedSecond.routeConfirmation = nil
        #expect(result.trains == [expectedFirst, expectedSecond])
    }

    @Test func pendingMissingAStationCodeStaysPending() {
        let missing = ride(id: "missing", confirmation: .pending, codes: ["004759", nil])
        let blank = ride(id: "blank", confirmation: .pending, codes: ["004759", ""])
        let result = RouteConfirmationRepair.clearInferredPending([missing, blank])

        #expect(result.changed == 0)
        #expect(result.trains == [missing, blank])
    }

    @Test func confirmedRideIsUntouched() {
        let confirmed = ride(id: "confirmed", confirmation: .confirmed, codes: ["004759", "008477"])
        let unmarked = ride(id: "unmarked", confirmation: nil, codes: ["004759", "008477"])
        let result = RouteConfirmationRepair.clearInferredPending([confirmed, unmarked])

        #expect(result.changed == 0)
        #expect(result.trains == [confirmed, unmarked])
    }

    @Test func pendingWithFewerThanTwoStopsStaysPending() {
        let oneStop = ride(id: "one", confirmation: .pending, codes: ["004759"])
        let none = ride(id: "none", confirmation: .pending, codes: [])
        let result = RouteConfirmationRepair.clearInferredPending([oneStop, none])

        #expect(result.changed == 0)
        #expect(result.trains == [oneStop, none])
    }
}
