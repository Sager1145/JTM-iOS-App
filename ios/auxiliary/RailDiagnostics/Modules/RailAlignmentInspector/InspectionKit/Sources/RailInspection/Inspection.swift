import Foundation

public struct InspectionPoint: Codable, Sendable, Equatable {
    public var longitude: Double
    public var latitude: Double

    public init(longitude: Double, latitude: Double) {
        self.longitude = longitude
        self.latitude = latitude
    }
}

public struct InspectionInput: Codable, Sendable {
    public var id: String
    public var lineID: String
    public var lineName: String
    public var operatorName: String
    public var intervalIndex: Int
    public var fromStationID: String
    public var toStationID: String
    public var fromName: String
    public var toName: String
    public var source: [InspectionPoint]
    public var display: [InspectionPoint]
    public var hasDisplayOverride: Bool

    public init(id: String, lineID: String, lineName: String, operatorName: String,
                intervalIndex: Int, fromStationID: String, toStationID: String,
                fromName: String, toName: String, source: [InspectionPoint],
                display: [InspectionPoint], hasDisplayOverride: Bool) {
        self.id = id
        self.lineID = lineID
        self.lineName = lineName
        self.operatorName = operatorName
        self.intervalIndex = intervalIndex
        self.fromStationID = fromStationID
        self.toStationID = toStationID
        self.fromName = fromName
        self.toName = toName
        self.source = source
        self.display = display
        self.hasDisplayOverride = hasDisplayOverride
    }
}

public struct InspectionItem: Identifiable, Codable, Sendable {
    public var id: String
    public var lineID: String
    public var lineName: String
    public var operatorName: String
    public var intervalIndex: Int
    public var fromName: String
    public var toName: String
    public var priority: Int
    public var signals: [String]
    public var maxChordMetres: Double
    public var maxTurnDegrees: Double
    public var sourceVertexCount: Int
    public var displayVertexCount: Int
}

public struct InspectionPlan: Codable, Sendable {
    public var format = "jtm-japan-inspection-plan-v1"
    public var packageVersion: String
    public var generatedAt: Date
    public var items: [InspectionItem]
    public var lineCount: Int

    /// Every supplied interval is retained. Signals rank human review candidates;
    /// they never establish alignment with a basemap or an automatic verdict.
    /// Callers supply unique interval IDs. Item ordering is deterministic; the
    /// generation timestamp records when the plan was built.
    public static func build(inputs: [InspectionInput], packageVersion: String) -> InspectionPlan {
        let items: [InspectionItem] = inputs.map { (input: InspectionInput) -> InspectionItem in
            let source = GeometryScan(input.source)
            let display = GeometryScan(input.display)
            var signals: [String] = []
            var priority = 0
            let scans: [(String, GeometryScan)] = [("源几何", source), ("显示几何", display)]
            for (label, scan) in scans {
                if scan.invalidCount > 0 {
                    signals.append("\(label)有无效坐标，需人工检查数据")
                    priority += 100
                }
                if scan.validCount < 2 {
                    signals.append("\(label)数据不足，无法检查区间，待补充数据及底图证据")
                    priority += 90
                }
                if scan.validCount < 3 && scan.maxChord > 150 {
                    signals.append("\(label)顶点少于3个且直线弦长超过150米：仅为底图复核候选")
                    priority += 45
                }
                if scan.maxChord > 120 {
                    signals.append("\(label)相邻顶点间距超过120米：长间隙复核候选")
                    priority += 30
                }
                if scan.maxTurn > 45 {
                    signals.append("\(label)转角超过45°且两侧长度均至少15米：转角复核候选")
                    priority += 40
                }
                if scan.maxTurn > 150 {
                    signals.append("\(label)折返超过150°：复核候选，需底图证据判断")
                    priority += 60
                }
            }
            if input.hasDisplayOverride {
                signals.append("显示覆盖存在，需对照底图复核接缝")
                priority += 20
            }
            if signals.isEmpty {
                signals.append("未发现自动候选信号，仍需人工对照底图复核")
            }
            return InspectionItem(id: input.id, lineID: input.lineID, lineName: input.lineName,
                                  operatorName: input.operatorName, intervalIndex: input.intervalIndex,
                                  fromName: input.fromName, toName: input.toName, priority: priority,
                                  signals: signals, maxChordMetres: max(source.maxChord, display.maxChord),
                                  maxTurnDegrees: max(source.maxTurn, display.maxTurn),
                                  sourceVertexCount: input.source.count, displayVertexCount: input.display.count)
        }
        let sortedItems = items.sorted { lhs, rhs in
            lhs.priority == rhs.priority ? lhs.id < rhs.id : lhs.priority > rhs.priority
        }
        return .init(packageVersion: packageVersion, generatedAt: Date(), items: sortedItems,
                     lineCount: Set(inputs.map(\.lineID)).count)
    }
}

public enum ReviewVerdict: String, Codable, Sendable {
    case pending, aligned, needsRepair, insufficientBasemap, repaired

    public var title: String {
        switch self {
        case .pending: "待复核"
        case .aligned: "与底图对齐"
        case .needsRepair: "需要修复"
        case .insufficientBasemap: "底图证据不足"
        case .repaired: "已修复"
        }
    }
}

public struct InspectionReview: Codable, Sendable {
    public var itemID: String
    public var verdict: ReviewVerdict
    public var note: String
    public var reviewedAt: Date
    public var source: [InspectionPoint]
    public var display: [InspectionPoint]
    public var evidencePaths: [String]
    public var fromStationID: String?
    public var toStationID: String?
    public var renderedDisplay: [[InspectionPoint]]?
    public var renderContract: String?
    public var camera: [String: Double]?

    public init(itemID: String, verdict: ReviewVerdict, note: String, reviewedAt: Date,
                source: [InspectionPoint], display: [InspectionPoint], evidencePaths: [String],
                fromStationID: String? = nil, toStationID: String? = nil,
                renderedDisplay: [[InspectionPoint]]? = nil, renderContract: String? = nil,
                camera: [String: Double]? = nil) {
        self.itemID = itemID
        self.verdict = verdict
        self.note = note
        self.reviewedAt = reviewedAt
        self.source = source
        self.display = display
        self.evidencePaths = evidencePaths
        self.fromStationID = fromStationID
        self.toStationID = toStationID
        self.renderedDisplay = renderedDisplay
        self.renderContract = renderContract
        self.camera = camera
    }

    /// A review follows the exact geometry observed, rather than a package-wide
    /// stamp. A coordinate edit or endpoint identity change makes it stale.
    /// Legacy reviews without endpoint IDs are stale. Callers also compare
    /// renderedDisplay/renderContract against their actual rendering pipeline.
    public func isCurrent(for input: InspectionInput) -> Bool {
        itemID == input.id && fromStationID == input.fromStationID
            && toStationID == input.toStationID && source == input.source && display == input.display
    }
}

private struct GeometryScan {
    var invalidCount = 0
    var validCount = 0
    var maxChord = 0.0
    var maxTurn = 0.0

    init(_ points: [InspectionPoint]) {
        var previous: InspectionPoint?
        var beforePrevious: InspectionPoint?
        var previousLength = 0.0
        for point in points {
            guard Self.isValid(point) else {
                invalidCount += 1
                // Invalid vertices break adjacency, so no invented bridge is
                // measured between their valid neighbors.
                previous = nil
                beforePrevious = nil
                previousLength = 0
                continue
            }
            validCount += 1
            if let previous {
                let length = Self.distance(previous, point)
                maxChord = max(maxChord, length)
                if let beforePrevious, previousLength >= 15, length >= 15 {
                    let incoming = Self.bearing(previous, beforePrevious) + .pi
                    let outgoing = Self.bearing(previous, point)
                    let turn = acos(min(1, max(-1, cos(outgoing - incoming)))) * 180 / .pi
                    maxTurn = max(maxTurn, turn)
                }
                previousLength = length
            }
            beforePrevious = previous
            previous = point
        }
    }

    private static func isValid(_ point: InspectionPoint) -> Bool {
        point.longitude.isFinite && point.latitude.isFinite
            && (-180...180).contains(point.longitude) && (-90...90).contains(point.latitude)
    }

    private static func distance(_ a: InspectionPoint, _ b: InspectionPoint) -> Double {
        let latitudeA = a.latitude * .pi / 180
        let latitudeB = b.latitude * .pi / 180
        let deltaLatitude = latitudeB - latitudeA
        let deltaLongitude = (b.longitude - a.longitude) * .pi / 180
        let haversine = pow(sin(deltaLatitude / 2), 2)
            + cos(latitudeA) * cos(latitudeB) * pow(sin(deltaLongitude / 2), 2)
        return 6_371_008.8 * 2 * asin(sqrt(min(1, max(0, haversine))))
    }

    private static func bearing(_ a: InspectionPoint, _ b: InspectionPoint) -> Double {
        let latitudeA = a.latitude * .pi / 180
        let latitudeB = b.latitude * .pi / 180
        let deltaLongitude = (b.longitude - a.longitude) * .pi / 180
        return atan2(sin(deltaLongitude) * cos(latitudeB),
                     cos(latitudeA) * sin(latitudeB)
                        - sin(latitudeA) * cos(latitudeB) * cos(deltaLongitude))
    }
}
