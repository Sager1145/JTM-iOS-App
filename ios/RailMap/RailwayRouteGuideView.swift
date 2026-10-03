import MapKit
import RailCore
import SwiftUI

/// Selects a span of recorded visits before searching physical route choices.
/// Occurrence identities distinguish repeated visits to the same station.
/// Present this view in the parent's sheet NavigationStack.
struct RailwayRouteCorrectionView: View {
    typealias Choice = RailwayRouteChoices.Choice

    @Environment(\.dismiss) private var dismiss
    @Environment(AppLocalization.self) private var localization

    private let train: Train
    private let package: CompactPackage
    private let excludedStationCodes: Set<String>
    private let onApply: (Choice, UUID, UUID) -> Void

    @State private var fromID: UUID?
    @State private var toID: UUID?
    @State private var loading = false
    @State private var foundChoices: [Choice] = []
    @State private var loadedSearch: SearchKey?
    @State private var session: Session?
    @State private var showingGuide = false

    init(
        train: Train, package: CompactPackage, excludedStationCodes: Set<String> = [],
        onApply: @escaping (Choice, UUID, UUID) -> Void
    ) {
        let prepared = RailwayRouteEditing.preparing(train)
        self.train = prepared
        self.package = package
        self.excludedStationCodes = excludedStationCodes
        self.onApply = onApply
        let mappedStops = prepared.stops.filter { $0.n02StationCode != nil }
        _fromID = State(initialValue: mappedStops.first?.routeEditing?.visitID)
        _toID = State(initialValue: mappedStops.last?.routeEditing?.visitID)
    }

    private var rows: [Endpoint] {
        train.stops.enumerated().compactMap { index, stop in
            guard let id = stop.routeEditing?.visitID, let code = stop.n02StationCode else { return nil }
            return Endpoint(id: id, index: index, code: code, name: stop.name)
        }
    }

    private var from: Endpoint? { rows.first { $0.id == fromID } }
    private var to: Endpoint? { rows.first { $0.id == toID } }

    private var destinationRows: [Endpoint] {
        guard let from else { return [] }
        return rows.filter { $0.index > from.index }
    }

    private var search: SearchKey? {
        guard let from, let to, from.index < to.index, from.code != to.code else { return nil }
        return SearchKey(fromID: from.id, toID: to.id, origin: from.code, destination: to.code)
    }

    var body: some View {
        Form {
            Section {
                Picker(localization.editorText("ios.editor.fromStation"), selection: $fromID) {
                    ForEach(rows.filter { $0.index < (rows.last?.index ?? 0) }) { row in
                        Text(endpointName(row)).tag(Optional(row.id))
                    }
                }
                .accessibilityIdentifier("routeCorrectionFrom")
                Picker(localization.editorText("ios.editor.toStation"), selection: $toID) {
                    ForEach(destinationRows) { row in
                        Text(endpointName(row)).tag(Optional(row.id))
                    }
                }
                .accessibilityIdentifier("routeCorrectionTo")
            } header: {
                Text(text("choosePortion"))
            } footer: {
                Text(text(excludedStationCodes.isEmpty ? "portionHelp" : "avoidHelp"))
            }

            Section {
                if loading {
                    ProgressView(text("findingPaths"))
                } else if search == nil {
                    Text(text("invalidEndpoints")).foregroundStyle(.secondary)
                } else if loadedSearch == search && foundChoices.isEmpty {
                    Text(text("emptyDetail")).foregroundStyle(.secondary)
                        .accessibilityIdentifier("routeCorrectionEmpty")
                }
                Button(text("findPaths"), systemImage: "map") { openGuide() }
                    .disabled(loading || search == nil || loadedSearch != search || foundChoices.isEmpty)
                    .accessibilityIdentifier("routeCorrectionCompare")
            }
        }
        .navigationTitle(text("title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(localization.text("ios.cancel")) { dismiss() }
                    .accessibilityIdentifier("routeCorrectionCancel")
            }
        }
        .onChange(of: fromID) { _, _ in
            if !destinationRows.contains(where: { $0.id == toID }) {
                toID = destinationRows.last?.id
            }
        }
        .task(id: search) { await loadChoices() }
        .navigationDestination(isPresented: $showingGuide) {
            if let session {
                RailwayRouteGuideView(
                    train: session.train, package: package, choices: session.choices,
                    embeddedInNavigationStack: true, onCancel: { dismiss() }
                ) { choice in
                    onApply(choice, session.fromID, session.toID)
                }
            }
        }
    }

    private func loadChoices() async {
        foundChoices = []
        loadedSearch = nil
        guard let search else { loading = false; return }
        loading = true
        let package = package
        let trainType = train.trainType
        let excluded = excludedStationCodes
        // Bounded physical search also supports spans crossing railway families.
        let worker = Task.detached(priority: .userInitiated) {
            LocalJourneySearch.choices(
                package: package, originCode: search.origin, destinationCode: search.destination,
                trainType: trainType, excludingStationCodes: excluded)
        }
        let result = await withTaskCancellationHandler {
            await worker.value
        } onCancel: { worker.cancel() }
        guard !Task.isCancelled, self.search == search else { return }
        foundChoices = result
        loadedSearch = search
        loading = false
    }

    private func openGuide() {
        guard let from, let to, let search, loadedSearch == search, !foundChoices.isEmpty else { return }
        var segment = train
        segment.stops = Array(train.stops[from.index...to.index])
        segment.origin = segment.stops[0].name
        segment.destination = segment.stops[segment.stops.count - 1].name
        if let sections = train.routeSections, sections.count == train.stops.count - 1 {
            segment.routeSections = Array(sections[from.index..<to.index])
        } else {
            // The core planner can reconstruct absent adjacent sections safely.
            segment.routeSections = nil
        }
        session = Session(train: segment, choices: foundChoices, fromID: from.id, toID: to.id)
        showingGuide = true
    }

    private func endpointName(_ endpoint: Endpoint) -> String {
        text("occurrence", [
            "number": .number(Double(endpoint.index + 1)),
            "station": .string(localization.stationName(endpoint.name, code: endpoint.code)),
        ])
    }

    private func text(_ key: String, _ params: [String: Localization.Param]? = nil) -> String {
        localization.editorText("ios.routeGuide." + key, params)
    }

    private struct Endpoint: Identifiable {
        let id: UUID
        let index: Int
        let code: String
        let name: String
    }

    private struct SearchKey: Hashable, Sendable {
        let fromID: UUID
        let toID: UUID
        let origin: String
        let destination: String
    }

    private struct Session {
        let train: Train
        let choices: [Choice]
        let fromID: UUID
        let toID: UUID
    }
}

/// A draft-only route guide. The parent owns applying the final choice and
/// confirming replacement of authored stops; leaving this sheet never edits a ride.
struct RailwayRouteGuideView: View {
    typealias Choice = RailwayRouteChoices.Choice
    typealias Decision = RailwayRouteEditing.Decision

    @Environment(\.dismiss) private var dismiss
    @Environment(AppLocalization.self) private var localization
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let train: Train
    private let choices: [Choice]
    private let decisions: [Decision]
    private let geometry: RailwayGuideGeometry
    private let onApply: (Choice) -> Void
    private let embeddedInNavigationStack: Bool
    private let onCancel: (() -> Void)?
    private let isInferred: Bool

    @State private var step = 0
    @State private var confirmed: [String: String] = [:]
    @State private var previewID: String?
    @State private var reviewChoiceID: String?
    @State private var pendingChange: PendingChange?
    @State private var showingFullRoute = false

    init(
        train: Train, package: CompactPackage, choices: [Choice],
        embeddedInNavigationStack: Bool = false, onCancel: (() -> Void)? = nil,
        isInferred: Bool = false,
        onApply: @escaping (Choice) -> Void
    ) {
        // A single prepared snapshot gives every preview the same visit identity.
        // It is intentionally immutable for the lifetime of this editing sheet.
        self.train = RailwayRouteEditing.preparing(train)
        self.choices = choices
        self.decisions = RailwayRouteEditing.decisions(choices: choices)
        self.geometry = RailwayGuideGeometry(package: package, choices: choices)
        self.onApply = onApply
        self.embeddedInNavigationStack = embeddedInNavigationStack
        self.onCancel = onCancel
        self.isInferred = isInferred
    }

    private var currentDecision: Decision? {
        decisions.indices.contains(step) ? decisions[step] : nil
    }

    private var currentOptions: [Choice] {
        guard let decision = currentDecision else { return [] }
        let preceding = constraints(before: step)
        return decision.options.filter { option in
            choices.contains { matches($0, constraints: preceding) && contains($0, option: option) }
        }
    }

    private var remainingChoices: [Choice] {
        choices.filter { matches($0, constraints: confirmed) }
    }

    private var inspectionChoices: [Choice] {
        guard let decision = currentDecision else { return remainingChoices }
        var constraints = constraints(before: step)
        if let preview { constraints[decision.id] = preview.id }
        return choices.filter { matches($0, constraints: constraints) }
    }

    private var preview: Choice? {
        currentOptions.first { $0.id == previewID }
    }

    private var reviewChoice: Choice? {
        if let selected = remainingChoices.first(where: { $0.id == reviewChoiceID }) { return selected }
        return remainingChoices.count == 1 ? remainingChoices.first : nil
    }

    private var reviewPlan: RailwayRouteEditing.Plan? {
        guard let choice = reviewChoice else { return nil }
        return RailwayRouteEditing.plan(
            train: train, choice: choice,
            fromVisitID: train.stops.first?.routeEditing?.visitID,
            toVisitID: train.stops.last?.routeEditing?.visitID)
    }

    var body: some View {
        Group {
            if embeddedInNavigationStack {
                content
            } else {
                NavigationStack { content }
            }
        }
    }

    private var content: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if isInferred {
                        Label(text("inferenceNote"), systemImage: "wand.and.stars")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .accessibilityIdentifier("routeGuideInferenceNotice")
                    }
                    if choices.isEmpty {
                        emptyState
                    } else if let decision = currentDecision {
                        decisionContent(decision)
                            .id(decision.id)
                            .transition(stepTransition)
                    } else {
                        reviewContent
                            .transition(stepTransition)
                    }
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(text("title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localization.text("ios.cancel")) { leave() }
                        .accessibilityIdentifier("routeGuideCancel")
                }
                if !choices.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showingFullRoute = true } label: {
                            Image(systemName: "map")
                        }
                        .accessibilityLabel(text("fullRoute"))
                        .accessibilityIdentifier("routeGuideFullRoute")
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { actions }
            .confirmationDialog(
                text("changeTitle"),
                isPresented: Binding(
                    get: { pendingChange != nil },
                    set: { if !$0 { pendingChange = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingChange
            ) { change in
                Button(text("changeConfirm"), role: .destructive) {
                    accept(change)
                    pendingChange = nil
                }
                Button(text("keepSelection"), role: .cancel) { pendingChange = nil }
            } message: { change in
                Text(text("changeDetail", ["count": .number(Double(change.invalidatedCount))]))
            }
            .sheet(isPresented: $showingFullRoute) {
                RailwayGuideInspectionView(
                    choices: inspectionChoices, geometry: geometry,
                    selectedID: inspectionChoices.count == 1 ? inspectionChoices.first?.id : reviewChoice?.id,
                    title: text("wholeRoute"), geometryWarning: text("geometryUnavailable")
                )
            }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(text("noCandidate"), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
        } description: {
            Text(text("emptyDetail"))
        }
    }

    private func decisionContent(_ decision: Decision) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(text("step", ["current": .number(Double(step + 1)), "total": .number(Double(decisions.count))]))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(station(decision.originName, code: decision.originCode) + " → "
                 + station(decision.destinationName, code: decision.destinationCode))
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text(text("help")).font(.subheadline).foregroundStyle(.secondary)
            RailwayGuideMap(
                choices: currentOptions, geometry: geometry, selectedID: preview?.id,
                geometryWarning: text("geometryUnavailable")
            )
            .id(decision.id + "-map")
            ForEach(numbered(currentOptions)) { option in
                optionCard(option.choice, number: option.number, selected: preview?.id == option.id) {
                    animate {
                        previewID = option.id
                    }
                }
            }
            if let preview {
                VStack(alignment: .leading, spacing: 10) {
                    Label(text("preview"), systemImage: "eye")
                        .font(.headline)
                    Text(text("previewNote")).font(.caption).foregroundStyle(.secondary)
                    ForEach(visitRows(preview)) { visit in
                        HStack(spacing: 10) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 7))
                                .foregroundStyle(.secondary)
                            Text(station(visit.name, code: visit.code))
                                .font(.subheadline)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background, in: RoundedRectangle(cornerRadius: 16))
                .transition(stepTransition)
                .accessibilityIdentifier("routeGuidePreviewStations")
            }
            Text(text("progress", ["confirmed": .number(Double(confirmed.count)), "total": .number(Double(decisions.count))]))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var reviewContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(text("reviewTitle")).font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            RailwayGuideMap(
                choices: remainingChoices, geometry: geometry,
                selectedID: reviewChoice?.id, geometryWarning: text("geometryUnavailable")
            )
            .id("whole-route-map")
            // A safety net when two complete physical alignments still share all
            // decision slices: applying requires an explicit complete candidate.
            if remainingChoices.count > 1 {
                ForEach(numbered(remainingChoices)) { option in
                    optionCard(option.choice, number: option.number, selected: reviewChoice?.id == option.id) {
                        animate { reviewChoiceID = option.id }
                    }
                }
            } else if let choice = reviewChoice {
                Text(choice.lineNames.joined(separator: " · "))
                    .font(.headline)
            }
            if let plan = reviewPlan {
                changeSummary(plan)
                projectedStops(plan)
            } else if reviewChoice != nil {
                Label(text("routeUnavailable"), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func optionCard(
        _ choice: Choice, number: Int, selected: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Text(number.formatted(.number.locale(localization.locale)))
                    .font(.headline.monospacedDigit())
                    .frame(width: 30, height: 30)
                    .foregroundStyle(.white)
                    .background(RailwayGuideMap.color(number), in: Circle())
                VStack(alignment: .leading, spacing: 5) {
                    Text(text("option", ["number": .number(Double(number))]))
                        .font(.subheadline.weight(.semibold))
                    Text(choice.lineNames.isEmpty ? text("lineOption") : choice.lineNames.joined(separator: " · "))
                        .font(.headline)
                    if !choice.operatorNames.isEmpty {
                        Text(choice.operatorNames.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    let via = choice.stations.dropFirst().dropLast()
                    if !via.isEmpty {
                        Text(via.map { station($0.name, code: $0.code) }.joined(separator: " · "))
                            .font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(text("stationCount", ["count": .number(Double(choice.stations.count))]))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .font(.title3)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier("routeGuideOption\(number)")
    }

    private func changeSummary(_ plan: RailwayRouteEditing.Plan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if plan.insertedStops.isEmpty && plan.removedStops.isEmpty && plan.conflictingStops.isEmpty {
                Text(text("unchanged")).foregroundStyle(.secondary)
            }
            if !plan.insertedStops.isEmpty {
                changeNames(plan.insertedStops, title: text("inserted", ["count": .number(Double(plan.insertedStops.count))]),
                            symbol: "plus.circle.fill", color: .green)
                Text(localization.editorText("ios.editor.generatedStationsNote"))
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !plan.removedStops.isEmpty {
                changeNames(plan.removedStops, title: text("removed", ["count": .number(Double(plan.removedStops.count))]),
                            symbol: "minus.circle.fill", color: .orange)
            }
            if plan.requiresConfirmation {
                Label(text("protected"), systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.orange)
                Text(text("protectedDetail")).font(.caption).foregroundStyle(.secondary)
                ForEach(stopRows(plan.conflictingStops)) { row in
                    Text(station(row.stop.name, code: row.stop.n02StationCode))
                        .font(.subheadline)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityIdentifier("routeGuideChangeSummary")
    }

    private func changeNames(_ stops: [Stop], title: String, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.subheadline.weight(.semibold)).foregroundStyle(color)
            ForEach(stopRows(stops)) { row in
                Text(station(row.stop.name, code: row.stop.n02StationCode))
                    .font(.subheadline)
                    .transition(stepTransition)
            }
        }
    }

    private func projectedStops(_ plan: RailwayRouteEditing.Plan) -> some View {
        let insertedIDs = Set(plan.insertedStops.compactMap { $0.routeEditing?.visitID })
        return VStack(alignment: .leading, spacing: 12) {
            Text(text("wholeRoute")).font(.headline)
            ForEach(stopRows(plan.updatedTrain.stops)) { row in
                let inserted = row.stop.routeEditing.map { insertedIDs.contains($0.visitID) } ?? false
                HStack(spacing: 12) {
                    Image(systemName: inserted ? "plus.circle.fill" : "circle.fill")
                        .font(.system(size: inserted ? 16 : 8))
                        .frame(width: 16)
                        .foregroundStyle(inserted ? Color.green : Color.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(station(row.stop.name, code: row.stop.n02StationCode))
                        if row.stop.routeEditing?.generatedBy != nil {
                            AutoFilledStationLabel()
                        }
                        if let detail = stopDetail(row.stop) {
                            Text(detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .transition(stepTransition)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityIdentifier("routeGuideProjectedStops")
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if !choices.isEmpty {
                HStack(spacing: 12) {
                    if step > 0 {
                        Button(text("previous")) { goBack() }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("routeGuidePrevious")
                    }
                    if currentDecision != nil {
                        Button(text("confirm")) { confirmPreview() }
                            .buttonStyle(.borderedProminent)
                            .disabled(preview == nil)
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("routeGuideConfirm")
                    } else {
                        Button(text("apply")) {
                            if let choice = reviewChoice, reviewPlan != nil { onApply(choice) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(reviewChoice == nil || reviewPlan == nil)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("routeGuideApply")
                    }
                }
                HStack(spacing: 16) {
                    Button(text("unsure")) { leave() }
                    Button(text("noCandidate")) { leave() }
                }
                .font(.caption)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, choices.isEmpty ? 0 : 12)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func confirmPreview() {
        guard let decision = currentDecision, let preview else { return }
        var next = confirmed
        next[decision.id] = preview.id
        var invalidated = 0
        // Preserve independent choices. A later constraint survives whenever at
        // least one complete path supports it together with the retained earlier ones.
        var retained = constraints(before: step)
        retained[decision.id] = preview.id
        for later in decisions.dropFirst(step + 1) {
            guard let selected = next[later.id] else { continue }
            var trial = retained
            trial[later.id] = selected
            if choices.contains(where: { matches($0, constraints: trial) }) {
                retained[later.id] = selected
            } else {
                next.removeValue(forKey: later.id)
                invalidated += 1
            }
        }
        let change = PendingChange(confirmed: next, invalidatedCount: invalidated)
        if invalidated > 0 { pendingChange = change } else { accept(change) }
    }

    private func accept(_ change: PendingChange) {
        animate {
            confirmed = change.confirmed
            reviewChoiceID = nil
            // Move to the first choice that still needs confirmation, so preserved
            // independent later choices need not be repeated.
            step = decisions.firstIndex { confirmed[$0.id] == nil } ?? decisions.count
            previewID = currentDecision.flatMap { confirmed[$0.id] }
        }
    }

    private func goBack() {
        animate {
            step = max(0, step - 1)
            previewID = currentDecision.flatMap { confirmed[$0.id] }
        }
    }

    private func constraints(before index: Int) -> [String: String] {
        Dictionary(uniqueKeysWithValues: decisions.prefix(index).compactMap { decision in
            confirmed[decision.id].map { (decision.id, $0) }
        })
    }

    private func matches(_ choice: Choice, constraints: [String: String]) -> Bool {
        constraints.allSatisfy { id, optionID in
            guard let option = decisions.first(where: { $0.id == id })?.options.first(where: { $0.id == optionID })
            else { return false }
            return contains(choice, option: option)
        }
    }

    private func contains(_ choice: Choice, option: Choice) -> Bool {
        let codes = option.sectionCodes
        guard !codes.isEmpty, codes.count <= choice.sectionCodes.count else { return false }
        return (0...(choice.sectionCodes.count - codes.count)).contains { start in
            Array(choice.sectionCodes[start..<(start + codes.count)]) == codes
        }
    }

    private var stepTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 10))
    }

    private func animate(_ updates: () -> Void) {
        withAnimation(.easeOut(duration: reduceMotion ? 0.12 : 0.22), updates)
    }

    private func leave() {
        if let onCancel { onCancel() } else { dismiss() }
    }

    private func text(_ key: String, _ params: [String: Localization.Param]? = nil) -> String {
        localization.editorText("ios.routeGuide." + key, params)
    }

    private func station(_ name: String, code: String?) -> String {
        localization.stationName(name, code: code)
    }

    private func stopDetail(_ stop: Stop) -> String? {
        let times = [stop.arrival, stop.departure].compactMap { $0 }.filter { !$0.isEmpty }
        return times.isEmpty ? nil : times.joined(separator: " · ")
    }

    private func numbered(_ choices: [Choice]) -> [NumberedChoice] {
        choices.enumerated().map { NumberedChoice(number: $0.offset + 1, choice: $0.element) }
    }

    private func visitRows(_ choice: Choice) -> [VisitRow] {
        var occurrences: [String: Int] = [:]
        return choice.stations.map { visit in
            occurrences[visit.code, default: 0] += 1
            return VisitRow(id: visit.code + "#\(occurrences[visit.code]!)", name: visit.name, code: visit.code)
        }
    }

    private func stopRows(_ stops: [Stop]) -> [StopRow] {
        // Preparing assigns visit IDs; the fallback keeps malformed data readable
        // without collapsing repeated station occurrences into the same row.
        var occurrences: [String: Int] = [:]
        return stops.map { stop in
            let code = stop.n02StationCode ?? stop.name
            occurrences[code, default: 0] += 1
            return StopRow(id: stop.routeEditing?.visitID.uuidString ?? code + "#\(occurrences[code]!)", stop: stop)
        }
    }

    private struct PendingChange {
        let confirmed: [String: String]
        let invalidatedCount: Int
    }

    private struct NumberedChoice: Identifiable {
        var id: String { choice.id }
        let number: Int
        let choice: Choice
    }

    private struct VisitRow: Identifiable {
        let id: String
        let name: String
        let code: String
    }

    private struct StopRow: Identifiable {
        let id: String
        let stop: Stop
    }
}

/// One geometry lookup per guide session, using the exact survey intervals
/// selected by the solver. Missing intervals stay missing; no endpoint chord
/// or passenger stop sequence can manufacture railway geometry here.
private struct RailwayGuideGeometry {
    let intervals: [String: [CLLocationCoordinate2D]]
    let stations: [String: CLLocationCoordinate2D]

    init(package: CompactPackage, choices: [RailwayRouteChoices.Choice]) {
        let neededLines = Set(choices.flatMap(\.lineIDs))
        var intervals: [String: [CLLocationCoordinate2D]] = [:]
        var stations: [String: CLLocationCoordinate2D] = [:]
        for line in package.lines where neededLines.contains(line.id) {
            for interval in RailIntervalCodes.intervals(for: line) {
                // A one-vertex interval cannot describe a path.
                guard interval.coordinates.count >= 2 else { continue }
                intervals[interval.code] = interval.coordinates.map {
                    CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
                }
            }
            for station in line.stations {
                stations[station.id] = CLLocationCoordinate2D(
                    latitude: station.coordinate.lat, longitude: station.coordinate.lon)
            }
        }
        self.intervals = intervals
        self.stations = stations
    }
}

private struct RailwayGuideMap: View {
    @Environment(AppLocalization.self) private var localization
    let choices: [RailwayRouteChoices.Choice]
    let geometry: RailwayGuideGeometry
    let selectedID: String?
    let geometryWarning: String

    private var common: Set<String> {
        guard let first = choices.first else { return [] }
        return choices.dropFirst().reduce(Set(first.sectionCodes)) { $0.intersection($1.sectionCodes) }
    }

    private var strokes: [Stroke] {
        let common = common
        var result: [Stroke] = []
        var drawnCommon: Set<String> = []
        for (index, choice) in choices.enumerated() {
            for (occurrence, code) in choice.sectionCodes.enumerated() {
                guard let coordinates = geometry.intervals[code] else { continue }
                let shared = choices.count > 1 && common.contains(code)
                if shared && !drawnCommon.insert(code).inserted { continue }
                result.append(Stroke(
                    id: choice.id + "|\(occurrence)", coordinates: coordinates,
                    number: index + 1, shared: shared,
                    selected: choice.id == selectedID || choices.count == 1))
            }
        }
        // Draw the selected alignment over the other options without moving the camera.
        return result.sorted { !$0.selected && $1.selected }
    }

    private var markers: [Marker] {
        let common = common
        return choices.enumerated().compactMap { index, choice in
            guard !choice.sectionCodes.isEmpty else { return nil }
            let distinguishing = choice.sectionCodes.first { !common.contains($0) }
                ?? choice.sectionCodes[choice.sectionCodes.count / 2]
            guard let coordinates = geometry.intervals[distinguishing], !coordinates.isEmpty else { return nil }
            return Marker(id: choice.id, number: index + 1, coordinate: coordinates[coordinates.count / 2])
        }
    }

    private var endpoints: [Endpoint] {
        guard let choice = choices.first, let origin = choice.stations.first,
              let destination = choice.stations.last else { return [] }
        return [("origin", origin), ("destination", destination)].compactMap { id, visit in
            guard let coordinate = geometry.stations[visit.code] else { return nil }
            return Endpoint(id: id, name: localization.stationName(visit.name, code: visit.code), coordinate: coordinate)
        }
    }

    private var missingGeometry: Bool {
        choices.contains { choice in choice.sectionCodes.contains { geometry.intervals[$0] == nil } }
    }

    private var region: MKCoordinateRegion {
        // The bounds depend on all candidates, never on the previewed card.
        let coordinates = choices.flatMap { choice in
            choice.sectionCodes.flatMap { geometry.intervals[$0] ?? [] }
        }
        guard let first = coordinates.first else {
            let stationCoordinates = choices.flatMap(\.stations).compactMap { geometry.stations[$0.code] }
            guard let anchor = stationCoordinates.first else {
                return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 35.7, longitude: 139.7),
                                          span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1))
            }
            return MKCoordinateRegion(center: anchor, span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1))
        }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: max(0.012, (maxLat - minLat) * 1.35),
                                   longitudeDelta: max(0.012, (maxLon - minLon) * 1.35)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Map(initialPosition: .region(region), interactionModes: [.pan, .zoom]) {
                ForEach(strokes) { stroke in
                    MapPolyline(coordinates: stroke.coordinates)
                        .stroke(stroke.shared ? Color.secondary.opacity(0.55) : Self.color(stroke.number).opacity(stroke.selected ? 1 : 0.65),
                                style: StrokeStyle(lineWidth: stroke.selected && !stroke.shared ? 6 : 4, lineCap: .round, lineJoin: .round))
                }
                ForEach(markers) { marker in
                    Annotation("", coordinate: marker.coordinate) {
                        Text("\(marker.number)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Self.color(marker.number), in: Circle())
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                            .accessibilityHidden(true)
                    }
                }
                ForEach(endpoints) { endpoint in
                    Annotation(endpoint.name, coordinate: endpoint.coordinate, anchor: .bottom) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.primary)
                            .background(.background, in: Circle())
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false))
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .accessibilityIdentifier("routeGuideMap")
            if missingGeometry {
                Label(geometryWarning, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    static func color(_ number: Int) -> Color {
        let palette: [Color] = [.blue, .orange, .purple, .green, .pink, .cyan]
        return palette[(max(1, number) - 1) % palette.count]
    }

    private struct Stroke: Identifiable {
        let id: String
        let coordinates: [CLLocationCoordinate2D]
        let number: Int
        let shared: Bool
        let selected: Bool
    }

    private struct Marker: Identifiable {
        let id: String
        let number: Int
        let coordinate: CLLocationCoordinate2D
    }

    private struct Endpoint: Identifiable {
        let id: String
        let name: String
        let coordinate: CLLocationCoordinate2D
    }
}

private struct RailwayGuideInspectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppLocalization.self) private var localization
    let choices: [RailwayRouteChoices.Choice]
    let geometry: RailwayGuideGeometry
    let selectedID: String?
    let title: String
    let geometryWarning: String

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    RailwayGuideMap(choices: choices, geometry: geometry,
                                    selectedID: selectedID, geometryWarning: geometryWarning)
                    ForEach(options) { option in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 10) {
                                Text(option.number.formatted(.number.locale(localization.locale)))
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(.white)
                                    .frame(width: 28, height: 28)
                                    .background(RailwayGuideMap.color(option.number), in: Circle())
                                Text(option.choice.lineNames.joined(separator: " · ")).font(.headline)
                            }
                            Text(option.choice.stations.map {
                                localization.stationName($0.name, code: $0.code)
                            }.joined(separator: " → "))
                            .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(localization.text("ios.done")) { dismiss() }
                }
            }
        }
    }

    private var options: [Option] {
        choices.enumerated().map { Option(number: $0.offset + 1, choice: $0.element) }
    }

    private struct Option: Identifiable {
        var id: String { choice.id }
        let number: Int
        let choice: RailwayRouteChoices.Choice
    }
}
