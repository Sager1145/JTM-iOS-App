import RailCore
import RailPresentation
import SwiftUI

/// The original journey card in a resizable presentation with a live map behind it.
struct WorkspaceJourneyMenu: View {
    @Bindable var itineraries: ItineraryStore
    let library: RideLibrary
    let controller: RailMapController
    @State private var recordID: String
    @State private var isSaving = false
    @State private var saveFailureDetail: String?
    @State private var showsDetails = false
    @State private var cardMorph = PanelMorph()
    @State private var menuMeasurements = MenuMeasurements()
    @State private var focusRequested = false
    @State private var detent: PresentationDetent = .height(WorkspaceMenuMetrics.journeyCompactHeight)
    @State private var tripNoteFlow = TripNoteFlow()
    /// The notes presenter of the details sheet. Held here, not by the sheet,
    /// so its draft survives the sheet stepping aside for a map pick.
    @State private var detailsNoteFlow = TripNoteFlow()
    @State private var detailsStepAside: TripNoteDetailsStepAside?
    /// The step-aside's own wait for a sheet to settle. Not the host's
    /// single slot: a later request there would cancel it mid-chain.
    @State private var stepAsideWait: Task<Void, Never>?
    @State private var hookToken = UUID()
    /// Which menu installed `controller.onTripNote` last, so a menu that is
    /// leaving never clears the hook of the one replacing it.
    @MainActor private static var hookOwner: UUID?
    @Environment(\.dismiss) private var dismiss
    @Environment(AppLocalization.self) private var localization
    @Environment(PresentationHost.self) private var presentationHost
    @Environment(RailNetworkStore.self) private var network
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let presentation: (Train) -> JourneyPresentation
    let onSave: (Train, String) -> JourneyEditing.Replaced
    let onRebuild: (Train) -> Int?
    let onPrimary: (JourneyPresentation.PrimaryAction, Train) -> Void
    let onSecondary: (SecondaryAction, Train) -> Void
    let onEditJourney: (Train) -> Void

    init(trainID: String, itineraries: ItineraryStore, library: RideLibrary, controller: RailMapController,
         presentation: @escaping (Train) -> JourneyPresentation,
         onSave: @escaping (Train, String) -> JourneyEditing.Replaced,
         onRebuild: @escaping (Train) -> Int?,
         onPrimary: @escaping (JourneyPresentation.PrimaryAction, Train) -> Void,
         onSecondary: @escaping (SecondaryAction, Train) -> Void,
         onEditJourney: @escaping (Train) -> Void) {
        self.itineraries = itineraries
        self.library = library
        self.controller = controller
        _recordID = State(initialValue: trainID)
        self.presentation = presentation
        self.onSave = onSave
        self.onRebuild = onRebuild
        self.onPrimary = onPrimary
        self.onSecondary = onSecondary
        self.onEditJourney = onEditJourney
    }

    private var train: Train? { itineraries.store?.trains.first { $0.id == recordID } }

    var body: some View {
        Group {
            if let train {
                RideCard(
                    train: train, presentation: presentation(train), dateChipTitle: train.date,
                    onClose: { dismiss() },
                    onPrimary: { action in
                        if action == .save { onEditJourney(train) }
                        else if action == .locate {
                            focusRequested = true
                            withAnimation(RailMotion.spring) { detent = lowestDetent }
                            focusIfReady()
                        } else { onPrimary(action, train) }
                    },
                    onSecondary: { action in
                        switch action {
                        case .edit: onEditJourney(train)
                        case .inspectDetails: showsDetails = true
                        default: onSecondary(action, train)
                        }
                    },
                    onSetRidden: { _ = save(RideLedger.setRidden(train, $0)) },
                    tripNoteFlow: tripNoteFlow)
                    .tripNotesPresentation(
                        flow: tripNoteFlow, train: train,
                        trains: itineraries.loaded?.trains ?? [],
                        onSet: { notes in
                            var edited = train
                            edited.setTripNotes(notes)
                            // Answers only once persistence has: a failed write
                            // is rolled back by `startSave`, and the form, still
                            // holding its draft, offers another try.
                            return await saveAwaitingPersistence(edited)
                        })
                    // The source panel's compact stage must not hide this card's body.
                    .environment(cardMorph)
                    .padding(.top, RailSpacing.s16)
                    .sheet(isPresented: $showsDetails) {
                        NavigationStack {
                            RideDetailView(
                                train: train, onSave: { save($0) },
                                onSaveAwaitingPersistence: { await saveAwaitingPersistence($0) },
                                onRebuild: { onRebuild(train) },
                                suggestionTrains: itineraries.loaded?.trains ?? [],
                                onEditJourney: { train in
                                    showsDetails = false
                                    presentationHost.afterTeardown { onEditJourney(train) }
                                },
                                tripNoteFlow: detailsNoteFlow)
                                .disabled(isSaving)
                                .alert(
                                    localization.countryText("ios.journey.saveFailedTitle", fallback: "Could not save this journey"),
                                    isPresented: Binding(get: { saveFailureDetail != nil },
                                        set: { if !$0 { saveFailureDetail = nil } })
                                ) {
                                    Button(localization.text("ios.done", fallback: "Done"), role: .cancel) {}
                                } message: {
                                    Text(saveFailureDetail ?? "")
                                }
                                .railSheetClose(
                                    Text(localization.text("ios.close", fallback: "Close")),
                                    identifier: "rideDetailClose"
                                ) { showsDetails = false }
                        }
                        .environment(localization)
                        .environment(network)
                        // The full ride detail, so it opens full height.
                        .railSheet(.full)
                    }
            }
        }
        .background(Color.railMenuBackground)
        .onGeometryChange(for: MenuMeasurements.self) { proxy in
            MenuMeasurements(height: proxy.size.height, bottomInset: proxy.safeAreaInsets.bottom)
        } action: { measurements in
            menuMeasurements = measurements
            controller.journeyMenuBottomObstruction = measurements.height + measurements.bottomInset
            focusIfReady()
        }
        .onAppear {
            installTripNoteHooks()
            if menuMeasurements.height > 0 {
                controller.journeyMenuBottomObstruction =
                    menuMeasurements.height + menuMeasurements.bottomInset
            }
        }
        .onDisappear {
            controller.journeyMenuBottomObstruction = nil
            // A pick belongs to the menu that started it.
            tripNoteFlow.reset()
            detailsNoteFlow.reset()
            // Before the pick is cancelled: its nil answer must not reopen
            // details on a menu that is leaving.
            detailsStepAside?.abandon()
            stepAsideWait?.cancel()
            controller.cancelTripNotePickIfOwned(trainID: recordID)
            tripNoteFlow.pickPlace = nil
            detailsNoteFlow.pickPlace = nil
            detailsStepAside = nil
            if Self.hookOwner == hookToken {
                controller.onTripNote = nil
                Self.hookOwner = nil
            }
        }
        #if !targetEnvironment(macCatalyst)
        .presentationDetents( // ui-token-ok: hand-built detents (spec §0.1 resident surfaces)
            dynamicTypeSize.isAccessibilitySize
                ? [.large] : [.height(WorkspaceMenuMetrics.journeyCompactHeight), .medium, .large],
            selection: $detent)
        #endif
        .presentationDragIndicator(.hidden)
        .railMenuPresentationCornerRadius()
        .presentationContentInteraction(.scrolls)
        // Remove UIKit's dimming view at every height. Dragging resizes the
        // card; dismissal is reserved for the header's X button.
        .presentationBackgroundInteraction(.enabled)
        .interactiveDismissDisabled()
        .onChange(of: dynamicTypeSize, initial: true) { _, size in
            detent = size.isAccessibilitySize ? .large
                : .height(WorkspaceMenuMetrics.journeyCompactHeight)
        }
        .onChange(of: train == nil, initial: true) { _, missing in
            if missing { dismiss() }
        }
    }

    /// The map's "!" opens the read card from here, the one presenter, and a
    /// place pick lowers this sheet to its compact height until it finishes.
    private func installTripNoteHooks() {
        Self.hookOwner = hookToken
        controller.onTripNote = { trainID, noteID in
            guard trainID == recordID else { return }
            tripNoteFlow.screen = .read(noteID: noteID)
        }
        tripNoteFlow.pickPlace = { initial, finish in beginMapPick(initial, finish) }
        // From the details sheet the sheet steps aside first, and is back
        // before the form (or nothing, on cancel) is shown.
        let stepAside = TripNoteDetailsStepAside(
            closeDetails: { done in
                showsDetails = false
                afterSheetSettles(done)
            },
            startPick: { initial, finish in beginMapPick(initial, finish) },
            reopenDetails: { done in
                showsDetails = true
                afterSheetSettles(done)
            })
        detailsStepAside = stepAside
        detailsNoteFlow.pickPlace = { initial, finish in stepAside.pick(initial: initial, finish: finish) }
    }

    /// Runs `done` once the host has had its teardown delay and nothing is
    /// presenting or dismissing.
    private func afterSheetSettles(_ done: @escaping @MainActor () -> Void) {
        stepAsideWait?.cancel()
        stepAsideWait = Task { @MainActor in
            do {
                try await Task.sleep(for: presentationHost.teardown)
                while !presentationHost.isIdle { try await Task.sleep(for: .milliseconds(16)) }
            } catch {
                return
            }
            done()
        }
    }

    private func beginMapPick(_ initial: TripNoteAnchor?, _ finish: @escaping (TripNoteAnchor?) -> Void) {
        // One pick at a time: a second tap must not capture the lowered
        // detent as the one to restore.
        guard controller.tripNotePickTrainID == nil else { finish(nil); return }
        let restored = detent
        withAnimation(RailMotion.spring) { detent = lowestDetent }
        controller.beginTripNotePick(trainID: recordID, initial: initial) { anchor in
            withAnimation(RailMotion.spring) { detent = restored }
            finish(anchor)
        }
    }

    private var lowestDetent: PresentationDetent {
        dynamicTypeSize.isAccessibilitySize ? .large
            : .height(WorkspaceMenuMetrics.journeyCompactHeight)
    }

    /// Fit only after the sheet reports its lowest available visible edge.
    private func focusIfReady() {
        guard focusRequested, menuMeasurements.height > 0, let train else { return }
        #if !targetEnvironment(macCatalyst)
        guard dynamicTypeSize.isAccessibilitySize
            || menuMeasurements.height <= WorkspaceMenuMetrics.journeyCompactHeight + 1 else { return }
        #endif
        focusRequested = false
        controller.journeyMenuBottomObstruction =
            menuMeasurements.height + menuMeasurements.bottomInset
        onPrimary(.locate, train)
    }

    private struct MenuMeasurements: Equatable {
        var height: CGFloat = 0
        var bottomInset: CGFloat = 0
    }

    private func save(_ edited: Train) -> Bool { startSave(edited) != nil }

    /// A note save from a form that shows its own failure: waits for the write
    /// and clears the journey-level failure alert, so one failure raises one
    /// alert (the form's), not a second one behind the form's sheet.
    private func saveAwaitingPersistence(_ edited: Train) async -> Bool {
        guard let saving = startSave(edited) else { return false }
        let persisted = await saving.value
        saveFailureDetail = NoteSaveAlert.journeyFailureDetail(afterNoteSave: persisted, current: saveFailureDetail)
        return persisted
    }

    /// Starts a save; nil when it was refused. The task answers whether the
    /// write finally persisted.
    private func startSave(_ edited: Train) -> Task<Bool, Never>? {
        guard !isSaving else { return nil }
        let previousID = recordID
        let attempt = onSave(edited, previousID)
        guard let persistence = attempt.persistence else { return nil }
        switch attempt.outcome {
        case .saved: recordID = edited.id
        case let .savedKeepingID(keptID, _): recordID = keptID
        case .refusedImportRunning, .notFound, .unsupportedRegion: return nil
        }
        isSaving = true
        saveFailureDetail = nil
        return Task { @MainActor in
            let saved = await persistence.value
            isSaving = false
            guard saved.saved else {
                if attempt.rollback?() == true { recordID = previousID }
                saveFailureDetail = saved.error ?? ""
                return false
            }
            return true
        }
    }
}

/// Which failure alert a note save may leave up. The form shows its own
/// "refused" alert, so the journey-level one must stay down.
enum NoteSaveAlert {
    static func journeyFailureDetail(afterNoteSave persisted: Bool, current: String?) -> String? {
        persisted ? current : nil
    }
}
