import Foundation
import Testing
@testable import RailCore

@Suite("RideKey")
struct RideKeyTests {
    static func base() -> Train {
        Train(
            id: "t1", date: "2025-03-01", number: "1001A", trainType: "express", company: "JR East",
            origin: "東京", destination: "新大阪",
            stops: [
                Stop(name: "東京", n02StationCode: "001", platformNumber: 14, stopType: "passenger_stop",
                     rideSegment: true, stationID: "st:jp:1"),
                Stop(name: "新大阪", n02StationCode: "002", stopType: "passenger_stop", rideSegment: true),
            ], region: "jp")
            .with {
                $0.routeSections = [RouteSection(
                    from: "東京", to: "新大阪", lineNames: ["東海道新幹線"], operatorNames: ["JR東海"],
                    lineIDs: ["l1"], sectionCodes: ["a", "b"], trackPreference: .up)]
                $0.routePolicy = RoutePolicy(mode: "strict", jrOnly: true, allowedInstitutionTypeCodes: ["2"])
            }
    }

    @Test("notes and other non-route fields do not change the key")
    func nonRouteFieldsAreIgnored() {
        let key = RideKey.make(for: Self.base())
        var t = Self.base()
        t.id = "other-id"
        t.notes = "window seat"
        t.visible = false
        t.vehicleType = "N700S"
        t.direction = "下り"
        t.numberEn = "Nozomi"
        t.stops[0].arrival = "10:00"
        t.stops[0].actualDeparture = "10:05"
        t.stops[0].routeEditing = Stop.RouteEditingMetadata()
        #expect(RideKey.make(for: t) == key)
    }

    @Test("every route field changes the key", arguments: Array(0..<30))
    func routeFieldChangesKey(_ index: Int) {
        let key = RideKey.make(for: Self.base())
        var t = Self.base()
        switch index {
        case 0: t.region = "tw"
        case 1: t.date = "2025-03-02"
        case 2: t.date = nil
        case 3: t.number = "1002A"
        case 4: t.trainType = "local"
        case 5: t.company = "JR West"
        case 6: t.operatorID = "op:jp:1"
        case 7: t.operatorIDs = ["op:jp:1", "op:jp:2"]
        case 8: t.origin = "品川"
        case 9: t.destination = "京都"
        case 10: t.routeConfirmation = .pending
        case 11: t.stops[0].name = "品川"
        case 12: t.stops[0].n02StationCode = "009"
        case 13: t.stops[0].stationID = "st:jp:2"
        case 14: t.stops[0].platformNumber = 15
        case 15: t.stops[0].platformNumber = nil
        case 16: t.stops[1].stopType = "pass"
        case 17: t.stops[1].rideSegment = false
        case 18: t.stops.append(Stop(name: "名古屋"))
        case 19: t.routeSections?[0].lineNames = ["東海道線"]
        case 20: t.routeSections?[0].lineIDs = ["l2"]
        case 21: t.routeSections?[0].sectionCodes = ["b", "a"]
        case 22: t.routeSections?[0].trackPreference = .down
        case 23: t.routeSections?[0].fromStationID = "st:jp:1"
        case 24: t.routeSections?[0].operatorNames = nil
        case 25: t.routeSections = nil
        case 26: t.routePolicy?.jrOnly = false
        case 27: t.routePolicy?.allowedInstitutionTypeCodes = ["3"]
        case 28: t.routePolicy = nil
        default: t.routeSections?.append(RouteSection(from: "新大阪", to: "博多"))
        }
        #expect(RideKey.make(for: t) != key, "route field case \(index) did not change the key")
    }

    @Test("framing keeps adjacent strings, nil and empty apart")
    func framing() {
        var a = Self.base(), b = Self.base()
        a.origin = "ab"; a.destination = "c"
        b.origin = "a"; b.destination = "bc"
        #expect(RideKey.make(for: a) != RideKey.make(for: b))
        var c = Self.base(), d = Self.base()
        c.company = nil
        d.company = ""
        #expect(RideKey.make(for: c) != RideKey.make(for: d))
    }

    @Test("the key is stable across calls and has fixed pinned value")
    func stable() {
        let k = RideKey.make(for: Self.base())
        #expect(k == RideKey.make(for: Self.base()))
        // Pinned: a change here means every user's ride cache silently misses.
        let hex = String(format: "%016llx%016llx", k.high, k.low)
        #expect(hex == Self.pinned, "actual \(hex)")
    }

    static let pinned = "df03d9abb3d474187702aed688216375"
}

extension Train {
    fileprivate func with(_ edit: (inout Train) -> Void) -> Train {
        var copy = self
        edit(&copy)
        return copy
    }
}
