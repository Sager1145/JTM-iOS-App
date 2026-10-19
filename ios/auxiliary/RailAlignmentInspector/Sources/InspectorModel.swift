import Foundation
import MapKit
import Observation
import RailCore
import RailInspection

enum ComparisonMode: String, CaseIterable, Identifiable {
    case basemap, decoded, display, smooth, compare, extracted
    var id: String { rawValue }
    var title: String {
        switch self {
        case .basemap: "底图"
        case .decoded: "包几何"
        case .display: "显示几何"
        case .smooth: "平滑"
        case .compare: "叠加对照"
        case .extracted: "抽离"
        }
    }
}

@MainActor @Observable
final class InspectorModel {
    let captureAdmission: InspectionCaptureAdmission
    let batch: BatchCaptureController

    private let reviewOutputURL: URL?
    private let diagnosticRequest: DiagnosticRequest?
    private(set) var packageURL: URL?
    private(set) var admittedCaptureInputs: [InspectionInput] = []
    @ObservationIgnored var captureTaskRequested: ((String, Int?) -> Void)?

    init(outputURL: URL? = nil, diagnosticRequest: DiagnosticRequest? = nil) {
        self.diagnosticRequest = diagnosticRequest
        reviewOutputURL = outputURL
        let admission = InspectionCaptureAdmission()
        captureAdmission = admission
        batch = BatchCaptureController(outputURL: outputURL, captureAdmission: admission)
    }
    var lines: [CompactPackage.Line] = []
    var topology: [String: DisplayParts.LineTopology] = [:]
    var version = ""
    var query = ""
    var lineID: String?
    var stationIndex = 0
    var mode = ComparisonMode.compare
    var opacity = 0.7
    var peek = false
    var error: String?
    var status = "地图加载中"
    var decoded: [[Coordinate]] = []
    var display: [[Coordinate]] = []
    var focus = UUID()
    var focusRect = MKMapRect.null
    var cameraRecord: [String: Double] = [:]
    var plan: RailInspection.InspectionPlan?
    var inputsByID: [String: InspectionInput] = [:]
    var reviews: [String: InspectionReview] = [:]
    var observations: [String: [InspectionReview]] = [:]
    var inspectionPointIndex = 0
    var pendingOnly = false
    var draftVerdict = ReviewVerdict.pending
    var draftNote = ""
    var reference: ReferenceTrack?
    var referenceRevision = UUID()
    var evidence: EvidenceBundle?
    var captureRequest: UUID?
    var busyCapture: Bool { captureAdmission.scope == .manual }
    var zoomRequest: Double?
    var cameraCenterRequest: Coordinate?
    var zoomRevision = UUID()
    var analysisRequest: UUID?
    var analysisGeneration = UUID()
    var analysisBusy = false
    var transitCartography = false
    var blueRailwayOnly = false
    var analysisReport: AppleMapExtractionReport?
    var analysisRect = MKMapRect.null
    var showAnalysisBasemap = false
    var showAnalysisConstructed = true
    @ObservationIgnored var analysisTask: Task<Void, Never>?
    private var draftItemID: String?
    private var freshReviewIDs: Set<String> = []
    // Increment when this inspector's projection/smoothing contract changes.
    private var renderContract: String {
        let values = [0.0, 8, 14, 17, 18, 22].flatMap { zoom -> [Double] in
            let scale = RailStyle.scale(atZoom: zoom)
            return [Double(scale), Double(RailStyle.minimumCornerRadius(atScale: scale))]
        }
        return "\(InspectorStrokeGeometry.revision);\(InspectorStrokeGeometry.joinContract);\(RailStyle.railWidth);\(RailStyle.strokeCornerRadius);\(RailStyle.strokeMinRamp);\(RailStyle.parallelLaneCentreDistance);\(values)"
    }
    private var renderedInput: [[InspectionPoint]] {
        display.map { $0.map { InspectionPoint(longitude: $0.lon, latitude: $0.lat) } }
    }

    var currentInput: InspectionInput? {
        guard let lineID else { return nil }
        return inputsByID["\(lineID)#\(stationIndex)"]
    }
    var canCaptureEvidence: Bool {
        line != nil && !captureAdmission.isBusy && !analysisBusy && mode != .extracted
    }
    var currentItem: InspectionItem? {
        guard let id = currentInput?.id else { return nil }
        return plan?.items.first { $0.id == id }
    }
    var currentReview: InspectionReview? {
        guard let input = currentInput, let review = reviews[input.id], freshReviewIDs.contains(input.id) else { return nil }
        return review
    }
    var totalCount: Int { plan?.items.count ?? 0 }
    var reviewedCount: Int { plan?.items.filter { isReviewed($0.id) }.count ?? 0 }
    var progressText: String { "全量 \(totalCount) · 视点结论 \(reviews.filter { freshReviewIDs.contains($0.key) && $0.value.verdict != .pending }.count) · 详细覆盖 \(reviewedCount)" }
    var filteredItems: [InspectionItem] {
        searchItems.filter { !pendingOnly || !isReviewed($0.id) }
    }
    private var searchItems: [InspectionItem] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return (plan?.items ?? []).filter { item in
            search.isEmpty ||
                [item.lineID, item.lineName, item.operatorName, item.fromName, item.toName, item.id]
                    .contains { $0.localizedCaseInsensitiveContains(search) }
        }
    }
    var referencePaths: [[Coordinate]] {
        guard let reference, let item = currentItem,
              reference.lineID == nil || reference.lineID == item.lineID,
              reference.intervalIndex == nil || reference.intervalIndex == item.intervalIndex else { return [] }
        return reference.paths
    }
    var referenceLabel: String? { referencePaths.isEmpty ? nil : reference?.label }

    var line: CompactPackage.Line? { lines.first { $0.id == lineID } }
    var filteredLines: [CompactPackage.Line] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return search.isEmpty ? lines : lines.filter {
            [$0.name, $0.nameRoma ?? "", $0.operator ?? "", $0.id]
                .contains { $0.localizedCaseInsensitiveContains(search) }
        }
    }

    func load() async {
        guard lines.isEmpty, error == nil else { return }
        let url: URL
        if let inputPath = diagnosticRequest?.inputPath {
            url = URL(fileURLWithPath: inputPath)
        } else if let bundled = Bundle.main.url(forResource: "jp-2025", withExtension: "json") {
            url = bundled
        } else {
            error = "缺少 jp-2025.json"; return
        }
        packageURL = url
        do {
            // Fresh scoped sessions build only this line's review/capture plan.
            // Legacy evidence keeps the full sorted-ID directory mapping.
            let scopedLineID = diagnosticRequest?.alignmentEvidenceDirectory == nil ? diagnosticRequest?.lineID : nil
            let result = try await Task.detached(priority: .userInitiated) {
                let loaded = try DisplayParts.LoadedPackage.load(contentsOf: url)
                guard loaded.package.country.lowercased() == "jp" else {
                    throw DiagnosticError.invalidRequest("Alignment requires a Japan (jp) compact package.")
                }
                let scopedLines = loaded.package.lines.filter { scopedLineID == nil || $0.id == scopedLineID }
                let inputs = Self.makeInputs(scopedLines)
                let plan = RailInspection.InspectionPlan.build(inputs: inputs, packageVersion: loaded.package.version)
                return (loaded, inputs, plan)
            }.value
            let loaded = result.0
            version = loaded.package.version
            topology = loaded.topologyByLineID
            lines = loaded.package.lines.sorted { ($0.operator ?? "", $0.name) < ($1.operator ?? "", $1.name) }
            inputsByID = Dictionary(uniqueKeysWithValues: result.1.map { ($0.id, $0) })
            plan = result.2
            loadReviews()
            if let referenceURL = Bundle.main.url(forResource: "tabata-reference", withExtension: "geojson") {
                reference = try ReferenceTrack.read(Data(contentsOf: referenceURL))
                referenceRevision = UUID()
            }
            refreshReviewDependencies()
            // Interactive browsing builds no country-wide capture plan. The
            // unified task owner admits an exact scope when capture is asked for.
            if diagnosticRequest != nil {
                do { try configureBatch() } catch { self.error = "批量计划读取失败：\(error.localizedDescription)" }
            }
            select(diagnosticRequest?.lineID ?? lines.first { $0.name == "山手線" }?.id ?? lines.first?.id)
        } catch { self.error = error.localizedDescription }
    }

    private func configureBatch() throws {
        guard let diagnosticRequest else { return }
        let selected = try diagnosticRequest.alignmentInputs(Array(inputsByID.values))
        try batch.configure(inputs: selected,
                            linesByID: Dictionary(uniqueKeysWithValues: lines.map { ($0.id, $0) }),
                            topology: topology, packageVersion: version, reference: reference,
                            protectedScope: Set(selected.map(\.id)), settings: diagnosticRequest.normalizedCaptureSettings)
        admittedCaptureInputs = selected
    }

    /// UI and keyboard actions must return to the sole immutable-task owner.
    func startBatch(selectedOnly: Bool = false) {
        guard !batch.isRunning, !analysisBusy, !captureAdmission.isBusy,
              let captureTaskRequested, let lineID, !selectedOnly || currentInput != nil else { return }
        captureTaskRequested(lineID, selectedOnly ? stationIndex : nil)
    }

    func select(_ id: String?) {
        guard lineID != id else { return }
        lineID = id; stationIndex = 0; inspectionPointIndex = 0
        guard let line else { decoded = []; display = []; return }
        decoded = CompactPackage.decodeIntervals(line)
        display = DisplayParts.parts(for: line, topology: topology[line.id] ?? .init())
        focusStation()
    }

    func navigate(_ delta: Int) {
        guard let line, !line.stations.isEmpty else { return }
        stationIndex = min(max(stationIndex + delta, 0), line.stations.count - 1)
        focusStation()
    }

    func focusStation() {
        invalidateAnalysis()
        loadDraft()
        guard let line, line.stations.indices.contains(stationIndex) else { return }
        let point = MKMapPoint(line.displayCoordinate(for: line.stations[stationIndex]).native)
        let span = 1400 / MKMetersPerMapPointAtLatitude(point.coordinate.latitude)
        focusRect = MKMapRect(x: point.x - span / 2, y: point.y - span / 2, width: span, height: span)
        focus = UUID()
    }

    func focusInterval() {
        invalidateAnalysis()
        guard decoded.indices.contains(stationIndex) else { return }
        let effective = currentInput?.display.map { Coordinate(lon: $0.longitude, lat: $0.latitude) } ?? []
        focusRect = Self.bounds(effective.isEmpty ? decoded[stationIndex] : effective); focus = UUID()
    }

    func focusLine() { invalidateAnalysis(); focusRect = Self.bounds(display.flatMap { $0 }); focus = UUID() }

    static func bounds(_ coordinates: [Coordinate]) -> MKMapRect {
        coordinates.reduce(MKMapRect.null) { rect, coordinate in
            let point = MKMapPoint(coordinate.native)
            return rect.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
        }
    }

    func selectItem(_ id: String) {
        guard let input = inputsByID[id] else { return }
        select(input.lineID)
        stationIndex = input.intervalIndex
        inspectionPointIndex = 0
        loadDraft()
        focusInterval()
    }

    func navigateQueue(_ delta: Int) {
        let queue = searchItems
        guard !queue.isEmpty else { return }
        let direction = delta < 0 ? -1 : 1
        let index = queue.firstIndex { $0.id == currentInput?.id } ?? (direction > 0 ? -1 : queue.count)
        for offset in 1...queue.count {
            let next = ((index + direction * offset) % queue.count + queue.count) % queue.count
            guard !isReviewed(queue[next].id) else { continue }
            selectItem(queue[next].id)
            return
        }
        status = "当前搜索范围内没有待检区间"
    }

    func saveReview() {
        guard let input = currentInput else { return }
        let review = InspectionReview(itemID: input.id, verdict: draftVerdict, note: draftNote,
                                      reviewedAt: Date(), source: input.source, display: input.display,
                                      evidencePaths: currentReview?.evidencePaths ?? [],
                                      fromStationID: input.fromStationID, toStationID: input.toStationID,
                                      renderedDisplay: renderedInput, renderContract: contract(for: input), camera: cameraRecord)
        do {
            var updated = reviews
            updated[input.id] = review
            try persistReviews(updated)
            reviews = updated
            freshReviewIDs.insert(input.id)
            status = "已保存人工复核：\(draftVerdict.title)"
        } catch { self.error = error.localizedDescription }
    }

    func planData() throws -> Data {
        guard let plan else { return Data() }
        var object = try JSONSerialization.jsonObject(with: Self.recordEncoder().encode(plan)) as! [String: Any]
        let current = reviews.filter { id, _ in freshReviewIDs.contains(id) }
        object["observations"] = try JSONSerialization.jsonObject(with: Self.recordEncoder().encode(observations))
        object["reviews"] = try JSONSerialization.jsonObject(with: Self.recordEncoder().encode(current))
        object["reviewedCount"] = reviewedCount
        object["staleReviewCount"] = reviews.keys.filter { !freshReviewIDs.contains($0) }.count
        object["lineSummary"] = lines.map { line -> [String: Any] in
            let items = plan.items.filter { $0.lineID == line.id }
            var counts: [String: Int] = [:]
            for item in items { counts[freshReviewIDs.contains(item.id) ? (reviews[item.id]?.verdict.rawValue ?? "pending") : "pending", default: 0] += 1 }
            return ["lineID": line.id, "name": line.name, "intervalCount": items.count,
                    "spatiallyCoveredAtDetail": items.filter { isReviewed($0.id) }.count, "viewVerdicts": counts]
        }
        object["scope"] = "Every station interval; priority is triage, never geographic pass. Review is captured viewport only."
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    func importReference(data: Data) throws {
        var imported = try ReferenceTrack.read(data)
        guard let item = currentItem else { throw EvidenceError.invalidReference }
        if imported.lineID == nil { imported.lineID = item.lineID }
        if imported.intervalIndex == nil { imported.intervalIndex = item.intervalIndex }
        reference = imported
        referenceRevision = UUID()
        refreshReviewDependencies()
        status = "已导入外部轨道参考，需人工核对轨道身份"
    }

    func captureRequested() {
        guard canCaptureEvidence,
              let request = captureAdmission.begin(.manual) else { return }
        evidence = nil
        captureRequest = request
        status = "正在生成同视角证据…"
    }

    func finishCapture(_ request: UUID, bundle: EvidenceBundle? = nil, error: Error? = nil) {
        captureAdmission.finish(request)
        guard captureRequest == request else { return }
        captureRequest = nil
        if let bundle { evidence = bundle }
        if let error { self.error = error.localizedDescription }
    }

    func analysisRequested() {
        guard !analysisBusy, !captureAdmission.isBusy, line != nil else { return }
        invalidateAnalysis()
        if mode == .extracted { mode = .compare }
        guard let request = captureAdmission.begin(.analysis) else { return }
        analysisGeneration = request
        analysisRequest = request
        analysisBusy = true
        error = nil
        status = "正在从 Apple 底图抽离铁路与车站…"
    }

    func invalidateAnalysis() {
        if mode == .extracted { mode = .compare }
        if analysisTask == nil, let request = analysisRequest { captureAdmission.finish(request) }
        analysisTask?.cancel()
        analysisTask = nil
        analysisGeneration = UUID()
        analysisRequest = nil
        analysisReport = nil
        analysisRect = .null
        analysisBusy = false
    }

    func analysisFiles() throws -> [String: Data] {
        guard let analysisReport else { return [:] }
        return try analysisReport.files()
    }

    func requestDetail(_ zoom: Double) {
        invalidateAnalysis()
        cameraCenterRequest = nil
        zoomRequest = zoom
        zoomRevision = UUID()
    }

    func requestCamera(_ text: String) {
        let values = text.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard values.count == 3, let longitude = values[0], let latitude = values[1], let zoom = values[2],
              longitude.isFinite, latitude.isFinite, zoom.isFinite,
              (-180...180).contains(longitude), (-85...85).contains(latitude), (1...22).contains(zoom),
              !captureAdmission.isBusy, !analysisBusy else {
            status = "请输入经度,纬度,缩放级别（1–22）"
            return
        }
        invalidateAnalysis()
        cameraCenterRequest = Coordinate(lon: longitude, lat: latitude)
        zoomRequest = zoom
        zoomRevision = UUID()
    }

    /// Called after the evidence folder has actually been exported. Capture
    /// generation alone does not attach nonexistent paths to a review.
    func recordEvidenceSuccess(_ bundle: EvidenceBundle, paths: [String] = []) {
        evidence = bundle
        guard let id = bundle.itemID, let input = inputsByID[id], !paths.isEmpty else { return }
        let existing = freshReviewIDs.contains(id) ? reviews[id] : nil
        let metadata = bundle.files["view.json"].flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let capturedParts = (metadata?["renderedDisplay"] as? [[[Double]]])?.map { $0.map { InspectionPoint(longitude: $0[0], latitude: $0[1]) } }
        let review = InspectionReview(itemID: id, verdict: existing?.verdict ?? .pending,
                                      note: existing?.note ?? "", reviewedAt: existing?.reviewedAt ?? Date(),
                                      source: input.source, display: input.display,
                                      evidencePaths: Array(Set((existing?.evidencePaths ?? []) + paths)).sorted(),
                                      fromStationID: input.fromStationID, toStationID: input.toStationID,
                                      renderedDisplay: existing?.renderedDisplay ?? capturedParts,
                                      renderContract: existing?.renderContract ?? (metadata?["renderContract"] as? String),
                                      camera: existing?.camera ?? (metadata?["camera"] as? [String: Double]))
        do {
            var updated = reviews
            updated[id] = review
            try persistReviews(updated)
            reviews = updated
            refreshReviewDependencies()
            status = "证据已导出并关联区间"
        } catch { self.error = error.localizedDescription }
    }

    func recordEvidenceFailure(_ error: Error) {
        self.error = error.localizedDescription
    }

    private func isReviewed(_ id: String) -> Bool {
        guard let input = inputsByID[id], let review = reviews[id] else { return false }
        return review.verdict != .pending && freshReviewIDs.contains(input.id) && hasDetailedCoverage(review, input: input)
    }

    private func contract(for input: InspectionInput) -> String {
        guard let reference, reference.lineID == input.lineID,
              reference.intervalIndex == input.intervalIndex else { return renderContract + ";Apple-only" }
        return renderContract + ";reference=\(reference.label);\(reference.paths.map { $0.map { [$0.lon, $0.lat] } })"
    }

    private func hasDetailedCoverage(_ review: InspectionReview, input: InspectionInput) -> Bool {
        let valid = (observations[input.id] ?? [review]).filter {
            $0.isCurrent(for: input) && $0.renderedDisplay == review.renderedDisplay && $0.renderContract == review.renderContract &&
                $0.verdict != .pending && $0.verdict != .insufficientBasemap
        }
        let rects: [MKMapRect] = valid.compactMap { observed in
            guard let camera = observed.camera, (camera["zoom256"] ?? 0) >= 16.99,
                  let x = camera["rectX"], let y = camera["rectY"],
                  let w = camera["rectWidth"], let h = camera["rectHeight"] else { return nil }
            let margin = 20 / MKMetersPerMapPointAtLatitude(camera["latitude"] ?? 35)
            return MKMapRect(x: x + margin, y: y + margin, width: max(0, w - 2 * margin), height: max(0, h - 2 * margin))
        }
        let path = input.display.map { Coordinate(lon: $0.longitude, lat: $0.latitude) }
        let samples = InspectionViewpoints.points(input: path, spacingMetres: 20)
        return !samples.isEmpty && samples.allSatisfy { point in rects.contains { $0.contains(MKMapPoint(point.native)) } }
    }

    var inspectionPoints: [Coordinate] {
        InspectionViewpoints.points(input: currentInput?.display.map { Coordinate(lon: $0.longitude, lat: $0.latitude) } ?? [])
    }

    func navigateInspectionPoint(_ delta: Int) {
        let points = inspectionPoints
        guard !points.isEmpty else { return }
        inspectionPointIndex = min(max(inspectionPointIndex + delta, 0), points.count - 1)
        let point = MKMapPoint(points[inspectionPointIndex].native)
        focusRect = MKMapRect(x: point.x - 100, y: point.y - 100, width: 200, height: 200)
        focus = UUID()
        requestDetail(17)
    }

    func reviewTitle(_ id: String) -> String {
        guard freshReviewIDs.contains(id), let review = reviews[id], let input = inputsByID[id] else { return "待复核" }
        return review.verdict.title + (hasDetailedCoverage(review, input: input) ? "" : " · 仅视点")
    }

    private func refreshReviewDependencies() {
        freshReviewIDs = []
        var rendered: [String: [[InspectionPoint]]] = [:]
        for (id, review) in reviews {
            guard let input = inputsByID[id], review.isCurrent(for: input), review.renderContract == contract(for: input),
                  let line = lines.first(where: { $0.id == input.lineID }) else { continue }
            if rendered[line.id] == nil {
                rendered[line.id] = DisplayParts.parts(for: line, topology: topology[line.id] ?? .init()).map {
                    $0.map { InspectionPoint(longitude: $0.lon, latitude: $0.lat) }
                }
            }
            if review.renderedDisplay == rendered[line.id] { freshReviewIDs.insert(id) }
        }
    }

    private func loadDraft() {
        guard draftItemID != currentInput?.id else { return }
        inspectionPointIndex = 0
        draftItemID = currentInput?.id
        draftVerdict = currentReview?.verdict ?? .pending
        draftNote = currentReview?.note ?? ""
    }

    private var reviewsURL: URL {
        if let outputURL = reviewOutputURL {
            return outputURL.appendingPathComponent("reviews.json")
        }
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return root.appendingPathComponent("RailAlignmentInspector", isDirectory: true)
            .appendingPathComponent("reviews.json")
    }

    private func loadReviews() {
        guard FileManager.default.fileExists(atPath: reviewsURL.path) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let data = try Data(contentsOf: reviewsURL)
            if let history = try? decoder.decode([String: [InspectionReview]].self, from: data) {
                observations = history
                reviews = history.compactMapValues { $0.last }
            } else {
                reviews = try decoder.decode([String: InspectionReview].self, from: data)
                observations = reviews.mapValues { [$0] }
            }
        } catch { self.error = "无法读取已保存复核：\(error.localizedDescription)" }
    }

    private func persistReviews(_ updated: [String: InspectionReview]) throws {
        try FileManager.default.createDirectory(at: reviewsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var history = observations
        for (id, review) in updated {
            var rows = history[id] ?? []
            if let index = rows.firstIndex(where: {
                $0.camera == review.camera && $0.source == review.source && $0.display == review.display &&
                    $0.renderedDisplay == review.renderedDisplay && $0.renderContract == review.renderContract
            }) { rows[index] = review }
            else { rows.append(review) }
            history[id] = rows.sorted { $0.reviewedAt < $1.reviewedAt }
        }
        try Self.recordEncoder().encode(history).write(to: reviewsURL, options: .atomic)
        observations = history
    }

    private static func recordEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    nonisolated private static func makeInputs(_ lines: [CompactPackage.Line]) -> [InspectionInput] {
        lines.flatMap { line -> [InspectionInput] in
            let source = CompactPackage.decodeIntervals(line)
            let display = CompactPackage.decodeDisplayIntervals(line)
            let stationCount = line.stations.count
            let expected = line.isLoop ? stationCount : max(0, stationCount - 1)
            return (0..<max(expected, line.segments.count)).map { index in
                let from = line.stations[safe: index]
                let to = line.isLoop && index == stationCount - 1 ? line.stations.first : line.stations[safe: index + 1]
                let sourcePoints = (source[safe: index] ?? []).map { InspectionPoint(longitude: $0.lon, latitude: $0.lat) }
                let displayPoints = (display[safe: index] ?? []).map { InspectionPoint(longitude: $0.lon, latitude: $0.lat) }
                return InspectionInput(id: "\(line.id)#\(index)", lineID: line.id, lineName: line.name,
                                       operatorName: line.operator ?? "", intervalIndex: index,
                                       fromStationID: from?.id ?? "", toStationID: to?.id ?? "",
                                       fromName: from?.name ?? "缺失车站", toName: to?.name ?? "缺失车站",
                                       source: sourcePoints, display: displayPoints,
                                       hasDisplayOverride: line.displayIntervalCoordinates[index] != nil || sourcePoints != displayPoints)
            }
        }
    }

    func viewRecord(camera: [String: Double]? = nil) throws -> Data {
        var object: [String: Any] = [
            "format": "jtm-rail-view-v1", "region": "jp", "packageVersion": version,
            "lineID": lineID ?? "", "stationID": line?.stations[safe: stationIndex]?.id ?? "",
            "mode": peek ? "basemap" : mode.rawValue, "opacity": opacity,
            "camera": camera ?? cameraRecord, "timestamp": ISO8601DateFormatter().string(from: Date()),
            "result": currentReview?.verdict.rawValue ?? "pending", "reference": "Apple MKMapView drawn railway track",
            "geometryScope": "isolated centreline; no lanes/follows/joins/family collapse",
            "note": "人工复核记录；自动信号仅为候选。此元数据不包含底图像素误差测量。",
            "reviewTitle": currentReview?.verdict.title ?? ReviewVerdict.pending.title,
            "reviewNote": currentReview?.note ?? "",
            "reviewFresh": currentReview != nil,
            "referenceLabel": referenceLabel ?? "",
            "renderContract": currentInput.map { contract(for: $0) } ?? renderContract,
            "reviewScope": "Selected viewport only; a conclusion does not certify the entire interval or line."
        ]
        if let input = currentInput {
            object["intervalInput"] = try JSONSerialization.jsonObject(with: Self.recordEncoder().encode(input))
        }
        if let review = currentReview {
            object["review"] = try JSONSerialization.jsonObject(with: Self.recordEncoder().encode(review))
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }
}

extension Coordinate {
    var native: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
