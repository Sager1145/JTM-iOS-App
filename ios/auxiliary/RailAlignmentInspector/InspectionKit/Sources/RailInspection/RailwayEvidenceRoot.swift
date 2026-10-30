import Foundation

/// Auxiliary evidence lives on the mounted external archive. Explicit scratch
/// URLs remain available to isolated tests; an unavailable archive never falls back.
public enum RailwayEvidenceRoot {
    public static let externalVolume = URL(fileURLWithPath: "/Volumes/JTM Evidence", isDirectory: true)
    public static let canonicalRoot = externalVolume.appendingPathComponent(
        "99 Compatibility/Workspace/JTM-iOS-App/railway-evidence/local", isDirectory: true)

    public enum WriteError: LocalizedError {
        case archiveUnavailable
        case outsideEvidenceStorage(String)

        public var errorDescription: String? {
            switch self {
            case .archiveUnavailable:
                "Mount the external railway evidence archive at /Volumes/JTM Evidence before writing evidence."
            case .outsideEvidenceStorage(let path):
                "Evidence writes require the external archive or an explicit private scratch path: \(path)"
            }
        }
    }

    public static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment,
                               sourceFile: String = #filePath) -> URL {
        if let override = environment["RAILWAY_EVIDENCE_ROOT"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true).standardizedFileURL
        }
        return canonicalRoot
    }

    /// Return the actual write URL, so atomic replacement cannot replace a
    /// compatibility leaf link in the checkout. This function creates nothing.
    public static func validatedWriteURL(_ url: URL, externalVolumeAvailable: Bool? = nil) throws -> URL {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        let scratchRoots = [URL(fileURLWithPath: "/private/tmp", isDirectory: true),
                            FileManager.default.temporaryDirectory.resolvingSymlinksInPath()]
        if scratchRoots.contains(where: { contains(resolved, in: $0) }) { return resolved }
        guard contains(resolved, in: canonicalRoot) else {
            throw WriteError.outsideEvidenceStorage(url.path)
        }
        let mounted = externalVolumeAvailable ?? ((try? externalVolume.resourceValues(forKeys: [.volumeURLKey]))?
            .volume?.standardizedFileURL.path == externalVolume.path)
        guard mounted else { throw WriteError.archiveUnavailable }
        return resolved
    }

    private static func contains(_ url: URL, in root: URL) -> Bool {
        let path = url.path, base = root.standardizedFileURL.path
        return path == base || path.hasPrefix(base + "/")
    }

    public static func diagnosticSessions(root: URL = resolve()) -> URL {
        root.appendingPathComponent("diagnostics/sessions", isDirectory: true)
    }

    public static func alignmentInspector(root: URL = resolve()) -> URL {
        root.appendingPathComponent("alignment-inspector", isDirectory: true)
    }

    public static func batchEvidence(root: URL = resolve()) -> URL {
        alignmentInspector(root: root).appendingPathComponent("BatchEvidence", isDirectory: true)
    }
}
