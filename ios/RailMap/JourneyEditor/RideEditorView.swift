import RailCore
import RailApplication
import RailPresentation
import SwiftUI

/// A local draft is committed once; cancelling never changes the saved journey.
/// Guided creation stays in `NewTripView`. This form edits an existing ride.
struct RideEditorView: View {
    @Environment(AppLocalization.self) private var localization
    @Environment(RailNetworkStore.self) private var network
    @Environment(ItineraryStore.self) private var itineraries: ItineraryStore?
    @Environment(RiddenRouteStore.self) private var riddenRoutes: RiddenRouteStore?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private enum OfficialEnglishName {
        case loading
        case available(String)
        case unavailable

        var value: String? {
            if case .available(let name) = self { return name }
            return nil
        }
    }
    @State private var officialEnglishName: OfficialEnglishName = .loading
    @State private var draft: Train
    @State private var baseline: Train
    /// Preserve persisted visit identity across route changes and reopening.
    @State private var stopIDs: [UUID]
    @State private var showsDiscardConfirmation = false
    @State private var showsAICompletion = false
    @State private var limitedExpressName = ""
    @State private var addedStopID: UUID?
    @State private var stopEditMode: EditMode = .inactive
    /// The stops removed by the last delete, with the rows they came from.
    ///
    /// §8.6 asks for an undo before a confirmation, and here undo is exactly
    /// reliable: the draft is a value held in this view and nothing has been
    /// committed, so putting the rows back is arithmetic rather than a
    /// recovery. A confirmation would be asking permission to do something
    /// that costs nothing to reverse.
    @State private var undoableDeletion: [Deletion] = []
    /// The JP limited-express pattern picker and its replace-existing-stops
    /// confirmation. The picker is presented as a sheet; a chosen pattern is
    /// held here so the confirmation dialog (when needed) can apply it.
    @State private var showsServicePatternPicker = false
    @State private var showsReplaceStopsConfirmation = false
    @State private var pendingTimetableTrip: TrainTimetableDatabase.Trip?
    /// The pattern chosen in this editing session. Kept separately from the
    /// editable stops so a later date change can be checked without rewriting
    /// any of the reader's subsequent edits.
    @State private var selectedPattern: TrainServicePatterns.Pattern?
    @State private var selectedTimetableDate: String?
    /// Recomputed once per draft change rather than once per field.
    ///
    /// The authoritative half of the validation encodes the draft and runs
    /// `TrainValidation.validateTrain` over it; a `body` that called it from
    /// every field's inline message would run that a dozen times per
    /// keystroke, on a form whose stop list can be forty rows long.
    @State private var issues: [RideDraftIssue] = []
    @State private var aiDenial: EditorAIDenial?
    /// Catalog for station resolution and draft-pin coordinates. Nil until loaded.
    @State private var editorCatalog: EditorCatalog?
    /// Stable catalog identity for route choices during this editor session.
    /// The document schema stores line/operator names, so these ids are mapped
    /// back only when committing the picker.
    @State private var selectedCatalogLineIDs: Set<String> = []
    @State private var selectedRouteChoice: RailwayRouteChoices.Choice?
    @State private var generatedStopIDs: Set<UUID> = []
    @State private var routeChoicesLoaded = false
    @State private var routeChoiceLoadError: String?
    @State private var routePackage: CompactPackage?
    @State private var showsLocalJourneyFill = false
    @State private var localJourneyCommit: LocalJourneyAutofill.Proposal?
    @State private var localJourneyUndo: LocalJourneyUndo?

    private struct LocalJourneyUndo {
        let before: Train
        let after: Train
        let previousChoice: RailwayRouteChoices.Choice?
        let previousLineIDs: Set<String>
        let previousPattern: TrainServicePatterns.Pattern?
        let previousTimetableDate: String?
    }
    @State private var routeGuideRequest: RouteGuideRequest?
    @State private var routeInferenceTask: Task<Void, Never>?
    @State private var isInferringRoute = false
    @State private var routeInferenceFailed = false
    @State private var acceptedRouteStopCodes: [String?]?
    @State private var pendingRouteCommit: RouteCommit?
    @State private var routeEditUndo: RailwayRouteEditing.Undo?
    @State private var routeEditSummary: String?
    @State private var routeGuideError = false
    /// Last direction word written by inference. A matching field may be replaced.
    @State private var autoInferredDirection: String?
    @State private var directionBasisSeen = ""
    /// Timetable apply owns `direction` for the draft change that follows.
    @State private var holdOfficialDirection = false
    /// The reader set Direction, including confirming the same word or clearing it.
    @State private var userDirectionEdited = false
    @State private var isRepairingRoute = false
    @State private var routeRepairSummary: String?
    @State private var routeRepairSnapshot: Train?
    @State private var routeCommitAfterDismiss: RouteCommit?
    @State private var routeUndoCatalogLineIDs: Set<String> = []
    /// The route choice in effect before the last apply. Undo restores it with
    /// the stops, so visits on the restored route still delete through the guide.
    @State private var routeUndoChoice: RailwayRouteChoices.Choice?

    private struct RepairContinuation {
        var remaining: [RouteRepairFlow.Step]
        var repaired: Int
        var gaps: [RouteRepairFlow.GapName]
        var snapshot: Train
    }

    private struct RouteCommit {
        let plan: RailwayRouteEditing.Plan
        let choice: RailwayRouteChoices.Choice
        var continuation: RepairContinuation?
    }

    private struct RouteGuideRequest: Identifiable {
        let id = UUID()
        var train: Train
        var package: CompactPackage
        var excludedCodes: Set<String> = []
        var inferredChoices: [RailwayRouteChoices.Choice]?
        var focus: (fromVisitID: UUID, toVisitID: UUID)?
        var repairContinuation: RepairContinuation?
    }

    /// Cross-border journeys can carry station codes from more than one
    /// package. Keep those small, cached catalogs available for draft pins.
    @State private var editorCatalogs: [String: EditorCatalog] = [:]
    @State private var draftMapRevision = 0
    @State private var publishedDraftPins: [DraftStopPin]?
    @State private var publishedDraftNetworkDate: String?
    @FocusState private var focused: RideDraftIssue.Field?

    let original: Train
    let title: String
    let onSave: (Train) -> Void
    let onCancel: () -> Void
    var onDraftMap: (DraftMapSnapshot) -> Void = { _ in }
    var highlightedStopID: Binding<UUID?> = .constant(nil)
    let suggestionTrains: [Train]
    /// Ids already in the store, so an id collision is visible while it is
    /// being typed rather than after the save quietly keeps the old one.
    /// When omitted, the editor reads ``ItineraryStore/trainIDs``.
    var existingIDs: Set<String>?

    private struct Deletion: Equatable {
        var offset: Int
        var stop: Stop
        var id: UUID
    }

    init(
        train: Train,
        title: String = "Edit journey",
        existingIDs: Set<String>? = nil,
        suggestionTrains: [Train] = [],
        onCancel: @escaping () -> Void,
        onDraftMap: @escaping (DraftMapSnapshot) -> Void = { _ in },
        highlightedStopID: Binding<UUID?> = .constant(nil),
        onSave: @escaping (Train) -> Void
    ) {
        original = train
        self.title = title
        self.existingIDs = existingIDs
        self.suggestionTrains = suggestionTrains
        _draft = State(initialValue: train)
        _baseline = State(initialValue: train)
        _stopIDs = State(initialValue: train.stops.map { $0.routeEditing?.visitID ?? UUID() })
        _generatedStopIDs = State(initialValue: Set(train.stops.compactMap {
            $0.routeEditing?.generatedBy == nil ? nil : $0.routeEditing?.visitID
        }))
        self.onSave = onSave
        self.onCancel = onCancel
        self.onDraftMap = onDraftMap
        self.highlightedStopID = highlightedStopID
    }

    var body: some View {
        editorRoutePresentations
        .sheet(isPresented: $showsAICompletion) {
            JourneyCompletionView(
                trains: [draft],
                context: limitedExpressName.isEmpty ? ""
                    : "Limited express service name: \(limitedExpressName)",
                allowsRawImport: true,
                onApply: { completed in
                    guard var train = completed.first else { return }
                    if train.stops != draft.stops || train.routeSections != draft.routeSections {
                        if train.routeConfirmation == .confirmed { train.routeConfirmation = nil }
                    }
                    applyCompletedDraft(train)
                })
        }
        .confirmationDialog(
            localization.text("ios.editor.replaceExistingStopsTitle"),
            isPresented: $showsReplaceStopsConfirmation, titleVisibility: .visible
        ) {
            Button(localization.text("ios.editor.replaceExistingStops"), role: .destructive) {
                if let trip = pendingTimetableTrip {
                    pendingTimetableTrip = nil
                    applyTimetableTrip(trip)
                } else {
                    showsServicePatternPicker = true
                }
            }
            .accessibilityIdentifier("rideEditorReplaceStops")
            Button(localization.text("ios.cancel", fallback: "Cancel"), role: .cancel) {
                pendingTimetableTrip = nil
            }
            .accessibilityIdentifier("rideEditorKeepStops")
        }
        .onChange(of: showsReplaceStopsConfirmation) { _, presented in
            if !presented { pendingTimetableTrip = nil }
        }
        .sheet(isPresented: $showsServicePatternPicker) {
            servicePatternPicker
        }
        .interactiveDismissDisabled(draft != baseline)
    }

    private var editorNavigation: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                editorLoadingEvents(proxy)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(localization.text("ios.cancel", fallback: "Cancel")) {
                            if draft == baseline {
                                onCancel()
                            } else {
                                showsDiscardConfirmation = true
                            }
                        }
                        .accessibilityIdentifier("rideEditorCancel")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        // §5.4 uses the specific verb: 保存旅程, not 完成.
                        Button(localization.text("ios.editor.saveJourney")) {
                            guard blocking.isEmpty, draft.journeyGroup?.name.isEmpty != true else { return }
                            saveDraft()
                        }
                        .accessibilityIdentifier("rideEditorSave")
                        // §7.6: the primary action takes the one filled
                        // emphasis on the screen. Cancel and Save were the
                        // same glass capsule with the same white label at the
                        // same weight, so the row said nothing about which of
                        // the two commits the reader's work — and the two sit
                        // a thumb's width apart.
                        .buttonStyle(.borderedProminent)
                        .disabled(!blocking.isEmpty || draft.journeyGroup?.name.isEmpty == true)
                        // §10.3's ⌘S. On the button rather than on the form,
                        // so it is disabled by exactly the same condition —
                        // a shortcut that commits a draft the button refuses
                        // would be a second, looser save path.
                        .keyboardShortcut("s", modifiers: .command)
                    }
                }
            }
            // §5.4: leaving a dirty draft asks; a clean one just closes.
            .confirmationDialog(
                localization.text("ios.editor.discardTitle"),
                isPresented: $showsDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button(
                    localization.text("ios.editor.discardChanges"),
                    role: .destructive
                ) { onCancel() }
                Button(localization.text("ios.editor.keepEditing"), role: .cancel) {}
            } message: {
                Text(localization.text("ios.editor.discardDetail"))
            }
        }
    }

    private func editorForm(_ proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 0) {
        Form {
            if !blocking.isEmpty { problemSummary(proxy) }
            basicsSection
            stationsSection
            routeSelectionSection
            stopsSection
            localLineServicesSection
            searchableDetailsSection
            serviceSectionsSection
            journeyStatusSection
            journeyGroupSection
            routingSection
            styleSection
            recordSection
            completionSection
        }
        .accessibilityIdentifier("rideEditorForm")
        // Inline, and short. §14.5 forbids a fixed English-width
        // assumption, and the large title fought both toolbar buttons
        // for the same row and lost — 「乗車記録を編集」 came back as
        // 「乗車記録…」, a heading truncated to a stub. The specific
        // verb the spec asks for is on the SAVE button, which is where
        // it does work; this row only has to say which surface this is.
        }
    }

    private func editorDraftEvents(_ proxy: ScrollViewProxy) -> some View {
        editorForm(proxy)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .task(id: Region.resolved(draft)) { network.ensure(Region.resolved(draft)) }
        .navigationDestination(item: $addedStopID) { stopID in
            if let index = stopIDs.firstIndex(of: stopID) {
                StopEditorView(stop: editableStop(stopID), journeyDate: $draft.date,
                               index: index, region: Region.resolved(draft),
                               selectedLineIDs: selectedCatalogLineIDs)
            }
        }
        .environment(\.editMode, $stopEditMode)
        .onChange(of: draft, initial: true) { before, after in
            if before.stops != after.stops || before.routePolicy != after.routePolicy {
                routeInferenceFailed = false
            }
            let visitsChanged = before.stops.map(\.n02StationCode) != after.stops.map(\.n02StationCode)
            if visitsChanged && before.routeSections == after.routeSections
                && after.routeConfirmation == .confirmed
                && acceptedRouteStopCodes != after.stops.map(\.n02StationCode) {
                draft.routeConfirmation = nil
            }
            acceptedRouteStopCodes = nil
            revalidate()
            if holdOfficialDirection {
                holdOfficialDirection = false
                directionBasisSeen = directionBasis(after)
            } else {
                refreshAutoDirection()
            }
        }
        .onChange(of: routeChoicesLoaded) { _, loaded in
            if loaded { refreshAutoDirection(force: true) }
        }
        .onChange(of: draft.stops, initial: true) { _, _ in publishDraftMap() }
        .onChange(of: draft.date) { _, _ in publishDraftMap() }
        .onChange(of: stopIDs) { _, _ in publishDraftMap() }
        .onChange(of: highlightedStopID.wrappedValue) { _, id in
            guard let id, stopIDs.contains(id) else { return }
            addedStopID = id
            highlightedStopID.wrappedValue = nil
        }
    }

    private func editorLoadingEvents(_ proxy: ScrollViewProxy) -> some View {
        editorDraftEvents(proxy)
        .task(id: officialNameQuery) {
            officialEnglishName = .loading
            let train: Train = {
                var value = draft
                value.region = Region.resolved(draft).code
                return value
            }()
            let result = await Task.detached(priority: .userInitiated) {
                guard TrainTimetableDatabase.accepts(train) else { return String?.none }
                let database: TrainTimetableDatabase
                do {
                    database = try TrainTimetableDatabase.bundled(country: train.region ?? "jp")
                } catch {
                    return String?.none
                }
                return try? JourneyEnglishName.official(for: train, database: database)
            }.value
            guard !Task.isCancelled else { return }
            officialEnglishName = result.map(OfficialEnglishName.available) ?? .unavailable
        }
        .task(id: routeChoiceTaskID) { await loadRouteChoices() }
        .onDisappear {
            routeInferenceTask?.cancel()
            routeInferenceTask = nil
            isInferringRoute = false
        }
        .task(id: catalogTaskID) {
            let region = Region.resolved(draft)
            let loaded = try? await Task.detached(priority: .userInitiated) {
                try loadCatalog(for: region)
            }.value
            guard !Task.isCancelled else { return }
            editorCatalog = loaded
            if let loaded {
                editorCatalogs[region.code] = loaded
                let matched = CatalogLinePreferenceMapping.matching(
                    lineNames: draft.routePolicy?.preferredLineNames ?? [],
                    operatorNames: draft.routePolicy?.preferredOperatorNames ?? [],
                    regionCode: region.code,
                    catalog: loaded)
                selectedCatalogLineIDs = selectedRouteChoice.map { Set($0.lineIDs) } ?? Set(matched.lineIDs)
            } else {
                selectedCatalogLineIDs = []
            }
            for regionCode in draftPinRegionCodes where editorCatalogs[regionCode] == nil {
                guard let pinRegion = Region(rawValue: regionCode) else { continue }
                let pinCatalog = try? await Task.detached(priority: .utility) {
                    try loadCatalog(for: pinRegion)
                }.value
                guard !Task.isCancelled else { return }
                if let pinCatalog { editorCatalogs[regionCode] = pinCatalog }
            }
            revalidate()
            publishDraftMap()
        }
#if DEBUG
        // Scroll straight to a named section, for the same reason the
        // other `RAILMAP_UI_TEST_*` hooks exist: a screenshot harness
        // cannot scroll a form, so anything below the first screen —
        // the region row, the route sections and their messages —
        // would never be reviewed outside a hand session.
        .task {
            await scrollToRequestedSection(proxy)
        }
#endif
        .onChange(of: publishedIDs, initial: true) { _, _ in revalidate() }
    }

    private func routeGuideSheet(_ request: RouteGuideRequest) -> some View {
        NavigationStack {
            if let choices = request.inferredChoices,
               let fromID = request.focus?.fromVisitID ?? request.train.stops.first?.routeEditing?.visitID,
               let toID = request.focus?.toVisitID ?? request.train.stops.last?.routeEditing?.visitID {
                RailwayRouteGuideView(train: request.train, package: request.package,
                    choices: choices, embeddedInNavigationStack: true,
                    onPending: markRoutePending, isInferred: true,
                    fromVisitID: fromID, toVisitID: toID) { selected in
                    proposeRouteChoice(selected, fromID: fromID, toID: toID)
                }
            } else {
                RailwayRouteCorrectionView(
                    train: request.train, package: request.package,
                    excludedStationCodes: request.excludedCodes, focus: request.focus,
                    onPending: markRoutePending
                ) { choice, fromID, toID in
                    proposeRouteChoice(choice, fromID: fromID, toID: toID)
                }
            }
        }
        .alert(localization.text("ios.routeGuide.routeUnavailable"), isPresented: $routeGuideError) {
            Button(localization.text("ios.done"), role: .cancel) {}
        }
        .confirmationDialog(
            localization.text("ios.routeGuide.removalTitle"),
            isPresented: Binding(get: { pendingRouteCommit != nil }, set: {
                if !$0 { pendingRouteCommit = nil }
            }), titleVisibility: .visible, presenting: pendingRouteCommit
        ) { commit in
            Button(localization.text("ios.routeGuide.removeAndApply"), role: .destructive) {
                commitRoutePlan(commit.plan, choice: commit.choice, continuation: commit.continuation)
            }
            Button(localization.text("ios.editor.keepEditing"), role: .cancel) {
                pendingRouteCommit = nil
            }
        } message: { commit in
            Text(localization.text("ios.routeGuide.removalDetail", params: [
                "stations": .string(commit.plan.conflictingStops.map(\.name).joined(separator: " · "))
            ]))
        }
    }

    private var editorRoutePresentations: some View {
        editorNavigation
        .sheet(isPresented: $showsLocalJourneyFill, onDismiss: finishLocalJourneyFill) {
            if let package = routePackage {
                LocalJourneyFillView(train: routeEditingDraft, package: package, onPending: { pending in
                    applyCompletedDraft(pending)
                    markRoutePending()
                    showsLocalJourneyFill = false
                }) { proposal in
                    localJourneyCommit = proposal
                    showsLocalJourneyFill = false
                }
            }
        }
        .sheet(item: $routeGuideRequest, onDismiss: finishRouteGuide) { request in
            routeGuideSheet(request)
        }
    }

    private var servicePatternPicker: some View {
        ServicePatternPickerView(
            region: Region.resolved(draft).code,
            rideDate: draft.date.flatMap { $0.isEmpty ? nil : $0 },
            onSelectDate: { draft.date = $0 },
            onSelectTrip: { applyTimetableTrip($0) },
            onSelectDraft: { applyTimetableTrip($0) }
        ) { pattern, reversed in
            let ridden = RideLedger.hasBeenRidden(draft)
            resetRouteChoiceState()
            draft = TrainServicePatterns.apply(pattern, to: draft, reversed: reversed, ridden: ridden)
            selectedPattern = pattern
            selectedTimetableDate = nil
            synchronizeStopIdentity()
            undoableDeletion = []
            addedStopID = nil
        }
    }

    private func applyTimetableTrip(_ trip: TrainTimetableDatabase.Trip) {
        guard Region.resolved(draft) == .jp else { return }
        let ridden = RideLedger.hasBeenRidden(draft)
        guard let drafted = JourneyDraftWork.timetableDraft(from: trip, appliedTo: draft, ridden: ridden)
        else { return }
        resetRouteChoiceState()
        holdOfficialDirection = true
        draft = drafted.train
        TimetableRouteEvidence.rememberAppliedOccurrence(trip: trip, train: drafted.train)
        selectedTimetableDate = drafted.serviceDate
        limitedExpressName = drafted.serviceName
        selectedPattern = drafted.pattern
        synchronizeStopIdentity()
        undoableDeletion = []
        addedStopID = nil
    }

    /// Keep editor occurrence identity only when completion updates the same
    /// ordered station visits. A raw import can replace the entire route even
    /// when the number of stops happens to stay the same.
    private func applyCompletedDraft(_ completed: Train) {
        let previous = Dictionary(zip(stopIDs, draft.stops), uniquingKeysWith: { first, _ in first })
        let existingIDs = stopIDs
        let sameVisits = stopIDs.count == draft.stops.count
            && draft.stops.count == completed.stops.count
            && zip(draft.stops, completed.stops).allSatisfy { pair in
                pair.0.name == pair.1.name
                    && pair.0.n02StationCode == pair.1.n02StationCode
            }
        if !sameVisits {
            stopIDs = completed.stops.map { _ in UUID() }
            addedStopID = nil
            highlightedStopID.wrappedValue = nil
            focused = nil
            stopEditMode = .inactive
            undoableDeletion = []
            selectedPattern = nil
            selectedTimetableDate = nil
        }
        if !sameVisits || draft.routePolicy != completed.routePolicy {
            let region = Region.resolved(completed).code
            if let catalog = editorCatalogs[region] ?? (Region.resolved(draft).code == region ? editorCatalog : nil) {
                let matched = CatalogLinePreferenceMapping.matching(
                    lineNames: completed.routePolicy?.preferredLineNames ?? [],
                    operatorNames: completed.routePolicy?.preferredOperatorNames ?? [],
                    regionCode: region,
                    catalog: catalog)
                selectedCatalogLineIDs = Set(matched.lineIDs)
            } else {
                selectedCatalogLineIDs = []
            }
        }
        var updated = completed
        for index in updated.stops.indices {
            guard let id = updated.stops[index].routeEditing?.visitID,
                  let oldStop = previous[id], updated.stops[index] != oldStop else { continue }
            updated.stops[index].routeEditing?.generatedBy = nil
        }
        if updated.routeConfirmation == .confirmed {
            acceptedRouteStopCodes = updated.stops.map(\.n02StationCode)
        }
        draft = updated
        if sameVisits {
            stopIDs = draft.stops.indices.map { draft.stops[$0].routeEditing?.visitID ?? existingIDs[$0] }
        } else {
            synchronizeStopIdentity()
        }
        resetRouteChoiceState()
    }

#if DEBUG
    private func scrollToRequestedSection(_ proxy: ScrollViewProxy) async {
        guard let wanted = UITestLaunchConfiguration.current[.editorSection] else { return }
        try? await Task.sleep(for: .milliseconds(700))
        switch wanted {
        case "record": proxy.scrollTo(RideDraftIssue.Field.id, anchor: .center)
        case "routing": proxy.scrollTo(RideDraftIssue.Field.routePolicy, anchor: .center)
        default: break
        }
    }
#endif

    private var completionSection: some View {
        let denial: EditorAIDenial? = showsAICompletion ? .requestInFlight : aiDenial
        return Section {
            Button { showsAICompletion = true } label: {
                Label(localization.text("ios.ai.title", fallback: "AI completion"), systemImage: "sparkles")
            }
            .accessibilityIdentifier("rideEditorAICompletion")
            if let denial {
                Text(aiDenialText(denial))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func aiDenialText(_ denial: EditorAIDenial) -> String {
        let key: String
        switch denial {
        case .noResolvedStation: key = "ios.editor.ai.noStation"
        case .noExplicitTime: key = "ios.editor.ai.noTime"
        case .invalidTime: key = "ios.editor.ai.invalidTime"
        case .timeNotOnThatStation: key = "ios.editor.ai.timeNotOnStation"
        case .requestInFlight: key = "ios.editor.ai.busy"
        case .providerUnavailable: key = "ios.editor.ai.busy"
        }
        return localization.text(key)
    }

    private func publishDraftMap() {
        let pins = draftPins()
        let networkDate = Dates.normalizeDateString(draft.date)
        guard pins != publishedDraftPins || networkDate != publishedDraftNetworkDate else { return }
        publishedDraftPins = pins
        publishedDraftNetworkDate = networkDate
        draftMapRevision += 1
        onDraftMap(DraftMapPins.snapshot(
            revision: draftMapRevision, pins: pins, networkRideDate: networkDate))
    }

    private func draftPins() -> [DraftStopPin] {
        let fallbackRegion = Region.resolved(draft).code
        guard stopIDs.count == draft.stops.count else { return [] }
        return zip(stopIDs, draft.stops).map { id, stop in
            let code = stop.n02StationCode ?? ""
            let region = Region.fromStationCode(code)?.code ?? fallbackRegion
            let station = code.isEmpty
                ? nil
                : editorCatalogs[region]?.station(StationKey(regionCode: region, sourceCode: code))
            let arrival = EditorTime.parseTime(stop.arrival)
            let departure = EditorTime.parseTime(stop.departure)
            func canonical(_ parse: ServiceTimeParse) -> String? {
                if case .valid(_, let time) = parse { return EditorTime.canonical(time) }
                return nil
            }
            func offset(_ parse: ServiceTimeParse) -> Int? {
                if case .valid(_, let time) = parse { return time.dayOffset }
                return nil
            }
            var timeParts: [String] = []
            if let time = canonical(arrival) {
                timeParts.append("\(localization.countryText("popup.arrival", fallback: "Arrival")): \(time)")
            }
            if let time = canonical(departure) {
                let key = stop.stopType == "pass_through" ? "ios.editor.passTime" : "popup.departure"
                let label = stop.stopType == "pass_through"
                    ? localization.text(key)
                    : localization.countryText(key, fallback: "Departure")
                timeParts.append("\(label): \(time)")
            }
            return DraftStopPin(
                occurrenceID: id,
                name: stop.name,
                stopType: stop.stopType,
                timeText: timeParts.joined(separator: " · "),
                dayOffset: [offset(arrival), offset(departure)].compactMap { $0 }.max() ?? 0,
                latitude: station?.latitude,
                longitude: station?.longitude)
        }
    }

    private var draftPinRegionCodes: [String] {
        var codes = [Region.resolved(draft).code]
        for stop in draft.stops {
            guard let code = Region.fromStationCode(stop.n02StationCode)?.code,
                  !codes.contains(code)
            else { continue }
            codes.append(code)
        }
        return codes
    }

    private var catalogTaskID: String {
        "\(Region.resolved(draft).code)|\(draftPinRegionCodes.joined(separator: "+"))"
    }

    private var routeChoiceTaskID: String { Region.resolved(draft).code }

    private func loadRouteChoices() async {
        let region = Region.resolved(draft)
        routeChoicesLoaded = false
        routeChoiceLoadError = nil
        routePackage = nil
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let package = try await DisplayNetworkCache.shared.package(country: region.code).package
            try Task.checkCancellation()
            return package
        }
        do {
            let package = try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: { worker.cancel() }
            guard !Task.isCancelled else { return }
            routePackage = package
            routeChoicesLoaded = true
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            routeChoiceLoadError = error.localizedDescription
            routeChoicesLoaded = true
        }
    }

    /// Opening the guide does not mutate the draft, including legacy identity.
    private var routeEditingDraft: Train {
        var value = draft
        for index in value.stops.indices where stopIDs.indices.contains(index) {
            if value.stops[index].routeEditing == nil {
                value.stops[index].routeEditing = Stop.RouteEditingMetadata(visitID: stopIDs[index])
            }
        }
        return value
    }

    private func openRouteGuide(excluding codes: Set<String> = []) {
        guard let package = routePackage else { return }
        pendingRouteCommit = nil
        routeGuideRequest = RouteGuideRequest(train: routeEditingDraft, package: package, excludedCodes: codes)
    }

    /// Inference only proposes a route; the existing preview owns confirmation.
    private func markRoutePending() {
        routeInferenceTask?.cancel()
        routeInferenceTask = nil
        isInferringRoute = false
        draft.routeConfirmation = .pending
        routeCommitAfterDismiss = nil
        pendingRouteCommit = nil
        routeGuideRequest = nil
        routeInferenceFailed = false
    }

    private func inferRoute() {
        guard let package = routePackage, !isInferringRoute else { return }
        let snapshot = draft
        let prepared = routeEditingDraft
        routeInferenceFailed = false
        routeChoiceLoadError = nil
        isInferringRoute = true
        routeInferenceTask = Task {
            let worker = Task.detached(priority: .userInitiated) {
                let aliases = try loadJourneyStationAliases(for: prepared.stops.compactMap(\.n02StationCode), package: package)
                return RecordedRouteAdmission.admission(
                    in: prepared, package: package, stationAliases: aliases, maximumExpansions: 200_000)
            }
            let result: RecordedRouteAdmission.Outcome
            do {
                result = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: { worker.cancel() }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                isInferringRoute = false
                guard draft == snapshot else { return }
                routeChoiceLoadError = error.localizedDescription
                return
            }
            guard !Task.isCancelled else { return }
            isInferringRoute = false
            guard draft == snapshot else { return }
            if let choice = result.automaticChoice,
               let plan = RailwayRouteEditing.plan(train: prepared, choice: choice),
               !plan.requiresConfirmation {
                applyRoutePlan(plan, choice: choice)
                return
            }
            guard !result.choices.isEmpty else { routeInferenceFailed = true; return }
            pendingRouteCommit = nil
            // A unique package or corridor proposal keeps its admission origin
            // when the stop edit still needs confirmation. The raw search choice
            // would look like a passenger selection.
            let guided = result.automaticChoice.map { [$0] } ?? result.choices
            routeGuideRequest = RouteGuideRequest(train: prepared, package: package, inferredChoices: guided)
        }
    }

    private func proposeRouteChoice(_ choice: RailwayRouteChoices.Choice, fromID: UUID, toID: UUID) {
        let continuation = routeGuideRequest?.repairContinuation
        guard let plan = RailwayRouteEditing.plan(
            train: routeEditingDraft, choice: choice, fromVisitID: fromID, toVisitID: toID
        ) else { routeGuideError = true; return }
        if plan.requiresConfirmation {
            pendingRouteCommit = RouteCommit(plan: plan, choice: choice, continuation: continuation)
        } else {
            commitRoutePlan(plan, choice: choice, continuation: continuation)
        }
    }

    private func commitRoutePlan(
        _ plan: RailwayRouteEditing.Plan, choice: RailwayRouteChoices.Choice,
        continuation: RepairContinuation? = nil
    ) {
        // Let the guide leave first so the reader can see the list change.
        routeCommitAfterDismiss = RouteCommit(plan: plan, choice: choice, continuation: continuation)
        pendingRouteCommit = nil
        routeGuideRequest = nil
    }

    private func finishLocalJourneyFill() {
        guard let proposal = localJourneyCommit else { return }
        localJourneyCommit = nil
        let before = draft
        let previousChoice = selectedRouteChoice
        let previousLineIDs = selectedCatalogLineIDs
        let previousPattern = selectedPattern
        let previousTimetableDate = selectedTimetableDate
        var completed = proposal.train
        if completed.number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            completed.number = completed.origin + " → " + completed.destination
        }
        if !proposal.choice.operatorNames.isEmpty {
            RegistryIdentityUpgrade.reassignCompany(
                proposal.choice.operatorNames.joined(separator: " / "), on: &completed)
        }
        applyCompletedDraft(completed)
        selectedRouteChoice = proposal.choice
        selectedCatalogLineIDs = Set(proposal.choice.lineIDs)
        selectedPattern = nil
        selectedTimetableDate = nil
        // Settle editor-derived direction before capturing the exact Undo draft.
        refreshAutoDirection()
        localJourneyUndo = LocalJourneyUndo(before: before, after: draft,
            previousChoice: previousChoice, previousLineIDs: previousLineIDs,
            previousPattern: previousPattern, previousTimetableDate: previousTimetableDate)
    }

    private func finishRouteGuide() {
        pendingRouteCommit = nil
        guard let commit = routeCommitAfterDismiss else { return }
        routeCommitAfterDismiss = nil
        applyRoutePlan(commit.plan, choice: commit.choice)
        if let continuation = commit.continuation {
            continueRepair(applied: 1, continuation)
        }
    }

    private func applyRoutePlan(_ plan: RailwayRouteEditing.Plan, choice: RailwayRouteChoices.Choice) {
        routeUndoCatalogLineIDs = selectedCatalogLineIDs
        routeUndoChoice = selectedRouteChoice
        routeEditUndo = plan.undo
        withAnimation(reduceMotion ? .easeOut(duration: 0.16)
            : .timingCurve(0.77, 0, 0.175, 1, duration: 0.24)) {
            acceptedRouteStopCodes = plan.updatedTrain.stops.map(\.n02StationCode)
            draft = plan.updatedTrain
            synchronizeStopIdentity()
            selectedRouteChoice = choice
            selectedCatalogLineIDs = Set(plan.updatedTrain.routeSections?.flatMap { $0.lineIDs ?? [] }
                ?? choice.lineIDs)
            undoableDeletion = []
            routeEditSummary = localization.text("ios.routeGuide.updated", params: [
                "added": .number(Double(plan.insertedStops.count)),
                "removed": .number(Double(plan.removedStops.count + plan.conflictingStops.count))
            ])
        }
    }

    private func synchronizeStopIdentity() {
        stopIDs = draft.stops.map { $0.routeEditing?.visitID ?? UUID() }
        generatedStopIDs = Set(draft.stops.compactMap {
            $0.routeEditing?.generatedBy == nil ? nil : $0.routeEditing?.visitID
        })
    }

    /// Editing an automatic visit promotes it to an authored visit permanently.
    private func editableStop(_ id: UUID) -> Binding<Stop> {
        Binding(get: {
            guard let index = stopIDs.firstIndex(of: id), draft.stops.indices.contains(index) else {
                return Stop(name: "")
            }
            return draft.stops[index]
        }, set: { value in
            guard let index = stopIDs.firstIndex(of: id), draft.stops.indices.contains(index) else { return }
            var updated = value
            let previous = draft.stops[index]
            if updated.name != previous.name || updated.n02StationCode != previous.n02StationCode {
                updated.stationID = nil
            }
            if updated != previous {
                if updated.routeEditing == nil { updated.routeEditing = Stop.RouteEditingMetadata(visitID: id) }
                updated.routeEditing?.generatedBy = nil
                generatedStopIDs.remove(id)
            }
            draft.stops[index] = updated
        })
    }

    private func resetRouteChoiceState() {
        selectedRouteChoice = nil
        routeUndoChoice = nil
        generatedStopIDs = Set(draft.stops.compactMap {
            $0.routeEditing?.generatedBy == nil ? nil : $0.routeEditing?.visitID
        })
        routeEditUndo = nil
        routeEditSummary = nil
    }

    private var autoFilledStationsNote: some View {
        Label(localization.text("ios.editor.generatedStationsNote"), systemImage: "info.circle")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("rideEditorAutoFilledStationsNote")
    }

    // MARK: - Why the save is off (§5.4)

    /// Always on screen while the draft is invalid, because a disabled button
    /// cannot answer a tap. §5.4: "保存禁用时必须让用户知道原因；点击不可用的
    /// 视觉区域不应无反馈."
    @ViewBuilder
    private func problemSummary(_ proxy: ScrollViewProxy) -> some View {
        Section {
            ForEach(blocking) { issue in
                Label(message(issue), systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(localization.text("ios.editor.showErrors")) {
                focusFirstProblem(proxy)
            }
            .frame(minHeight: 44)
        } header: {
            Text(localization.text("ios.editor.cannotSaveYet"))
        } footer: {
            Text(localization.text("ios.editor.blockedCount", params: ["count": .number(Double(blocking.count))]))
        }
    }

    /// §5.4: "第一个错误字段应可被『查看错误』动作聚焦."
    private func focusFirstProblem(_ proxy: ScrollViewProxy) {
        guard let issue = blocking.first else { return }
        let target = scrollTarget(for: issue.field)
        if reduceMotion {
            proxy.scrollTo(target, anchor: .center)
        } else {
            withAnimation(RailMotion.spring) {
                proxy.scrollTo(target, anchor: .center)
            }
        }
        if issue.field.isTextField {
            focused = issue.field
        }
    }

    /// Validation identifies stop problems by their current ordinal; scrolling
    /// identifies the mutable row by its stable editor-session id.
    private func scrollTarget(for field: RideDraftIssue.Field) -> AnyHashable {
        if case .stop(let index) = field, stopIDs.indices.contains(index) {
            return AnyHashable(stopIDs[index])
        }
        return AnyHashable(field)
    }

    // MARK: - 1. Basics

    private var basicsSection: some View {
        Section {
            dateFields
            numberFields
            serviceDetails
        } header: {
            Text(localization.text("ios.editor.basics"))
        }
    }

    @ViewBuilder private var dateFields: some View {
            EditorDateField(
                title: localization.text("ios.editor.date"),
                date: $draft.date,
                region: Region.resolved(draft),
                focus: $focused,
                field: .date,
                accessibilityID: "rideEditorDateInput")
                .id(RideDraftIssue.Field.date)
            fieldIssues(.date)
            timetableDateNotice
            if let pattern = selectedPattern,
               let date = draft.date,
               let applicability = pattern.applicability(on: date),
               applicability != .applicable {
                Label(
                    applicability == .notApplicable
                        ? localization.text("ios.editor.patternNotApplicable")
                        : localization.text("ios.editor.patternValidityUnknown"),
                    systemImage: "exclamationmark.triangle"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
                .accessibilityIdentifier("rideEditorPatternDateNotice")
            }

    }

    @ViewBuilder private var timetableDateNotice: some View {
        if let selectedTimetableDate,
           Dates.normalizeDateString(selectedTimetableDate) != Dates.normalizeDateString(draft.date) {
            Label(localization.text("ios.editor.timetableDateChanged", params: ["date": .string(selectedTimetableDate)]),
                  systemImage: "exclamationmark.triangle")
                .font(.footnote).foregroundStyle(.orange)
                .accessibilityIdentifier("rideEditorTimetableDateNotice")
        }
    }

    @ViewBuilder private var numberFields: some View {
            EditorSearchField(
                title: localization.countryText("field.number", fallback: "Train number"),
                text: $draft.number,
                suggestions: serviceSuggestions,
                focus: $focused, field: .number
            )
            .accessibilityIdentifier("rideEditorNumber")
            .id(RideDraftIssue.Field.number)
            fieldIssues(.number)
            englishNameFields
    }

    private var journeyStatusSection: some View {
        Section {
            Toggle(
                localization.text("ios.detail.riddenState"), isOn: riddenBinding)
            if RideLedger.confirmation(of: draft) == .partly {
                // The whole-journey switch reads "on" over a record that is
                // only partly ridden, which is true — it IS being counted —
                // and would be misleading unread. Say how much, and where the
                // rest of it is decided.
                Text(
                    localization.text(
                        "ios.editor.riddenPartlyNote", params: ["n": .number(Double(RideLedger.riddenSegmentCount(draft.stops)))])
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Toggle(localization.text("ios.showOnMap", fallback: "Show on map"), isOn: visibleBinding)
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(localization.text("ios.editor.riddenNote"))
                Text(localization.text("ios.editor.visibilityNote"))
            }
        }
    }

    private struct OfficialNameQuery: Equatable {
        var number: String
        var date: String?
        var region: String
    }

    private var officialNameQuery: OfficialNameQuery {
        OfficialNameQuery(number: draft.number, date: draft.date, region: Region.resolved(draft).code)
    }

    @ViewBuilder private var englishNameFields: some View {
        EditorTextField(
            title: localization.countryText("field.numberEn", fallback: "English name"),
            text: optionalText(\.numberEn))
        .accessibilityIdentifier("rideEditorNumberEn")
        Button {
            guard let name = officialEnglishName.value else { return }
            draft.numberEn = name
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(localization.text("ios.editor.useOfficialEnglishName"))
                if let name = officialEnglishName.value {
                    Text(verbatim: name).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .disabled(officialEnglishName.value == nil)
        .accessibilityIdentifier("rideEditorUseOfficialEnglishName")
        if case .unavailable = officialEnglishName {
            Text(localization.text("ios.editor.officialEnglishNameUnavailable"))
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var serviceDetails: some View {
        Group {
            EditorTextField(
                title: localization.countryText("field.direction", fallback: "Direction"),
                text: directionText,
                onSubmit: { userDirectionEdited = true })
            if showsAutoDirectionBadge, let word = localizedDirectionWord {
                Text("\(word) · \(localization.text("ios.direction.auto"))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("rideEditorDirectionAuto")
            }
        }
    }

    private var regionalHistory: [Train] {
        suggestionTrains.filter { Region.resolved($0) == Region.resolved(draft) }
    }

    private var serviceSuggestions: [String] {
        regionalHistory.map(\.number) + TrainServiceBranding.services
            .filter { $0.region == Region.resolved(draft).code }.flatMap(\.names)
    }

    private var defaultServiceTypes: [String] {
        JourneyDraftWork.serviceTypeIDs.map { localization.text("ios.editor.serviceType.\($0)") }
    }

    private var regionalLines: [RailNetworkStore.DrawnLine] {
        network.lines.filter { $0.region == Region.resolved(draft) }
    }

    private var searchableDetailsSection: some View {
        Section {
            EditorSearchField(
                title: localization.countryText("field.trainType", fallback: "Train type"),
                text: optionalText(\.trainType),
                suggestions: regionalHistory.compactMap(\.trainType) + defaultServiceTypes)
                .accessibilityIdentifier("rideEditorTrainType")
            EditorSearchField(
                title: localization.text("ios.editor.vehicleType"),
                text: optionalText(\.vehicleType),
                suggestions: regionalHistory.compactMap(\.vehicleType))
                .accessibilityIdentifier("rideEditorVehicleType")
            preferredLineSelectionRow
            EditorSearchField(
                title: localization.countryText("field.company", fallback: "Operator"),
                text: companyText,
                suggestions: regionalHistory.compactMap(\.company) + regionalLines.compactMap(\.operatorName),
                matchesIdentity: true,
                identityRegion: Region.resolved(draft).code)
        } header: {
            Text(localization.text("ios.editor.serviceDetails"))
        } footer: {
            Text(localization.text("ios.editor.searchDetailsNote"))
        }
    }

    private var journeyGroupSection: some View {
        Section {
            JourneyGroupChoiceFields(
                selection: $draft.journeyGroup,
                groups: JourneyGroupCatalog.groups(in: suggestionTrains))
        } footer: {
            Text(localization.text("ios.journeyGroup.crossRegion"))
        }
    }

    private var serviceSectionsSection: some View {
        Section {
            ForEach(JourneyServiceSections.legs(of: draft)) { leg in
                NavigationLink {
                    ServiceRangeEditorView(train: $draft, leg: leg)
                } label: {
                    ServiceSectionSummary(leg: leg, train: draft)
                }
                .accessibilityIdentifier("rideEditorServiceLeg-\(leg.id)")
            }
            NavigationLink {
                ServiceRangeEditorView(train: $draft, leg: nil)
            } label: {
                Label(localization.text("ios.editor.addSectionService"), systemImage: "plus.circle")
            }
            .disabled(draft.stops.count < 2)
            .accessibilityIdentifier("rideEditorAddServiceLeg")
            TextField(localization.text("ios.ai.notes"), text: optionalText(\.notes), axis: .vertical)
                .lineLimit(2...5)
                .accessibilityIdentifier("rideEditorNotes")
        } header: {
            Text(localization.text("ios.editor.sectionServices"))
        } footer: {
            Text(localization.text("ios.editor.sectionServicesNote"))
        }
    }

    /// Both editor modes expose the same physical-route workflow beside stops.
    private var routeSelectionSection: some View {
        Section {
            Button { showsLocalJourneyFill = true } label: {
                Label(LocalJourneyStrings.text("title", language: localization.language),
                    systemImage: "point.topleft.down.curvedto.point.bottomright.up")
            }
            .disabled(routePackage == nil)
            .accessibilityIdentifier("rideEditorLocalAutofill")
            if let undo = localJourneyUndo, undo.after == draft {
                Button(localization.text("ios.routeGuide.undo")) {
                    applyCompletedDraft(undo.before)
                    selectedRouteChoice = undo.previousChoice
                    selectedCatalogLineIDs = undo.previousLineIDs
                    selectedPattern = undo.previousPattern
                    selectedTimetableDate = undo.previousTimetableDate
                    localJourneyUndo = nil
                }
                .accessibilityIdentifier("rideEditorLocalAutofillUndo")
            }
            Button { inferRoute() } label: {
                HStack {
                    Label(localization.text("ios.routeGuide.infer"), systemImage: "wand.and.stars")
                    if isInferringRoute { Spacer(); ProgressView() }
                }
            }
            .disabled(isInferringRoute || routePackage == nil || draft.stops.count < 2
                || draft.stops.contains { $0.n02StationCode == nil })
            .accessibilityIdentifier("rideEditorInferRoute")
            if repairSpanCount > 0 {
                Text(localization.text("ios.route.sectionsNeedRepair", params: [
                    "n": .number(Double(repairSpanCount)),
                ]))
                .font(.footnote)
                .foregroundStyle(.secondary)
                Button {
                    repairRoute()
                } label: {
                    HStack {
                        Label(localization.text("ios.route.repairRoute"), systemImage: "wrench.and.screwdriver")
                        if isRepairingRoute { Spacer(); ProgressView() }
                    }
                }
                .disabled(isRepairingRoute || routePackage == nil)
                .accessibilityIdentifier("rideEditorRepairRoute")
            }
            if let routeRepairSummary {
                Text(routeRepairSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("rideEditorRepairSummary")
            }
            if let snapshot = routeRepairSnapshot, snapshot != draft {
                Button(localization.text("ios.routeGuide.undo")) {
                    draft = snapshot
                    synchronizeStopIdentity()
                    undoableDeletion = []
                    routeRepairSnapshot = nil
                    routeRepairSummary = nil
                    routeEditUndo = nil
                    routeEditSummary = nil
                }
                .accessibilityIdentifier("rideEditorRepairUndo")
            }
            guidedLineSelectionRow
            Button(localization.text("ios.routeGuide.keepPending"), action: markRoutePending)
                .accessibilityIdentifier("rideEditorPendingRoute")
            if draft.requiresRouteConfirmation {
                Label(localization.text("ios.routeGuide.pending"), systemImage: "questionmark.circle")
                Text(localization.text("ios.routeGuide.pendingNote"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if routeInferenceFailed {
                Text(localization.text("ios.routeGuide.inferenceFailed"))
                    .font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("rideEditorInferenceFailed")
            }
        } footer: {
            Text(localization.text("ios.routeGuide.inferenceNote"))
        }
    }

    @ViewBuilder private var localLineServicesSection: some View {
        if Region.resolved(draft) == .jp, let package = routePackage {
            LocalLineServicesSection(package: package,
                lineIDs: Array(selectedCatalogLineIDs).sorted(), serviceDate: draft.date,
                trainType: optionalText(\.trainType))
        }
    }

    private var preferredLineSelectionRow: some View {
        NavigationLink {
            EditorLineSearchView(
                region: Region.resolved(draft),
                lineNames: draft.routePolicy?.preferredLineNames ?? [],
                operatorNames: draft.routePolicy?.preferredOperatorNames ?? [],
                selectedLineIDs: selectedCatalogLineIDs,
                stationCodes: SolverRegistryInput.solveInputCodes(
                    stops: draft.stops, region: Region.resolved(draft).code),
                onCommit: { lineIDs, lineNames, operatorNames in
                    selectedCatalogLineIDs = Set(lineIDs)
                    var policy = routePolicy.wrappedValue
                    policy.preferredLineNames = lineNames.isEmpty ? nil : lineNames
                    policy.preferredOperatorNames = operatorNames.isEmpty ? nil : operatorNames
                    draft.routePolicy = policy
                })
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Label(localization.text("ios.editor.searchLines"), systemImage: "magnifyingglass")
                if let names = draft.routePolicy?.preferredLineNames, !names.isEmpty {
                    Text(names.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let operators = draft.routePolicy?.preferredOperatorNames, !operators.isEmpty {
                    Text(operators.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityIdentifier("rideEditorPreferredLines")
    }

    private var guidedLineSelectionRow: some View {
        Button { openRouteGuide() } label: {
            VStack(alignment: .leading, spacing: 4) {
                Label(localization.text("ios.routeGuide.manual"),
                      systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                if let choice = selectedRouteChoice {
                    Text(choice.lineNames.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if let error = routeChoiceLoadError {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                } else if !routeChoicesLoaded {
                    ProgressView()
                } else {
                    Text(localization.text("ios.routeGuide.selectRange"))
                        .font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .disabled(routePackage == nil || SolverRegistryInput.solvableEndpointCount(
            stops: draft.stops, region: Region.resolved(draft).code) < 2)
        .accessibilityIdentifier("rideEditorLines")
    }

    private var regionPicker: some View {
        Picker(localization.countryText("country.label", fallback: "Region"), selection: regionSelection) {
            ForEach(Region.enabledOrdered) { region in
                Text(localization.text(region.localizationKey, fallback: region.fallbackName)).tag(region)
            }
        }
        .accessibilityIdentifier("rideEditorRegion")
    }

    // MARK: - 2. Origin and destination

    private var stationsSection: some View {
        Section {
            EditorTextField(
                title: localization.countryText("field.origin", fallback: "Origin"),
                text: $draft.origin,
                focus: $focused,
                field: .origin
            )
            .id(RideDraftIssue.Field.origin)
            fieldIssues(.origin)

            EditorTextField(
                title: localization.countryText("field.destination", fallback: "Destination"),
                text: $draft.destination,
                focus: $focused,
                field: .destination
            )
            .id(RideDraftIssue.Field.destination)
            fieldIssues(.destination)
        } header: {
            Text(localization.text("ios.stations", fallback: "Stations"))
        } footer: {
            Text(localization.text("ios.editor.stationsNote"))
        }
    }

    // MARK: - 3. Stops

    private var stopsSection: some View {
        Section {
            if !generatedStopIDs.isEmpty {
                autoFilledStationsNote
            }
            ForEach(stopIDs, id: \.self) { stopID in
                if let index = stopIDs.firstIndex(of: stopID) {
                    HStack(spacing: 8) {
                        if stopEditMode.isEditing {
                            Button {
                                deleteStop(stopID)
                            } label: {
                                Label(localization.countryText("btn.delete", fallback: "Delete"),
                                      systemImage: "minus.circle.fill")
                                    .labelStyle(.iconOnly)
                                    .foregroundStyle(.red)
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("rideEditorDeleteStop-\(index)")
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            NavigationLink {
                                StopEditorView(
                                    stop: editableStop(stopID), journeyDate: $draft.date,
                                    index: index, region: Region.resolved(draft),
                                    selectedLineIDs: selectedCatalogLineIDs)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    StopEditorLabel(
                                        stop: draft.stops[index], journeyDate: draft.date, index: index + 1)
                                    if generatedStopIDs.contains(stopID) {
                                        AutoFilledStationLabel()
                                            .accessibilityIdentifier("rideEditorAutoFilledStop-\(index)")
                                    }
                                }
                            }
                            .accessibilityIdentifier("rideEditorStop-\(index)")
                            fieldIssues(.stop(index))
                        }
                    }
                    .id(stopID)
                    .transition(.asymmetric(
                        insertion: (reduceMotion ? AnyTransition.opacity
                            : .opacity.combined(with: .offset(y: 8)))
                            .animation(.easeOut(duration: 0.20)),
                        removal: AnyTransition.opacity.animation(.easeOut(duration: 0.16))))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        // Route stops may open a preview instead of being removed.
                        // A destructive role would optimistically animate deletion.
                        Button {
                            deleteStop(stopID)
                        } label: {
                            Label(localization.countryText("btn.delete", fallback: "Delete"),
                                  systemImage: "trash")
                        }
                        .tint(.red)
                        .accessibilityIdentifier("rideEditorSwipeDeleteStop-\(index)")
                    }
                }
            }
            .onMove(perform: moveStops)

            if let summary = routeEditSummary {
                HStack {
                    Text(summary).font(.footnote)
                    Spacer()
                    if routeEditUndo != nil {
                        Button(localization.text("ios.routeGuide.undo")) {
                            guard let restored = routeEditUndo?.restore(in: draft) else {
                                routeEditUndo = nil
                                routeEditSummary = localization.text("ios.routeGuide.undoUnavailable")
                                return
                            }
                            withAnimation(reduceMotion ? .easeOut(duration: 0.16)
                                : .timingCurve(0.77, 0, 0.175, 1, duration: 0.24)) {
                                draft = restored
                                synchronizeStopIdentity()
                                undoableDeletion = []
                                selectedRouteChoice = routeUndoChoice
                                routeUndoChoice = nil
                                selectedCatalogLineIDs = routeUndoCatalogLineIDs
                                routeEditUndo = nil
                                routeEditSummary = nil
                            }
                        }
                        .accessibilityIdentifier("rideEditorUndoRoute")
                    }
                }
                .frame(minHeight: 44)
            }
            if !undoableDeletion.isEmpty { undoBanner }

            if Region.resolved(draft).code == "jp" {
                Button {
                    if draft.stops.contains(where: { !$0.name.isEmpty }) {
                        showsReplaceStopsConfirmation = true
                    } else {
                        showsServicePatternPicker = true
                    }
                } label: {
                    Label(localization.text("ios.editor.selectExpressStops"),
                          systemImage: "train.side.front.car")
                }
                .accessibilityIdentifier("rideEditorServicePattern")
                Text(localization.text("ios.editor.expressStopsNote"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Button {
                undoableDeletion = []
                let id = UUID()
                let ridden = RideLedger.hasBeenRidden(draft)
                let index = draft.stops.count
                draft.stops.insert(
                    Stop(name: "", stopType: "passenger_stop", rideSegment: ridden), at: index)
                stopIDs.insert(id, at: index)
                stopEditMode = .inactive
                addedStopID = id
            } label: {
                Label(
                    localization.countryText("btn.addStop", fallback: "Add stop"),
                    systemImage: "plus")
            }
            .accessibilityIdentifier("rideEditorAddStop")
            fieldIssues(.stops)
        } header: {
            HStack {
                Text(localization.countryText("sec.stops", fallback: "Stops"))
                Spacer()
                Button(localization.text(stopEditMode.isEditing
                    ? "ios.editor.finishReordering" : "ios.editor.reorderStops")) {
                    stopEditMode = stopEditMode.isEditing ? .inactive : .active
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("rideEditorReorderStops")
                .frame(minHeight: 44)
            }
            .id(RideDraftIssue.Field.stops)
        } footer: {
            Text(localization.text("ios.editor.stopsNote"))
        }
    }

    /// §8.6: a short undo rather than a confirmation, because the draft has
    /// not been committed and putting the rows back is exact.
    private var undoBanner: some View {
        HStack {
            Text(
                localization.text(
                    "ios.editor.deletedStops", params: ["count": .number(Double(undoableDeletion.count))])
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            Spacer()
            Button(localization.text("ios.editor.undoDelete")) {
                for deletion in undoableDeletion.sorted(by: { $0.offset < $1.offset }) {
                    let at = min(deletion.offset, draft.stops.count)
                    draft.stops.insert(deletion.stop, at: at)
                    stopIDs.insert(deletion.id, at: at)
                }
                undoableDeletion = []
            }
            .accessibilityIdentifier("rideEditorUndoStops")
        }
        .frame(minHeight: 44)
    }

    /// Resolve the visit when invoked; moving a row must not change its target.
    private func deleteStop(_ stopID: UUID) {
        guard let index = stopIDs.firstIndex(of: stopID) else { return }
        deleteStops(at: IndexSet(integer: index))
    }

    private func deleteStops(at offsets: IndexSet) {
        let mandatoryCodes = Set(offsets.compactMap { index -> String? in
            guard index > 0, index < draft.stops.count - 1,
                  (generatedStopIDs.contains(stopIDs[index])
                   || selectedRouteChoice?.stations.contains(where: {
                      $0.code == draft.stops[index].n02StationCode
                   }) == true) else { return nil }
            return draft.stops[index].n02StationCode
        })
        if !mandatoryCodes.isEmpty {
            openRouteGuide(excluding: mandatoryCodes)
            return
        }
        undoableDeletion = offsets.sorted().map {
            Deletion(offset: $0, stop: draft.stops[$0], id: stopIDs[$0])
        }
        draft.stops.remove(atOffsets: offsets)
        stopIDs.remove(atOffsets: offsets)
    }

    private func moveStops(from offsets: IndexSet, to destination: Int) {
        resetRouteChoiceState()
        undoableDeletion = []
        draft.stops.move(fromOffsets: offsets, toOffset: destination)
        stopIDs.move(fromOffsets: offsets, toOffset: destination)
    }

    // MARK: - 4. Routing (advanced)

    private var routingSection: some View {
        Section {
            NavigationLink {
                RoutePolicyEditorView(policy: routePolicy)
                    .environment(localization)
            } label: {
                LabeledContent(
                    localization.text("ios.routePolicy", fallback: "Route policy"),
                    value: routePolicySummary)
            }
            .id(RideDraftIssue.Field.routePolicy)
            fieldIssues(.routePolicy)

            if issues.first(for: .routePolicy) != nil {
                Button(localization.text("ios.editor.policyReset")) {
                    draft.routePolicy = Self.canonicalPolicy
                }
                .frame(minHeight: 44)
            }

            ForEach(routeSectionIndices, id: \.self) { index in
                NavigationLink {
                    RouteSectionEditorView(
                        section: routeSection(at: index), region: Region.resolved(draft),
                        rideDate: draft.date)
                        .environment(localization)
                } label: {
                    RouteSectionLabel(
                        section: draft.routeSections?[index], index: index + 1,
                        train: draft,
                        localization: localization)
                }
                .contextMenu {
                    Button(role: .destructive) {
                        deleteRouteSections(at: IndexSet(integer: index))
                    } label: {
                        Label(
                            localization.countryText("btn.delete", fallback: "Delete"),
                            systemImage: "trash")
                    }
                }
            }
            .onDelete(perform: deleteRouteSections)
            .onMove(perform: moveRouteSections)

            // Below the list rather than inside it: a `ForEach` that carries
            // `onDelete` and `onMove` addresses its OWN elements, and a second
            // view per element makes a swipe ambiguous about which row it is
            // acting on. Each message names its section number, which is what
            // it would have said standing next to it.
            ForEach(routeSectionIndices, id: \.self) { index in
                fieldIssues(.routeSection(index))
                    .id(RideDraftIssue.Field.routeSection(index))
            }

            Button(action: addRouteSection) {
                Label(
                    localization.text("ios.addRouteSection", fallback: "Add route section"),
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            }
        } header: {
            Text(localization.text("ios.routing", fallback: "Routing"))
        } footer: {
            // §5.4: the rebuild happens after the stops are saved, and where
            // it happens is stated rather than left to be discovered.
            Text(localization.text("ios.editor.rebuildAfterSave"))
        }
    }

    // MARK: - 5. Style

    private var styleSection: some View {
        Section {
            HStack {
                EditorTextField(
                    title: localization.text("ios.editor.routeColor"),
                    text: styleColor,
                    prompt: "#RRGGBB",
                    focus: $focused,
                    field: .color
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                // The same square the journey's mark is drawn in, at the same
                // corner ratio — this field IS that mark's fallback colour, so
                // previewing it as a circle showed the editor one shape and
                // every list the other.
                RouteLogoSquare.shape(side: 22)
                    .fill(routeColor)
                    .frame(width: 22, height: 22)
                    .overlay(
                        RouteLogoSquare.shape(side: 22)
                            .strokeBorder(.separator, lineWidth: 0.5))
                    .accessibilityHidden(true)
            }
            .id(RideDraftIssue.Field.color)
            fieldIssues(.color)
        } header: {
            Text(localization.text("ios.style", fallback: "Style"))
        }
    }

    // MARK: - 6. Record details (advanced — §5.4, §8.2)

    private var recordSection: some View {
        Section {
            // Which region this ride is measured against: its solver, its
            // statistics, its station picker. Offered rather than derived
            // because a hand-written ride may carry no station codes at all,
            // and then nothing else in the record can say.
            regionPicker
            Text(localization.text("ios.editor.regionNote"))
                .font(.footnote)
                .foregroundStyle(.secondary)

            EditorTextField(
                title: localization.countryText("field.id", fallback: "Identifier"),
                text: $draft.id,
                focus: $focused,
                field: .id
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .id(RideDraftIssue.Field.id)
            fieldIssues(.id)
            fieldIssues(.record)
                .id(RideDraftIssue.Field.record)
        } header: {
            Text(localization.text("ios.editor.record"))
        } footer: {
            Text(localization.text("ios.editor.recordNote"))
        }
    }

    // MARK: - Inline messages

    /// Every message for one field, in the field's own row.
    @ViewBuilder
    private func fieldIssues(_ field: RideDraftIssue.Field) -> some View {
        ForEach(issues.all(for: field)) { issue in
            Label(message(issue), systemImage: symbol(issue))
                .font(.footnote)
                .foregroundStyle(issue.severity == .error ? Color.red : Color.orange)
                .fixedSize(horizontal: false, vertical: true)
                // §10.2: the message belongs to the control above it, not to a
                // separate thing the reader has to find.
                .accessibilityElement(children: .combine)
        }
    }

    private func symbol(_ issue: RideDraftIssue) -> String {
        issue.severity == .error ? "exclamationmark.circle.fill" : "exclamationmark.triangle"
    }

    private func message(_ issue: RideDraftIssue) -> String {
        if let literal = issue.literal { return literal }
        return localization.text(issue.key, params: issue.params)
    }

    // MARK: - Validation

    private var publishedIDs: Set<String> {
        existingIDs ?? itineraries?.trainIDs ?? []
    }

    private func revalidate() {
        issues = RideDraftValidation.issues(
            for: draft, originalID: original.id, existingIDs: publishedIDs)
        aiDenial = JourneyCompletion.requestEligibility(
            train: draft, catalogs: editorCatalogs, requestInFlight: false).denial
    }

    private var blocking: [RideDraftIssue] { issues.blocking }

    private var hasAdvancedIssues: Bool {
        blocking.contains {
            switch $0.field {
            case .id, .color, .routePolicy, .routeSection, .record: true
            default: false
            }
        }
    }

    // MARK: - Bindings

    private var visibleBinding: Binding<Bool> {
        Binding(get: { draft.visible != false }, set: { draft.visible = $0 })
    }

    /// Whether this journey was ridden — the switch the passport reads.
    ///
    /// Writing it sets `ride_segment` across every call of the journey, which
    /// is what `RideLedger.setRidden` means and why the per-stop switches in
    /// the stop list are still there for a journey only partly ridden.
    /// An existing record's ride state is never inferred from its date.
    private var riddenBinding: Binding<Bool> {
        Binding(
            get: { RideLedger.hasBeenRidden(draft) },
            set: { draft = RideLedger.setRidden(draft, $0) })
    }

    /// The region row.
    ///
    /// Reading falls back to what the stops say — an untagged ride shows the
    /// region it would be treated as, not a blank — and writing states it,
    /// because a reader who picked a region meant it even where the stops
    /// would have said something else.
    private var regionSelection: Binding<Region> {
        Binding(
            get: { Region.resolved(draft) },
            set: { region in
                guard region != Region.resolved(draft) else { return }
                undoableDeletion = []
                draft.region = region.code
            }
        )
    }

    private var styleColor: Binding<String> {
        Binding(
            get: { draft.style?.color ?? "" },
            set: { draft.style = TrainStyle(color: $0.isEmpty ? nil : $0) }
        )
    }

    private var routeColor: Color {
        Color(hex: draft.style?.color) ?? .accentColor
    }

    /// The policy every canonical writer produces. Also the repair offered
    /// when a decoded policy fails the schema: the four invariants below are
    /// constants, not choices, so resetting them cannot lose a decision the
    /// reader made.
    private static let canonicalPolicy = RoutePolicy(
        mode: "single_primary_route",
        jrOnly: false,
        allowAlternatives: false,
        allowBrowserStraightLineFallback: false,
        allowedInstitutionTypeCodes: TrainValidation.defaultAllowedInstitutionTypeCodes,
        institutionFilterMode: "soft")

    private var routePolicy: Binding<RoutePolicy> {
        Binding(
            get: { draft.routePolicy ?? Self.canonicalPolicy },
            set: { draft.routePolicy = $0 }
        )
    }

    private var routePolicySummary: String {
        switch draft.routePolicy?.institutionFilterMode {
        case "hard": localization.text("ios.editor.hardConstraint")
        case "soft": localization.text("ios.editor.softPreference")
        default: localization.text("ios.editor.automatic")
        }
    }

    private var routeSectionIndices: Range<Int> {
        (draft.routeSections ?? []).indices
    }

    private func routeSection(at index: Int) -> Binding<RouteSection> {
        Binding(
            get: { draft.routeSections?[index] ?? RouteSection() },
            set: { value in
                guard draft.routeSections?.indices.contains(index) == true else { return }
                draft.routeSections?[index] = value
            }
        )
    }

    private func addRouteSection() {
        var sections = draft.routeSections ?? []
        let previous = sections.last?.to ?? draft.stops.first?.name
        sections.append(
            RouteSection(
                from: previous,
                to: draft.stops.last?.name,
                fromN02StationCode: sections.last?.toN02StationCode
                    ?? draft.stops.first?.n02StationCode,
                toN02StationCode: draft.stops.last?.n02StationCode
            )
        )
        draft.routeSections = sections
    }

    private func deleteRouteSections(at offsets: IndexSet) {
        var sections = draft.routeSections ?? []
        sections.remove(atOffsets: offsets)
        draft.routeSections = sections
    }

    private func moveRouteSections(from offsets: IndexSet, to destination: Int) {
        var sections = draft.routeSections ?? []
        sections.move(fromOffsets: offsets, toOffset: destination)
        draft.routeSections = sections
    }

    private var showsAutoDirectionBadge: Bool {
        let current = draft.direction?.trimmingCharacters(in: .whitespacesAndNewlines)
        return current?.isEmpty == false && current == autoInferredDirection
    }

    private var localizedDirectionWord: String? {
        switch draft.direction?.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "up": localization.text("ios.direction.up")
        case "down": localization.text("ios.direction.down")
        default: nil
        }
    }

    private func directionBasis(_ train: Train) -> String {
        var parts: [String] = []
        for stop in train.stops {
            parts.append("\(stop.n02StationCode ?? "")\u{1F}\(stop.name)")
        }
        parts.append("#")
        for section in train.routeSections ?? [] {
            let lines = (section.lineIDs ?? []).joined(separator: ",")
            parts.append("\(section.fromN02StationCode ?? "")\u{1F}\(section.toN02StationCode ?? "")\u{1F}\(lines)")
        }
        return parts.joined(separator: "\u{1E}")
    }

    /// Writes an inferred word only when the field is empty or still the last
    /// inferred word. A timetable apply sets `holdOfficialDirection` first.
    /// A reader edit, including confirming the same word or clearing it, sticks.
    private func refreshAutoDirection(force: Bool = false) {
        guard !userDirectionEdited else { return }
        guard let package = routePackage else { return }
        let basis = directionBasis(draft)
        if !force, basis == directionBasisSeen { return }
        let current = draft.direction?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard current.isEmpty || current == autoInferredDirection else { return }
        directionBasisSeen = basis
        let inferred: String?
        do {
            inferred = try TravelDirection.infer(train: draft, package: package)?.direction.rawValue
        } catch {
            routeChoiceLoadError = error.localizedDescription
            return
        }
        autoInferredDirection = inferred
        if draft.direction != inferred {
            let updatesBaseline = draft == baseline
            draft.direction = inferred
            if updatesBaseline { baseline.direction = inferred }
        }
    }

    private func saveDraft() {
        if !userDirectionEdited {
            let current = draft.direction?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if current.isEmpty, let package = routePackage {
                do {
                    if let inferred = try TravelDirection.infer(train: draft, package: package) {
                        draft.direction = inferred.direction.rawValue
                        autoInferredDirection = inferred.direction.rawValue
                    }
                } catch {
                    routeChoiceLoadError = error.localizedDescription
                }
            }
        }
        onSave(draft)
    }

    /// Stored gap indexes apply only when the draft still visits the same
    /// stations, in order. A matching count is not the same ride.
    private var repairStopsMatchOriginal: Bool {
        draft.stops.count == original.stops.count
            && zip(draft.stops, original.stops).allSatisfy { stop, stored in
                stop.n02StationCode == stored.n02StationCode && stop.name == stored.name
            }
    }

    private func repairGapMarks() -> [RouteRepair.Gap]? {
        guard repairStopsMatchOriginal, let riddenRoutes,
              case .needsReview(_, _, let gaps) = riddenRoutes.status(
                forTrainID: original.id,
                pendingConfirmationIDs: itineraries?.pendingConfirmationIDs ?? [])
        else { return nil }
        return gaps.map {
            RouteRepair.Gap(segmentIndex: $0.segmentIndex, isBoundary: $0.isBoundary,
                            station: $0.isBoundary ? $0.from : nil)
        }
    }

    private var repairSpanCount: Int {
        guard let marks = repairGapMarks() else { return 0 }
        return RouteRepair.failingSpans(train: draft, gaps: marks).count
    }

    private func repairRoute() {
        guard !isRepairingRoute, let package = routePackage, repairStopsMatchOriginal,
              let marks = repairGapMarks(), !marks.isEmpty else { return }
        let snapshot = draft
        let prepared = routeEditingDraft
        let stepped = RouteRepairFlow.steps(RouteRepair.failingSpans(train: prepared, gaps: marks), in: prepared)
        isRepairingRoute = true
        Task {
            let result: RouteRepairSession.Result
            do {
                result = try await RouteRepairSession.search(
                    train: stepped.train, baseline: snapshot, package: package, steps: stepped.steps,
                    loadAliases: { try loadJourneyStationAliases(for: $0, package: $1) })
            } catch {
                isRepairingRoute = false
                guard !Task.isCancelled, draft == snapshot else { return }
                routeRepairSummary = error.localizedDescription
                return
            }
            isRepairingRoute = false
            guard result.accepts(draft) else { return }
            let advance = result.advance
            if advance.train != prepared {
                acceptedRouteStopCodes = advance.train.stops.map(\.n02StationCode)
                draft = advance.train
                synchronizeStopIdentity()
                undoableDeletion = []
            }
            presentRepair(result, snapshot: snapshot, package: package)
        }
    }

    private func continueRepair(applied extra: Int, _ continuation: RepairContinuation) {
        guard !isRepairingRoute, let package = routePackage else { return }
        let snapshot = draft
        let prepared = routeEditingDraft
        let steps = continuation.remaining
        let repairedBase = continuation.repaired + extra
        let priorGaps = continuation.gaps
        let repairSnapshot = continuation.snapshot
        isRepairingRoute = true
        Task {
            let result: RouteRepairSession.Result
            do {
                result = try await RouteRepairSession.search(
                    train: prepared, baseline: snapshot, package: package, steps: steps,
                    repaired: repairedBase, gaps: priorGaps,
                    loadAliases: { try loadJourneyStationAliases(for: $0, package: $1) })
            } catch {
                isRepairingRoute = false
                guard !Task.isCancelled, draft == snapshot else { return }
                routeRepairSummary = error.localizedDescription
                return
            }
            isRepairingRoute = false
            guard result.accepts(draft) else { return }
            let advance = result.advance
            if advance.train != prepared {
                acceptedRouteStopCodes = advance.train.stops.map(\.n02StationCode)
                draft = advance.train
                synchronizeStopIdentity()
                undoableDeletion = []
            }
            presentRepair(result, snapshot: repairSnapshot, package: package)
        }
    }

    private func presentRepair(
        _ result: RouteRepairSession.Result, snapshot: Train, package: CompactPackage
    ) {
        let advance = result.advance
        routeRepairSnapshot = snapshot
        routeRepairSummary = result.summary { key, params in
            localization.text(key, params: params)
        }
        guard let pause = advance.pause, !pause.choices.isEmpty else { return }
        routeGuideRequest = RouteGuideRequest(
            train: advance.train, package: package, inferredChoices: pause.choices,
            focus: (pause.fromVisitID, pause.toVisitID),
            repairContinuation: RepairContinuation(
                remaining: pause.remaining, repaired: advance.repaired, gaps: advance.gaps, snapshot: snapshot))
    }

    private func optionalText(_ keyPath: WritableKeyPath<Train, String?>) -> Binding<String> {
        EditorBindings.optionalText($draft, keyPath)
    }

    /// Company text is typed. The registry ids are not.
    private var companyText: Binding<String> {
        Binding(
            get: { draft.company ?? "" },
            set: { value in
                RegistryIdentityUpgrade.reassignCompany(value.isEmpty ? nil : value, on: &draft)
            }
        )
    }

    /// Any write counts, including the same word again or a clear.
    private var directionText: Binding<String> {
        Binding(
            get: { draft.direction ?? "" },
            set: { value in
                userDirectionEdited = true
                draft.direction = value.isEmpty ? nil : value
            }
        )
    }
}

