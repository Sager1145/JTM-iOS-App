import RailCore
import Testing

struct RideMarkerVisibilityTests {
    @Test("every service type uses the ordinary-train timing")
    func serviceTimingIsUniform() throws {
        let types = ["新幹線", "新干线", "KTX", "特急", "Limited Express", "快速", "普通"]
        let ordinaryStop = try #require(RideMarkerVisibility.minimumMapLibreZoom(
            role: "stop", trainType: "普通", country: "jp", densityMinZoom: 8))
        let ordinaryPass = try #require(RideMarkerVisibility.minimumMapLibreZoom(
            role: "pass", trainType: "普通", country: "jp", densityMinZoom: 8))

        for type in types {
            #expect(RideMarkerVisibility.minimumMapLibreZoom(
                role: "stop", trainType: type, country: "jp", densityMinZoom: 8)
                == ordinaryStop)
            #expect(RideMarkerVisibility.minimumMapLibreZoom(
                role: "pass", trainType: type, country: "jp", densityMinZoom: 8)
                == ordinaryPass)
        }
    }

    @Test("boundaries remain visible at every zoom")
    func boundaryVisibility() {
        #expect(RideMarkerVisibility.minimumMapLibreZoom(
            role: "terminal", trainType: "普通", country: "jp", densityMinZoom: 14) == nil)
        #expect(RideMarkerVisibility.minimumMapLibreZoom(
            role: "xday", trainType: "普通", country: "jp", densityMinZoom: 14) == nil)
    }

    @Test("density delays every service while pass-throughs remain later")
    func densityOrdering() throws {
        let local = try #require(RideMarkerVisibility.minimumMapLibreZoom(
            role: "stop", trainType: "普通", country: "jp", densityMinZoom: 8))
        let denseHighSpeed = try #require(RideMarkerVisibility.minimumMapLibreZoom(
            role: "stop", trainType: "新幹線", country: "jp", densityMinZoom: 12))
        let denseHighSpeedPass = try #require(RideMarkerVisibility.minimumMapLibreZoom(
            role: "pass", trainType: "新幹線", country: "jp", densityMinZoom: 12))

        #expect(local < denseHighSpeed)
        #expect(denseHighSpeed < denseHighSpeedPass)
    }
}
