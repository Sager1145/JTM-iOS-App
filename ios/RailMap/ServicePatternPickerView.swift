import RailCore
import SwiftUI

/// Source clocks remain visible even when route evidence is incomplete.
private struct TimetableTripDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var sources: [TrainTimetableDatabase.SourceDocument] = []
    @State private var sourceQueryFailed = false
    @State private var showsAICheck = false
    let trip: TrainTimetableDatabase.Trip
    let onUseDraft: ((TrainTimetableDatabase.Trip) -> Void)?
    private static let database = TrainTimetableDatabase.bundled()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("運転日: \(trip.serviceDate) · 日本時間")
                    Text("\(trip.origin?.station.name ?? "?") → \(trip.destination?.station.name ?? "?")")
                    if let englishName = trip.service.englishName {
                        Text(englishName).foregroundStyle(.secondary)
                    }
                    Text("ダイヤ: \(trip.timetableEditionName)")
                        .font(.caption).foregroundStyle(.secondary)
                    if !trip.canApplyToRouteEditor {
                        Text(trip.timetableCompleteness == .conflict
                             ? "資料競合があるため、下書きへ取り込めません"
                             : "全経路は未確認です。掲載された停車駅・時刻を下書きへ取り込めます")
                            .foregroundStyle(.orange)
                    }
                    if trip.factCompleteness["stops"] != .verified {
                        Text("資料に掲載された駅のみ表示しています。全停車駅の情報は未確認です")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if onUseDraft != nil, trip.timetableCompleteness != .conflict,
                       trip.passengerStops.count >= 2 {
                        Button("掲載時刻を編集用の下書きにする") { onUseDraft?(trip) }
                            .accessibilityIdentifier("timetableUseDraft-\(trip.id)")
                        Text("掲載駅だけを取り込みます。未掲載の停車駅と経路は編集画面で確認してください。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button("AIで公表時刻を照合") { showsAICheck = true }
                        .accessibilityIdentifier("timetableAICheck-\(trip.id)")
                }
                Section("停車駅・公表時刻") {
                    ForEach(trip.stops) { stop in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(stop.station.name).font(.headline)
                            if stop.callType == "pass" {
                                Text("レ · 通過").foregroundStyle(.secondary)
                            } else {
                                Text("着 \(clock(stop.arrivalTime, seconds: stop.arrivalSeconds))")
                                Text("発 \(clock(stop.departureTime, seconds: stop.departureSeconds))")
                            }
                            if !stop.isPassengerCall && stop.callType != "pass" {
                                Text("旅客停車ではありません").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .monospacedDigit()
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("timetableStop-\(stop.sequence)")
                        ForEach(trip.timetableSymbols.filter { $0.afterStopSequence == stop.sequence }) { row in
                            HStack {
                                Text(row.stationName).font(.headline)
                                Spacer()
                                Text(row.symbol)
                                    .font(.body.monospaced())
                                    .accessibilityLabel(row.symbol == "レ" ? "通過" : "この列車は経由しません")
                            }
                            .foregroundStyle(.secondary)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("timetableSymbol-\(row.id)")
                        }
                    }
                }
                Section("確認状況") {
                    ForEach(trip.factCompleteness.keys.sorted(), id: \.self) { key in
                        LabeledContent(dimension(key), value: status(trip.factCompleteness[key]))
                    }
                }
                Section("出典") {
                    if sourceQueryFailed {
                        Text("出典を読み込めませんでした").foregroundStyle(.secondary)
                    }
                    ForEach(sources) { source in
                        VStack(alignment: .leading, spacing: 5) {
                            if let url = URL(string: source.urlOrLocator),
                               ["https", "http"].contains(url.scheme ?? "") {
                                Link(source.title, destination: url)
                            } else {
                                Text(source.title)
                            }
                            Text(source.publisher).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .accessibilityIdentifier("timetableDetailList")
            .navigationTitle("\(trip.displayName) \(trip.publicNumber ?? trip.trainNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .task {
                do {
                    guard let database = Self.database else {
                        sourceQueryFailed = true
                        return
                    }
                    sources = try database.sources(for: trip)
                } catch {
                    sourceQueryFailed = true
                }
            }
            .sheet(isPresented: $showsAICheck) {
                TimetableAICheckView(trip: trip, sources: sources)
            }
        }
    }

    private func clock(_ source: String?, seconds: Int?) -> String {
        guard let source else { return "掲載なし" }
        guard let seconds, seconds >= 86400,
              let civilDate = Dates.addDays(trip.serviceDate, seconds / 86400)
        else { return source }
        return "\(source)（\(civilDate)）"
    }

    private func status(_ coverage: TrainTimetableDatabase.Coverage?) -> String {
        switch coverage {
        case .verified: "確認済み"
        case .partial: "一部確認"
        case .conflict: "資料競合"
        case .notApplicable: "対象外"
        default: "未確認"
        }
    }

    private func dimension(_ key: String) -> String {
        ["identity": "列車の識別", "train_number": "列車番号", "operator": "運行会社",
         "validity_calendar": "運転日", "origin_destination": "始発・終着", "stops": "停車駅",
         "times": "時刻", "route_lines": "経路", "station_refs": "駅の識別", "provenance": "出典"][key]
            ?? "その他の資料"
    }
}

/// Read-only research result. The published timetable stays intact until the
/// reader explicitly changes the journey draft in the editor.
private struct TimetableAICheckView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let trip: TrainTimetableDatabase.Trip
    let sources: [TrainTimetableDatabase.SourceDocument]
    @State private var auth = ChatGPTSubscriptionAuth.shared
    @State private var service: ChatGPTSubscriptionService?
    @State private var models: [ChatGPTSubscriptionProtocol.Model] = []
    @State private var selectedModel = ""
    @State private var answer = ""
    @State private var failure: String?
    @State private var isWorking = false
    @State private var activeTask: Task<Void, Never>?
    @State private var ownsLogin = false

    private var prompt: String {
        let calls = trip.stops.map { stop in
            "\(stop.station.name): 着 \(stop.arrivalTime ?? "未掲載") / 発 \(stop.departureTime ?? "未掲載")"
        }.joined(separator: "\n")
        let citations = sources.map { "\($0.publisher): \($0.urlOrLocator)" }.joined(separator: "\n")
        return """
        日本の鉄道の公表時刻表を照合してください。対象は \(trip.serviceDate) の \(trip.displayName) \(trip.publicNumber ?? trip.trainNumber) です。
        以下はアプリに保存された掲載時刻です。公式情報と各行を比較し、確認できた差分、追加の停車駅、運転日、資料の版を出典URL付きで示してください。確認できない値は不明と記してください。実際の運行時刻を予定時刻から推定しないでください。
        ダイヤ版: \(trip.timetableEditionName) (\(trip.timetableVersionID))
        \(calls)
        登録済み資料:
        \(citations.isEmpty ? "なし" : citations)
        """
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("照合対象") {
                    Text("\(trip.displayName) \(trip.publicNumber ?? trip.trainNumber) · \(trip.serviceDate)")
                    Text("AIの回答は提案です。公表資料を確認してから編集画面で時刻を変更してください。")
                        .font(.footnote).foregroundStyle(.secondary)
                    ShareLink(item: prompt) { Label("照合依頼を共有", systemImage: "square.and.arrow.up") }
                    Button("ChatGPTを開く") { openURL(URL(string: "https://chatgpt.com/")!) }
                    DisclosureGroup("照合依頼") {
                        Text(prompt).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
                Section("AI照合") {
                    if auth.isSignedIn {
                        if !models.isEmpty {
                            Picker("モデル", selection: $selectedModel) {
                                ForEach(models) { model in Text(model.displayName).tag(model.id) }
                            }
                        }
                        Button("照合を実行") { activeTask = Task { await check() } }
                            .disabled(isWorking || selectedModel.isEmpty)
                    } else {
                        Button("ChatGPTにサインイン") { activeTask = Task { await signIn() } }
                            .disabled(isWorking)
                        if let code = auth.userCode, auth.isSigningIn {
                            Text(code).font(.title2.monospaced()).textSelection(.enabled)
                            Button("認証ページを開く") { openURL(auth.loginURL) }
                        }
                    }
                    if isWorking { ProgressView() }
                    if let failure { Text(failure).foregroundStyle(.red) }
                    if !answer.isEmpty { Text(answer).textSelection(.enabled) }
                }
            }
            .navigationTitle("時刻表のAI照合")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("閉じる") { dismiss() }
            } }
            .task { if auth.isSignedIn { await loadModels() } }
            .onDisappear {
                activeTask?.cancel()
                if ownsLogin { auth.cancelLogin() }
            }
        }
    }

    @MainActor private func loadModels() async {
        do {
            if service == nil { service = ChatGPTSubscriptionService(auth: .shared) }
            models = try await service!.models()
            selectedModel = models.first?.id ?? ""
        } catch { failure = error.localizedDescription }
    }

    @MainActor private func signIn() async {
        isWorking = true
        defer { isWorking = false }
        ownsLogin = true
        defer { ownsLogin = false }
        do { try await auth.login(); await loadModels() }
        catch { failure = error.localizedDescription }
    }

    @MainActor private func check() async {
        guard let service else { return }
        isWorking = true
        failure = nil
        defer { isWorking = false }
        do { answer = try await service.complete(prompt: prompt, model: selectedModel) }
        catch { failure = error.localizedDescription }
    }
}

/// Presented from the ride editor's stops section so a JP limited-express
/// stop pattern can prefill the draft's stop list. Tapping a row hands the
/// chosen pattern back to the caller and dismisses; the resulting stops stay
/// ordinary, editable rows afterwards.
struct ServicePatternPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let region: String
    @Environment(AppLocalization.self) private var localization
    @State private var rideDate: String?
    let onSelectDate: ((String?) -> Void)?
    @State private var showsDateEditor = false
    @State private var isLoadingTimetable = false
    let onSelectTrip: ((TrainTimetableDatabase.Trip) -> Void)?
    let onSelectDraft: ((TrainTimetableDatabase.Trip) -> Void)?
    let onSelect: (TrainServicePatterns.Pattern, Bool) -> Void

    @State private var query = ""
    @State private var showsAllHistory = false
    @State private var companyFilter: String?
    @State private var lineFilter: String?
    @State private var pendingSelection: Selection?
    @State private var timetablePatterns: [TrainServicePatterns.Pattern] = []
    @State private var timetableDetails: [String: TimetableDetail] = [:]
    @State private var timetableTripsByPatternID: [String: TrainTimetableDatabase.Trip] = [:]
    @State private var incompleteTimetableTrips: [TrainTimetableDatabase.Trip] = []
    @State private var timetableCoverage: TrainTimetableDatabase.Coverage?
    @State private var timetableTripCount = 0
    @State private var incompleteTimetableTripCount = 0
    @State private var timetableQueryFailed = false
    @State private var inspectedTrip: TrainTimetableDatabase.Trip?

    private static let timetableDatabase = TrainTimetableDatabase.bundled()
    private static let jrAndNationalOperatorNames: Set<String> = [
        "北海道旅客鉄道", "東日本旅客鉄道", "東海旅客鉄道",
        "西日本旅客鉄道", "四国旅客鉄道", "九州旅客鉄道",
        "日本国有鉄道", "国鉄",
    ]

    init(
        region: String, rideDate: String?,
        onSelectDate: ((String?) -> Void)? = nil,
        onSelectTrip: ((TrainTimetableDatabase.Trip) -> Void)? = nil,
        onSelectDraft: ((TrainTimetableDatabase.Trip) -> Void)? = nil,
        onSelect: @escaping (TrainServicePatterns.Pattern, Bool) -> Void
    ) {
        self.region = region
        _rideDate = State(initialValue: rideDate)
        self.onSelectDate = onSelectDate
        self.onSelectTrip = onSelectTrip
        self.onSelectDraft = onSelectDraft
        self.onSelect = onSelect
    }

    private struct Selection: Identifiable {
        let pattern: TrainServicePatterns.Pattern
        let reversed: Bool
        var id: String { "\(pattern.id):\(reversed)" }
    }

    private struct TimetableDetail: Sendable {
        let serviceName: String
        let departureTime: String?
    }

    private var legacyMatches: [TrainServicePatterns.Pattern] {
        TrainServicePatterns.search("", region: region, filter: .init(
            company: companyFilter, status: .any, line: lineFilter, rideDate: rideDate))
            .filter { TimetableSearch(query).matches($0) }
    }

    private var exactMatches: [TrainServicePatterns.Pattern] {
        let search = TimetableSearch(query)
        return timetablePatterns.filter { pattern in
            if let companyFilter, pattern.companyLabel != companyFilter { return false }
            if let lineFilter {
                let line = TrainServiceBranding.canonicalLineName(lineFilter)
                guard pattern.lines.contains(where: {
                    TrainServiceBranding.canonicalLineName($0) == line
                }) else { return false }
            }
            if let trip = timetableTripsByPatternID[pattern.id] { return search.matches(trip) }
            return search.matches(pattern)
        }
    }

    private var incompleteTripMatches: [TrainTimetableDatabase.Trip] {
        let search = TimetableSearch(query)
        return incompleteTimetableTrips.filter { trip in
            if let companyFilter,
               !trip.operatorSegments.map(\.displayName).contains(companyFilter) { return false }
            if let lineFilter {
                let line = TrainServiceBranding.canonicalLineName(lineFilter)
                guard trip.lineSegments.contains(where: {
                    TrainServiceBranding.canonicalLineName($0.lineName) == line
                }) else { return false }
            }
            return search.matches(trip)
        }
    }

    private var knownMatches: [TrainServicePatterns.Pattern] {
        guard rideDate != nil else { return legacyMatches }
        if !timetablePatterns.isEmpty { return exactMatches }
        if timetableCoverage == .verified && timetableTripCount == 0 { return [] }
        return []
    }

    private var unknownMatches: [TrainServicePatterns.Pattern] {
        guard rideDate != nil else { return [] }
        return legacyMatches.filter { pattern in
            guard let rideDate else { return false }
            return pattern.applicability(on: rideDate) != .notApplicable
                && (shouldShowLegacyFallback || !isJROrNationalRailway(pattern))
        }
    }

    private var outsideMatches: [TrainServicePatterns.Pattern] {
        guard let rideDate, showsAllHistory else { return [] }
        return legacyMatches.filter { $0.applicability(on: rideDate) == .notApplicable }
    }

    private var shouldShowLegacyFallback: Bool {
        guard rideDate != nil else { return false }
        return timetableQueryFailed
            || timetableCoverage != .verified
            || incompleteTimetableTripCount > 0
            || (timetableTripCount > 0 && timetablePatterns.isEmpty)
    }

    private var companyLabels: [String] {
        Array(Set(
            TrainServicePatterns.companyLabels(region: region)
                + timetablePatterns.map(\.companyLabel).filter { !$0.isEmpty }
                + incompleteTimetableTrips.flatMap { $0.operatorSegments.map(\.displayName) }
        )).sorted()
    }

    private var lineNames: [String] {
        Array(Set(
            TrainServicePatterns.lineNames(region: region) + timetablePatterns.flatMap(\.lines)
                + incompleteTimetableTrips.flatMap { $0.lineSegments.map(\.lineName) }
        )).sorted()
    }

    private var groups: [(name: String, companyLabel: String, patterns: [TrainServicePatterns.Pattern])] {
        var order: [String] = []
        var byName: [String: [TrainServicePatterns.Pattern]] = [:]
        for pattern in knownMatches {
            let name = timetableDetails[pattern.id]?.serviceName ?? pattern.name
            if byName[name] == nil { order.append(name) }
            byName[name, default: []].append(pattern)
        }
        return order.map { name in
            (name: name, companyLabel: byName[name]?.first?.companyLabel ?? "", patterns: byName[name] ?? [])
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { showsDateEditor.toggle() } label: {
                        Label(localization.editorText("ios.editor.timetableBrowseDate")
                              + (rideDate.map { ": " + $0 } ?? ""), systemImage: "calendar")
                    }
                    .accessibilityIdentifier("servicePatternDateEditor")
                    if showsDateEditor {
                        EditorDateField(
                            title: localization.editorText("ios.editor.timetableBrowseDate"),
                            date: $rideDate, region: Region(rawValue: region) ?? .jp,
                            accessibilityID: "servicePatternDateInput")
                        Button(localization.editorText("ios.editor.timetableAnyDate")) { rideDate = nil }
                    }
                    Text(localization.editorText("ios.editor.timetableSearchHelp"))
                        .font(.caption).foregroundStyle(.secondary)
                    if isLoadingTimetable {
                        ProgressView(localization.editorText("ios.editor.timetableSearching"))
                    }
                    if let rideDate {
                        Toggle("すべての履歴を表示", isOn: $showsAllHistory)
                            .accessibilityIdentifier("servicePatternHistoryFilter")
                        Text("乗車日: \(rideDate)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("乗車日を設定すると、その日に有効なパターンを表示します")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let rideDate {
                        timetableStatus(date: rideDate)
                    }

                    HStack {
                        Menu {
                            Button("すべての会社") { companyFilter = nil }
                            ForEach(companyLabels, id: \.self) { label in
                                Button(label) { companyFilter = label }
                            }
                        } label: {
                            Label(companyFilter ?? "すべての会社", systemImage: "building.2")
                        }
                        .accessibilityIdentifier("servicePatternCompanyFilter")

                        Spacer()

                        Menu {
                            Button("すべての路線") { lineFilter = nil }
                            ForEach(lineNames, id: \.self) { line in
                                Button(line) { lineFilter = line }
                            }
                        } label: {
                            Label(lineFilter ?? "すべての路線", systemImage: "arrow.triangle.swap")
                        }
                        .accessibilityIdentifier("servicePatternLineFilter")
                    }
                }
                ForEach(groups, id: \.name) { group in
                    Section(header: Text("\(group.name) · \(group.companyLabel)")) {
                        ForEach(group.patterns) { pattern in
                            patternRow(pattern)
                        }
                    }
                }
                if !incompleteTripMatches.isEmpty {
                    Section(localization.editorText("ios.editor.timetablePublishedDraft")) {
                        ForEach(incompleteTripMatches) { trip in
                            VStack(alignment: .leading, spacing: 8) {
                                incompleteTripRow(trip)
                                Button("停車駅・時刻を確認") { inspectedTrip = trip }
                                    .buttonStyle(.borderless)
                                    .accessibilityIdentifier("timetableDetails-\(trip.id)")
                            }
                        }
                    }
                }
                if !unknownMatches.isEmpty {
                    Section("互換パターン（当日ダイヤ未確認）") {
                        ForEach(unknownMatches) { pattern in patternRow(pattern) }
                    }
                }
                if !outsideMatches.isEmpty {
                    Section("乗車日の対象外・有効期間未確認") {
                        ForEach(outsideMatches) { pattern in patternRow(pattern) }
                    }
                }
                if !isLoadingTimetable && groups.isEmpty && incompleteTripMatches.isEmpty
                    && unknownMatches.isEmpty && outsideMatches.isEmpty
                {
                    Text(timetableCoverage == .verified && timetableTripCount == 0
                         ? "この日は運行予定の特急がありません"
                         : "該当する列車パターンが見つかりません")
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("servicePatternList")
            .navigationTitle("列車パターンから入力")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: Text(localization.editorText("ios.editor.timetableSearchPrompt")))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
            .task(id: "\(region):\(rideDate ?? "")") { await loadTimetable() }
            .sheet(item: $inspectedTrip) { trip in
                TimetableTripDetailView(trip: trip, onUseDraft: onSelectDraft == nil ? nil : { chosen in
                    onSelectDate?(chosen.serviceDate)
                    onSelectDraft?(chosen)
                    inspectedTrip = nil
                    dismiss()
                })
            }
            .confirmationDialog(
                "このパターンは乗車日の対象外です。適用しますか？",
                isPresented: Binding(get: { pendingSelection != nil },
                                     set: { if !$0 { pendingSelection = nil } }),
                titleVisibility: .visible
            ) {
                Button("確認して適用") {
                    guard let selection = pendingSelection else { return }
                    apply(selection)
                }
                Button("キャンセル", role: .cancel) { pendingSelection = nil }
            }
        }
    }

    private func patternRow(_ pattern: TrainServicePatterns.Pattern) -> some View {
        HStack(spacing: 0) {
            Button { select(pattern, reversed: false) } label: { row(for: pattern) }
            // A timetable trip has a direction, train number, and times of its
            // own. Reversing it would fabricate a train that the database does
            // not contain. Legacy route summaries keep their direction toggle.
            if !pattern.id.hasPrefix("timetable:") {
                Button { select(pattern, reversed: true) } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("逆方向: \(pattern.destination) → \(pattern.origin)")
            }
        }
        .frame(minHeight: 44)
    }

    private func select(_ pattern: TrainServicePatterns.Pattern, reversed: Bool) {
        if let trip = timetableTripsByPatternID[pattern.id], let onSelectTrip {
            onSelectDate?(trip.serviceDate)
            onSelectTrip(trip)
            dismiss()
            return
        }
        let selection = Selection(pattern: pattern, reversed: reversed)
        if let rideDate, pattern.applicability(on: rideDate) == .notApplicable {
            pendingSelection = selection
        } else {
            apply(selection)
        }
    }

    private func apply(_ selection: Selection) {
        onSelectDate?(rideDate)
        onSelect(selection.pattern, selection.reversed)
        pendingSelection = nil
        dismiss()
    }

    private func row(for pattern: TrainServicePatterns.Pattern) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(pattern.label)
                if pattern.confidence == "low" {
                    Text("要確認")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .clipShape(Capsule())
                }
                if let rideDate, let applicability = pattern.applicability(on: rideDate),
                   applicability != .applicable {
                    Text(applicability == .unknown ? "有効期間未確認" : "乗車日の対象外")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.2))
                        .clipShape(Capsule())
                }
                if pattern.completeness.stops != .complete
                    || pattern.completeness.lines != .complete
                    || pattern.completeness.validity != .complete
                {
                    Text("停站\(mark(pattern.completeness.stops)) 路線\(mark(pattern.completeness.lines)) 日付\(mark(pattern.completeness.validity))")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            Text("\(pattern.origin) → \(pattern.destination) · \(pattern.stops.count)駅")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let departure = timetableDetails[pattern.id]?.departureTime {
                Text("始発 \(departure)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if pattern.validFrom != nil || pattern.validUntil != nil {
                Text(validityCaption(for: pattern))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !pattern.lines.isEmpty {
                Text("経由: \(pattern.lines.joined(separator: "・"))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !pattern.optionalStops.isEmpty {
                Text("一部列車停車: \(pattern.optionalStops.joined(separator: "、"))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func incompleteTripRow(_ trip: TrainTimetableDatabase.Trip) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text([trip.service.canonicalName, trip.publicNumber ?? trip.trainNumber]
                .filter { !$0.isEmpty }.joined(separator: " "))
            if let englishName = trip.service.englishName {
                Text(englishName).font(.caption).foregroundStyle(.secondary)
            }
            Text("\(trip.origin?.station.name ?? "?") → \(trip.destination?.station.name ?? "?") · \(trip.factCompleteness["stops"] == .verified ? "" : "掲載")\(trip.passengerStops.count)駅")
                .font(.caption).foregroundStyle(.secondary)
            if let departure = trip.origin?.departureTime ?? trip.origin?.arrivalTime {
                Text("始発 \(departure)").font(.caption2).foregroundStyle(.secondary)
            }
            Text(trip.timetableEditionName).font(.caption2).foregroundStyle(.secondary)
            let missing = [
                "operator": "運行会社", "validity_calendar": "運転日", "stops": "停車駅",
                "times": "時刻", "route_lines": "経路", "station_refs": "駅参照",
                "provenance": "出典",
            ].compactMap { key, label in
                trip.factCompleteness[key] == .verified ? nil : label
            }
            Text("未確認: \(missing.joined(separator: "・"))")
                .font(.caption2).foregroundStyle(.orange)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("timetableIncompleteTrip-\(trip.id)")
        .accessibilityHint(localization.editorText("ios.editor.timetableMatchNote"))
    }

    private func validityCaption(for pattern: TrainServicePatterns.Pattern) -> String {
        let from = pattern.validFrom ?? "?"
        if let until = pattern.validUntil {
            return "\(from)〜\(until)未満"
        }
        return "\(from)〜"
    }

    private func mark(_ level: TrainServicePatterns.Pattern.Level) -> String {
        switch level {
        case .complete: "✓"
        case .partial: "△"
        case .missing: "?"
        }
    }

    @ViewBuilder private func timetableStatus(date: String) -> some View {
        if timetableQueryFailed || Self.timetableDatabase == nil {
            Text("当日ダイヤDBを利用できないため、互換パターンを表示しています")
                .font(.caption).foregroundStyle(.orange)
        } else if timetableCoverage == .conflict {
            Text("\(date) の当日ダイヤには未解決の資料競合があります。互換パターンも別に表示します")
                .font(.caption).foregroundStyle(.orange)
        } else if timetableCoverage == .verified && timetableTripCount == 0 {
            Text("\(date) はJR・国鉄の運行予定特急がありません。私鉄の互換パターンは引き続き表示します")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            if timetableCoverage == .partial || timetableCoverage == .unknown {
                Text("\(date) の当日ダイヤは調査途中です。他の列車が未掲載の可能性があります")
                    .font(.caption).foregroundStyle(.orange)
                    .accessibilityIdentifier("timetableInventoryIncomplete")
            }
            if incompleteTimetableTripCount > 0 {
                Text("当日ダイヤ \(timetableTripCount)本中 \(incompleteTimetableTripCount)本は全経路未確認です。掲載駅・時刻を下書きとして確認できます（資料競合を除く）")
                    .font(.caption).foregroundStyle(.orange)
                    .accessibilityIdentifier("timetableTripsNotApplicable")
            }
            if timetableCoverage == .verified && incompleteTimetableTripCount == 0
                && !timetablePatterns.isEmpty {
                Text("\(date) の列車番号別ダイヤ")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @MainActor private func loadTimetable() async {
        isLoadingTimetable = true
        defer { if !Task.isCancelled { isLoadingTimetable = false } }
        timetablePatterns = []
        timetableDetails = [:]
        timetableTripsByPatternID = [:]
        incompleteTimetableTrips = []
        timetableCoverage = nil
        timetableTripCount = 0
        incompleteTimetableTripCount = 0
        timetableQueryFailed = false
        guard region == "jp", let rideDate, let database = Self.timetableDatabase else { return }

        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                let trips = try database.trips(on: rideDate)
                let coverage = try database.coverage(on: rideDate)
                return (trips, coverage)
            }.value
            guard !Task.isCancelled else { return }
            timetableCoverage = loaded.1.status
            timetableTripCount = loaded.0.count
            incompleteTimetableTripCount = loaded.0.filter { !$0.canApplyToRouteEditor }.count
            for trip in loaded.0 {
                guard let pattern = trip.compatibilityPattern() else {
                    incompleteTimetableTrips.append(trip)
                    continue
                }
                timetablePatterns.append(pattern)
                timetableTripsByPatternID[pattern.id] = trip
                timetableDetails[pattern.id] = TimetableDetail(
                    serviceName: trip.service.canonicalName,
                    departureTime: trip.origin?.departureTime ?? trip.origin?.arrivalTime)
            }
        } catch {
            guard !Task.isCancelled else { return }
            timetableQueryFailed = true
        }
    }

    private func isJROrNationalRailway(_ pattern: TrainServicePatterns.Pattern) -> Bool {
        pattern.company.split(separator: "/").contains { component in
            Self.jrAndNationalOperatorNames.contains(
                component.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
