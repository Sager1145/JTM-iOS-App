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
