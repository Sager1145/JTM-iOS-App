import Foundation

/// One native snapshot scale and viewport; all dimensions are points at 1×.
public struct DiagnosticCaptureSettings: Codable, Equatable, Sendable {
    public enum Appearance: String, Codable, Sendable { case light, dark }
    public enum BasemapStyle: String, Codable, Sendable { case standard, imagery }
    public enum OutputMode: String, Codable, CaseIterable, Sendable { case basemap, display, smooth }
    public var zoom: Double
    public var width: Int
    public var height: Int
    public var appearance: Appearance
    public var basemapStyle: BasemapStyle
    public var outputModes: [OutputMode]

    public init(zoom: Double = 17, width: Int = 1024, height: Int = 768,
                appearance: Appearance = .light, basemapStyle: BasemapStyle = .standard,
                outputModes: [OutputMode] = OutputMode.allCases) {
        self.zoom = zoom; self.width = width; self.height = height
        self.appearance = appearance; self.basemapStyle = basemapStyle; self.outputModes = outputModes
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case zoom, width, height, appearance, basemapStyle, outputModes }
    private struct InputKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    public init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: InputKey.self)
        let supported = Set(CodingKeys.allCases.map(\.rawValue))
        let unknown = raw.allKeys.map(\.stringValue).filter { !supported.contains($0) }.sorted()
        guard unknown.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Unsupported capture settings: \(unknown.joined(separator: ", "))."))
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        for key in CodingKeys.allCases where values.contains(key) {
            if try values.decodeNil(forKey: key) {
                throw DecodingError.valueNotFound(String.self, .init(codingPath: decoder.codingPath + [key],
                    debugDescription: "Capture setting \(key.rawValue) cannot be null; omit it to use the default."))
            }
        }
        self.init(zoom: try values.decodeIfPresent(Double.self, forKey: .zoom) ?? 17,
                  width: try values.decodeIfPresent(Int.self, forKey: .width) ?? 1024,
                  height: try values.decodeIfPresent(Int.self, forKey: .height) ?? 768,
                  appearance: try values.decodeIfPresent(Appearance.self, forKey: .appearance) ?? .light,
                  basemapStyle: try values.decodeIfPresent(BasemapStyle.self, forKey: .basemapStyle) ?? .standard,
                  outputModes: try values.decodeIfPresent([OutputMode].self, forKey: .outputModes) ?? OutputMode.allCases)
    }

    public func validate() throws {
        guard zoom.isFinite, (10...20).contains(zoom) else {
            throw DiagnosticError.invalidRequest("Capture zoom must be finite and within 10...20 (256-point tile convention).")
        }
        guard (256...4096).contains(width), (256...4096).contains(height), width * height <= 8_388_608 else {
            throw DiagnosticError.invalidRequest("Capture viewport must be 256...4096 points per side and at most 8,388,608 pixels at 1×.")
        }
        guard !outputModes.isEmpty, Set(outputModes).count == outputModes.count else {
            throw DiagnosticError.invalidRequest("Capture output modes must be nonempty and unique: basemap, display, smooth.")
        }
    }

    /// Conservative spacing for overlapping axis-aligned Mercator views. The
    /// latitude bound includes the interior of each great-circle segment, not
    /// just its endpoints. A 20% margin retains coverage as scale varies.
    public func coverageSpacingMetres(inputs: [InspectionInput]) throws -> Double {
        try validate()
        var latitudeBound = 0.0
        for input in inputs where input.display.allSatisfy(BatchGeometry.isValid) {
            for point in input.display { latitudeBound = max(latitudeBound, abs(point.latitude)) }
            for (a, b) in zip(input.display, input.display.dropFirst()) {
                let angularDegrees = BatchGeometry.distance(a, b) / BatchGeometry.radius * 180 / .pi
                latitudeBound = max(latitudeBound, min(abs(a.latitude), abs(b.latitude)) + angularDegrees)
            }
        }
        let latitude = min(85.05112878, latitudeBound) * .pi / 180
        let metresPerPoint = 40_075_016.68557849 * cos(latitude) / (256 * pow(2, zoom))
        return min(350, Double(min(width, height)) * metresPerPoint * 0.4)
    }
}

/// Local, bounded invocation shared by the unified native workspaces.
public struct DiagnosticRequest: Codable, Equatable, Sendable {
    public enum Workspace: String, Codable, Sendable { case alignment, route, through }
    public enum Action: String, Codable, Sendable { case prepare, capture, retryFailures, solve, inspect }
    public var schemaVersion: Int = 1
    public var requestID: String
    public var workspace: Workspace
    public var action: Action
    public var sessionDirectory: String
    public var lineID: String?
    public var intervalIndices: [Int]?
    public var stationIDs: [String]?
    /// Alignment: optional compact package; route: required journey JSON.
    public var inputPath: String?
    public var patternID: String?
    public var reviewDay: String?
    public var alignmentEvidenceDirectory: String?
    /// Exact IDs from the scoped batch plan; omission selects every viewpoint.
    public var viewpointIDs: [String]?
    public var captureLimit: Int?
    public var evidencePaths: [String]?
    public var captureSettings: DiagnosticCaptureSettings?
    public var normalizedCaptureSettings: DiagnosticCaptureSettings { captureSettings ?? .init() }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, requestID, workspace, action, sessionDirectory, lineID, intervalIndices, stationIDs
        case inputPath, patternID, reviewDay, alignmentEvidenceDirectory, captureLimit, viewpointIDs, evidencePaths, captureSettings
    }
    private struct InputKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: InputKey.self)
        let supported = Set(CodingKeys.allCases.map(\.rawValue))
        let unknown = raw.allKeys.map(\.stringValue).filter { !supported.contains($0) }.sorted()
        guard unknown.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Unsupported diagnostic request fields: \(unknown.joined(separator: ", "))."))
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if values.contains(.viewpointIDs), try values.decodeNil(forKey: .viewpointIDs) {
            throw DecodingError.valueNotFound([String].self, .init(codingPath: decoder.codingPath + [CodingKeys.viewpointIDs],
                debugDescription: "Viewpoint IDs cannot be null; omit the field to select all scoped viewpoints."))
        }
        self.init(requestID: try values.decode(String.self, forKey: .requestID),
                  workspace: try values.decode(Workspace.self, forKey: .workspace),
                  action: try values.decode(Action.self, forKey: .action),
                  sessionDirectory: try values.decode(String.self, forKey: .sessionDirectory),
                  lineID: try values.decodeIfPresent(String.self, forKey: .lineID),
                  intervalIndices: try values.decodeIfPresent([Int].self, forKey: .intervalIndices),
                  stationIDs: try values.decodeIfPresent([String].self, forKey: .stationIDs),
                  inputPath: try values.decodeIfPresent(String.self, forKey: .inputPath),
                  patternID: try values.decodeIfPresent(String.self, forKey: .patternID),
                  reviewDay: try values.decodeIfPresent(String.self, forKey: .reviewDay),
                  alignmentEvidenceDirectory: try values.decodeIfPresent(String.self, forKey: .alignmentEvidenceDirectory),
                  captureLimit: try values.decodeIfPresent(Int.self, forKey: .captureLimit),
                  viewpointIDs: try values.decodeIfPresent([String].self, forKey: .viewpointIDs),
                  evidencePaths: try values.decodeIfPresent([String].self, forKey: .evidencePaths),
                  captureSettings: try values.decodeIfPresent(DiagnosticCaptureSettings.self, forKey: .captureSettings))
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
    }

    public init(requestID: String, workspace: Workspace, action: Action, sessionDirectory: String,
                lineID: String? = nil, intervalIndices: [Int]? = nil, stationIDs: [String]? = nil,
                inputPath: String? = nil, patternID: String? = nil, reviewDay: String? = nil,
                alignmentEvidenceDirectory: String? = nil, captureLimit: Int? = nil, viewpointIDs: [String]? = nil,
                evidencePaths: [String]? = nil, captureSettings: DiagnosticCaptureSettings? = nil) {
        self.requestID = requestID; self.workspace = workspace; self.action = action
        self.sessionDirectory = sessionDirectory; self.lineID = lineID; self.intervalIndices = intervalIndices
        self.stationIDs = stationIDs; self.inputPath = inputPath; self.patternID = patternID; self.reviewDay = reviewDay
        self.alignmentEvidenceDirectory = alignmentEvidenceDirectory; self.captureLimit = captureLimit
        self.evidencePaths = evidencePaths; self.captureSettings = captureSettings; self.viewpointIDs = viewpointIDs
    }

    public func validate() throws {
        try normalizedCaptureSettings.validate()
        if captureSettings != nil, workspace != .alignment {
            throw DiagnosticError.invalidRequest("Capture settings apply only to alignment requests.")
        }
        guard schemaVersion == 1, !requestID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (sessionDirectory as NSString).isAbsolutePath else { throw DiagnosticError.invalidRequest("Version, request ID and absolute session directory are required.") }
        for path in [inputPath, alignmentEvidenceDirectory].compactMap({ $0 }) + (evidencePaths ?? []) {
            guard (path as NSString).isAbsolutePath else { throw DiagnosticError.invalidRequest("Paths must be absolute: \(path)") }
        }
        if let indices = intervalIndices {
            guard !indices.isEmpty, indices.allSatisfy({ $0 >= 0 }), Set(indices).count == indices.count else {
                throw DiagnosticError.invalidRequest("Interval indices must be unique, nonnegative and nonempty.")
            }
        }
        if let ids = stationIDs, ids.isEmpty || ids.contains(where: { $0.isEmpty }) {
            throw DiagnosticError.invalidRequest("Station scope must be nonempty.")
        }
        if let ids = viewpointIDs {
            guard workspace == .alignment, !ids.isEmpty, Set(ids).count == ids.count,
                  ids.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                throw DiagnosticError.invalidRequest("Viewpoint IDs must be nonempty, unique exact IDs on an alignment request.")
            }
        }
        if let captureLimit, !(1...1000).contains(captureLimit) { throw DiagnosticError.invalidRequest("Capture limit must be 1...1000.") }
        switch workspace {
        case .alignment:
            guard let lineID, !lineID.isEmpty, [.prepare, .capture, .retryFailures].contains(action) else {
                throw DiagnosticError.invalidRequest("Alignment requires one exact line ID and prepare/capture/retryFailures.")
            }
        case .route:
            guard inputPath != nil, [.prepare, .solve].contains(action) else { throw DiagnosticError.invalidRequest("Route requires inputPath and prepare/solve.") }
        case .through:
            guard inputPath == nil else {
                throw DiagnosticError.invalidRequest("Through requests do not accept inputPath.")
            }
            guard let patternID, !patternID.isEmpty, let reviewDay,
                  Self.validDay(reviewDay), [.prepare, .inspect].contains(action) else {
                throw DiagnosticError.invalidRequest("Through requires an exact pattern ID, Gregorian ISO day and prepare/inspect.")
            }
        }
    }

    public func alignmentInputs(_ inputs: [InspectionInput]) throws -> [InspectionInput] {
        try validate()
        let line = inputs.filter { $0.lineID == lineID }.sorted { $0.intervalIndex < $1.intervalIndex }
        guard !line.isEmpty else { throw DiagnosticError.invalidRequest("Unknown line ID: \(lineID ?? "")") }
        if let indices = intervalIndices, !Set(indices).isSubset(of: Set(line.map(\.intervalIndex))) {
            throw DiagnosticError.invalidRequest("Unknown interval index; no wider fallback is allowed.")
        }
        if let stationIDs, !Set(stationIDs).isSubset(of: Set(line.flatMap { [$0.fromStationID, $0.toStationID] })) {
            throw DiagnosticError.invalidRequest("Unknown station ID on the exact line.")
        }
        let selected = line.filter { input in
            (intervalIndices == nil || intervalIndices!.contains(input.intervalIndex)) &&
            (stationIDs == nil || stationIDs!.contains(input.fromStationID) || stationIDs!.contains(input.toStationID))
        }
        guard !selected.isEmpty else { throw DiagnosticError.invalidRequest("The intersection of the requested scopes is empty.") }
        return selected
    }

    /// Admit exact IDs against the actual scoped plan, including retained ordinals.
    public func alignmentViewpointIDs(in plan: BatchInspectionPlan, inputs: [InspectionInput]) throws -> Set<String>? {
        try validate()
        guard let viewpointIDs else { return nil }
        let selected = Set(viewpointIDs)
        let owners = Set(try alignmentInputs(inputs).map(\.id))
        let items = plan.items.filter { owners.contains($0.itemID) }
        guard selected.isSubset(of: Set(items.flatMap(\.viewpoints).map(\.id))) else {
            throw DiagnosticError.invalidRequest("Unknown or out-of-scope viewpoint ID; no wider fallback is allowed.")
        }
        return selected
    }

    private static func validDay(_ text: String) -> Bool {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return text.count == 10 && formatter.date(from: text).map { formatter.string(from: $0) == text } == true
    }
}

public enum DiagnosticError: LocalizedError {
    case invalidRequest(String), changedRequest
    public var errorDescription: String? {
        switch self {
        case .invalidRequest(let reason): reason
        case .changedRequest: "This session belongs to a different request. Use a new session directory; retain the existing evidence."
        }
    }
}

public struct DiagnosticCandidate: Codable, Equatable, Sendable, Identifiable {
    public struct Corner: Codable, Equatable, Sendable {
        public var displayVertexIndex: Int
        public var coordinate: InspectionPoint
        public var turnDegrees: Double
        public var incomingMetres: Double
        public var outgoingMetres: Double
    }

    public var id: String
    public var category: String
    public var itemIDs: [String]
    public var stationID: String?
    public var measuredMetres: Double?
    public var corner: Corner? = nil
    public var state = "pendingReview"
    public var note: String

    /// No metric here can establish connectivity or an Apple platform offset.
    public static func tasks(selected: [InspectionInput], context: [InspectionInput]) -> [Self] {
        var result: [Self] = []
        let byIndex = Dictionary(context.filter { $0.lineID == selected.first?.lineID }.map { ($0.intervalIndex, $0) }, uniquingKeysWith: { first, _ in first })
        for input in selected {
            for (category, note) in [
                ("lineOffset", "Compare own track with retained native basemap evidence."),
                ("stationApproach", "Review station approach, intended connections and false joins; proximity is not physical proof."),
                ("disconnectedParts", "Review visible breaks and clipping separately from physical connectivity.")
            ] {
                result.append(.init(id: "\(input.id)/\(category)", category: category, itemIDs: [input.id], note: note))
            }
            if input.display.count >= 3 {
                for index in 1..<(input.display.count - 1) {
                    guard let corner = displayCorner(at: index, in: input.display) else { continue }
                    result.append(.init(id: "\(input.id)/displayVertex/\(index)/sharpTurn", category: "sharpTurn",
                        itemIDs: [input.id], corner: corner,
                        note: "Sharp-turn candidate for \(input.id) at own display vertex \(index), [\(corner.coordinate.longitude), \(corner.coordinate.latitude)]: \(corner.turnDegrees)°; incoming \(corner.incomingMetres) m; outgoing \(corner.outgoingMetres) m. This is a review candidate, not a finding of wrong geometry or physical proof. Compare the owning passenger corridor and retained native evidence before deciding."))
                }
            }
            for station in [input.fromStationID, input.toStationID] {
                let id = "\(input.lineID)/station/\(station)"
                if !result.contains(where: { $0.id == id }) {
                    result.append(.init(id: id, category: "stationOffset", itemIDs: [input.id], stationID: station,
                                        note: "Blue passenger platforms define this line's station extent; purple transfer passages and yards are excluded."))
                }
            }
            for leftIndex in [input.intervalIndex - 1, input.intervalIndex] {
                guard let left = byIndex[leftIndex], let right = byIndex[leftIndex + 1] else { continue }
                let id = "\(left.id)/seam"
                guard !result.contains(where: { $0.id == id }) else { continue }
                let distance: Double?
                if let end = left.display.last, let start = right.display.first { distance = metres(end, start) }
                else { distance = nil }
                result.append(.init(id: id, category: "intervalSeam", itemIDs: [left.id, right.id],
                                    stationID: left.toStationID, measuredMetres: distance,
                                    note: "Adjacent display endpoints only. Zero distance does not prove rendered continuity, track identity or physical connection; missing geometry stays unknown."))
            }
        }
        return result
    }

    private static func displayCorner(at index: Int, in points: [InspectionPoint]) -> Corner? {
        let a = points[index - 1], b = points[index], c = points[index + 1]
        guard let incoming = metres(a, b), let outgoing = metres(b, c),
              incoming.isFinite, outgoing.isFinite, incoming > 0, outgoing > 0 else { return nil }
        // Local display deflection, with both legs projected at the corner's
        // latitude. This measures an angle; it does not establish track identity.
        let longitudeScale = cos(b.latitude * .pi / 180)
        let incomingX = (b.longitude - a.longitude) * longitudeScale
        let incomingY = b.latitude - a.latitude
        let outgoingX = (c.longitude - b.longitude) * longitudeScale
        let outgoingY = c.latitude - b.latitude
        let incomingLength = hypot(incomingX, incomingY), outgoingLength = hypot(outgoingX, outgoingY)
        guard incomingLength.isFinite, outgoingLength.isFinite,
              incomingLength > 0, outgoingLength > 0 else { return nil }
        let cosine = incomingX / incomingLength * (outgoingX / outgoingLength)
            + incomingY / incomingLength * (outgoingY / outgoingLength)
        guard cosine.isFinite else { return nil }
        let degrees = acos(min(1, max(-1, cosine))) * 180 / .pi
        guard degrees.isFinite, degrees >= 20 else { return nil }
        return .init(displayVertexIndex: index, coordinate: b, turnDegrees: degrees,
                     incomingMetres: incoming, outgoingMetres: outgoing)
    }

    private static func metres(_ a: InspectionPoint, _ b: InspectionPoint) -> Double? {
        guard [a.longitude, b.longitude, a.latitude, b.latitude].allSatisfy(\.isFinite),
              abs(a.latitude) <= 90, abs(b.latitude) <= 90, abs(a.longitude) <= 180, abs(b.longitude) <= 180 else { return nil }
        let radians = Double.pi / 180
        let lat = (b.latitude - a.latitude) * radians, lon = (b.longitude - a.longitude) * radians
        let h = pow(sin(lat / 2), 2) + cos(a.latitude * radians) * cos(b.latitude * radians) * pow(sin(lon / 2), 2)
        return 6_371_000 * 2 * asin(sqrt(min(1, max(0, h))))
    }
}
