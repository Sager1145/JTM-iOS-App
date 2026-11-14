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
        for count in [1] { #expect(answer(MapTapHits(tapCount: count)) == .clearWhenSettled) }
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

    @Test("Decision 3: a dot of an unselected trip selects that trip, only the selected trip's dots open the card")
    func dotsOfUnselectedTrip() {
        // The map layer reports an unselected trip's dot as that trip in reach, not as a selected dot.
        #expect(answer(MapTapHits(tripIDsInReach: ["other"])) == .pickTrip("other"))
        #expect(answer(MapTapHits(selectedTripStationDot: true, tripIDsInReach: ["sel"])) == .stationCard)
    }

    @Test("Decision 4: several trips show the chooser whether or not a trip card is open")
    func chooserWithCardOpen() {
        for open in [false, true] {
            #expect(answer(MapTapHits(tripIDsInReach: ["a", "b"], tripCardOpen: open)) == .tripChooser(["a", "b"]))
            #expect(answer(MapTapHits(tripIDsInReach: ["a", "a"], tripCardOpen: open)) == .pickTrip("a"))
        }
    }
}
