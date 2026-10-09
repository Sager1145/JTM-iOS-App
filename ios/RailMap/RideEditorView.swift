import RailCore
import RailPresentation
import SwiftUI

/// A local draft is committed once; cancelling never changes the saved journey.
/// New journeys put the route first and disclose optional settings on demand.
struct RideEditorView: View {
    @Environment(AppLocalization.self) private var localization
    @Environment(RailNetworkStore.self) private var network
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
    /// Preserve persisted visit identity across route changes and reopening.
    @State private var stopIDs: [UUID]
    private enum WizardStep: Int, CaseIterable {
        case region, route, service, date, confirm
        var key: String { "ios.editor.step.\(self)" }
    }
    @State private var step: WizardStep = .region
    @State private var pendingRegion: Region?
    @State private var showsDiscardConfirmation = false
    @State private var showsOptionalDetails = false
    @State private var showsValidation = false
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
    /// Whether the reader has moved the ride switch themselves. Once true the
    /// date pre-fill is finished for this session — see ``prefillRidden(forDate:)``.
    @State private var riddenIsTheReaders = false
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
    /// New journeys use a compact form and derive endpoints from their stops.
    let isNew: Bool
    let onSave: (Train) -> Void
    let onCancel: () -> Void
    var onDraftMap: (DraftMapSnapshot) -> Void = { _ in }
    var highlightedStopID: Binding<UUID?> = .constant(nil)
    let suggestionTrains: [Train]
    /// Ids already in the store, so an id collision is visible while it is
    /// being typed rather than after the save quietly keeps the old one.
    /// Defaults to whatever the workspace has published (see
    /// ``RideStatusCenter``).
    var existingIDs: Set<String>?

    private struct Deletion: Equatable {
        var offset: Int
        var stop: Stop
        var id: UUID
    }

    init(
        train: Train,
        title: String = "Edit journey",
        isNew: Bool = false,
        existingIDs: Set<String>? = nil,
        suggestionTrains: [Train] = [],
        onCancel: @escaping () -> Void,
        onDraftMap: @escaping (DraftMapSnapshot) -> Void = { _ in },
        highlightedStopID: Binding<UUID?> = .constant(nil),
        onSave: @escaping (Train) -> Void
    ) {
        original = train
        self.title = title
        self.isNew = isNew
        self.existingIDs = existingIDs
        self.suggestionTrains = suggestionTrains
        var initialDraft = train
        if isNew && (initialDraft.trainType?.isEmpty != false) { initialDraft.trainType = "local" }
        _draft = State(initialValue: initialDraft)
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
            localization.editorText("ios.editor.replaceExistingStopsTitle"),
            isPresented: $showsReplaceStopsConfirmation, titleVisibility: .visible
        ) {
            Button(localization.editorText("ios.editor.replaceExistingStops"), role: .destructive) {
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
        .interactiveDismissDisabled(draft != original)
    }

    private var editorNavigation: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                editorLoadingEvents(proxy)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(localization.text("ios.cancel", fallback: "Cancel")) {
                            if draft == original {
                                onCancel()
                            } else {
                                showsDiscardConfirmation = true
                            }
                        }
                        .accessibilityIdentifier("rideEditorCancel")
                    }
                    if !isNew {
                    ToolbarItem(placement: .confirmationAction) {
                        // §5.4 uses the specific verb: 保存旅程, not 完成.
                        Button(localization.editorText("ios.editor.saveJourney")) {
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
            }
            // §5.4: leaving a dirty draft asks; a clean one just closes.
            .confirmationDialog(
                localization.editorText("ios.editor.discardTitle"),
                isPresented: $showsDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button(
                    localization.editorText("ios.editor.discardChanges"),
                    role: .destructive
                ) { onCancel() }
                Button(localization.editorText("ios.editor.keepEditing"), role: .cancel) {}
            } message: {
                Text(localization.editorText("ios.editor.discardDetail"))
            }
        }
    }

    private func editorForm(_ proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 0) {
        Form {
            if isNew {
                wizardHeader
                switch step {
                case .region:
                    Section { regionPicker; trainTypePicker }
                case .route:
                    routeSelectionSection
                    stopsSection
                case .service:
                    Section { numberFields }
                    localLineServicesSection
                    searchableDetailsSection
                    serviceSectionsSection
                    Section {
                        DisclosureGroup(localization.editorText("ios.editor.optionalDetails"),
                                        isExpanded: $showsOptionalDetails) { serviceDetails }
                    }
                case .date:
                    Section {
                        dateFields
                        if Region.resolved(draft) == .jp { timetableBrowseButton }
                    }
                    journeyStatusSection
                    journeyGroupSection
                    localLineServicesSection
                    if Region.resolved(draft) == .jp {
                        TimetableQuickMatchView(
                            train: JourneyCompletion.resolvingUniqueStationNames(
                                in: draft, catalogs: editorCatalogs),
                            serviceName: limitedExpressName) { trip in
                            pendingTimetableTrip = trip
                            showsReplaceStopsConfirmation = true
                        }
                        routeSelectionSection
                    }
                case .confirm:
                    confirmationSections
                }
                if step != .region { completionSection }
                if (showsValidation || step == .confirm) && !presentedBlocking.isEmpty { problemSummary(proxy) }
            } else {
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
        }
        .accessibilityIdentifier("rideEditorForm")
        // Inline, and short. §14.5 forbids a fixed English-width
        // assumption, and the large title fought both toolbar buttons
        // for the same row and lost — 「乗車記録を編集」 came back as
        // 「乗車記録…」, a heading truncated to a stub. The specific
        // verb the spec asks for is on the SAVE button, which is where
        // it does work; this row only has to say which surface this is.
            if isNew { wizardNavigation(proxy) }
        }
    }

    private func editorDraftEvents(_ proxy: ScrollViewProxy) -> some View {
        editorForm(proxy)
        .onChange(of: step) { _, _ in
            focused = nil
            stopEditMode = .inactive
            showsValidation = false
            proxy.scrollTo("wizardTop", anchor: .top)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .task(id: Region.resolved(draft)) { network.ensure(Region.resolved(draft)) }
        .navigationDestination(item: $addedStopID) { stopID in
            if let index = stopIDs.firstIndex(of: stopID) {
                StopEditorView(stop: editableStop(stopID), journeyDate: $draft.date,
                               index: index, isNew: isNew,
                               region: Region.resolved(draft), allowsEndpointRoles: !isNew,
                               selectedLineIDs: isNew && (index == 0 || index == draft.stops.count - 1)
                                ? [] : selectedCatalogLineIDs,
                               onRiddenChange: { riddenIsTheReaders = true })
            }
        }
        .onChange(of: draft.stops) { _, stops in
            guard isNew else { return }
            draft.origin = stops.first?.name ?? ""
            draft.destination = stops.last?.name ?? ""
            normalizeEndpointRoles()
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
                guard TrainTimetableDatabase.accepts(train),
                      let database = TrainTimetableDatabase.bundled(country: train.region ?? "jp") else { return String?.none }
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
        // Keyed on the date alone, so that editing any other field —
        // including the ride switch itself — cannot re-run it.
        .onChange(of: draft.date, initial: true) { _, date in
            prefillRidden(forDate: date)
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
        .alert(localization.editorText("ios.routeGuide.routeUnavailable"), isPresented: $routeGuideError) {
            Button(localization.text("ios.done"), role: .cancel) {}
        }
        .confirmationDialog(
            localization.editorText("ios.routeGuide.removalTitle"),
            isPresented: Binding(get: { pendingRouteCommit != nil }, set: {
                if !$0 { pendingRouteCommit = nil }
            }), titleVisibility: .visible, presenting: pendingRouteCommit
        ) { commit in
            Button(localization.editorText("ios.routeGuide.removeAndApply"), role: .destructive) {
                commitRoutePlan(commit.plan, choice: commit.choice, continuation: commit.continuation)
            }
            Button(localization.editorText("ios.editor.keepEditing"), role: .cancel) {
                pendingRouteCommit = nil
            }
        } message: { commit in
            Text(localization.editorText("ios.routeGuide.removalDetail", [
                "stations": .string(commit.plan.conflictingStops.map(\.name).joined(separator: " · "))
            ]))
        }
    }

    private var editorRoutePresentations: some View {
        editorNavigation
        .confirmationDialog(localization.editorText("ios.editor.changeRegion"),
            isPresented: Binding(get: { pendingRegion != nil }, set: { if !$0 { pendingRegion = nil } }),
            titleVisibility: .visible, presenting: pendingRegion) { region in
                Button(localization.editorText("ios.editor.resetRoute"), role: .destructive) {
                    let ridden = RideLedger.hasBeenRidden(draft)
                    draft.region = region.code
                    draft.stops = [Stop(name: "", stopType: "origin", rideSegment: ridden),
                                   Stop(name: "", stopType: "destination", rideSegment: ridden)]
                    stopIDs = draft.stops.map { _ in UUID() }
                    draft.origin = ""
                    draft.destination = ""
                    draft.routePolicy = nil
                    draft.routeSections = nil
                    limitedExpressName = ""
                    selectedPattern = nil
                    selectedTimetableDate = nil
                    resetRouteChoiceState()
                    undoableDeletion = []
                    pendingRegion = nil
                    prefillRidden(forDate: draft.date)
                }
                Button(localization.editorText("ios.editor.keepEditing"), role: .cancel) { pendingRegion = nil }
            } message: { _ in Text(localization.editorText("ios.editor.changeRegionNote")) }
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

    private var timetableBrowseButton: some View {
        Button {
            if draft.stops.contains(where: { !$0.name.isEmpty }) {
                showsReplaceStopsConfirmation = true
            } else {
                showsServicePatternPicker = true
            }
        } label: {
            Label(localization.editorText("ios.editor.timetableBrowse"), systemImage: "magnifyingglass")
        }
        .accessibilityIdentifier("rideEditorTimetableBrowse")
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
        guard let applied = trip.canApplyToRouteEditor
            ? trip.applying(to: draft, ridden: ridden)
            : trip.publishedStopsDraft(to: draft, ridden: ridden)
        else { return }
        resetRouteChoiceState()
        holdOfficialDirection = true
        draft = applied
        selectedTimetableDate = trip.serviceDate
        limitedExpressName = trip.service.canonicalName
        selectedPattern = trip.canApplyToRouteEditor ? trip.compatibilityPattern() : nil
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
        guard let wanted = ProcessInfo.processInfo
            .environment["RAILMAP_UI_TEST_EDITOR_SECTION"] else { return }
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
        return localization.editorText(key)
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
                    ? localization.editorText(key)
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
            let package = try EditorRoutePackageCache.load(region: region)
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
        isInferringRoute = true
        routeInferenceTask = Task {
            let worker = Task.detached(priority: .userInitiated) {
                let aliases = loadJourneyStationAliases(for: prepared.stops.compactMap(\.n02StationCode), package: package)
                return RailwayRouteInference.search(in: prepared, package: package, stationAliases: aliases, maximumExpansions: 200_000)
            }
            let result = await withTaskCancellationHandler {
                await worker.value
            } onCancel: { worker.cancel() }
            guard !Task.isCancelled else { return }
            isInferringRoute = false
            guard draft == snapshot else { return }
            if let choice = result.uniqueChoice,
               let plan = RailwayRouteEditing.plan(train: prepared, choice: choice),
               !plan.requiresConfirmation {
                applyRoutePlan(plan, choice: choice)
                return
            }
            guard !result.choices.isEmpty else { routeInferenceFailed = true; return }
            pendingRouteCommit = nil
            routeGuideRequest = RouteGuideRequest(train: prepared, package: package, inferredChoices: result.choices)
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
            completed.company = proposal.choice.operatorNames.joined(separator: " / ")
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
            routeEditSummary = localization.editorText("ios.routeGuide.updated", [
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
            if updated != draft.stops[index] {
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

    private var wizardHeader: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(localization.editorText("ios.editor.stepCount", [
                    "current": .number(Double(step.rawValue + 1)), "total": .number(5)]))
                    .font(.caption).foregroundStyle(.secondary)
                Text(localization.editorText(step.key)).font(.title2.bold())
                if !dynamicTypeSize.isAccessibilitySize {
                    Text(localization.editorText(step.key + "Note"))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ProgressView(value: Double(step.rawValue + 1), total: 5)
                    .accessibilityLabel(localization.editorText(step.key))
            }
            .padding(.vertical, 4)
        }
        .id("wizardTop")
        .accessibilityIdentifier("rideEditorStep")
    }

    private func wizardNavigation(_ proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 16) {
            if step != .region {
                Button {
                    step = WizardStep(rawValue: step.rawValue - 1) ?? .region
                } label: {
                    if dynamicTypeSize.isAccessibilitySize {
                        Image(systemName: "chevron.backward").frame(minWidth: 24, minHeight: 24)
                    } else {
                        Text(localization.editorText("ios.editor.previous"))
                            .lineLimit(2)
                    }
                }
                .accessibilityLabel(localization.editorText("ios.editor.previous"))
                .buttonStyle(.bordered)
                .accessibilityIdentifier("rideEditorPrevious")
            }
            if step != .confirm {
                Button {
                    revalidate()
                    guard presentedBlocking.isEmpty else {
                        showsValidation = true
                        focused = nil
                        if let issue = presentedBlocking.first {
                            proxy.scrollTo(scrollTarget(for: issue.field), anchor: .top)
                        }
                        return
                    }
                    step = WizardStep(rawValue: step.rawValue + 1) ?? .confirm
                } label: {
                    Text(localization.editorText("ios.editor.next"))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("rideEditorNext")
                .disabled(draft.journeyGroup?.name.isEmpty == true)
            } else {
                Button {
                    guard blocking.isEmpty, draft.journeyGroup?.name.isEmpty != true else { return }
                    saveDraft()
                } label: {
                    Text(dynamicTypeSize.isAccessibilitySize
                        ? localization.text("ios.save", fallback: "Save")
                        : localization.editorText("ios.editor.saveJourney"))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                }
                .accessibilityLabel(localization.editorText("ios.editor.saveJourney"))
                .buttonStyle(.borderedProminent)
                .disabled(!blocking.isEmpty || draft.journeyGroup?.name.isEmpty == true)
                .accessibilityIdentifier("rideEditorSave")
                .keyboardShortcut("s", modifiers: .command)
            }
        }
        .controlSize(.large)
        .padding(.horizontal).padding(.vertical, 10)
        .background(.bar)
    }

    @ViewBuilder private var confirmationSections: some View {
        if selectedTimetableDate != nil && selectedTimetableDate != draft.date {
            Section { timetableDateNotice }
        }
        Section(localization.editorText("ios.editor.step.route")) {
            LabeledContent(localization.countryText("country.label", fallback: "Region"),
                value: localization.text(Region.resolved(draft).localizationKey,
                                         fallback: Region.resolved(draft).fallbackName))
            ForEach(stopIDs, id: \.self) { stopID in
                if let index = stopIDs.firstIndex(of: stopID) {
                    LabeledContent("\(index + 1)") {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(draft.stops[index].name)
                            if generatedStopIDs.contains(stopID) {
                                AutoFilledStationLabel()
                            }
                        }
                    }
                }
            }
            if !generatedStopIDs.isEmpty {
                autoFilledStationsNote
            }
            if let names = draft.routePolicy?.preferredLineNames, !names.isEmpty {
                LabeledContent(localization.editorText("ios.editor.searchLines"), value: names.joined(separator: " · "))
            }
        }
        Section(localization.editorText("ios.editor.step.service")) {
            if let group = draft.journeyGroup {
                LabeledContent(localization.groupText("title"), value: group.name)
            }
            LabeledContent(localization.countryText("field.number", fallback: "Train number"), value: draft.number)
            if let value = draft.trainType, !value.isEmpty {
                LabeledContent(localization.countryText("field.trainType", fallback: "Train type"), value: value)
            }
            if let value = draft.vehicleType, !value.isEmpty {
                LabeledContent(localization.editorText("ios.editor.vehicleType"), value: value)
            }
            if let value = draft.company, !value.isEmpty {
                LabeledContent(localization.countryText("field.company", fallback: "Operator"), value: value)
            }
            if let value = draft.numberEn, !value.isEmpty {
                LabeledContent(localization.countryText("field.numberEn", fallback: "English name"), value: value)
            }
            if let value = draft.direction, !value.isEmpty {
                LabeledContent(localization.countryText("field.direction", fallback: "Direction"), value: value)
            }
            if let value = draft.notes, !value.isEmpty {
                LabeledContent(localization.editorText("ios.ai.notes"), value: value)
            }
        }
        if !JourneyServiceSections.legs(of: draft).isEmpty {
            Section(localization.editorText("ios.editor.sectionServices")) {
                ForEach(JourneyServiceSections.legs(of: draft)) { leg in
                    ServiceSectionSummary(leg: leg, train: draft)
                }
            }
        }
        Section(localization.editorText("ios.editor.step.date")) {
            LabeledContent(localization.editorText("ios.editor.date"),
                value: draft.date ?? localization.editorText("ios.editor.noDate"))
            LabeledContent(localization.editorText("ios.detail.riddenState"),
                value: localization.editorText(RideLedger.confirmation(of: draft) == .partly
                    ? "ios.editor.partly" : RideLedger.hasBeenRidden(draft) ? "ios.editor.yes" : "ios.editor.no"))
            LabeledContent(localization.text("ios.showOnMap", fallback: "Show on map"),
                value: localization.editorText(draft.visible != false ? "ios.editor.yes" : "ios.editor.no"))
        }
    }

    private var autoFilledStationsNote: some View {
        Label(localization.editorText("ios.editor.generatedStationsNote"), systemImage: "info.circle")
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
            if isNew && step != .confirm && !showsValidation {
                Text(localization.editorText("ios.editor.requiredGuide"))
                    .foregroundStyle(.secondary)
            }
            ForEach(isNew && step != .confirm && !showsValidation ? [] : presentedBlocking) { issue in
                Label(message(issue), systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(localization.editorText(isNew && step != .confirm && !showsValidation
                ? "ios.editor.reviewRequired" : "ios.editor.showErrors")) {
                showsValidation = true
                focusFirstProblem(proxy)
            }
            .frame(minHeight: 44)
        } header: {
            Text(localization.editorText(isNew && step != .confirm && !showsValidation
                ? "ios.editor.beforeSaving" : "ios.editor.cannotSaveYet"))
        } footer: {
            if !isNew || showsValidation {
                Text(localization.editorText("ios.editor.blockedCount",
                    ["count": .number(Double(presentedBlocking.count))]))
            }
        }
    }

    /// §5.4: "第一个错误字段应可被『查看错误』动作聚焦."
    private func focusFirstProblem(_ proxy: ScrollViewProxy) {
        guard let issue = presentedBlocking.first else { return }
        if isNew && step == .confirm {
            switch issue.field {
            case .date: step = .date
            case .number: step = .service
            default: step = .route
            }
            return
        }
        if isNew, case .stop(let index) = issue.field, stopIDs.indices.contains(index) {
            addedStopID = stopIDs[index]
            return
        }
        let target = scrollTarget(for: issue.field)
        if reduceMotion {
            proxy.scrollTo(target, anchor: .center)
        } else {
            withAnimation(RailMotion.spring) {
                proxy.scrollTo(target, anchor: .center)
            }
        }
        if issue.field.isTextField && !(isNew && (issue.field == .origin || issue.field == .destination)) {
            focused = issue.field
        }
    }

    /// Validation identifies stop problems by their current ordinal; scrolling
    /// identifies the mutable row by its stable editor-session id.
    private func scrollTarget(for field: RideDraftIssue.Field) -> AnyHashable {
        if isNew, field == .origin || field == .destination {
            return AnyHashable(RideDraftIssue.Field.stops)
        }
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

            if !isNew { serviceDetails }

        } header: {
            Text(localization.editorText("ios.editor.basics"))
        }
    }

    @ViewBuilder private var dateFields: some View {
            if isNew {
                Toggle(localization.editorText("ios.editor.includeDate"), isOn: Binding(
                    get: { draft.date != nil },
                    set: { draft.date = $0 ? RecordDate.today(in: Region.resolved(draft).clock) : nil }
                ))
                if draft.date != nil {
                    EditorDateField(
                        title: localization.editorText("ios.editor.date"),
                        // Clearing text keeps the explicitly enabled date
                        // visible and invalid until it is repaired or disabled.
                        date: Binding(
                            get: { draft.date },
                            set: { draft.date = $0 ?? "" }),
                        region: Region.resolved(draft),
                        focus: $focused,
                        field: .date,
                        accessibilityID: "rideEditorDateInput")
                        .id(RideDraftIssue.Field.date)
                    fieldIssues(.date)
                }
            } else {
                EditorDateField(
                    title: localization.editorText("ios.editor.date"),
                    date: $draft.date,
                    region: Region.resolved(draft),
                    focus: $focused,
                    field: .date,
                    accessibilityID: "rideEditorDateInput")
                    .id(RideDraftIssue.Field.date)
            }
            if !isNew { fieldIssues(.date) }
            timetableDateNotice
            if let pattern = selectedPattern,
               let date = draft.date,
               let applicability = pattern.applicability(on: date),
               applicability != .applicable {
                Label(
                    applicability == .notApplicable
                        ? "選択した列車パターンはこの乗車日の対象外です。停車駅はそのまま保持されます。"
                        : "選択した列車パターンの有効期間は確認できません。停車駅はそのまま保持されます。",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
                .accessibilityIdentifier("rideEditorPatternDateNotice")
            }

    }

    @ViewBuilder private var timetableDateNotice: some View {
        if let selectedTimetableDate, selectedTimetableDate != draft.date {
            Label(localization.editorText("ios.editor.timetableDateChanged", ["date": .string(selectedTimetableDate)]),
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
            if !isNew || step == .confirm { fieldIssues(.number) }
            englishNameFields
    }

    private var journeyStatusSection: some View {
        Section {
            Toggle(
                localization.editorText("ios.detail.riddenState"), isOn: riddenBinding)
            if RideLedger.confirmation(of: draft) == .partly {
                // The whole-journey switch reads "on" over a record that is
                // only partly ridden, which is true — it IS being counted —
                // and would be misleading unread. Say how much, and where the
                // rest of it is decided.
                Text(
                    localization.editorText(
                        "ios.editor.riddenPartlyNote",
                        ["n": .number(Double(RideLedger.riddenSegmentCount(draft.stops)))])
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Toggle(localization.text("ios.showOnMap", fallback: "Show on map"), isOn: visibleBinding)
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(localization.editorText("ios.editor.riddenNote"))
                Text(localization.editorText("ios.editor.visibilityNote"))
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
                Text(localization.editorText("ios.editor.useOfficialEnglishName"))
                if let name = officialEnglishName.value {
                    Text(verbatim: name).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .disabled(officialEnglishName.value == nil)
        .accessibilityIdentifier("rideEditorUseOfficialEnglishName")
        if case .unavailable = officialEnglishName {
            Text(localization.editorText("ios.editor.officialEnglishNameUnavailable"))
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
                Text("\(word) · \(localization.editorText("ios.direction.auto"))")
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
        ["local", "rapid", "express", "limitedExpress", "highSpeed"]
            .map { localization.editorText("ios.editor.serviceType.\($0)") }
    }

    private var regionalLines: [RailNetworkStore.DrawnLine] {
        network.lines.filter { $0.region == Region.resolved(draft) }
    }

    private var searchableDetailsSection: some View {
        Section {
            if isNew {
                EditorSearchField(
                    title: localization.editorText("ios.editor.limitedExpressName"),
                    text: $limitedExpressName,
                    suggestions: TrainServiceBranding.services
                        .filter { $0.region == Region.resolved(draft).code }
                        .flatMap(\.names))
                    .accessibilityIdentifier("rideEditorLimitedExpressName")
            }
            if !isNew {
                EditorSearchField(
                    title: localization.countryText("field.trainType", fallback: "Train type"),
                    text: optionalText(\.trainType),
                    suggestions: regionalHistory.compactMap(\.trainType) + defaultServiceTypes)
                    .accessibilityIdentifier("rideEditorTrainType")
            }
            EditorSearchField(
                title: localization.editorText("ios.editor.vehicleType"),
                text: optionalText(\.vehicleType),
                suggestions: regionalHistory.compactMap(\.vehicleType))
                .accessibilityIdentifier("rideEditorVehicleType")
            if !isNew { preferredLineSelectionRow }
            EditorSearchField(
                title: localization.countryText("field.company", fallback: "Operator"),
                text: optionalText(\.company),
                suggestions: regionalHistory.compactMap(\.company) + regionalLines.compactMap(\.operatorName))
        } header: {
            Text(localization.editorText(isNew ? "ios.editor.step.service" : "ios.editor.serviceDetails"))
        } footer: {
            Text(localization.editorText(isNew ? "ios.editor.vehicleSearchNote" : "ios.editor.searchDetailsNote"))
        }
    }

    private var journeyGroupSection: some View {
        Section {
            JourneyGroupChoiceFields(
                selection: $draft.journeyGroup,
                groups: JourneyGroupCatalog.groups(in: suggestionTrains))
        } footer: {
            Text(localization.groupText("crossRegion"))
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
                Label(localization.editorText("ios.editor.addSectionService"), systemImage: "plus.circle")
            }
            .disabled(draft.stops.count < 2)
            .accessibilityIdentifier("rideEditorAddServiceLeg")
            TextField(localization.editorText("ios.ai.notes"), text: optionalText(\.notes), axis: .vertical)
                .lineLimit(2...5)
                .accessibilityIdentifier("rideEditorNotes")
        } header: {
            Text(localization.editorText("ios.editor.sectionServices"))
        } footer: {
            Text(localization.editorText("ios.editor.sectionServicesNote"))
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
                Button(localization.editorText("ios.routeGuide.undo")) {
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
                    Label(localization.editorText("ios.routeGuide.infer"), systemImage: "wand.and.stars")
                    if isInferringRoute { Spacer(); ProgressView() }
                }
            }
            .disabled(isInferringRoute || routePackage == nil || draft.stops.count < 2
                || draft.stops.contains { $0.n02StationCode == nil })
            .accessibilityIdentifier("rideEditorInferRoute")
            if repairSpanCount > 0 {
                Text(localization.editorText("ios.route.sectionsNeedRepair", [
                    "n": .number(Double(repairSpanCount)),
                ]))
                .font(.footnote)
                .foregroundStyle(.secondary)
                Button {
                    repairRoute()
                } label: {
                    HStack {
                        Label(localization.editorText("ios.route.repairRoute"), systemImage: "wrench.and.screwdriver")
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
                Button(localization.editorText("ios.routeGuide.undo")) {
                    draft = snapshot
                    synchronizeStopIdentity()
                    routeRepairSnapshot = nil
                    routeRepairSummary = nil
                }
                .accessibilityIdentifier("rideEditorRepairUndo")
            }
            guidedLineSelectionRow
            Button(localization.editorText("ios.routeGuide.keepPending"), action: markRoutePending)
                .accessibilityIdentifier("rideEditorPendingRoute")
            if draft.requiresRouteConfirmation {
                Label(localization.editorText("ios.routeGuide.pending"), systemImage: "questionmark.circle")
                Text(localization.editorText("ios.routeGuide.pendingNote"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if routeInferenceFailed {
                Text(localization.editorText("ios.routeGuide.inferenceFailed"))
                    .font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("rideEditorInferenceFailed")
            }
        } footer: {
            Text(localization.editorText("ios.routeGuide.inferenceNote"))
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
                stationCodes: draft.stops.compactMap(\.n02StationCode),
                onCommit: { lineIDs, lineNames, operatorNames in
                    selectedCatalogLineIDs = Set(lineIDs)
                    var policy = routePolicy.wrappedValue
                    policy.preferredLineNames = lineNames.isEmpty ? nil : lineNames
                    policy.preferredOperatorNames = operatorNames.isEmpty ? nil : operatorNames
                    draft.routePolicy = policy
                })
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Label(localization.editorText("ios.editor.searchLines"), systemImage: "magnifyingglass")
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

    private var trainTypePicker: some View {
        Picker(localization.countryText("field.trainType", fallback: "Train type"),
               selection: Binding(get: { draft.trainType ?? "local" }, set: { draft.trainType = $0 })) {
            ForEach(["local", "rapid", "express", "limitedExpress", "highSpeed"], id: \.self) { type in
                Text(localization.editorText("ios.editor.serviceType.\(type)")).tag(type)
            }
            if let type = draft.trainType,
               !["local", "rapid", "express", "limitedExpress", "highSpeed"].contains(type) {
                Text(type).tag(type)
            }
        }
        .accessibilityIdentifier("rideEditorTrainType")
    }

    private var guidedLineSelectionRow: some View {
        Button { openRouteGuide() } label: {
            VStack(alignment: .leading, spacing: 4) {
                Label(localization.editorText("ios.routeGuide.manual"),
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
                    Text(localization.editorText("ios.routeGuide.selectRange"))
                        .font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .disabled(routePackage == nil || draft.stops.compactMap(\.n02StationCode).count < 2)
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
            Text(localization.editorText("ios.editor.stationsNote"))
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
                                    index: index, isNew: isNew,
                                    region: Region.resolved(draft), allowsEndpointRoles: !isNew,
                                    selectedLineIDs: isNew && (index == 0 || index == draft.stops.count - 1)
                                            ? [] : selectedCatalogLineIDs,
                                           onRiddenChange: { riddenIsTheReaders = true })
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    StopEditorLabel(
                                        stop: draft.stops[index], journeyDate: draft.date, index: index + 1,
                                        emptyTitle: isNew ? localization.editorText(index == 0
                                            ? "ios.editor.chooseOrigin" : index == stopIDs.count - 1
                                            ? "ios.editor.chooseDestination" : "ios.editor.untitledStop") : nil)
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
                        Button(localization.editorText("ios.routeGuide.undo")) {
                            guard let restored = routeEditUndo?.restore(in: draft) else {
                                routeEditUndo = nil
                                routeEditSummary = localization.editorText("ios.routeGuide.undoUnavailable")
                                return
                            }
                            withAnimation(reduceMotion ? .easeOut(duration: 0.16)
                                : .timingCurve(0.77, 0, 0.175, 1, duration: 0.24)) {
                                draft = restored
                                synchronizeStopIdentity()
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
                    Label(localization.editorText("ios.editor.selectExpressStops"),
                          systemImage: "train.side.front.car")
                }
                .accessibilityIdentifier("rideEditorServicePattern")
                Text(localization.editorText("ios.editor.expressStopsNote"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Button {
                undoableDeletion = []
                let id = UUID()
                let ridden = RideLedger.hasBeenRidden(draft)
                let index = isNew ? max(0, draft.stops.count - 1) : draft.stops.count
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
                Button(localization.editorText(stopEditMode.isEditing
                    ? "ios.editor.finishReordering" : "ios.editor.reorderStops")) {
                    stopEditMode = stopEditMode.isEditing ? .inactive : .active
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("rideEditorReorderStops")
                .frame(minHeight: 44)
            }
            .id(RideDraftIssue.Field.stops)
        } footer: {
            Text(localization.editorText("ios.editor.stopsNote"))
        }
    }

    /// §8.6: a short undo rather than a confirmation, because the draft has
    /// not been committed and putting the rows back is exact.
    private var undoBanner: some View {
        HStack {
            Text(
                localization.editorText(
                    "ios.editor.deletedStops",
                    ["count": .number(Double(undoableDeletion.count))])
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            Spacer()
            Button(localization.editorText("ios.editor.undoDelete")) {
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

    /// New journeys define their endpoints by route order, including after undo.
    /// Existing records retain their explicitly authored stop roles.
    private func normalizeEndpointRoles() {
        guard isNew else { return }
        for index in draft.stops.indices {
            let role: String
            if index == 0 { role = "origin" }
            else if index == draft.stops.count - 1 { role = "destination" }
            else if ["origin", "destination"].contains(draft.stops[index].stopType) {
                role = "passenger_stop"
            } else { continue }
            if draft.stops[index].stopType != role { draft.stops[index].stopType = role }
        }
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
                Button(localization.editorText("ios.editor.policyReset")) {
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
                        region: Region.resolved(draft),
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
            Text(localization.editorText("ios.editor.rebuildAfterSave"))
        }
    }

    // MARK: - 5. Style

    private var styleSection: some View {
        Section {
            HStack {
                EditorTextField(
                    title: localization.editorText("ios.editor.routeColor"),
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
            if !isNew {
                regionPicker
                Text(localization.editorText("ios.editor.regionNote"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

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
            Text(localization.editorText("ios.editor.record"))
        } footer: {
            Text(localization.editorText("ios.editor.recordNote"))
        }
    }

    // MARK: - Inline messages

    /// Every message for one field, in the field's own row.
    @ViewBuilder
    private func fieldIssues(_ field: RideDraftIssue.Field) -> some View {
        ForEach(isNew && step != .confirm && !showsValidation ? [] : issues.all(for: field)) { issue in
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
        return localization.editorText(issue.key, issue.params)
    }

    // MARK: - Validation

    private var publishedIDs: Set<String> {
        existingIDs ?? RideStatusCenter.shared.trainIDs
    }

    private func revalidate() {
        issues = RideDraftValidation.issues(
            for: draft, originalID: original.id, existingIDs: publishedIDs)
        aiDenial = RideEditorAI.denial(
            train: draft, catalogs: editorCatalogs, requestInFlight: false)
    }

    private var blocking: [RideDraftIssue] { issues.blocking }

    /// Endpoints mirror the stop list during creation; report each missing station once.
    private var presentedBlocking: [RideDraftIssue] {
        blocking.filter { issue in
            guard isNew else { return true }
            guard issue.field != .origin && issue.field != .destination else { return false }
            switch step {
            case .region: return false
            case .route:
                switch issue.field { case .stops, .stop, .routePolicy, .routeSection: return true; default: return false }
            // The service name/number can be obtained from the timetable or AI
            // after the date is entered. It remains required at final review.
            case .service: return false
            case .date: return issue.field == .date
            case .confirm: return true
            }
        }
    }

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
    ///
    /// **Touching it takes it out of the pre-fill's hands, for good.** See
    /// ``prefillRidden(forDate:)``.
    private var riddenBinding: Binding<Bool> {
        Binding(
            get: { RideLedger.hasBeenRidden(draft) },
            set: { ridden in
                riddenIsTheReaders = true
                draft = RideLedger.setRidden(draft, ridden)
            })
    }

    /// The date pre-fill, and the exact edge of what the app is allowed to
    /// decide for itself.
    ///
    /// Nothing in this app may conclude from a date that a journey happened —
    /// a date is a plan, and a passport filled in from the calendar counts
    /// trips that were cancelled, moved or simply never taken. What a FORM may
    /// do is open on the likely answer, in a switch the reader is looking at,
    /// which they can move, and which they confirm by pressing Save. That is
    /// the whole of what this is, and it is fenced accordingly:
    ///
    ///   - **Only while creating.** An existing record's ride state is never
    ///     touched here, however its date is edited. What is written down is
    ///     what the reader said, and it stays said.
    ///   - **Only until touched.** The moment the reader moves the switch it
    ///     is theirs, and typing a different date afterwards will not move it
    ///     back.
    ///
    /// It follows the date field rather than firing once when the sheet opens
    /// because a blank journey has no date yet: seeded at open it would always
    /// read "ridden", and picking next month's date would leave it there —
    /// which is the pre-fill being wrong in exactly the direction that matters.
    private func prefillRidden(forDate date: String?) {
        guard isNew, !riddenIsTheReaders else { return }
        // An unparseable or empty date names no day, so there is nothing to be
        // ahead of and the form opens on "ridden" — the same answer every
        // record written by an older build carries.
        let ridden = Dates.normalizeDateString(date).map {
            $0 <= RecordDate.today(in: Region.resolved(draft).clock)
        } ?? true
        guard RideLedger.hasBeenRidden(draft) != ridden else { return }
        draft = RideLedger.setRidden(draft, ridden)
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
                if isNew && (draft.stops.contains { !$0.name.isEmpty || $0.n02StationCode != nil }
                    || !(draft.routePolicy?.preferredLineNames ?? []).isEmpty) {
                    pendingRegion = region
                } else {
                    undoableDeletion = []
                    draft.region = region.code
                    prefillRidden(forDate: draft.date)
                }
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
        case "hard": localization.editorText("ios.editor.hardConstraint")
        case "soft": localization.editorText("ios.editor.softPreference")
        default: localization.editorText("ios.editor.automatic")
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
        case "up": localization.editorText("ios.direction.up")
        case "down": localization.editorText("ios.direction.down")
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
        directionBasisSeen = basis
        let inferred = TravelDirection.infer(train: draft, package: package)?.direction.rawValue
        let current = draft.direction?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard current.isEmpty || current == autoInferredDirection else { return }
        autoInferredDirection = inferred
        if draft.direction != inferred {
            draft.direction = inferred
        }
    }

    private func saveDraft() {
        if !userDirectionEdited {
            let current = draft.direction?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if current.isEmpty, let package = routePackage,
               let inferred = TravelDirection.infer(train: draft, package: package) {
                draft.direction = inferred.direction.rawValue
                autoInferredDirection = inferred.direction.rawValue
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
        guard !isNew, repairStopsMatchOriginal,
              case .needsReview(_, _, let gaps) = RideStatusCenter.shared.status(forTrainID: original.id)
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
            let codes = stepped.train.stops.compactMap(\.n02StationCode)
            let aliases = await Task.detached(priority: .userInitiated) {
                loadJourneyStationAliases(for: codes, package: package)
            }.value
            let advance = await Task.detached(priority: .userInitiated) {
                RouteRepairFlow.advance(
                    train: stepped.train, package: package, aliases: aliases, steps: stepped.steps)
            }.value
            isRepairingRoute = false
            guard draft == snapshot else { return }
            if advance.train != snapshot {
                acceptedRouteStopCodes = advance.train.stops.map(\.n02StationCode)
                draft = advance.train
                synchronizeStopIdentity()
            }
            presentRepair(advance, repaired: advance.repaired, gaps: advance.gaps,
                          snapshot: snapshot, package: package)
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
            let codes = prepared.stops.compactMap(\.n02StationCode)
            let aliases = await Task.detached(priority: .userInitiated) {
                loadJourneyStationAliases(for: codes, package: package)
            }.value
            let advance = await Task.detached(priority: .userInitiated) {
                RouteRepairFlow.advance(
                    train: prepared, package: package, aliases: aliases, steps: steps)
            }.value
            isRepairingRoute = false
            guard draft == snapshot else { return }
            if advance.train != prepared {
                acceptedRouteStopCodes = advance.train.stops.map(\.n02StationCode)
                draft = advance.train
                synchronizeStopIdentity()
            }
            presentRepair(
                advance, repaired: repairedBase + advance.repaired,
                gaps: priorGaps + advance.gaps, snapshot: repairSnapshot, package: package)
        }
    }

    private func presentRepair(
        _ advance: RouteRepairFlow.Advance, repaired: Int, gaps: [RouteRepairFlow.GapName],
        snapshot: Train, package: CompactPackage
    ) {
        routeRepairSnapshot = snapshot
        routeRepairSummary = RouteRepairFlow.summary(
            repaired: repaired, needsChoice: advance.pause == nil ? 0 : 1, gaps: gaps
        ) { key, params in
            localization.text(key, params: params)
        }
        guard let pause = advance.pause, !pause.choices.isEmpty else { return }
        routeGuideRequest = RouteGuideRequest(
            train: advance.train, package: package, inferredChoices: pause.choices,
            focus: (pause.fromVisitID, pause.toVisitID),
            repairContinuation: RepairContinuation(
                remaining: pause.remaining, repaired: repaired, gaps: gaps, snapshot: snapshot))
    }

    private func optionalText(_ keyPath: WritableKeyPath<Train, String?>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] ?? "" },
            set: { draft[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
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

private struct ServiceRangeEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppLocalization.self) private var localization
    @Binding var train: Train
    let leg: JourneyServiceSections.Leg?
    @State private var fromIndex: Int
    @State private var toIndex: Int
    @State private var linesText: String
    @State private var operatorsText: String
    @State private var number: String
    @State private var name: String

    init(train: Binding<Train>, leg: JourneyServiceSections.Leg?) {
        _train = train
        self.leg = leg
        let sections = StoreOperations.rideRouteSections(for: train.wrappedValue)
        let firstUnfilled = sections.firstIndex { RouteSectionServiceInfo(section: $0).isEmpty }
            ?? max(0, sections.count - 1)
        _fromIndex = State(initialValue: leg?.fromStopIndex ?? firstUnfilled)
        _toIndex = State(initialValue: leg?.toStopIndex ?? firstUnfilled + 1)
        _linesText = State(initialValue: (leg?.info.lineNames ?? []).joined(separator: ", "))
        _operatorsText = State(initialValue: (leg?.info.operatorNames ?? []).joined(separator: ", "))
        _number = State(initialValue: leg?.info.number ?? "")
        _name = State(initialValue: leg?.info.name ?? "")
    }

    private var stopChoices: [Int] { Array(train.stops.indices) }
    private var lines: [String] { names(in: linesText) }
    private var operators: [String] { names(in: operatorsText) }

    var body: some View {
        Form {
            Section(localization.editorText("ios.editor.endpoints")) {
                Picker(localization.editorText("ios.editor.fromStation"), selection: $fromIndex) {
                    ForEach(stopChoices.dropLast(), id: \.self) { index in
                        Text(station(at: index)).tag(index)
                    }
                }
                .accessibilityIdentifier("rideEditorServiceFrom")
                .onChange(of: fromIndex) { _, index in
                    if toIndex <= index { toIndex = index + 1 }
                }
                Picker(localization.editorText("ios.editor.toStation"), selection: $toIndex) {
                    ForEach(stopChoices.filter { $0 > fromIndex }, id: \.self) { index in
                        Text(station(at: index)).tag(index)
                    }
                }
                .accessibilityIdentifier("rideEditorServiceTo")
            }
            Section {
                NavigationLink {
                    EditorLineSearchView(
                        region: Region.resolved(train), lineNames: lines, operatorNames: operators,
                        selectedLineIDs: [],
                        stationCodes: Array(train.stops[fromIndex...toIndex]).compactMap(\.n02StationCode)
                    ) { _, names, operatorNames in
                        linesText = names.joined(separator: ", ")
                        operatorsText = operatorNames.joined(separator: ", ")
                    }
                } label: {
                    LabeledContent(localization.editorText("ios.editor.searchLines"),
                                   value: lines.joined(separator: " · "))
                }
                EditorTextField(title: localization.editorText("ios.editor.lineNames"),
                                text: $linesText,
                                prompt: localization.editorText("ios.editor.onePerComma"))
                EditorTextField(title: localization.editorText("ios.editor.operatorNames"),
                                text: $operatorsText,
                                prompt: localization.editorText("ios.editor.onePerComma"))
                EditorTextField(title: localization.countryText("field.number", fallback: "Train number"),
                                text: $number,
                                prompt: localization.editorText("ios.editor.sectionNumberUnknown"))
                    .accessibilityIdentifier("rideEditorSectionNumber")
                EditorTextField(title: localization.editorText("ios.editor.displayName"), text: $name)
            } header: {
                Text(localization.editorText("ios.editor.sectionService"))
            } footer: {
                Text(localization.editorText("ios.editor.sectionServicesNote"))
            }
            if leg != nil {
                Section {
                    Button(localization.editorText("ios.editor.clearSectionService"), role: .destructive) {
                        train = RouteSectionServiceEditing.applying(
                            RouteSectionServiceInfo(), to: train,
                            fromStopIndex: fromIndex, toStopIndex: toIndex)
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(localization.editorText("ios.editor.sectionService"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(localization.editorText("ios.editor.applySectionService")) {
                    train = RouteSectionServiceEditing.applying(
                        RouteSectionServiceInfo(lineNames: lines, operatorNames: operators,
                                                number: number, name: name),
                        to: train, fromStopIndex: fromIndex, toStopIndex: toIndex)
                    dismiss()
                }
                .accessibilityIdentifier("rideEditorApplyServiceLeg")
            }
        }
    }

    private func station(at index: Int) -> String {
        let stop = train.stops[index]
        return "\(index + 1). \(localization.stationName(stop.name, in: train, code: stop.n02StationCode))"
    }

    private func names(in text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ",，、"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}

private struct RouteSectionLabel: View {
    let section: RouteSection?
    let index: Int
    /// Which readings table names these two stations. A section carries the
    /// OPERATOR's station code outside Japan, which names no region on its
    /// own — see `StationNaming.swift`.
    let region: Region
    let localization: AppLocalization

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(localization.editorText("ios.editor.sectionIndex", ["index": .number(Double(index))]))
            // A section whose endpoint NAME was dropped on the way to disk
            // still knows its station code: `leanExportSection` omits a name
            // the stop list can re-derive, so 「駅名未設定 → 駅名未設定」 is
            // what an ordinary, perfectly valid section reads as unless the
            // code is allowed to stand in for it.
            Text("\(endpoint(section?.from, section?.fromN02StationCode)) → "
                + "\(endpoint(section?.to, section?.toN02StationCode))")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }

    private func endpoint(_ name: String?, _ code: String?) -> String {
        if let name, !name.isEmpty {
            return localization.stationName(name, code: code, region: region)
        }
        if let code, !code.isEmpty { return code }
        return localization.editorText("ios.route.unnamedStation")
    }
}

private struct RoutePolicyEditorView: View {
    @Environment(AppLocalization.self) private var localization
    @Binding var policy: RoutePolicy

    var body: some View {
        Form {
            Section(localization.editorText("ios.editor.solver")) {
                Picker(
                    localization.editorText("ios.editor.institutionFilter"),
                    selection: optionalText(\.institutionFilterMode)
                ) {
                    Text(localization.editorText("ios.editor.automatic")).tag("")
                    Text(localization.editorText("ios.editor.softPreference")).tag("soft")
                    Text(localization.editorText("ios.editor.hardConstraint")).tag("hard")
                }
                Toggle(
                    localization.editorText("ios.editor.jrOnlyHint"), isOn: optionalBool(\.jrOnly))
                // Schema constants, shown so the reader can see they are off
                // rather than wonder. jsonspec §13.5: a straight line between
                // two stations is forbidden under all circumstances.
                LabeledContent(
                    localization.editorText("ios.editor.routeAlternatives"),
                    value: localization.editorText("ios.editor.disabled"))
                LabeledContent(
                    localization.editorText("ios.editor.straightLineFallback"),
                    value: localization.editorText("ios.editor.disabled"))
            }

            Section {
                EditorTextField(
                    title: localization.editorText("ios.editor.institutionCodes"),
                    text: commaSeparated(\.allowedInstitutionTypeCodes),
                    prompt: "1, 2, 3"
                )
                EditorTextField(
                    title: localization.editorText("ios.editor.preferredLines"),
                    text: commaSeparated(\.preferredLineNames),
                    prompt: localization.editorText("ios.editor.onePerComma")
                )
                EditorTextField(
                    title: localization.editorText("ios.editor.preferredOperators"),
                    text: commaSeparated(\.preferredOperatorNames),
                    prompt: localization.editorText("ios.editor.onePerComma")
                )
            } header: {
                Text(localization.editorText("ios.editor.preferences"))
            } footer: {
                Text(localization.editorText("ios.editor.policyFooter"))
            }
        }
        .navigationTitle(localization.text("ios.routePolicy", fallback: "Route policy"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func optionalText(_ keyPath: WritableKeyPath<RoutePolicy, String?>) -> Binding<String> {
        Binding(
            get: { policy[keyPath: keyPath] ?? "" },
            set: { policy[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    private func optionalBool(_ keyPath: WritableKeyPath<RoutePolicy, Bool?>) -> Binding<Bool> {
        Binding(
            get: { policy[keyPath: keyPath] ?? false },
            set: { policy[keyPath: keyPath] = $0 }
        )
    }

    private func commaSeparated(
        _ keyPath: WritableKeyPath<RoutePolicy, [String]?>
    ) -> Binding<String> {
        Binding(
            get: { (policy[keyPath: keyPath] ?? []).joined(separator: ", ") },
            set: { policy[keyPath: keyPath] = Self.values(from: $0) }
        )
    }

    private static func values(from text: String) -> [String]? {
        let values = text.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        return values.isEmpty ? nil : values
    }
}

private struct RouteSectionEditorView: View {
    @Environment(AppLocalization.self) private var localization
    @Binding var section: RouteSection
    let region: Region
    var rideDate: String? = nil

    var body: some View {
        Form {
            Section(localization.editorText("ios.editor.endpoints")) {
                EditorTextField(
                    title: localization.editorText("ios.editor.fromStation"),
                    text: optionalText(\.from))
                NavigationLink {
                    StationPickerView(
                        regionCode: region.code,
                        onSelect: { station in
                            section.from = station.name
                            section.fromN02StationCode = station.key.sourceCode
                        },
                        rideDate: rideDate,
                        onSelectRetired: { station in
                            section.from = station.name
                            section.fromN02StationCode = station.certifiedCode
                        })
                    .environment(localization)
                } label: {
                    LabeledContent(
                        localization.editorText("ios.editor.chooseStation"),
                        value: section.from ?? "")
                }
                EditorTextField(
                    title: localization.editorText("ios.editor.toStation"),
                    text: optionalText(\.to))
                NavigationLink {
                    StationPickerView(
                        regionCode: region.code,
                        onSelect: { station in
                            section.to = station.name
                            section.toN02StationCode = station.key.sourceCode
                        },
                        rideDate: rideDate,
                        onSelectRetired: { station in
                            section.to = station.name
                            section.toN02StationCode = station.certifiedCode
                        })
                    .environment(localization)
                } label: {
                    LabeledContent(
                        localization.editorText("ios.editor.chooseStation"),
                        value: section.to ?? "")
                }
            }

            Section(localization.editorText("ios.editor.constraints")) {
                EditorTextField(
                    title: localization.editorText("ios.editor.lineNames"),
                    text: commaSeparated(\.lineNames),
                    prompt: localization.editorText("ios.editor.onePerComma"))
                EditorTextField(
                    title: localization.editorText("ios.editor.operatorNames"),
                    text: commaSeparated(\.operatorNames),
                    prompt: localization.editorText("ios.editor.onePerComma"))
            }

            Section(localization.editorText("ios.editor.sectionService")) {
                EditorTextField(
                    title: localization.countryText("field.number", fallback: "Train number"),
                    text: optionalText(\.number))
                EditorTextField(
                    title: localization.editorText("ios.editor.displayName"),
                    text: optionalText(\.name))
            }
        }
        .navigationTitle(localization.text("ios.routeSection", fallback: "Route section"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func optionalText(_ keyPath: WritableKeyPath<RouteSection, String?>) -> Binding<String> {
        Binding(
            get: { section[keyPath: keyPath] ?? "" },
            set: { section[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    private func commaSeparated(
        _ keyPath: WritableKeyPath<RouteSection, [String]?>
    ) -> Binding<String> {
        Binding(
            get: { (section[keyPath: keyPath] ?? []).joined(separator: ", ") },
            set: {
                let values = $0.split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }.filter { !$0.isEmpty }
                section[keyPath: keyPath] = values.isEmpty ? nil : values
            }
        )
    }
}

private struct StopEditorLabel: View {
    @Environment(AppLocalization.self) private var localization
    let stop: Stop
    let journeyDate: String?
    let index: Int
    var emptyTitle: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            Text(index, format: .number)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(stop.name.isEmpty ? (emptyTitle ?? localization.editorText("ios.editor.untitledStop")) : stop.name)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    if let arrival = stop.arrival, !arrival.isEmpty { Text(displayTime(arrival)) }
                    if let departure = stop.departure, !departure.isEmpty { Text(displayTime(departure)) }
                    if let actual = stop.actualArrival, !actual.isEmpty {
                        Text("実着 \(displayTime(actual))")
                    }
                    if let actual = stop.actualDeparture, !actual.isEmpty {
                        Text("実発 \(displayTime(actual))")
                    }
                    if let platform = stop.platformNumber {
                        Text(
                            localization.editorText(
                                "ios.detail.platformValue",
                                ["number": .number(Double(platform))]))
                    }
                    if stop.stopType != "passenger_stop" {
                        Text(localization.countryText("stoptype.\(stop.stopType)", fallback: stop.stopType))
                    }
                    if !stop.rideSegment {
                        Text(localization.editorText("ios.detail.notRidden"))
                    }
                }
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
            Spacer()
            if stop.rideSegment {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
                    .accessibilityLabel(localization.editorText("ios.detail.ridden"))
            }
        }
        .frame(minHeight: 44)
    }

    private func displayTime(_ raw: String) -> String {
        guard let journeyDate,
              case .valid(_, let clock) = EditorTime.parseTime(raw),
              clock.dayOffset > 0,
              let date = Dates.addDays(journeyDate, clock.dayOffset)
        else { return raw }
        return "\(date) " + String(format: "%02d:%02d", clock.hour, clock.minute)
    }
}

/// Station-and-time gate shared by the AI button and the completion sheet.
private enum RideEditorAI {
    static func denial(train: Train, catalogs: [String: EditorCatalog], requestInFlight: Bool) -> EditorAIDenial? {
        let resolved = JourneyCompletion.resolvingUniqueStationNames(in: train, catalogs: catalogs)
        return JourneyCompletion.requestDenial(
            train: resolved,
            stationIsInDatabase: { code in
                catalogs.contains { region, catalog in
                    catalog.station(StationKey(regionCode: region, sourceCode: code)) != nil
                }
            },
            requestInFlight: requestInFlight)
    }
}

/// Decoding geometry stays off the main actor and is reused across endpoint edits.
enum EditorRoutePackageCache {
    final class Store: @unchecked Sendable {
        static let shared = Store()
        let lock = NSLock()
        var packages: [String: CompactPackage] = [:]
    }

    nonisolated static func load(region: Region) throws -> CompactPackage {
        let store = Store.shared
        store.lock.lock()
        let cached = store.packages[region.code]
        store.lock.unlock()
        if let cached { return cached }
        guard let url = Bundle.main.url(forResource: region.packageResource, withExtension: "json")
        else { throw EditorCatalogLoadError.missingResource(region.code) }
        let package = try JSONDecoder().decode(CompactPackage.self, from: Data(contentsOf: url))
        store.lock.lock()
        store.packages[region.code] = package
        store.lock.unlock()
        return package
    }
}

private struct StopEditorView: View {
    @Environment(AppLocalization.self) private var localization
    @Binding var stop: Stop
    @Binding var journeyDate: String?
    let index: Int
    var isNew = false
    /// The ride's region, so the picker offers that network's stations rather
    /// than all 14,000 across five countries — where 中央駅 and 中央站 would
    /// sit next to each other and picking the wrong one is a route that will
    /// never solve.
    let region: Region
    var allowsEndpointRoles = true
    let selectedLineIDs: Set<String>
    var onRiddenChange: () -> Void = {}

    /// `TrainValidation.stopTypes`, not a copy of it: the order is the web
    /// editor's `<select>` order and is quoted into the rejection message, so
    /// a second list here would be a second answer.
    private var types: [String] { TrainValidation.stopTypes }
    @FocusState private var stationNameFocused: Bool
    @State private var catalog: EditorCatalog?
    @State private var stationMatches: [CatalogStation] = []
    @State private var retiredStationMatches: [RetiredStation] = []
    @State private var retiredOpenStations: [RetiredStation] = []

    private var selectedLines: [CatalogLine] {
        guard let catalog else { return [] }
        return selectedLineIDs.compactMap { catalog.line(id: $0, regionCode: region.code) }
            .sorted { lhs, rhs in
                if lhs.name != rhs.name { return lhs.name < rhs.name }
                return lhs.id < rhs.id
            }
    }

    private var filteredStations: [CatalogStation] {
        guard let catalog else { return [] }
        guard !selectedLineIDs.isEmpty else { return catalog.stations(in: region.code) }
        let keys = Set(selectedLineIDs.flatMap { lineID in
            catalog.memberships(lineID: lineID, regionCode: region.code).map(\.stationKey)
        })
        return catalog.stations(in: region.code).filter { keys.contains($0.key) }
    }

    private var hasStationLineConflict: Bool {
        guard let catalog, !selectedLineIDs.isEmpty,
              let code = stop.n02StationCode, !code.isEmpty
        else { return false }
        let key = StationKey(regionCode: region.code, sourceCode: code)
        return catalog.memberships(stationKey: key).allSatisfy { !selectedLineIDs.contains($0.lineID) }
    }

    private var stationName: Binding<String> {
        Binding(get: { stop.name }, set: { name in
            if name != stop.name { stop.n02StationCode = nil }
            stop.name = name
        })
    }

    var body: some View {
        Form {
            Section(localization.editorText("ios.editor.station")) {
                if stop.routeEditing?.generatedBy != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        AutoFilledStationLabel()
                        Text(localization.editorText("ios.editor.generatedStationsNote"))
                            .font(.footnote).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityIdentifier("stopEditorAutoFilledNote")
                }
                EditorField(title: localization.editorText("ios.editor.stationName")) {
                    TextField(localization.editorText("ios.editor.stationSearch"), text: stationName)
                        .focused($stationNameFocused)
                        .autocorrectionDisabled()
                }
                .accessibilityIdentifier("rideEditorStopName")
                if stationNameFocused {
                    ForEach(stationMatches, id: \.key.sourceCode) { station in
                        Button {
                            stop.name = station.name
                            stop.n02StationCode = station.key.sourceCode
                            stationNameFocused = false
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(station.name)
                                if let catalog {
                                    let subtitle = StationCatalogText.subtitle(for: station, catalog: catalog)
                                    if !subtitle.isEmpty {
                                        Text(subtitle)
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("rideEditorStationSuggestion-\(station.key.sourceCode)")
                    }
                    ForEach(retiredStationMatches, id: \.id) { station in
                        Button {
                            stop.name = station.name
                            stop.n02StationCode = station.certifiedCode
                            stationNameFocused = false
                        } label: {
                            RetiredStationLabel(station: station, rideDate: journeyDate)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("stationPickerRetired-\(station.id)")
                    }
                }
                if stop.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(localization.editorText("ios.editor.stationGuide"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if stop.n02StationCode?.isEmpty != false {
                    if let matchedRetired = retiredOpenStations.first(where: { $0.name == stop.name }) {
                        Label(
                            localization.editorText(
                                matchedRetired.certifiedCode != nil
                                    ? "ios.editor.renamedStationNote" : "ios.editor.retiredStationNote"),
                            systemImage: "clock.arrow.circlepath")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(localization.editorText("ios.editor.stationUnmatched"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if hasStationLineConflict {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(localization.editorText("ios.editor.station")): \(stop.name)")
                            Text("\(localization.editorText("ios.editor.lineNames")): \(selectedLines.map(\.name).joined(separator: " · "))")
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("rideEditorStationLineConflict")
                }
                NavigationLink {
                    StationPickerView(
                        regionCode: region.code, selectedLineIDs: selectedLineIDs,
                        onSelect: { station in
                            stop.name = station.name
                            stop.n02StationCode = station.key.sourceCode
                        },
                        rideDate: journeyDate,
                        onSelectRetired: { station in
                            stop.name = station.name
                            stop.n02StationCode = station.certifiedCode
                        })
                    .environment(localization)
                } label: {
                    Label(
                        localization.editorText("ios.editor.chooseStation"),
                        systemImage: "tram.circle")
                }
                EditorTextField(
                    title: localization.editorText("ios.editor.platformNumber"),
                    text: platformText,
                    prompt: localization.editorText("ios.editor.platformOptional")
                )
                .accessibilityIdentifier("rideEditorStopPlatform")
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                if let platform = stop.platformNumber, platform < 0 {
                    Label(
                        localization.editorText("ios.editor.platformRule"),
                        systemImage: "exclamationmark.circle.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section {
                if isNew {
                    Toggle(localization.editorText("ios.editor.includeDate"), isOn: Binding(
                        get: { journeyDate != nil },
                        set: { journeyDate = $0 ? RecordDate.today(in: region.clock) : nil }
                    ))
                    .accessibilityIdentifier("rideEditorStopIncludeDate")
                }
                if !isNew || journeyDate != nil {
                    EditorDateField(
                        title: localization.editorText("ios.editor.date"),
                        date: Binding(
                            get: { journeyDate },
                            set: { journeyDate = $0 ?? "" }),
                        region: region,
                        accessibilityID: "rideEditorStopJourneyDate")
                }
            } header: {
                Text(localization.editorText("ios.editor.date"))
            } footer: {
                Text(localization.editorText("ios.editor.sharedJourneyDateNote"))
            }

            Section {
                if stop.stopType == "pass_through" {
                    EditorTimeField(
                        title: localization.editorText("ios.editor.passTime"),
                        time: $stop.departure,
                        serviceDate: journeyDate,
                        accessibilityID: "rideEditorStopDeparture")
                    if let arrival = stop.arrival, arrival.isEmpty == false {
                        EditorTimeField(
                            title: localization.countryText("popup.arrival", fallback: "Arrival"),
                            time: $stop.arrival,
                            serviceDate: journeyDate)
                    }
                } else {
                    EditorTimeField(
                        title: localization.countryText("popup.arrival", fallback: "Arrival"),
                        time: $stop.arrival,
                        serviceDate: journeyDate,
                        accessibilityID: "rideEditorStopArrival")
                    EditorTimeField(
                        title: localization.countryText("popup.departure", fallback: "Departure"),
                        time: $stop.departure,
                        serviceDate: journeyDate,
                        accessibilityID: "rideEditorStopDeparture")
                }
            } header: {
                Text(localization.editorText("ios.editor.times"))
            } footer: {
                // The stored clock keeps its service-day offset (for example,
                // 25:10); the picker and preview show its civil date.
                Text(localization.editorText("ios.editor.crossDayHint"))
            }
            Section {
                EditorTimeField(title: localization.editorText("ios.editor.actualArrival"),
                                time: $stop.actualArrival,
                                serviceDate: journeyDate,
                                accessibilityID: "rideEditorStopActualArrival")
                if let status = StopTimingStatus.localizedLabel(
                    scheduled: stop.arrival, actual: stop.actualArrival,
                    localization: localization) {
                    Text(status).foregroundStyle(.secondary)
                }
                EditorTimeField(title: localization.editorText("ios.editor.actualDeparture"),
                                time: $stop.actualDeparture,
                                serviceDate: journeyDate,
                                accessibilityID: "rideEditorStopActualDeparture")
                if let status = StopTimingStatus.localizedLabel(
                    scheduled: stop.departure, actual: stop.actualDeparture,
                    localization: localization) {
                    Text(status).foregroundStyle(.secondary)
                }
            } header: {
                Text(localization.editorText("ios.editor.actualTimes"))
            } footer: {
                Text(localization.editorText("ios.editor.actualTimesNote"))
            }

            Section {
                Picker(
                    localization.countryText("popup.stopType", fallback: "Stop type"),
                    selection: $stop.stopType
                ) {
                    ForEach(allowsEndpointRoles ? types : types.filter {
                        !["origin", "destination"].contains($0) || $0 == stop.stopType
                    }, id: \.self) {
                        Text(localization.countryText("stoptype.\($0)", fallback: $0)).tag($0)
                    }
                }
                .disabled(!allowsEndpointRoles && ["origin", "destination"].contains(stop.stopType))
                Toggle(
                    localization.countryText("popup.rideSegment", fallback: "Ridden segment"),
                    isOn: Binding(get: { stop.rideSegment }, set: { value in
                        onRiddenChange()
                        stop.rideSegment = value
                    }))
                    .accessibilityIdentifier("rideEditorStopRidden")
            } footer: {
                Text(localization.editorText("ios.editor.rideSegmentNote"))
            }
        }
        .task(id: region.code) {
            let region = region
            do {
                let loaded = try await Task.detached(priority: .userInitiated) {
                    try loadCatalog(for: region)
                }.value
                guard !Task.isCancelled else { return }
                catalog = loaded
            } catch {
                guard !Task.isCancelled else { return }
                catalog = nil
            }
        }
        .task(id: "\(region.code)|\(stop.name)|\(selectedLineIDs.sorted().joined(separator: ","))|\(catalog == nil)") {
            guard catalog != nil else {
                stationMatches = []
                return
            }
            let stations = filteredStations
            let query = stop.name.trimmingCharacters(in: .whitespacesAndNewlines)
            stationMatches = []
            guard !query.isEmpty else { return }
            do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
            let found = await Task.detached(priority: .userInitiated) {
                let prepared = SearchFold.PreparedQuery(query)
                return stations.compactMap { station -> (station: CatalogStation, rank: Int)? in
                    let fields = [station.name] + station.aliases
                    guard prepared.matches(fields: fields) else { return nil }
                    let names = fields.map(SearchFold.fold)
                    let rank = names.contains(prepared.whole)
                        ? 0
                        : names.contains(where: { $0.hasPrefix(prepared.whole) }) ? 1 : 2
                    return (station, rank)
                }
                .sorted { lhs, rhs in
                    if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
                    let order = lhs.station.name.localizedStandardCompare(rhs.station.name)
                    if order != .orderedSame { return order == .orderedAscending }
                    return lhs.station.key.sourceCode < rhs.station.key.sourceCode
                }
                .prefix(6)
                .map(\.station)
            }.value
            guard !Task.isCancelled else { return }
            stationMatches = Array(found)
        }
        .task(id: "\(region.code)|\(journeyDate ?? "")|\(selectedLineIDs.sorted().joined(separator: ","))|\(catalog == nil)") {
            // Cheap empty check: an undated/current-date ride never has an
            // open retired station, so skip the overlay decode entirely.
            guard let journeyDate, !journeyDate.isEmpty else {
                retiredOpenStations = []
                return
            }
            let regionCode = region.code
            let lineIDs = selectedLineIDs
            let loadedCatalog = catalog
            let open = await Task.detached(priority: .userInitiated) {
                openRetiredStations(
                    catalog: loadedCatalog, regionCode: regionCode, selectedLineIDs: lineIDs,
                    rideDate: journeyDate)
            }.value
            guard !Task.isCancelled else { return }
            retiredOpenStations = open
        }
        .task(id: "\(stop.name)|\(retiredOpenStations.map(\.id).joined(separator: ","))") {
            let query = stop.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty, !retiredOpenStations.isEmpty else {
                retiredStationMatches = []
                return
            }
            let prepared = SearchFold.PreparedQuery(query)
            retiredStationMatches = retiredOpenStations.filter {
                prepared.matches(fields: [$0.name])
            }
        }
        .navigationTitle(
            stop.name.isEmpty
                ? localization.editorText("ios.editor.stopIndex", ["index": .number(Double(index + 1))])
                : stop.name
        )
        .navigationBarTitleDisplayMode(.inline)
    }

    private func optionalText(_ keyPath: WritableKeyPath<Stop, String?>) -> Binding<String> {
        Binding(
            get: { stop[keyPath: keyPath] ?? "" },
            set: { stop[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    private var platformText: Binding<String> {
        Binding(
            get: { stop.platformNumber.map(String.init) ?? "" },
            set: {
                let value = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                stop.platformNumber = value.isEmpty ? nil : Int(value)
            }
        )
    }
}

private enum StationCatalogText {
    static func subtitle(for station: CatalogStation, catalog: EditorCatalog) -> String {
        let operators = Dictionary(
            uniqueKeysWithValues: catalog.operators(in: station.key.regionCode).map { ($0.id, $0.name) })
        return subtitle(for: station, catalog: catalog, operators: operators)
    }

    static func subtitle(
        for station: CatalogStation, catalog: EditorCatalog, operators: [String: String]
    ) -> String {
        let memberships = catalog.memberships(stationKey: station.key)
        let labels = memberships.prefix(3).map { member -> String in
            guard let line = catalog.line(id: member.lineID, regionCode: member.regionCode) else {
                return member.lineID
            }
            if let name = line.operatorIDs.compactMap({ operators[$0] }).first(where: { !$0.isEmpty }) {
                return "\(line.name) · \(name)"
            }
            return line.name
        }
        var text = labels.joined(separator: " · ")
        if memberships.count > 3 { text += " · +\(memberships.count - 3)" }
        return text
    }

    static func rows(catalog: EditorCatalog, regionCode: String) -> [CatalogStationRow] {
        let operators = Dictionary(
            uniqueKeysWithValues: catalog.operators(in: regionCode).map { ($0.id, $0.name) })
        return catalog.stations(in: regionCode).map { station in
            CatalogStationRow(
                station: station,
                subtitle: subtitle(for: station, catalog: catalog, operators: operators))
        }
    }
}

private struct CatalogStationLineGroup: Identifiable, Sendable {
    var line: CatalogLine
    var operatorID: String
    var operatorName: String
    var rows: [CatalogStationRow]
    var id: String { line.id }
}

private struct CatalogStationCompanyGroup: Identifiable {
    var id: String
    var name: String
    var lines: [CatalogStationLineGroup]
}

/// ADR 0011 overlay stations open on `rideDate`, restricted to
/// `selectedLineIDs` when non-empty. `[]` for an undated/current-date
/// ride, matching ``RetiredStation/period(on:)``'s own guard.
private nonisolated func openRetiredStations(
    catalog: EditorCatalog?, regionCode: String, selectedLineIDs: Set<String>,
    rideDate: String?
) -> [RetiredStation] {
    guard let rideDate, !rideDate.isEmpty else { return [] }
    let all = RiddenRouteStore.retiredStations(region: regionCode)
    guard !all.isEmpty else { return [] }
    let open = RailHistoryStations.open(all, on: rideDate)
    guard !open.isEmpty else { return [] }
    guard !selectedLineIDs.isEmpty, let catalog else { return open }
    let selectedLines = catalog.lines(in: regionCode).filter { selectedLineIDs.contains($0.id) }
    let allowedNames = Set(selectedLines.flatMap { [$0.name] + $0.aliases })
    // Overlay line names are N02 spellings and may not match the catalog's;
    // an empty filtered result means the names didn't line up, not that
    // there are truly no open retired stations on these lines.
    let filtered = open.filter { allowedNames.contains($0.lineName) }
    return filtered.isEmpty ? open : filtered
}

/// Catalog stations for one region. Empty search is a company → line → station
/// browser. Search results keep those categories instead of flattening stations
/// with the same display name into one ambiguous list.
private struct StationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppLocalization.self) private var localization
    let regionCode: String
    var selectedLineIDs: Set<String> = []
    let onSelect: (CatalogStation) -> Void
    var rideDate: String? = nil
    var onSelectRetired: ((RetiredStation) -> Void)? = nil
    @State private var query = ""
    @State private var search = StationPickerSearchController()
    @State private var preparedLineGroups: [CatalogStationLineGroup] = []
    @State private var didLoad = false
    @State private var loadError: String?


    private var matches: [CatalogStationRow] { search.matches }
    private var retired: [RetiredStation] { search.retired }
    private var matchedRetired: [RetiredStation] { search.matchedRetired }
    private var loadIdentity: StationPickerSearchController.LoadIdentity {
        .init(regionCode: regionCode, selectedLineIDs: selectedLineIDs,
            rideDate: rideDate, includesRetired: onSelectRetired != nil)
    }

    private var companyGroups: [CatalogStationCompanyGroup] {
        Dictionary(grouping: preparedLineGroups, by: \.operatorID).map { operatorID, lines in
            CatalogStationCompanyGroup(
                id: operatorID,
                name: lines.first?.operatorName
                    ?? localization.countryText("field.company", fallback: "Operator"),
                lines: lines)
        }
        .sorted { lhs, rhs in
            if lhs.name != rhs.name { return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending }
            return lhs.id < rhs.id
        }
    }

    private var matchedLineGroups: [CatalogStationLineGroup] {
        let keys = Set(matches.map(\.station.key))
        return preparedLineGroups.compactMap { group in
            let rows = group.rows.filter { keys.contains($0.station.key) }
            guard !rows.isEmpty else { return nil }
            var copy = group
            copy.rows = rows
            return copy
        }
    }

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Group {
            if let loadError {
                Text(loadError)
                    .foregroundStyle(.secondary)
                    .padding()
            } else if !didLoad {
                ProgressView()
            } else if isSearching {
                List {
                    ForEach(matchedLineGroups) { group in
                        Section {
                            ForEach(group.rows) { row in stationButton(row) }
                        } header: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.operatorName)
                                Text(group.line.name).font(.caption)
                            }
                        }
                    }
                    if !matchedRetired.isEmpty {
                        ForEach(matchedRetired) { station in retiredStationButton(station) }
                    }
                    if matchedLineGroups.isEmpty && matchedRetired.isEmpty {
                        Text(localization.editorText("ios.editor.stationUnmatched"))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                List {
                    ForEach(companyGroups) { company in
                        Section(company.name) {
                            ForEach(company.lines) { group in
                                NavigationLink {
                                    StationLinePickerView(
                                        title: group.line.name,
                                        rows: group.rows,
                                        onSelect: select)
                                } label: {
                                    Text(group.line.name)
                                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                }
                                .accessibilityIdentifier("rideEditorStationLine-\(group.line.id)")
                            }
                        }
                    }
                    if !retired.isEmpty {
                        Section(localization.editorText("ios.editor.retiredStationsSection")) {
                            ForEach(retired) { station in retiredStationButton(station) }
                        }
                    }
                }
            }
        }
        .navigationTitle(localization.editorText("ios.editor.chooseStation"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $query, placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(localization.editorText("ios.editor.stationSearch")))
        .task(id: loadIdentity) {
            let input = loadIdentity
            let loadID = search.beginLoad()
            didLoad = false
            loadError = nil
            preparedLineGroups = []
            guard let region = Region(rawValue: input.regionCode) else {
                loadError = EditorCatalogLoadError.missingResource(input.regionCode).localizedDescription
                return
            }
            do {
                let catalog = try await Task.detached(priority: .userInitiated) {
                    try loadCatalog(for: region)
                }.value
                guard !Task.isCancelled, search.acceptsLoad(loadID) else { return }
                let result = await Task.detached(priority: .userInitiated) {
                    Self.prepare(catalog: catalog, regionCode: input.regionCode,
                        selectedLineIDs: input.selectedLineIDs)
                }.value
                guard !Task.isCancelled, search.acceptsLoad(loadID) else { return }
                var retired: [RetiredStation] = []
                if input.includesRetired {
                    retired = await Task.detached(priority: .userInitiated) {
                        openRetiredStations(catalog: catalog, regionCode: input.regionCode,
                            selectedLineIDs: input.selectedLineIDs, rideDate: input.rideDate)
                    }.value
                    guard !Task.isCancelled, search.acceptsLoad(loadID) else { return }
                }
                guard search.install(rows: result.rows, retired: retired, loadID: loadID, query: query)
                else { return }
                preparedLineGroups = result.groups
                didLoad = true
            } catch {
                guard !Task.isCancelled, search.acceptsLoad(loadID) else { return }
                loadError = error.localizedDescription
            }
        }
        .onChange(of: query) { _, needle in search.apply(query: needle) }
        .onDisappear { search.cancel() }
    }

    @ViewBuilder
    private func stationButton(_ row: CatalogStationRow) -> some View {
        Button { select(row.station) } label: {
            CatalogStationLabel(row: row)
        }
        .buttonStyle(RailRowPressStyle(cornerRadius: 0))
        .accessibilityIdentifier("rideEditorStation-\(row.station.key.sourceCode)")
    }

    @ViewBuilder
    private func retiredStationButton(_ station: RetiredStation) -> some View {
        Button { selectRetired(station) } label: {
            RetiredStationLabel(station: station, rideDate: rideDate)
        }
        .buttonStyle(RailRowPressStyle(cornerRadius: 0))
        .accessibilityIdentifier("stationPickerRetired-\(station.id)")
    }

    private func select(_ station: CatalogStation) {
        onSelect(station)
        dismiss()
    }

    private func selectRetired(_ station: RetiredStation) {
        onSelectRetired?(station)
        dismiss()
    }

    private nonisolated static func prepare(
        catalog: EditorCatalog, regionCode: String, selectedLineIDs: Set<String>
    ) -> (rows: [CatalogStationRow], groups: [CatalogStationLineGroup]) {
        let allRows = StationCatalogText.rows(catalog: catalog, regionCode: regionCode)
        let rowByKey = Dictionary(uniqueKeysWithValues: allRows.map { ($0.station.key, $0) })
        let operatorNames = Dictionary(
            uniqueKeysWithValues: catalog.operators(in: regionCode).map { ($0.id, $0.name) })
        let lines = catalog.lines(in: regionCode).filter {
            selectedLineIDs.isEmpty || selectedLineIDs.contains($0.id)
        }
        let groups = lines.compactMap { line -> CatalogStationLineGroup? in
            var seen: Set<StationKey> = []
            let rows: [CatalogStationRow] = catalog
                .memberships(lineID: line.id, regionCode: regionCode)
                .compactMap { member -> CatalogStationRow? in
                    guard seen.insert(member.stationKey).inserted else { return nil }
                    return rowByKey[member.stationKey]
                }
            guard !rows.isEmpty else { return nil }
            let operatorID = line.operatorIDs.first ?? ""
            return CatalogStationLineGroup(
                line: line,
                operatorID: operatorID,
                operatorName: operatorNames[operatorID] ?? operatorID,
                rows: rows)
        }
        let keys = Set(groups.flatMap { $0.rows }.map { $0.station.key })
        return (allRows.filter { keys.contains($0.station.key) }, groups)
    }

}

private struct RetiredStationLabel: View {
    @Environment(AppLocalization.self) private var localization
    let station: RetiredStation
    let rideDate: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(station.name)
            Text("\(station.lineName) · \(station.operatorName)")
                .font(.caption).foregroundStyle(.secondary)
            Label(
                closedText, systemImage: "clock.arrow.circlepath"
            )
            .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    private var closedText: String {
        // A `certifiedCode` means this entry is an old name for a station
        // that still exists today (builder-certified same code + geometry),
        // not a closed station.
        let marker = localization.editorText(
            station.certifiedCode != nil ? "ios.editor.renamedStation" : "ios.editor.retiredStation")
        guard let validTo = station.period(on: rideDate)?.validTo else { return marker }
        let onKey = station.certifiedCode != nil ? "ios.editor.renamedOn" : "ios.editor.retiredOn"
        return "\(marker) · \(localization.editorText(onKey, ["date": .string(validTo)]))"
    }
}

private struct CatalogStationLabel: View {
    let row: CatalogStationRow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.station.name)
            if !row.subtitle.isEmpty {
                Text(row.subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(.rect)
    }
}

private struct StationLinePickerView: View {
    let title: String
    let rows: [CatalogStationRow]
    let onSelect: (CatalogStation) -> Void

    var body: some View {
        List(rows) { row in
            Button { onSelect(row.station) } label: {
                CatalogStationLabel(row: row)
            }
            .buttonStyle(RailRowPressStyle(cornerRadius: 0))
            .accessibilityIdentifier("rideEditorStation-\(row.station.key.sourceCode)")
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A form field that keeps its label visible once it has a value.
///
/// A bare `TextField("車次", text:)` in a `Form` shows its title *only while
/// the field is empty* — the moment a value arrives, the one word saying what
/// the value means disappears. On a form of ten fields that leaves a column of
/// unlabelled strings, and it is worse in the three CJK interface languages,
/// where a station name and an operator name are the same shape.
///
/// So the label is a caption above the value, which also keeps a long label
/// and a long value from competing for one line (§10.1, §14.5).
private struct EditorField<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            content
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

/// `EditorField` around a plain text field, which is nearly all of them.
///
/// `focus`/`field` are threaded in rather than left to the caller's
/// `.focused(...)` on the wrapper: the focus binding has to land on the
/// focusable element itself for "查看错误" to be able to put the cursor in the
/// first bad field, and a modifier on the enclosing `VStack` is not a
/// guarantee that it does.
private struct EditorTextField: View {
    let title: String
    @Binding var text: String
    var prompt: String?
    var focus: FocusState<RideDraftIssue.Field?>.Binding?
    var field: RideDraftIssue.Field?
    var onSubmit: (() -> Void)? = nil

    var body: some View {
        EditorField(title: title) {
            if let focus, let field {
                textField.focused(focus, equals: field)
            } else {
                textField
            }
        }
    }

    private var textField: some View {
        TextField(title, text: $text, prompt: Text(prompt ?? title))
            .labelsHidden()
            .onSubmit { onSubmit?() }
    }
}

/// Text remains editable even when a catalog or previous record has no match.
private struct EditorSearchField: View {
    let title: String
    @Binding var text: String
    let suggestions: [String]
    var prompt: String? = nil
    var focus: FocusState<RideDraftIssue.Field?>.Binding?
    var field: RideDraftIssue.Field?
    @FocusState private var hasFocus: Bool

    private var matches: [String] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prepared = SearchFold.PreparedQuery(query)
        return Array(Set(suggestions.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }))
            .filter { query.isEmpty || prepared.matches(fields: OperatorIdentity.searchNames(for: $0)) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .prefix(6).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            EditorField(title: title) {
                textField
            }
            if isFocused {
                ForEach(matches, id: \.self) { value in
                    Button {
                        text = value
                        dismissFocus()
                    } label: {
                        Label(value, systemImage: "arrow.up.left")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("editorSuggestion-\(value)")
                }
            }
        }
    }

    // Bind the native field to the same focus state as the editor's other fields.
    // The private Boolean is only used by search fields without an editor binding.
    @ViewBuilder private var textField: some View {
        if let focus, let field {
            baseTextField.focused(focus, equals: field)
        } else {
            baseTextField.focused($hasFocus)
        }
    }

    private var baseTextField: some View {
        TextField(title, text: $text, prompt: Text(prompt ?? title))
            .submitLabel(.done)
            .onSubmit { dismissFocus() }
            .autocorrectionDisabled()
    }

    private var isFocused: Bool {
        if let focus, let field { return focus.wrappedValue == field }
        return hasFocus
    }

    private func dismissFocus() {
        if let focus, let field {
            if focus.wrappedValue == field { focus.wrappedValue = nil }
        } else {
            hasFocus = false
        }
    }
}

private struct EditorLineSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppLocalization.self) private var localization
    let region: Region
    let lineNames: [String]
    let operatorNames: [String]
    let selectedLineIDs: Set<String>
    let stationCodes: [String]
    let onCommit: (_ lineIDs: [String], _ lineNames: [String], _ operatorNames: [String]) -> Void
    @State private var query = ""
    @State private var isSearching = false
    @State private var catalog: EditorCatalog?
    @State private var regionLines: [CatalogLine] = []
    @State private var operatorNameByID: [String: String] = [:]
    @State private var selectedIDs: Set<String> = []
    @State private var unresolvedNames: [String] = []
    @State private var didInitialize = false
    @State private var didCommit = false
    @State private var userEdited = false
    @State private var loadError: String?

    private struct OperatorLineGroup: Identifiable {
        var id: String
        var name: String
        var lines: [CatalogLine]
    }

    /// Nil means there is no resolved station constraint. A non-nil set is
    /// the union of lines serving the selected stops, so transfers can still
    /// choose more than one line.
    private var stationLineIDs: Set<String>? {
        guard let catalog else { return nil }
        var resolvedStation = false
        var lineIDs: Set<String> = []
        for code in Set(stationCodes) where !code.isEmpty {
            let key = StationKey(regionCode: region.code, sourceCode: code)
            guard catalog.station(key) != nil else { continue }
            resolvedStation = true
            lineIDs.formUnion(catalog.memberships(stationKey: key).map(\.lineID))
        }
        return resolvedStation ? lineIDs : nil
    }

    private var candidateLines: [CatalogLine] {
        guard let stationLineIDs else { return regionLines }
        return regionLines.filter { stationLineIDs.contains($0.id) }
    }

    private var matches: [CatalogLine] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let prepared = SearchFold.PreparedQuery(needle)
        let operatorCodes = OperatorIdentity.exactCodes(query: needle)
        return candidateLines.filter { line in
            if let operatorCodes {
                return line.operatorIDs.contains {
                    !Set(OperatorIdentity.codes(forJoined: operatorNameByID[$0] ?? "")).isDisjoint(with: operatorCodes)
                }
            }
            return needle.isEmpty || prepared.matches(fields: [line.name] + line.aliases
                + line.operatorIDs.flatMap { OperatorIdentity.searchNames(for: operatorNameByID[$0] ?? "") })
        }
    }

    private var selectedLines: [CatalogLine] {
        regionLines.filter { selectedIDs.contains($0.id) }
    }

    private var conflictingSelectedLines: [CatalogLine] {
        guard let stationLineIDs else { return [] }
        return selectedLines.filter { !stationLineIDs.contains($0.id) }
    }

    private var matchGroups: [OperatorLineGroup] {
        let grouped = Dictionary(grouping: matches) { line in
            line.operatorIDs.first ?? ""
        }
        return grouped.map { operatorID, lines in
            OperatorLineGroup(
                id: operatorID,
                name: operatorNameByID[operatorID]
                    ?? localization.countryText("field.company", fallback: "Operator"),
                lines: lines)
        }
        .sorted { lhs, rhs in
            if lhs.name != rhs.name { return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending }
            return lhs.id < rhs.id
        }
    }

    var body: some View {
        Group {
            if let loadError {
                Text(loadError).foregroundStyle(.secondary).padding()
            } else if catalog == nil {
                ProgressView()
            } else {
                List {
                    if !selectedLines.isEmpty || !unresolvedNames.isEmpty {
                        Section(localization.editorText("ios.editor.selectedLines")) {
                            ForEach(selectedLines, id: \.id) { line in
                                lineButton(line, tagged: false)
                            }
                            ForEach(unresolvedNames, id: \.self) { name in
                                Text(name)
                                    .foregroundStyle(.secondary)
                                    .frame(minHeight: 44, alignment: .leading)
                            }
                        }
                    }
                    if !conflictingSelectedLines.isEmpty {
                        Section {
                            ForEach(conflictingSelectedLines, id: \.id) { line in
                                HStack(spacing: 12) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(line.name)
                                        if let operatorName = line.operatorIDs
                                            .compactMap({ operatorNameByID[$0] }).first
                                        {
                                            Text(operatorName).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        } header: {
                            Text("\(localization.editorText("ios.editor.station")) ↔ \(localization.editorText("ios.editor.lineNames"))")
                        }
                    }
                    ForEach(matchGroups) { group in
                        Section(group.name) {
                            ForEach(group.lines, id: \.id) { line in
                                lineButton(line, tagged: true)
                            }
                        }
                    }
                    if matches.isEmpty {
                        Section {
                            Text(localization.editorText("ios.editor.noLineMatches"))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(localization.editorText("ios.editor.searchLines"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, isPresented: $isSearching, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text(localization.editorText("ios.editor.lineSearchPrompt")))
        .task {
            let region = region
            do {
                let loaded = try await Task.detached(priority: .userInitiated) {
                    try loadCatalog(for: region)
                }.value
                guard !Task.isCancelled else { return }
                if !didInitialize {
                    let matched = CatalogLinePreferenceMapping.matching(
                        lineNames: lineNames, operatorNames: operatorNames,
                        regionCode: region.code, catalog: loaded)
                    let knownSelectedIDs = selectedLineIDs.filter {
                        loaded.line(id: $0, regionCode: region.code) != nil
                    }
                    selectedIDs = knownSelectedIDs.isEmpty ? Set(matched.lineIDs) : knownSelectedIDs
                    unresolvedNames = matched.unresolvedNames
                    didInitialize = true
                }
                operatorNameByID = Dictionary(
                    uniqueKeysWithValues: loaded.operators(in: region.code).map { ($0.id, $0.name) })
                regionLines = loaded.lines(in: region.code)
                catalog = loaded
            } catch {
                loadError = error.localizedDescription
            }
        }
        .onDisappear { commit() }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(localization.text("ios.done", fallback: "Done")) {
                    commit()
                    dismiss()
                }
                .accessibilityIdentifier("rideEditorLinesDone")
            }
        }
    }

    @ViewBuilder
    private func lineButton(_ line: CatalogLine, tagged: Bool) -> some View {
        let row = lineRow(line)
        if tagged {
            row.accessibilityIdentifier("rideEditorLine-\(line.id)")
        } else {
            row
        }
    }

    private func lineRow(_ line: CatalogLine) -> some View {
        let lineID = line.id
        let selected = selectedIDs.contains(lineID)
        let operatorName = line.operatorIDs.compactMap { operatorNameByID[$0] }.first { !$0.isEmpty }
        return Button {
            if selected { selectedIDs.remove(lineID) } else { selectedIDs.insert(lineID) }
            userEdited = true
            isSearching = false
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(line.name)
                    if let operatorName {
                        Text(operatorName).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if selected { Image(systemName: "checkmark") }
            }
            .frame(minHeight: 44)
        }
        .accessibilityValue(selected ? localization.editorText("ios.editor.lineSelected") : "")
    }

    private func commit() {
        // Opening the list and leaving it must not drop a stored name that
        // matched more than one line. Those names stay unresolved until the
        // reader actually toggles a row.
        guard !didCommit, didInitialize, userEdited, let catalog else { return }
        didCommit = true
        let preference = CatalogLinePreferenceMapping.preferences(
            lineIDs: Array(selectedIDs), regionCode: region.code, catalog: catalog)
        var lineNames = preference.lineNames
        for name in unresolvedNames where !lineNames.contains(name) {
            lineNames.append(name)
        }
        onCommit(selectedIDs.sorted(), lineNames, preference.operatorNames)
    }
}

/// A compact source label shared by route previews and both editor modes.
struct AutoFilledStationLabel: View {
    @Environment(AppLocalization.self) private var localization

    var body: some View {
        Label(localization.editorText("ios.editor.generatedStation"), systemImage: "wand.and.stars")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
            .fixedSize(horizontal: false, vertical: true)
    }
}
