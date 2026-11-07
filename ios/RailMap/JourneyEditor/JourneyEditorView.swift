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
///
/// The draft and its planning live in `TripDraftModel`; this view is the
/// shell: header, map, the form's sections, the sheets, and the events
/// that keep the model's derived state current.
struct JourneyEditorView: View, JourneyEditorLabelling {
    @Environment(AppLocalization.self) var localization
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

    /// Alternatives drawn on the map. Each is an overlay with its own track;
    /// more than this is clutter on a phone and memory for nothing.
    nonisolated static let maximumDrawnRoutes = 4

    @State var model: TripDraftModel
    @State private var showsDiscardConfirmation = false
    /// The reader's usual values on this route, offered under empty fields.
    @State private var historySuggestions: [TripDraftModel.Field: String] = [:]

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
        _model = State(initialValue: TripDraftModel(train: train, isNew: isNew))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                EditorMapPanel(model: model)
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
        .interactiveDismissDisabled(model.isDirty(original: train))
        .onChange(of: model.draft, initial: true) { _, value in
            model.detailIssues = RideDraftValidation.issues(
                for: value, originalID: train.id, existingIDs: itineraries?.trainIDs ?? [])
            model.saveIssues = []
        }
        .onChange(of: [model.draft.stops.first?.n02StationCode, model.draft.stops.last?.n02StationCode]) { _, _ in
            // A stop edited to another station moves the saved route's end.
            if model.showsRecordRoute, let catalog = model.catalog { model.seedStations(from: catalog) }
        }
        .task(id: TripDraftModel.RecordGeometryKey(
            sections: model.showsRecordRoute ? model.draft.routeSections ?? [] : [], loaded: model.package != nil)) {
            await model.loadRecordGeometry()
        }
        // Waits for the package, the seeded stations and the route status:
        // a status still resolving has no gaps yet, and a later one retries.
        .task(id: [model.package != nil, model.seededStationIdentity != nil, repairGaps != nil]) {
            guard startsWithRouteRepair, !model.repairStarted, model.package != nil,
                  model.seededStationIdentity != nil, repairGaps != nil else { return }
            model.startRepair(gaps: repairGaps, text: repairText)
        }
        .confirmationDialog(
            localization.text("ios.routeGuide.removalTitle"),
            isPresented: Binding(get: { model.removal != nil }, set: { if !$0 { model.removal = nil } }),
            titleVisibility: .visible,
            presenting: model.removal
        ) { request in
            Button(localization.text("ios.routeGuide.removeAndApply"), role: .destructive) {
                model.removal = nil
                switch request.action {
                case .save: commit(confirmedRemoval: true)
                case .repair(let index): model.chooseRepair(index, confirmedRemoval: true, text: repairText)
                }
            }
            .accessibilityIdentifier("newTripRemoveStops")
            Button(localization.text("ios.cancel", fallback: "Cancel"), role: .cancel) { model.removal = nil }
        } message: { request in
            Text(localization.text("ios.routeGuide.removalDetail",
                                   params: ["stations": .string(request.stations.joined(separator: "、"))]))
        }
        .onChange(of: model.repair.pause) { _, pause in
            model.refreshDrawnRoutes()
            if pause != nil { model.mapFitRevision += 1 }
        }
        .onChange(of: model.showsRecordRoute) { _, _ in model.refreshDrawnRoutes() }
        .task(id: model.directionKey) { await model.loadDirections(original: train) }
        // Closing the editor stops a running repair search at once.
        .onDisappear { model.repair.cancel() }
        .sheet(isPresented: $model.showsTicketScan) {
            if let region = model.ticketRegion {
                TicketScanView(region: region) { reading in model.fillFromTicket(reading) }
            }
        }
        .sheet(isPresented: $model.showsFillDetails) {
            EditorFillDetailsSheet(model: model, original: train)
        }
        .sheet(isPresented: $model.showsVehiclePicker) {
            VehiclePickerView(
                vehicleType: model.readerBinding(
                    .vehicleType, get: { model.draft.vehicleType }, set: { model.draft.vehicleType = $0 }),
                suggestions: model.vehicleSuggestions(among: suggestionTrains))
        }
        .sheet(item: $model.picking) { field in
            if let catalog = model.catalog {
                NavigationStack {
                    StationPickerView(
                        regionCode: model.region.code,
                        sourceCatalog: catalog,
                        companyFilter: model.companyName.isEmpty ? nil : model.companyName,
                        onSelectWithLine: { [generation = model.draftGeneration] station, line, stationID in
                            model.pick(station, line: line, stationID: stationID, for: field, generation: generation)
                        })
                }
            }
        }
        .onChange(of: model.departure) { _, newValue in
            model.departureChanged(to: newValue)
        }
        .onChange(of: model.dayString(model.departure), initial: true) { _, day in
            model.draftMapRevision += 1
            onDraftMap(DraftMapSnapshot(
                revision: model.draftMapRevision, pins: [], networkRideDate: day))
        }
        .onChange(of: model.arrival) { _, _ in
            model.saveIssues = []
        }
        .onChange(of: model.trainType) { _, _ in
            model.saveIssues = []
        }
        .onChange(of: model.trainNumber) { _, _ in
            model.saveIssues = []
        }
        .onChange(of: model.companyName) { _, _ in
            model.saveIssues = []
        }
        .task(id: model.region.code) {
            await SolverRegistryInput.awaitReady(region: model.region.code)
            model.registryEpoch += 1
        }
        .onChange(of: model.region) { _, _ in
            model.regionChanged()
        }
        .onChange(of: model.origin) { _, _ in
            model.allowUnverifiedConnections = false
            model.refreshCompanyCache()
        }
        .onChange(of: model.destination) { _, _ in
            model.allowUnverifiedConnections = false
            model.refreshCompanyCache()
        }
        .onChange(of: model.vias) { _, _ in
            model.allowUnverifiedConnections = false
        }
        .onChange(of: model.endpointIdentity) { _, _ in
            // Frame the trip as soon as an endpoint moves, before the route arrives.
            model.mapFitRevision += 1
        }
        .onChange(of: model.companyOptions) { _, options in
            if !model.companyName.isEmpty, !options.contains(model.companyName), model.companyName != model.seed.company {
                model.companyName = ""
            }
        }
        .onChange(of: model.selectedCorridorID) { _, _ in
            model.autofillFailed = false
            model.saveIssues = []
            model.refreshDrawnRoutes()
        }
        .onChange(of: model.outcome) { _, _ in model.refreshDrawnRoutes() }
        .onChange(of: model.timetableTrain != nil) { _, _ in model.refreshDrawnRoutes() }
        .task(id: model.region) { await model.loadRegion() }
        .task(id: model.catalog != nil) { model.locateNearbyStations() }
        .task(id: model.endpointIdentity) {
            historySuggestions = model.historySuggestions(among: suggestionTrains)
        }
        .onDisappear { model.ticketMatchTask?.cancel() }
        .task(id: model.routeIdentity) { await model.planRoute() }
#if DEBUG
        // UI tests stand in for the camera: the lines a scan would read.
        .task(id: model.catalog != nil) {
            guard isNew, model.catalog != nil, model.ticketFillCount == nil, let region = model.ticketRegion,
                  let raw = UITestLaunchConfiguration.current[.ticket], !raw.isEmpty else { return }
            let lines = raw.split(separator: "|").map { RecognizedLine(text: String($0)) }
            model.fillFromTicket(TicketParser.parse(lines: lines, region: region))
        }
        // Test control channel: lend this editor's own actions (AppControlHost).
        .modifier(AppControlEditorRegistration(handle: appControlHandle))
#endif
    }

    private var form: some View {
        Form {
            if model.loadFailed {
                Text(text(
                    "loadFailed",
                    fallback: "The rail data for this region could not be loaded."))
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Quick fill first, then the order a ticket reads: where, when,
            // which train, then what was ridden and what it cost.
            EditorQuickFillSection(model: model)
            EditorStationsSection(model: model)
            EditorTimeSection(model: model)
            EditorServiceSection(model: model, suggestions: historySuggestions)
            if model.timetableTrain != nil || model.hasRecordRoute || (model.origin != nil && model.destination != nil) {
                EditorRouteSection(model: model, original: train, reviewGaps: reviewGaps)
            }
            // A saved trip's stops belong with its route.
            JourneyEditorDetails(
                draft: $model.draft, region: model.region, showsStops: model.showsRecordRoute,
                suggestionTrains: suggestionTrains, issues: model.detailIssues,
                expanded: $model.detailsExpanded, part: .stops)
            EditorVehicleSection(model: model, suggestions: historySuggestions)
            EditorTicketSection(model: model)
            JourneyEditorDetails(
                draft: $model.draft, region: model.region, showsStops: model.showsRecordRoute,
                suggestionTrains: suggestionTrains, issues: model.detailIssues,
                expanded: $model.detailsExpanded, part: .more)
            if !model.saveIssues.isEmpty {
                Section {
                    ForEach(model.saveIssues) { issue in
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
        // Number pads (cars, car ridden, fare) have no Return key.
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(localization.text("ios.done", fallback: "Done")) {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .accessibilityIdentifier("newTripKeyboardDone")
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button(text("cancel", fallback: "Cancel")) {
                if model.isDirty(original: train) { showsDiscardConfirmation = true } else { onCancel() }
            }
            .accessibilityIdentifier("newTripCancel")
            Spacer(minLength: 8)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            Button(text("save", fallback: "Save")) { commit(confirmedRemoval: false) }
                .fontWeight(.semibold)
                .disabled(!model.canSave)
                // ⌘S is disabled by the same condition as the button.
                .keyboardShortcut("s", modifiers: .command)
                .accessibilityIdentifier("newTripSave")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func commit(confirmedRemoval: Bool) {
        model.commit(
            confirmedRemoval: confirmedRemoval, original: train,
            existingIDs: itineraries?.trainIDs ?? [], onSave: onSave)
    }

    // MARK: - saved route and repair

    /// Gaps the route status reported for the saved journey, while the draft
    /// still visits the same stations. Nil when nothing needs repair.
    private var repairGaps: [RouteRepair.Gap]? {
        reviewGaps?.map(RouteRepair.Gap.init)
    }

    private var reviewGaps: [SectionGap]? {
        guard !isNew, model.showsRecordRoute,
              model.draft.stops.count == train.stops.count,
              zip(model.draft.stops, train.stops).allSatisfy({
                  $0.n02StationCode == $1.n02StationCode && $0.name == $1.name
              }),
              let status = riddenRoutes?.status(
                  forTrainID: train.id,
                  pendingConfirmationIDs: itineraries?.pendingConfirmationIDs ?? []),
              case .needsReview(_, _, let gaps) = status, !gaps.isEmpty else { return nil }
        return gaps
    }
}

#if DEBUG
extension JourneyEditorView {
    /// This editor's own station assignment, planner state, section choice and
    /// save, for the test control channel; see `AppControlHost`.
    var appControlHandle: AppControlEditorHandle {
        AppControlEditorHandle(
            trainID: train.id, isNew: isNew,
            isReady: { (model.catalog != nil && model.package != nil && model.geometryCache != nil) || model.loadFailed },
            loadFailed: { model.loadFailed },
            region: { model.region.code },
            station: { query in
                let exact = model.mapStations.filter { $0.key.sourceCode == query }
                if !exact.isEmpty { return exact }
                let named = model.mapStations.filter { $0.name == query }
                return named.isEmpty ? model.mapStations.filter { $0.aliases.contains(query) } : named
            },
            setRoute: { from, to, via in
                if let from { model.assign(from, to: .origin, reduceMotion: reduceMotion) }
                if let to { model.assign(to, to: .destination, reduceMotion: reduceMotion) }
                if let via {
                    model.vias = []
                    for station in via { model.assign(station, to: .via, reduceMotion: reduceMotion) }
                }
            },
            setDay: { day in
                guard let target = RecordDate.date(from: day),
                      let current = RecordDate.date(from: model.dayString(model.departure)) else { return }
                model.departure = target.addingTimeInterval(model.departure.timeIntervalSince(current))
            },
            choose: { id, index in
                guard model.sections.indices.contains(index),
                      model.sections[index].candidates.contains(where: { $0.id == id }) else { return false }
                model.choose(id, inSection: index)
                return true
            },
            commit: { confirmed in commit(confirmedRemoval: confirmed) },
            snapshot: { appControlSnapshot },
            autofillProbe: { appControlAutofillProbe },
            fillTicket: { lines in
                guard let region = model.ticketRegion else { return ["error": "no paper tickets in this region"] }
                let reading = TicketParser.parse(lines: lines.map { RecognizedLine(text: $0) }, region: region)
                let written = model.fillFromTicket(reading)
                return [
                    "written": .number(Double(written)),
                    "filled": .object(model.filledBy.reduce(into: [:]) { result, item in
                        result[String(describing: item.key)] = .string(item.value.rawValue)
                    }),
                    "trainNumber": .string(model.trainNumber), "trainType": .string(model.trainType),
                    "origin": .string(model.origin?.name ?? ""), "destination": .string(model.destination?.name ?? ""),
                    "departure": .string(model.dayString(model.departure) + " " + model.clock(model.departure, extraDays: 0)),
                ]
            })
    }

    /// What `corridorDraft(for:)` hands `LocalJourneyAutofill.proposal` for the
    /// selected corridor, rebuilt without side effects, for diagnosing a save
    /// that ends in `autofillFailed`. Mirrors the endpoint replacement there.
    private var appControlAutofillProbe: AppControlJSON {
        func encode(_ value: some Encodable) -> AppControlJSON {
            (try? JSONEncoder().encode(value)).flatMap { try? JSONDecoder().decode(AppControlJSON.self, from: $0) } ?? .null
        }
        guard let corridor = model.selectedCorridor, let origin = model.origin, let destination = model.destination else {
            return ["selectedCorridor": .null, "hasRecordRoute": .bool(model.hasRecordRoute), "draft": encode(model.draft)]
        }
        var input = model.draft
        input.region = model.region.code
        let replaced = !model.hasRecordRoute || input.stops.count < 2
        if replaced {
            input.stops = [
                model.endpointStop(origin, stationID: model.originStationID, stopType: "origin", ridden: model.isRidden),
                model.endpointStop(destination, stationID: model.destinationStationID, stopType: "destination", ridden: model.isRidden),
            ]
        }
        let proposal = LocalJourneyAutofill.proposal(train: input, choice: corridor.choice)
        let sections = input.routeSections ?? []
        return [
            "hasRecordRoute": .bool(model.hasRecordRoute),
            "region": .string(model.region.code),
            "endpointsReplaced": .bool(replaced),
            "corridorID": .string(corridor.id),
            "corridorLineIDs": .array(corridor.choice.lineIDs.map { .string($0) }),
            "corridorSectionCount": .number(Double(corridor.choice.sectionCodes.count)),
            "draft": encode(model.draft),
            "input": encode(input),
            "inputRouteSectionCount": .number(Double(sections.count)),
            "inputFirstSection": sections.first.map(encode) ?? .null,
            "inputLastSection": sections.last.map(encode) ?? .null,
            "inputRouteConfirmation": encode(input.routeConfirmation),
            "proposalNil": .bool(proposal == nil),
            "proposalStopCount": .number(Double(proposal?.train.stops.count ?? -1)),
            "candidateTrainNil": .bool(model.candidateTrain(for: corridor) == nil),
            "corridorDraftNil": .bool(model.corridorDraft(for: corridor) == nil),
        ]
    }

    private var appControlSnapshot: AppControlEditorSnapshot {
        typealias Snapshot = AppControlEditorSnapshot
        let planned = model.plannedIdentity == model.routeIdentity
        let notices: [String] = [
            model.loadFailed ? "loadFailed" : nil,
            model.autofillFailed ? "autofillFailed" : nil,
            model.corridorsRemovedByDate ? "corridorsHiddenByDate" : nil,
            model.routeProofFailure.map { "routeProofFailure: \($0)" },
            model.historicalSaveAllowed ? "historicalSaveAllowed" : nil,
        ].compactMap { $0 }
        let sectionList = model.sections.enumerated().map { index, section in
            let (name, detail) = Snapshot.outcomeName(section.outcome)
            let notice: String? = switch model.historicalNotice(for: section) {
            case .info: "info"
            case .warning: "warning"
            case nil: nil
            }
            let probe: String? = switch section.historicalProbe {
            case .some(.historicalOnly): "historicalOnly"
            case .some(.none): "none"
            case nil: nil
            }
            return Snapshot.Section(
                key: section.key, index: index, from: section.fromName, to: section.toName, outcome: name, outcomeDetail: detail,
                candidates: section.candidates.map {
                    Snapshot.candidate($0, proven: section.proven, historical: section.historical)
                },
                chosen: model.choice(for: section), historicalNotice: notice, historicalProbe: probe,
                proofFailure: section.proofFailure, removedByDate: section.removedByDate)
        }
        let corridor = model.selectedCorridor
        let removalStations: [String]? = model.removal.flatMap { request -> [String]? in
            if case .save = request.action { return request.stations }
            return nil
        }
        return AppControlEditorSnapshot(
            trainID: train.id, isNew: isNew, region: model.region.code,
            ready: model.catalog != nil && model.package != nil, searching: model.searching, planned: planned,
            routeEdited: model.routeEdited, canSave: model.canSave, date: model.dayString(model.departure),
            origin: model.origin.map {
                Snapshot.Station(code: $0.key.sourceCode, name: $0.name, stationID: model.originStationID, lineID: model.originLine?.id)
            },
            destination: model.destination.map {
                Snapshot.Station(code: $0.key.sourceCode, name: $0.name, stationID: model.destinationStationID,
                                 lineID: model.destinationLine?.id)
            },
            vias: model.vias.map { Snapshot.Station(code: $0.station.key.sourceCode, name: $0.station.name) },
            sections: sectionList, pendingSections: model.pendingSections, selectedCorridorID: model.selectedCorridorID,
            joinedOutcome: model.outcome.map { Snapshot.outcomeName($0).0 },
            passStations: corridor?.choice.stations.map { Snapshot.Station(code: $0.code, name: $0.name) } ?? [],
            conflicts: corridor.map { model.corridorConflicts($0).map(\.name) } ?? [],
            removalPending: removalStations,
            notices: notices,
            saveIssues: model.saveIssues.map { "\($0.severity):\($0.field):\($0.literal ?? $0.key)" },
            sectionChoices: model.sectionChoices.reduce(into: [:]) { result, item in
                result[item.key.replacingOccurrences(of: "\u{1f}", with: "|")] = item.value
            },
            allowUnverifiedConnections: model.allowUnverifiedConnections,
            physicallyResolvedCorridorIDs: model.physicallyResolvedCorridorIDs.sorted(),
            trainType: model.trainType, company: model.companyName)
    }
}

/// Registers the open editor with the control channel while it is on screen.
private struct AppControlEditorRegistration: ViewModifier {
    let handle: AppControlEditorHandle
    @State private var token = UUID()
    func body(content: Content) -> some View {
        content
            .onAppear { AppControlHost.shared.register(editor: handle, token: token) }
            .onDisappear { AppControlHost.shared.unregister(editor: token) }
    }
}
#endif
