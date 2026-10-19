import Foundation

/// Content identities generated from the resources copied into an app build.
/// A revision changes when a country's solver or display inputs change.
public struct RailResourceRevisions: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let regions: [String: String]
    public let timetableRevision: String
    public let sourceHashes: [String: String]

    public init(schemaVersion: Int = 1, regions: [String: String],
                timetableRevision: String, sourceHashes: [String: String] = [:]) {
        self.schemaVersion = schemaVersion
        self.regions = regions
        self.timetableRevision = timetableRevision
        self.sourceHashes = sourceHashes
    }

    public enum ResourceError: Error, LocalizedError, Sendable, Equatable {
        case missingResource
        case invalidArtifact(String)
        case missingRegion(String)

        public var errorDescription: String? {
            switch self {
            case .missingResource: "Rail resource revisions are missing from the selected bundle."
            case .invalidArtifact(let reason): "Invalid rail resource revisions: \(reason)"
            case .missingRegion(let country): "Rail resource revisions have no identity for \(country)."
            }
        }
    }

    private static let bundledLock = NSLock()
    nonisolated(unsafe) private static var bundledRevisions: [URL: Self] = [:]

    /// The app's content attestation has one reader. Invalid or missing files
    /// throw and are never retained as an empty or partially loaded snapshot.
    public static func bundled(bundle: Bundle = .main) throws -> Self {
        guard let url = bundle.url(forResource: "rail-resource-revisions", withExtension: "json") else {
            throw ResourceError.missingResource
        }
        bundledLock.lock()
        defer { bundledLock.unlock() }
        let key = url.standardizedFileURL
        if let revisions = bundledRevisions[key] { return revisions }
        let decoded = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard decoded.schemaVersion == 1, !decoded.regions.isEmpty,
              decoded.regions.values.allSatisfy({ !$0.isEmpty }), !decoded.timetableRevision.isEmpty else {
            throw ResourceError.invalidArtifact("unsupported schema or empty content identity")
        }
        bundledRevisions[key] = decoded
        return decoded
    }

    /// Resource consumers requiring an identity must not invent an unversioned cache key.
    public func requiredRevision(for country: String) throws -> String {
        guard let revision = revision(for: country) else { throw ResourceError.missingRegion(country) }
        return revision
    }

    /// Border journeys depend on every country in their scope, in stable order.
    public func revision(for country: String) -> String? {
        guard schemaVersion == 1 else { return nil }
        let countries = Set(country.split(separator: "+").map(String.init)).sorted()
        guard !countries.isEmpty else { return nil }
        var values: [String] = []
        for code in countries {
            guard let revision = regions[code], !revision.isEmpty else { return nil }
            values.append("\(code):\(revision)")
        }
        return values.joined(separator: "|")
    }

    /// Legacy parts without a content attestation are solved on the device.
    public func acceptsPrecomputed(sourceHashes candidate: [String: String]?, country: String) -> Bool {
        guard schemaVersion == 1, let candidate, !candidate.isEmpty else { return false }
        let suffix = country == "jp" ? "" : "-\(country)"
        let required = ["\(country)-2025.json", "rail-sections\(suffix).json",
                        "stations\(suffix).json", "matched-routes.json", "matched-stops.json"]
        guard required.allSatisfy({ candidate[$0] != nil && sourceHashes[$0] != nil }) else { return false }
        let history = "rail-history\(suffix).json"
        guard candidate[history] == sourceHashes[history] else { return false }
        return candidate.allSatisfy { filename, hash in
            !hash.isEmpty && sourceHashes[filename] == hash
        }
    }

    /// A fresh manifest cannot attest an older or unattested chunk's geometry.
    public func acceptsPrecomputed(
        manifestSourceHashes: [String: String]?, partSourceHashes: [String: String]?, country: String
    ) -> Bool {
        acceptsPrecomputed(sourceHashes: manifestSourceHashes, country: country)
            && acceptsPrecomputed(sourceHashes: partSourceHashes, country: country)
            && manifestSourceHashes == partSourceHashes
    }
}
