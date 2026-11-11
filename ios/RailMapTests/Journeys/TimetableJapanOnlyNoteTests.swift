import Testing
@testable import RailMap

/// Timetable autofill is Japan-only; every other region shows a quiet note
/// in the quick-fill section instead of silently offering nothing.
struct TimetableJapanOnlyNoteTests {
    @Test func noteShowsOutsideJapan() {
        for region in [Region.tw, .kr, .hk, .mo] {
            #expect(EditorQuickFillSection.showsJapanOnlyTimetableNote(region: region))
        }
    }

    @Test func noteIsHiddenForJapan() {
        #expect(!EditorQuickFillSection.showsJapanOnlyTimetableNote(region: .jp))
    }
}
