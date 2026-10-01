import Foundation

/// Optional part identities let a dataset locate trains without opening route geometry.
/// Older or malformed identity maps remain readable and use the caller's part scan.
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
        // A bad optional field must not prevent the legacy scan.
        partTrainIDs = try? container.decode([String: String].self, forKey: .partTrainIDs)
    }

    /// Returns nil unless every listed part has a nonempty identity and coverage is exact.
    public var indexedParts: [String: [PartRef]]? {
        guard let partTrainIDs,
              Set(partTrainIDs.keys) == Set(parts),
              partTrainIDs.values.allSatisfy({
                  !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              }) else { return nil }
        var index: [String: [PartRef]] = [:]
        index.reserveCapacity(parts.count)
        for (position, name) in parts.enumerated() {
            guard let id = partTrainIDs[name] else { return nil }
            index[id, default: []].append(PartRef(name: name, position: position))
        }
        return index
    }
}
