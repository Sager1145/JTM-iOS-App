import Foundation

/// Optional part identities let a dataset locate trains without opening route geometry.
/// Missing or null identity maps use the legacy part scan; declared maps must be valid.
public struct DatasetManifestIndex: Decodable, Sendable {
    public struct PartRef: Sendable, Equatable {
        public let name: String
        public let position: Int

        public init(name: String, position: Int) {
            self.name = name
            self.position = position
        }
    }

    public let parts: [String]
    private let partTrainIDs: [String: String]?

    private enum CodingKeys: String, CodingKey {
        case parts
        case partTrainIDs = "part_train_ids"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        parts = try container.decode([String].self, forKey: .parts)
        partTrainIDs = try container.decodeIfPresent([String: String].self, forKey: .partTrainIDs)
        if let partTrainIDs {
            guard Set(partTrainIDs.keys) == Set(parts) else {
                throw DecodingError.dataCorruptedError(forKey: .partTrainIDs, in: container,
                    debugDescription: "Part identity coverage must exactly match the manifest parts.")
            }
            guard partTrainIDs.values.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                throw DecodingError.dataCorruptedError(forKey: .partTrainIDs, in: container,
                    debugDescription: "Part train identities must not be empty.")
            }
        }
    }

    /// Only a missing or null identity map requests the caller's legacy scan.
    public var indexedParts: [String: [PartRef]]? {
        guard let partTrainIDs else { return nil }
        var index: [String: [PartRef]] = [:]
        index.reserveCapacity(parts.count)
        for (position, name) in parts.enumerated() {
            // Exact coverage and nonempty IDs were established during decode.
            index[partTrainIDs[name]!, default: []].append(PartRef(name: name, position: position))
        }
        return index
    }
}
