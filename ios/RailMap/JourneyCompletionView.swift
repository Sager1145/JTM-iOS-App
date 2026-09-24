import RailCore
import SwiftUI

/// Completion is staged locally; only an explicit apply changes the caller's draft.
struct JourneyCompletionView: View {
    @Environment(AppLocalization.self) private var localization
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let trains: [Train]
    var context = ""
    let onApply: ([Train]) -> Void
    /// Defaults to the research rule. The journey editor passes the station-and-time gate instead.
    var isEligible: (Train) -> Bool = JourneyCompletion.isEligible
    @State private var prompt = ""
    @State private var response = ""
    @State private var proposed: [Train]?
    @State private var failure: String?
    @State private var auth = ChatGPTSubscriptionAuth.shared
    /// Created lazily on first use: a `ChatGPTSubscriptionService` owns a `URLSession`, and this
    /// view struct is initialized far more often than it is actually used to talk to ChatGPT.
    @State private var service: ChatGPTSubscriptionService?
    @State private var models: [ChatGPTSubscriptionProtocol.Model] = []
    @State private var selectedModel = ""
    @State private var operation: Task<Void, Never>?
    @State private var isWorking = false
    @State private var ownsLogin = false
    @State private var previewResponse = ""

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
                subscriptionSection
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
                if let failure { Section { Text(failure).foregroundStyle(.red) } }
                if let proposed {
                    Section {
                        Text(text("review"))
                        ForEach(proposed, id: \.id) { train in
                            if let old = trains.first(where: { $0.id == train.id }) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(train.number).font(.headline)
                                    ForEach(changes(from: old, to: train)) { change in
                                        Text(change.text).font(.callout)
                                    }
                                }
                            }
                        }
                        DisclosureGroup(text("sources")) {
                            Text(response).font(.caption.monospaced()).textSelection(.enabled)
                        }
                        Button(text("apply")) {
                            onApply(proposed)
                            dismiss()
                        }.disabled(isWorking || proposed == trains)
                        .accessibilityIdentifier("aiCompletionApply")
                    } header: { Text(text("preview")) }
                }
            }
            .navigationTitle(text("title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localization.text("ios.cancel", fallback: "Cancel")) { dismiss() }
                }
            }
            .task {
                do {
                    prompt = try JourneyCompletion.prompt(
                        trains: trains, context: context, eligible: isEligible)
                }
                catch { failure = error.localizedDescription; return }
                if auth.isSignedIn { run { try await loadModels() } }
            }
            .onChange(of: response) { _, value in
                if value != previewResponse { proposed = nil; failure = nil }
            }
            .onDisappear {
                operation?.cancel()
                if ownsLogin { auth.cancelLogin() }
            }
        }
    }

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
                        let result = try await currentService().complete(prompt: prompt, model: selectedModel)
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

    private func preview() {
        previewResponse = response
        do {
            proposed = try JourneyCompletion.merge(response: response, into: trains)
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
            if before != after, let after {
                rows.append(Change(id: id ?? label, text: label + ": " + after))
            }
        }
        add(text("service"), old.number, new.number)
        add(text("english"), old.numberEn, new.numberEn)
        add(text("type"), old.trainType, new.trainType)
        add(text("vehicle"), old.vehicleType, new.vehicleType)
        add(text("company"), old.company, new.company)
        add(text("direction"), old.direction, new.direction)
        add(text("lines"), old.routePolicy?.preferredLineNames?.joined(separator: " · "),
            new.routePolicy?.preferredLineNames?.joined(separator: " · "))
        for (index, stop) in new.stops.enumerated() where old.stops.indices.contains(index) {
            let before = old.stops[index]
            add(stop.name + " · " + text("arrival"), before.arrival, stop.arrival, id: "stop-\(index)-arrival")
            add(stop.name + " · " + text("departure"), before.departure, stop.departure, id: "stop-\(index)-departure")
            add(stop.name + " · " + text("platform"), before.platformNumber.map(String.init), stop.platformNumber.map(String.init), id: "stop-\(index)-platform")
        }
        return rows.isEmpty ? [Change(id: "unchanged", text: text("unchanged"))] : rows
    }
}
