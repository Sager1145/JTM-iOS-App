import Foundation
import Testing
@testable import RailCore

/// Regression guard: every row-to-row link a physical junction row records is
/// read by `TripConnectivity.Junctions`. A row that names three or more package
/// rows (several rows of one identity meet the junction vertex) must split them
/// into `fromLineIDs` and `toLineIDs`; without those sides the reader cannot
/// tell which rows face each other and joins none of them, so a planned trip
/// across that junction is silently drawn as a transfer. Every pair across the
/// sides (and every two-ID row) must come back from `join(_:_:at:on:)` on a
/// date the row is valid.
struct RegressionGuardJunctionRowsRead {
    private struct Document: Decodable {
        struct Row: Decodable {
            struct Marker: Decodable {}
            let id: String
            let region: String
            let stationCode: String?
            let lineIDs: [String]?
            let fromLineIDs: [String]?
            let toLineIDs: [String]?
            let evidence: [String]
            let validFrom: String?
            let validTo: String?
            let endJunction: Marker?
        }
        let junctions: [Row]
    }

    /// Reviewed rows that name two lineIDs but carry no stationCode, so the reader skips
    /// them on purpose. Only shrinks: an entry that gains a code (or disappears) fails.
    static let reviewedCodeless: [String: String] = [
        "musashino-minami-fuchuhommachi-tsurumi":
            "osmTrack over the 武蔵野南線 freight line 府中本町–鶴見; the route graph carries it, but no package row changes onto 東海道線 at a coded station",
    ]

    /// Rows whose recorded links the reader drops, with the reason.
    static func unreadLinks(_ data: Data, region: String,
                            reviewedCodeless: [String: String] = [:]) throws -> [String] {
        let rows = try JSONDecoder().decode(Document.self, from: data).junctions.filter { $0.region == region }
        let junctions = try TripConnectivity.Junctions(registryData: data, region: region)
        var problems: [String] = []
        for row in rows {
            let ids = row.lineIDs ?? []
            if row.fromLineIDs != nil || row.toLineIDs != nil, ids.count <= 2 {
                problems.append("\(row.id): fromLineIDs/toLineIDs are only for rows naming three or more lineIDs")
            }
            guard ids.count >= 2 else { continue }
            if row.evidence.isEmpty {
                problems.append("\(row.id): names \(ids.count) lineIDs but has no evidence")
                continue
            }
            guard let code = row.stationCode else {
                if reviewedCodeless[row.id] == nil {
                    problems.append("\(row.id): names \(ids.count) lineIDs but has no stationCode, so TripConnectivity never reads it; add the package station code, or list it in reviewedCodeless with a reason")
                }
                continue
            }
            if reviewedCodeless[row.id] != nil {
                problems.append("\(row.id): listed in reviewedCodeless but now has stationCode \(code); remove the entry")
            }
            if row.endJunction != nil, !RouteGraph.PhysicalJunction.hasSameTrainEvidence(row.evidence) { continue }
            let pairs = TripConnectivity.Junctions.linePairs(
                lineIDs: row.lineIDs, fromLineIDs: row.fromLineIDs, toLineIDs: row.toLineIDs)
            if pairs.isEmpty {
                problems.append("\(row.id): names \(ids.count) lineIDs; give fromLineIDs and toLineIDs (disjoint, non-empty, together exactly lineIDs)")
                continue
            }
            // A date inside [validFrom, validTo): an undated ride sees only open rows.
            let date = row.validFrom ?? (row.validTo == nil ? nil : "1872-10-14")
            for pair in pairs {
                let ab = pair.sorted()
                if junctions.join(ab[0], ab[1], at: code, on: date)?.id == nil {
                    problems.append("\(row.id): \(ab[0]) / \(ab[1]) at \(code) is not read")
                }
            }
        }
        return problems
    }

    @Test("Every jp junction row's row-to-row links are read by TripConnectivity")
    func registryLinksAreRead() throws {
        let url = try PortFixtures.repositoryRoot().appendingPathComponent("app/data/physical-rail-junctions.json")
        let data = try Data(contentsOf: url)
        var problems = try Self.unreadLinks(data, region: "jp", reviewedCodeless: Self.reviewedCodeless)
        let ids = Set(try JSONDecoder().decode(Document.self, from: data).junctions.map(\.id))
        for id in Self.reviewedCodeless.keys.sorted() where !ids.contains(id) {
            problems.append("\(id): listed in reviewedCodeless but no longer in the registry; remove the entry")
        }
        #expect(problems.isEmpty, "unread junction links:\n\(problems.joined(separator: "\n"))")
    }

    @Test("Three-row junctions expand across their sides only")
    func sidesExpandAcross() throws {
        func doc(_ extra: String) -> Data {
            Data("""
            {"format":"jtm-physical-rail-junctions-v1","junctions":[{"id":"j","region":"jp",
             "stationCode":"S","lineIDs":["A","B","B-2"],\(extra)"evidence":["https://example.org"]}]}
            """.utf8)
        }
        let sided = doc(#""fromLineIDs":["A"],"toLineIDs":["B","B-2"],"#)
        let junctions = try TripConnectivity.Junctions(registryData: sided, region: "jp")
        #expect(junctions.join("A", "B", at: "S", on: nil)?.id == "j")
        #expect(junctions.join("B-2", "A", at: "S", on: nil)?.id == "j")
        #expect(junctions.join("B", "B-2", at: "S", on: nil) == nil)
        #expect(try Self.unreadLinks(sided, region: "jp").isEmpty)

        let unsided = doc("")
        #expect(try TripConnectivity.Junctions(registryData: unsided, region: "jp")
            .join("A", "B", at: "S", on: nil) == nil)
        #expect(try Self.unreadLinks(unsided, region: "jp").count == 1)

        let overlapping = doc(#""fromLineIDs":["A","B"],"toLineIDs":["B","B-2"],"#)
        #expect(try Self.unreadLinks(overlapping, region: "jp").count == 1)
    }
}
