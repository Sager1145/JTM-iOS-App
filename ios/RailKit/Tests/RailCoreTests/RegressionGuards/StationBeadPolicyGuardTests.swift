import RailCore
import Testing

/// The station election skips a station's siblings when it is not a tenant.
/// That is exact only while `isSuppressed` is false for every station without
/// a tenant group, whatever the siblings are.
struct StationBeadPolicyGuardTests {
    private func window(_ group: String, landlord: Bool, from: Double, to: Double) -> StationBeadPolicy.Window {
        .init(groupID: group, isLandlord: landlord, from: from, to: to)
    }

    private func station(
        _ line: String, drawn: Bool = true, measure: Double? = 10,
        windows: [StationBeadPolicy.Window] = []
    ) -> StationBeadPolicy.Station {
        .init(region: "jp", stationCode: "platform", lineID: line, isDrawn: drawn,
              anchorMeasure: measure, windows: windows)
    }

    @Test func aStationWithoutATenantGroupIsNeverSuppressedForAnySiblings() {
        let landlord = window("family", landlord: true, from: 0, to: 100)
        let tenant = window("family", landlord: false, from: 0, to: 100)
        let others: [[StationBeadPolicy.Station]] = [
            [],
            [station("owner", windows: [landlord])],
            [station("owner", windows: [landlord]), station("tenant", windows: [tenant])],
            [station("a", windows: [tenant]), station("b", windows: [tenant]), station("c")],
        ]
        // No anchor measure, no windows, only landlord windows, a tenant
        // window that does not contain the measure: none has a tenant group.
        let own: [StationBeadPolicy.Station] = [
            station("x", measure: nil),
            station("x"),
            station("x", windows: [landlord]),
            station("x", measure: 500, windows: [tenant]),
            station("x", drawn: false, windows: [window("family", landlord: false, from: 20, to: 30)]),
        ]
        for station in own {
            #expect(station.tenantGroup == nil)
            for siblings in others {
                #expect(!StationBeadPolicy.isSuppressed(station, siblings: siblings))
                #expect(!StationBeadPolicy.isSuppressed(station, siblings: siblings + [station]))
            }
        }
    }

    @Test func aTenantStationIsReportedAsOne() {
        let tenant = station("t", windows: [window("family", landlord: false, from: 0, to: 20)])
        #expect(tenant.tenantGroup == "family")
    }
}
