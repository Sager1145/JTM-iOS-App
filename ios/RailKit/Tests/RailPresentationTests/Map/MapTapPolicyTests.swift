import Testing
@testable import RailPresentation

struct MapTapPolicyTests {
    private func answer(_ hits: MapTapHits) -> MapTapAnswer { MapTapPolicy.answer(hits) }

    @Test("Reach constants are 18, 33 and 12 points")
    func reach() {
        #expect(MapTapPolicy.tripReach == 18)
        #expect(MapTapPolicy.stationReach == 33)
        #expect(MapTapPolicy.networkLineReach == 12)
    }

    @Test("Empty map clears only once the double-tap window has passed")
    func emptyClearsWhenSettled() {
        #expect(answer(MapTapHits()) == .clearWhenSettled)
        #expect(!MapTapAnswer.clearWhenSettled.answersImmediately)
    }

    @Test("Clear is produced only for an empty first tap")
    func clearOnlyWhenEmpty() {
        let nonEmpty: [MapTapHits] = [
            MapTapHits(annotationViewUnderFinger: true), MapTapHits(selectedTripStationDot: true),
            MapTapHits(tripIDsInReach: ["a"]), MapTapHits(stationAnnotationInReach: true),
            MapTapHits(networkLineIDsInReach: ["L"]), MapTapHits(tapCount: 2),
        ]
        for hits in nonEmpty { #expect(answer(hits) != .clearWhenSettled) }
        #expect(answer(MapTapHits(tapCount: 1)) == .clearWhenSettled)
        for count in [0, 2, 3] { #expect(answer(MapTapHits(tapCount: count)) != .clearWhenSettled) }
    }

    @Test("Every hit answers at once")
    func hitsAnswerImmediately() {
        let hits: [MapTapHits] = [
            MapTapHits(annotationViewUnderFinger: true), MapTapHits(selectedTripStationDot: true),
            MapTapHits(tripIDsInReach: ["a"]), MapTapHits(tripIDsInReach: ["a", "b"]),
            MapTapHits(stationAnnotationInReach: true), MapTapHits(networkLineIDsInReach: ["L"]),
            MapTapHits(networkLineIDsInReach: ["L", "M"]),
        ]
        for h in hits { #expect(answer(h).answersImmediately) }
    }

    @Test("The second tap of a double tap is never answered")
    func secondTapIgnored() {
        #expect(MapTapPolicy.receives(tapCount: 1))
        #expect(!MapTapPolicy.receives(tapCount: 2))
        #expect(!MapTapPolicy.receives(tapCount: 3))
        #expect(!MapTapPolicy.receives(tapCount: 0))
        #expect(!MapTapPolicy.receives(tapCount: -1))
        #expect(answer(MapTapHits(tapCount: 0)) == .ignore)
        #expect(answer(MapTapHits(tapCount: -1)) == .ignore)
        let everything = MapTapHits(
            annotationViewUnderFinger: true, selectedTripStationDot: true, tripIDsInReach: ["a"],
            stationAnnotationInReach: true, networkLineIDsInReach: ["L"], tapCount: 2)
        #expect(answer(everything) == .ignore)
        #expect(answer(MapTapHits(tapCount: 2)) == .ignore)
    }

    @Test("Priority: annotation view beats everything")
    func annotationFirst() {
        let hits = MapTapHits(
            annotationViewUnderFinger: true, selectedTripStationDot: true, tripIDsInReach: ["a", "b"],
            stationAnnotationInReach: true, networkLineIDsInReach: ["L"])
        #expect(answer(hits) == .annotation)
    }

    @Test("Priority: selected trip's station dot beats trips, stations and lines")
    func selectedDotSecond() {
        let hits = MapTapHits(
            selectedTripStationDot: true, tripIDsInReach: ["a", "b"], stationAnnotationInReach: true,
            networkLineIDsInReach: ["L"])
        #expect(answer(hits) == .stationCard)
    }

    @Test("Priority: trips beat a station annotation and network lines")
    func tripsThird() {
        let hits = MapTapHits(tripIDsInReach: ["a"], stationAnnotationInReach: true, networkLineIDsInReach: ["L"])
        #expect(answer(hits) == .pickTrip("a"))
    }

    @Test("Priority: a station annotation beats network lines")
    func stationFourth() {
        #expect(answer(MapTapHits(stationAnnotationInReach: true, networkLineIDsInReach: ["L"])) == .station)
    }

    @Test("Lines last: one opens the card, several show a list, duplicates collapse")
    func lines() {
        #expect(answer(MapTapHits(networkLineIDsInReach: ["L"])) == .lineCard("L"))
        #expect(answer(MapTapHits(networkLineIDsInReach: ["L", "L"])) == .lineCard("L"))
        #expect(answer(MapTapHits(networkLineIDsInReach: ["L", "M", "L"])) == .lineChooser(["L", "M"]))
    }

    @Test("Decision 3: an unselected trip's mounted dot selects that trip, never .annotation")
    func dotsOfUnselectedTrip() {
        // Trip A selected, finger on a dot of trip B: the host reports B in reach and no annotation view.
        #expect(answer(MapTapHits(tripIDsInReach: ["B"])) == .pickTrip("B"))
        // Only the selected trip's dot opens the station card.
        #expect(answer(MapTapHits(selectedTripStationDot: true, tripIDsInReach: ["A"])) == .stationCard)
    }

    @Test("Duplicate trips are dropped keeping first-seen order")
    func tripsOrderedDedupe() {
        #expect(answer(MapTapHits(tripIDsInReach: ["b", "a", "b"])) == .tripChooser(["b", "a"]))
    }

    @Test("Double tap: one trip selects and zooms, none or several only zoom")
    func doubleTap() {
        #expect(MapTapPolicy.doubleTapAnswer(MapTapHits(tripIDsInReach: ["a"], tapCount: 2)) == .selectTripAndZoom("a"))
        #expect(MapTapPolicy.doubleTapAnswer(MapTapHits(tripIDsInReach: ["a", "a"], tapCount: 2)) == .selectTripAndZoom("a"))
        #expect(MapTapPolicy.doubleTapAnswer(MapTapHits(tripIDsInReach: ["a", "b"], tapCount: 2)) == .zoom)
        #expect(MapTapPolicy.doubleTapAnswer(MapTapHits(networkLineIDsInReach: ["L"], tapCount: 2)) == .zoom)
        #expect(MapTapPolicy.doubleTapAnswer(MapTapHits(tapCount: 2)) == .zoom)
    }

    @Test("Decision 4: several trips show the chooser whether or not a trip card is open")
    func chooserWithCardOpen() {
        for open in [false, true] {
            #expect(answer(MapTapHits(tripIDsInReach: ["a", "b"], tripCardOpen: open)) == .tripChooser(["a", "b"]))
            #expect(answer(MapTapHits(tripIDsInReach: ["a", "a"], tripCardOpen: open)) == .pickTrip("a"))
        }
    }
}
