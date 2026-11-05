import RailApplication
import RailCore
import RailPresentation
import SwiftUI

/// The one journey editor. A new trip is an empty draft; an existing trip
/// opens with its saved route drawn on the map. Changing an endpoint or a
/// via replans on the map, a route that needs review is fixed by choosing
/// between the paused span's tracks on the same map, and every other field
/// of the record is kept unless the reader edits it. The host supplies the
/// panel chrome and persists the result of `onSave`.
struct JourneyEditorView: View {
    @Environment(AppLocalization.self) private var localization
    @Environment(ItineraryStore.self) private var itineraries: ItineraryStore?
    @Environment(RiddenRouteStore.self) private var riddenRoutes: RiddenRouteStore?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let train: Train
    let isNew: Bool
    let title: String
    /// Open straight into route repair, as the journey card's Repair route does.
    let startsWithRouteRepair: Bool
    /// Saved journeys, for group and suggestion catalogs.
    let suggestionTrains: [Train]
    let onCancel: () -> Void
    let onDraftMap: (DraftMapSnapshot) -> Void
    let onSave: (Train) -> Void

    private static let serviceTypes = JourneyDraftWork.serviceTypeIDs

    private struct HeaderSnapshot {
        var trainType: String
        var departure: Date
        var arrival: Date
        var previousDeparture: Date
        var departureTouched: Bool
        var arrivalTouched: Bool
    }

    /// A route change that would drop recorded stops, waiting for the reader.
    private struct RemovalRequest: Identifiable {
        enum Action { case save, repair(Int) }
        let id = UUID()
        var action: Action
        var stations: [String]
    }
    private static let recordRouteID = "record"
    private static let repairRoutePrefix = "repair-"
    /// Alternatives drawn on the map. Each is an overlay with its own track;
    /// more than this is clutter on a phone and memory for nothing.
    nonisolated static let maximumDrawnRoutes = 4

    private enum StationField: String, Identifiable {
        case origin
        case via
        case destination
        var id: String { rawValue }
    }

    /// A reader-chosen station the route must pass. Narrows the planner's
    /// candidates; saved only as an ordinary visit of the chosen route.
    private struct ViaStop: Identifiable, Equatable {
        let id = UUID()
        var station: CatalogStation
        var stationID: String?
    }

    @State private var region: Region
    @State private var catalog: EditorCatalog?
    @State private var package: CompactPackage?
    @State private var loadFailed = false
    @State private var origin: CatalogStation?
    @State private var destination: CatalogStation?
    @State private var originLine: CatalogLine?
    @State private var destinationLine: CatalogLine?
    @State private var originStationID: String?
    @State private var destinationStationID: String?
    @State private var trainType: String
    @State private var timetableTrain: Train?
    @State private var timetableRideSpan: ClosedRange<Int>?
    @State private var applyingTimetable = false
    @State private var timetableTrainTypeChanged = false
    @State private var limitedExpressName = ""
    @State private var showsTimetablePicker = false
    @State private var timetableFailed = false
    @State private var trainNumber = ""
    @State private var companyName = ""
    @State private var departure: Date
    @State private var arrival: Date
    @State private var previousDeparture: Date
    @State private var draftMapRevision = 0
    /// Date prefill remains live until the reader makes an explicit choice.
    @State private var riddenOverride: Bool?
    @State private var picking: StationField?
    @State private var allowUnverifiedConnections = false
    @State private var outcome: TripRoutePlanner.Outcome?
    /// `routeIdentity` that `outcome` was planned for. A newer identity makes the outcome stale.
    @State private var plannedIdentity = ""
    @State private var physicallyResolvedCorridorIDs: Set<String> = []
    /// Why the corridors on screen were not marked proven. Saving them stays allowed.
    @State private var routeProofFailure: String?
    /// Bumped when the region changes. A search or plan started earlier must not write this draft.
    @State private var draftGeneration = 0
    /// Bumped when this region's registry settles so the timetable query resolves again.
    @State private var registryEpoch = 0
    @State private var searching = false
    @State private var selectedCorridorID: String?
    @State private var corridorsRemovedByDate = false
    /// The corridor the reader last picked, kept across replans that are
    /// cancelled before they finish and so never restore the live selection.
    @State private var preferredCorridorID: String?
    @State private var autofillFailed = false
    @State private var saveIssues: [RideDraftIssue] = []
    /// Catalog operator id → display name. Rebuilt when the catalog or stations change.
    @State private var operatorNameByID: [String: String] = [:]
    /// Catalog display name → `CompactPackage.Line.operator`, the string the planner compares.
    @State private var packageOperatorByDisplayName: [String: String] = [:]
    @State private var companyOptions: [String] = []
    @State private var lineLabelByID: [String: String] = [:]
    @State private var vias: [ViaStop] = []
    /// Station the reader tapped on the map, waiting for From / Via / To.
    @State private var tappedStation: CatalogStation?
    /// Track geometry for each planned corridor id, built off the main actor.
    @State private var corridorGeometry: [String: [TripRouteGeometry.Piece]] = [:]
    @State private var lineColorByID: [String: String] = [:]
    @State private var mapFitRevision = 0
    @State private var mapZoomedIn = false
    @State private var mapStations: [CatalogStation] = []
    /// Routes on the map. Kept through a replan so the line does not blink out.
    @State private var drawnRoutes: [TripMapContent.Route] = []
    @State private var routeFitIdentity = ""
    /// The record being edited. Route planning, a timetable and repair write
    /// into it only through `commit`, `applyCorridor` and the repair controller.
    @State private var draft: Train
    @State private var seed: EditorSeed
    /// `stationIdentity` of the saved route once its stations are found in
    /// the catalog. Nil until then. While the identity still matches, the
    /// saved stops are the route and nothing is replanned.
    @State private var seededStationIdentity: String?
    /// Track of the saved route, drawn while it is unchanged.
    @State private var recordGeometry: [TripRouteGeometry.Piece] = []
    @State private var repair = RouteRepairController()
    /// Interval track decoded once per line for this editor session, over the
    /// shared resident package. Planning, the saved route and repair reuse it.
    @State private var geometryCache: TripRouteGeometry.Cache?
    @State private var repairStarted = false
    @State private var showsDiscardConfirmation = false
    @State private var showsFillDetails = false
    @State private var detailIssues: [RideDraftIssue] = []
    @State private var showsCompletion = false
    /// The reader set this clock in the picker. A shift that follows the
    /// departure, or a timetable, does not count.
    @State private var departureTouched = false
    @State private var arrivalTouched = false
    /// Header values before a timetable was applied, restored by Remove.
    @State private var headerBeforeTimetable: HeaderSnapshot?
    @State private var removal: RemovalRequest?
    /// Passenger direction per line stretch of the route on screen. Read
    /// from the route, never typed.
    @State private var directionLegs: [TravelDirection.Leg] = []
    @State private var showsBoundForEntry = false
    @State private var showsVehiclePicker = false
    /// Platforms typed before the route has stops of its own (a new trip);
    /// written onto the ride's first and last stop when it is saved.
    @State private var pendingDeparturePlatform: Int?
    @State private var pendingArrivalPlatform: Int?
    @State private var boundForDraft = ""
    @State private var detailsExpanded: Bool
    /// The draft's stops are the route: a saved journey, or a completion the
    /// reader applied. False only for a new trip still choosing its route.
    @State private var hasRecordRoute: Bool

    init(
        train: Train,
        isNew: Bool,
        title: String,
        startsWithRouteRepair: Bool = false,
        suggestionTrains: [Train] = [],
        onCancel: @escaping () -> Void,
        onDraftMap: @escaping (DraftMapSnapshot) -> Void = { _ in },
        onSave: @escaping (Train) -> Void
    ) {
        self.train = train
        self.isNew = isNew
        self.title = title
        self.startsWithRouteRepair = startsWithRouteRepair
        self.suggestionTrains = suggestionTrains
        self.onCancel = onCancel
        self.onDraftMap = onDraftMap
        self.onSave = onSave
        _draft = State(initialValue: train)
        _hasRecordRoute = State(initialValue: !isNew)
        // Collapsed until asked for: its lookups (the official English name
        // reads the timetable database) are work a route edit does not need.
        _detailsExpanded = State(initialValue: false)
        _region = State(initialValue: Region(rawValue: train.region ?? "") ?? Region.resolved(train))
        let seeded = EditorSeed(train: train, isNew: isNew)
        _seed = State(initialValue: seeded)
        _trainType = State(initialValue: seeded.trainType)
        _trainNumber = State(initialValue: seeded.number)
        _companyName = State(initialValue: seeded.company)
        _departure = State(initialValue: seeded.departure)
        _arrival = State(initialValue: seeded.arrival)
        _previousDeparture = State(initialValue: seeded.departure)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                mapPanel
                form
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .confirmationDialog(
            localization.text("ios.editor.discardTitle"),
            isPresented: $showsDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button(localization.text("ios.editor.discardChanges"), role: .destructive) { onCancel() }
            Button(localization.text("ios.editor.keepEditing"), role: .cancel) {}
        } message: {
            Text(localization.text("ios.editor.discardDetail"))
        }
        .interactiveDismissDisabled(isDirty)
        .onChange(of: draft, initial: true) { _, value in
            detailIssues = RideDraftValidation.issues(
                for: value, originalID: train.id, existingIDs: itineraries?.trainIDs ?? [])
            saveIssues = []
        }
        .onChange(of: [draft.stops.first?.n02StationCode, draft.stops.last?.n02StationCode]) { _, _ in
            // A stop edited to another station moves the saved route's end.
            if showsRecordRoute, let catalog { seedStations(from: catalog) }
        }
        .task(id: RecordGeometryKey(
            sections: showsRecordRoute ? draft.routeSections ?? [] : [], loaded: package != nil)) {
            await loadRecordGeometry()
        }
        // Waits for the package, the seeded stations and the route status:
        // a status still resolving has no gaps yet, and a later one retries.
        .task(id: [package != nil, seededStationIdentity != nil, repairGaps != nil]) {
            guard startsWithRouteRepair, !repairStarted, package != nil,
                  seededStationIdentity != nil, repairGaps != nil else { return }
            startRepair()
        }
        .confirmationDialog(
            localization.text("ios.routeGuide.removalTitle"),
            isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } }),
            titleVisibility: .visible,
            presenting: removal
        ) { request in
            Button(localization.text("ios.routeGuide.removeAndApply"), role: .destructive) {
                removal = nil
                switch request.action {
                case .save: commit(confirmedRemoval: true)
                case .repair(let index): chooseRepair(index, confirmedRemoval: true)
                }
            }
            .accessibilityIdentifier("newTripRemoveStops")
            Button(localization.text("ios.cancel", fallback: "Cancel"), role: .cancel) { removal = nil }
        } message: { request in
            Text(localization.text("ios.routeGuide.removalDetail",
                                   params: ["stations": .string(request.stations.joined(separator: "、"))]))
        }
        .onChange(of: repair.pause) { _, pause in
            refreshDrawnRoutes()
            if pause != nil { mapFitRevision += 1 }
        }
        .onChange(of: showsRecordRoute) { _, _ in refreshDrawnRoutes() }
        .task(id: directionKey) { await loadDirections() }
        // Closing the editor stops a running repair search at once.
        .onDisappear { repair.cancel() }
        .sheet(isPresented: $showsFillDetails) {
            fillDetailsSheet
        }
        .sheet(isPresented: $showsVehiclePicker) {
            VehiclePickerView(
                vehicleType: $draft.vehicleType,
                suggestions: vehicleSuggestions)
        }
        .sheet(item: $picking) { field in
            if let catalog {
                NavigationStack {
                    StationPickerView(
                        regionCode: region.code,
                        sourceCatalog: catalog,
                        companyFilter: companyName.isEmpty ? nil : companyName,
                        onSelectWithLine: { [generation = draftGeneration] station, line, stationID in
                            guard generation == draftGeneration else {
                                picking = nil
                                return
                            }
                            clearTimetable()
                            switch field {
                            case .origin:
                                origin = station
                                originLine = line
                                originStationID = stationID
                            case .via:
                                vias.append(ViaStop(station: station, stationID: stationID))
                            case .destination:
                                destination = station
                                destinationLine = line
                                destinationStationID = stationID
                            }
                            picking = nil
                        })
                }
            }
        }
        .onChange(of: departure) { _, newValue in
            let shiftedArrival = arrival.addingTimeInterval(
                newValue.timeIntervalSince(previousDeparture))
            arrival = max(shiftedArrival, newValue)
            previousDeparture = newValue
            saveIssues = []
        }
        .onChange(of: dayString(departure), initial: true) { _, day in
            draftMapRevision += 1
            onDraftMap(DraftMapSnapshot(
                revision: draftMapRevision, pins: [], networkRideDate: day))
        }
        .onChange(of: arrival) { _, _ in
            saveIssues = []
        }
        .onChange(of: trainType) { _, _ in
            saveIssues = []
        }
        .onChange(of: trainNumber) { _, _ in
            saveIssues = []
        }
        .onChange(of: companyName) { _, _ in
            saveIssues = []
        }
        .task(id: region.code) {
            await SolverRegistryInput.awaitReady(region: region.code)
            registryEpoch += 1
        }
        .onChange(of: region) { _, _ in
            draftGeneration += 1
            picking = nil
            allowUnverifiedConnections = false
            clearTimetable()
            limitedExpressName = ""
            origin = nil
            destination = nil
            originLine = nil
            destinationLine = nil
            originStationID = nil
            destinationStationID = nil
            vias = []
            tappedStation = nil
            corridorGeometry = [:]
            drawnRoutes = []
            routeFitIdentity = ""
            lineColorByID = [:]
            mapStations = []
            if hasRecordRoute {
                // Relabelling a saved journey: find its stations again in the
                // new region's catalog, and keep the operator it already names.
                seededStationIdentity = nil
            } else {
                companyName = ""
            }
            catalog = nil
            package = nil
            geometryCache = nil
            outcome = nil
            plannedIdentity = ""
            physicallyResolvedCorridorIDs.removeAll()
            routeProofFailure = nil
            selectedCorridorID = nil
            corridorsRemovedByDate = false
            preferredCorridorID = nil
            autofillFailed = false
            loadFailed = false
            saveIssues = []
            refreshCompanyCache()
        }
        .onChange(of: origin) { _, _ in
            allowUnverifiedConnections = false
            refreshCompanyCache()
        }
        .onChange(of: destination) { _, _ in
            allowUnverifiedConnections = false
            refreshCompanyCache()
        }
        .onChange(of: vias) { _, _ in
            allowUnverifiedConnections = false
        }
        .onChange(of: endpointIdentity) { _, _ in
            // Frame the trip as soon as an endpoint moves, before the route arrives.
            mapFitRevision += 1
        }
        .onChange(of: companyOptions) { _, options in
            if !companyName.isEmpty, !options.contains(companyName), companyName != seed.company {
                companyName = ""
            }
        }
        .onChange(of: selectedCorridorID) { _, _ in
            autofillFailed = false
            saveIssues = []
            refreshDrawnRoutes()
        }
        .onChange(of: outcome) { _, _ in refreshDrawnRoutes() }
        .onChange(of: timetableTrain != nil) { _, _ in refreshDrawnRoutes() }
        .task(id: region) { await loadRegion() }
        .task(id: routeIdentity) { await planRoute() }
    }

    private var form: some View {
        Form {
            if loadFailed {
                Text(text(
                    "loadFailed",
                    fallback: "The rail data for this region could not be loaded."))
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if Region.enabledOrdered.count > 1 {
                regionSection
            }
            stationsSection
            if timetableTrain != nil || hasRecordRoute || (origin != nil && destination != nil) {
                routeSection
            }
            timeSection
            serviceSection
            Section {
                Toggle(text("ridden", fallback: "I have ridden this journey"), isOn: Binding(
                    get: { isRidden }, set: { riddenOverride = $0 }))
                    .accessibilityIdentifier("newTripRidden")
            }
            tripDetailsSection
            JourneyEditorDetails(
                draft: $draft, region: region, showsStops: showsRecordRoute,
                suggestionTrains: suggestionTrains, issues: detailIssues,
                expanded: $detailsExpanded)
            if !saveIssues.isEmpty {
                Section {
                    ForEach(saveIssues) { issue in
                        Text(localization.text(for: issue))
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .accessibilityIdentifier("newTripForm")
        .scrollDismissesKeyboard(.interactively)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button(text("cancel", fallback: "Cancel")) {
                if isDirty { showsDiscardConfirmation = true } else { onCancel() }
            }
            .accessibilityIdentifier("newTripCancel")
            Spacer(minLength: 8)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            Button(text("save", fallback: "Save"), action: commit)
                .fontWeight(.semibold)
                .disabled(!canSave)
                // ⌘S is disabled by the same condition as the button.
                .keyboardShortcut("s", modifiers: .command)
                .accessibilityIdentifier("newTripSave")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// Leaving asks only when Save would write something.
    private var isDirty: Bool {
        if draft != train || timetableTrain != nil || riddenOverride != nil
            || pendingDeparturePlatform != nil || pendingArrivalPlatform != nil { return true }
        if trainType != seed.trainType || trainNumber != seed.number || companyName != seed.company
            || departure != seed.departure || arrival != seed.arrival { return true }
        if hasRecordRoute { return routeEdited }
        return origin != nil || destination != nil || !vias.isEmpty
    }

    // MARK: - saved route and repair

    private struct RecordGeometryKey: Equatable {
        var sections: [RouteSection]
        var loaded: Bool
    }

    private func loadRecordGeometry() async {
        guard showsRecordRoute, let geometryCache else {
            if !recordGeometry.isEmpty {
                recordGeometry = []
                refreshDrawnRoutes()
            }
            return
        }
        let sections = draft.routeSections ?? []
        let pieces = await Task.detached(priority: .userInitiated) {
            TripRouteGeometry.pieces(for: sections, cache: geometryCache)
        }.value
        guard !Task.isCancelled else { return }
        let firstDraw = recordGeometry.isEmpty
        recordGeometry = pieces
        refreshDrawnRoutes()
        if firstDraw, !pieces.isEmpty { mapFitRevision += 1 }
    }

    /// Gaps the route status reported for the saved journey, while the draft
    /// still visits the same stations. Nil when nothing needs repair.
    private var repairGaps: [RouteRepair.Gap]? {
        guard !isNew, showsRecordRoute,
              draft.stops.count == train.stops.count,
              zip(draft.stops, train.stops).allSatisfy({
                  $0.n02StationCode == $1.n02StationCode && $0.name == $1.name
              }),
              let status = riddenRoutes?.status(
                  forTrainID: train.id,
                  pendingConfirmationIDs: itineraries?.pendingConfirmationIDs ?? []),
              case .needsReview(_, _, let gaps) = status, !gaps.isEmpty else { return nil }
        return gaps.map(RouteRepair.Gap.init)
    }

    private func repairText(_ key: String, _ params: [String: Localization.Param]) -> String {
        if key == "ios.journey.repairInterrupted" {
            return localization.journeyText(key, fallback: "Ride changed while repairing; run Repair again")
        }
        return localization.text(key, params: params)
    }

    private func applyRepair(_ expected: Train, _ result: Train) -> Bool {
        guard draft == expected else { return false }
        draft = result
        return true
    }

    private func startRepair() {
        guard let package, let geometryCache, let gaps = repairGaps else { return }
        repairStarted = true
        repair.start(train: draft, gaps: gaps, package: package, geometry: geometryCache, text: repairText, apply: applyRepair)
    }

    private func chooseRepair(_ index: Int, confirmedRemoval: Bool = false) {
        guard let package, let geometryCache, let pause = repair.pause, pause.choices.indices.contains(index) else { return }
        let choice = pause.choices[index]
        if !confirmedRemoval, let plan = repair.plan(for: choice), plan.requiresConfirmation {
            removal = RemovalRequest(action: .repair(index), stations: plan.conflictingStops.map(\.name))
            return
        }
        repair.choose(choice, package: package, geometry: geometryCache, text: repairText, apply: applyRepair)
    }

    @ViewBuilder private var recordRouteRows: some View {
        let lines = (draft.routeSections ?? []).compactMap { $0.lineNames?.first }
        VStack(alignment: .leading, spacing: 4) {
            Text(lines.isEmpty ? text("savedRoute", fallback: "Saved route") : uniqued(lines).joined(separator: " · "))
                .font(.body.weight(.semibold))
            Text(text("stationCount", fallback: "{count} stations",
                      ["count": .string(String(draft.stops.count))]))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if draft.routeConfirmation == .pending {
                Text(localization.text("ios.route.pendingConfirmation", fallback: "Route pending confirmation"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("newTripSavedRoute")
        if let pause = repair.pause {
            Text(text("repairChoose", fallback: "Choose the route between {from} and {to}",
                      ["from": .string(visitName(pause.fromVisitID)), "to": .string(visitName(pause.toVisitID))]))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(pause.choices.enumerated()), id: \.offset) { index, choice in
                Button { chooseRepair(index) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(uniqued(choice.lineNames).joined(separator: " · "))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(text("stationCount", fallback: "{count} stations",
                                  ["count": .string(String(choice.stations.count))]))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .accessibilityIdentifier("newTripRepairChoice-\(index)")
            }
            Button(text("repairSkip", fallback: "Leave this part as it is")) {
                guard let package, let geometryCache else { return }
                repair.skip(package: package, geometry: geometryCache, text: repairText, apply: applyRepair)
            }
            .accessibilityIdentifier("newTripRepairSkip")
        } else if repair.isRunning {
            ProgressView()
                .frame(maxWidth: .infinity)
                .accessibilityLabel(text("repairing", fallback: "Repairing route"))
        } else if repairGaps != nil {
            Button {
                startRepair()
            } label: {
                Label(localization.text("ios.route.repairRoute", fallback: "Repair route"),
                      systemImage: "wrench.and.screwdriver")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .disabled(package == nil)
            .accessibilityIdentifier("newTripRepairRoute")
        }
        if let summary = repair.summary {
            Text(summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("newTripRepairSummary")
        }
    }

    private func visitName(_ id: UUID) -> String {
        guard let stop = draft.stops.first(where: { $0.routeEditing?.visitID == id }) else { return "" }
        return localization.stationName(stop.name, code: stop.n02StationCode, region: region)
    }

    private func uniqued(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    // MARK: - map

    private var mapPanel: some View {
        TripMapView(
            regionCode: region.code,
            stations: mapStations,
            content: mapContent,
            reduceMotion: reduceMotion,
            onStation: { station in
                withAnimation(RailMotion.animation(RailMotion.spring, reduceMotion: reduceMotion)) {
                    tappedStation = station
                }
            },
            onRoute: { id in
                if id.hasPrefix(Self.repairRoutePrefix) {
                    if let index = Int(id.dropFirst(Self.repairRoutePrefix.count)) { chooseRepair(index) }
                    return
                }
                guard id != Self.recordRouteID, selectedCorridor?.id != id else { return }
                selectedCorridorID = id
                preferredCorridorID = id
            },
            onBackground: {
                guard tappedStation != nil else { return }
                withAnimation(RailMotion.animation(RailMotion.enter, reduceMotion: reduceMotion)) {
                    tappedStation = nil
                }
            },
            onZoomChange: { mapZoomedIn = $0 })
            .overlay(alignment: .top) { mapHint }
            .overlay(alignment: .bottom) {
                if let tappedStation {
                    stationActionCard(tappedStation)
                        .transition(RailMotion.anchoredTransition(reduceMotion: reduceMotion, anchor: .bottom))
                }
            }
            .containerRelativeFrame(.vertical) { height, _ in
                min(max(height * 0.42, 240), 460)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
            .sensoryFeedback(.selection, trigger: selectedCorridorID) { old, new in
                old != nil && new != nil
            }
    }

    /// One short line telling the reader what the map will do next.
    @ViewBuilder private var mapHint: some View {
        let hint: String? = {
            if tappedStation != nil { return nil }
            if catalog == nil { return nil }
            if !mapZoomedIn, origin == nil || destination == nil {
                return text("mapZoomHint", fallback: "Zoom in to tap stations, or search below")
            }
            if origin == nil { return text("mapOriginHint", fallback: "Tap a station to start from") }
            if destination == nil { return text("mapDestinationHint", fallback: "Tap where the trip ends") }
            if timetableTrain != nil { return nil }
            if searching { return text("searching", fallback: "Searching routes") }
            if drawnRoutes.count > 1 {
                return text("mapAlternativesHint",
                            fallback: "{count} routes · tap a grey line, or add a stop",
                            ["count": .string(String(drawnRoutes.count))])
            }
            return nil
        }()
        if let hint {
            Text(hint)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.regularMaterial, in: Capsule())
                .padding(.top, 10)
                .padding(.horizontal, 12)
                .allowsHitTesting(false)
                .accessibilityIdentifier("newTripMapHint")
                .id(hint)
                .transition(.opacity)
                .animation(RailMotion.crossfade, value: hint)
        }
    }

    private func stationActionCard(_ station: CatalogStation) -> some View {
        let role = mapRole(of: station)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(stationTitle(station))
                        .font(.headline)
                        .lineLimit(2)
                    if let subtitle = stationSubtitle(station, line: nil) {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Button {
                    withAnimation(RailMotion.animation(RailMotion.enter, reduceMotion: reduceMotion)) {
                        tappedStation = nil
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(text("close", fallback: "Close"))
                .accessibilityIdentifier("newTripMapStationClose")
            }
            HStack(spacing: 8) {
                if let role {
                    actionButton(text("mapRemove", fallback: "Remove"), systemImage: "minus.circle",
                                 identifier: "newTripMapRemove", prominent: false) {
                        removeFromTrip(station, role: role)
                    }
                } else {
                    actionButton(text("from", fallback: "From"), systemImage: "circle.fill",
                                 identifier: "newTripMapSetOrigin", prominent: origin == nil) {
                        assign(station, to: .origin)
                    }
                    if origin != nil, destination != nil, timetableTrain == nil {
                        actionButton(text("mapVia", fallback: "Via"), systemImage: "plus",
                                     identifier: "newTripMapAddVia", prominent: false) {
                            assign(station, to: .via)
                        }
                    }
                    actionButton(text("to", fallback: "To"), systemImage: "flag.fill",
                                 identifier: "newTripMapSetDestination",
                                 prominent: origin != nil && destination == nil) {
                        assign(station, to: .destination)
                    }
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(10)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("newTripMapStationCard")
    }

    private func actionButton(
        _ title: String, systemImage: String, identifier: String, prominent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Group {
            if prominent {
                Button(action: action) {
                    Label(title, systemImage: systemImage).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button(action: action) {
                    Label(title, systemImage: systemImage).frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .controlSize(.regular)
        .labelStyle(.titleAndIcon)
        .accessibilityIdentifier(identifier)
    }

    private enum MapRole: Equatable { case origin, via(UUID), destination }

    private func mapRole(of station: CatalogStation) -> MapRole? {
        if origin?.key == station.key { return .origin }
        if destination?.key == station.key { return .destination }
        if let via = vias.first(where: { $0.station.key == station.key }) { return .via(via.id) }
        return nil
    }

    private func assign(_ station: CatalogStation, to field: StationField) {
        clearTimetable()
        switch field {
        case .origin:
            origin = station
            originLine = nil
            originStationID = nil
        case .via:
            vias.append(ViaStop(station: station, stationID: nil))
        case .destination:
            destination = station
            destinationLine = nil
            destinationStationID = nil
        }
        withAnimation(RailMotion.animation(RailMotion.enter, reduceMotion: reduceMotion)) {
            tappedStation = nil
        }
    }

    private func removeFromTrip(_ station: CatalogStation, role: MapRole) {
        clearTimetable()
        switch role {
        case .origin:
            origin = nil
            originLine = nil
            originStationID = nil
        case .destination:
            destination = nil
            destinationLine = nil
            destinationStationID = nil
        case .via(let id):
            vias.removeAll { $0.id == id }
        }
        withAnimation(RailMotion.animation(RailMotion.enter, reduceMotion: reduceMotion)) {
            tappedStation = nil
        }
    }

    private func viaRow(_ via: ViaStop, index: Int) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(text("viaTitle", fallback: "Via"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(stationTitle(via.station))
                if let subtitle = stationSubtitle(via.station, line: nil) {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            Button {
                clearTimetable()
                vias.removeAll { $0.id == via.id }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(text("removeVia", fallback: "Remove stop"))
            .accessibilityIdentifier("newTripRemoveVia-\(index)")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("newTripVia-\(index)")
    }

    /// Endpoints and vias only; a change reframes the camera.
    private var endpointIdentity: String {
        ([origin, destination].map { $0?.key.sourceCode ?? "" }
            + vias.map(\.station.key.sourceCode)).joined(separator: ",")
    }

    private var mapContent: TripMapContent {
        var marks: [TripMapContent.Mark] = []
        func mark(_ station: CatalogStation, role: TripMapContent.Role, id: String) {
            let coordinate = AppleMapDatum.display(
                Coordinate(lon: station.longitude, lat: station.latitude), country: region.code)
            marks.append(.init(id: id, role: role, station: station, coordinate: coordinate.clLocation))
        }
        if let origin { mark(origin, role: .origin, id: "origin") }
        for (index, via) in vias.enumerated() {
            mark(via.station, role: .via(index), id: "via-\(via.id.uuidString)")
        }
        if let destination { mark(destination, role: .destination, id: "destination") }
        return TripMapContent(
            routes: drawnRoutes, marks: marks, arrows: directionArrows, fitRevision: mapFitRevision)
    }

    private func mapRoute(id: String, pieces: [TripRouteGeometry.Piece], selected: Bool) -> TripMapContent.Route {
        TripMapContent.Route(
            id: id,
            pieces: pieces.map { piece in
                TripMapContent.Piece(
                    coordinates: AppleMapDatum.display(piece.coordinates, country: region.code)
                        .map(\.clLocation),
                    colorHex: piece.lineID.flatMap { lineColorByID[$0] },
                    isConnector: piece.isConnector)
            },
            isSelected: selected)
    }

    private func refreshDrawnRoutes() {
        if showsRecordRoute {
            var routes: [TripMapContent.Route] = []
            if !recordGeometry.isEmpty {
                routes.append(mapRoute(id: Self.recordRouteID, pieces: recordGeometry, selected: true))
            }
            // A paused repair offers its span's tracks as the alternatives.
            for (index, pieces) in (repair.pause?.geometry ?? []).prefix(Self.maximumDrawnRoutes).enumerated()
            where !pieces.isEmpty {
                routes.append(mapRoute(id: Self.repairRoutePrefix + String(index), pieces: pieces, selected: false))
            }
            drawnRoutes = routes
            return
        }
        guard origin != nil, destination != nil, timetableTrain == nil else {
            drawnRoutes = []
            return
        }
        // Mid-replan the previous routes stay until the new outcome lands.
        guard let outcome else { return }
        guard case .corridors(let corridors) = outcome else {
            drawnRoutes = []
            return
        }
        let drawn = corridors.prefix(Self.maximumDrawnRoutes)
            + corridors.dropFirst(Self.maximumDrawnRoutes).filter { $0.id == selectedCorridorID }
        drawnRoutes = drawn.compactMap { corridor in
            guard let pieces = corridorGeometry[corridor.id], !pieces.isEmpty else { return nil }
            return mapRoute(id: corridor.id, pieces: pieces, selected: corridor.id == selectedCorridorID)
        }
    }

    private var regionSection: some View {
        Section {
            Picker(text("region", fallback: "Region"), selection: $region) {
                ForEach(Region.enabledOrdered) { region in
                    Text(localization.text(region.localizationKey, fallback: region.fallbackName))
                        .tag(region)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var stationsSection: some View {
        Section {
            if catalog == nil, !loadFailed {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
            stationButton(
                title: text("from", fallback: "From"),
                station: origin,
                line: originLine,
                identifier: "newTripOrigin") { picking = .origin }
            Button(action: swapStations) {
                Image(systemName: "arrow.up.arrow.down")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .accessibilityIdentifier("newTripSwap")
            .accessibilityLabel(text("swap", fallback: "Swap stations"))
            .disabled(origin == nil && destination == nil)
            ForEach(Array(vias.enumerated()), id: \.element.id) { index, via in
                viaRow(via, index: index)
            }
            if origin != nil, destination != nil, timetableTrain == nil {
                Button {
                    picking = .via
                } label: {
                    Label(text("addVia", fallback: "Add a stop along the way"), systemImage: "plus.circle")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .disabled(catalog == nil)
                .accessibilityIdentifier("newTripAddVia")
            }
            stationButton(
                title: text("to", fallback: "To"),
                station: destination,
                line: destinationLine,
                identifier: "newTripDestination") { picking = .destination }
        } header: {
            Text(text("stations", fallback: "Stations"))
        }
    }

    private var serviceSection: some View {
        Section {
            Picker(text("trainType", fallback: "Train type"), selection: Binding(
                get: { trainType },
                set: { value in
                    if timetableTrain != nil, value != trainType { timetableTrainTypeChanged = true }
                    trainType = value
                })) {
                ForEach(trainTypeOptions, id: \.self) { type in
                    Text(trainTypeLabel(type)).tag(type)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("newTripTrainType")
            TextField(text("trainNumber", fallback: "Train number or name"), text: $trainNumber)
                .accessibilityIdentifier("newTripNumber")
            Picker(text("company", fallback: "Company"), selection: $companyName) {
                Text(text("anyCompany", fallback: "Any company")).tag("")
                ForEach(shownCompanyOptions, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("newTripCompany")
        } header: {
            Text(text("service", fallback: "Service"))
        }
    }

    /// The standard service types, plus a saved journey's own type so it
    /// is shown and kept rather than replaced by the first standard one.
    private var trainTypeOptions: [String] {
        var options = Self.serviceTypes
        for type in [seed.trainType, trainType] where !options.contains(type) { options.append(type) }
        return options
    }

    private func trainTypeLabel(_ type: String) -> String {
        if Self.serviceTypes.contains(type) { return localization.text("ios.editor.serviceType.\(type)") }
        return type.isEmpty ? text("trainTypeNotSet", fallback: "Not set") : type
    }

    private var shownCompanyOptions: [String] {
        guard !companyName.isEmpty, !companyOptions.contains(companyName) else { return companyOptions }
        return companyOptions + [companyName]
    }

    private var timeSection: some View {
        Section {
            DatePicker(
                text("departure", fallback: "Departure"),
                selection: timetableTimeSelection(isDeparture: true),
                displayedComponents: [.date, .hourAndMinute])
                .accessibilityIdentifier("newTripDeparture")
            DatePicker(
                text("arrival", fallback: "Arrival"),
                selection: timetableTimeSelection(isDeparture: false),
                displayedComponents: [.date, .hourAndMinute])
                .accessibilityIdentifier("newTripArrival")
            if arrival < departure {
                Text(text(
                    "arrivalBeforeDeparture",
                    fallback: "Arrival is before departure."))
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text(text("time", fallback: "Time"))
        }
    }

    /// One entry for every source that can fill in this trip: timetable
    /// matches, the full timetable, the line's service types, and ChatGPT
    /// or pasted text. What was applied stays visible here.
    /// The ride's first and last stop: the saved stops, or values held until
    /// a new route has stops to put them on.
    private var departurePlatform: Binding<Int?> {
        showsRecordRoute && !draft.stops.isEmpty
            ? Binding(get: { draft.stops.first?.platformNumber },
                      set: { if !draft.stops.isEmpty { draft.stops[0].platformNumber = $0 } })
            : $pendingDeparturePlatform
    }

    private var arrivalPlatform: Binding<Int?> {
        showsRecordRoute && draft.stops.count >= 2
            ? Binding(get: { draft.stops.last?.platformNumber },
                      set: { if draft.stops.count >= 2 { draft.stops[draft.stops.count - 1].platformNumber = $0 } })
            : $pendingArrivalPlatform
    }

    private var missingDetails: MissingTripDetails {
        MissingTripDetails(
            train: showsRecordRoute ? draft : { var t = draft; t.stops = []; return t }(),
            departurePlatform: departurePlatform.wrappedValue,
            arrivalPlatform: arrivalPlatform.wrappedValue)
    }

    private func missingText(_ missing: MissingTripDetails) -> String {
        var parts: [String] = []
        if missing.vehicleType { parts.append(localization.text("ios.editor.vehicleType")) }
        if missing.platformCount > 0 {
            parts.append(text("missingPlatforms", fallback: "{count} platforms",
                              ["count": .string(String(missing.platformCount))]))
        }
        return text("needsDetails", fallback: "Still missing: {items}",
                    ["items": .string(parts.joined(separator: " · "))])
    }

    /// Hand entry for what no source filled: vehicle type and the two
    /// platforms that matter most. Other stops' platforms are on their rows.
    @ViewBuilder private var manualEntryRows: some View {
        let missing = missingDetails
        if !missing.isEmpty {
            Label(missingText(missing), systemImage: "square.and.pencil")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("newTripNeedsDetails")
        }
        Button { showsVehiclePicker = true } label: {
            LabeledContent(localization.text("ios.editor.vehicleType")) {
                Text(draft.vehicleType.flatMap { $0.isEmpty ? nil : $0 }
                     ?? text("vehicleAdd", fallback: "Add"))
                    .foregroundStyle(missing.vehicleType ? Color.accentColor : Color.primary)
            }
            .frame(minHeight: 44)
        }
        .accessibilityIdentifier("newTripVehicleType")
        HStack {
            Text(text("platforms", fallback: "Platforms"))
            Spacer()
            Text(text("departureShort", fallback: "Dep.")).font(.caption).foregroundStyle(.secondary)
            PlatformEntryBadge(platform: departurePlatform, identifier: "newTripDeparturePlatform")
            Text(text("arrivalShort", fallback: "Arr.")).font(.caption).foregroundStyle(.secondary)
            PlatformEntryBadge(platform: arrivalPlatform, identifier: "newTripArrivalPlatform")
        }
    }

    /// The applied timetable's own vehicle first, then the reader's history.
    private var vehicleSuggestions: [String] {
        var base = draft
        if let timetableTrain { base.routeSections = timetableTrain.routeSections }
        else if routeEdited, let corridor = selectedCorridor { base.routeSections = corridor.choice.routeSections }
        var values = VehiclePickerView.suggestions(for: base, among: suggestionTrains)
        if let official = timetableTrain?.vehicleType, !official.isEmpty, !values.contains(official) {
            values.insert(official, at: 0)
        }
        return values
    }

    /// Platforms typed before the route existed go onto the saved ride's ends.
    private func applyPendingPlatforms(to result: inout Train, span: ClosedRange<Int>? = nil) {
        guard result.stops.count >= 2 else { return }
        let range = span ?? 0...(result.stops.count - 1)
        if let pendingDeparturePlatform { result.stops[range.lowerBound].platformNumber = pendingDeparturePlatform }
        if let pendingArrivalPlatform { result.stops[range.upperBound].platformNumber = pendingArrivalPlatform }
    }

    private var tripDetailsSection: some View {
        Section {
            Button { showsFillDetails = true } label: {
                Label(text("fillDetails", fallback: "Fill in trip details"), systemImage: "text.badge.plus")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .accessibilityIdentifier("newTripFillDetails")
            if timetableFailed {
                Text(text("timetableFailed", fallback: "This timetable could not be applied."))
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            if let timetableTrain {
                VStack(alignment: .leading, spacing: 6) {
                    Text(limitedExpressName.isEmpty ? timetableTrain.number : limitedExpressName)
                        .font(.headline)
                    Text("\(timetableTrain.origin) → \(timetableTrain.destination)")
                    Text(text("stationCount", fallback: "{count} stations",
                              ["count": .string(String(timetableTrain.stops.count))]))
                    Text(timetableTimes(timetableTrain))
                        .font(.caption.monospacedDigit())
                    Button(text("timetableRemove", fallback: "Remove"), action: removeTimetable)
                        .accessibilityIdentifier("newTripTimetableRemove")
                }
                // Keep the Remove button's own identifier reachable.
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("newTripTimetableApplied")
            }
            manualEntryRows
        } header: {
            Text(text("tripDetails", fallback: "Trip details"))
        } footer: {
            Text(text("fillDetailsNote",
                      fallback: "Timetables, the line's services, and ChatGPT or pasted text, in one list."))
        }
    }

    private var fillDetailsSheet: some View {
        NavigationStack {
            Form {
                if region == .jp {
                    Section {
                        TextField(text("serviceName", fallback: "Service name"), text: $limitedExpressName)
                            .accessibilityIdentifier("newTripLimitedExpressName")
                        Menu(text("serviceSuggestions", fallback: "Service suggestions")) {
                            ForEach(serviceSuggestions, id: \.self) { name in
                                Button(name) { limitedExpressName = name }
                            }
                        }
                        Button { showsTimetablePicker = true } label: {
                            Label(text("timetableBrowse", fallback: "Browse timetables"), systemImage: "magnifyingglass")
                        }
                        .accessibilityIdentifier("newTripTimetableBrowse")
                    } header: {
                        Text(text("timetable", fallback: "Timetable"))
                    }
                    if origin != nil, destination != nil {
                        TimetableQuickMatchView(
                            train: timetableQuery,
                            serviceName: limitedExpressName) { trip in
                            applyTimetableTrip(trip)
                            showsFillDetails = false
                        }
                    }
                    if let package, !routeLineIDs.isEmpty {
                        LocalLineServicesSection(
                            package: package, lineIDs: routeLineIDs,
                            serviceDate: dayString(departure), trainType: $trainType)
                    }
                }
                Section {
                    Button { showsCompletion = true } label: {
                        Label(text("completeWithText", fallback: "ChatGPT or pasted text"),
                              systemImage: "sparkles")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .accessibilityIdentifier("rideEditorAICompletion")
                } footer: {
                    Text(text("completeWithTextNote",
                              fallback: "Review every proposed change before it is applied."))
                }
                // Whatever no source filled is entered by hand in the editor.
                let missing = missingDetails
                if !missing.isEmpty {
                    Section {
                        Text(missingText(missing)).font(.footnote)
                        Button(text("enterByHand", fallback: "Enter the rest by hand")) {
                            showsFillDetails = false
                        }
                        .accessibilityIdentifier("newTripFillDetailsByHand")
                    }
                }
            }
            .navigationTitle(text("fillDetails", fallback: "Fill in trip details"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localization.text("ios.done", fallback: "Done")) { showsFillDetails = false }
                        .accessibilityIdentifier("newTripFillDetailsDone")
                }
            }
            .accessibilityIdentifier("newTripFillDetailsForm")
        }
        .sheet(isPresented: $showsTimetablePicker) {
            ServicePatternPickerView(
                region: region.code,
                rideDate: dayString(departure),
                onSelectDate: { day in
                    if let day, let date = timetableDate(day, time: clock(departure, extraDays: 0)) {
                        timetableTimeSelection(isDeparture: true).wrappedValue = date
                    }
                },
                onSelectTrip: { applyTimetableTrip($0); showsFillDetails = false },
                onSelectDraft: { applyTimetableTrip($0); showsFillDetails = false }
            ) { pattern, reversed in
                applyPattern(pattern, reversed: reversed)
                showsFillDetails = false
            }
        }
        .sheet(isPresented: $showsCompletion) {
            JourneyCompletionView(
                trains: [currentResult() ?? draft],
                context: limitedExpressName.isEmpty ? ""
                    : "Limited express service name: \(limitedExpressName)",
                allowsRawImport: true,
                onApply: { completed in
                    guard let completed = completed.first else { return }
                    adoptCompletedRecord(completed)
                    showsFillDetails = false
                })
        }
    }

    /// Lines of the route on screen, for the line's service types.
    private var routeLineIDs: [String] {
        let sections: [RouteSection]
        if let timetableTrain {
            sections = timetableTrain.routeSections ?? []
        } else if routeEdited {
            return selectedCorridor?.choice.lineIDs ?? []
        } else {
            sections = draft.routeSections ?? []
        }
        var seen: Set<String> = []
        return sections.flatMap { $0.lineIDs ?? [] }.filter { seen.insert($0).inserted }
    }

    /// What Save would write now, without validating it.
    private func currentResult() -> Train? {
        if let timetableTrain { return timetableResult(timetableTrain) }
        if routeEdited { return selectedCorridor.flatMap(corridorDraft(for:)) }
        var result = draft
        result.region = region.code
        applyHeader(to: &result)
        return result
    }

    /// A reviewed completion becomes the record: its stops are the route,
    /// and the header shows its values.
    private func adoptCompletedRecord(_ completed: Train) {
        var completed = completed
        if completed.stops != draft.stops || completed.routeSections != draft.routeSections,
           completed.routeConfirmation == .confirmed {
            completed.routeConfirmation = nil
        }
        clearTimetable()
        vias = []
        draft = completed
        hasRecordRoute = completed.stops.count >= 2
        let seeded = EditorSeed(train: completed, isNew: false)
        seed = seeded
        trainType = seeded.trainType
        trainNumber = seeded.number
        companyName = seeded.company
        departure = seeded.departure
        arrival = seeded.arrival
        previousDeparture = seeded.departure
        riddenOverride = nil
        seededStationIdentity = nil
        if let catalog { seedStations(from: catalog) }
    }

    private var serviceSuggestions: [String] {
        let names = TrainServiceBranding.services.filter { $0.region == region.code }.flatMap(\.names)
        return Array(Set(names)).sorted().filter {
            limitedExpressName.isEmpty || $0.localizedCaseInsensitiveContains(limitedExpressName)
        }
    }

    private var timetableBase: Train {
        var base = draft
        base.region = region.code
        base.date = dayString(departure)
        base.stops = [origin, destination].enumerated().compactMap { index, station in
            guard let station else { return nil }
            return endpointStop(
                station, stationID: index == 0 ? originStationID : destinationStationID,
                stopType: index == 0 ? "origin" : "destination", ridden: false)
        }
        base.origin = origin?.name ?? ""
        base.destination = destination?.name ?? ""
        return base
    }

    /// Derived on every render (two stops, cheap) so the lookup can never run
    /// against an older copy of the Time section.
    private var timetableQuery: Train {
        // Quick match only looks up once the endpoints carry departure and
        // arrival clocks, so the query uses the Time section's values.
        // `registryEpoch` is read so a settle rebuilds this derived train.
        _ = registryEpoch
        var query = timetableBase
        if query.stops.count == 2 {
            query.stops[0].departure = clock(departure, extraDays: 0)
            query.stops[1].arrival = clock(arrival, extraDays: extraDays(from: departure, to: arrival))
        }
        return JourneyCompletion.resolvingUniqueStationNames(
            in: query, catalogs: catalog.map { [region.code: $0] } ?? [:])
    }

    private func timetableTimeSelection(isDeparture: Bool) -> Binding<Date> {
        Binding(
            get: { isDeparture ? departure : arrival },
            set: { value in
                let previous = isDeparture ? departure : arrival
                // Only the departure day identifies the service; overnight
                // arrivals legitimately fall on the next civil day.
                if isDeparture, !applyingTimetable, dayString(value) != dayString(previous),
                   let timetableTrain, dayString(value) != timetableTrain.date {
                    clearTimetable()
                }
                if !applyingTimetable {
                    if isDeparture { departureTouched = true } else { arrivalTouched = true }
                }
                if isDeparture { departure = value } else { arrival = value }
            })
    }

    private var isRidden: Bool {
        riddenOverride ?? (hasRecordRoute ? RideLedger.hasBeenRidden(draft) : prefillRidden(forDate: dayString(departure)))
    }

    private func prefillRidden(forDate date: String?) -> Bool {
        Dates.normalizeDateString(date).map {
            $0 <= RecordDate.today(in: Region.resolved(timetableBase).clock)
        } ?? true
    }

    /// Remove puts the header back as it was before the timetable filled it.
    private func removeTimetable() {
        if let header = headerBeforeTimetable {
            applyingTimetable = true
            trainType = header.trainType
            departure = header.departure
            arrival = header.arrival
            previousDeparture = header.previousDeparture
            departureTouched = header.departureTouched
            arrivalTouched = header.arrivalTouched
            applyingTimetable = false
        }
        clearTimetable()
    }

    private func clearTimetable() {
        headerBeforeTimetable = nil
        timetableTrain = nil
        timetableRideSpan = nil
        timetableTrainTypeChanged = false
        timetableFailed = false
        saveIssues = []
    }

    private func applyTimetableTrip(_ trip: TrainTimetableDatabase.Trip) {
        let day = trip.serviceDate.isEmpty ? dayString(departure) : trip.serviceDate
        let ridden = riddenOverride ?? prefillRidden(forDate: day)
        guard let drafted = JourneyDraftWork.timetableDraft(
            from: trip, appliedTo: timetableBase, ridden: ridden) else {
            timetableFailed = true
            return
        }
        if acceptTimetable(drafted.train) {
            limitedExpressName = drafted.serviceName
            if let kept = timetableTrain {
                TimetableRouteEvidence.rememberAppliedOccurrence(trip: trip, train: kept)
            }
        }
    }

    private func applyPattern(_ pattern: TrainServicePatterns.Pattern, reversed: Bool) {
        _ = acceptTimetable(TrainServicePatterns.apply(
            pattern, to: timetableBase, reversed: reversed, ridden: isRidden))
    }

    @discardableResult
    private func acceptTimetable(_ applied: Train) -> Bool {
        guard applied.stops.count >= 2 else {
            timetableFailed = true
            return false
        }
        var applied = applied
        var span = 0...(applied.stops.count - 1)
        if let origin, let destination {
            let codes = [origin.key.sourceCode, destination.key.sourceCode]
                + applied.stops.compactMap(\.n02StationCode)
            let aliases: [String: String]
            do {
                aliases = try package.map { try loadJourneyStationAliases(for: codes, package: $0) } ?? [:]
            } catch {
                timetableFailed = true
                routeProofFailure = error.localizedDescription
                return false
            }
            func matches(_ stop: Stop, _ station: CatalogStation) -> Bool {
                guard let code = stop.n02StationCode else { return false }
                let selected = station.key.sourceCode
                return (aliases[code] ?? code) == (aliases[selected] ?? selected)
            }
            guard let first = applied.stops.firstIndex(where: { matches($0, origin) }),
                  let last = applied.stops.indices.first(where: {
                      $0 > first && matches(applied.stops[$0], destination)
                  }) else {
                timetableFailed = true
                return false
            }
            span = first...last
            // Keep published passenger calls and route facts. Pass-through flags
            // inherit adjacent calls in Statistics, so do not turn unboarded
            // passenger calls into pass-throughs to represent a partial ride.
            for index in applied.stops.indices {
                applied.stops[index].rideSegment = span.contains(index) && applied.stops[index].rideSegment
                if applied.stops[index].stopType == "origin" || applied.stops[index].stopType == "destination" {
                    applied.stops[index].stopType = "passenger_stop"
                }
            }
            applied.stops[first].stopType = "origin"
            applied.stops[last].stopType = "destination"
            applied.origin = applied.stops[first].name
            applied.destination = applied.stops[last].name
        } else {
            if origin == nil,
               let code = applied.stops.first?.n02StationCode,
               let station = catalog?.station(StationKey(regionCode: region.code, sourceCode: code)) {
                origin = station
                originLine = nil
                originStationID = applied.stops.first?.stationID
            }
            if destination == nil,
               let code = applied.stops.last?.n02StationCode,
               let station = catalog?.station(StationKey(regionCode: region.code, sourceCode: code)) {
                destination = station
                destinationLine = nil
                destinationStationID = applied.stops.last?.stationID
            }
        }
        if headerBeforeTimetable == nil {
            headerBeforeTimetable = HeaderSnapshot(
                trainType: trainType, departure: departure, arrival: arrival,
                previousDeparture: previousDeparture,
                departureTouched: departureTouched, arrivalTouched: arrivalTouched)
        }
        applyingTimetable = true
        defer { applyingTimetable = false }
        timetableTrain = applied
        timetableRideSpan = span
        timetableTrainTypeChanged = false
        timetableFailed = false
        saveIssues = []
        let type = applied.trainType ?? ""
        if type.contains("新幹線") { trainType = "highSpeed" }
        else if type.contains("特急") { trainType = "limitedExpress" }
        else if type.contains("急行") { trainType = "express" }
        else if type.contains("快速") { trainType = "rapid" }
        let day = applied.date ?? dayString(departure)
        var appliedDeparture: Date?
        var appliedArrival: Date?
        if let time = applied.stops[span.lowerBound].departure,
           let date = timetableDate(day, time: time) {
            appliedDeparture = date
        }
        if let time = applied.stops[span.upperBound].arrival,
           let date = timetableDate(day, time: time) {
            appliedArrival = date
        }
        if let appliedDeparture {
            timetableTimeSelection(isDeparture: true).wrappedValue = appliedDeparture
        }
        if let appliedArrival {
            timetableTimeSelection(isDeparture: false).wrappedValue = appliedArrival
        }
        if let appliedDeparture, appliedArrival != nil {
            previousDeparture = appliedDeparture
        }
        return true
    }

    private func timetableDate(_ day: String, time: String) -> Date? {
        EditorSeed.date(day: day, time: time)
    }

    private func timetableTimes(_ timetable: Train) -> String {
        let span = timetableRideSpan ?? 0...(timetable.stops.count - 1)
        return [timetable.stops[span.lowerBound].departure, timetable.stops[span.upperBound].arrival]
            .compactMap { $0 }.joined(separator: " → ")
    }

    private func timetablePassStations(_ timetable: Train) -> some View {
        DisclosureGroup {
            ForEach(Array(timetable.stops.enumerated()), id: \.offset) { _, stop in
                let qualifier = recordedQualifier(code: stop.n02StationCode)
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(BracketedStationText.title(
                            officialName: stop.name,
                            localizedTitle: localization.stationName(
                                stop.name, code: stop.n02StationCode, region: region),
                            regionCode: region.code, localization: localization))
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .layoutPriority(1)
                        StationQualifierCaption(text: BracketedStationText.secondary(
                            officialName: stop.name, regionCode: region.code,
                            qualifier: qualifier, localization: localization))
                    }
                    Spacer(minLength: 8)
                    Text([stop.arrival, stop.departure].compactMap { $0 }.joined(separator: " / "))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    StationQualifierCopy.spoken(
                        name: stop.name, countryCode: region.code.uppercased(),
                        qualifier: qualifier, localization: localization))
                .contextMenu {
                    let full = copyText(code: stop.n02StationCode, fallbackName: stop.name)
                    Button {
                        StationQualifierCopy.copy(full)
                    } label: {
                        Label(localization.text("ios.editor.copyStation", fallback: "Copy"), systemImage: "doc.on.doc")
                    }
                    ShareLink(item: full) {
                        Label(localization.text("ios.share", fallback: "Share"), systemImage: "square.and.arrow.up")
                    }
                }
            }
        } label: {
            Text(text("passStations", fallback: "Stations on this route ({count})",
                      ["count": .string(String(timetable.stops.count))]))
        }
        .accessibilityIdentifier("newTripPassStations")
    }

    private var routeSection: some View {
        Section {
            if let timetableTrain {
                timetablePassStations(timetableTrain)
            } else if showsRecordRoute {
                recordRouteRows
            } else if searching {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(text("searching", fallback: "Searching routes"))
            } else if let outcome {
                routeOutcome(outcome)
            }
            if let routeProofFailure {
                Text(routeProofFailure)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if autofillFailed {
                Text(text("autofillFailed", fallback: "This route could not be applied."))
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            directionRows
        } header: {
            Text(text("route", fallback: "Route"))
        }
    }

    // MARK: - direction

    /// What decides the legs: the route on screen, not every render's draft.
    private struct DirectionKey: Equatable {
        var stops: [String?]
        var sections: [RouteSection]
        var loaded: Bool
    }

    /// The route the direction is read from: the saved route, the chosen
    /// corridor, or the applied timetable. Built only when its key changes.
    private var directionSource: Train? {
        if let timetableTrain { return timetableResult(timetableTrain) }
        if routeEdited { return selectedCorridor.flatMap(corridorDraft(for:)) }
        return draft
    }

    private var directionKey: DirectionKey {
        // Cheap inputs only; the source train itself is built in the task.
        DirectionKey(
            stops: (timetableTrain?.stops ?? (routeEdited ? [] : draft.stops)).map(\.n02StationCode)
                + [selectedCorridorID, routeEdited ? "edited" : nil],
            sections: timetableTrain?.routeSections ?? (routeEdited ? [] : draft.routeSections ?? []),
            loaded: package != nil)
    }

    private func loadDirections() async {
        guard let package, let source = directionSource, source.stops.count >= 2 else {
            directionLegs = []
            return
        }
        let legs = await Task.detached(priority: .utility) {
            (try? TravelDirection.legs(train: source, package: package)) ?? []
        }.value
        guard !Task.isCancelled else { return }
        directionLegs = legs
    }

    /// The reader's 方面, from the record's direction field. A stored
    /// up/down word is a direction, not a 方面, and is not shown here.
    private var boundFor: String? {
        let value = draft.direction?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty || ["up", "down", "unknown"].contains(value) ? nil : value
    }

    private func directionWord(_ direction: TravelDirection.Direction?) -> String {
        switch direction {
        case .up: localization.text("ios.direction.up")
        case .down: localization.text("ios.direction.down")
        case nil: text("directionUnknown", fallback: "Direction not known")
        }
    }

    private func boundForText(_ name: String) -> String {
        text("boundFor", fallback: "Toward {name}", ["name": .string(name)])
    }

    /// Suggestions only. Nothing is written until the reader picks one.
    private var boundForSuggestions: [String] {
        var names = directionLegs.reversed().compactMap(\.terminalName)
        if let last = (directionSource ?? draft).stops.last?.name { names.insert(last, at: 0) }
        var seen: Set<String> = []
        return names.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    @ViewBuilder private var directionRows: some View {
        ForEach(Array(directionLegs.enumerated()), id: \.offset) { index, leg in
            HStack(spacing: 10) {
                Image(systemName: leg.direction == .up ? "arrow.up.circle.fill"
                      : leg.direction == .down ? "arrow.down.circle.fill" : "questionmark.circle")
                    .foregroundStyle(leg.direction == nil ? Color.secondary : Color.accentColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(directionWord(leg.direction))
                        .font(.subheadline.weight(.semibold))
                    if let line = leg.lineID.flatMap(lineName(for:)) {
                        Text(line).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if index == directionLegs.count - 1, let boundFor {
                    Text(boundForText(boundFor)).font(.caption).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("newTripDirection-\(index)")
        }
        if !directionLegs.isEmpty || boundFor != nil {
            Menu {
                ForEach(boundForSuggestions, id: \.self) { name in
                    Button(boundForText(name)) { draft.direction = name }
                }
                Button(text("boundForOther", fallback: "Other…")) {
                    boundForDraft = boundFor ?? ""
                    showsBoundForEntry = true
                }
                if boundFor != nil {
                    Button(text("boundForClear", fallback: "Clear"), role: .destructive) { draft.direction = nil }
                }
            } label: {
                LabeledContent(text("boundForTitle", fallback: "方面")) {
                    Text(boundFor.map(boundForText) ?? text("boundForChoose", fallback: "Choose"))
                        .foregroundStyle(boundFor == nil ? .secondary : .primary)
                }
                .frame(minHeight: 44)
            }
            .accessibilityIdentifier("newTripBoundFor")
            .alert(text("boundForTitle", fallback: "方面"), isPresented: $showsBoundForEntry) {
                TextField(text("boundForTitle", fallback: "方面"), text: $boundForDraft)
                Button(localization.text("ios.done", fallback: "Done")) {
                    let value = boundForDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    draft.direction = value.isEmpty ? nil : value
                }
                Button(localization.text("ios.cancel", fallback: "Cancel"), role: .cancel) {}
            }
        }
    }

    private func lineName(for id: String) -> String? {
        lineLabelByID[id] ?? package?.lines.first(where: { $0.id == id })?.name
    }

    /// One arrow per leg, at the middle of that leg's line on the chosen
    /// route, pointing the way the trip runs.
    private var directionArrows: [TripMapContent.Arrow] {
        guard !directionLegs.isEmpty,
              let route = drawnRoutes.first(where: \.isSelected) else { return [] }
        let pieces = route.pieces.filter { !$0.isConnector && $0.coordinates.count >= 2 }
        var arrows: [TripMapContent.Arrow] = []
        var used = 0
        for (index, leg) in directionLegs.enumerated() where leg.direction != nil {
            guard used < pieces.count else { break }
            let piece = pieces[used]
            used += 1
            let coordinates = piece.coordinates
            let middle = coordinates.count / 2
            let a = coordinates[max(0, middle - 1)]
            let b = coordinates[min(coordinates.count - 1, max(middle, 1))]
            var label = directionWord(leg.direction)
            if index == directionLegs.count - 1, let boundFor { label += " · " + boundForText(boundFor) }
            arrows.append(.init(id: String(index), coordinate: a, bearing: bearing(a, b), label: label))
        }
        return arrows
    }

    private func bearing(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return atan2(y, x) * 180 / .pi
    }

    @ViewBuilder private func routeOutcome(_ outcome: TripRoutePlanner.Outcome) -> some View {
        switch outcome {
        case .corridors(let corridors):
            if corridors.count > 1 {
                Text(text(
                    "multipleRoutes",
                    fallback: "Multiple routes connect these stations — choose one"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(corridors.enumerated()), id: \.element.id) { index, corridor in
                VStack(alignment: .leading, spacing: 8) {
                    corridorRow(corridor, index: index)
                    if selectedCorridorID == corridor.id {
                        passStations(corridor)
                    }
                }
            }
            if corridorsRemovedByDate {
                Text(text(
                    corridors.isEmpty ? "noCorridorOnDate" : "corridorsHiddenByDate",
                    fallback: corridors.isEmpty
                        ? "No route was open on this date."
                        : "Some routes are hidden because they were not open on this date."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .disconnected(let junctions):
            VStack(alignment: .leading, spacing: 8) {
                routeError(disconnectedMessage(junctions))
                Text(text("continueAnywayExplanation",
                          fallback: "Treat the listed stations as through-running connections."))
                    .font(.caption).foregroundStyle(.secondary)
                Button(text("continueAnyway", fallback: "Continue anyway")) {
                    allowUnverifiedConnections = true
                }
                .accessibilityIdentifier("newTripContinueAnyway")
            }
        case .noRoute:
            routeError(text(
                "noRoute",
                fallback: "No rail connection between these stations."))
        case .noCompanyRoute(let name):
            routeError(text(
                "noCompanyRoute",
                fallback: "No route between these stations is operated by {company}.",
                ["company": .string(name)]))
        case .sameStation:
            routeError(text("sameStation", fallback: "Choose two different stations."))
        case .truncated:
            routeError(text(
                "truncated",
                fallback: "The search was too large. Try choosing a company or a different train type."))
        }
    }

    private func corridorRow(_ corridor: TripRoutePlanner.Corridor, index: Int) -> some View {
        let selected = selectedCorridorID == corridor.id
        return Button {
            selectedCorridorID = corridor.id
            preferredCorridorID = corridor.id
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(corridor.lineNames.joined(separator: " → "))
                        .font(.body)
                        .multilineTextAlignment(.leading)
                    if !corridor.operatorNames.isEmpty {
                        Text(corridor.operatorNames.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(stationCountText(corridor))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(Array(corridor.junctions.enumerated()), id: \.offset) { _, junction in
                        if let badge = junctionBadge(junction) {
                            if junction.link == .none {
                                Label(badge, systemImage: "exclamationmark.triangle")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                Text(badge)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if selected {
                    Image(systemName: "checkmark")
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("newTripCorridor-\(index)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func passStations(_ corridor: TripRoutePlanner.Corridor) -> some View {
        let stations = corridor.choice.stations
        return DisclosureGroup {
            ForEach(Array(stations.enumerated()), id: \.offset) { index, visit in
                let qualifier = visitQualifier(visit, corridor: corridor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(BracketedStationText.title(
                        officialName: visit.name,
                        localizedTitle: localization.stationName(
                            visit.name, code: visit.code, region: region),
                        regionCode: region.code, localization: localization))
                        .fontWeight(index == 0 || index == stations.count - 1 ? .bold : .regular)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                    StationQualifierCaption(text: BracketedStationText.secondary(
                        officialName: visit.name, regionCode: region.code,
                        qualifier: qualifier, localization: localization))
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(StationQualifierCopy.spoken(
                    name: visit.name, countryCode: region.code.uppercased(),
                    qualifier: qualifier, localization: localization))
                .contextMenu {
                    let full = copyText(
                        code: visit.code, fallbackName: visit.name,
                        contextLineIDs: Set(corridor.choice.lineIDs))
                    Button {
                        StationQualifierCopy.copy(full)
                    } label: {
                        Label(localization.text("ios.editor.copyStation", fallback: "Copy"), systemImage: "doc.on.doc")
                    }
                    ShareLink(item: full) {
                        Label(localization.text("ios.share", fallback: "Share"), systemImage: "square.and.arrow.up")
                    }
                }
            }
        } label: {
            Text(text(
                "passStations",
                fallback: "Stations on this route ({count})",
                ["count": .string(String(stations.count))]))
        }
        .accessibilityIdentifier("newTripPassStations")
    }

    private func routeError(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("newTripRouteError")
    }

    private func stationButton(
        title: String,
        station: CatalogStation?,
        line: CatalogLine?,
        identifier: String,
        choose: @escaping () -> Void
    ) -> some View {
        Button(action: choose) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(stationTitle(station))
                    .font(.body)
                    .foregroundStyle(station == nil ? Color.secondary : Color.primary)
                if let station, let subtitle = stationSubtitle(station, line: line) {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(catalog == nil)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(stationAccessibility(title: title, station: station, line: line))
        .accessibilityIdentifier(identifier)
        .contextMenu {
            if let station {
                let full = copyText(for: station, line: line)
                Button {
                    StationQualifierCopy.copy(full)
                } label: {
                    Label(localization.text("ios.editor.copyStation", fallback: "Copy"), systemImage: "doc.on.doc")
                }
                ShareLink(item: full) {
                    Label(localization.text("ios.share", fallback: "Share"), systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    private var canSave: Bool {
        guard draft.journeyGroup?.name.isEmpty != true, !repair.isRunning else { return false }
        if let timetableTrain { return timetableTrain.stops.count >= 2 && arrival >= departure }
        if !routeEdited { return hasRecordRoute && arrival >= departure }
        return origin != nil && destination != nil && arrival >= departure
            && plannedIdentity == routeIdentity
            && selectedCorridor != nil && !searching
    }

    /// Stations, lines and vias: the inputs that pick a physical route.
    private var stationIdentity: String {
        [
            region.code,
            origin?.key.sourceCode ?? "",
            destination?.key.sourceCode ?? "",
            originLine?.id ?? "",
            destinationLine?.id ?? "",
            vias.map(\.station.key.sourceCode).joined(separator: ","),
        ].joined(separator: "\u{1f}")
    }

    /// The reader asked for a route other than the saved one. Always true
    /// for a new trip, which has no saved route.
    private var routeEdited: Bool {
        !hasRecordRoute || seededStationIdentity.map { $0 != stationIdentity } == true
    }

    /// Whether the editor still shows the saved stops as the route.
    private var showsRecordRoute: Bool {
        !routeEdited && timetableTrain == nil
    }

    private var selectedCorridor: TripRoutePlanner.Corridor? {
        guard plannedIdentity == routeIdentity,
              let selectedCorridorID,
              let outcome,
              case .corridors(let corridors) = outcome else { return nil }
        return corridors.first { $0.id == selectedCorridorID }
    }

    private var routeIdentity: String {
        [
            region.code,
            origin?.key.sourceCode ?? "",
            destination?.key.sourceCode ?? "",
            originLine?.id ?? "",
            destinationLine?.id ?? "",
            vias.map(\.station.key.sourceCode).joined(separator: ","),
            dayString(departure),
            String(departure.timeIntervalSinceReferenceDate),
            String(arrival.timeIntervalSinceReferenceDate),
            trainNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            trainType,
            companyName,
            package == nil ? "0" : "1",
            allowUnverifiedConnections ? "1" : "0",
        ].joined(separator: "\u{1f}")
    }

    /// Operators of the lines that serve the chosen origin, the chosen
    /// destination, or both. Sorted and deduped by display name.
    /// Called when the catalog or the endpoint stations change, not from `body`.
    private func refreshCompanyCache() {
        guard let catalog else {
            operatorNameByID = [:]
            packageOperatorByDisplayName = [:]
            companyOptions = []
            lineLabelByID = [:]
            return
        }
        let names = Dictionary(
            catalog.operators(in: region.code).map { ($0.id, $0.name) },
            uniquingKeysWith: { first, _ in first })
        operatorNameByID = names
        lineLabelByID = StationLabel.lineLabels(in: catalog, regionCode: region.code)
        if let package {
            packageOperatorByDisplayName = Self.packageOperatorNames(package)
        }
        var found: Set<String> = []
        for station in [origin, destination].compactMap({ $0 }) {
            for member in catalog.memberships(stationKey: station.key) {
                guard let line = catalog.line(id: member.lineID, regionCode: member.regionCode) else { continue }
                for identifier in line.operatorIDs {
                    if let name = names[identifier], !name.isEmpty { found.insert(name) }
                }
            }
        }
        companyOptions = found.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// `CatalogOperator.name` is the package operator with whitespace collapsed.
    /// Prefer a raw `line.operator` that already equals that name; otherwise keep
    /// the package spelling, which is what corridor `operatorNames` contain.
    private static func packageOperatorNames(_ package: CompactPackage) -> [String: String] {
        var chosen: [String: String] = [:]
        for line in package.lines {
            guard let raw = line.operator else { continue }
            let collapsed = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard !collapsed.isEmpty else { continue }
            if let existing = chosen[collapsed] {
                if existing != collapsed, raw == collapsed { chosen[collapsed] = raw }
            } else {
                chosen[collapsed] = raw
            }
        }
        return chosen
    }

    private func copyText(for station: CatalogStation, line: CatalogLine?) -> String {
        guard let catalog else {
            return StationLabel.countryOnly(
                name: station.name, countryCode: station.key.regionCode.uppercased()).full
        }
        return StationReferenceResolution.copyLabel(
            for: station, catalog: catalog, preferredLineID: line?.id)
    }

    private func copyText(
        code: String?, fallbackName: String, contextLineIDs: Set<String> = []
    ) -> String {
        let country = region.code.uppercased()
        guard let catalog, let code, !code.isEmpty,
              let station = catalog.station(StationKey(regionCode: region.code, sourceCode: code))
        else { return StationLabel.countryOnly(name: fallbackName, countryCode: country).full }
        return StationReferenceResolution.copyLabel(
            for: station, catalog: catalog, contextLineIDs: contextLineIDs)
    }

    private func stationTitle(_ station: CatalogStation?) -> String {
        guard let station else { return text("chooseStation", fallback: "Choose station") }
        return BracketedStationText.title(
            officialName: station.name,
            localizedTitle: localization.stationName(
                station.name, code: station.key.sourceCode, region: region),
            regionCode: station.key.regionCode, localization: localization)
    }

    /// Bracket qualifier for the chosen station. A picked line names that line.
    private func stationQualifier(_ station: CatalogStation, line: CatalogLine?) -> String {
        guard let catalog else {
            return StationLabel.caption(countryCode: station.key.regionCode.uppercased(), detail: nil)
        }
        let labels = lineLabelByID.isEmpty
            ? StationLabel.lineLabels(in: catalog, regionCode: station.key.regionCode) : lineLabelByID
        return StationLabel.text(
            for: station, catalog: catalog, labels: labels, preferredLineID: line?.id).qualifier
    }

    private func stationSubtitle(_ station: CatalogStation, line: CatalogLine?) -> String? {
        let qualifier = stationQualifier(station, line: line)
        return BracketedStationText.secondary(
            officialName: station.name, regionCode: station.key.regionCode,
            qualifier: qualifier, localization: localization)
    }

    private func stationAccessibility(title: String, station: CatalogStation?, line: CatalogLine?) -> String {
        guard let station else { return title }
        let qualifier = stationQualifier(station, line: line)
        return title + "，" + StationQualifierCopy.spoken(
            name: station.name, countryCode: station.key.regionCode.uppercased(),
            qualifier: qualifier, localization: localization)
    }

    private func recordedQualifier(code: String?) -> String {
        let country = region.code.uppercased()
        guard let catalog, let code, !code.isEmpty,
              let station = catalog.station(StationKey(regionCode: region.code, sourceCode: code))
        else { return StationLabel.caption(countryCode: country, detail: nil) }
        let labels = lineLabelByID.isEmpty
            ? StationLabel.lineLabels(in: catalog, regionCode: region.code) : lineLabelByID
        return StationLabel.text(for: station, catalog: catalog, labels: labels).qualifier
    }

    private func visitQualifier(
        _ visit: RailwayRouteChoices.Visit, corridor: TripRoutePlanner.Corridor
    ) -> String {
        let country = region.code.uppercased()
        if let change = lineChangeCaption(for: visit, junctions: corridor.junctions) {
            let detail = change.replacingOccurrences(of: "\n", with: " · ")
            return StationLabel.caption(countryCode: country, detail: detail)
        }
        guard let catalog,
              let station = catalog.station(StationKey(regionCode: region.code, sourceCode: visit.code))
        else {
            if corridor.lineNames.count == 1, let name = corridor.lineNames.first {
                return StationLabel.caption(countryCode: country, detail: name)
            }
            return StationLabel.caption(countryCode: country, detail: nil)
        }
        let labels = lineLabelByID.isEmpty
            ? StationLabel.lineLabels(in: catalog, regionCode: region.code) : lineLabelByID
        return StationLabel.text(
            for: station, catalog: catalog, labels: labels,
            contextLineIDs: Set(corridor.choice.lineIDs)).qualifier
    }

    /// Finds the saved journey's end stations in the catalog. The saved
    /// stops stay the route until the reader picks another station or via.
    private func seedStations(from catalog: EditorCatalog) {
        func station(_ stop: Stop?) -> CatalogStation? {
            guard let code = stop?.n02StationCode else { return nil }
            return catalog.station(StationKey(regionCode: region.code, sourceCode: code))
        }
        if draft.stops.count >= 2 {
            origin = station(draft.stops.first)
            originStationID = draft.stops.first?.stationID
            destination = station(draft.stops.last)
            destinationStationID = draft.stops.last?.stationID
        }
        seededStationIdentity = stationIdentity
    }

    private func swapStations() {
        clearTimetable()
        let previous = origin
        let previousLine = originLine
        origin = destination
        originLine = destinationLine
        destination = previous
        destinationLine = previousLine
        let previousID = originStationID
        originStationID = destinationStationID
        destinationStationID = previousID
        vias.reverse()
    }

    private func endpointStop(
        _ station: CatalogStation, stationID: String?, stopType: String, ridden: Bool
    ) -> Stop {
        var stop = Stop(
            name: station.name, n02StationCode: station.key.sourceCode,
            stopType: stopType, rideSegment: ridden)
        RegistryStationSelection.fill(
            &stop, regionCode: region.code, sourceCode: station.key.sourceCode,
            catalogName: station.name, stationID: stationID)
        stop.stopType = stopType
        stop.rideSegment = ridden
        return stop
    }

    private func commitCompany(_ text: String, on train: inout Train) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            RegistryIdentityUpgrade.reassignCompany(nil, on: &train)
        } else if !RegistryOperatorCommit.apply(text: trimmed, region: region.code, to: &train) {
            RegistryIdentityUpgrade.reassignCompany(trimmed, on: &train)
        }
    }

    private func loadRegion() async {
        loadFailed = false
        let region = region
        let generation = draftGeneration
        let worker = Task.detached(priority: .utility) { () async throws -> (EditorCatalog, CompactPackage) in
            let catalog = try loadCatalog(for: region)
            let package = try await DisplayNetworkCache.shared.package(country: region.code).package
            return (catalog, package)
        }
        do {
            let loaded = try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled, region == self.region, generation == draftGeneration else { return }
            catalog = loaded.0
            package = loaded.1
            geometryCache = TripRouteGeometry.Cache(package: loaded.1)
            mapStations = loaded.0.stations(in: region.code)
            if hasRecordRoute, seededStationIdentity == nil { seedStations(from: loaded.0) }
            lineColorByID = Dictionary(
                loaded.1.lines.compactMap { line in line.color.map { (line.id, $0) } },
                uniquingKeysWith: { first, _ in first })
            refreshCompanyCache()
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, region == self.region, generation == draftGeneration else { return }
            catalog = nil
            package = nil
            geometryCache = nil
            loadFailed = true
        }
    }

    private func planRoute() async {
        // Typing a number or nudging a time changes the identity on every
        // keystroke. Wait for the input to settle before solving; a newer
        // identity cancels this task during the wait.
        if routeEdited, origin != nil, destination != nil {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
        }
        let generation = draftGeneration
        let identity = routeIdentity
        let previousSelectedCorridorID = selectedCorridorID ?? preferredCorridorID
        outcome = nil
        plannedIdentity = ""
        physicallyResolvedCorridorIDs.removeAll()
        routeProofFailure = nil
        selectedCorridorID = nil
        corridorsRemovedByDate = false
        autofillFailed = false
        guard routeEdited, let origin, let destination, let package, let geometryCache else {
            searching = false
            refreshDrawnRoutes()
            return
        }
        searching = true
        let originCode = origin.key.sourceCode
        let destinationCode = destination.key.sourceCode
        let allowUnverifiedConnections = allowUnverifiedConnections
        let originLineID = originLine?.id
        let destinationLineID = destinationLine?.id
        let rideDate = dayString(departure)
        let viaCodes = vias.map(\.station.key.sourceCode)
        let trainType = trainType
        // Only an operator the catalog names filters the search. A saved
        // journey's company text ("A・B" for a through service) does not.
        let operatorName = companyName.isEmpty || !companyOptions.contains(companyName)
            ? nil
            : (packageOperatorByDisplayName[companyName] ?? companyName)
        let worker = Task.detached(priority: .userInitiated) {
            let request = TripRoutePlanner.Request(
                originCode: originCode,
                destinationCode: destinationCode,
                trainType: trainType,
                operatorName: operatorName,
                stationAliases: try loadJourneyStationAliases(
                    for: [originCode, destinationCode] + viaCodes, package: package),
                originLineID: originLineID,
                destinationLineID: destinationLineID,
                allowUnverifiedConnections: allowUnverifiedConnections)
            let context = try loadJourneyAdmissionContext(rideDate: rideDate, package: package)
            let outcome = try TripRoutePlanner.plan(
                package: package, request: request, viaCodes: viaCodes, rideDate: rideDate,
                admissionContext: context)
            var geometry: [String: [TripRouteGeometry.Piece]] = [:]
            if case .corridors(let corridors) = outcome {
                for corridor in corridors.prefix(Self.maximumDrawnRoutes) {
                    try Task.checkCancellation()
                    geometry[corridor.id] = TripRouteGeometry.pieces(for: corridor.choice, cache: geometryCache)
                }
            }
            return (outcome, geometry)
        }
        let result: TripRoutePlanner.Outcome
        let geometry: [String: [TripRouteGeometry.Piece]]
        do {
            (result, geometry) = try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: { worker.cancel() }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, identity == routeIdentity, generation == draftGeneration else { return }
            searching = false
            routeProofFailure = error.localizedDescription
            drawnRoutes = []
            return
        }
        guard !Task.isCancelled, identity == routeIdentity, generation == draftGeneration else { return }
        var publishedResult = result
        var removedByDate = false
        var physicallyResolvedIDs: Set<String> = []
        var proofFailure: String?
        if case .corridors(let corridors) = result {
            let hasDatedNetwork = RiddenRouteStore.hasDatedNetwork(region: region.code)
            var latestValidFrom: String?
            do {
                if hasDatedNetwork {
                    latestValidFrom = try RiddenRouteStore.latestValidFrom(region: region.code)
                }
            } catch {
                // Unknown date bounds cannot exclude otherwise valid corridors.
                // Keep the proposals, show the actual resource failure, and leave them unproven.
                proofFailure = error.localizedDescription
            }
            let normalizedRideDate = Dates.normalizeDateString(rideDate)
            // Today's network cannot reject a date after its newest opening.
            let needsDateValidation = hasDatedNetwork && proofFailure == nil && (
                normalizedRideDate != rideDate
                    || latestValidFrom.map { rideDate < $0 } == true)
            if needsDateValidation {
                let candidates = corridors.map {
                    TripRouteValidation.Candidate(id: $0.id, train: corridorDraft(for: $0))
                }
                do {
                    let validation = try await TripRouteValidation.validate(candidates: candidates) { trains in
                        try await RiddenRouteStore.routeAvailabilities(trains).map {
                            .init(datedResolved: $0.datedResolved, undatedResolved: $0.undatedResolved)
                        }
                    }
                    physicallyResolvedIDs = validation.physicallyResolvedIDs
                    proofFailure = validation.unprovenReason
                    if validation.unprovenReason != nil { physicallyResolvedIDs = [] }
                    let filtered = corridors.filter { validation.retainedIDs.contains($0.id) }
                    removedByDate = filtered.count < corridors.count
                    publishedResult = .corridors(filtered)
                } catch is CancellationError {
                    return
                } catch {
                    // The records stay savable. Retained ids are not proof.
                    physicallyResolvedIDs = []
                    proofFailure = "Route proof is unavailable, so these records stay savable and unproven."
                }
            }
            guard !Task.isCancelled, identity == routeIdentity, generation == draftGeneration else { return }
        }
        physicallyResolvedCorridorIDs = physicallyResolvedIDs
        routeProofFailure = proofFailure
        plannedIdentity = identity
        corridorGeometry = geometry
        outcome = publishedResult
        corridorsRemovedByDate = removedByDate
        searching = false
        if case .corridors(let corridors) = publishedResult {
            if let previousSelectedCorridorID,
               corridors.contains(where: { $0.id == previousSelectedCorridorID }) {
                selectedCorridorID = previousSelectedCorridorID
            } else if corridors.count == 1 {
                selectedCorridorID = corridors[0].id
            }
        }
        // Build the drawn routes now, not in a later onChange, so the fit
        // below frames the new routes rather than the previous set.
        refreshDrawnRoutes()
        // Frame the route once per set of stations; a time or train edit
        // replans without moving a camera the reader may have panned.
        if routeFitIdentity != endpointIdentity {
            routeFitIdentity = endpointIdentity
            mapFitRevision += 1
        }
    }

    private func commit() { commit(confirmedRemoval: false) }

    private func commit(confirmedRemoval: Bool) {
        guard canSave else { return }
        var result: Train
        if let timetableTrain {
            result = timetableResult(timetableTrain)
            applyPendingPlatforms(to: &result, span: timetableRideSpan)
        } else if routeEdited {
            guard let corridor = selectedCorridor, let drafted = corridorDraft(for: corridor) else {
                autofillFailed = true
                return
            }
            let dropped = corridorConflicts(corridor)
            if !confirmedRemoval, !dropped.isEmpty {
                removal = RemovalRequest(action: .save, stations: dropped.map(\.name))
                return
            }
            result = drafted
            applyPendingPlatforms(to: &result)
        } else {
            result = draft
            // An untouched legacy record keeps having no region field.
            if train.region != nil || region != Region.resolved(train) { result.region = region.code }
            applyHeader(to: &result)
        }
        let blocking = RideDraftValidation.issues(
            for: result, originalID: train.id, existingIDs: itineraries?.trainIDs ?? []).blocking
        guard blocking.isEmpty else {
            saveIssues = blocking
            return
        }
        saveIssues = []
        onSave(result)
    }

    private func timetableResult(_ timetable: Train) -> Train {
        var result = timetable
        carryDetails(from: draft, into: &result)
        result.region = region.code
        let serviceDate = result.date ?? dayString(departure)
        result.date = serviceDate
        if timetableTrainTypeChanged { result.trainType = trainType }
        let span = timetableRideSpan ?? 0...(result.stops.count - 1)
        for index in result.stops.indices {
            result.stops[index].rideSegment = span.contains(index) && isRidden
        }
        let pickerDeparture = clock(
            departure, extraDays: extraDays(from: serviceDate, to: departure))
        if result.stops[span.lowerBound].departure != pickerDeparture {
            result.stops[span.lowerBound].departure = pickerDeparture
        }
        let pickerArrival = clock(
            arrival, extraDays: extraDays(from: serviceDate, to: arrival))
        if result.stops[span.upperBound].arrival != pickerArrival {
            result.stops[span.upperBound].arrival = pickerArrival
        }
        // The header shows a saved journey's own number and operator. Only a
        // value the reader changed outranks the timetable's.
        if !companyName.isEmpty, companyName != seed.company {
            commitCompany(companyName, on: &result)
        }
        let typed = trainNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let number = typed == seed.number.trimmingCharacters(in: .whitespacesAndNewlines) ? "" : typed
        result.number = [number, result.number, limitedExpressName,
                         result.routeSections?.first?.lineNames?.first ?? originLine?.name ?? ""]
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
        result.origin = result.stops[span.lowerBound].name
        result.destination = result.stops[span.upperBound].name
        return result
    }

    /// Fields only the details sections edit. A timetable replaces the route
    /// and the service, never these.
    private func carryDetails(from source: Train, into result: inout Train) {
        result.id = source.id
        result.notes = source.notes
        result.journeyGroup = source.journeyGroup
        result.style = source.style
        result.visible = source.visible
        // The timetable sets these from the service. Keep the draft's only
        // when the reader typed them in this session.
        if source.numberEn != train.numberEn { result.numberEn = source.numberEn }
        if source.vehicleType != train.vehicleType { result.vehicleType = source.vehicleType }
        if source.direction != train.direction { result.direction = source.direction }
    }

    /// Header fields of a saved journey are written back only when the
    /// reader changed them. A placeholder clock (none was saved and the
    /// reader did not set one) is never written.
    private func applyHeader(to result: inout Train) {
        let last = result.stops.count - 1
        let serviceDate = headerServiceDate()
        if departureTouched {
            result.date = serviceDate
            if last >= 1, seed.departureKnown
                || clock(departure, extraDays: 0) != clock(seed.departure, extraDays: 0) {
                result.stops[0].departure = clock(
                    departure, extraDays: extraDays(from: serviceDate, to: departure))
            }
        }
        if arrivalTouched, last >= 1, seed.arrivalKnown
            || clock(arrival, extraDays: 0) != clock(seed.arrival, extraDays: 0) {
            result.stops[last].arrival = clock(
                arrival, extraDays: extraDays(from: serviceDate, to: arrival))
        }
        let number = trainNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        if number != seed.number.trimmingCharacters(in: .whitespacesAndNewlines), !number.isEmpty {
            result.number = number
        }
        if trainType != seed.trainType { result.trainType = trainType.isEmpty ? nil : trainType }
        if companyName != seed.company { commitCompany(companyName, on: &result) }
        if let riddenOverride { result = RideLedger.setRidden(result, riddenOverride) }
    }

    /// The saved service day, moved by as many days as the reader moved the
    /// departure. A first departure after midnight ("24:30") stays on the
    /// day the service started, not on the calendar day it left.
    private func headerServiceDate() -> String {
        let saved = Dates.normalizeDateString(draft.date)
        guard departureTouched else { return saved ?? dayString(departure) }
        let calendar = Calendar.current
        let moved = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: seed.departure),
            to: calendar.startOfDay(for: departure)).day ?? 0
        return saved.flatMap { Dates.addDays($0, moved) } ?? dayString(departure)
    }

    /// Recorded stops of a saved journey that this corridor does not pass.
    private func corridorConflicts(_ corridor: TripRoutePlanner.Corridor) -> [Stop] {
        guard hasRecordRoute, draft.stops.count >= 2 else { return [] }
        return LocalJourneyAutofill.proposal(train: draft, choice: corridor.choice)?.conflictingStops ?? []
    }

    /// Build exactly the candidate that saving this corridor would persist.
    /// A saved journey keeps its visits that the new route still passes,
    /// with their clocks; only the route between them is replaced.
    private func corridorDraft(for corridor: TripRoutePlanner.Corridor) -> Train? {
        guard let origin, let destination else { return nil }
        var result = draft
        result.region = region.code
        if !hasRecordRoute || result.stops.count < 2 {
            // Same mapping StationPickerView uses: CatalogStation.key.sourceCode.
            result.stops = [
                endpointStop(origin, stationID: originStationID, stopType: "origin", ridden: isRidden),
                endpointStop(destination, stationID: destinationStationID, stopType: "destination", ridden: isRidden),
            ]
        }
        // Physical confirmation comes from the resolver result for this exact planning input.
        guard let proposal = LocalJourneyAutofill.proposal(train: result, choice: corridor.choice),
              proposal.train.stops.count >= 2 else { return nil }
        result = proposal.train
        result.routeConfirmation = plannedIdentity == routeIdentity
            && physicallyResolvedCorridorIDs.contains(corridor.id) ? .confirmed : .pending
        result.region = region.code
        let last = result.stops.count - 1
        for (index, station, stationID) in [(0, origin, originStationID), (last, destination, destinationStationID)]
        where result.stops[index].n02StationCode == station.key.sourceCode && stationID != nil
            && result.stops[index].stationID != stationID {
            RegistryStationSelection.fill(
                &result.stops[index], regionCode: region.code, sourceCode: station.key.sourceCode,
                catalogName: station.name, stationID: stationID)
        }
        if !hasRecordRoute {
            result.date = dayString(departure)
            result.stops[0].departure = clock(departure, extraDays: 0)
            result.stops[last].arrival = clock(arrival, extraDays: extraDays(from: departure, to: arrival))
            result.trainType = trainType
            let typedNumber = trainNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            result.number = typedNumber.isEmpty
                ? (corridor.lineNames.first ?? originLine?.name ?? "")
                : typedNumber
        } else {
            applyHeader(to: &result)
            if result.number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.number = corridor.lineNames.first ?? originLine?.name ?? ""
            }
        }
        if companyName.isEmpty, !hasRecordRoute || seed.company.isEmpty {
            let joined = corridor.operatorNames.filter { !$0.isEmpty }.joined(separator: "・")
            commitCompany(joined, on: &result)
        } else if !hasRecordRoute {
            commitCompany(companyName, on: &result)
        }
        result.origin = origin.name
        result.destination = destination.name
        return result
    }

    private func stationCountText(_ corridor: TripRoutePlanner.Corridor) -> String {
        let count = String(corridor.passStationCount)
        guard plannedIdentity == routeIdentity,
              physicallyResolvedCorridorIDs.contains(corridor.id),
              let kilometers = kilometerString(corridor.distanceKm) else {
            return text("stationCount", fallback: "{count} stations", ["count": .string(count)])
        }
        return text(
            "stationCountDistance",
            fallback: "{count} stations · {km} km",
            ["count": .string(count), "km": .string(kilometers)])
    }

    private func junctionBadge(_ junction: TripRoutePlanner.Junction) -> String? {
        let station = localization.stationName(junction.stationName, code: junction.stationCode, region: region)
        switch junction.link {
        case .throughService:
            return text(
                "throughService",
                fallback: "Through service at {station}",
                ["station": .string(station)])
        case .none:
            return text("unverifiedConnection", fallback: "Unverified connection at {station}",
                        ["station": .string(station)])
        case .sameLine:
            return nil
        }
    }

    private func lineChangeCaption(
        for visit: RailwayRouteChoices.Visit,
        junctions: [TripRoutePlanner.Junction]
    ) -> String? {
        let captions = junctions.filter { $0.stationCode == visit.code }.map { junction in
            text(
                "lineChange",
                fallback: "{from} → {to}",
                ["from": .string(junction.fromLineName), "to": .string(junction.toLineName)])
        }
        guard !captions.isEmpty else { return nil }
        return captions.joined(separator: "\n")
    }

    private func disconnectedMessage(_ junctions: [TripRoutePlanner.Junction]) -> String {
        let changes = junctions.map { junction in
            text(
                "changeAt",
                fallback: "{station} ({from} → {to})",
                [
                    "station": .string(localization.stationName(
                        junction.stationName, code: junction.stationCode, region: region)),
                    "from": .string(junction.fromLineName),
                    "to": .string(junction.toLineName),
                ])
        }.joined(separator: "\n")
        let lead = text(
            "disconnected",
            fallback: "These lines are not connected — one train cannot run this way. Change trains at: {changes}",
            ["changes": .string(changes)])
        return lead + "\n" + text("addLegs", fallback: "Add each leg as its own trip.")
    }

    private func dayString(_ date: Date) -> String {
        RecordDate.text(from: date)
    }

    /// Hours run past 24 when arrival falls on a later calendar day (`25:10`).
    private func clock(_ date: Date, extraDays: Int) -> String {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date) + extraDays * 24
        let minute = calendar.component(.minute, from: date)
        return String(format: "%02d:%02d", hour, minute)
    }

    private func extraDays(from departure: Date, to arrival: Date) -> Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: departure)
        let end = calendar.startOfDay(for: arrival)
        return max(0, calendar.dateComponents([.day], from: start, to: end).day ?? 0)
    }

    private func extraDays(from serviceDate: String, to date: Date) -> Int {
        guard let serviceDay = timetableDate(serviceDate, time: "00:00") else { return 0 }
        return extraDays(from: serviceDay, to: date)
    }

    private func kilometerString(_ kilometers: Double) -> String? {
        guard kilometers > 0 else { return nil }
        let rounded = (kilometers * 10).rounded() / 10
        guard rounded > 0 else { return nil }
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(format: "%.1f", rounded)
    }

    private func text(
        _ key: String,
        fallback: String,
        _ params: [String: Localization.Param]? = nil
    ) -> String {
        localization.text("ios.newTrip.\(key)", params: params, fallback: fallback)
    }
}
