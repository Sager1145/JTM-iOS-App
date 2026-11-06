import Foundation
import Observation
import RailCore
import RailPresentation

@MainActor
@Observable
final class RouteWorkbenchModel {
    let routes = RiddenRouteStore()
    private(set) var trains: [Train] = []
    private(set) var savedResults: [RiddenRouteStore.DrawnRide] = []
    private(set) var resultsByID: [String: RiddenRouteStore.DrawnRide] = [:]
    private(set) var sourceName = "尚未导入"
    private(set) var isReading = false
    private(set) var isRunning = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var importElapsed: TimeInterval = 0
    private(set) var inspectionElapsed: TimeInterval = 0
    private(set) var batchPhase = "empty"
    private(set) var message = "导入行程 JSON，在 Mac 上批量解析物理线路区段。"
    private var started: Date?
    private var missingResultStatus = "尚未解析"
    private var batchFailure: String?
    private(set) var findings: [RouteBatchInspection.Finding] = []
    private(set) var findingsByTrainID: [String: [RouteBatchInspection.Finding]] = [:]
    private(set) var isInspecting = false
    private(set) var inspectionMessage = "批量解析完成后自动检查；取消后可检查已返回的部分。"
    private var inspectionTask: Task<Void, Never>?
    private var inspectionRevision = 0
    var error: String?
    private(set) var inputURL: URL?
    @ObservationIgnored var solveTaskRequested: ((URL) -> Void)?

    func requestSolve() {
        guard !isRunning, !isReading, let inputURL else { return }
        solveTaskRequested?(inputURL)
    }

    var results: [RiddenRouteStore.DrawnRide] { isRunning ? routes.rides : savedResults }
    var completedCount: Int { results.count }
    var phaseKey: String {
        switch routes.state {
        case .idle: "idle"
        case .loading: "loading"
        case .loaded: "loaded"
        case .failed(let message): "failed:\(message)"
        }
    }

    /// Retain picker-granted bytes before its security scope ends. Both human
    /// import surfaces pass this durable immutable file to the task interface.
    static func importForTask(_ url: URL) async throws -> URL {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RailDiagnostics/Inputs/" + UUID().uuidString, isDirectory: true)
        return try await Task.detached(priority: .userInitiated) {
            let data = try Data(contentsOf: url)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let retained = root.appendingPathComponent(url.lastPathComponent)
            try data.write(to: retained, options: .atomic)
            return retained
        }.value
    }

    func read(_ url: URL, retainingForTask: Bool = false) async {
        guard !isRunning, !isReading else { return }
        isReading = true
        error = nil
        let readingStarted = Date()
        message = "正在读取行程文件…"
        defer { isReading = false }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let retainedURL = retainingForTask ? try await Self.importForTask(url) : url
            let loaded = try await Task.detached(priority: .userInitiated) {
                let text = try String(contentsOf: retainedURL, encoding: .utf8)
                return try Self.importTrains(text)
            }.value
            resetInspection()
            routes.clear()
            trains = loaded
            inputURL = retainedURL
            savedResults = []
            resultsByID = [:]
            elapsed = 0
            missingResultStatus = "尚未解析"
            sourceName = url.lastPathComponent
            importElapsed = Date().timeIntervalSince(readingStarted)
            batchPhase = "imported"
            message = "已导入 \(loaded.count) 条行程；原文件保持不变。"
        } catch {
            self.error = error.localizedDescription
            message = "读取失败：\(error.localizedDescription)"
        }
    }

    nonisolated static func importTrains(_ text: String) throws -> [Train] {
        let parsed = try TrainValidation.parseImportedCanonicalStore(text: text)
        guard case .array(let items)? = parsed["trains"] else { return [] }
        var session = ImportEngine.Session()
        for item in items {
            try Task.checkCancellation()
            if case .string(let code)? = item["region"] { session.country = code }
            else { session.country = "jp" }
            try session.appendImportedTrain(item)
        }
        // Keep imported records separate from the solver's inferred preferences.
        // RiddenRouteStore performs its own canonical normalization.
        return session.trains
    }

    func start() {
        guard !trains.isEmpty, !isReading, !isRunning else { return }
        resetInspection()
        savedResults = []
        resultsByID = [:]
        elapsed = 0
        started = Date()
        isRunning = true
        batchPhase = "running"
        message = "批量解析中；复用生产缓存、区段证据和求解器。"
        routes.clear()
        routes.load(trains: trains)
        refresh()
    }

    func refresh() {
        guard isRunning else { return }
        savedResults = routes.rides
        resultsByID = Dictionary(savedResults.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        elapsed = started.map { Date().timeIntervalSince($0) } ?? 0
        switch routes.state {
        case .loaded:
            isRunning = false
            batchPhase = "completed"
            missingResultStatus = "处理结束，未返回可用路线"
            message = "批量处理结束。未确认和无可用路线的记录仍保留。"
            inspect(finished: true)
        case .failed(let reason):
            isRunning = false
            batchPhase = "failed"
            batchFailure = reason
            missingResultStatus = "处理失败，未返回结果"
            message = "处理失败：\(reason)；已完成结果保留。"
            inspect(finished: false)
        case .idle, .loading: break
        }
    }

    func cancel() {
        guard isRunning else { return }
        savedResults = routes.rides
        resultsByID = Dictionary(savedResults.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        elapsed = started.map { Date().timeIntervalSince($0) } ?? 0
        isRunning = false
        batchPhase = "cancelled"
        routes.clear()
        missingResultStatus = "已取消，未返回结果"
        message = "已取消；保留 \(savedResults.count) 条已返回的结果，其余记录原样导出。"
    }

    private func resetInspection() {
        inspectionRevision += 1
        inspectionTask?.cancel()
        inspectionTask = nil
        isInspecting = false
        batchFailure = nil
        findings = []
        findingsByTrainID = [:]
        inspectionElapsed = 0
        inspectionMessage = "尚未检查本次结果。"
    }

    func inspect(finished: Bool? = nil) {
        guard !isRunning, !isReading, !isInspecting else { return }
        inspectionRevision += 1
        let revision = inspectionRevision
        let originals = trains
        let terminal = finished ?? (missingResultStatus == "处理结束，未返回可用路线")
        let failureReason = batchFailure
        let settled = results
        let inspectionStarted = Date()
        let snapshots = settled.map { ride -> RouteBatchInspection.Result in
            var expected = ride.expectedSectionCount
            let count: Int
            let resolved: Bool
            switch ride.route {
            case .resolved: count = ride.indicesAreAuthoritative ? Set(ride.segments.map(\.segmentIndex)).count : expected; resolved = true
            case .partial(let solved, let publishedExpected, _):
                expected = publishedExpected; count = solved; resolved = false
            case .unavailable(let publishedExpected):
                expected = publishedExpected; count = 0; resolved = false
            case .historyDatabaseInvalid: count = 0; resolved = false
            }
            return .init(trainID: ride.id, expectedSectionCount: expected, resolvedSectionCount: count,
                isResolved: resolved, physicalGaps: ride.physicalGaps.map { .init(index: $0.segmentIndex, isBoundary: $0.isBoundary) },
                segments: ride.segments.map { segment in
                    .init(index: segment.segmentIndex, partIndex: segment.partIndex,
                        sourceCoordinates: segment.sourceCoordinates,
                        intervalSelection: segment.physicalRoute.map {
                            .init(fromCode: $0.fromStationCode, toCode: $0.toStationCode,
                                intervals: $0.intervals, provenance: $0.provenance.rawValue)
                        }, isCurrent: segment.temporalKind == .current)
                }, indicesAreAuthoritative: ride.indicesAreAuthoritative)
        }
        isInspecting = true
        inspectionMessage = "检查输入、结果覆盖、几何、区段证据与导出回读…"
        inspectionTask = Task {
            let work = Task.detached(priority: .utility) {
                RouteBatchInspection.inspect(trains: originals, results: snapshots, finished: terminal,
                                             failureReason: failureReason)
            }
            var checked = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
            guard !Task.isCancelled, revision == inspectionRevision else { return }
            checked += await inspectPhysicalIntervals(originals: originals, settled: settled)
            guard !Task.isCancelled, revision == inspectionRevision else { return }
            do {
                let data = try await export(reportOnly: false)
                let decoded = try JSONDecoder().decode(TrainStore.self, from: data)
                checked += RouteBatchInspection.inspectExport(originals: originals, exported: decoded.trains)
            } catch {
                checked.append(.init(id: "export.decode", severity: .failure, code: "export.decode",
                    trainID: nil, sectionIndex: nil, message: "导出回读失败：\(error.localizedDescription)"))
            }
            guard !Task.isCancelled, revision == inspectionRevision else { return }
            findings = checked
            findingsByTrainID = Dictionary(grouping: checked.filter { $0.trainID != nil }, by: { $0.trainID! })
            inspectionElapsed = Date().timeIntervalSince(inspectionStarted)
            let failures = checked.filter { $0.severity == .failure }.count
            let reviews = checked.filter { $0.severity == .review }.count
            inspectionMessage = "\(failures) 项失败 · \(reviews) 项待审阅。检查结果一致性与证据状态；实际线路及性能仍需对应观测。"
            isInspecting = false
            inspectionTask = nil
        }
    }

    nonisolated static func validateReportDestination(_ report: URL, input: URL) throws {
        let original = input.standardizedFileURL.resolvingSymlinksInPath()
        let destination = report.standardizedFileURL.resolvingSymlinksInPath()
        var aliasesInput = original.path == destination.path
        if !aliasesInput,
           let inputAttributes = try? FileManager.default.attributesOfItem(atPath: original.path),
           let reportAttributes = try? FileManager.default.attributesOfItem(atPath: destination.path),
           let inputDevice = inputAttributes[.systemNumber] as? NSNumber,
           let reportDevice = reportAttributes[.systemNumber] as? NSNumber,
           let inputFile = inputAttributes[.systemFileNumber] as? NSNumber,
           let reportFile = reportAttributes[.systemFileNumber] as? NSNumber {
            aliasesInput = inputDevice == reportDevice && inputFile == reportFile
        }
        guard !aliasesInput else {
            throw CocoaError(.fileWriteInvalidFileName, userInfo: [
                NSLocalizedDescriptionKey: "检查报告不能写入原始行程文件；请选择独立的报告路径。"
            ])
        }
    }

    private func inspectPhysicalIntervals(originals: [Train], settled: [RiddenRouteStore.DrawnRide]) async -> [RouteBatchInspection.Finding] {
        let byID = Dictionary(originals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let scopes = Dictionary(grouping: settled.filter { byID[$0.id] != nil }, by: { RouteScope(byID[$0.id]!) })
        var checked: [RouteBatchInspection.Finding] = []
        for scope in scopes.keys.sorted(by: { $0.key < $1.key }) {
            guard !Task.isCancelled else { return [] }
            guard let network = try? await DisplayNetworkCache.shared.network(scope: scope) else {
                checked.append(.init(id: "network/\(scope.key)", severity: .review, code: "network.unavailable",
                    trainID: nil, sectionIndex: nil, message: "无法读取 \(scope.key) 网络，区段身份回放尚未检查。"))
                continue
            }
            for ride in scopes[scope] ?? [] {
                let groups = Dictionary(grouping: ride.segments, by: \.segmentIndex)
                for index in groups.keys.sorted() {
                    guard let selection = groups[index]?.first?.physicalRoute,
                          !selection.intervals.isEmpty, selection.provenance != .matchedGeometry else { continue }
                    let codes = selection.intervals.map(\.code)
                    if network.directedIntervals(sectionCodes: codes, fromStationCode: selection.fromStationCode,
                        toStationCode: selection.toStationCode) != selection.intervals {
                        checked.append(.init(id: "network/\(ride.id)/\(index)", severity: .failure,
                            code: "network.interval_replay", trainID: ride.id, sectionIndex: index,
                            message: "区段身份、顺序或方向无法按当前网络和端点回放。"))
                    }
                    if selection.provenance == .database && selection.databaseProvenance == nil {
                        checked.append(.init(id: "database/\(ride.id)/\(index)", severity: .failure,
                            code: "database.provenance_missing", trainID: ride.id, sectionIndex: index,
                            message: "数据库选择缺少班次、运营日与时刻表版本来源。"))
                    }
                }
            }
        }
        return checked
    }

    func status(_ train: Train) -> String {
        if train.requiresRouteConfirmation { return "待确认物理路线" }
        guard let ride = resultsByID[train.id] else {
            return isRunning ? "等待解析" : missingResultStatus
        }
        switch ride.route {
        case .resolved: return "路线已解析"
        case .partial(let solved, let expected, _): return "部分解析 \(solved)/\(expected)"
        case .unavailable: return "路线不可用"
        case .historyDatabaseInvalid(let reason): return "历史数据不可用：\(reason)"
        }
    }

    func export(reportOnly: Bool) async throws -> Data {
        let inputs = trains
        let settled = results
        let seconds = elapsed
        let source = sourceName
        if reportOnly {
            let inspection = findings
            let inspectionState = inspectionMessage
            let states = inputs.map { diagnostic(for: $0) }
            let phase = batchPhase
            let failure = batchFailure
            let importSeconds = importElapsed
            let inspectionSeconds = inspectionElapsed
            let counters = await RiddenRouteStore.sharedWorkCounters()
            return try await Task.detached {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                return try encoder.encode(Report(schemaVersion: 2, sectionIndexBase: 0, source: source, phase: phase,
                    batchFailure: failure, elapsedSeconds: seconds, timingScope: "routeLoad",
                    importElapsedSeconds: importSeconds, inspectionElapsedSeconds: inspectionSeconds,
                    routeCacheVersion: RouteGraph.routeDrawnCacheVersion, sharedWork: counters,
                    inspectionState: inspectionState, findings: inspection, rows: states))
            }.value
        }
        var output = inputs
        let byID = Dictionary(settled.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let eligible = inputs.indices.filter { index in
            guard let ride = byID[inputs[index].id] else { return false }
            return ride.indicesAreAuthoritative && ride.route.isResolved && ride.physicalGaps.isEmpty && !ride.segments.isEmpty
                && ride.segments.allSatisfy { segment in
                    segment.temporalKind == .current && segment.physicalRoute.map {
                        $0.provenance != .matchedGeometry && !$0.intervals.isEmpty
                    } == true
                }
        }
        let scopes = Dictionary(grouping: eligible, by: { RouteScope(inputs[$0]) })
        // DisplayNetworkCache retains one scope. Grouping avoids rebuilding a
        // national network for each interleaved-region row; retain input order.
        for scope in scopes.keys.sorted(by: { $0.key < $1.key }) {
            guard let network = try? await DisplayNetworkCache.shared.network(scope: scope) else { continue }
            for inputIndex in scopes[scope] ?? [] {
                let train = inputs[inputIndex]
                guard let ride = byID[train.id] else { continue }
                // Precomputed display matches lack canonical index provenance. Only
                // production explicit/station-sequence choices can freeze new IDs.
                let groups = Dictionary(grouping: ride.segments, by: \.segmentIndex)
                var selections: [ResolvedRouteExport.Selection] = []
                for (index, parts) in groups {
                    guard let first = parts.first, first.temporalKind == .current,
                          let selected = first.physicalRoute,
                          selected.provenance != .matchedGeometry,
                          parts.allSatisfy({ $0.temporalKind == .current && $0.physicalRoute == selected })
                    else { continue }
                    selections.append(.init(sectionIndex: index,
                        fromStationCode: selected.fromStationCode, toStationCode: selected.toStationCode,
                        intervals: selected.intervals))
                }
                let projection = selections
                let exported = await Task.detached(priority: .userInitiated) {
                    // Generate a section template only when none was authored.
                    // Do not apply Tokyo preferences to the export template.
                    let template: Train
                    if train.routeSections?.isEmpty != false {
                        template = TrainValidation.normalizeExportTrain(
                            TrainValidation.restoringRouteSectionEndpointNames(train),
                            country: Region.resolved(train).code, stations: .empty)
                    } else { template = train }
                    let projected = ResolvedRouteExport.applying(to: template, selections: projection,
                                                                network: network, isComplete: true)
                    guard projected != template else { return train }
                    var result = train
                    result.routeSections = projected.routeSections
                    return result
                }.value
                output[inputIndex] = exported
            }
        }
        let exportTrains = output
        return await Task.detached(priority: .userInitiated) {
            Data(StoreOperations.stringify(StoreOperations.json(TrainStore(trains: exportTrains)), indent: 2).utf8)
        }.value
    }

    struct JourneyDiagnostic: Encodable, Sendable {
        struct Gap: Encodable, Sendable {
            let sectionIndex: Int
            let isBoundary: Bool
            let from: String?
            let to: String?
        }
        struct Part: Encodable, Sendable {
            let sectionIndex: Int
            let partIndex: Int
            let from: String?
            let to: String?
            let sourceVertexCount: Int
            let sourceCoordinates: [[Double]]
            let temporalKind: RouteGraph.TemporalKind
            let physicalSelection: RiddenRouteStore.PhysicalRouteSelection?
        }
        let id: String
        let number: String
        let origin: String
        let destination: String
        let status: String
        let expectedSectionCount: Int?
        let resolvedSectionCount: Int?
        let indicesAreAuthoritative: Bool?
        let unresolvedSections: [Gap]
        let physicalGaps: [RiddenRouteStore.PhysicalGap]
        let parts: [Part]
    }

    /// Keeps unknown canonical coverage explicit even when display geometry is available.
    func diagnostic(for train: Train) -> JourneyDiagnostic {
        let ride = resultsByID[train.id]
        var expected = ride?.expectedSectionCount
        var resolved: Int?
        var gaps: [JourneyDiagnostic.Gap] = []
        if let ride {
            switch ride.route {
            case .resolved:
                // Legacy display parts cannot establish canonical section coverage.
                resolved = ride.indicesAreAuthoritative ? Set(ride.segments.map(\.segmentIndex)).count : nil
            case .partial(let solved, let publishedExpected, let unsolved):
                expected = publishedExpected
                resolved = solved
                gaps = unsolved.map { .init(sectionIndex: $0.segmentIndex, isBoundary: $0.isBoundary,
                                            from: $0.from, to: $0.to) }
            case .unavailable(let publishedExpected): expected = publishedExpected; resolved = 0
            case .historyDatabaseInvalid: expected = nil
            }
        }
        return .init(id: train.id, number: train.number, origin: train.origin, destination: train.destination,
            status: status(train), expectedSectionCount: expected, resolvedSectionCount: resolved,
            indicesAreAuthoritative: ride?.indicesAreAuthoritative, unresolvedSections: gaps,
            physicalGaps: ride?.physicalGaps ?? [], parts: (ride?.segments ?? []).map {
                .init(sectionIndex: $0.segmentIndex, partIndex: $0.partIndex, from: $0.from, to: $0.to,
                      sourceVertexCount: $0.sourceCoordinates.count,
                      sourceCoordinates: $0.sourceCoordinates.map(\.pair),
                      temporalKind: $0.temporalKind,
                      physicalSelection: $0.physicalRoute)
            })
    }

    private struct Report: Encodable, Sendable {
        let schemaVersion: Int
        let sectionIndexBase: Int
        let source: String
        let phase: String
        let batchFailure: String?
        let elapsedSeconds: TimeInterval
        let timingScope: String
        let importElapsedSeconds: TimeInterval
        let inspectionElapsedSeconds: TimeInterval
        let routeCacheVersion: String
        let sharedWork: RiddenRouteStore.SharedWorkCounters
        let inspectionState: String
        let findings: [RouteBatchInspection.Finding]
        let rows: [JourneyDiagnostic]
    }
}
