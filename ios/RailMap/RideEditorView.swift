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
    @State private var draft: Train
    /// Editor-session identity for stops. `Stop` is a canonical value without
    /// an id, but these rows can be inserted, deleted and moved; tying SwiftUI
    /// identity to their array offsets moves navigation/focus state to a
    /// different stop whenever the order changes.
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
    /// Catalog for station resolution and draft-pin coordinates. Nil until loaded.
    @State private var editorCatalog: EditorCatalog?
    /// Stable catalog identity for route choices during this editor session.
    /// The document schema stores line/operator names, so these ids are mapped
    /// back only when committing the picker.
    @State private var selectedCatalogLineIDs: Set<String> = []
    /// Cross-border journeys can carry station codes from more than one
    /// package. Keep those small, cached catalogs available for draft pins.
    @State private var editorCatalogs: [String: EditorCatalog] = [:]
    @State private var draftMapRevision = 0
    @State private var publishedDraftPins: [DraftStopPin]?
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
        _draft = State(initialValue: train)
        _stopIDs = State(initialValue: train.stops.map { _ in UUID() })
        self.onSave = onSave
        self.onCancel = onCancel
        self.onDraftMap = onDraftMap
        self.highlightedStopID = highlightedStopID
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                Form {
                    if isNew {
                        wizardHeader
                        switch step {
                        case .region:
                            Section { regionPicker }
                        case .route:
                            stopsSection
                            Section { lineSelectionRow }
                        case .service:
                            Section { numberFields }
                            searchableDetailsSection
                            Section {
                                DisclosureGroup(localization.editorText("ios.editor.optionalDetails"),
                                                isExpanded: $showsOptionalDetails) { serviceDetails }
                            }
                        case .date:
                            Section { dateFields }
                            journeyStatusSection
                        case .confirm:
                            confirmationSections
                        }
                        if step != .region { completionSection }
                        if (showsValidation || step == .confirm) && !presentedBlocking.isEmpty { problemSummary(proxy) }
                    } else {
                        if !blocking.isEmpty { problemSummary(proxy) }
                        basicsSection
                        stationsSection
                        stopsSection
                        searchableDetailsSection
                        journeyStatusSection
                        routingSection
                        styleSection
                        recordSection
                        completionSection
                    }
                }
                // Inline, and short. §14.5 forbids a fixed English-width
                // assumption, and the large title fought both toolbar buttons
                // for the same row and lost — 「乗車記録を編集」 came back as
                // 「乗車記録…」, a heading truncated to a stub. The specific
                // verb the spec asks for is on the SAVE button, which is where
                // it does work; this row only has to say which surface this is.
                    if isNew { wizardNavigation(proxy) }
                }
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
                        StopEditorView(stop: $draft.stops[index], index: index,
                                       region: Region.resolved(draft), allowsEndpointRoles: !isNew,
                                       selectedLineIDs: selectedCatalogLineIDs,
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
                .onChange(of: draft, initial: true) { _, _ in revalidate() }
                .onChange(of: draft.stops, initial: true) { _, _ in publishDraftMap() }
                .onChange(of: stopIDs) { _, _ in publishDraftMap() }
                .onChange(of: highlightedStopID.wrappedValue) { _, id in
                    guard let id, stopIDs.contains(id) else { return }
                    addedStopID = id
                    highlightedStopID.wrappedValue = nil
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
                        selectedCatalogLineIDs = Set(matched.lineIDs)
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
                            guard blocking.isEmpty else { return }
                            onSave(draft)
                        }
                        .accessibilityIdentifier("rideEditorSave")
                        // §7.6: the primary action takes the one filled
                        // emphasis on the screen. Cancel and Save were the
                        // same glass capsule with the same white label at the
                        // same weight, so the row said nothing about which of
                        // the two commits the reader's work — and the two sit
                        // a thumb's width apart.
                        .buttonStyle(.borderedProminent)
                        .disabled(!blocking.isEmpty)
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
                    undoableDeletion = []
                    pendingRegion = nil
                    prefillRidden(forDate: draft.date)
                }
                Button(localization.editorText("ios.editor.keepEditing"), role: .cancel) { pendingRegion = nil }
            } message: { _ in Text(localization.editorText("ios.editor.changeRegionNote")) }
        .sheet(isPresented: $showsAICompletion) {
            JourneyCompletionView(
                trains: [draft],
                allowsRawImport: true,
                onApply: { completed in
                    guard let train = completed.first else { return }
                    draft = train
                })
        }
        .confirmationDialog(
            "既存の駅を置き換えますか？", isPresented: $showsReplaceStopsConfirmation, titleVisibility: .visible
        ) {
            Button("置き換える", role: .destructive) { showsServicePatternPicker = true }
            Button("キャンセル", role: .cancel) {}
        }
        .sheet(isPresented: $showsServicePatternPicker) {
            servicePatternPicker
        }
        .interactiveDismissDisabled(draft != original)
    }

    private var servicePatternPicker: some View {
        ServicePatternPickerView(
            region: Region.resolved(draft).code,
            rideDate: draft.date.flatMap { $0.isEmpty ? nil : $0 }
        ) { pattern, reversed in
            let ridden = RideLedger.hasBeenRidden(draft)
            draft = TrainServicePatterns.apply(pattern, to: draft, reversed: reversed, ridden: ridden)
            stopIDs = draft.stops.map { _ in UUID() }
            undoableDeletion = []
            addedStopID = nil
        }
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
        let denial = RideEditorAI.denial(
            train: draft, catalog: editorCatalog, requestInFlight: showsAICompletion)
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
        guard pins != publishedDraftPins else { return }
        publishedDraftPins = pins
        draftMapRevision += 1
        onDraftMap(DraftMapPins.snapshot(revision: draftMapRevision, pins: pins))
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
                        Text(localization.editorText("ios.editor.previous")).fixedSize()
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
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("rideEditorNext")
            } else {
                Button {
                    guard blocking.isEmpty else { return }
                    onSave(draft)
                } label: {
                    Text(dynamicTypeSize.isAccessibilitySize
                        ? localization.text("ios.save", fallback: "Save")
                        : localization.editorText("ios.editor.saveJourney"))
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(maxWidth: .infinity)
                }
                .accessibilityLabel(localization.editorText("ios.editor.saveJourney"))
                .buttonStyle(.borderedProminent)
                .disabled(!blocking.isEmpty)
                .accessibilityIdentifier("rideEditorSave")
                .keyboardShortcut("s", modifiers: .command)
            }
        }
        .controlSize(.large)
        .padding(.horizontal).padding(.vertical, 10)
        .background(.bar)
    }

    @ViewBuilder private var confirmationSections: some View {
        Section(localization.editorText("ios.editor.step.route")) {
            LabeledContent(localization.countryText("country.label", fallback: "Region"),
                value: localization.text(Region.resolved(draft).localizationKey,
                                         fallback: Region.resolved(draft).fallbackName))
            ForEach(Array(draft.stops.enumerated()), id: \.offset) { index, stop in
                LabeledContent("\(index + 1)", value: stop.name)
            }
            if let names = draft.routePolicy?.preferredLineNames, !names.isEmpty {
                LabeledContent(localization.editorText("ios.editor.searchLines"), value: names.joined(separator: " · "))
            }
        }
        Section(localization.editorText("ios.editor.step.service")) {
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
                        date: $draft.date,
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

    private var serviceDetails: some View {
        Group {
            // Optional, so it has no issue anchor and shares no focus identity
            // with the required caption above it.
            EditorTextField(
                title: localization.countryText("field.numberEn", fallback: "English name"),
                text: optionalText(\.numberEn))
            .accessibilityIdentifier("rideEditorNumberEn")

            EditorTextField(
                title: localization.countryText("field.direction", fallback: "Direction"),
                text: optionalText(\.direction))

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
            EditorSearchField(
                title: localization.countryText("field.trainType", fallback: "Train type"),
                text: optionalText(\.trainType),
                suggestions: regionalHistory.compactMap(\.trainType) + defaultServiceTypes)
                .accessibilityIdentifier("rideEditorTrainType")
            EditorSearchField(
                title: localization.editorText("ios.editor.vehicleType"),
                text: optionalText(\.vehicleType),
                suggestions: regionalHistory.compactMap(\.vehicleType))
                .accessibilityIdentifier("rideEditorVehicleType")
            if !isNew { lineSelectionRow }
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

    private var lineSelectionRow: some View {
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
            ForEach(stopIDs, id: \.self) { stopID in
                if let index = stopIDs.firstIndex(of: stopID) {
                    VStack(alignment: .leading, spacing: 4) {
                        NavigationLink {
                            StopEditorView(
                                stop: $draft.stops[index], index: index,
                                region: Region.resolved(draft), allowsEndpointRoles: !isNew,
                                selectedLineIDs: selectedCatalogLineIDs,
                                       onRiddenChange: { riddenIsTheReaders = true })
                        } label: {
                            StopEditorLabel(
                                stop: draft.stops[index], index: index + 1,
                                emptyTitle: isNew ? localization.editorText(index == 0
                                    ? "ios.editor.chooseOrigin" : index == stopIDs.count - 1
                                    ? "ios.editor.chooseDestination" : "ios.editor.untitledStop") : nil)
                        }
                        .accessibilityIdentifier("rideEditorStop-\(index)")
                        fieldIssues(.stop(index))
                    }
                    .id(stopID)
                }
            }
            .onDelete(perform: deleteStops)
            .onMove(perform: moveStops)

            if !undoableDeletion.isEmpty { undoBanner }

            if Region.resolved(draft).code == "jp" {
                Button {
                    if draft.stops.contains(where: { !$0.name.isEmpty }) {
                        showsReplaceStopsConfirmation = true
                    } else {
                        showsServicePatternPicker = true
                    }
                } label: {
                    Label("特急から駅を入力", systemImage: "train.side.front.car")
                }
                .accessibilityIdentifier("rideEditorServicePattern")
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

    private func deleteStops(at offsets: IndexSet) {
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
                        section: routeSection(at: index), region: Region.resolved(draft))
                        .environment(localization)
                } label: {
                    RouteSectionLabel(
                        section: draft.routeSections?[index], index: index + 1,
                        region: Region.resolved(draft),
                        localization: localization)
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
            case .service: return issue.field == .number
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

    private func optionalText(_ keyPath: WritableKeyPath<Train, String?>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] ?? "" },
            set: { draft[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
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

    var body: some View {
        Form {
            Section(localization.editorText("ios.editor.endpoints")) {
                EditorTextField(
                    title: localization.editorText("ios.editor.fromStation"),
                    text: optionalText(\.from))
                NavigationLink {
                    StationPickerView(regionCode: region.code) { station in
                        section.from = station.name
                        section.fromN02StationCode = station.key.sourceCode
                    }
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
                    StationPickerView(regionCode: region.code) { station in
                        section.to = station.name
                        section.toN02StationCode = station.key.sourceCode
                    }
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

            Section(localization.editorText("ios.editor.branchService")) {
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
                    if let arrival = stop.arrival, !arrival.isEmpty { Text(arrival) }
                    if let departure = stop.departure, !departure.isEmpty { Text(departure) }
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
}

/// Station-and-time gate shared by the AI button and the completion sheet.
private enum RideEditorAI {
    static func denial(train: Train, catalog: EditorCatalog?, requestInFlight: Bool) -> EditorAIDenial? {
        let region = Region.resolved(train).code
        let stops = train.stops.map { stop in
            let code = stop.n02StationCode ?? ""
            let resolved = code.isEmpty == false
                && catalog?.station(StationKey(regionCode: region, sourceCode: code)) != nil
            func field(_ text: String?) -> EditorTimeInput {
                guard let text, text.isEmpty == false else {
                    return EditorTime.input("", confirmed: false)
                }
                return EditorTime.input(text, confirmed: true)
            }
            return EditorAIStop(
                occurrenceID: UUID(),
                stationResolved: resolved,
                arrival: field(stop.arrival),
                departure: field(stop.departure))
        }
        return EditorAIEligibility.denial(
            stops: stops, providerAvailable: true, requestInFlight: requestInFlight)
    }
}

private struct StopEditorView: View {
    @Environment(AppLocalization.self) private var localization
    @Binding var stop: Stop
    let index: Int
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
                }
                if stop.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(localization.editorText("ios.editor.stationGuide"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if stop.n02StationCode?.isEmpty != false {
                    Text(localization.editorText("ios.editor.stationUnmatched"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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
                    StationPickerView(regionCode: region.code, selectedLineIDs: selectedLineIDs) { station in
                        stop.name = station.name
                        stop.n02StationCode = station.key.sourceCode
                    }
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

            Section {
                if stop.stopType == "pass_through" {
                    EditorTimeField(
                        title: localization.editorText("ios.editor.passTime"),
                        time: $stop.departure)
                    if let arrival = stop.arrival, arrival.isEmpty == false {
                        EditorTimeField(
                            title: localization.countryText("popup.arrival", fallback: "Arrival"),
                            time: $stop.arrival)
                    }
                } else {
                    EditorTimeField(
                        title: localization.countryText("popup.arrival", fallback: "Arrival"),
                        time: $stop.arrival)
                    EditorTimeField(
                        title: localization.countryText("popup.departure", fallback: "Departure"),
                        time: $stop.departure)
                }
            } header: {
                Text(localization.editorText("ios.editor.times"))
            } footer: {
                // §7.3 / §10.4: an overnight time is written past 24:00 and
                // kept that way. Nothing here reformats it into a date.
                Text(localization.editorText("ios.editor.crossDayHint"))
            }
        }
        .task(id: region.code) {
            let region = region
            do {
                catalog = try await Task.detached(priority: .userInitiated) {
                    try loadCatalog(for: region)
                }.value
            } catch {
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
                stations.filter { station in
                    station.name.localizedStandardContains(query)
                        || station.aliases.contains { $0.localizedStandardContains(query) }
                }
                .sorted { lhs, rhs in
                    if lhs.name != rhs.name { return lhs.name < rhs.name }
                    return lhs.key.sourceCode < rhs.key.sourceCode
                }
                .prefix(6)
            }.value
            guard !Task.isCancelled else { return }
            stationMatches = Array(found)
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

private struct CatalogStationRow: Identifiable, Hashable, Sendable {
    var station: CatalogStation
    var subtitle: String
    var id: String { station.key.sourceCode }
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

/// Catalog stations for one region. Empty search is a company → line → station
/// browser. Search results keep those categories instead of flattening stations
/// with the same display name into one ambiguous list.
private struct StationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppLocalization.self) private var localization
    let regionCode: String
    var selectedLineIDs: Set<String> = []
    let onSelect: (CatalogStation) -> Void
    @State private var query = ""
    @State private var prepared: [CatalogStationRow] = []
    @State private var preparedLineGroups: [CatalogStationLineGroup] = []
    @State private var matches: [CatalogStationRow] = []
    @State private var didLoad = false
    @State private var loadError: String?
    @State private var filterTask: Task<Void, Never>?

    private static let debounce = Duration.milliseconds(120)

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
                    if matchedLineGroups.isEmpty {
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
                }
            }
        }
        .navigationTitle(localization.editorText("ios.editor.chooseStation"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $query, placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(localization.editorText("ios.editor.stationSearch")))
        .task(id: regionCode) {
            guard let region = Region(rawValue: regionCode) else {
                loadError = EditorCatalogLoadError.missingResource(regionCode).localizedDescription
                return
            }
            do {
                let catalog = try await Task.detached(priority: .userInitiated) {
                    try loadCatalog(for: region)
                }.value
                guard !Task.isCancelled else { return }
                let lineIDs = selectedLineIDs
                let result = await Task.detached(priority: .userInitiated) {
                    Self.prepare(
                        catalog: catalog, regionCode: regionCode, selectedLineIDs: lineIDs)
                }.value
                prepared = result.rows
                preparedLineGroups = result.groups
                didLoad = true
                apply(query: query)
            } catch {
                loadError = error.localizedDescription
            }
        }
        .onChange(of: query) { _, needle in
            apply(query: needle)
        }
        .onDisappear { filterTask?.cancel() }
    }

    @ViewBuilder
    private func stationButton(_ row: CatalogStationRow) -> some View {
        Button { select(row.station) } label: {
            CatalogStationLabel(row: row)
        }
        .buttonStyle(RailRowPressStyle(cornerRadius: 0))
        .accessibilityIdentifier("rideEditorStation-\(row.station.key.sourceCode)")
    }

    private func select(_ station: CatalogStation) {
        onSelect(station)
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

    private nonisolated static func filter(
        _ rows: [CatalogStationRow], needle: String
    ) -> [CatalogStationRow] {
        rows.filter {
            $0.station.name.localizedStandardContains(needle)
                || $0.station.aliases.contains { $0.localizedStandardContains(needle) }
                || $0.station.key.sourceCode.localizedStandardContains(needle)
        }
    }

    private func apply(query: String) {
        filterTask?.cancel()
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else {
            matches = prepared
            return
        }
        let source = prepared
        filterTask = Task { @MainActor in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            let found = await Task.detached(priority: .userInitiated) {
                Self.filter(source, needle: needle)
            }.value
            guard !Task.isCancelled else { return }
            matches = found
        }
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
        return Array(Set(suggestions.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }))
            .filter { query.isEmpty || $0.localizedStandardContains(query) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .prefix(6).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            EditorField(title: title) {
                TextField(title, text: $text, prompt: Text(prompt ?? title))
                    .focused($hasFocus)
                    .submitLabel(.done)
                    .onSubmit { hasFocus = false }
                    .autocorrectionDisabled()
            }
            if hasFocus {
                ForEach(matches, id: \.self) { value in
                    Button {
                        text = value
                        hasFocus = false
                    } label: {
                        Label(value, systemImage: "arrow.up.left")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("editorSuggestion-\(value)")
                }
            }
        }
        .onChange(of: hasFocus) { _, active in
            guard let focus, let field else { return }
            if active { focus.wrappedValue = field }
            else if focus.wrappedValue == field { focus.wrappedValue = nil }
        }
        .onChange(of: focus?.wrappedValue) { _, value in
            if let field { hasFocus = value == field }
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
        guard !needle.isEmpty else { return candidateLines }
        return candidateLines.filter { line in
            line.name.localizedStandardContains(needle)
                || line.aliases.contains { $0.localizedStandardContains(needle) }
                || line.operatorIDs.contains {
                    (operatorNameByID[$0] ?? "").localizedStandardContains(needle)
                }
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
