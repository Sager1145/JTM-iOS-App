import Foundation
import RailTestSupport
import Testing

/// The selected-trip card keeps "Add note" on the same line as Focus, Play, Edit
/// and More: `RideCard` hands it to `QuietActionGroup` as `addNote:` and the
/// group draws it as the fifth circle in `journeyControlRow`. A standalone
/// "tripNotesAdd" button under the row in `RideCard` must not come back.
@Suite("RegressionGuardNoteButtonRow")
struct RegressionGuardNoteButtonRow {

    private static func body(of function: String, in text: String) -> String {
        guard let start = text.range(of: "private func \(function)(") else { return "" }
        let rest = text[start.lowerBound...]
        let end = rest.range(of: "\n    private func ", range: rest.index(after: rest.startIndex)..<rest.endIndex)
        return String(end.map { rest[..<$0.lowerBound] } ?? rest)
    }

    @Test func rideCardPassesAddNoteToTheGroupAndDrawsNoStandaloneButton() throws {
        let card = try SourceFiles.text("RailMap/Journeys/RideCard.swift")
        #expect(card.contains("addNote:"), "RideCard must pass addNote: to QuietActionGroup.")
        #expect(!card.contains("\"tripNotesAdd\""),
                "RideCard must not draw its own tripNotesAdd button under the control row.")
    }

    @Test func journeyControlRowDrawsTheAddNoteButton() throws {
        let components = try SourceFiles.text("RailMap/Journeys/JourneyComponents.swift")
        let row = Self.body(of: "journeyControlRow", in: components)
        #expect(!row.isEmpty)
        #expect(row.contains("journeyRowAddNoteButton"))
        #expect(components.contains("journeyRowAddNoteButton: some View"))
        #expect(components.contains("\"tripNotesAdd\""))
        #expect(components.contains("var addNote: (() -> Void)?"))
    }
}
