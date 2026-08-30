import Foundation
import Testing

@testable import RailPresentation

/// Where a camera showing more than one network opens.
///
/// The boxes below are the app's own `Region.networkBounds` — the measured
/// extent of the seven shipped packages — so this checks the answer the map
/// actually opens on rather than an invented one.
struct LongitudeArcTests {

    private func edges(_ west: Double, _ east: Double) -> LongitudeArc.Edges {
        LongitudeArc.Edges(west: west, east: east)
    }

    /// `Region.networkBounds`, longitudes only, in `allCases` order.
    private var everyNetwork: [LongitudeArc.Edges] {
        [
            edges(127.652285, 145.598010),  // jp
            edges(120.211958, 121.957939),  // tw
            edges(113.935773, 114.274552),  // hk
            edges(113.529403, 113.575406),  // mo
            edges(126.386565, 129.430039),  // kr
            edges(-123.201627, -69.965602),  // us
            edges(-130.359435, -63.269876),  // ca
        ]
    }

    /// Five networks that do not wrap answer exactly what `min`/`max` did,
    /// which is what makes this safe to have replaced `min`/`max` with.
    @Test("a set of boxes that does not wrap is its own plain extent")
    func noWrap() {
        let asia = Array(everyNetwork.prefix(5))
        let band = LongitudeArc.smallest(asia)
        #expect(abs(band.span - (145.598010 - 113.529403)) < 1e-9)
        #expect(abs(band.center - (145.598010 + 113.529403) / 2) < 1e-9)
    }

    /// The case the whole file exists for. East Asia runs to 146°E and North
    /// America from 130°W, so `min`/`max` describes a band 276° wide centred
    /// over Africa — it contains both networks and shows the reader the
    /// Atlantic in the middle of a view of the Pacific rim.
    @Test("Asia and North America are framed across the Pacific, not across Africa")
    func wrapsTheShortWay() {
        let band = LongitudeArc.smallest(everyNetwork)
        // The naive answer, for contrast: 276° centred at 7.6°E.
        let naiveWest = -130.359435, naiveEast = 145.598010
        #expect(naiveEast - naiveWest > 275)
        #expect(band.span < naiveEast - naiveWest)
        // Centred in the Pacific and reported in the range MapKit takes.
        #expect(band.center < -140)
        #expect(band.center >= -180)
        #expect(band.span <= 360)
        // And it really does contain every box: measured east from the band's
        // own western edge, no box reaches past its width.
        let west = band.center - band.span / 2
        for box in everyNetwork {
            for edge in [box.west, box.east] {
                var reach = (edge - west).truncatingRemainder(dividingBy: 360)
                if reach < 0 { reach += 360 }
                #expect(reach <= band.span + 1e-9)
            }
        }
    }

    /// Two boxes either side of the antimeridian are 20° apart, not 340°.
    @Test("the short way round the antimeridian is the short way")
    func acrossTheAntimeridian() {
        let band = LongitudeArc.smallest([edges(170, 175), edges(-175, -170)])
        #expect(abs(band.span - 20) < 1e-9)
        #expect(abs(abs(band.center) - 180) < 1e-9)
    }

    /// A box that already straddles the antimeridian reaches to its own east
    /// edge the long way round rather than collapsing to a negative width.
    @Test("a box that already wraps keeps its own width")
    func boxThatAlreadyWraps() {
        let band = LongitudeArc.smallest([edges(170, -170)])
        #expect(abs(band.span - 20) < 1e-9)
    }

    /// One box is its own band, and no box at all is the whole circle: a
    /// camera has to be pointed somewhere.
    @Test("one box, and none at all")
    func degenerate() {
        let one = LongitudeArc.smallest([edges(-123.201627, -69.965602)])
        #expect(abs(one.span - (-69.965602 + 123.201627)) < 1e-9)
        #expect(abs(one.center - (-69.965602 - 123.201627) / 2) < 1e-9)

        let none = LongitudeArc.smallest([])
        #expect(none.span == 360)
        #expect(none.center == 0)
    }
}
