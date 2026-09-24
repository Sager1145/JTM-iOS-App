import RailCore
import SwiftUI

/// Completion is staged locally; only an explicit apply changes the caller's draft.
struct JourneyCompletionView: View {
    @Environment(AppLocalization.self) private var localization
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private let initialTrains: [Train]
    private let initialContext: String
    private let allowsRawImport: Bool
    private let onApply: ([Train]) -> Void
    /// Temporary source compatibility for callers using the former injected gate. The catalog
    /// and corresponding-time gate always runs as well, so callers cannot loosen it.
    private let callerEligibility: ((Train) -> Bool)?

    @State private var draftTrains: [Train]
    @State private var prompt = ""
    @State private var response = ""
    @State private var proposed: [Train]?
    @State private var failure: String?
    @State private var auth = ChatGPTSubscriptionAuth.shared
    @State private var service: ChatGPTSubscriptionService?
    @State private var models: [ChatGPTSubscriptionProtocol.Model] = []
    @State private var selectedModel = ""
    @State private var operation: Task<Void, Never>?
    @State private var isWorking = false
    @State private var ownsLogin = false
    @State private var previewResponse = ""

    @State private var rawText = ""
    @State private var rawDraft: JourneyCompletion.RawDraft?
    @State private var rawSelections: [Int: StationKey] = [:]
    @State private var rawWasConfirmed = false
    @State private var catalogs: [String: EditorCatalog] = [:]
    @State private var catalogsAreLoading = true

    init(
        trains: [Train], context: String = "", allowsRawImport: Bool = false,
        onApply: @escaping ([Train]) -> Void,
        isEligible: ((Train) -> Bool)? = nil
    ) {
        initialTrains = trains
        initialContext = context
        self.allowsRawImport = allowsRawImport
        self.onApply = onApply
        callerEligibility = isEligible
        _draftTrains = State(initialValue: trains)
    }

    private func text(_ key: String) -> String { localization.text("ios.ai." + key, fallback: key) }

    private func currentService() -> ChatGPTSubscriptionService {
        if let service { return service }
        let created = ChatGPTSubscriptionService(auth: .shared)
        service = created
        return created
    }

    var body: some View {
        NavigationStack {
            Form {
                if allowsRawImport { rawImportSection }
                subscriptionSection
                promptSection
                responseSection
                if let failure { Section { Text(failure).foregroundStyle(.red) } }
                if proposed != nil || draftTrains != initialTrains { reviewSection }
            }
            .navigationTitle(text("title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localization.text("ios.cancel", fallback: "Cancel")) { dismiss() }
                }
            }
            .task { await prepareCatalogs() }
            .onChange(of: response) { _, value in
                if value != previewResponse { proposed = nil; failure = nil }
            }
            .onChange(of: rawText) { _, value in
                guard value != rawDraft?.sourceText else { return }
                rawDraft = nil
                rawSelections = [:]
                rawWasConfirmed = false
            }
            .onDisappear {
                operation?.cancel()
                if ownsLogin { auth.cancelLogin() }
            }
        }
    }

    // MARK: - pasted text

    private var rawImportSection: some View {
        Section {
            Text(text("rawInstructions"))
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextEditor(text: $rawText)
                .font(.caption.monospaced())
                .frame(minHeight: 120)
                .accessibilityLabel(text("rawInput"))
                .accessibilityIdentifier("aiRawInput")
                .disabled(isWorking)
            Button { extractRawText() } label: {
                Label(text("extract"), systemImage: "text.viewfinder")
            }
            .disabled(
                catalogsAreLoading || isWorking
                    || rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("aiRawExtract")

            if catalogsAreLoading {
                HStack { ProgressView(); Text(text("loadingCatalog")) }
            }
            if let rawDraft {
                ForEach(rawDraft.stops) { stop in rawStopRow(stop) }
                if !rawDraft.unmatchedLines.isEmpty {
                    DisclosureGroup(text("unmatched")) {
                        Text(rawDraft.unmatchedLines.joined(separator: "\n"))
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
                Button { confirmRawDraft(rawDraft) } label: {
                    Label(
                        text(rawWasConfirmed ? "confirmed" : "confirmExtracted"),
                        systemImage: rawWasConfirmed ? "checkmark.circle.fill" : "checkmark.circle")
                }
                .disabled(isWorking || rawWasConfirmed || builtTrain(from: rawDraft) == nil)
                .accessibilityIdentifier("aiRawConfirm")
            }
        } header: { Text(text("rawTitle")) }
    }

    @ViewBuilder
    private func rawStopRow(_ stop: JourneyCompletion.RawStop) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(stop.matchedName).font(.headline)
                Spacer()
                Text([stop.arrival, stop.departure].compactMap { $0 }.joined(separator: " / "))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if stop.candidates.count == 1, let station = stop.candidates.first {
                Label("\(station.name) · \(station.key.sourceCode)", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker(
                    text("stationMatch"),
                    selection: Binding<StationKey?>(
                        get: { rawSelections[stop.id] },
                        set: { value in rawSelections[stop.id] = value })
                ) {
                    Text(text("chooseStation")).tag(nil as StationKey?)
                    ForEach(stop.candidates, id: \.key) { station in
                        Text("\(station.name) · \(station.key.sourceCode)")
                            .tag(station.key as StationKey?)
                    }
                }
            }
        }
    }

    private func extractRawText() {
        guard let seed = initialTrains.first else { return }
        let region = Region.resolved(seed)
        guard let catalog = catalogs[region.code] else {
            failure = text("catalogUnavailable")
            return
        }
        let extracted = JourneyCompletion.rawDraft(
            text: rawText, catalog: catalog, regionCode: region.code, seed: seed)
        rawDraft = extracted
        rawSelections = Dictionary(uniqueKeysWithValues: extracted.stops.compactMap { stop in
            stop.automaticSelection.map { (stop.id, $0) }
        })
        rawWasConfirmed = false
        proposed = nil
        response = ""
        failure = extracted.stops.count < 2 ? text("notEnoughStops") : nil
    }

    private func builtTrain(from rawDraft: JourneyCompletion.RawDraft) -> Train? {
        guard let seed = initialTrains.first else { return nil }
        let region = Region.resolved(seed)
        guard let catalog = catalogs[region.code] else { return nil }
        return rawDraft.train(seed: seed, selections: rawSelections, catalog: catalog)
    }

    private func confirmRawDraft(_ rawDraft: JourneyCompletion.RawDraft) {
        guard let train = builtTrain(from: rawDraft) else { return }
        draftTrains = [train]
        rawWasConfirmed = true
        proposed = nil
        response = ""
        refreshPrompt(reportFailure: true)
    }

    // MARK: - prompt and response

    private var promptSection: some View {
        Section {
            Text(text("instructions"))
            ShareLink(item: prompt) {
                Label(text("share"), systemImage: "square.and.arrow.up")
            }.disabled(prompt.isEmpty)
            Button(text("open")) { openURL(URL(string: "https://chatgpt.com/")!) }
            DisclosureGroup(text("prompt")) {
                Text(prompt).font(.caption.monospaced()).textSelection(.enabled)
            }
        }
    }

    private var responseSection: some View {
        Section {
            TextEditor(text: $response)
                .font(.caption.monospaced())
                .frame(minHeight: 160)
                .accessibilityLabel(text("response"))
                .accessibilityIdentifier("aiCompletionResponse")
                .disabled(isWorking)
            Button(text("preview")) { preview() }
                .disabled(isWorking || response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("aiCompletionPreview")
        } header: { Text(text("response")) }
    }

    private var reviewSection: some View {
        let reviewed = proposed ?? draftTrains
        return Section {
            Text(text("review"))
            ForEach(reviewed, id: \.id) { train in
                if let old = initialTrains.first(where: { $0.id == train.id }) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(train.number.isEmpty ? "\(train.origin) → \(train.destination)" : train.number)
                            .font(.headline)
                        ForEach(changes(from: old, to: train)) { change in
                            Text(change.text).font(.callout)
                        }
                    }
                }
            }
            if !response.isEmpty {
                DisclosureGroup(text("sources")) {
                    Text(response).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
            Button(text("apply")) {
                onApply(reviewed)
                dismiss()
            }
            .disabled(isWorking || reviewed == initialTrains)
            .accessibilityIdentifier("aiCompletionApply")
        } header: { Text(text("preview")) }
    }

    // MARK: - subscription

    private var subscriptionSection: some View {
        Section {
            Text(text("subscriptionInfo")).font(.footnote).foregroundStyle(.secondary)
            if auth.isSignedIn {
                LabeledContent(text("account"), value: auth.accountLabel ?? "ChatGPT")
                if let plan = auth.planLabel { LabeledContent(text("plan"), value: plan) }
                if !models.isEmpty {
                    Picker(text("model"), selection: $selectedModel) {
                        ForEach(models) { model in Text(model.displayName).tag(model.id) }
                    }.disabled(isWorking)
                }
                Button(text("refreshModels")) { run { try await loadModels() } }
                    .disabled(isWorking)
                Button {
                    run {
                        let requestPrompt = try makePrompt()
                        let result = try await currentService().complete(
                            prompt: requestPrompt, model: selectedModel)
                        try Task.checkCancellation()
                        response = result
                        preview()
                    }
                } label: { Label(text("complete"), systemImage: "sparkles") }
                    .disabled(isWorking || prompt.isEmpty || !models.contains { $0.id == selectedModel })
                    .accessibilityIdentifier("aiSubscriptionComplete")
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
                }.disabled(isWorking)
                .accessibilityIdentifier("aiSubscriptionSignIn")
            }
            if let code = auth.userCode, auth.isSigningIn {
                Text(code).font(.title2.monospaced()).textSelection(.enabled)
                    .accessibilityIdentifier("aiSubscriptionCode")
                Text(text("deviceInstructions")).font(.footnote)
                Button(text("authorize")) { openURL(auth.loginURL) }
            }
            if isWorking {
                HStack {
                    ProgressView()
                    Text(text(auth.isSigningIn ? "waitingLogin" : "working"))
                }
                Button(text("cancelRequest")) {
                    operation?.cancel()
                    if ownsLogin { auth.cancelLogin() }
                }
            }
        } header: { Text(text("subscription")) }
    }

    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        guard !isWorking else { return }
        isWorking = true
        failure = nil
        operation = Task { @MainActor in
            defer { isWorking = false; operation = nil }
            do { try await action() }
            catch is CancellationError { }
            catch {
                if !Task.isCancelled { failure = error.localizedDescription }
            }
        }
    }

    private func loadModels() async throws {
        let available = try await currentService().models()
        try Task.checkCancellation()
        models = available
        if !models.contains(where: { $0.id == selectedModel }) {
            selectedModel = models.first?.id ?? ""
        }
        if models.isEmpty { failure = text("noModels") }
    }

    private func prepareCatalogs() async {
        let regions = Set(initialTrains.flatMap(Region.regionsTouched))
        let result = await Task.detached(priority: .userInitiated) {
            var loaded: [String: EditorCatalog] = [:]
            var firstError: Swift.Error?
            for region in regions {
                do { loaded[region.code] = try loadCatalog(for: region) }
                catch { if firstError == nil { firstError = error } }
            }
            return (loaded, firstError?.localizedDescription)
        }.value
        guard !Task.isCancelled else { return }
        catalogs = result.0
        catalogsAreLoading = false
        if catalogs.isEmpty, let detail = result.1 { failure = detail }
        refreshPrompt(reportFailure: !allowsRawImport)
        if auth.isSignedIn { run { try await loadModels() } }
    }

    private func containsDatabaseStation(_ code: String) -> Bool {
        for (regionCode, catalog) in catalogs {
            if catalog.station(StationKey(regionCode: regionCode, sourceCode: code)) != nil {
                return true
            }
        }
        return false
    }

    private func eligible(_ train: Train) -> Bool {
        JourneyCompletion.isRequestEligible(
            train, stationIsInDatabase: containsDatabaseStation)
            && (callerEligibility?(train) ?? true)
    }

    private func makePrompt() throws -> String {
        try JourneyCompletion.prompt(
            trains: draftTrains,
            context: rawWasConfirmed ? rawText : initialContext,
            eligible: eligible)
    }

    private func refreshPrompt(reportFailure: Bool) {
        do {
            prompt = try makePrompt()
            if failure == JourneyCompletion.Error.noEligibleTrains.localizedDescription { failure = nil }
        } catch {
            prompt = ""
            if reportFailure { failure = error.localizedDescription }
        }
    }

    private func preview() {
        previewResponse = response
        do {
            proposed = try JourneyCompletion.merge(response: response, into: draftTrains)
            failure = nil
        } catch { proposed = nil; failure = text("invalid") + "\n" + error.localizedDescription }
    }

    private struct Change: Identifiable {
        let id: String
        let text: String
    }

    private func changes(from old: Train, to new: Train) -> [Change] {
        var rows: [Change] = []
        func add(_ label: String, _ before: String?, _ after: String?, id: String? = nil) {
            if before != after, let after, !after.isEmpty {
                rows.append(Change(id: id ?? label, text: label + ": " + after))
            }
        }
        add(text("date"), old.date, new.date)
        add(text("service"), old.number, new.number)
        add(text("english"), old.numberEn, new.numberEn)
        add(text("type"), old.trainType, new.trainType)
        add(text("vehicle"), old.vehicleType, new.vehicleType)
        add(text("company"), old.company, new.company)
        add(text("direction"), old.direction, new.direction)
        add(text("origin"), old.origin, new.origin)
        add(text("destination"), old.destination, new.destination)
        add(text("lines"), old.routePolicy?.preferredLineNames?.joined(separator: " · "),
            new.routePolicy?.preferredLineNames?.joined(separator: " · "))
        for (index, stop) in new.stops.enumerated() {
            let before = old.stops.indices.contains(index) ? old.stops[index] : nil
            add(text("station"), before?.name, stop.name, id: "stop-\(index)-name")
            add(stop.name + " · " + text("arrival"), before?.arrival, stop.arrival, id: "stop-\(index)-arrival")
            add(stop.name + " · " + text("departure"), before?.departure, stop.departure, id: "stop-\(index)-departure")
            add(stop.name + " · " + text("platform"), before?.platformNumber.map(String.init), stop.platformNumber.map(String.init), id: "stop-\(index)-platform")
        }
        return rows.isEmpty ? [Change(id: "unchanged", text: text("unchanged"))] : rows
    }
}
