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
}
