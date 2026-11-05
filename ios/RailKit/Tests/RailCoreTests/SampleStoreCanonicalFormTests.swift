import Foundation
import Testing
@testable import RailCore

/// The bundled example stores are stored exactly as the app stores a user's
/// own rides in `Rides/train-store.json`.
///
/// A ride the user saves passes through `RideStorage.writeStore`:
///   1. `BundledRegistry.upgradeIfReady` = ``RegistryIdentityUpgrade/apply(_:bundle:)``
///      with the ride's region bundle (`operator_id(s)`, stop and section `station_id`);
///   2. `MergedStore.export`: each train through
///      ``TrainValidation/normalizeExportTrain(_:country:stations:)`` for its own
///      region, stringified at indent 2, every line indented four spaces, spliced
///      into the canonical `TrainStore()` envelope.
/// `canonicalBytes` repeats those steps with the same RailCore functions (the
/// app-target wrappers only select the registry and region), so a bundled store
/// that equals its canonical bytes is byte-for-byte what the app would write.
///
/// Opt-in, because on main the registry upgrade still rebuilds a whole
/// RegistryIdentity per stop (~10 min for the 287 rides; data-perf's
/// 1d2b64625 removes that). Check with SAMPLE_CANONICAL_CHECK=1, or rewrite
/// the stores after a data edit with
///     SAMPLE_CANONICAL_WRITE=1 swift test --filter SampleStoreCanonicalFormTests
struct SampleStoreCanonicalFormTests {
    static let stores = [
        "train-store.json", "train-store-tw.json", "train-store-hk.json", "train-store-kr.json",
        "train-store-mo.json", "special-samples/new-year-grand-loop.json",
        "special-samples/tokyo-limited-express-loop.json",
    ]

    static func canonicalBytes(_ store: TrainStore, bundles: (String) throws -> RegistryBundle) throws -> String {
        let envelope = StoreOperations.stringify(StoreOperations.json(TrainStore()), indent: 2)
        guard !store.trains.isEmpty, let emptyArray = envelope.range(of: "[]") else { return envelope }
        var text = String(envelope[..<emptyArray.lowerBound]) + "[\n"
        for (index, train) in store.trains.enumerated() {
            let region = try #require(train.region, "sample \(train.id) must name its region")
            let upgraded = RegistryIdentityUpgrade.apply(train, bundle: try bundles(region))
            let normalized = TrainValidation.normalizeExportTrain(upgraded, country: region)
            if index > 0 { text += ",\n" }
            text += "    " + StoreOperations.stringify(StoreOperations.json(normalized), indent: 2)
                .replacingOccurrences(of: "\n", with: "\n    ")
        }
        text += "\n  ]"
        text += envelope[emptyArray.upperBound...]
        return text
    }

    @Test("Every bundled example store is byte-identical to the app's own ride store format",
          .enabled(if: ProcessInfo.processInfo.environment["SAMPLE_CANONICAL_CHECK"] == "1"
                       || ProcessInfo.processInfo.environment["SAMPLE_CANONICAL_WRITE"] == "1"))
    func bundledSamplesAreCanonical() throws {
        let root = try PortFixtures.repositoryRoot()
        var cache: [String: RegistryBundle] = [:]
        func bundle(_ region: String) throws -> RegistryBundle {
            if let cached = cache[region] { return cached }
            let url = root.appending(path: "app/data/registry-bundle/\(region).json")
            let loaded = try JSONDecoder().decode(RegistryBundle.self, from: Data(contentsOf: url))
            cache[region] = loaded
            return loaded
        }
        let rewrite = ProcessInfo.processInfo.environment["SAMPLE_CANONICAL_WRITE"] == "1"
        for name in Self.stores {
            let url = root.appending(path: "app/data/\(name)")
            let data = try Data(contentsOf: url)
            let store = try JSONDecoder().decode(TrainStore.self, from: data)
            for train in store.trains { try TrainValidation.validateSupportedRegions(train) }
            var canonical = try Self.canonicalBytes(store, bundles: bundle)
            // Canonical bytes are a fixed point: decoding and re-exporting them changes nothing.
            let again = try Self.canonicalBytes(
                JSONDecoder().decode(TrainStore.self, from: Data(canonical.utf8)), bundles: bundle)
            #expect(again == canonical, "\(name): canonical export is not a fixed point")
            canonical = again
            if rewrite {
                try Data(canonical.utf8).write(to: url, options: .atomic)
            } else {
                #expect(String(decoding: data, as: UTF8.self) == canonical,
                        "\(name) differs from the app's ride-store bytes; rerun with SAMPLE_CANONICAL_WRITE=1")
            }
        }
    }
}
