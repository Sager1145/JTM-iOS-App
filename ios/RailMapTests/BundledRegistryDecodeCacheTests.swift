import Foundation
import Testing

@testable import RailMap

struct BundledRegistryDecodeCacheTests {
    private func json(region: String) -> Data {
        Data("""
        {"schema":"jtm-registry-bundle/1","region":"\(region)","run":1,"stationCodes":{},"groupCodes":{},"operators":{},"stationOperator":{},"lines":{}}
        """.utf8)
    }

    @Test func badJSONDecodesAndLogsOnce() {
        var cache = BundledRegistry.DecodeCache()
        var loads = 0
        let bad = Data("{".utf8)
        let first = cache.lookup(region: "jp") {
            loads += 1
            return bad
        }
        let second = cache.lookup(region: "jp") {
            loads += 1
            return bad
        }
        #expect(first == nil)
        #expect(second == nil)
        #expect(loads == 1)
        #expect(cache.logCount == 1)
    }

    @Test func missingFileIsNotCached() {
        var cache = BundledRegistry.DecodeCache()
        var loads = 0
        #expect(cache.lookup(region: "jp") {
            loads += 1
            return nil
        } == nil)
        #expect(cache.lookup(region: "jp") {
            loads += 1
            return nil
        } == nil)
        #expect(loads == 2)
        #expect(cache.logCount == 0)
    }

    @Test func unreadableExistingFileIsACachedFailure() {
        var cache = BundledRegistry.DecodeCache()
        var loads = 0
        #expect(cache.lookup(region: "jp", fileExists: true) {
            loads += 1
            return nil
        } == nil)
        #expect(cache.lookup(region: "jp", fileExists: true) {
            loads += 1
            return nil
        } == nil)
        #expect(loads == 1)
        #expect(cache.logCount == 1)
        #expect(cache.hasFailed("jp"))
    }

    @Test func regionMismatchIsACachedDecodeFailure() {
        var cache = BundledRegistry.DecodeCache()
        var loads = 0
        let data = json(region: "tw")
        #expect(cache.lookup(region: "jp") {
            loads += 1
            return data
        } == nil)
        #expect(cache.lookup(region: "jp") {
            loads += 1
            return data
        } == nil)
        #expect(loads == 1)
        #expect(cache.logCount == 1)
    }

    @Test func successfulDecodeIsCached() {
        var cache = BundledRegistry.DecodeCache()
        var loads = 0
        let data = json(region: "jp")
        let first = cache.lookup(region: "JP") {
            loads += 1
            return data
        }
        let second = cache.lookup(region: "jp") {
            loads += 1
            return data
        }
        #expect(first?.region == "jp")
        #expect(second?.region == "jp")
        #expect(loads == 1)
        #expect(cache.logCount == 0)
    }

    @Test func schema1DropsReverseMapsAndSchema2KeepsOperatorRecords() throws {
        var cache = BundledRegistry.DecodeCache()
        let legacy = Data("""
        {"schema":"jtm-registry-bundle/1","region":"jp","run":1,"stationCodes":{},"groupCodes":{},"operators":{"op:jp:1":["JR東日本"]},"stationOperator":{},"lines":{},"stations":{"st:jp:1":{"cx":"cx:jp:1","group":"G","codes":[],"op":"op:jp:1","name":"東京","lines":[]}}}
        """.utf8)
        let old = cache.lookup(region: "jp") { legacy }
        #expect(old?.schema == RegistryBundle.legacySchema)
        #expect(old?.stations.isEmpty == true)
        #expect(old?.operators["op:jp:1"] == ["JR東日本"])

        var fresh = BundledRegistry.DecodeCache()
        let current = Data("""
        {"schema":"jtm-registry-bundle/2","region":"tw","run":2,"stationCodes":{},"groupCodes":{},"operators":{"op:tw:1":{"names":["台鐵"],"label":"台鐵","logo":null,"identity":null}},"stationOperator":{},"lines":{},"stations":{},"complexes":{},"lineParts":{}}
        """.utf8)
        let decoded = try #require(fresh.lookup(region: "tw") { current })
        #expect(decoded.operatorRecords["op:tw:1"]?.label == "台鐵")
        #expect(decoded.operatorRecords["op:tw:1"]?.logo == nil)
        #expect(decoded.operators["op:tw:1"] == ["台鐵"])
        #expect(RegistryIdentity(bundle: decoded).`operator`(for: "op:tw:1")?.label == "台鐵")
    }
}
