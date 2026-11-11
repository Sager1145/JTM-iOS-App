import Foundation
import Testing

/// Regression guard for the Data Library, Settings and Layers pass of the
/// 2026-11-11 UI audit (`docs/maintenance/2026-11-11-ui-placement-grouping-audit.md`:
/// A11, A17, B1, B3, B5; duplicate-functionality H4; part 1 L16).
///
/// Source scans over `ios/RailMap`, in the style of the other regression guards:
/// the app target has no fast test path for view code, and each rule here is a
/// statement about which file owns a function.
@Suite("RegressionGuardDataSettingsLayers")
struct DataSettingsLayersGuardTests {
    private static let ios: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // RegressionGuards
        .deletingLastPathComponent() // RailCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // RailKit
        .deletingLastPathComponent() // ios

    private static func source(_ path: String) throws -> String {
        try String(contentsOf: ios.appendingPathComponent(path), encoding: .utf8)
    }

    /// The first string literal after `marker`.
    private static func quoted(after marker: String, in text: String) -> String? {
        guard let start = text.range(of: marker) else { return nil }
        let rest = text[start.upperBound...]
        guard let open = rest.firstIndex(of: "\"") else { return nil }
        let body = rest[rest.index(after: open)...]
        guard let close = body.firstIndex(of: "\"") else { return nil }
        return String(body[..<close])
    }

    private static func count(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    // MARK: H4 and A11: the Data Library

    @Test("the Data Library has one save retry, no duplicate save/reload/delete buttons")
    func dataLibraryHasNoDuplicateActions() throws {
        let view = try Self.source("RailMap/Import/DataManagerView.swift")
        // "Save current rides" and "Save again" both queued the same write.
        #expect(Self.count("saveWorkingSet()", in: view) <= 1)
        // The reload retry, the backup restore and the unreadable-file delete
        // are the only readers.
        #expect(Self.count("itineraries.load(from:", in: view) <= 3)
        for retired in ["btn.saveAsMine", "btn.restoreMine", "btn.clearStorage", "deleteSaved("] {
            #expect(!view.contains(retired), "\(retired) is a retired duplicate of save, reload or delete")
        }
        // The only other delete is the one for a file that cannot be read.
        #expect(Self.count("deleteSavedStore()", in: view) == 1)
        #expect(view.contains("deleteUnreadableConfirm"))
        // One delete, one confirmation.
        #expect(Self.count("data.deleteAllTitle", in: view) >= 1)
        #expect(Self.count("isPresented(.deleteAll)", in: view) == 1)
    }

    @Test("the Data Library title is the menu item's name, not the old one")
    func dataLibraryTitleMatchesItsMenuItem() throws {
        let view = try Self.source("RailMap/Import/DataManagerView.swift")
        #expect(view.contains("\"nav.dataLibrary\""))
        #expect(!view.contains("\"nav.data\""))
    }

    @Test("no string says the screen falls back to a bundled sample")
    func noBundledSampleFallbackText() throws {
        let dir = Self.ios.appendingPathComponent("RailMap/Localization")
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".swift") }
        for file in files {
            let text = try String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8)
            #expect(!text.localizedCaseInsensitiveContains("falls back to the bundled sample"), "\(file)")
            #expect(!text.contains("換回內建示例"), "\(file)")
        }
    }

    // MARK: B1: import signpost

    @Test("the export section points to Add trip for import, in four languages")
    func exportSectionHasTheImportSignpost() throws {
        let view = try Self.source("RailMap/Import/DataManagerView.swift")
        #expect(view.contains("data.importSignpost"))
        let strings = try Self.source("RailMap/Localization/DataStrings.swift")
        let start = try #require(strings.range(of: "\"data.importSignpost\": ["))
        let block = String(strings[start.lowerBound...].prefix(600))
        for language in [".en:", ".ja:", ".zhHans:", ".zhHant:"] { #expect(block.contains(language)) }
        #expect(block.contains("To import a file, use Add trip."))
        // The sentence names the Add trip entry as that language spells it.
        let shell = try Self.source("RailMap/Localization/ShellStrings.swift")
        let addStart = try #require(shell.range(of: "\"ios.tab.addTrip\": ["))
        let addBlock = String(shell[addStart.lowerBound...].prefix(300))
        for language in [".ja:", ".zhHans:", ".zhHant:"] {
            let label = try #require(Self.quoted(after: language, in: addBlock))
            let line = try #require(Self.quoted(after: language, in: block))
            #expect(line.contains(label), "\(language) signpost must name “\(label)”")
        }
    }

    // MARK: B5: one Sample trips page

    @Test("samples are added, replaced and removed only on the Sample trips page")
    func samplesLiveOnOnePage() throws {
        let manager = try Self.source("RailMap/Import/DataManagerView.swift")
        let page = try Self.source("RailMap/Import/SampleTripsView.swift")
        #expect(manager.contains("SampleTripsView("))
        for owned in [".merge(", ".replaceAll(", "removeTrains(withIDs:"] {
            #expect(!manager.contains(owned), "\(owned) belongs to SampleTripsView")
            #expect(page.contains(owned))
        }
        // Adding and replacing ask first; replacing is a visible row, not a long-press.
        #expect(page.contains("sampleAddConfirm"))
        #expect(page.contains("sampleReplaceConfirm"))
        #expect(!page.contains(".contextMenu"))
        #expect(!manager.contains(".contextMenu"))
    }

    // MARK: A17: reset

    @Test("Reset to defaults is the last row of Settings and asks first")
    func resetIsLastAndConfirmed() throws {
        let settings = try Self.source("RailMap/Settings/SettingsView.swift")
        let body = try #require(settings.range(of: "Form {\n            generalSection"))
        let order = settings[body.lowerBound...].prefix(400)
        let about = try #require(order.range(of: "aboutSection"))
        let reset = try #require(order.range(of: "resetSection"))
        #expect(about.lowerBound < reset.lowerBound)
        #expect(settings.contains("confirmReset"))
        // `display.reset()` is only reached from the confirmation.
        #expect(Self.count("display.reset()", in: settings) == 1)
        #expect(settings.contains("settingsResetConfirm"))
    }

    // MARK: B3: map display options

    @Test("Network era, Only the selected date and Auto-focus are edited in the Layers sheet")
    func mapDisplayOptionsAreInLayers() throws {
        let layers = try Self.source("RailMap/Map/MapLayersView.swift")
        let settings = try Self.source("RailMap/Settings/SettingsView.swift")
        #expect(layers.contains("display.networkEra = $0"))
        #expect(layers.contains("isOn: $mapFollowsSelectedDate"))
        #expect(layers.contains("isOn: $autoFocusZoom"))
        #expect(layers.contains("ios.layers.datesGroup"))
        #expect(!settings.contains("networkEra"), "Settings keeps Opening view and Map style only")
        #expect(!settings.contains("ios.networkEra"))
    }

    // MARK: L16: every source link label has a key

    @Test("source link labels that are not proper names have catalog or table keys")
    func sourceLinkLabelsHaveKeys() throws {
        let info = try Self.source("RailMap/Map/MapInfoView.swift")
        let pattern = try NSRegularExpression(pattern: "labelKey:\\s*\"([A-Za-z0-9_.]+)\"")
        let keys = pattern.matches(in: info, range: NSRange(info.startIndex..., in: info)).compactMap {
            Range($0.range(at: 1), in: info).map { String(info[$0]) }
        }
        #expect(keys.count >= 7)
        for required in ["ios.info.hkJourneyPlanner", "ios.info.hkOpenData", "ios.info.moLrtLines"] {
            #expect(keys.contains(required))
        }
        let catalog = try Self.source("Resources/Localizable.xcstrings")
        let dir = Self.ios.appendingPathComponent("RailMap/Localization")
        let tables = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".swift") }
            .map { try String(contentsOf: dir.appendingPathComponent($0), encoding: .utf8) }
            .joined(separator: "\n")
        for key in keys {
            let inCatalog = catalog.contains("\"\(key)\" : {")
            if inCatalog { continue }
            let start = try #require(tables.range(of: "\"\(key)\": ["), "\(key) has no catalog or table entry")
            let block = String(tables[start.lowerBound...].prefix(500))
            for language in [".en:", ".ja:", ".zhHans:", ".zhHant:"] {
                #expect(block.contains(language), "\(key) lacks \(language)")
            }
        }
    }
}
