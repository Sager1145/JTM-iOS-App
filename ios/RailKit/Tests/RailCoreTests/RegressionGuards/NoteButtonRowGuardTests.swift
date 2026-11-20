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

    /// Four one-row candidates, each with the add-note circle; the third is the
    /// compact label row (40-pt layout, 44-pt hit area), the last an icon-only
    /// primary. Add note is never folded into the More menu.
    @Test func fourCandidatesAllKeepFiveControls() throws {
        let components = try SourceFiles.text("RailMap/Journeys/JourneyComponents.swift")
        let start = try #require(components.range(of: "ViewThatFits(in: .horizontal) {\n                journeyControlRow("))
        let rest = components[start.lowerBound...]
        let block = String(rest[..<rest.range(of: "\n            }\n")!.lowerBound])
        #expect(block.components(separatedBy: "journeyControlRow(").count - 1 == 4,
                "The one-row ViewThatFits needs exactly four candidates.")
        #expect(block.contains("compact: true)"))
        #expect(block.contains("compact: true, iconOnlyPrimary: true)"))
        let row = Self.body(of: "journeyControlRow", in: components)
        #expect(row.contains("if addNote != nil { journeyRowAddNoteButton(compact: compact) }"),
                "The add-note circle must be drawn unconditionally in every candidate.")
        #expect(row.contains("journeyRowIconPrimaryButton"))
        #expect(!components.contains("tripNotesAddMenuItem"))
        #expect(!components.contains("includesAddNote"))
        #expect(components.contains("WorkspaceMenuMetrics.touchSide - SheetIconButton<Image>.visualSide"),
                "The compact hit area must stay 44 pt.")
        #expect(components.contains("contentShape(Rectangle().inset(by: -outset))"))
    }

    @Test func journeyControlRowDrawsTheAddNoteButton() throws {
        let components = try SourceFiles.text("RailMap/Journeys/JourneyComponents.swift")
        let row = Self.body(of: "journeyControlRow", in: components)
        #expect(!row.isEmpty)
        #expect(row.contains("journeyRowAddNoteButton"))
        #expect(components.contains("func journeyRowAddNoteButton(compact: Bool)"))
        #expect(components.contains("\"tripNotesAdd\""))
        #expect(components.contains("var addNote: (() -> Void)?"))
    }

    /// The connector's bands come from the endpoint's own fonts, not from
    /// guessed line heights, so arrow / elapsed time stay on the station / time
    /// centre lines.
    @Test func routeTimingConnectorDerivesBandsFromEndpointFonts() throws {
        let text = try SourceFiles.text("RailMap/Journeys/JourneyComponents.swift")
        for gone in ["nameLineHeight", "timeLineHeight", "smallTimeLineHeight"] {
            #expect(!text.contains(gone), "\(gone) is a hard-coded band height and must stay gone.")
        }
        #expect(text.contains("private var nameFont: Font"))
        #expect(text.contains("private var timeFont: Font"))
        #expect(text.contains(".font(nameFont)"), "endpoint must set the station name in nameFont.")
        #expect(text.contains(".font(timeFont)"), "endpoint must set the time in timeFont.")
        #expect(text.contains("band(font: nameFont)"), "connector arrow band must use nameFont.")
        #expect(text.contains("elapsedLabel(font: timeFont)"), "connector time band must use timeFont.")
        #expect(text.contains("Text(\"0\").font(font).hidden()"))
    }
}
