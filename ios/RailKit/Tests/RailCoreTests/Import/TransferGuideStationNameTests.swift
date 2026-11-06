import Testing

@testable import RailCore

// =========================================================================
//  Three rules that decide whether a row IS a station, checked against the
//  names the five packages actually carry.
//
//  All three were wrong in the same direction, and that direction is the
//  dangerous one: a row the parser declines is not an error the reader sees.
//  It falls into `unclaimed`, the leg quietly ends at the stop before it, and
//  the journey is saved short. Nothing in `review(_:)` can catch that —
//  a leg that lost its last call is still monotone in time and still agrees
//  with its own station count.
//
//  The expected sets below are not opinions. They were taken out of
//  `app/public/rail/*-2025.json` (10,328 distinct station names across the
//  five packages), which is why they are written out in full: a future
//  package that adds a tenth 円 station should fail here and be added
//  deliberately, not silently rejected at run time.
// =========================================================================

@Suite("station names the parser used to throw away")
struct TransferGuideStationNameTests {

    /// The nine names containing 円.
    ///
    /// `looksLikeStationName` forbade 円 outright, to keep a fare from being
    /// read as a station. But a fare has digits in front of its 円, and
    /// `takeSuffixed(_, "円")` has already cut those out of the line before a
    /// name is considered — so the rule was rejecting 高円寺 to guard against
    /// something that could no longer arrive.
    @Test("a station whose name contains 円 is still a station")
    func yenNamesAreStations() {
        for name in [
            "高円寺", "新高円寺", "東高円寺", "円町", "円山公園",
            "円座", "円田", "円行寺口", "河野原円心",
        ] {
            #expect(
                TransferGuide.Text.looksLikeStationName(name),
                "\(name) is a station in the packages and was rejected")
        }
    }

    /// …and the thing that rule was actually for still works.
    @Test("a fare is still not a station")
    func faresAreNotStations() {
        for fare in ["1200円", "47,280円", "3170円", "24,640円"] {
            #expect(
                !TransferGuide.Text.looksLikeStationName(fare),
                "\(fare) was read as a station name")
        }
    }

    /// The four names beginning with 発.
    ///
    /// `gluedMarker` reads a leading 発 as a departure badge that Vision glued
    /// to the station beside it. Every station whose name genuinely starts
    /// with 発 therefore has to be listed, or its name loses a character —
    /// and a name no package carries resolves to no station code, so the stop
    /// is saved without one and that stretch never draws. 発寒南 was missing.
    @Test("a station whose name begins with 発 keeps its first character")
    func hatsuNamesSurvive() {
        for name in ["発寒", "発寒中央", "発寒南", "発坂"] {
            let read = TransferGuide.gluedMarker(name)
            #expect(read.marker == nil, "\(name) was read as a 発 badge")
            #expect(read.name == name, "\(name) was amputated to \(read.name)")
        }
    }

    /// The badge itself still has to be readable, or fixing the above would
    /// have cost the thing it exists for.
    @Test("a 発 genuinely glued to a station is still a badge")
    func aGluedDepartureBadgeStillReads() {
        let read = TransferGuide.gluedMarker("発札幌")
        #expect(read.marker == .departure)
        #expect(read.name == "札幌")
    }

    /// The longest name in the five packages is 25 characters. The ceiling
    /// was 24.
    @Test("the longest station name in the packages fits under the ceiling")
    func theLongestNameFits() {
        let longest = "トヨタモビリティ富山Gスクエア五福前（五福末広町）"
        #expect(longest.count == 25)
        #expect(TransferGuide.Text.looksLikeStationName(longest))
    }
}
