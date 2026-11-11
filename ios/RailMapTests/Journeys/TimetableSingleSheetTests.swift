import Foundation
import Testing

/// The timetable pages are pushed onto one navigation stack, never presented
/// as sheets over a sheet (HIG: one sheet at a time). The picker, the trip
/// detail and the train research all live under `Timetable/`.
struct TimetableSingleSheetTests {
    @Test func timetableViewsPresentNoSheets() throws {
        let folder = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "RailMap/Timetable")
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
