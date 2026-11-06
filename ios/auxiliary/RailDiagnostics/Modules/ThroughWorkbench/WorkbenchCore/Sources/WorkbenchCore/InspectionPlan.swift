import Foundation

public struct InspectionPlan: Codable, Sendable {
    public let startDay: String
    public let endDay: String
    public let patternCount: Int
    public let sampledDays: [String]
    public let checks: [InspectionCheck]
    public let findings: [InspectionFinding]
}
public struct InspectionCheck: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let scope: String
    public let result: String
    public let detail: String
}
public struct InspectionFinding: Codable, Sendable, Identifiable {
    public let id: String
    public let patternID: String
    public let category: String
    public let title: String
    public let severity: Severity
    public let days: [String]
    public let recommendation: String
    public let requiresEvidence: Bool
}

extension WorkbenchDocument {
    /// Bounded boundary inspection. It reports source gaps; it never turns them into historical facts.
    public func inspectionPlan(through endDay: String) throws -> InspectionPlan {
        try ISODay.validate(endDay)
        guard targetFrom <= endDay else { throw WorkbenchError.invalid("检查结束日不能早于历史目标起点。") }
        var worker = InspectionWorker(document: self, endDay: endDay)
        return worker.run()
    }
}

private struct InspectionWorker {
    let document: WorkbenchDocument
    let endDay: String
    var days = Set<String>()
    var findings: [String: InspectionFinding] = [:]
    // Immutable physical inputs are decoded once per referenced line, independent of sampled dates.
    var decoded: [String: [[[Double]]]] = [:]
    var invalidLines = Set<String>()
    var legCoordinates: [JSONValue: [[Double]]] = [:]
    var inspectedPatterns = Set<JSONValue>()
    var inspectedConnectors = Set<JSONValue>()
    var matchedJunctions = Set<String>()
    var lines: [String: JSONValue] = [:]
    let layers: [(String, String)] = [
        ("catalog", "目录结构与身份"), ("windows", "半开有效期"),
        ("variants", "历史有序路径"), ("sources", "来源与证据范围"),
        ("physical", "物理锚点与方向"), ("junctions", "区段连接"),
        ("coverage", "时间覆盖"), ("history", "历史几何与身份"),
        ("inventory", "外部服务清单完整性"), ("parity", "原生应用一致性")
    ]

    mutating func add(_ key: String, pattern: String = "", category: String, title: String,
                      severity: Severity = .unknown, day: String? = nil, evidence: Bool = true,
                      recommendation: String = "查阅有日期和明确适用范围的来源，再提交带来源的修复；保留未知状态。") {
        // Category + scoped key is stable across dates and repeated plan runs.
        let id = "\(category):\(pattern):\(key)"
        var occurrences = Set(findings[id]?.days ?? [])
        if let day { occurrences.insert(day) }
        findings[id] = InspectionFinding(id: id, patternID: pattern, category: category,
            title: title, severity: severity, days: occurrences.sorted(),
            recommendation: recommendation, requiresEvidence: evidence)
    }
    mutating func boundary(_ day: String?) {
        guard let day, let date = ISODay.date(day) else { return }
        if day >= document.targetFrom && day <= endDay { days.insert(day) }
        let before = ISODay.string(date.addingTimeInterval(-86400))
        if before >= document.targetFrom && before <= endDay { days.insert(before) }
    }
    mutating func collect(_ value: JSONValue) {
        // Patch changes can replace nested windows. Collect date fields without interpreting coordinate values.
        if let object = value.objectValue {
            for (key, child) in object {
                if ["validFrom", "validTo", "effectiveFrom", "effectiveTo"].contains(key) { boundary(child.stringValue) }
                else if child.objectValue != nil || child.arrayValue != nil { collect(child) }
            }
        } else if let array = value.arrayValue { for child in array { collect(child) } }
    }
    func validURL(_ value: JSONValue) -> Bool {
        guard let text = value.stringValue, !text.isEmpty,
              !text.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) }),
              let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              !(url.host ?? "").isEmpty else { return false }
        return true
    }
    mutating func sources(_ value: JSONValue?, pattern: String, key: String, day: String? = nil) {
        guard let rows = value?.arrayValue, !rows.isEmpty else {
            add(key, pattern: pattern, category: "sources", title: "缺少来源网页：\(key)", day: day); return
        }
        if !rows.allSatisfy(validURL) {
            add("\(key)-invalid", pattern: pattern, category: "sources", title: "来源网页格式无效或包含空白：\(key)", severity: .error, day: day)
        }
    }
    @discardableResult mutating func window(_ value: JSONValue, pattern: String, key: String, day: String? = nil) -> Bool {
        do { try WorkbenchDocument.validateWindows(value, label: key); return true }
        catch {
            add(key, pattern: pattern, category: "windows", title: error.localizedDescription,
                severity: .error, day: day, evidence: false,
                recommendation: "修正字段类型或无效日期；若需更改实际运营起止日期，必须先查证来源。")
            return false
        }
    }
    mutating func run() -> InspectionPlan {
        days = [document.targetFrom, endDay]
        collect(document.catalog)
        if let physical = document.physicalJunctions {
            collect(physical)
            for row in physical["junctions"]?.arrayValue ?? [] {
                boundary(row["reviewedAt"]?.stringValue)
                if let reviewed = row["reviewedAt"]?.stringValue.flatMap(ISODay.date) {
                    boundary(ISODay.string(reviewed.addingTimeInterval(86400)))
                }
            }
        }
        boundary(document.catalog["coverageFrom"]?.stringValue)
        boundary(document.catalog["checkedAt"]?.stringValue)
        for patch in document.patches {
            boundary(patch.effectiveFrom); boundary(patch.effectiveTo)
            collect(.object(patch.changes))
            for leg in patch.legChanges { collect(.object(leg.changes)) }
        }
        let sampled = days.sorted()
        let base = document.catalog["patterns"]?.arrayValue ?? []
        let patternCount = Set(base.compactMap { $0["id"]?.stringValue }.filter { !$0.isEmpty }).union(document.patches.map(\.patternID).filter { !$0.isEmpty }).count
        if document.schemaVersion != 1 || document.catalog.objectValue == nil || document.catalog["patterns"]?.arrayValue == nil {
            add("schema", category: "catalog", title: "工作文件或目录结构不受支持。", severity: .error, evidence: false,
                recommendation: "按支持的工作文件格式重新导入，保留原始文件以便审查。")
        }
        if document.catalog["schemaVersion"]?.numberValue != 2 {
            add("catalog-version", category: "catalog", title: "目录 schemaVersion 不是受支持的版本 2。", severity: .error, evidence: false)
        }
        var seen = Set<String>()
        for (index, pattern) in base.enumerated() {
            let id = pattern["id"]?.stringValue ?? ""
            if id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !seen.insert(id).inserted {
                add("identity-\(index)", pattern: id, category: "catalog", title: "记录 ID 为空或重复（记录 #\(index + 1)）。", severity: .error, evidence: false)
            }
        }
        var physicalIDs = Set<String>()
        for (index, line) in (document.package?["lines"]?.arrayValue ?? []).enumerated() {
            guard let id = line["id"]?.stringValue, !id.isEmpty, physicalIDs.insert(id).inserted else {
                add("line-identity-\(index)", category: "physical", title: "物理线路 ID 为空或重复。", severity: .error); continue
            }
            lines[id] = line
        }
        var patchIDs = Set<String>()
        for patch in document.patches {
            if !patchIDs.insert(patch.id).inserted { add("patch-\(patch.id)", pattern: patch.patternID, category: "catalog", title: "修复记录 ID 重复。", severity: .error, evidence: false) }
            do { try patch.validate() }
            catch { add("patch-\(patch.id)", pattern: patch.patternID, category: "windows", title: "修复记录无效：" + error.localizedDescription, severity: .error) }
            if !validURL(.string(patch.sourceURL)) { add("patch-\(patch.id)", pattern: patch.patternID, category: "sources", title: "修复来源网页无效或包含空白。", severity: .error) }
        }
        inspectMetadata(sampled)
        inspectPhysicalJunctions()
        // Raw records remain inspectable even if one malformed import blocks snapshot materialization.
        for (index, pattern) in base.enumerated() { inspectPattern(pattern, fallbackID: "record-\(index)") }
        inspectConnectorList(document.catalog["connectors"])
        for day in sampled {
            let snapshot: JSONValue
            do { snapshot = try document.catalog(on: day) }
            catch {
                add("snapshot", category: "catalog", title: "无法生成历史快照：" + error.localizedDescription, severity: .error, day: day)
                continue
            }
            inspectConnectorList(snapshot["connectors"])
            for (index, pattern) in (snapshot["patterns"]?.arrayValue ?? []).enumerated() {
                inspectPattern(pattern, fallbackID: "record-\(index)")
                inspectDay(pattern, day: day, connectors: snapshot["connectors"]?.arrayValue ?? [])
            }
        }
        let ordered = findings.values.sorted { $0.id < $1.id }
        let checks = layers.map { category, title in
            let scoped = ordered.filter { $0.category == category }
            let result = scoped.contains { $0.severity == .error } ? "failed" : scoped.contains { $0.severity == .unknown } ? "unknown" : scoped.isEmpty ? "passed" : "warning"
            return InspectionCheck(id: category, title: title,
                scope: "\(patternCount) 条记录；\(sampled.count) 个日期边界样本", result: result,
                detail: "\(scoped.count) 项发现。来源格式检查不证明网页内容；日期边界检查不证明每日班次。"
                    + (category == "junctions" ? " 已匹配 \(matchedJunctions.count) 个有日期的来源端点连接；不证明当前几何在历史日完全相同。" : ""))
        }
        return InspectionPlan(startDay: document.targetFrom, endDay: endDay, patternCount: patternCount,
                              sampledDays: sampled, checks: checks, findings: ordered)
    }
    mutating func inspectPhysicalJunctions() {
        guard let value = document.physicalJunctions else { return }
        guard value["format"]?.stringValue == "jtm-physical-rail-junctions-v1",
              let rows = value["junctions"]?.arrayValue else {
            add("physical-format", category: "junctions", title: "物理连接目录格式不受支持。", severity: .error, evidence: false); return
        }
        var ids = Set<String>()
        for (index, row) in rows.enumerated() {
            let id = row["id"]?.stringValue ?? ""
            let key = "physical-\(id.isEmpty ? String(index) : id)"
            if id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !ids.insert(id).inserted {
                add("physical-id-\(index)", category: "junctions", title: "物理连接 ID 为空或重复。", severity: .error, evidence: false)
            }
            window(row, pattern: "", key: key)
            sources(row["evidence"], pattern: "", key: key)
            for note in ["geometryEvidence", "temporalEvidence"] where row[note]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                add("\(key)-\(note)", category: "junctions", title: "物理连接缺少明确的几何或日期证据范围说明。")
            }
            if row["validFrom"]?.stringValue == nil {
                add("\(key)-start", category: "junctions", title: "物理连接未声明起始证据日期；不推断历史连通。")
            }
            if let reviewed = row["reviewedAt"]?.stringValue, ISODay.date(reviewed) != nil {
                if let from = row["validFrom"]?.stringValue, from > reviewed {
                    add("\(key)-review", category: "junctions", title: "物理连接起始日期晚于审查日期。", severity: .error)
                }
            } else { add("\(key)-review", category: "junctions", title: "物理连接审查日期缺失或无效。") }
            let lineIDs = row["lineIDs"]?.arrayValue
            let kind = row["kind"] == nil || row["kind"] == .null ? "zeroLength" : row["kind"]?.stringValue ?? ""
            if kind != "osmTrack", lineIDs?.isEmpty != false || lineIDs?.allSatisfy({ $0.stringValue?.isEmpty == false }) != true {
                add("\(key)-lines", category: "junctions", title: "物理连接缺少明确的线路 ID。", severity: .error)
            }
            if kind == "osmTrack", row["endJunction"] != nil && row["endJunction"] != .null {
                add("\(key)-foreign-stub", category: "junctions", title: "同身份 OSM 轨道的跨身份端点短接需原生来源区段验证；工作台保留未知状态。")
            }
            for side in ["from", "to"] {
                let endpoint = row[side]
                if WorkbenchDocument.junctionCoordinate(endpoint?["coordinate"]) == nil
                    || ["operatorName", "lineName", "railwayClassCode"].contains(where: {
                        endpoint?["identity"]?[$0]?.stringValue?.isEmpty != false
                    }) {
                    add("\(key)-\(side)", category: "junctions", title: "物理连接端点需要完整来源身份和有效测量坐标。", severity: .error)
                }
            }
            if !["zeroLength", "shortLink", "osmConnector", "osmTrack"].contains(kind) {
                add("\(key)-kind", category: "junctions", title: "物理连接类型不受支持。", severity: .error)
            }
            if ["zeroLength", "shortLink", "osmConnector"].contains(row["kind"]?.stringValue ?? "zeroLength"),
               !WorkbenchDocument.reviewedJunctionGeometry(row) {
                add("\(key)-geometry", category: "junctions", title: "物理连接几何不符合声明类型或测量端点限制。", severity: .error)
            }
        }
    }
    mutating func inspectMetadata(_ sampled: [String]) {
        for key in ["coverageFrom", "checkedAt"] {
            guard let day = document.catalog[key]?.stringValue, ISODay.date(day) != nil else {
                add(key, category: "coverage", title: "目录 \(key) 缺失或无效；时间覆盖不能确定。"); continue
            }
            for sample in sampled where (key == "coverageFrom" ? sample < day : sample > day) {
                add(key, category: "coverage", title: key == "coverageFrom" ? "日期早于目录覆盖起点；缺失开始日期不能证明服务存在。" : "日期晚于目录核对日；后续变更未证实。", day: sample)
            }
        }
        if let start = document.catalog["coverageFrom"]?.stringValue, let end = document.catalog["checkedAt"]?.stringValue, start > end {
            add("metadata-order", category: "coverage", title: "覆盖起点晚于核对日期。", severity: .error)
        }
        add("source-content", category: "sources", title: "网页内容、发布日期和所支持的端点范围尚未独立核实。")
        add("completeness", category: "inventory", title: "区域 checked 标签只描述已列记录；外部清单遗漏与全国历史完整性未核实。",
            recommendation: "按地区和期间与官方运营者、时刻表和历史清单核对，记录遗漏及不可编码服务。")
        add("native", category: "parity", title: "原生加载、日期选择、地图绘制和路由一致性尚未执行验证。",
            recommendation: "使用已审查的边界案例进行一次有针对性的原生检查，记录实际观察。")
        add("historical", category: "history", title: document.history == nil ? "未导入历史几何与身份期间；当前物理包不能证明历史路径。" : "历史叠加已保留，但直通路径仍使用物理包；历史身份、几何适用期和再分发条件待核实。")
        if document.package == nil { add("package", category: "physical", title: "未导入物理包；锚点、方向和轨道几何检查无法执行。") }
        for (index, coverage) in (document.catalog["coverage"]?.arrayValue ?? []).enumerated() {
            if coverage["level"]?.stringValue == "checked" {
                add("label-\(index)", category: "inventory", title: "\(coverage["region"]?.stringValue ?? "区域") checked 标签缺少独立完整性证明。")
            }
        }
    }
    mutating func inspectPattern(_ pattern: JSONValue, fallbackID: String) {
        guard inspectedPatterns.insert(pattern).inserted else { return }
        let id = pattern["id"]?.stringValue ?? fallbackID
        guard pattern.objectValue != nil, let legs = pattern["legs"]?.arrayValue, !legs.isEmpty,
              pattern["name"]?.stringValue?.isEmpty == false, pattern["serviceCode"]?.stringValue?.isEmpty == false else {
            add("fields", pattern: id, category: "catalog", title: "记录需要名称、服务代码和非空有序 legs。", severity: .error, evidence: false); return
        }
        window(pattern, pattern: id, key: "pattern")
        sources(pattern["sourceURLs"], pattern: id, key: "pattern")
        if pattern["validFrom"]?.stringValue == nil {
            add("start", pattern: id, category: "coverage", title: "服务开始日期未明确；目标起点以前及目录覆盖起点以前的存在性未知。")
        }
        let review = pattern["historicalReview"]?["status"]?.stringValue
        if review == "onsetConstraintOnly" || review == "periodsUnresolved" {
            add("scope", pattern: id, category: "sources", title: review == "onsetConstraintOnly" ? "开通日期约束不证明完整端点与历史路径。" : "历史运行期间与端点未完整确认。")
        }
        let notes = pattern["notes"]?.stringValue ?? ""
        if notes.contains("confidence: medium") || notes.contains("unconfirmed") {
            add("confidence", pattern: id, category: "sources", title: "记录包含中等可信度或未确认事实。")
        }
        do { try WorkbenchDocument.validateLegVariants(pattern) }
        catch { add("structure", pattern: id, category: "variants", title: error.localizedDescription, severity: .error) }
        for (index, variant) in (pattern["legVariants"]?.arrayValue ?? []).enumerated() {
            window(variant, pattern: id, key: "variant-\(index)")
            sources(variant["sourceURLs"], pattern: id, key: "variant-\(index)")
        }
        for (index, leg) in legs.enumerated() {
            window(leg, pattern: id, key: "leg-\(index)")
            inspectLeg(leg, pattern: id, key: "leg-\(index)")
        }
    }
    mutating func intervals(_ lineID: String) -> [[[Double]]]? {
        if let existing = decoded[lineID] { return existing }
        if invalidLines.contains(lineID) { return nil }
        guard let value = WorkbenchDocument.decodedSourceIntervals(lines[lineID]) else { invalidLines.insert(lineID); return nil }
        decoded[lineID] = value; return value
    }
    mutating func coordinates(_ leg: JSONValue) -> [[Double]] {
        if let cached = legCoordinates[leg] { return cached }
        let result = uncachedCoordinates(leg)
        legCoordinates[leg] = result
        return result
    }
    mutating func uncachedCoordinates(_ leg: JSONValue) -> [[Double]] {
        let lineID = leg["lineID"]?.stringValue ?? ""
        guard let intervals = intervals(lineID) else { return [] }
        return WorkbenchDocument.sourceCoordinates(line: lines[lineID], intervals: intervals,
            from: leg["fromStationCode"]?.stringValue ?? "", to: leg["toStationCode"]?.stringValue ?? "",
            loopTraversal: leg["loopTraversal"], loopTraversalSourceURLs: leg["loopTraversalSourceURLs"])
    }
    mutating func inspectLeg(_ leg: JSONValue, pattern: String, key: String) {
        let id = leg["lineID"]?.stringValue ?? ""
        let from = leg["fromStationCode"]?.stringValue ?? "", to = leg["toStationCode"]?.stringValue ?? ""
        if id.isEmpty || from.isEmpty || to.isEmpty || from == to {
            add(key, pattern: pattern, category: "physical", title: "区段需要线路及不同的起终点锚点。", severity: .error); return
        }
        guard document.package != nil else { return }
        guard let line = lines[id] else { add(key, pattern: pattern, category: "physical", title: "物理线路不存在：\(id)", severity: .error); return }
        if let traversal = leg["loopTraversal"], traversal != .null {
            if !["forward", "reverse"].contains(traversal.stringValue ?? "") || !WorkbenchDocument.isLoop(line) {
                add("\(key)-loop-traversal", pattern: pattern, category: "physical", title: "loopTraversal 必须在环线上明确为 forward 或 reverse。", severity: .error)
            }
            sources(leg["loopTraversalSourceURLs"], pattern: pattern, key: "\(key)-loop-traversal")
        }
        let names = document.stationNames(line)
        guard names[from] != nil && names[to] != nil,
              document.stationCoordinate(line, code: from) != nil,
              document.stationCoordinate(line, code: to) != nil else {
            add(key, pattern: pattern, category: "physical", title: "锚点不属于指定线路或坐标无效：\(from) → \(to)", severity: .error); return
        }
        let coords = coordinates(leg)
        if coords.count < 2 {
            if intervals(id) != nil && WorkbenchDocument.isLoop(line)
                && (WorkbenchDocument.loopDirection(line, traversal: leg["loopTraversal"]) == nil
                    || (leg["loopTraversal"] != nil && leg["loopTraversal"] != .null
                        && !WorkbenchDocument.loopTraversalHasEvidence(leg["loopTraversalSourceURLs"]))) {
                add("\(key)-geometry", pattern: pattern, category: "physical", title: "环线方向未明确，不能唯一选择有序路径。")
            } else { add("\(key)-geometry", pattern: pattern, category: "physical", title: "物理折线缺失、区间行数错误或连续接缝无效。", severity: .error) }
        }
        else if coords.first != document.stationCoordinate(line, code: from) || coords.last != document.stationCoordinate(line, code: to) {
            add("\(key)-anchor", pattern: pattern, category: "physical", title: "来源折线端点与车站锚点不一致；未吸附或补造几何。", severity: .warning)
        }
        if let reverse = leg["reverseLineID"]?.stringValue {
            if let mate = lines[reverse] {
                let related = mate["alignmentOf"]?.stringValue == id || line["alignmentOf"]?.stringValue == reverse
                let mateNames = document.stationNames(mate)
                if !related || mate["operator"] != line["operator"] || mateNames[from] == nil || mateNames[to] == nil {
                    add("\(key)-reverse", pattern: pattern, category: "physical", title: "反向线路关系、运营者或锚点不匹配。", severity: .error)
                }
                var reverseFields: [String: JSONValue] = ["lineID": .string(reverse), "fromStationCode": .string(to), "toStationCode": .string(from)]
                if let traversal = leg["loopTraversal"]?.stringValue, ["forward", "reverse"].contains(traversal) {
                    reverseFields["loopTraversal"] = .string(traversal == "forward" ? "reverse" : "forward")
                    reverseFields["loopTraversalSourceURLs"] = leg["loopTraversalSourceURLs"]
                }
                let reverseLeg: JSONValue = .object(reverseFields)
                inspectLeg(reverseLeg, pattern: pattern, key: "\(key)-reverse-path")
            } else { add("\(key)-reverse", pattern: pattern, category: "physical", title: "反向线路不存在。", severity: .error) }
        }
        let alignment = line["alignmentDirection"]?.stringValue
        let stationOrder = line["stationOrderDirection"]?.stringValue
        if let alignment, let stationOrder, ["up", "down"].contains(alignment), ["up", "down"].contains(stationOrder) {
            let codes = line["stations"]?.arrayValue?.compactMap { $0.arrayValue?.first?.stringValue } ?? []
            if let a = codes.firstIndex(of: from), let b = codes.firstIndex(of: to),
               (WorkbenchDocument.isLoop(line) ? WorkbenchDocument.loopDirection(line, traversal: leg["loopTraversal"]) == 1 : a < b) != (alignment == stationOrder) {
                add("\(key)-alignment", pattern: pattern, category: "physical", title: "区段行进顺序与物理轨道方向不匹配。", severity: .error)
            }
        }
        let permitted = line["permittedTraversal"]?.stringValue
        if permitted == "forward" || permitted == "reverse" {
            let codes = line["stations"]?.arrayValue?.compactMap { $0.arrayValue?.first?.stringValue } ?? []
            if !WorkbenchDocument.isLoop(line), let a = codes.firstIndex(of: from), let b = codes.firstIndex(of: to), (permitted == "forward" ? a > b : a < b) {
                add("\(key)-direction", pattern: pattern, category: "physical", title: "区段顺序违反物理线路允许的方向。", severity: .error)
            }
        }
    }
    mutating func inspectConnectorList(_ value: JSONValue?) {
        guard let connectors = value?.arrayValue else {
            add("structure", category: "junctions", title: "connectors 不是列表。", severity: .error, evidence: false); return
        }
        var seen = Set<String>()
        for (index, connector) in connectors.enumerated() {
            let id = connector["id"]?.stringValue ?? ""
            if id.isEmpty || !seen.insert(id).inserted { add("connector-id-\(index)", category: "junctions", title: "连接记录 ID 为空或重复。", severity: .error, evidence: false) }
            guard inspectedConnectors.insert(connector).inserted else { continue }
            let key = "connector-\(id.isEmpty ? String(index) : id)"
            window(connector, pattern: "", key: key)
            sources(connector["sourceURLs"], pattern: "", key: key)
            for side in ["from", "to"] {
                let line = connector["\(side)LineID"]?.stringValue ?? ""
                let code = connector["\(side)StationCode"]?.stringValue ?? ""
                if line.isEmpty || code.isEmpty || (document.package != nil && document.stationCoordinate(lines[line], code: code) == nil) {
                    add("\(key)-\(side)", category: "junctions", title: "连接记录需要有效的物理线路和车站锚点。", severity: .error)
                }
            }
        }
    }
    mutating func inspectDay(_ pattern: JSONValue, day: String, connectors: [JSONValue]) {
        let id = pattern["id"]?.stringValue ?? ""
        guard (try? WorkbenchDocument.validateWindows(pattern, label: id)) != nil,
              (try? WorkbenchDocument.validateLegVariants(pattern)) != nil,
              let legs = pattern["legs"]?.arrayValue,
              legs.allSatisfy({ (try? WorkbenchDocument.validateWindows($0, label: id)) != nil }) else { return }
        guard ISODay.active(pattern, on: day) else { return }
        if let floor = document.catalog["coverageFrom"]?.stringValue, day < floor, pattern["validFrom"]?.stringValue == nil {
            add("unknown-status", pattern: id, category: "coverage", title: "当日服务存在性未知。", day: day); return
        }
        if let variants = pattern["legVariants"]?.arrayValue, !variants.contains(where: { ISODay.active($0, on: day) }) {
            let floor = document.catalog["coverageFrom"]?.stringValue
            let checked = document.catalog["checkedAt"]?.stringValue
            if let floor, let checked, day >= floor && day <= checked {
                add("period-gap", pattern: id, category: "variants", title: "声明证据范围内没有当日历史路径；不能解释为服务停用。", day: day)
            }
            return
        }
        if pattern["legVariants"]?.arrayValue?.first(where: { ISODay.active($0, on: day) })?["suspended"] == .bool(true) {
            return
        }
        let order = WorkbenchDocument.activeLegIndices(pattern, on: day)
        if order.isEmpty && legs.contains(where: { ISODay.active($0, on: day) }) {
            add("date-gap", pattern: id, category: "variants", title: "时间过滤移除中间区段，无法选择连续路径。", severity: .error, day: day)
        }
        for (a, b) in zip(order, order.dropFirst()) {
            let first = legs[a], second = legs[b]
            let firstCode = first["toStationCode"]?.stringValue ?? "", secondCode = second["fromStationCode"]?.stringValue ?? ""
            let firstCoords = coordinates(first), secondCoords = coordinates(second)
            if let reviewed = document.reviewedJunction(between: first, and: second, on: day, lines: lines,
                                                        firstCoordinates: firstCoords, secondCoordinates: secondCoords) {
                matchedJunctions.insert("\(id):\(a):\(b):\(reviewed)")
                continue
            }
            if firstCode == secondCode {
                if let last = firstCoords.last, let start = secondCoords.first, last != start {
                    add("gap-\(a)-\(b)", pattern: id, category: "junctions", title: "相同站码的来源折线端点不重合；显示直通关系不能填补几何缺口。", severity: .warning, day: day)
                }
                if first["lineID"] != second["lineID"] {
                    add("physical-proof-\(a)-\(b)", pattern: id, category: "junctions", title: "跨线路相同站码仍需经审查的物理连接证据。", day: day)
                }
            } else {
                let firstIDs = [first["lineID"]?.stringValue, first["reverseLineID"]?.stringValue].compactMap { $0 }
                let secondIDs = [second["lineID"]?.stringValue, second["reverseLineID"]?.stringValue].compactMap { $0 }
                let registered = connectors.contains { c in
                    guard (try? WorkbenchDocument.validateWindows(c, label: "connector")) != nil, ISODay.active(c, on: day) else { return false }
                    return (firstIDs.contains(c["fromLineID"]?.stringValue ?? "") && c["fromStationCode"]?.stringValue == firstCode && secondIDs.contains(c["toLineID"]?.stringValue ?? "") && c["toStationCode"]?.stringValue == secondCode)
                        || (firstIDs.contains(c["toLineID"]?.stringValue ?? "") && c["toStationCode"]?.stringValue == firstCode && secondIDs.contains(c["fromLineID"]?.stringValue ?? "") && c["fromStationCode"]?.stringValue == secondCode)
                }
                add("join-\(a)-\(b)", pattern: id, category: "junctions", title: registered ? "登记的直通显示连接不能证明物理轨道可通行。" : "区段站码不连续且没有当日登记的连接。", severity: registered ? .unknown : .error, day: day)
            }
        }
    }
}
