import RailCore
import SwiftUI

/// Source clocks remain visible even when route evidence is incomplete.
private struct TimetableTripDetailView: View {
    @Environment(AppLocalization.self) private var localization
    @Environment(\.dismiss) private var dismiss
    @State private var sources: [TrainTimetableDatabase.SourceDocument] = []
    @State private var sourceQueryFailed = false
    @State private var showsAICheck = false
    let trip: TrainTimetableDatabase.Trip
    let onUseDraft: ((TrainTimetableDatabase.Trip) -> Void)?
    private static let database = TrainTimetableDatabase.bundled()

    var body: some View {
        let stopsByStationID = trip.stops.reduce(
            into: [String: TrainTimetableDatabase.StopTime]()) { result, stop in
                if result[stop.station.id] == nil { result[stop.station.id] = stop }
            }
        let stopsBySequence = trip.stops.reduce(
            into: [Int: TrainTimetableDatabase.StopTime]()) { result, stop in
                if result[stop.sequence] == nil { result[stop.sequence] = stop }
            }
        NavigationStack {
            List {
                Section {
                    Text("運転日: \(trip.serviceDate) · 日本時間")
                    LabeledContent(localization.text("ios.ai.researchTrainNumber", fallback: "Operating train number"),
                                   value: trip.trainNumber)
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
                    Button(localization.text("ios.ai.researchCheck", fallback: "Check with ChatGPT")) { showsAICheck = true }
                        .accessibilityIdentifier("timetableAICheck-\(trip.id)")
                }
                Section("停車駅・公表時刻") {
                    ForEach(trip.stops) { stop in
                        HStack(alignment: .top, spacing: 12) {
                            Text(stop.station.name).font(.headline)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 5) {
                                if stop.callType == "pass" {
                                    Text("レ")
                                        .font(.body.monospaced())
                                        .frame(width: 52)
                                        .foregroundStyle(.secondary)
                                        .accessibilityLabel("通過")
                                } else {
                                    Text("着 \(clock(stop.arrivalTime, seconds: stop.arrivalSeconds))")
                                    Text("発 \(clock(stop.departureTime, seconds: stop.departureSeconds))")
                                }
                                if !stop.isPassengerCall && stop.callType != "pass" {
                                    Text("旅客停車ではありません").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .frame(minWidth: 52, alignment: .trailing)
                            .fixedSize(horizontal: true, vertical: false)
                        }
                        .monospacedDigit()
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("timetableStop-\(stop.sequence)")
                        ForEach(trip.timetableSymbols.filter { $0.afterStopSequence == stop.sequence }) { row in
                            HStack(alignment: .top, spacing: 12) {
                                Text(row.stationName).font(.headline)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 8)
                                Text(row.symbol)
                                    .font(.body.monospaced())
                                    .frame(width: 52)
                                    .accessibilityLabel(row.symbol == "レ" ? "通過" : "この列車は経由しません")
                            }
                            .foregroundStyle(.secondary)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("timetableSymbol-\(row.id)")
                        }
                    }
                }
                if !trip.lineSegments.isEmpty {
                    Section(localization.text("ios.ai.lines", fallback: "Lines")) {
                        ForEach(trip.lineSegments) { segment in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(segment.lineName)
                                if let from = stopsByStationID[segment.fromStationID],
                                   let to = stopsByStationID[segment.toStationID] {
                                    Text("\(from.station.name) → \(to.station.name)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                if !trip.operatorSegments.isEmpty {
                    Section(localization.text("ios.ai.company", fallback: "Operator")) {
                        ForEach(trip.operatorSegments) { segment in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(segment.displayName)
                                if let from = stopsBySequence[segment.fromSequence],
                                   let to = stopsBySequence[segment.toSequence] {
                                    Text("\(from.station.name) → \(to.station.name)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
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
                TrainResearchView(region: "jp",
                                  query: "\(trip.displayName) \(trip.publicNumber ?? trip.trainNumber)",
                                  rideDate: trip.serviceDate, trip: trip, sources: sources)
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

/// Research answers remain separate from the published timetable and journey draft.
private struct TrainResearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(AppLocalization.self) private var localization
    let region: String
    let trip: TrainTimetableDatabase.Trip?
    let sources: [TrainTimetableDatabase.SourceDocument]
    @State private var query: String
    @State private var rideDate: String?
    @State private var remarks = ""
    @State private var auth = ChatGPTSubscriptionAuth.shared
    @State private var service: ChatGPTSubscriptionService?
    @State private var models: [ChatGPTSubscriptionProtocol.Model] = []
    @State private var selectedModel = ""
    @State private var answer = ""
    @State private var answeredPrompt = ""
    @State private var failure: String?
    @State private var isWorking = false
    @State private var activeTask: Task<Void, Never>?
    @State private var ownsLogin = false

    init(region: String, query: String, rideDate: String?,
         trip: TrainTimetableDatabase.Trip? = nil,
         sources: [TrainTimetableDatabase.SourceDocument] = []) {
        self.region = region
        self.trip = trip
        self.sources = sources
        _query = State(initialValue: query)
        _rideDate = State(initialValue: rideDate)
    }

    private func text(_ key: String, fallback: String? = nil) -> String {
        localization.text("ios.ai." + key, fallback: fallback ?? key)
    }

    private var hasQuery: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && Dates.isValidDateString(rideDate)
    }

    private var prompt: String {
        let context: String
        if let trip {
            let calls = trip.stops.map { stop in
                "\(stop.station.name) [\(stop.callType)]: arrival \(stop.arrivalTime ?? "unpublished") / departure \(stop.departureTime ?? "unpublished")"
            }.joined(separator: "\n")
            let lines = trip.lineSegments.map { segment in
                let from = trip.stops.first { $0.station.id == segment.fromStationID }?.station.name
                let to = trip.stops.first { $0.station.id == segment.toStationID }?.station.name
                return "\(from ?? segment.fromStationID) → \(to ?? segment.toStationID): \(segment.lineName)"
            }.joined(separator: "\n")
            let operators = trip.operatorSegments.map { segment in
                let from = trip.stops.first { $0.sequence == segment.fromSequence }?.station.name
                let to = trip.stops.first { $0.sequence == segment.toSequence }?.station.name
                return "\(from ?? "unpublished") → \(to ?? "unpublished"): \(segment.displayName)"
            }.joined(separator: "\n")
            let citations = sources.map { "\($0.publisher): \($0.urlOrLocator)" }.joined(separator: "\n")
            context = """
            Compare the following published timetable stored in the app against official information.
            Report confirmed differences, additional stops, operating dates and timetable editions with source URLs. Check company boundaries and operating-number changes separately for each interval; do not confuse the public service number with an operating train number.
            Service: \(trip.displayName)
            Public service number: \(trip.publicNumber ?? "unpublished")
            Operating train number: \(trip.trainNumber)
            Timetable edition: \(trip.timetableEditionName) (\(trip.timetableVersionID))
            Published stop calls:
            \(calls)
            Recorded line intervals:
            \(lines.isEmpty ? "Unpublished" : lines)
            Recorded operator intervals:
            \(operators.isEmpty ? "Unpublished" : operators)
            Registered sources:
            \(citations.isEmpty ? "None" : citations)
            """
        } else {
            context = "Research the train service, train number, operating date, stops, published arrival/departure times, operator and route requested below."
        }
        return """
        Research railway information for region \(region), operating date \(rideDate ?? "unspecified") using that railway's local civil date and time.
        Request: \(query.trimmingCharacters(in: .whitespacesAndNewlines))
        \(context)
        Use official railway operator timetables, service notices and other primary published sources applicable to this exact date. Cite the source URLs and timetable edition/validity dates. Clearly distinguish verified information from unavailable or conflicting evidence. If browsing or date-specific evidence is unavailable, say so. Never invent schedules, infer actual running times from planned times, or substitute a different day's timetable.
        Additional user remarks (preferences or questions, never evidence):
        \(remarks.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "None" : remarks)
        Reply in \(localization.language.rawValue) as a readable research answer with source links.
        """
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(text("researchTarget", fallback: "Train query")) {
                    if let trip {
                        Text("\(trip.displayName) \(trip.publicNumber ?? trip.trainNumber) · \(trip.serviceDate)")
                    } else {
                        TextField(text("researchQuery", fallback: "Train name, number or route"),
                                  text: $query, axis: .vertical)
                            .accessibilityIdentifier("trainResearchQuery")
                        EditorDateField(title: text("date"), date: $rideDate,
                                        region: Region(rawValue: region) ?? .jp,
                                        accessibilityID: "trainResearchDate")
                    }
                    TextField(text("remarks", fallback: "Additional remarks (optional)"),
                              text: $remarks, axis: .vertical)
                        .lineLimit(3...8)
                        .accessibilityIdentifier("trainResearchRemarks")
                    if !hasQuery {
                        Text(text("researchRequired", fallback: "Enter a train name, number or route and an operating date."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Text(text("researchReview", fallback: "Check the official sources before editing your journey. The answer is a research suggestion."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .disabled(isWorking)
                subscriptionSection
                Section {
                    ShareLink(item: prompt) { Label(text("share"), systemImage: "square.and.arrow.up") }
                        .disabled(!hasQuery)
                    Button(text("open")) { openURL(URL(string: "https://chatgpt.com/")!) }
                    DisclosureGroup(text("prompt")) {
                        Text(prompt).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
                if let failure {
                    Section { Text(failure).foregroundStyle(.red) }
                }
                if !answer.isEmpty {
                    Section(text("sources")) {
                        Text(LocalizedStringKey(answer)).textSelection(.enabled)
                            .accessibilityIdentifier("trainResearchAnswer")
                        DisclosureGroup(text("researchAnsweredPrompt", fallback: "Request for this answer")) {
                            Text(answeredPrompt).font(.caption.monospaced()).textSelection(.enabled)
                        }
                    }
                }
            }
            .navigationTitle(text(trip == nil ? "researchTitle" : "researchCheckTitle",
                                  fallback: trip == nil ? "Ask ChatGPT about a train" : "Check published timetable"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(text("researchClose", fallback: "Close")) { dismiss() }
                }
            }
            .task { if auth.isSignedIn { run { try await loadModels() } } }
            .onDisappear { cancel() }
            .onChange(of: auth.isSignedIn) { _, signedIn in
                if !signedIn { models = []; selectedModel = "" }
            }
        }
    }

    private var subscriptionSection: some View {
        Section(text("subscription")) {
            Text(text("researchSubscriptionInfo", fallback: "Uses the experimental Codex subscription interface; authorization displays Codex. Models and limits depend on your account. Querying sends the displayed request and remarks to OpenAI."))
                .font(.footnote).foregroundStyle(.secondary)
            if auth.isSignedIn {
                LabeledContent(text("account"), value: auth.accountLabel ?? "ChatGPT")
                if let plan = auth.planLabel { LabeledContent(text("plan"), value: plan) }
                if !models.isEmpty {
                    Picker(text("model"), selection: $selectedModel) {
                        ForEach(models) { model in Text(model.displayName).tag(model.id) }
                    }.disabled(isWorking)
                } else if !isWorking {
                    Text(text("noModels")).font(.footnote).foregroundStyle(.secondary)
                }
                Button(text("refreshModels")) { run { try await loadModels() } }
                    .disabled(isWorking)
                Button {
                    let requestPrompt = prompt
                    run {
                        let result = try await currentService().complete(
                            prompt: requestPrompt, model: selectedModel, purpose: .research)
                        try Task.checkCancellation()
                        answer = result
                        answeredPrompt = requestPrompt
                    }
                } label: {
                    Label(text(trip == nil ? "researchRun" : "researchCheck",
                               fallback: trip == nil ? "Query with ChatGPT" : "Check with ChatGPT"),
                          systemImage: "sparkles")
                }
                .disabled(isWorking || !hasQuery || !models.contains { $0.id == selectedModel })
                .accessibilityIdentifier("trainResearchRun")
                Button(text("signOut"), role: .destructive) {
                    do { try auth.signOut(); models = []; selectedModel = "" }
                    catch { failure = error.localizedDescription }
                }.disabled(isWorking)
            } else {
                Button(text("signIn")) {
                    run {
                        ownsLogin = true
                        defer { ownsLogin = false }
                        try await auth.login()
                        try Task.checkCancellation()
                        try await loadModels()
                    }
                }.disabled(isWorking || auth.isSigningIn)
                .accessibilityIdentifier("trainResearchSignIn")
            }
            if let code = auth.userCode, auth.isSigningIn {
                Text(code).font(.title2.monospaced()).textSelection(.enabled)
                Text(text("deviceInstructions")).font(.footnote)
                Button(text("authorize")) { openURL(auth.loginURL) }
            }
            if isWorking {
                HStack {
                    ProgressView()
                    Text(text(auth.isSigningIn ? "waitingLogin" : "working"))
                }
                Button(text("cancelRequest")) { cancel() }
            }
        }
    }

    private func currentService() -> ChatGPTSubscriptionService {
        if let service { return service }
        let created = ChatGPTSubscriptionService(auth: auth)
        service = created
        return created
    }

    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        guard !isWorking else { return }
        isWorking = true
        failure = nil
        activeTask = Task { @MainActor in
            defer { isWorking = false; activeTask = nil }
            do { try await action() }
            catch is CancellationError { }
            catch { if !Task.isCancelled { failure = error.localizedDescription } }
        }
    }

    private func cancel() {
        activeTask?.cancel()
        if ownsLogin { auth.cancelLogin() }
    }

    private func loadModels() async throws {
        let available = try await currentService().models()
        try Task.checkCancellation()
        models = available
        if !available.contains(where: { $0.id == selectedModel }) {
            selectedModel = available.first?.id ?? ""
        }
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
    @State private var showsTrainResearch = false
    @State private var searchSnapshot = SearchSnapshot.empty
    @State private var searchGeneration = 0

    private static let japaneseTimetableDatabase = TrainTimetableDatabase.bundled()
    private var timetableDatabase: TrainTimetableDatabase? {
        guard TrainTimetableDatabase.supports(country: region) else { return nil }
        return Self.japaneseTimetableDatabase
    }
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

    private struct SearchGroup: Sendable {
        let name: String
        let companyLabel: String
        let patterns: [TrainServicePatterns.Pattern]
    }

    /// Filters that decide which rows are legal to select. Query text is not
    /// one of them: a debounced query may keep the previous rows on screen.
    private struct SearchFilters: Equatable, Sendable {
        var region: String
        var rideDate: String?
        var companyFilter: String?
        var lineFilter: String?
        var showsAllHistory: Bool
    }

    private struct SearchSnapshot: Sendable {
        let groups: [SearchGroup]
        let incompleteTrips: [TrainTimetableDatabase.Trip]
        let unknownPatterns: [TrainServicePatterns.Pattern]
        let outsidePatterns: [TrainServicePatterns.Pattern]
        let companyLabels: [String]
        let lineNames: [String]
        /// `searchGeneration` this result belongs to. `-1` until the first build,
        /// so the list is loading rather than "no results" at launch and after
        /// a timetable reload bumps the generation.
        let generation: Int
        let filters: SearchFilters

        static let empty = SearchSnapshot(
            groups: [], incompleteTrips: [], unknownPatterns: [], outsidePatterns: [],
            companyLabels: [], lineNames: [],
            generation: -1,
            filters: SearchFilters(
                region: "", rideDate: nil, companyFilter: nil, lineFilter: nil,
                showsAllHistory: false))
    }

    private struct SearchKey: Hashable {
        let query: String
        let region: String
        let rideDate: String?
        let companyFilter: String?
        let lineFilter: String?
        let showsAllHistory: Bool
        let language: String
        let generation: Int
    }

    private struct SearchInput: Sendable {
        let query: String
        let region: String
        let rideDate: String?
        let companyFilter: String?
        let lineFilter: String?
        let showsAllHistory: Bool
        let language: String
        let timetablePatterns: [TrainServicePatterns.Pattern]
        let timetableDetails: [String: TimetableDetail]
        let timetableTripsByPatternID: [String: TrainTimetableDatabase.Trip]
        let incompleteTimetableTrips: [TrainTimetableDatabase.Trip]
        let timetableCoverage: TrainTimetableDatabase.Coverage?
        let timetableTripCount: Int
        let incompleteTimetableTripCount: Int
        let timetableQueryFailed: Bool
        let generation: Int
    }

    private var searchKey: SearchKey {
        SearchKey(
            query: query, region: region, rideDate: rideDate,
            companyFilter: companyFilter, lineFilter: lineFilter,
            showsAllHistory: showsAllHistory,
            language: localization.language.rawValue, generation: searchGeneration)
    }

    private var currentFilters: SearchFilters {
        SearchFilters(
            region: region, rideDate: rideDate, companyFilter: companyFilter,
            lineFilter: lineFilter, showsAllHistory: showsAllHistory)
    }

    private var searchSnapshotMatchesGeneration: Bool {
        searchSnapshot.generation == searchGeneration
    }

    private var searchSnapshotMatchesFilters: Bool {
        searchSnapshot.filters == currentFilters
    }

    /// Timetable loading, or the snapshot on screen is not the one for this
    /// generation or these filters. The empty-results row must wait for that
    /// snapshot; otherwise the frame after `loadTimetable` says "no results".
    private var showsSearchLoading: Bool {
        isLoadingTimetable || !searchSnapshotMatchesGeneration || !searchSnapshotMatchesFilters
    }

    /// Stale rows stay visible across a query debounce. They do not stay
    /// tappable across a filter or timetable change.
    private var allowsResultSelection: Bool {
        searchSnapshotMatchesGeneration && searchSnapshotMatchesFilters && !isLoadingTimetable
    }

    private func companyDisplayName(_ code: String) -> String {
        OperatorIdentity.displayName(code: code, language: localization.language.rawValue) ?? code
    }

    nonisolated private static func makeSearchSnapshot(_ input: SearchInput) -> SearchSnapshot {
        let search = TimetableSearch(input.query)
        let legacyMatches = TrainServicePatterns.search("", region: input.region, filter: .init(
            company: input.companyFilter, status: .any, line: input.lineFilter,
            rideDate: input.rideDate))
            .filter { search.matches($0) }
        let exactMatches = input.timetablePatterns.filter { pattern in
            if let companyFilter = input.companyFilter,
               !OperatorIdentity.sameCompany(pattern.company, companyFilter) { return false }
            if let lineFilter = input.lineFilter {
                let line = TrainServiceBranding.canonicalLineName(lineFilter)
                guard pattern.lines.contains(where: {
                    TrainServiceBranding.canonicalLineName($0) == line
                }) else { return false }
            }
            if let trip = input.timetableTripsByPatternID[pattern.id] { return search.matches(trip) }
            return search.matches(pattern)
        }
        let incompleteTrips = input.incompleteTimetableTrips.filter { trip in
            if let companyFilter = input.companyFilter,
               !trip.operatorSegments.contains(where: {
                   OperatorIdentity.sameCompany($0.displayName, companyFilter)
               }) { return false }
            if let lineFilter = input.lineFilter {
                let line = TrainServiceBranding.canonicalLineName(lineFilter)
                guard trip.lineSegments.contains(where: {
                    TrainServiceBranding.canonicalLineName($0.lineName) == line
                }) else { return false }
            }
            return search.matches(trip)
        }
        let knownMatches: [TrainServicePatterns.Pattern]
        if input.region != "jp" || input.rideDate == nil {
            knownMatches = legacyMatches
        } else if !input.timetablePatterns.isEmpty {
            knownMatches = exactMatches
        } else {
            knownMatches = []
        }
        let shouldShowLegacyFallback = input.rideDate != nil
            && (input.timetableQueryFailed
                || input.timetableCoverage != .verified
                || input.incompleteTimetableTripCount > 0
                || (input.timetableTripCount > 0 && input.timetablePatterns.isEmpty))
        let unknownPatterns: [TrainServicePatterns.Pattern]
        if input.region == "jp", let rideDate = input.rideDate {
            unknownPatterns = legacyMatches.filter { pattern in
                pattern.applicability(on: rideDate) != .notApplicable
                    && (shouldShowLegacyFallback || !isJROrNationalRailway(pattern))
            }
        } else {
            unknownPatterns = []
        }
        let outsidePatterns: [TrainServicePatterns.Pattern]
        if let rideDate = input.rideDate, input.showsAllHistory {
            outsidePatterns = legacyMatches.filter {
                $0.applicability(on: rideDate) == .notApplicable
            }
        } else {
            outsidePatterns = []
        }
        let companyNames = TrainServicePatterns.companyLabels(region: input.region)
            + input.timetablePatterns.map(\.companyLabel).filter { !$0.isEmpty }
            + input.incompleteTimetableTrips.flatMap { $0.operatorSegments.map(\.displayName) }
        let companyLabels = Array(Set(companyNames.flatMap { name -> [String] in
            name.components(separatedBy: "/").map {
                let part = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                return OperatorIdentity.code(for: part) ?? part
            }.filter { !$0.isEmpty }
        })).sorted {
            companyDisplayName($0, language: input.language)
                .localizedStandardCompare(companyDisplayName($1, language: input.language))
                == .orderedAscending
        }
        let lineNames = Array(Set(
            TrainServicePatterns.lineNames(region: input.region)
                + input.timetablePatterns.flatMap(\.lines)
                + input.incompleteTimetableTrips.flatMap { $0.lineSegments.map(\.lineName) }
        )).sorted()
        var order: [String] = []
        var byName: [String: [TrainServicePatterns.Pattern]] = [:]
        for pattern in knownMatches {
            let name = input.timetableDetails[pattern.id]?.serviceName ?? pattern.name
            if byName[name] == nil { order.append(name) }
            byName[name, default: []].append(pattern)
        }
        let groups = order.map { name in
            SearchGroup(name: name, companyLabel: byName[name]?.first?.companyLabel ?? "",
                        patterns: byName[name] ?? [])
        }
        return SearchSnapshot(
            groups: groups, incompleteTrips: incompleteTrips,
            unknownPatterns: unknownPatterns, outsidePatterns: outsidePatterns,
            companyLabels: companyLabels, lineNames: lineNames,
            generation: input.generation,
            filters: SearchFilters(
                region: input.region, rideDate: input.rideDate,
                companyFilter: input.companyFilter, lineFilter: input.lineFilter,
                showsAllHistory: input.showsAllHistory))
    }

    nonisolated private static func companyDisplayName(_ code: String, language: String) -> String {
        OperatorIdentity.displayName(code: code, language: language) ?? code
    }

    nonisolated private static func isJROrNationalRailway(
        _ pattern: TrainServicePatterns.Pattern
    ) -> Bool {
        pattern.company.split(separator: "/").contains { component in
            jrAndNationalOperatorNames.contains(
                component.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    var body: some View {
        let results = searchSnapshot
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
                    if showsSearchLoading {
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

                    if region == "jp", let rideDate {
                        timetableStatus(date: rideDate)
                    }

                    HStack {
                        Menu {
                            Button("すべての会社") { companyFilter = nil }
                            ForEach(results.companyLabels, id: \.self) { label in
                                Button(companyDisplayName(label)) { companyFilter = label }
                            }
                        } label: {
                            Label(companyFilter.map(companyDisplayName) ?? "すべての会社", systemImage: "building.2")
                        }
                        .railMenuButtonStyle()
                        .accessibilityIdentifier("servicePatternCompanyFilter")

                        Spacer()

                        Menu {
                            Button("すべての路線") { lineFilter = nil }
                            ForEach(results.lineNames, id: \.self) { line in
                                Button(line) { lineFilter = line }
                            }
                        } label: {
                            Label(lineFilter ?? "すべての路線", systemImage: "arrow.triangle.swap")
                        }
                        .railMenuButtonStyle()
                        .accessibilityIdentifier("servicePatternLineFilter")
                    }
                }
                Section {
                    Button { showsTrainResearch = true } label: {
                        Label(localization.text("ios.ai.researchTitle", fallback: "Ask ChatGPT about a train"),
                              systemImage: "sparkles")
                    }
                    .accessibilityIdentifier("servicePatternChatGPTQuery")
                }
                if searchSnapshotMatchesGeneration {
                    ForEach(results.groups, id: \.name) { group in
                        Section(header: Text("\(group.name) · \(group.companyLabel)")) {
                            ForEach(group.patterns) { pattern in
                                patternRow(pattern)
                            }
                        }
                    }
                    if !results.incompleteTrips.isEmpty {
                        Section(localization.editorText("ios.editor.timetablePublishedDraft")) {
                            ForEach(results.incompleteTrips) { trip in
                                VStack(alignment: .leading, spacing: 8) {
                                    incompleteTripRow(trip)
                                    Button("停車駅・時刻を確認") { inspectedTrip = trip }
                                        .buttonStyle(.borderless)
                                        .disabled(!allowsResultSelection)
                                        .accessibilityIdentifier("timetableDetails-\(trip.id)")
                                }
                            }
                        }
                    }
                    if !results.unknownPatterns.isEmpty {
                        Section("互換パターン（当日ダイヤ未確認）") {
                            ForEach(results.unknownPatterns) { pattern in patternRow(pattern) }
                        }
                    }
                    if !results.outsidePatterns.isEmpty {
                        Section("乗車日の対象外・有効期間未確認") {
                            ForEach(results.outsidePatterns) { pattern in patternRow(pattern) }
                        }
                    }
                }
                if allowsResultSelection && results.groups.isEmpty && results.incompleteTrips.isEmpty
                    && results.unknownPatterns.isEmpty && results.outsidePatterns.isEmpty
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
            .task(id: searchKey) { await updateSearchSnapshot() }
            .sheet(isPresented: $showsTrainResearch) {
                TrainResearchView(region: region, query: query, rideDate: rideDate)
            }
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
        .disabled(!allowsResultSelection)
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
        if timetableQueryFailed || timetableDatabase == nil {
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
        searchGeneration += 1
        guard region == "jp", let rideDate, let database = timetableDatabase else { return }

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
            searchGeneration += 1
        } catch {
            guard !Task.isCancelled else { return }
            timetableQueryFailed = true
            searchGeneration += 1
        }
    }

    @MainActor private func updateSearchSnapshot() async {
        let queryIsEmpty = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !queryIsEmpty {
            do { try await Task.sleep(for: .milliseconds(150)) }
            catch { return }
        }
        guard !Task.isCancelled else { return }
        let input = SearchInput(
            query: query, region: region, rideDate: rideDate,
            companyFilter: companyFilter, lineFilter: lineFilter,
            showsAllHistory: showsAllHistory, language: localization.language.rawValue,
            timetablePatterns: timetablePatterns, timetableDetails: timetableDetails,
            timetableTripsByPatternID: timetableTripsByPatternID,
            incompleteTimetableTrips: incompleteTimetableTrips,
            timetableCoverage: timetableCoverage, timetableTripCount: timetableTripCount,
            incompleteTimetableTripCount: incompleteTimetableTripCount,
            timetableQueryFailed: timetableQueryFailed,
            generation: searchGeneration)
        // An empty query is the list the reader is already looking at. Hopping
        // it off the main actor leaves a frame of the previous snapshot.
        let snapshot: SearchSnapshot
        if queryIsEmpty {
            snapshot = Self.makeSearchSnapshot(input)
        } else {
            snapshot = await Task.detached(priority: .userInitiated) {
                Self.makeSearchSnapshot(input)
            }.value
        }
        guard !Task.isCancelled else { return }
        guard snapshot.generation == searchGeneration,
              snapshot.filters == currentFilters else { return }
        searchSnapshot = snapshot
    }
}
