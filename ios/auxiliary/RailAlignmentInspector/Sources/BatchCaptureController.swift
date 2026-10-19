import CryptoKit
import Foundation
@preconcurrency import MapKit
import Observation
import RailCore
import RailInspection
import UIKit

/// Product evidence collection, with one snapshot in flight. Capture status is
/// deliberately separate from the inspector's human review verdicts.
@MainActor @Observable
final class BatchCaptureController {
    let outputURL: URL
    let captureAdmission: InspectionCaptureAdmission
    private(set) var plan: BatchInspectionPlan?
    private(set) var checkpoint: BatchInspectionCheckpoint?
    private(set) var isRunning = false
    private(set) var currentItemID: String?
    private(set) var currentViewpointID: String?
    private(set) var lastError: String?
    private(set) var status = "尚未生成批量计划"
    private(set) var totalCount = 0
    private(set) var completedCount = 0
    private(set) var failedCount = 0
    private(set) var pendingCount = 0
    private(set) var unavailableCount = 0
    private(set) var captureSettings = DiagnosticCaptureSettings()
    /// Observers can refresh evidence indexes without treating status updates or
    /// report-only flushes as new persisted capture evidence.
    private(set) var evidenceRevision = 0

    @ObservationIgnored private var inputs: [String: InspectionInput] = [:]
    @ObservationIgnored private var lines: [String: CompactPackage.Line] = [:]
    @ObservationIgnored private var topology: [String: DisplayParts.LineTopology] = [:]
    @ObservationIgnored private var reference: ReferenceTrack?
    @ObservationIgnored private var renderedLine: BatchCaptureGeometry.RenderedLine?
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var lineDependencies: [String: String] = [:]
    @ObservationIgnored private var referenceDependencies: [String: String] = [:]
    @ObservationIgnored private var receipts: [String: CaptureReceipt] = [:]
    @ObservationIgnored private var planDigest = ""
    @ObservationIgnored private var preservesBroaderPlan = false
    @ObservationIgnored private var intervalDependencies: [String: String] = [:]
    @ObservationIgnored private var directoryIndices: [String: Int] = [:]
    @ObservationIgnored private var capturesSinceReport = 0
    @ObservationIgnored private var candidates: [String: CandidateSummary] = [:]

    private struct FileReceipt: Codable {
        let name: String
        let byteCount: Int
        let sha256: String
    }
    private struct CaptureReceipt: Codable {
        let directory: String
        let files: [FileReceipt]
    }
    /// Exact geometries live in the immutable plan file once. Only small
    /// progress rows and dependency digests are atomically rewritten per view.
    private struct SavedCheckpoint: Codable {
        var format = "jtm-native-batch-capture-v1"
        let planDigest: String
        let capturedCount: Int
        let failedCount: Int
        let pendingCount: Int
        let unavailableIntervalCount: Int
    }
    private struct SavedCapture: Codable {
        var format = "jtm-native-batch-view-state-v1"
        let planDigest: String
        let progress: BatchInspectionProgress
        let intervalDependency: String
        let lineDependency: String
        let referenceDependency: String
        let receipt: CaptureReceipt?
        let candidate: CandidateSummary?
    }
    private struct CandidateSummary: Codable {
        let smoothToDisplayMaximumMetres: Double?
        let displayToDecodedDisplayMaximumMetres: Double?
        let cappedSampling: Bool
    }
    private enum CaptureError: LocalizedError {
        case duplicateIDs, missingLine, invalidGeometry, noVisibleGeometry, unsafeEvidenceName, invalidReceipt, incompatibleEvidence
        var errorDescription: String? {
            switch self {
            case .incompatibleEvidence: "所选范围的原始证据依赖或收据已变化。保留原目录并使用新的证据目录。"
            case .duplicateIDs: "批量输入区间 ID 重复。"
            case .missingLine: "批量目标对应的完整线路缺失。"
            case .invalidGeometry: "完整显示线路含无效坐标，无法生成平滑证据。"
            case .noVisibleGeometry: "目标视点中没有可用的显示和平滑中心线。"
            case .unsafeEvidenceName: "证据文件名不符合固定输出格式。"
            case .invalidReceipt: "已保存证据不存在或内容改变，将重新采集。"
            }
        }
    }

    init(outputURL: URL? = nil, captureAdmission: InspectionCaptureAdmission = InspectionCaptureAdmission()) {
        self.captureAdmission = captureAdmission
        self.outputURL = outputURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RailAlignmentInspector/BatchEvidence", isDirectory: true)
    }

    func configure(inputs: [InspectionInput], linesByID: [String: CompactPackage.Line],
                   topology: [String: DisplayParts.LineTopology], packageVersion: String,
                   reference: ReferenceTrack? = nil, protectedScope: Set<String> = [],
                   settings: DiagnosticCaptureSettings = .init()) throws {
        guard !isRunning else { return }
        lastError = nil
        guard Set(inputs.map(\.id)).count == inputs.count else { throw CaptureError.duplicateIDs }
        try settings.validate()
        var newPlan = try BatchInspectionPlan.build(inputs: inputs, packageVersion: packageVersion, settings: settings)
        var slotPlan = newPlan
        let existingPlanURL = outputURL.appendingPathComponent("plan.json")
        let retainsExistingPlan = FileManager.default.fileExists(atPath: existingPlanURL.path)
        if retainsExistingPlan {
            guard let previous = try? JSONDecoder().decode(BatchInspectionPlan.self, from: Data(contentsOf: existingPlanURL)) else {
                throw CaptureError.incompatibleEvidence
            }
            do { newPlan = try previous.scoped(to: inputs, packageVersion: packageVersion, settings: settings) }
            catch { throw CaptureError.incompatibleEvidence }
            slotPlan = previous
        } else if ["captures", "checkpoint.json"].contains(where: {
            FileManager.default.fileExists(atPath: outputURL.appendingPathComponent($0).path)
        }) {
            throw CaptureError.incompatibleEvidence
        }
        let planData = try Self.encoder.encode(newPlan)
        let digest = Self.digest(planData)
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        var restored = BatchInspectionCheckpoint(plan: newPlan)
        self.inputs = Dictionary(uniqueKeysWithValues: inputs.map { ($0.id, $0) })
        self.lines = linesByID
        self.topology = topology
        self.reference = reference
        self.captureSettings = settings
        preservesBroaderPlan = slotPlan.items.count > newPlan.items.count
        renderedLine = nil
        lineDependencies = [:]
        referenceDependencies = [:]
        receipts = [:]
        candidates = [:]
        intervalDependencies = [:]
        directoryIndices = slotPlan.captureDirectoryIndices
        for item in newPlan.items { intervalDependencies[item.itemID] = Self.digest(try Self.encoder.encode(item.identity)) }
        for lineID in Set(inputs.map(\.lineID)) {
            guard let line = linesByID[lineID] else { continue }
            let display = DisplayParts.parts(for: line, topology: topology[lineID] ?? .init())
            guard Self.valid(display) else { continue }
            lineDependencies[lineID] = BatchCaptureGeometry.dependency(line: line, display: display, settings: settings)
        }
        for input in inputs {
            referenceDependencies[input.id] = BatchCaptureGeometry.referenceDependency(scopedReference(for: input))
        }
        var validIdentityPlans: [String: Bool] = [:]
        var restoredRows: [BatchInspectionProgress] = []
        for row in restored.progress {
            guard let input = self.inputs[row.itemID] else { continue }
            let stateURL = outputURL.appendingPathComponent(captureDirectory(inputID: input.id, pointOrdinal: row.viewpoint.pointOrdinal))
                .appendingPathComponent("capture-state.json")
            guard let data = try? Data(contentsOf: stateURL), let saved = try? JSONDecoder().decode(SavedCapture.self, from: data),
                  saved.format == "jtm-native-batch-view-state-v1", saved.progress.viewpoint == row.viewpoint,
                  saved.intervalDependency == intervalDependencies[input.id],
                  lineDependencies[input.lineID] != nil, saved.lineDependency == lineDependencies[input.lineID],
                  saved.referenceDependency == referenceDependencies[input.id] else {
                if protectedScope.contains(input.id), FileManager.default.fileExists(atPath: stateURL.path) { throw CaptureError.incompatibleEvidence }
                continue
            }
            if validIdentityPlans[saved.planDigest] == nil {
                validIdentityPlans[saved.planDigest] = Self.validDigest(saved.planDigest)
                    && (try? Self.fileDigest(identityPlanURL(saved.planDigest))) == saved.planDigest
            }
            guard validIdentityPlans[saved.planDigest] == true else {
                if protectedScope.contains(input.id) { throw CaptureError.incompatibleEvidence }
                continue
            }
            receipts[row.viewpointID] = saved.receipt
            if saved.progress.status != .captured || validReceipt(for: saved.progress) {
                restoredRows.append(saved.progress)
                candidates[row.viewpointID] = saved.candidate
            } else {
                if protectedScope.contains(input.id), saved.progress.status == .captured { throw CaptureError.incompatibleEvidence }
                receipts.removeValue(forKey: row.viewpointID)
            }
        }
        restored.record(progress: restoredRows)
        plan = newPlan
        totalCount = newPlan.items.reduce(0) { $0 + $1.viewpoints.count }
        unavailableCount = newPlan.items.filter { $0.geometryStatus != .available }.count
        checkpoint = restored
        refreshCounts()
        planDigest = digest
        // Retain prior immutable identity files: existing evidence may still
        // refer to them. No per-view copy of the complete plan is written.
        if (try? Self.fileDigest(identityPlanURL(digest))) != digest {
            try planData.write(to: identityPlanURL(digest), options: .atomic)
        }
        if !retainsExistingPlan { try planData.write(to: existingPlanURL, options: .atomic) }
        try persist(writeReport: true)
        evidenceRevision &+= 1
        status = "全量视点 \(totalCount) · 已采集 \(completedCount) · 不可用区间 \(unavailableCount)"
    }

    /// Default scope is every pending target. Failures remain recorded until an
    /// explicit retry; pressing Resume never creates an unbounded retry loop.
    func start(scope: Set<String>? = nil, limit: Int? = nil, viewpointIDs: Set<String>? = nil) {
        guard !isRunning, let plan, checkpoint != nil else { return }
        let statuses = Dictionary((checkpoint?.progress ?? []).map { ($0.viewpointID, $0.status) }, uniquingKeysWith: { first, _ in first })
        let targets = plan.viewpoints.filter {
            (scope == nil || scope!.contains($0.itemID)) && (viewpointIDs == nil || viewpointIDs!.contains($0.id)) && statuses[$0.id] == .pending
        }
        let selected = limit.map { Array(targets.prefix(max(0, $0))) } ?? targets
        guard !selected.isEmpty else { status = "所选范围没有待采集视点"; return }
        guard let lease = captureAdmission.begin(.batch) else { return }
        isRunning = true
        lastError = nil
        runTask = Task { @MainActor [weak self, captureAdmission] in
            defer { captureAdmission.finish(lease) }
            guard let self else { return }
            defer {
                self.isRunning = false
                self.currentItemID = nil
                self.currentViewpointID = nil
                self.renderedLine = nil
                self.runTask = nil
            }
            for viewpoint in selected {
                if Task.isCancelled { break }
                self.currentItemID = viewpoint.itemID
                self.currentViewpointID = viewpoint.id
                self.status = "采集 \(self.completedCount + 1)/\(self.totalCount) · \(viewpoint.itemID) · 视点 \(viewpoint.pointOrdinal + 1)"
                do {
                    try await self.capture(viewpoint)
                } catch {
                    if Task.isCancelled || error is CancellationError { break }
                    self.lastError = error.localizedDescription
                    self.checkpoint?.record(viewpoint: viewpoint, status: .failed, note: error.localizedDescription)
                    self.refreshCounts()
                    do { try self.persist(viewpoint: viewpoint) }
                    catch {
                        self.lastError = "保存检查点失败：\(error.localizedDescription)"
                        break
                    }
                }
            }
            do { try self.persist(writeReport: true) }
            catch { self.lastError = "保存报告失败：\(error.localizedDescription)" }
            self.status = Task.isCancelled ? "批量采集已暂停" : "采集结束 · 已保存 \(self.completedCount) · 失败 \(self.failedCount) · 待采集 \(self.pendingCount)"
        }
    }

    func pause() {
        runTask?.cancel()
        status = "正在暂停；不会开始下一个快照"
    }

    func retryFailed(scope: Set<String>? = nil, limit: Int? = nil, viewpointIDs: Set<String>? = nil) {
        guard !isRunning, let rows = checkpoint?.progress else { return }
        let failures = rows.filter { $0.status == .failed && (scope == nil || scope!.contains($0.itemID)) && (viewpointIDs == nil || viewpointIDs!.contains($0.viewpointID)) }
        let selected = limit.map { Array(failures.prefix(max(0, $0))) } ?? failures
        for row in selected {
            let original = outputURL.appendingPathComponent(captureDirectory(inputID: row.itemID, pointOrdinal: row.viewpoint.pointOrdinal), isDirectory: true)
            if FileManager.default.fileExists(atPath: original.path) {
                do {
                    let history = outputURL.appendingPathComponent("retry-history", isDirectory: true)
                    try FileManager.default.createDirectory(at: history, withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: original, to: history.appendingPathComponent(UUID().uuidString, isDirectory: true))
                } catch { lastError = "保留失败证据失败：\(error.localizedDescription)"; return }
            }
            checkpoint?.record(viewpoint: row.viewpoint, status: .pending, note: "用户请求重试")
            refreshCounts()
            do { try persist(viewpoint: row.viewpoint) }
            catch { lastError = error.localizedDescription; return }
        }
        do { try persist(); start(scope: scope, viewpointIDs: Set(selected.map(\.viewpointID))) }
        catch { lastError = error.localizedDescription }
    }

    struct ScopeSummary {
        let progress: [BatchInspectionProgress]
        let capturedCount: Int
        let failedCount: Int
        let pendingCount: Int
        let unavailableCount: Int
        let incomplete: Bool
        var totalCount: Int { progress.count }
    }

    /// The exact same scope determines agent counts and completion state.
    func scopedSummary(scope: Set<String>, viewpointIDs: Set<String>? = nil) -> ScopeSummary {
        let rows = (checkpoint?.progress ?? []).filter { scope.contains($0.itemID) && (viewpointIDs == nil || viewpointIDs!.contains($0.viewpointID)) }
        var captured = 0, failed = 0, pending = 0
        for row in rows {
            switch row.status {
            case .captured: captured += 1
            case .failed: failed += 1
            case .pending: pending += 1
            }
        }
        let unavailable = (plan?.items ?? []).filter { scope.contains($0.itemID) && $0.geometryStatus != .available }.count
        return ScopeSummary(progress: rows, capturedCount: captured, failedCount: failed, pendingCount: pending,
            unavailableCount: unavailable, incomplete: plan == nil || rows.isEmpty || unavailable > 0 || captured != rows.count)
    }

    func reportData() throws -> Data {
        let rows = checkpoint?.progress ?? []
        let rowsByItem = Dictionary(grouping: rows, by: \.itemID)
        let intervals = (plan?.items ?? []).map { item -> [String: Any] in
            let captures = rowsByItem[item.itemID] ?? []
            let summaries = captures.compactMap { candidates[$0.viewpointID] }
            let input = inputs[item.itemID]
            return ["itemID": item.itemID, "lineID": input?.lineID ?? "", "lineName": input?.lineName ?? "",
                    "geometryStatus": item.geometryStatus.rawValue, "viewpointCount": item.viewpoints.count,
                    "capturedCount": captures.filter { $0.status == .captured }.count,
                    "failedCount": captures.filter { $0.status == .failed }.count,
                    "pendingCount": captures.filter { $0.status == .pending }.count,
                    "smoothToDisplayMaximumMetres": summaries.compactMap(\.smoothToDisplayMaximumMetres).max() as Any? ?? NSNull(),
                    "displayToDecodedDisplayMaximumMetres": summaries.compactMap(\.displayToDecodedDisplayMaximumMetres).max() as Any? ?? NSNull(),
                    "candidateViewpointCountOver10m": summaries.filter {
                        ($0.smoothToDisplayMaximumMetres ?? 0) >= 10 || ($0.displayToDecodedDisplayMaximumMetres ?? 0) >= 10
                    }.count,
                    "reviewVerdict": "pending"]
        }
        return try JSONSerialization.data(withJSONObject: [
            "format": "jtm-native-batch-report-v1", "packageVersion": plan?.packageVersion ?? "",
            "captureSettings": try JSONSerialization.jsonObject(with: Self.encoder.encode(captureSettings)),
            "lineCount": Set(inputs.values.map(\.lineID)).count, "intervalCount": plan?.items.count ?? 0,
            "viewpointCount": totalCount, "capturedCount": completedCount, "failedCount": failedCount,
            "pendingCount": pendingCount, "unavailableIntervalCount": unavailableCount,
            "scope": "All supplied Japan station intervals, risk ordered. Captures collect evidence; every human verdict remains pending. Overlapping viewpoints are distinct camera records and are not additive certified coverage.",
            "distanceScope": "10m requested smooth→display sampling; each view discloses sample cap and actual upper spacing. No Apple pixel residual.",
            "displayStageScope": "DisplayParts→complete decoded display intervals sampled independently. Values ≥10m are review candidates only; package and renderer geometry can both differ from Apple track.",
            "intervals": intervals
        ], options: [.prettyPrinted, .sortedKeys])
    }

    /// Agent lookup avoids scanning the national plan or guessing numeric folders.
    func scopedEvidenceIndex(scope: Set<String>, viewpointIDs: Set<String>? = nil) throws -> Data {
        let rows = (checkpoint?.progress ?? []).filter { scope.contains($0.itemID) && (viewpointIDs == nil || viewpointIDs!.contains($0.viewpointID)) }.sorted {
            let left = inputs[$0.itemID]?.intervalIndex ?? 0, right = inputs[$1.itemID]?.intervalIndex ?? 0
            return left == right ? $0.viewpoint.pointOrdinal < $1.viewpoint.pointOrdinal : left < right
        }
        let values: [[String: Any]] = rows.map { row in
            ["itemID": row.itemID, "viewpointID": row.viewpointID,
             "pointOrdinal": row.viewpoint.pointOrdinal, "status": row.status.rawValue,
             "longitude": row.viewpoint.coordinate.longitude, "latitude": row.viewpoint.coordinate.latitude,
             "directory": outputURL.appendingPathComponent(captureDirectory(inputID: row.itemID, pointOrdinal: row.viewpoint.pointOrdinal)).path,
             "lineDependency": lineDependencies[inputs[row.itemID]?.lineID ?? ""] ?? "",
             "referenceDependency": referenceDependencies[row.itemID] ?? "",
             "receiptFiles": receipts[row.viewpointID]?.files.map(\.name) ?? []]
        }
        return try JSONSerialization.data(withJSONObject: ["format": "jtm-scoped-evidence-index-v1", "views": values,
            "captureSettings": try JSONSerialization.jsonObject(with: Self.encoder.encode(captureSettings)),
            "spacingMetres": plan?.spacingMetres ?? 0,
            "selectedViewpointIDs": viewpointIDs.map { $0.sorted() } as Any? ?? NSNull(),
            "unavailableItemIDs": (plan?.items ?? []).filter { scope.contains($0.itemID) && $0.geometryStatus != .available }.map(\.itemID)], options: [.prettyPrinted, .sortedKeys])
    }

    private func capture(_ viewpoint: BatchInspectionViewpoint) async throws {
        guard let input = inputs[viewpoint.itemID], let line = lines[input.lineID] else { throw CaptureError.missingLine }
        if renderedLine?.lineID != line.id {
            let display = DisplayParts.parts(for: line, topology: topology[line.id] ?? .init())
            guard Self.valid(display) else { throw CaptureError.invalidGeometry }
            renderedLine = BatchCaptureGeometry.render(line: line, display: display, settings: captureSettings)
        }
        guard let renderedLine else { throw CaptureError.missingLine }
        let center = Coordinate(lon: viewpoint.coordinate.longitude, lat: viewpoint.coordinate.latitude)
        let rect = BatchCaptureGeometry.rect(center: center, settings: captureSettings)
        let display = BatchCaptureGeometry.clip(renderedLine.display, to: rect)
        let smooth = BatchCaptureGeometry.clip(renderedLine.smooth, to: rect)
        guard !display.paths.isEmpty, !smooth.paths.isEmpty else { throw CaptureError.noVisibleGeometry }
        let scoped = scopedReference(for: input)
        let references = BatchCaptureGeometry.clip(scoped?.paths ?? [], to: rect)
        let source = BatchCaptureGeometry.clip([input.source.map { Coordinate(lon: $0.longitude, lat: $0.latitude) }].filter(Self.valid), to: rect)
        let distances = BatchCaptureGeometry.distances(smooth: smooth, display: renderedLine.display)
        let decodedDisplay = renderedLine.decodedDisplay
        let displayStageDistances = Self.valid(decodedDisplay)
            ? BatchCaptureGeometry.distances(smooth: display, display: decodedDisplay) : nil
        let mapScale = BatchCaptureGeometry.mapPointsPerPoint(settings: captureSettings)
        let camera: [String: Double] = ["latitude": center.lat, "longitude": center.lon,
            "zoom256": captureSettings.zoom, "mapPointsPerPoint": mapScale,
            "metresPerPoint": mapScale * MKMetersPerMapPointAtLatitude(center.lat),
            "heading": 0, "pitch": 0, "viewportWidthPoints": Double(captureSettings.width),
            "viewportHeightPoints": Double(captureSettings.height), "displayScale": 1,
            "rectX": rect.origin.x, "rectY": rect.origin.y, "rectWidth": rect.width, "rectHeight": rect.height]
        var metadata: [String: Any] = [
            "format": "jtm-rail-view-v1", "region": "jp", "packageVersion": plan?.packageVersion ?? "",
            "itemID": input.id, "lineID": input.lineID, "intervalIndex": input.intervalIndex,
            "fromStationID": input.fromStationID, "toStationID": input.toStationID,
            "viewpointID": viewpoint.id, "pointOrdinal": viewpoint.pointOrdinal, "distanceMetres": viewpoint.distanceMetres,
            "camera": camera, "mode": "compare", "opacity": 1, "timestamp": ISO8601DateFormatter().string(from: Date()),
            "result": "pending", "reviewFresh": false, "reviewTitle": "待复核",
            "renderContract": BatchCaptureGeometry.styleContract(settings: captureSettings),
            "captureSettings": try JSONSerialization.jsonObject(with: Self.encoder.encode(captureSettings)),
            "coverageSpacingMetres": plan?.spacingMetres ?? 0,
            "wholeLineRenderDependency": lineDependencies[input.lineID] ?? "",
            "intervalIdentityPlan": "identity-plan-\(planDigest).json",
            "referenceDependency": referenceDependencies[input.id] ?? "Apple-only",
            "referenceLabel": scoped?.label ?? "", "referenceLineID": scoped?.lineID ?? "",
            "referenceIntervalIndex": scoped?.intervalIndex as Any? ?? NSNull(),
            "geometryScope": "Complete own-line DisplayParts smoothed with retained station/end anchors at the requested zoom, then clipped to this immutable viewport. Isolated centreline; no lanes/follows/joins/family collapse.",
            "originalDisplayPartIndices": display.originalPartIndices, "originalSmoothPartIndices": smooth.originalPartIndices,
            "originalReferencePartIndices": references.originalPartIndices,
            "sourceCoordinates": source.paths.map { $0.map { [$0.lon, $0.lat] } },
            "coverageScope": "This viewport only; overlapping viewpoints are separate records, never summed as reviewed coverage.",
            "distanceScope": "One-sided sampled smooth→display nearest polyline. Full display line is distance target. Reference has independently scoped input identity. Not Apple pixel residual."
        ]
        if let distances { metadata["displayDistanceSample"] = try JSONSerialization.jsonObject(with: Self.encoder.encode(distances)) }
        if var displayStageDistances {
            displayStageDistances.scope = "One-sided DisplayParts→complete decoded display intervals nearest-polyline distance, within this viewport. Includes grooming/anchor changes; not Apple pixel residual or alignment verdict."
            metadata["displayStageDistanceSample"] = try JSONSerialization.jsonObject(with: Self.encoder.encode(displayStageDistances))
        }
        let referenceRect = InspectorModel.bounds((scoped?.paths ?? []).flatMap { $0 }).intersection(rect)
        if !references.paths.isEmpty,
           let sample = InspectionDistances.sampledMaximum(smooth.paths, to: scoped?.paths ?? [], in: referenceRect) {
            metadata["referenceDistanceSample"] = try JSONSerialization.jsonObject(with: Self.encoder.encode(sample))
            metadata["referenceDistanceScope"] = "Selected interval reference identity only; samples clipped to reference bounds intersected with this viewport. Not Apple pixel residual."
        }
        let record = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        let options = MKMapSnapshotter.Options()
        options.mapRect = rect
        options.size = BatchCaptureGeometry.size(settings: captureSettings)
        let appearance: UIUserInterfaceStyle = captureSettings.appearance == .dark ? .dark : .light
        options.traitCollection = UITraitCollection(mutations: { traits in
            traits.displayScale = 1
            traits.userInterfaceStyle = appearance
        })
        switch captureSettings.basemapStyle {
        case .standard:
            options.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .default)
        case .imagery:
            options.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .flat)
        }
        options.pointOfInterestFilter = .excludingAll
        options.showsBuildings = true
        try Task.checkCancellation()
        var bundle = try await InspectionEvidence.capture(options: options, record: record,
            display: display.paths, smooth: smooth.paths, reference: references.paths,
            width: RailStyle.railWidth * RailStyle.scale(atZoom: captureSettings.zoom), itemID: input.id,
            outputModes: captureSettings.outputModes,
            expectedPixelSize: options.size)
        try Task.checkCancellation()
        bundle.files["README.txt"] = Data("One native MKMapSnapshotter view at the captureSettings in view.json, 1× pixels. Requested PNG modes: \(captureSettings.outputModes.map(\.rawValue).joined(separator: ", ")). Display and smooth overlays share that basemap, mapRect and viewport. Complete own-line geometry is smoothed before clipping. Snapshots collect evidence; alignment and physical connectivity remain pending human review.\n".utf8)
        if let distances { bundle.files["distance-samples.json"] = try Self.encoder.encode(distances) }
        if var displayStageDistances {
            displayStageDistances.scope = "One-sided DisplayParts→complete decoded display intervals nearest-polyline distance, within this viewport. Not Apple pixel residual or alignment verdict."
            bundle.files["display-stage-distance-samples.json"] = try Self.encoder.encode(displayStageDistances)
        }
        let directory = captureDirectory(inputID: input.id, pointOrdinal: viewpoint.pointOrdinal)
        let targetURL = outputURL.appendingPathComponent(directory, isDirectory: true)
        try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
        var files: [FileReceipt] = []
        for name in bundle.files.keys.sorted() {
            guard Self.allowedFiles.contains(name), let data = bundle.files[name] else { throw CaptureError.unsafeEvidenceName }
            try data.write(to: targetURL.appendingPathComponent(name), options: .atomic)
            files.append(.init(name: name, byteCount: data.count, sha256: Self.digest(data)))
        }
        for optionalName in ["basemap.png", "display.png", "smooth.png", "reference.png", "distance-samples.json", "display-stage-distance-samples.json"] where bundle.files[optionalName] == nil {
            let staleURL = targetURL.appendingPathComponent(optionalName)
            if FileManager.default.fileExists(atPath: staleURL.path) { try FileManager.default.removeItem(at: staleURL) }
        }
        let receipt = CaptureReceipt(directory: directory, files: files)
        receipts[viewpoint.id] = receipt
        candidates[viewpoint.id] = .init(smoothToDisplayMaximumMetres: distances?.maximumMetres,
            displayToDecodedDisplayMaximumMetres: displayStageDistances?.maximumMetres,
            cappedSampling: (distances?.capReducedSampling ?? false) || (displayStageDistances?.capReducedSampling ?? false))
        checkpoint?.record(viewpoint: viewpoint, status: .captured,
            evidencePaths: files.map { "\(directory)/\($0.name)" }, note: "快照证据已保存；人工对齐结论仍待复核")
        refreshCounts()
        try persist(viewpoint: viewpoint)
    }

    private func persist(viewpoint: BatchInspectionViewpoint? = nil, writeReport: Bool = false) throws {
        guard let checkpoint else { return }
        var changedViewState = false
        if let viewpoint, let row = checkpoint.progress.first(where: { $0.viewpointID == viewpoint.id }), let input = inputs[row.itemID] {
            let state = SavedCapture(planDigest: planDigest, progress: row, intervalDependency: intervalDependencies[input.id] ?? "",
                lineDependency: lineDependencies[input.lineID] ?? "", referenceDependency: referenceDependencies[input.id] ?? "Apple-only",
                receipt: receipts[row.viewpointID], candidate: candidates[row.viewpointID])
            let directory = outputURL.appendingPathComponent(captureDirectory(inputID: input.id, pointOrdinal: viewpoint.pointOrdinal), isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let stateURL = directory.appendingPathComponent("capture-state.json")
            let stateData = try Self.encoder.encode(state)
            if (try? Data(contentsOf: stateURL)) != stateData {
                try stateData.write(to: stateURL, options: .atomic)
                changedViewState = true
            }
            capturesSinceReport += 1
        }
        let saved = SavedCheckpoint(planDigest: planDigest, capturedCount: completedCount, failedCount: failedCount,
            pendingCount: pendingCount, unavailableIntervalCount: unavailableCount)
        let scopeSuffix = preservesBroaderPlan ? "-\(planDigest)" : ""
        try Self.encoder.encode(saved).write(to: outputURL.appendingPathComponent("checkpoint\(scopeSuffix).json"), options: .atomic)
        if writeReport || capturesSinceReport >= 100 {
            try reportData().write(to: outputURL.appendingPathComponent("report\(scopeSuffix).json"), options: .atomic)
            capturesSinceReport = 0
        }
        if changedViewState { evidenceRevision &+= 1 }
    }

    private func refreshCounts() {
        var captured = 0, failed = 0, pending = 0
        for row in checkpoint?.progress ?? [] {
            switch row.status {
            case .captured: captured += 1
            case .failed: failed += 1
            case .pending: pending += 1
            }
        }
        completedCount = captured
        failedCount = failed
        pendingCount = pending
    }

    private func validReceipt(for row: BatchInspectionProgress) -> Bool {
        let required = Set(["view.json", "README.txt"] + captureSettings.outputModes.map { "\($0.rawValue).png" })
        guard let receipt = receipts[row.viewpointID], receipt.directory == captureDirectory(inputID: row.itemID, pointOrdinal: row.viewpoint.pointOrdinal),
              Set(receipt.files.map(\.name)).isSuperset(of: required),
              Set(receipt.files.filter { $0.name.hasSuffix(".png") }.map(\.name)) == Set(captureSettings.outputModes.map { "\($0.rawValue).png" }),
              row.evidencePaths.sorted() == receipt.files.map({ "\(receipt.directory)/\($0.name)" }).sorted() else { return false }
        for file in receipt.files {
            guard Self.allowedFiles.contains(file.name), file.byteCount > 0, Self.validDigest(file.sha256) else { return false }
            let url = outputURL.appendingPathComponent(receipt.directory).appendingPathComponent(file.name)
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  attributes[.type] as? FileAttributeType == .typeRegular,
                  attributes[.size] as? Int == file.byteCount, let digest = try? Self.fileDigest(url), digest == file.sha256 else { return false }
        }
        return true
    }

    private func captureDirectory(inputID: String, pointOrdinal: Int) -> String {
        // Index order is independent of risk ranking. Exact target identities
        // reject moved slots after inventory edits. IDs never become paths.
        "captures/\(String(format: "%06d", directoryIndices[inputID] ?? -1))/\(String(format: "%06d", pointOrdinal))"
    }
    private func identityPlanURL(_ digest: String) -> URL {
        outputURL.appendingPathComponent("identity-plan-\(digest).json")
    }
    private func scopedReference(for input: InspectionInput) -> ReferenceTrack? {
        guard let reference, reference.lineID == input.lineID, reference.intervalIndex == input.intervalIndex else { return nil }
        return reference
    }
    private static let allowedFiles: Set<String> = ["view.json", "basemap.png", "display.png", "smooth.png", "reference.png", "README.txt", "distance-samples.json", "display-stage-distance-samples.json"]
    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
    private static func valid(_ paths: [[Coordinate]]) -> Bool { paths.allSatisfy(valid) }
    private static func valid(_ path: [Coordinate]) -> Bool {
        path.allSatisfy { $0.lon.isFinite && $0.lat.isFinite && abs($0.lon) <= 180 && abs($0.lat) < 90 }
    }
    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private static func validDigest(_ value: String) -> Bool {
        value.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    private static func fileDigest(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
