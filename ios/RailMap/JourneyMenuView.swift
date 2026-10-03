import RailCore
import RailPresentation
import SwiftUI

/// The original journey card in a resizable presentation with a live map behind it.
struct WorkspaceJourneyMenu: View {
    @Bindable var itineraries: ItineraryStore
    let controller: RailMapController
    @State private var recordID: String
    @State private var showsEditor = false
    @State private var showsDetails = false
    @State private var cardMorph = PanelMorph()
    @State private var menuMeasurements = MenuMeasurements()
    @State private var focusRequested = false
    @State private var detent: PresentationDetent = .height(WorkspaceMenuMetrics.journeyCompactHeight)
    @Environment(\.dismiss) private var dismiss
    @Environment(AppLocalization.self) private var localization
    @Environment(RailNetworkStore.self) private var network
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let presentation: (Train) -> JourneyPresentation
    let onSave: (Train, String) -> ItineraryStore.SaveOutcome
    let onRebuild: (Train) -> Int?
    let onPrimary: (JourneyPresentation.PrimaryAction, Train) -> Void
    let onSecondary: (SecondaryAction, Train) -> Void

    init(trainID: String, itineraries: ItineraryStore, controller: RailMapController,
         presentation: @escaping (Train) -> JourneyPresentation,
         onSave: @escaping (Train, String) -> ItineraryStore.SaveOutcome,
         onRebuild: @escaping (Train) -> Int?,
         onPrimary: @escaping (JourneyPresentation.PrimaryAction, Train) -> Void,
         onSecondary: @escaping (SecondaryAction, Train) -> Void) {
        self.itineraries = itineraries
        self.controller = controller
        _recordID = State(initialValue: trainID)
        self.presentation = presentation
        self.onSave = onSave
        self.onRebuild = onRebuild
        self.onPrimary = onPrimary
        self.onSecondary = onSecondary
    }

    private var train: Train? { itineraries.store?.trains.first { $0.id == recordID } }

    var body: some View {
        Group {
            if let train {
                RideCard(
                    train: train, presentation: presentation(train), dateChipTitle: train.date,
                    onClose: { dismiss() },
                    onPrimary: { action in
                        if action == .save { showsEditor = true }
                        else if action == .locate {
                            focusRequested = true
                            withAnimation(RailMotion.spring) { detent = lowestDetent }
                            focusIfReady()
                        } else { onPrimary(action, train) }
                    },
                    onSecondary: { action in
                        switch action {
                        case .edit: showsEditor = true
                        case .inspectDetails: showsDetails = true
                        default: onSecondary(action, train)
                        }
                    },
                    onSetRidden: { _ = save(RideLedger.setRidden(train, $0)) })
                    // The source panel's compact stage must not hide this card's body.
                    .environment(cardMorph)
                    .padding(.top, 16)
                    .sheet(isPresented: $showsEditor) {
                        RideEditorView(
                            train: train, title: train.number,
                            suggestionTrains: itineraries.loaded?.trains ?? [],
                            onCancel: { showsEditor = false },
                            onSave: { edited in
                                if save(edited) { showsEditor = false }
                            })
                            .environment(localization)
                            .environment(network)
                    }
                    .sheet(isPresented: $showsDetails) {
                        NavigationStack {
                            RideDetailView(
                                train: train, onSave: save, onRebuild: { onRebuild(train) },
                                suggestionTrains: itineraries.loaded?.trains ?? [])
                                .toolbar {
                                    ToolbarItem(placement: .cancellationAction) {
                                        Button(localization.text("ios.close", fallback: "Close"),
                                               systemImage: "xmark") { showsDetails = false }
                                    }
                                }
                        }
                        .environment(localization)
                        .environment(network)
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
            if menuMeasurements.height > 0 {
                controller.journeyMenuBottomObstruction =
                    menuMeasurements.height + menuMeasurements.bottomInset
            }
        }
        .onDisappear { controller.journeyMenuBottomObstruction = nil }
        .presentationDetents(
            dynamicTypeSize.isAccessibilitySize
                ? [.large] : [.height(WorkspaceMenuMetrics.journeyCompactHeight), .medium, .large],
            selection: $detent)
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

    private var lowestDetent: PresentationDetent {
        dynamicTypeSize.isAccessibilitySize ? .large
            : .height(WorkspaceMenuMetrics.journeyCompactHeight)
    }

    /// Fit only after the sheet reports its lowest available visible edge.
    private func focusIfReady() {
        guard focusRequested, menuMeasurements.height > 0,
              dynamicTypeSize.isAccessibilitySize
                || menuMeasurements.height <= WorkspaceMenuMetrics.journeyCompactHeight + 1,
              let train else { return }
        focusRequested = false
        controller.journeyMenuBottomObstruction =
            menuMeasurements.height + menuMeasurements.bottomInset
        onPrimary(.locate, train)
    }

    private struct MenuMeasurements: Equatable {
        var height: CGFloat = 0
        var bottomInset: CGFloat = 0
    }

    private func save(_ edited: Train) -> Bool {
        switch onSave(edited, recordID) {
        case .saved:
            recordID = edited.id
            return true
        case let .savedKeepingID(keptID, _):
            recordID = keptID
            return true
        case .refusedImportRunning, .notFound, .unsupportedRegion:
            return false
        }
    }
}
