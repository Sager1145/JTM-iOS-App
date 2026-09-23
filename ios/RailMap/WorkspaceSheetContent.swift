import RailCore
import RailPresentation
import SwiftUI

/// Every sheet the workspace can present over its resident chrome.
enum WorkspaceSheet: Identifiable {
    case newJourney(Train)
    case edit(Train)
    case detail(String)
    case importData
    case videoOptions
    case mapInfo
    case mapLayers
    case station(StationCard)
    case chooseRide([Train])
    case utility(UtilityDestination)

    var id: String {
        switch self {
        case .newJourney(let train): "new:\(train.id)"
        case .edit(let train): "edit:\(train.id)"
        case .detail(let id): "detail:\(id)"
        case .importData: "import"
        case .videoOptions: "video"
        case .mapInfo: "info"
        case .mapLayers: "layers"
        case .station(let card): "station:\(card.id)"
        case .chooseRide(let trains): "choose:\(trains.map(\.id).joined(separator: ","))"
        case .utility(let destination): "utility:\(destination.rawValue)"
        }
    }
}

/// Content for one workspace sheet. The workspace retains presentation state
/// and performs every mutation through the callbacks supplied here.
struct WorkspaceSheetContent: View {
    @Environment(AppLocalization.self) private var localization

    let sheet: WorkspaceSheet
    let itineraries: ItineraryStore
    let library: RideLibrary
    let controller: RailMapController
    let network: RailNetworkStore
    let importFlow: ImportFlow
    let videoSettings: VideoExportSettings
    let videoSourceRect: CGRect
    let videoSeconds: Double
    let videoDisplayScale: CGFloat
    @Binding var appearance: String
    let categoryIndexesAreBuilding: Bool
    let selectedDateIsAllDates: Bool
    let presentation: (Train) -> JourneyPresentation
    let onSaveNew: (Train) -> Void
    let onSaveEdit: (Train, String) -> Void
    let onSaveDetail: (Train, String) -> ItineraryStore.SaveOutcome
    let onRebuild: (Train) -> Int?
    let onStartExport: () -> Void
    let onDismiss: () -> Void
    let onPick: (Train) -> Void

    init(
        sheet: WorkspaceSheet,
        itineraries: ItineraryStore,
        library: RideLibrary,
        controller: RailMapController,
        network: RailNetworkStore,
        importFlow: ImportFlow,
        videoSettings: VideoExportSettings,
        videoSourceRect: CGRect,
        videoSeconds: Double,
        videoDisplayScale: CGFloat,
        appearance: Binding<String>,
        categoryIndexesAreBuilding: Bool,
        selectedDateIsAllDates: Bool,
        presentation: @escaping (Train) -> JourneyPresentation,
        onSaveNew: @escaping (Train) -> Void,
        onSaveEdit: @escaping (Train, String) -> Void,
        onSaveDetail: @escaping (Train, String) -> ItineraryStore.SaveOutcome,
        onRebuild: @escaping (Train) -> Int?,
        onStartExport: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        onPick: @escaping (Train) -> Void
    ) {
        self.sheet = sheet
        self.itineraries = itineraries
        self.library = library
        self.controller = controller
        self.network = network
        self.importFlow = importFlow
        self.videoSettings = videoSettings
        self.videoSourceRect = videoSourceRect
        self.videoSeconds = videoSeconds
        self.videoDisplayScale = videoDisplayScale
        _appearance = appearance
        self.categoryIndexesAreBuilding = categoryIndexesAreBuilding
        self.selectedDateIsAllDates = selectedDateIsAllDates
        self.presentation = presentation
        self.onSaveNew = onSaveNew
        self.onSaveEdit = onSaveEdit
        self.onSaveDetail = onSaveDetail
        self.onRebuild = onRebuild
        self.onStartExport = onStartExport
        self.onDismiss = onDismiss
        self.onPick = onPick
    }

    var body: some View {
        Group {
            switch sheet {
            case .newJourney(let draft):
                RideEditorView(
                    train: draft,
                    title: localization.text("ios.editorTitleNew", fallback: "New"),
                    isNew: true,
                    suggestionTrains: itineraries.loaded?.trains ?? [],
                    onSave: onSaveNew)
            case .edit(let train):
                RideEditorView(
                    train: train,
                    title: localization.text("ios.edit", fallback: "Edit"),
                    suggestionTrains: itineraries.loaded?.trains ?? []
                ) { edited in
                    onSaveEdit(edited, train.id)
                }
            case .videoOptions:
                VideoExportOptionsView(
                    settings: videoSettings,
                    sourceRect: videoSourceRect,
                    displayScale: videoDisplayScale,
                    seconds: videoSeconds
                ) {
                    onDismiss()
                    onStartExport()
                }
            case .detail(let id):
                NavigationStack {
                    WorkspaceRideDetailView(
                        trainID: id,
                        itineraries: itineraries,
                        onSave: onSaveDetail,
                        onRebuild: onRebuild)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(localization.text("ios.cancel", fallback: "Cancel")) {
                                onDismiss()
                            }
                        }
                    }
                }
            case .importData:
                DataImportView(
                    flow: importFlow,
                    itineraries: itineraries,
                    library: library)
            case .mapInfo:
                MapInfoView()
            case .mapLayers:
                MapLayersView(
                    controller: controller,
                    classifying: categoryIndexesAreBuilding)
            case .station(let card):
                StationCardView(card: card)
            case .chooseRide(let trains):
                RideChooserView(
                    trains: trains,
                    showsDate: selectedDateIsAllDates,
                    presentation: presentation
                ) { train in
                    onDismiss()
                    onPick(train)
                }
            case .utility(let destination):
                UtilityDestinationView(
                    destination: destination,
                    itineraries: itineraries,
                    library: library,
                    appearance: $appearance,
                    network: network,
                    controller: controller)
            }
        }
        // Every sub-menu is Liquid Glass at every height. Left to itself the
        // system turns a full-height sheet opaque, so the glass is set here
        // explicitly; lists and forms inside drop their grouped backdrop.
        .scrollContentBackground(.hidden)
        .presentationBackground {
            Color.clear.railGlass(in: Rectangle())
        }
    }
}
