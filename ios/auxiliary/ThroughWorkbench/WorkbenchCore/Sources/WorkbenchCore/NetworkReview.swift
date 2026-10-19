import Foundation

public enum Severity: String, Codable, Sendable { case error, warning, unknown }
public struct ReviewIssue: Identifiable, Sendable {
    public let id: String
    public let patternID: String
    public let message: String
    public let severity: Severity
}
public struct PatternDifference: Identifiable, Sendable {
    public var id: String { patternID }
    public let patternID: String
    public let name: String
    public let change: String
}
public struct PatternSummary: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let serviceCode: String
    public let isActive: Bool
    public let isHistoricalEvidenceMissing: Bool
    public var statusLabel: String { isHistoricalEvidenceMissing ? "Unknown" : isActive ? "Active" : "Inactive" }
    public let legs: [LegSummary]
    public let activeLegOrder: [Int]
    public var activeLegs: [LegSummary] {
        activeLegOrder.compactMap { index in legs.first { $0.index == index && $0.isActive } }
    }
    public let sourceURLs: [String]
    public let notes: String
    public let raw: JSONValue
}
public struct LegSummary: Identifiable, Sendable {
    public let id: String
    public let index: Int
    public let lineID: String
    public let fromStationCode: String
    public let toStationCode: String
    public let validFrom: String?
    public let validTo: String?
    public let isActive: Bool
    public let coordinates: [[Double]]
    public let fromName: String
    public let toName: String
    public let raw: JSONValue
}

extension WorkbenchDocument {
    /// Matches recorded named-railway continuity at these selected survey endpoints.
    /// This is not source-content verification, a historical geometry reconstruction,
    /// or a reproduction of the native route graph's full section identity checks.
    func reviewedJunction(between first: JSONValue, and second: JSONValue, on day: String,
                          lines: [String: JSONValue], firstCoordinates: [[Double]], secondCoordinates: [[Double]]) -> String? {
        guard physicalJunctions?["format"]?.stringValue == "jtm-physical-rail-junctions-v1",
              let rows = physicalJunctions?["junctions"]?.arrayValue,
              let firstID = first["lineID"]?.stringValue, let secondID = second["lineID"]?.stringValue,
              firstID != secondID, let firstLine = lines[firstID], let secondLine = lines[secondID],
              let end = firstCoordinates.last, let start = secondCoordinates.first,
              firstCoordinates.count >= 2, secondCoordinates.count >= 2 else { return nil }
        let duplicates = Dictionary(grouping: rows, by: { $0["id"]?.stringValue ?? "" })
        func matches(_ endpoint: JSONValue?, line: JSONValue, region: String, coordinate: [Double]) -> Bool {
            guard let identity = endpoint?["identity"],
                  let railwayOperator = identity["operatorName"]?.stringValue, !railwayOperator.isEmpty,
                  let name = identity["lineName"]?.stringValue, !name.isEmpty,
                  let railwayClass = identity["railwayClassCode"]?.stringValue, !railwayClass.isEmpty,
                  line["railwayIdentity"]?.stringValue == "\(region)-\(railwayOperator)-\(name)",
                  Self.junctionCoordinate(endpoint?["coordinate"]) == coordinate else { return false }
            // Compact railwayIdentity preserves the source's named identity despite
            // display-brand operator changes. Preserve any finer identity it carries.
            for key in ["railwayClassCode", "level", "trackID"] {
                if let actual = line[key], actual != .null, actual != identity[key] { return false }
                if ["level", "trackID"].contains(key), let expected = identity[key], expected != .null,
                   expected != .string(""), line[key] != expected { return false }
            }
            return true
        }
        for row in rows {
            guard let id = row["id"]?.stringValue, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  duplicates[id]?.count == 1, let region = row["region"]?.stringValue,
                  ["jp", "tw", "hk", "mo", "kr"].contains(region),
                  package?["country"]?.stringValue?.lowercased() == region,
                  let rawLineIDs = row["lineIDs"]?.arrayValue,
                  rawLineIDs.allSatisfy({ $0.stringValue?.isEmpty == false }),
                  let lineIDs = row["lineIDs"]?.arrayValue?.compactMap(\.stringValue),
                  lineIDs.contains(firstID), lineIDs.contains(secondID),
                  let from = row["validFrom"]?.stringValue, ISODay.date(from) != nil,
                  let reviewed = row["reviewedAt"]?.stringValue, ISODay.date(reviewed) != nil,
                  from <= reviewed, day <= reviewed,
                  (try? Self.validateWindows(row, label: id)) != nil, ISODay.active(row, on: day),
                  row["geometryEvidence"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                  row["temporalEvidence"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                  let evidence = row["evidence"]?.arrayValue, !evidence.isEmpty,
                  evidence.allSatisfy({ value in
                      guard let text = value.stringValue, !text.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains),
                            let url = URL(string: text) else { return false }
                      return ["http", "https"].contains(url.scheme?.lowercased() ?? "") && !(url.host ?? "").isEmpty
                  }), Self.reviewedJunctionGeometry(row) else { continue }
            if (matches(row["from"], line: firstLine, region: region, coordinate: end)
                && matches(row["to"], line: secondLine, region: region, coordinate: start))
                || (matches(row["to"], line: firstLine, region: region, coordinate: end)
                    && matches(row["from"], line: secondLine, region: region, coordinate: start)) { return id }
        }
        return nil
    }

    static func junctionCoordinate(_ value: JSONValue?) -> [Double]? {
        guard let pair = value?.arrayValue, pair.count == 2,
              let x = pair[0].numberValue, let y = pair[1].numberValue,
              x.isFinite, y.isFinite, abs(x) <= 180, abs(y) <= 90 else { return nil }
        return [x, y]
    }
    private static func junctionMeters(_ a: [Double], _ b: [Double]) -> Double {
        let radians = Double.pi / 180
        let lat = (b[1] - a[1]) * radians, lon = (b[0] - a[0]) * radians
        let h = pow(sin(lat / 2), 2) + cos(a[1] * radians) * cos(b[1] * radians) * pow(sin(lon / 2), 2)
        return 6_371_000 * 2 * asin(sqrt(min(1, h)))
    }
    static func reviewedJunctionGeometry(_ row: JSONValue) -> Bool {
        guard let from = junctionCoordinate(row["from"]?["coordinate"]),
              let to = junctionCoordinate(row["to"]?["coordinate"]) else { return false }
        let kind: String
        if row["kind"] == nil || row["kind"] == .null { kind = "zeroLength" }
        else if let declared = row["kind"]?.stringValue { kind = declared }
        else { return false }
        switch kind {
        case "zeroLength": return from == to
        case "shortLink": return from != to && junctionMeters(from, to) <= 30
        case "osmConnector":
            guard row["terminus"] == nil || row["terminus"] == .null,
                  row["endJunction"] == nil || row["endJunction"] == .null,
                  row["from"]?["identity"] != row["to"]?["identity"],
                  let declaredFrom = row["attachMeters"]?["from"]?.numberValue,
                  let declaredTo = row["attachMeters"]?["to"]?.numberValue,
                  declaredFrom.isFinite, declaredTo.isFinite,
                  (0...50).contains(declaredFrom), (0...50).contains(declaredTo),
                  row["source"]?["provider"]?.stringValue == "OpenStreetMap",
                  row["source"]?["license"]?.stringValue == "ODbL-1.0",
                  row["source"]?["ways"]?.arrayValue?.isEmpty == false,
                  let retrieved = row["source"]?["retrieved"]?.stringValue, ISODay.date(retrieved) != nil,
                  let raw = row["path"]?.arrayValue, raw.count >= 2 else { return false }
            let path = raw.compactMap { junctionCoordinate($0) }
            guard path.count == raw.count else { return false }
            let fromAttach = junctionMeters(from, path[0]), toAttach = junctionMeters(to, path[path.count - 1])
            let steps = zip(path, path.dropFirst()).map { junctionMeters($0, $1) }
            return fromAttach <= 50 && toAttach <= 50 && steps.allSatisfy { $0 <= 2_000 }
                && steps.reduce(fromAttach + toAttach, +) <= 1_500
        // An osmTrack is same-identity geometry; its foreign endJunction needs
        // native section/stub validation and is not accepted as a two-end join here.
        default: return false
        }
    }

    public func patterns(on day: String) throws -> [PatternSummary] {
        let source = try catalog(on: day)
        let lines = physicalLines()
        return (source["patterns"]?.arrayValue ?? []).map { pattern in
            let id = pattern["id"]?.stringValue ?? ""
            let active = ISODay.active(pattern, on: day)
            let floor = source["coverageFrom"]?.stringValue
            let beforeCoverage = floor.map { day < $0 && pattern["validFrom"]?.stringValue == nil } ?? false
            let missingVariant = active && (pattern["legVariants"]?.arrayValue.map { variants in
                !variants.contains { ISODay.active($0, on: day) }
            } ?? false)
            let unknown = beforeCoverage || missingVariant
            let activeOrder = unknown ? [] : Self.activeLegIndices(pattern, on: day)
            let activeIndices = Set(activeOrder)
            let legs = (pattern["legs"]?.arrayValue ?? []).enumerated().map { index, leg in
                let lineID = leg["lineID"]?.stringValue ?? ""
                let start = leg["fromStationCode"]?.stringValue ?? ""
                let end = leg["toStationCode"]?.stringValue ?? ""
                let line = lines[lineID]
                let names = stationNames(line)
                return LegSummary(id: "\(id)-leg-\(index)", index: index, lineID: lineID,
                    fromStationCode: start, toStationCode: end,
                    validFrom: leg["validFrom"]?.stringValue, validTo: leg["validTo"]?.stringValue,
                    isActive: active && activeIndices.contains(index),
                    coordinates: geometry(line: line, from: start, to: end, loopTraversal: leg["loopTraversal"],
                                          loopTraversalSourceURLs: leg["loopTraversalSourceURLs"]),
                    fromName: names[start] ?? start, toName: names[end] ?? end, raw: leg)
            }
            return PatternSummary(id: id, name: pattern["name"]?.stringValue ?? id,
                serviceCode: pattern["serviceCode"]?.stringValue ?? id,
                isActive: active && legs.contains { $0.isActive }, isHistoricalEvidenceMissing: unknown,
                legs: legs, activeLegOrder: activeOrder,
                sourceURLs: pattern["sourceURLs"]?.arrayValue?.compactMap(\.stringValue) ?? [],
                notes: pattern["notes"]?.stringValue ?? "", raw: pattern)
        }
    }

    public func audit(on day: String) throws -> [ReviewIssue] {
        let current = try catalog(on: day)
        var issues: [ReviewIssue] = []
        func issue(_ id: String, _ pattern: String, _ text: String, _ severity: Severity) {
            issues.append(ReviewIssue(id: id, patternID: pattern, message: text, severity: severity))
        }
        if let floor = catalog["coverageFrom"]?.stringValue, day < floor {
            issue("coverage-before-floor", "", "所选日期早于导入目录的覆盖起点 \(floor)。无开始日期的服务不能据此认定在当日存在。N02 1996-12-31 是观测基准。", .unknown)
        }
        if let checked = catalog["checkedAt"]?.stringValue, day > checked {
            issue("coverage-after-check", "", "所选日期晚于目录核对日 \(checked)，后续运营变化尚未证实。", .unknown)
        }
        if package == nil {
            issue("physical-package-missing", "", "未导入物理线路包，无法检查车站锚点与线路几何。", .unknown)
        } else if day < "2025-01-01" {
            issue("historical-geometry-review", "", "地图使用导入包的物理几何。当前线路 ID 不等于当年的运营者或线路身份；历史叠加与身份期间须复核。", .unknown)
        }
        if history != nil {
            issue("history-overlay-evidence", "", "已保留历史几何叠加；所选直通路径仍使用线路包锚点。旧版 N02 运营者补全和再分发条件需要单独核实。", .unknown)
        }
        let lines = physicalLines()
        let connectors = current["connectors"]?.arrayValue ?? []
        for pattern in try patterns(on: day) {
            do { try Self.validateWindows(pattern.raw, label: pattern.id) }
            catch { issue("\(pattern.id)-window", pattern.id, error.localizedDescription, .error) }
            if pattern.sourceURLs.isEmpty { issue("\(pattern.id)-source", pattern.id, "缺少直通服务来源。", .unknown) }
            if pattern.raw["validFrom"]?.stringValue == nil {
                issue("\(pattern.id)-unknown-start", pattern.id, "服务开始日期未明确；覆盖起点以前的存在性需要来源。", .unknown)
            }
            if pattern.raw["historicalReview"]?["status"]?.stringValue == "onsetConstraintOnly" {
                issue("\(pattern.id)-onset-scope", pattern.id,
                    "已核对开通日期，完整端点与历史路径仍待核实：" + (pattern.raw["historicalReview"]?["supportedScope"]?.stringValue ?? ""), .unknown)
            }
            if pattern.raw["historicalReview"]?["status"]?.stringValue == "periodsUnresolved" {
                issue("\(pattern.id)-period-scope", pattern.id,
                    "历史运行期间与端点尚未完整确认：" + (pattern.raw["historicalReview"]?["supportedScope"]?.stringValue ?? ""), .unknown)
            }
            if pattern.notes.contains("confidence: medium") || pattern.notes.contains("unconfirmed") {
                issue("\(pattern.id)-confidence", pattern.id, "原记录注明中等可信度或未确认事实，不能视为完整历史证明。", .unknown)
            }
            for leg in pattern.legs {
                do { try Self.validateWindows(leg.raw, label: pattern.id) }
                catch { issue("\(leg.id)-window", pattern.id, error.localizedDescription, .error) }
                if leg.fromStationCode == leg.toStationCode || leg.lineID.isEmpty {
                    issue("\(leg.id)-anchors", pattern.id, "区段需要有效线路及不同的起终点锚点。", .error)
                }
                guard package != nil else { continue }
                guard let line = lines[leg.lineID] else {
                    issue("\(leg.id)-line", pattern.id, "物理包没有线路：\(leg.lineID)", .error); continue
                }
                if let traversal = leg.raw["loopTraversal"], traversal != .null {
                    if !["forward", "reverse"].contains(traversal.stringValue ?? "") || !Self.isLoop(line) {
                        issue("\(leg.id)-loop-traversal", pattern.id, "loopTraversal 必须在环线上明确为 forward 或 reverse。", .error)
                    }
                    let sources = leg.raw["loopTraversalSourceURLs"]?.arrayValue ?? []
                    if sources.isEmpty { issue("\(leg.id)-loop-source", pattern.id, "环线区段方向缺少来源；当前路径选择不能证明历史方向。", .unknown) }
                    else if !sources.allSatisfy({ value in
                        guard let text = value.stringValue, let url = URL(string: text),
                              !text.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains) else { return false }
                        return ["http", "https"].contains(url.scheme?.lowercased() ?? "") && !(url.host ?? "").isEmpty
                    }) { issue("\(leg.id)-loop-source", pattern.id, "环线区段方向来源网页格式无效。", .error) }
                }
                let names = stationNames(line)
                if names[leg.fromStationCode] == nil || names[leg.toStationCode] == nil
                    || stationCoordinate(line, code: leg.fromStationCode) == nil || stationCoordinate(line, code: leg.toStationCode) == nil {
                    issue("\(leg.id)-station", pattern.id, "锚点不属于指定线路或坐标无效：\(leg.fromStationCode) → \(leg.toStationCode)", .error)
                } else if leg.coordinates.count < 2 {
                    if Self.decodedSourceIntervals(line) != nil && Self.isLoop(line)
                        && (Self.loopDirection(line, traversal: leg.raw["loopTraversal"]) == nil
                            || (leg.raw["loopTraversal"] != nil && leg.raw["loopTraversal"] != .null
                                && !Self.loopTraversalHasEvidence(leg.raw["loopTraversalSourceURLs"]))) {
                        issue("\(leg.id)-geometry", pattern.id, "环线方向没有明确来源，不能唯一选择有序路径。", .unknown)
                    } else { issue("\(leg.id)-geometry", pattern.id, "区段缺少完整的物理折线。", .error) }
                }
                if let first = leg.coordinates.first, let last = leg.coordinates.last,
                   (first != stationCoordinate(line, code: leg.fromStationCode) || last != stationCoordinate(line, code: leg.toStationCode)) {
                    issue("\(leg.id)-anchor-mismatch", pattern.id, "来源折线端点与车站锚点不一致；显示吸附不能作为物理连接证明。", .warning)
                }
                if let reverse = leg.raw["reverseLineID"]?.stringValue {
                    guard let mate = lines[reverse] else {
                        issue("\(leg.id)-reverse", pattern.id, "反向线路不存在：\(reverse)", .error); continue
                    }
                    let related = mate["alignmentOf"]?.stringValue == leg.lineID || line["alignmentOf"]?.stringValue == reverse
                    let mateNames = stationNames(mate)
                    if !related || mate["operator"] != line["operator"] || mateNames[leg.fromStationCode] == nil || mateNames[leg.toStationCode] == nil {
                        issue("\(leg.id)-reverse", pattern.id, "反向线路不是同运营者的配对区段或缺少锚点。", .error)
                    }
                }
            }
            if pattern.raw["legVariants"]?.arrayValue == nil && ISODay.active(pattern.raw, on: day) {
                let candidates = pattern.legs.filter { ISODay.active($0.raw, on: day) }
                if zip(candidates, candidates.dropFirst()).contains(where: { $1.index > $0.index + 1 }) {
                    issue("\(pattern.id)-date-path-gap", pattern.id, "时间过滤移除了中间区段；已拒绝整条路径，需提供有来源的明确 legVariants。", .error)
                }
            }
            let active = pattern.activeLegs
            for (a, b) in zip(active, active.dropFirst()) {
                if b.index > a.index + 1 && pattern.raw["legVariants"]?.arrayValue == nil {
                    issue("\(pattern.id)-skipped-\(a.index)", pattern.id, "时间过滤跨过了中间区段；请明确当日有序路径（也可能是互斥替代区段）。", .warning)
                }
                let firstIDs = [a.lineID, a.raw["reverseLineID"]?.stringValue].compactMap { $0 }
                let secondIDs = [b.lineID, b.raw["reverseLineID"]?.stringValue].compactMap { $0 }
                let connector = connectors.contains { c in
                    guard ISODay.active(c, on: day) else { return false }
                    return (firstIDs.contains(c["fromLineID"]?.stringValue ?? "") && c["fromStationCode"]?.stringValue == a.toStationCode && secondIDs.contains(c["toLineID"]?.stringValue ?? "") && c["toStationCode"]?.stringValue == b.fromStationCode)
                        || (secondIDs.contains(c["fromLineID"]?.stringValue ?? "") && c["fromStationCode"]?.stringValue == b.fromStationCode && firstIDs.contains(c["toLineID"]?.stringValue ?? "") && c["toStationCode"]?.stringValue == a.toStationCode)
                }
                let reviewed = reviewedJunction(between: a.raw, and: b.raw, on: day, lines: lines,
                                                firstCoordinates: a.coordinates, secondCoordinates: b.coordinates) != nil
                if a.toStationCode == b.fromStationCode,
                   let end = a.coordinates.last, let start = b.coordinates.first, end != start, !reviewed {
                    issue("\(pattern.id)-physical-gap-\(a.index)", pattern.id,
                        "相同站码的两个物理端点不重合。直通运营关系不能填补轨道几何缺口，需复核连接。", .warning)
                }
                if !reviewed && (connector || (a.lineID != b.lineID && a.toStationCode == b.fromStationCode)) {
                    issue("\(pattern.id)-junction-evidence-\(a.index)", pattern.id, "显示直通关系和相同站码不能证明物理轨道连接；需要经审查的物理连接证据。", .unknown)
                }
                if a.toStationCode != b.fromStationCode && !connector && !reviewed {
                    issue("\(pattern.id)-join-\(a.index)", pattern.id, "区段不连续：\(a.toName) [\(a.toStationCode)] → \(b.fromName) [\(b.fromStationCode)]；没有已登记的直通连接。", .error)
                }
            }
        }
        return issues
    }

    public func differences(from: String, to: String) throws -> [PatternDifference] {
        let before = try patterns(on: from), after = try patterns(on: to)
        let a = Dictionary(uniqueKeysWithValues: before.map { ($0.id, $0) })
        let b = Dictionary(uniqueKeysWithValues: after.map { ($0.id, $0) })
        return Set(a.keys).union(b.keys).sorted().compactMap { id in
            let old = a[id], new = b[id]
            let oldLegs = old?.activeLegs.map(\.raw) ?? []
            let newLegs = new?.activeLegs.map(\.raw) ?? []
            guard old?.raw != new?.raw || old?.isActive != new?.isActive || old?.isHistoricalEvidenceMissing != new?.isHistoricalEvidenceMissing || oldLegs != newLegs else { return nil }
            let evidenceChanged = old?.isHistoricalEvidenceMissing != new?.isHistoricalEvidenceMissing
            let change = old == nil ? "新增记录" : new == nil ? "移除记录" : evidenceChanged ? "历史证据状态变化（\(old?.statusLabel ?? "Unknown") → \(new?.statusLabel ?? "Unknown")）" : old?.isActive != new?.isActive ? (new?.isActive == true ? "服务启用" : "服务停用") : oldLegs != newLegs ? "有序区段变化" : "字段变化"
            return PatternDifference(patternID: id, name: new?.name ?? old?.name ?? id, change: change)
        }
    }

    func physicalLines() -> [String: JSONValue] {
        var result: [String: JSONValue] = [:]
        for line in package?["lines"]?.arrayValue ?? [] { if let id = line["id"]?.stringValue { result[id] = line } }
        return result
    }
    func stationNames(_ line: JSONValue?) -> [String: String] {
        var result: [String: String] = [:]
        for station in line?["stations"]?.arrayValue ?? [] {
            if let row = station.arrayValue, row.count >= 2, let id = row[0].stringValue { result[id] = row[1].stringValue ?? id }
        }
        return result
    }
    /// Decode chained compact-v1 seams before slicing. Missing rows never become straight chords.
    func geometry(line: JSONValue?, from: String, to: String, loopTraversal: JSONValue? = nil,
                  loopTraversalSourceURLs: JSONValue? = nil) -> [[Double]] {
        guard let intervals = Self.decodedSourceIntervals(line) else { return [] }
        return Self.sourceCoordinates(line: line, intervals: intervals, from: from, to: to,
                                      loopTraversal: loopTraversal, loopTraversalSourceURLs: loopTraversalSourceURLs)
    }
    static func isLoop(_ line: JSONValue?) -> Bool {
        line?["isLoop"] == .bool(true) || line?["isLoop"]?.numberValue == 1
    }
    /// A loop has two possible ordered paths until source-backed direction metadata selects one.
    static func loopDirection(_ line: JSONValue?, traversal: JSONValue? = nil) -> Int? {
        if let traversal, traversal != .null {
            if traversal == .string("forward") { return 1 }
            if traversal == .string("reverse") { return -1 }
            return nil
        }
        if line?["permittedTraversal"]?.stringValue == "forward" { return 1 }
        if line?["permittedTraversal"]?.stringValue == "reverse" { return -1 }
        if let alignment = line?["alignmentDirection"]?.stringValue,
           let order = line?["stationOrderDirection"]?.stringValue,
           ["up", "down"].contains(alignment), ["up", "down"].contains(order) {
            return alignment == order ? 1 : -1
        }
        return nil
    }
    static func loopTraversalHasEvidence(_ value: JSONValue?) -> Bool {
        guard let sources = value?.arrayValue, !sources.isEmpty else { return false }
        return sources.allSatisfy { value in
            guard let text = value.stringValue, !text.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains),
                  let url = URL(string: text) else { return false }
            return ["http", "https"].contains(url.scheme?.lowercased() ?? "") && !(url.host ?? "").isEmpty
        }
    }
    static func sourceCoordinates(line: JSONValue?, intervals: [[[Double]]], from: String, to: String,
                                  loopTraversal: JSONValue? = nil, loopTraversalSourceURLs: JSONValue? = nil) -> [[Double]] {
        let stations = line?["stations"]?.arrayValue ?? []
        guard let start = stations.firstIndex(where: { $0.arrayValue?.first?.stringValue == from }),
              let end = stations.firstIndex(where: { $0.arrayValue?.first?.stringValue == to }), start != end else { return [] }
        let direction: Int
        if isLoop(line) {
            if loopTraversal != nil && loopTraversal != .null && !loopTraversalHasEvidence(loopTraversalSourceURLs) { return [] }
            guard let selected = loopDirection(line, traversal: loopTraversal) else { return [] }
            direction = selected
        } else {
            guard loopTraversal == nil || loopTraversal == .null else { return [] }
            direction = start < end ? 1 : -1
        }
        var cursor = start
        var result: [[Double]] = []
        for _ in 0..<stations.count {
            if cursor == end { return result }
            let next = (cursor + direction + stations.count) % stations.count
            let index = direction == 1 ? cursor : next
            guard intervals.indices.contains(index) else { return [] }
            let coords = direction == 1 ? intervals[index] : Array(intervals[index].reversed())
            if let last = result.last {
                guard last == coords.first else { return [] }
                result.append(contentsOf: coords.dropFirst())
            } else { result = coords }
            cursor = next
        }
        return cursor == end ? result : []
    }
    /// Inspection keeps surveyed coordinates: station dots and display snapping are not evidence.
    static func decodedSourceIntervals(_ line: JSONValue?) -> [[[Double]]]? {
        let stations = line?["stations"]?.arrayValue ?? []
        guard stations.count >= 2, let rows = line?["segments"]?.arrayValue else { return nil }
        let loop = Self.isLoop(line)
        guard rows.count == stations.count - (loop ? 0 : 1) else { return nil }
        var previous: [Double]?
        var intervals: [[[Double]]] = []
        for row in rows {
            guard let v = row.arrayValue, v.count >= 3,
                  let flag = v[1].numberValue, flag == 0 || flag == 1,
                  let points = v[2].arrayValue else { return nil }
            var coords = points.compactMap { point -> [Double]? in
                guard let xy = point.arrayValue, xy.count >= 2,
                      let x = xy[0].numberValue, let y = xy[1].numberValue,
                      x.isFinite, y.isFinite, abs(x) <= 180, abs(y) <= 90 else { return nil }
                return [x, y]
            }
            guard coords.count == points.count else { return nil }
            if flag == 1 {
                guard let previous else { return nil }
                coords.insert(previous, at: 0)
            }
            guard coords.count >= 2 else { return nil }
            intervals.append(coords); previous = coords.last
        }
        return intervals
    }
    func stationCoordinate(_ line: JSONValue?, code: String) -> [Double]? {
        guard let station = line?["stations"]?.arrayValue?.first(where: { $0.arrayValue?.first?.stringValue == code }),
              let row = station.arrayValue, row.count >= 4,
              let x = row[2].numberValue, let y = row[3].numberValue,
              x.isFinite, y.isFinite, abs(x) <= 180, abs(y) <= 90 else { return nil }
        return [x, y]
    }

}
