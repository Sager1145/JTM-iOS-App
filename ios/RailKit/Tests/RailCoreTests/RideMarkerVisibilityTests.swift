import RailCore
import Testing

struct RideMarkerVisibilityTests {
    @Test("selected pass-through dots and names wait for the density floor", arguments: [8, 10, 14])
    func selectedPassVisibility(density: Int) throws {
        let floor = try #require(RideMarkerVisibility.minimumMapLibreZoom(
            role: "pass", trainType: "特急", country: "jp", densityMinZoom: density))
        #expect(!RideMarkerVisibility.isVisible(
            role: "pass", isSelected: true, mapLibreZoom: floor - 0.01, minimumMapLibreZoom: floor))
        #expect(RideMarkerVisibility.isVisible(
            role: "pass", isSelected: true, mapLibreZoom: floor, minimumMapLibreZoom: floor))
        #expect(RideMarkerVisibility.isVisible(
            role: "pass", isSelected: true, mapLibreZoom: floor + 1, minimumMapLibreZoom: floor))
    }

    @Test("selected calls remain visible while ordinary calls keep their zoom floor")
    func selectedCallVisibility() {
        for role in ["stop", "stop-center", "terminal", "xday"] {
            let floor = RideMarkerVisibility.minimumMapLibreZoom(
                role: role, trainType: "普通", country: "jp", densityMinZoom: 12)
            #expect(RideMarkerVisibility.isVisible(
                role: role, isSelected: true, mapLibreZoom: 3, minimumMapLibreZoom: floor))
            #expect(RideMarkerVisibility.isVisible(
                role: role, isSelected: false, mapLibreZoom: 3, minimumMapLibreZoom: floor)
                == (floor == nil))
        }
    }

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
