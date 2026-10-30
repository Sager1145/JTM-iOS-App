import CryptoKit
import Foundation
import Testing
@testable import RailMap

struct RailDisplayTemporalArtifactTests {
    private let digest = String(repeating: "0", count: 64)
    private var bank: [String: Any] {
        ["historyRevision": "history-1", "bankRevision": "bank-1",
         "sourcePackageSHA256": digest, "managedLineIDs": ["isumi"]]
    }

    private func historyData(bank: [String: Any]? = nil) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "format": "jtm-display-history-v1", "region": "jp", "temporalBank": bank ?? self.bank,
            "revision": "history-1",
            "parts": [["id": "jp|isumi#0", "index": 0, "kind": "current",
                       "validTo": "2024-10-05", "suspensionPeriodID": "isumi.suspension"] as [String: Any]],
            "stationStamps": [["id": "isumi:005136", "kind": "current",
                               "validFrom": "2008-08-09", "validTo": "2024-10-05",
                               "historyId": "isumi.opening", "suspensionPeriodID": "isumi.suspension"]],
            "lines": [], "stations": [],
        ] as [String: Any])
    }

    private func region(history: Data, temporal: Bool = true) -> [String: Any] {
        var value: [String: Any] = [
            "region": "jp", "file": "jp.display.bin", "bytes": 1, "sha256": digest,
            "minZoomMapLibre": 0, "stationsFile": "jp.stations.json",
            "historyFile": "jp.display-history.json", "historyBytes": history.count,
            "historySHA256": SHA256.hash(data: history).map { String(format: "%02x", $0) }.joined(),
        ]
        if temporal { value["temporalBank"] = bank }
        return value
    }

    private func decodeRegion(_ value: [String: Any]) throws -> RailDisplayNetworkManifest.RegionRecord {
        try JSONDecoder().decode(
            RailDisplayNetworkManifest.RegionRecord.self,
            from: JSONSerialization.data(withJSONObject: value))
    }

    private func withBundle<T>(history: Data?, _ body: (Bundle) throws -> T) throws -> T {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bundle")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let info = ["CFBundleIdentifier": "com.jtm.temporal-fixture", "CFBundleName": "TemporalFixture"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: root.appendingPathComponent("Info.plist"))
        let resources = root.appendingPathComponent("rail-display-network")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        if let history { try history.write(to: resources.appendingPathComponent("jp.display-history.json")) }
        return try body(#require(Bundle(url: root)))
    }

    @Test func requiredHistoryBindsBytesDigestRevisionAndBankBeforeAdmission() throws {
        let data = try historyData()
        let record = try decodeRegion(region(history: data))
        try withBundle(history: data) { bundle in
            let loadedHistory = try RailDisplayNetwork.history(record, bundle: bundle)
            let file = try #require(loadedHistory)
            #expect(file.partRows["jp|isumi#0"]?[0]?.suspensionPeriodID == "isumi.suspension")
            #expect(file.stationStampRows["isumi:005136"]?.suspensionPeriodID == "isumi.suspension")
            #expect(file.stationStampRows["isumi:005136"]?.historyId == "isumi.opening")
        }
        try withBundle(history: nil) { bundle in
            #expect(throws: (any Error).self) { try RailDisplayNetwork.history(record, bundle: bundle) }
        }
        for key in ["historyFile", "historyBytes", "historySHA256"] {
            var missing = region(history: data)
            missing.removeValue(forKey: key)
            let incomplete = try decodeRegion(missing)
            try withBundle(history: data) { bundle in
                #expect(throws: (any Error).self) { try RailDisplayNetwork.history(incomplete, bundle: bundle) }
            }
        }
        for key in ["historyRevision", "bankRevision", "sourcePackageSHA256", "managedLineIDs"] {
            var other = bank
            if key == "managedLineIDs" { other[key] = ["other"] }
            else { other[key] = "mismatch" }
            let mismatched = try historyData(bank: other)
            let matchingBytes = try decodeRegion(region(history: mismatched))
            try withBundle(history: mismatched) { bundle in
                #expect(throws: (any Error).self) { try RailDisplayNetwork.history(matchingBytes, bundle: bundle) }
            }
        }
        for revision in [nil, "stale-history"] as [String?] {
            var changed = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            changed["revision"] = revision
            let changedData = try JSONSerialization.data(withJSONObject: changed)
            let matchingBytes = try decodeRegion(region(history: changedData))
            try withBundle(history: changedData) { bundle in
                #expect(throws: (any Error).self) {
                    try RailDisplayNetwork.history(matchingBytes, bundle: bundle)
                }
            }
        }
        for key in ["parts", "stationStamps"] {
            var incomplete = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            incomplete[key] = [] as [Any]
            let partialData = try JSONSerialization.data(withJSONObject: incomplete)
            let partialRecord = try decodeRegion(region(history: partialData))
            try withBundle(history: partialData) { bundle in
                #expect(throws: (any Error).self) { try RailDisplayNetwork.history(partialRecord, bundle: bundle) }
            }
        }
        var wrongDigest = region(history: data)
        wrongDigest["historySHA256"] = digest
        let digestMismatch = try decodeRegion(wrongDigest)
        try withBundle(history: data) { bundle in
            #expect(throws: (any Error).self) { try RailDisplayNetwork.history(digestMismatch, bundle: bundle) }
        }
        try withBundle(history: Data("corrupt".utf8)) { bundle in
            #expect(throws: (any Error).self) { try RailDisplayNetwork.history(record, bundle: bundle) }
        }
    }

    @Test func legacyV2KeepsMissingOptionalHistoryNil() throws {
        let data = try historyData()
        let record = try decodeRegion(region(history: data, temporal: false))
        try withBundle(history: nil) { bundle in
            let loadedHistory = try RailDisplayNetwork.history(record, bundle: bundle)
            #expect(loadedHistory == nil)
        }
        var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "revision")
        let legacyData = try JSONSerialization.data(withJSONObject: legacy)
        let legacyRecord = try decodeRegion(region(history: legacyData, temporal: false))
        try withBundle(history: legacyData) { bundle in
            let loadedHistory = try RailDisplayNetwork.history(legacyRecord, bundle: bundle)
            let file = try #require(loadedHistory)
            #expect(file.revision == nil)
        }
        var value = manifest(format: "jtm-display-network-v2", history: data)
        value.removeValue(forKey: "requiredFeatures")
        var regions = try #require(value["regions"] as? [[String: Any]])
        regions[0].removeValue(forKey: "temporalBank")
        value["regions"] = regions
        #expect(try decodeManifest(value).format == "jtm-display-network-v2")
    }

    private func manifest(format: String, history: Data) -> [String: Any] {
        let regions = ["jp", "tw", "hk", "mo", "kr", "cn"].map { country -> [String: Any] in
            if country == "jp" { return region(history: history) }
            return ["region": country, "file": "\(country).display.bin", "bytes": 1,
                    "sha256": digest, "minZoomMapLibre": 0, "stationsFile": "\(country).stations.json"]
        }
        return [
            "format": format, "requiredFeatures": ["dated_service_bank_v1"],
            "packageSHA256": Dictionary(uniqueKeysWithValues: ["jp", "tw", "hk", "mo", "kr", "cn"].map { ($0, digest) }),
            "regions": regions,
            "lines": ["jp|isumi": ["id": "isumi", "region": "jp", "name": "Isumi", "rank": 1,
                                     "color": "#000000", "colorDark": "#000000", "minZoomMapLibre": 0,
                                     "lodMinZoomMapLibre": 0, "visibilityLengthKm": 26.8,
                                     "bounds": ["minLon": 140, "minLat": 35, "maxLon": 141, "maxLat": 36],
                                     "chunk": ["offset": 0, "length": 1, "sha256": digest] as [String: Any]] as [String: Any]],
        ]
    }

    private func decodeManifest(_ value: [String: Any]) throws -> RailDisplayNetworkManifest {
        try JSONDecoder().decode(RailDisplayNetworkManifest.self,
                                from: JSONSerialization.data(withJSONObject: value)).validated()
    }

    @Test func versionThreeRequiresKnownFeatureAndCompleteTemporalBinding() throws {
        let data = try historyData()
        let valid = manifest(format: "jtm-display-network-v3", history: data)
        #expect(try decodeManifest(valid).format == "jtm-display-network-v3")
        for capabilities in [[], ["future_feature"], ["dated_service_bank_v1", "future_feature"]] {
            var unknown = valid
            unknown["requiredFeatures"] = capabilities
            #expect(throws: (any Error).self) { try decodeManifest(unknown) }
        }
        var missing = valid
        var regions = try #require(valid["regions"] as? [[String: Any]])
        regions[0].removeValue(forKey: "historySHA256")
        missing["regions"] = regions
        #expect(throws: (any Error).self) { try decodeManifest(missing) }
        for (key, badValue) in [
            ("historyRevision", "" as Any), ("bankRevision", "" as Any),
            ("sourcePackageSHA256", String(repeating: "1", count: 64) as Any),
            ("managedLineIDs", ["unlisted"] as Any),
        ] {
            var invalidBank = bank
            invalidBank[key] = badValue
            var invalidRegion = region(history: data)
            invalidRegion["temporalBank"] = invalidBank
            var invalidManifest = valid
            var invalidRegions = try #require(valid["regions"] as? [[String: Any]])
            invalidRegions[0] = invalidRegion
            invalidManifest["regions"] = invalidRegions
            #expect(throws: (any Error).self) { try decodeManifest(invalidManifest) }
        }
        var downgraded = valid
        downgraded["format"] = "jtm-display-network-v2"
        #expect(throws: (any Error).self) { try decodeManifest(downgraded) }
    }

    @Test func chunkAdmissionRequiresMatchingHistoryCompleteStampsAndManifestVersion() throws {
        let history = try historyData()
        func chunk(_ count: Int = 1, format: String = "jtm-display-network-v3") throws -> Data {
            try JSONSerialization.data(withJSONObject: [
                "format": format, "region": "jp", "lineId": "isumi",
                "lines": [["lineKey": "jp|isumi", "continuous": true, "chain": 0,
                           "parts": Array(repeating: [[140.0, 35.0], [140.1, 35.1]], count: count)] as [String: Any]],
                "stations": [],
            ] as [String: Any])
        }
        for (blob, accepted) in [(try chunk(), true), (try chunk(2), false),
                                 (try chunk(format: "jtm-display-network-v2"), false)] {
            var value = manifest(format: "jtm-display-network-v3", history: history)
            var catalog = try #require(value["lines"] as? [String: [String: Any]])
            catalog["jp|isumi"]?["chunk"] = [
                "offset": 0, "length": blob.count,
                "sha256": SHA256.hash(data: blob).map { String(format: "%02x", $0) }.joined(),
            ]
            value["lines"] = catalog
            let manifest = try decodeManifest(value)
            let entry = try #require(RailDisplayNetworkIndex.lineIndex(for: manifest).entryByID["isumi"])
            #expect(throws: (any Error).self) {
                try RailDisplayNetwork.chunk(entry, blob: blob, catalog: manifest.lines, families: [:])
            }
            try withBundle(history: history) { bundle in
                let record = try #require(manifest.regions.first { $0.region == "jp" })
                let loadedHistory = try RailDisplayNetwork.history(record, bundle: bundle)
                let file = try #require(loadedHistory)
                if accepted {
                    let decoded = try RailDisplayNetwork.chunk(
                        entry, blob: blob, catalog: manifest.lines, families: [:], history: file)
                    #expect(decoded.lines.count == 1)
                } else {
                    #expect(throws: (any Error).self) {
                        try RailDisplayNetwork.chunk(
                            entry, blob: blob, catalog: manifest.lines, families: [:], history: file)
                    }
                }
            }
        }
    }
}
