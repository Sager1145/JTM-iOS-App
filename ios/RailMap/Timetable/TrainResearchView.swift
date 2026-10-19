import RailCore
import SwiftUI

/// Research answers remain separate from the published timetable and journey draft.
struct TrainResearchView: View {
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

