import Foundation

/// Every error AreaKit raises. Messages are complete sentences for the CLI.
public enum AreaRepairError: LocalizedError, Equatable {
    case repositoryNotFound(String)
    case invalidJSON(String)
    case invalidScope(String)
    case invalidPatch(String)
    case confirmationRequired
    case refused(String)
    case guardFailed(String)
    case changedSinceWrite(String)

    public var errorDescription: String? {
        switch self {
        case .repositoryNotFound(let path): "No JTM repository (a directory containing port-fixtures) at or above \(path)."
        case .invalidJSON(let reason): "Invalid JSON: \(reason)."
        case .invalidScope(let reason): "Area scope: \(reason)"
        case .invalidPatch(let reason): "Area patch: \(reason)"
        case .confirmationRequired: "Writing to the repository requires an explicit confirmation (--confirm)."
        case .refused(let reason): "Refused: \(reason)"
        case .guardFailed(let reason): "Regression guard failed; the write was reverted. \(reason)"
        case .changedSinceWrite(let path): "\(path) changed after the write; undo refuses to overwrite it."
        }
    }
}

/// The five repository data files an area reads, by role.
public enum DataFile: String, CaseIterable, Codable, Sendable {
    case package, sections, stations, history, junctions

    /// Path relative to the repository root.
    public var relativePath: String {
        switch self {
        case .package: "app/public/rail/jp-2025.json"
        case .sections: "app/data/rail-sections.json"
        case .stations: "app/data/stations.json"
        case .history: "app/data/rail-history.json"
        case .junctions: "app/data/physical-rail-junctions.json"
        }
    }

    public init?(relativePath: String) {
        guard let file = Self.allCases.first(where: { $0.relativePath == relativePath }) else { return nil }
        self = file
    }
}

/// Where data is read from: the repository, optionally shadowed file by file
/// by a scratch overlay directory that mirrors the repository layout.
public struct DataRoot: Equatable, Sendable {
    public var repo: URL
    public var overlay: URL?

    public init(repo: URL, overlay: URL? = nil) {
        self.repo = repo.standardizedFileURL
        self.overlay = overlay?.standardizedFileURL
    }

    /// The overlay copy when it exists, else the repository file.
    public func url(_ file: DataFile) -> URL {
        if let overlay {
            let candidate = overlay.appending(path: file.relativePath)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return repo.appending(path: file.relativePath)
    }

    /// True when `file` is served from the overlay.
    public func isOverlaid(_ file: DataFile) -> Bool { url(file) != repo.appending(path: file.relativePath) }

    /// The bundled sample rides used when no journeys file is given.
    public var defaultTrains: URL { repo.appending(path: "app/data/default-trains.json") }

    /// Walks up from `start` to the first directory that contains `port-fixtures`.
    public static func discoverRepo(from start: URL) throws -> URL {
        var directory = start.standardizedFileURL
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), !isDirectory.boolValue {
            directory.deleteLastPathComponent()
        }
        while true {
            if FileManager.default.fileExists(atPath: directory.appending(path: "port-fixtures").path) { return directory }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path { throw AreaRepairError.repositoryNotFound(start.path) }
            directory = parent
        }
    }
}
