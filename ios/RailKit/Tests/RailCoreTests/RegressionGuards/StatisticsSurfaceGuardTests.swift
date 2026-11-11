import Foundation
import Testing

/// Regression guard for the Statistics UI decisions of 2026-11-11
/// (`docs/maintenance/2026-11-11-ui-decisions.md`).
///
/// - B4: Play lives in the header; no code under `Statistics/` starts playback.
/// - Fix-options finding 4: Export JSON is offered only by the Data Library.
/// - Fix-options finding 3: record dates in Statistics and the station card go
///   through `TripDateLabel`, never a Statistics-local formatter.
/// - Decision 4: mode switches are a segmented Picker and single-choice rows
///   end in a checkmark; the filled/empty circle pair is gone.
@Suite("RegressionGuardStatisticsSurface")
struct RegressionGuardStatisticsSurface {
    private static let ios = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // RegressionGuards
        .deletingLastPathComponent() // RailCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // RailKit
        .deletingLastPathComponent() // ios

    private static func source(_ relative: String) throws -> String {
        try String(contentsOf: ios.appendingPathComponent(relative), encoding: .utf8)
    }

    private static func statisticsFiles() throws -> [String] {
        let dir = ios.appendingPathComponent("RailMap/Statistics")
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        let files = names.filter { $0.hasSuffix(".swift") }.map { "RailMap/Statistics/\($0)" }
        #expect(!files.isEmpty, "found no Statistics sources; #filePath resolution is broken")
        return files
    }

    @Test("no Statistics code starts playback or offers export")
    func noPlaybackOrExport() throws {
        for file in try Self.statisticsFiles() {
            let text = try Self.source(file)
            for forbidden in ["playback.start(", "btn.exportJson", ".fileExporter("] {
                #expect(!text.contains(forbidden), "\(file) contains \(forbidden)")
            }
        }
    }

    @Test("record dates use TripDateLabel")
    func dateLabels() throws {
        var files = try Self.statisticsFiles()
        files.append("RailMap/Map/StationCardView.swift")
        for file in files {
            let text = try Self.source(file)
            for forbidden in ["StatisticsFormat.dayLabel(", "StatisticsFormat.spelledDate("] {
                #expect(!text.contains(forbidden), "\(file) uses \(forbidden); use TripDateLabel")
            }
        }
        let station = try Self.source("RailMap/Map/StationCardView.swift")
        #expect(station.contains("TripDateLabel.label("), "station validity dates must use TripDateLabel")
    }

    @Test("scope picker uses a segmented picker and checkmark rows")
    func scopePickerStyle() throws {
        let text = try Self.source("RailMap/Statistics/StatisticsScopePicker.swift")
        #expect(text.contains(".pickerStyle(.segmented)"))
        #expect(!text.contains("checkmark.circle.fill"))
        #expect(!text.contains("\"circle\""))
    }
}
