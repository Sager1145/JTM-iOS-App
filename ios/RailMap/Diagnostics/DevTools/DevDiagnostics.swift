#if DEBUG
import Foundation
import OSLog
import RailPresentation
import UIKit

/// The app's own log lines (OSLogStore, this process, subsystem
/// `com.jtm.railmap`) and the diagnostics bundle the panel and
/// `app-control.py devtools export` write to the container.
enum DevDiagnostics {
    struct LogLine: Identifiable, Equatable {
        var id: Int
        var date: Date
        var level: String
        var category: String
        var message: String
    }

    /// Newest last. Reads the store off the main thread.
    static func logs(limit: Int = 400, sinceSeconds: TimeInterval = 3600) async -> [LogLine] {
        await Task.detached(priority: .utility) { () -> [LogLine] in
            guard let store = try? OSLogStore(scope: .currentProcessIdentifier) else { return [] }
            let position = store.position(date: Date().addingTimeInterval(-sinceSeconds))
            let predicate = NSPredicate(format: "subsystem == %@", RailSignpost.subsystem)
            guard let entries = try? store.getEntries(at: position, matching: predicate) else { return [] }
            var lines: [LogLine] = []
            for case let entry as OSLogEntryLog in entries {
                let level: String = switch entry.level {
                case .debug: "debug"
                case .info: "info"
                case .notice: "notice"
                case .error: "error"
                case .fault: "fault"
                default: "log"
                }
                lines.append(LogLine(id: lines.count, date: entry.date, level: level,
                                     category: entry.category, message: entry.composedMessage))
            }
            return Array(lines.suffix(limit))
        }.value
    }

    /// Writes `exports/diagnostics-<time>.json` under the control root.
    @MainActor
    static func export(state: AppControlJSON) async throws -> AppControlJSON {
        let started = ContinuousClock.now
        let lines = await logs(limit: 1000)
        let device = UIDevice.current
        let bundle: AppControlJSON = [
            "exportedAt": .string(Date().formatted(.iso8601)),
            "device": [
                "model": .string(device.model), "system": .string("\(device.systemName) \(device.systemVersion)"),
                "name": .string(device.name),
            ],
            "app": [
                "version": .string(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""),
                "build": .string(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""),
            ],
            "state": state,
            "performance": DevToolsController.shared.sampler.json,
            "signposts": AppControlHost.signposts(recent: 200),
            "logs": .array(lines.map { line in
                ["at": .string(line.date.formatted(.iso8601)), "level": .string(line.level),
                 "category": .string(line.category), "message": .string(line.message)]
            }),
        ]
        let folder = AppControlHost.root.appending(path: "exports", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        let name = "diagnostics-\(stamp.string(from: Date())).json"
        let file = folder.appending(path: name)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(bundle)
        try data.write(to: file, options: .atomic)
        return [
            "file": .string(file.path),
            "containerPath": .string("Library/Application Support/\(AppControl.rootFolderName)/exports/\(name)"),
            "name": .string(name), "bytes": .number(Double(data.count)), "logLines": .number(Double(lines.count)),
            "ms": .number(AppControlHost.ms(since: started)),
        ]
    }
}
#endif
