import Foundation
import Testing

@testable import RailCore

/// Opt-in sample migration through the same import and canonical save paths
/// as the app. The output is staged for review, never written over the input.
struct SampleStoreUpgradeTests {
    @Test func upgradeSampleStore() throws {
        guard let output = ProcessInfo.processInfo.environment["SAMPLE_STORE_UPGRADE_OUT"],
              !output.isEmpty else { return }
        let source = try ProcessInfo.processInfo.environment["SAMPLE_STORE_UPGRADE_IN"]
            .map { URL(fileURLWithPath: $0) }
            ?? PortFixtures.repositoryRoot().appending(path: "app/data/train-store.json")
        let destination = URL(fileURLWithPath: output)
        try #require(destination.standardizedFileURL != source.standardizedFileURL)
        let data = try Data(contentsOf: source)
        let original = try JSONDecoder().decode(TrainStore.self, from: data)
        let imported = try TrainValidation.parseImportedCanonicalStore(
            text: String(decoding: data, as: UTF8.self))
        guard case .array(let rows)? = imported["trains"] else {
            Issue.record("Sample store must contain a trains array")
            return
        }
        try #require(rows.count == 201)
        var workspace = StoreOperations.Workspace(country: "jp")
        for (index, row) in rows.enumerated() {
            try StoreOperations.appendImportedTrain(row, in: &workspace)
            // Import splits legacy bilingual captions. This format-only
            // migration must preserve their authored text and English names.
            workspace.store.trains[index].number = original.trains[index].number
            if let english = original.trains[index].numberEn {
                workspace.store.trains[index].numberEn = english
            }
        }
        // Ordinary RideEditorView save passes its draft unchanged; visit IDs
        // are assigned only by route editing, so no identities are invented.
        var upgraded = TrainValidation.buildCanonicalTrainStore(workspace.trains, country: "jp")
        for index in upgraded.trains.indices {
            // Sample sections are reviewed physical claims. Preserve their
            // authored shape, including empty arrays; load-time inference must
            // not turn inferred adjacent sections into persisted evidence.
            upgraded.trains[index].routeSections = original.trains[index].routeSections
            // Canonicalization fills absent preferences with empty arrays.
            // Preserve the sample's authored policy rather than adding defaults.
            upgraded.trains[index].routePolicy?.preferredLineNames =
                original.trains[index].routePolicy?.preferredLineNames
            upgraded.trains[index].routePolicy?.preferredOperatorNames =
                original.trains[index].routePolicy?.preferredOperatorNames
        }
        try #require(upgraded.trains.allSatisfy { $0.routeConfirmation == nil })
        let json = StoreOperations.json(upgraded)
        try TrainValidation.validateTrainStore(json)
        let text = StoreOperations.stringify(json, indent: 2) + "\n"
        try text.write(to: destination, atomically: true, encoding: .utf8)
    }
}
