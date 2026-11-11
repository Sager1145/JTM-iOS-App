import Foundation
import Testing

/// Source-structure guards for the journey editor and the timetable pages
/// (UI wave 1). They read app sources, so they live in RailKit: the hosted
/// app tests run in the simulator and cannot read the repository folder.
@Suite("RegressionGuardEditorStructure")
struct RegressionGuardEditorStructure {
    private static let ios = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // RegressionGuards
        .deletingLastPathComponent() // RailCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // RailKit
        .deletingLastPathComponent() // ios

    private static func source(_ relative: String) throws -> String {
        try String(contentsOf: ios.appendingPathComponent(relative), encoding: .utf8)
    }

    private static func editor(_ name: String) throws -> String {
        try source("RailMap/JourneyEditor/\(name)")
    }

    @Test func theEditorPushesItsSearchableListsAndKeepsOneSheetForFillDetails() throws {
        let editor = try Self.editor("JourneyEditorView.swift")
        #expect(!editor.contains(".sheet(item: $model.picking)"))
        #expect(!editor.contains(".sheet(isPresented: $model.showsVehiclePicker)"))
        let fill = try Self.editor("EditorFillDetailsSheet.swift")
        #expect(!fill.contains(".sheet(isPresented: $model.showsCompletion)"))
    }

    @Test func saveErrorsLiveInTheStatusRowNotAtTheBottomOfTheForm() throws {
        let editor = try Self.editor("JourneyEditorView.swift")
        #expect(editor.contains("EditorSaveStatusRow"))
        #expect(!editor.contains("ForEach(model.saveIssues)"))
    }

    @Test func theEditorHasNoHandBuiltCancelOrDoneToolbarItems() throws {
        for name in ["StationPickerView.swift", "EditorLineSearchView.swift", "JourneyEditorManualEntry.swift"] {
            let text = try Self.editor(name)
            #expect(!text.contains("ToolbarItem(placement: .confirmationAction)"), "\(name)")
            #expect(!text.contains("ToolbarItem(placement: .cancellationAction)"), "\(name)")
        }
    }

    @Test func theRecordIdentifierIsEditableOnlyWhenItIsInvalid() throws {
        let details = try Self.editor("JourneyEditorDetails.swift")
        #expect(details.contains("issues.all(for: .id).contains(where: { $0.severity == .error })"))
        #expect(details.contains("LabeledContent(localization.countryText(\"field.id\""))
    }

    @Test func theCompletionPageResetsWhenTheFillSheetGoesAway() throws {
        let fill = try Self.editor("EditorFillDetailsSheet.swift")
        #expect(fill.contains(".onDisappear { model.showsCompletion = false }"))
    }

    @Test func scrollAnchorsAreOnRowsNotSections() throws {
        for name in ["EditorServiceSection.swift", "EditorTimeSection.swift", "EditorRouteSection.swift",
                     "EditorStationsSection.swift", "JourneyEditorDetails.swift"] {
            let text = try Self.editor(name)
            for line in text.split(separator: "\n") where line.contains(".id(EditorAnchor.") {
                // Section-level ids sit at body indentation (8 spaces). The one
                // exception is the From/To VStack, a single Form row whose
                // modifiers are at that indentation.
                if name == "EditorStationsSection.swift", line.contains("EditorAnchor.origin") { continue }
                #expect(!line.hasPrefix("        .id("), "\(name): \(line)")
            }
        }
    }

    @Test func timetableViewsPresentNoSheets() throws {
        let folder = Self.ios.appendingPathComponent("RailMap/Timetable")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        try #require(!files.isEmpty)
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            #expect(!source.contains(".sheet("), "\(file.lastPathComponent) presents a sheet")
            #expect(!source.contains(".fullScreenCover("), "\(file.lastPathComponent) presents a cover")
        }
    }
}
