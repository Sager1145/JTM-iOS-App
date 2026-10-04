import CoreLocation
import MapKit
import RailCore
import RailPresentation
import SwiftUI
import UIKit

/// Seed for the resident journey editor. Edit keeps the id `replace` must target.
struct JourneyEditorLaunch {
    var train: Train
    var isNew: Bool
    var originalID: String?
}

/// The railway over Apple Maps, in the two shapes iOS asks for.
///
/// The compact case is a persistent map workspace: the map and the ride panel
/// remain interactive members of the same hierarchy. It deliberately is not a
/// modal sheet. The panel snaps between three semantic sizes and reserves room
/// for the system tab bar, while the drag handle is the only surface that owns
/// the vertical resize gesture.
///
/// The layout is chosen by the window's shape, not the device. A phone in
/// landscape has almost no height for a sheet but plenty of width for the
/// same menu docked as a floating card, and it reports a *compact*
/// horizontal size class on every model but the largest — so size class alone
/// would put a sheet there and leave the map a letterbox.
///
///   tall windows   a resizable persistent panel over the map
///   wide windows   the same menu docked as a card over a full-window map
///
/// The map's controls run down the right edge in both, and in the panel
/// layout they ride above it — at full height they are removed rather than
/// pushed off screen. A control the panel slides over is one that stops
/// working without ever looking broken.
///
/// ## Journey details are separate presentations
///
/// The source menu stays mounted while a journey opens its own sheet. Closing
/// that sheet returns to the same destination, filters and list position.
/// The selected train continues to identify the highlighted route on the map.
///
/// ## Nothing here decides which action is primary (§3.3, §11.2)
///
/// Every surface below renders a `JourneyPresentation` resolved by
/// `JourneyPresentationResolver`. This view does not ask "is it hidden", "is
/// it playing", "did the route fail" — those states can all be true at once,
/// and the one place that turns them into a single primary task is a module
/// with tests over 288 state combinations. What is left here is the wiring:
/// which store call each resolved action makes.
struct RailWorkspaceView: View {
    /// Read for one reason: `PanelHeader` drops its subtitle in a short
    /// window at an accessibility text size, and the compact stop must not
    /// reserve a row for a line that is not drawn. See ``compactHeaderRows``.
    @Environment(AppLocalization.self) private var localization

    @Bindable var store: RailNetworkStore
    @Bindable var itineraries: ItineraryStore
    @Bindable var library: RideLibrary
    @Bindable var riddenRoutes: RiddenRouteStore
    @Bindable var controller: RailMapController
    /// The app's ONE transport, owned by the shell.
    ///
    /// It used to be `@State` here, which was right while Journeys was the
    /// only workspace that could play anything. §5.3.5 gives Passport a replay
    /// entry point and §5.2 keeps the map live under Network, so a controller
    /// per workspace would mean a run started in one tab going on playing,
    /// unreachable, while another tab drew a map that knew nothing about it.
    @Bindable var playback: PlaybackController
    /// §5.3's numbers, computed once for the whole app.
    @Bindable var statistics: MileageStatisticsStore
    /// Which region Upcoming, All Journeys and the statistics are scoped to.
    /// `nil` is 全部 — see `StatisticsView.region`.
    @Binding var regionScope: Region?
    /// §2.2 (revised): which of the three destinations is on top. The shell
    /// owns it because it survives every panel here.
    @Binding var selection: PrimaryTab
    /// §6.2's appearance preference. Read here because the Settings
    /// destination is presented from this view now (see `WorkspaceSheet.utility`)
    /// rather than from the shell — a controller that is already presenting
    /// the resident sheet cannot present a second one.
    @AppStorage("appearance") private var appearance = "system"
    @State private var render: RailMapView.RenderStats?
    @State private var query = ""
    @State private var selectedDate = Dates.allDates
    /// Alerts and confirmations share one presentation slot. Independent
    /// booleans here can all become true during the same map/menu callback,
    /// which asks one hosting controller to present twice.
    @State private var dialog: WorkspaceDialog?
    /// §10.3's ⌘F target.
    @FocusState private var searchFocused: Bool
    @State private var sheet: WorkspaceSheet?
    @State private var linePreview: RailwayLinePreview?
    @State private var selectionBeforeJourneyMenu: String?
    @State private var journeyMenuOwnsSelection = false
    @State private var workspaceMenuIsSuspended = false

    private var hidesWorkspaceMenu: Bool {
        workspaceMenuIsSuspended || sheet?.hidesWorkspaceMenu == true
    }
    /// The journey editor lives in the resident sheet, not a second presentation.
    @State private var journeyEditor: JourneyEditorLaunch?
    /// Once an editor mutation reaches the working set, retries replace this
    /// exact record instead of adding the same draft again.
    @State private var journeyEditorRecordID: String?
    @State private var journeySaveAttemptID: UUID?
    @State private var journeySaveFailureDetail: String?
    /// A draft-pin tap asks the editor to open that stop. Cleared after it is consumed.
    @State private var highlightedStopID: UUID?
    /// The composition that owns an active workspace sheet.
    ///
    /// Compact and docked layouts deliberately attach presentations to
    /// different descendants: on a phone the only controller free to present
    /// is inside the resident bottom sheet, while a docked card can present
    /// from its own tree. Replacing those descendants during a rotation also
    /// replaces the presented `RideEditorView`, including its local draft.
    /// Keep its presenter mounted until dismissal, then let the workspace
    /// adopt the window's current layout.
    @State private var presentationLayoutMode: WorkspaceLayoutMode?
    @State private var importFlow = ImportFlow()
    /// Filming a run — see ``VideoExportFlow``, which owns the recorder, the
    /// reader's choices and the length the options sheet quotes.
    @State private var videoExport = VideoExportFlow()
    @State private var didRunDebugPlayback = false
    @State private var didRunDebugSheet = false
#if DEBUG
    // Loading another region must not reapply the starting camera mid-gesture.
    @State private var didApplyDebugCamera = false
#endif
    /// The 已乘路線顯示 filter's edge indexes and their build — see
    /// ``CategoryIndexes``. What stays here is only WHEN to ask, which is
    /// `categoryIndexKey`.
    @State private var categoryIndexes = CategoryIndexes()
    /// The workspace's memoised answers — see ``WorkspaceDerived``.
    ///
    /// Not observable and not observed: it is a cache whose every entry is a
    /// pure function of its key, so filling one during a body evaluation
    /// invalidates nothing. It exists because this view asks the same
    /// expensive questions several times per pass, and a sheet drag is one
    /// pass per frame.
    @State private var derived = WorkspaceDerived()
    @State private var journeySearch = JourneySearch()
    /// The dates the reader typed in — see ``ManualDates``, which owns them
    /// and their persistence.
    @State private var manualDates = ManualDates()
    @AppStorage("map-follows-selected-date") private var mapFollowsSelectedDate = false
    /// `focusZoomEnabled` — 自動縮放 for date changes. Direct journey and
    /// region picks always focus their complete extent.
    @AppStorage("auto-focus-zoom") private var autoFocusZoom = false
    /// 設定 › 啟動地圖範圍 — what the map opens on, when the reader would
    /// rather say than have the app infer. See ``LaunchMapScope`` and
    /// ``launchExtent``; `SettingsView.launchScopeSection` is the other end.
    @AppStorage("launch-map-scope") private var launchScope = LaunchMapScope.auto.rawValue
    /// Which country 國家地區 means. Kept apart from the mode so that a trip
    /// through 全球 and back does not forget it.
    @AppStorage("launch-map-region") private var launchScopeRegion = Region.jp.rawValue
    /// Where the resident sheet is resting, as a STAGE rather than as a
    /// `PresentationDetent`.
    ///
    /// The detent is derived from this (see ``detentBinding(_:)``) and never
    /// stored, because two of the three detents are `.height()` values
    /// computed from the window: a stored detent would be a number from the
    /// previous window size, and a detent that is not in the set the sheet was
    /// given is a detent SwiftUI silently replaces.
    @State private var stageSelection: SheetStage = Self.launchStage

    /// The live shape of the menu panel — see ``PanelMorph``. Shared by both
    /// compositions so `PanelHeader`, `RideCard` and `WorkspacePanelPage` read
    /// one number no matter which layout is driving it.
    @State private var panelMorph = PanelMorph(
        stage: Self.launchStage,
        expansion: Self.launchStage == .compact ? 0 : 1)

    /// Which stop the sheet opens at.
    ///
    /// `.medium` in the app. The environment override exists because the sheet
    /// is resized by dragging and there is no way to drive a drag from a
    /// screenshot harness — the same reason `RAILMAP_UI_TEST_SELECT` exists.
    /// Read once, and only in a debug build.
    private static var launchStage: SheetStage {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["RAILMAP_UI_TEST_STAGE"] {
        case "compact": return .compact
        case "expanded": return .expanded
        default: return .medium
        }
        #else
        return .medium
        #endif
    }
    /// Retains the sheet's measurement across layout changes without making
    /// every drag sample invalidate the workspace and its map inputs.
    @State private var sheetMeasurements = ResidentSheetMeasurements()

    @State private var lastOpenDockStage: SheetStage = .medium

    /// How tall the map's control rail actually draws, so the fade that keeps
    /// it out from under the status bar knows where its top edge is. See
    /// `mapLayout`'s `railFade`.
    @State private var railHeight: CGFloat = 0
    @State private var playbackBarHeight: CGFloat = 0

    /// §13's haptics, and only where they earn a place.
    ///
    /// The app had none at all. These three are the moments Apple's own rules
    /// name — a commit, a destructive commit, and a snap — and each fires on
    /// the CAUSAL event rather than on a state that happens to follow it, so
    /// the tap lands on the same frame as the change it belongs to. Deliberately
    /// not on every button: feedback everywhere trains a reader to feel nothing.
    ///
    /// Carries a counter because `sensoryFeedback` compares values, and two
    /// saves in a row are the same case — without it the second one is silent.
    private struct RailFeedback: Equatable {
        enum Kind { case saved, deleted, settled }
        var kind: Kind
        var count: Int
    }
    @State private var feedback: RailFeedback?

    private func signal(_ kind: RailFeedback.Kind) {
        feedback = RailFeedback(kind: kind, count: (feedback?.count ?? 0) + 1)
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// §10.1: the panel's smallest stop follows the reader's text size.
    ///
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title2) private var headerTitleRow = WorkspaceMenuMetrics.titleRowHeight

    /// Compact reserves the same ordinary title bar used at every other stop.
    /// Every tab reserves the same subtitle slot, even when it is empty.
    private var compactHeaderRows: CGFloat {
        let row = WorkspaceMenuMetrics.headerContentHeight(
            titleRow: headerTitleRow, stacked: false, drawsSubtitle: true)
        return row + WorkspaceMenuMetrics.topInset + WorkspaceMenuMetrics.bottomInset
    }


    var body: some View {
        GeometryReader { geometry in
            let layout = WorkspaceLayoutMetrics(containerSize: geometry.size)
            let renderedMode = presentationLayoutMode ?? layout.mode

            // One state graph, two compositions. Selection, search, filters,
            // playback, map camera, and presentation state all remain owned by
            // this view while the window crosses the breakpoint.
            Group {
                switch renderedMode {
                case .compactOverlay:
                    mapLayout(in: geometry)
                case .sideBySide:
                    sideBySideLayout(in: geometry, panelWidth: layout.sidePanelWidth)
                }
            }
            // Capture the presenter as its sheet becomes active. The pin is
            // released by WorkspacePresentations' onDismiss callback, after
            // the system has actually torn the sheet down; clearing it as
            // soon as `sheet` becomes nil would remove the presenter during
            // the dismissal animation.
            .onChange(of: sheet != nil) { wasPresented, isPresented in
                guard !wasPresented, isPresented,
                      presentationLayoutMode == nil else { return }
                presentationLayoutMode = layout.mode
            }
            .onChange(of: sheet?.hidesWorkspaceMenu == true) { _, hidesMenu in
                if hidesMenu {
                    searchFocused = false
                    workspaceMenuIsSuspended = true
                }
            }
            .onChange(of: journeyEditor != nil) { wasEditing, isEditing in
                if !wasEditing, isEditing {
                    // The editor owns its draft and stop identities. Keep its
                    // presenting subtree mounted across layout breakpoints.
                    presentationLayoutMode = layout.mode
                } else if wasEditing, !isEditing, sheet == nil {
                    presentationLayoutMode = nil
                }
            }
            // The system tab bar belongs to the page inside the sheet. iOS 26+
            // draws it as transparent glass over the menu; earlier systems
            // draw a solid bar and keep the page above it. The root proxy
            // only sees the home indicator.
        }
        .onChange(of: playback.currentTrainID) { _, id in
            if let id { itineraries.selectedTrainID = id }
        }
        // Where the map opens: the whole country the reader's first journey is
        // in. One step, and one only.
        //
        // It waits for two things and no more — an `MKMapView` to talk to, and
        // the rides to have been read. Deliberately NOT for the rail packages:
        // ``Region/networkExtent`` is a written-down box precisely so that the
        // opening view does not arrive seconds after the launch it belongs to.
        // See ``RailMapController/frameAtLaunch(_:)`` for what this replaced
        // and for the ways it declines to move a camera somebody else has.
        //
        // **A country, not the journey inside it.** A second step used to
        // follow this one, zooming from the country onto the routes of the
        // soonest upcoming day once their geometry had been read. It is gone,
        // and the argument for removing it is the argument for the whole of
        // this file's camera policy: that frame arrives when a disk read
        // finishes, which is not a moment the reader did anything at, and on a
        // small store it arrived so soon that the country was never on screen
        // at all. The opening view is a country. Everything closer than that
        // is something the reader asks for — a journey tapped, 定位, 自動縮放.
        //
        // Keyed on a cheap summary rather than on `launchExtent` itself: the
        // answer costs a pass over every ride, this key is read on every body
        // evaluation, and a sheet drag is a body evaluation per frame.
        .task(
            id: "\(controller.isMapReady)|\(launchScope)|\(launchScopeRegion)|\(launchFramingKey)"
        ) {
            guard controller.isMapReady, let launchExtent else { return }
            controller.frameAtLaunch(launchExtent)
        }
        // Restored scopes only filter content. Explicit menu picks frame the
        // complete country in selectRegion, including a repeated selection.
        .onChange(of: regionScope) { _, _ in
            controller.cancelAutoFocus()
        }
        .onChange(of: autoFocusZoom) { _, enabled in
            if !enabled { controller.cancelAutoFocus() }
        }
        .task(id: journeySearchRequest) {
            await journeySearch.search(journeySearchRequest,
                alsoNamed: localization.localizedStationNames(of:))
        }
        .task { manualDates.load() }
        // Built off the main actor, published as each region's arrives, and
        // never torn down: a reader who ticks 地下鐵 back off a minute later
        // should not wait for the network to be read a second time.
        .task(id: categoryIndexKey) {
            guard controller.layers.categories.anyHidden else { return }
            await categoryIndexes.load(for: riddenCountries)
        }
#if DEBUG
        .overlay(alignment: .topLeading) {
            if RouteStressHarness.enabled {
                RouteStressHarnessPanel(itineraries: itineraries, library: library,
                                        controller: controller, selectDate: selectDate)
            }
        }
        // A headless way to put the workspace into its selected state.
        //
        // The journey menu is reached by tapping a row, and a tap is the one thing a
        // screenshot harness driving `simctl` cannot perform — so every state
        // in §5.2, including the ones that only appear when a route fails,
        // would otherwise be unreviewable outside a human session. Same shape,
        // and the same DEBUG-only reach, as `RAILMAP_UI_TEST_PLAYBACK` above.
        .task(id: "\(itineraries.loaded?.trains.count ?? 0)") {
            guard let wanted = ProcessInfo.processInfo.environment["RAILMAP_UI_TEST_SELECT"],
                  itineraries.selectedTrainID == nil,
                  let trains = itineraries.loaded?.trains, !trains.isEmpty else { return }
            let train: Train?
            if let index = Int(wanted) {
                train = trains[min(max(index, 0), trains.count - 1)]
            } else {
                train = trains.first(where: { $0.id == wanted })
            }
            guard let train else { return }
            if ProcessInfo.processInfo.environment["RAILMAP_UI_TEST_TAB"] == nil {
                let inCurrentMapScope: Bool
                switch selection {
                case .upcoming: inCurrentMapScope = upcomingScope.ids.contains(train.id)
                case .stats: inCurrentMapScope = statisticsScope.ids.contains(train.id)
                case .all, .search:
                    let inRegion = selection != .all || regionScope == nil
                        || derived.trainIDs(inRegion: regionScope!, in: trains).contains(train.id)
                    let inDate = !mapFollowsSelectedDate || selectedDate == Dates.allDates
                        || derived.trainIDs(spanning: selectedDate, in: trains).contains(train.id)
                    inCurrentMapScope = inRegion && inDate
                }
                if !inCurrentMapScope {
                    selection = .all
                    if let regionScope,
                       !derived.trainIDs(inRegion: regionScope, in: trains).contains(train.id) {
                        self.regionScope = nil
                    }
                    if mapFollowsSelectedDate, selectedDate != Dates.allDates,
                       !derived.trainIDs(spanning: selectedDate, in: trains).contains(train.id) {
                        selectedDate = Dates.allDates
                    }
                }
            }
            pick(train)
        }
        // Which region the camera starts on, and which sample is loaded —
        // the two things a `simctl` harness cannot tap its way to. The opening
        // camera is chosen from the reader's own rides now, so a harness that
        // has loaded no store at all still opens on the East Asia fallback
        // rather than on the country the shot is meant to be of.
        .task(id: "\(store.lines.count)|\(controller.isMapReady)") {
            guard controller.isMapReady else { return }
            if let camera = ProcessInfo.processInfo.environment["RAILMAP_UI_TEST_CAMERA"] {
                guard !didApplyDebugCamera else { return }
                let values = camera.split(separator: ",").compactMap { Double($0) }
                if values.count == 3 {
                    do { try await Task.sleep(for: .milliseconds(700)) }
                    catch { return }
                    didApplyDebugCamera = true
                    controller.frameForUITest(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: values[0], longitude: values[1]),
                        span: MKCoordinateSpan(latitudeDelta: values[2], longitudeDelta: values[2])
                    ))
                    return
                }
            }
            guard let wanted = ProcessInfo.processInfo.environment["RAILMAP_UI_TEST_REGION"],
                  let region = Region(rawValue: wanted) else { return }
            let rect = store.lines
                .filter { $0.region == region }
                .reduce(MKMapRect.null) { $0.union($1.mapRect) }
            guard !rect.isNull else { return }
            // After the app's own opening move, and after the lines this rect
            // is measured from have landed. `frameAtLaunch` will not fire
            // twice, so this is the last word on the camera either way.
            do { try await Task.sleep(for: .milliseconds(700)) }
            catch { return }
            // `controller.framingInsets` rather than a bare margin: on a
            // window wide enough for the docked card this harness's own shot
            // would otherwise land half hidden behind it, the same way any
            // other "frame this" would without the controller's padding.
            controller.frameForUITest(rect)
        }
        // A sheet, for the same reason `RAILMAP_UI_TEST_SELECT` exists: the
        // legend, the importer and the export options are all reached by a tap
        // that a `simctl` harness cannot perform, so their layout would only
        // ever be reviewed by hand.
        .task(id: "\(controller.isMapReady)|\(itineraries.loaded?.trains.isEmpty == false)") {
            guard controller.isMapReady, !didRunDebugSheet,
                  let wanted = ProcessInfo.processInfo.environment["RAILMAP_UI_TEST_SHEET"]
            else { return }
            // Editing needs an existing journey; map readiness can precede
            // loading the saved store. Retry when the first journey arrives.
            if wanted == "edit", itineraries.selectedTrain == nil,
               itineraries.loaded?.trains.first == nil { return }
            do { try await Task.sleep(for: .milliseconds(900)) }
            catch { return }
            // A cancelled readiness task must not reload an already presented
            // import and silently replace the input being reviewed.
            guard controller.isMapReady, !didRunDebugSheet else { return }
            didRunDebugSheet = true
            switch wanted {
            case "info": sheet = .mapInfo
            case "import": sheet = .importData
            case "new":
                presentJourneyEditor(JourneyEditorLaunch(
                    train: newJourneyScaffold(in: defaultRegion), isNew: true, originalID: nil))
            case "edit":
                if let train = itineraries.selectedTrain ?? itineraries.loaded?.trains.first {
                    presentJourneyEditor(JourneyEditorLaunch(
                        train: train, isNew: false, originalID: train.id))
                }
            case "detail":
                var train = StoreOperations.createBlankTrain(country: "jp")
                train.number = "Review"
                if let id = itineraries.add(train) { sheet = .detail(id) }
            case "import-review", "import-reopen":
                // Only the test's in-memory workspace is cleared; saved rides
                // remain untouched so reopening can use the real empty-state door.
                if wanted == "import-reopen" { itineraries.deleteAll() }
                var train = StoreOperations.createBlankTrain(country: "jp")
                train.number = "Import review"
                let document = TrainStore(schemaVersion: TrainValidation.schemaVersion, trains: [train])
                importFlow.load(StoreOperations.stringify(StoreOperations.json(document)), origin: .pasted)
                sheet = .importData
            case "layers": sheet = .mapLayers
            // §4.1's two Utility destinations and the export options. All
            // three are reached by a tap on a control the harness cannot
            // press — the data button, the gear, and the transport's export
            // button — so without these the Data Library, Settings and the
            // shape/quality/bitrate sheet are the only surfaces left that
            // nothing but a hand session ever opens.
            case "data": sheet = .utility(.data)
            case "settings": sheet = .utility(.settings)
            case "video": sheet = .videoOptions
            case "station":
                // The station card replaced the map's callout, and a callout
                // was already unreachable from a `simctl` harness — a tap on a
                // bead is still a tap. The station is picked the same way the
                // map would have handed one up: whichever the network store
                // lists first, named and read exactly as the annotation names
                // and reads it.
                if let station = store.mapStations.first ?? store.stations.first {
                    sheet = .station(
                        StationCard(
                            station: station,
                            displayName: localization.stationName(
                                station.name, code: station.id),
                            readings: localization.nameReadingsTyped(
                                station.name, code: station.id).map(\.text)))
                }
            default: break
            }
        }
        // The layer switches, which otherwise need a finger on a checkbox.
        // Same reason as `RAILMAP_UI_TEST_SHEET`: what a filter DOES is only
        // reviewable by turning it off and looking at the map, and a `simctl`
        // harness cannot turn anything off. Names the switches to clear, so
        // `routes,metro` draws the dots without their lines and drops every
        // 地下鐵 stretch.
        // At first appearance rather than when the map is ready: these are
        // the state a reader would have set BEFORE loading anything, and
        // turning 自動縮放 on after a journey is already selected correctly
        // moves nothing — a switch is not a command to jump.
        .task {
            guard let wanted = ProcessInfo.processInfo
                .environment["RAILMAP_UI_TEST_LAYERS"]
            else { return }
            for key in wanted.split(separator: ",").map(String.init) {
                switch key {
                case "routes": controller.layers.routes = false
                case "stops": controller.layers.stops = false
                case "terminals": controller.layers.terminals = false
                case "pass": controller.layers.passThrough = false
                case "hsr": controller.layers.categories.hsr = false
                case "jr": controller.layers.categories.jr = false
                case "metro": controller.layers.categories.metro = false
                case "priv": controller.layers.categories.priv = false
                case "network": controller.showsNetwork = true
                // Not a layer, but the same problem: 自動縮放 is a stored
                // preference with a switch in the date menu, and a harness
                // cannot open a menu either. Without it every screenshot of
                // the map is taken from the launch camera, which frames a
                // whole country and shows a journey as a few pixels.
                case "focus": autoFocusZoom = true
                default: break
                }
            }
        }
        // The ambiguous-tap chooser, which otherwise needs a finger landing
        // within 18 points of two rides at once. The list it shows is built
        // the same way a real tap builds it — see `RideTapResolver`, whose
        // arithmetic is unit-tested; this only reaches the sheet.
        .task(id: "\(itineraries.loaded?.trains.count ?? -1)") {
            guard let count = ProcessInfo.processInfo.environment["RAILMAP_UI_TEST_CHOOSER"]
                .flatMap(Int.init), let trains = itineraries.loaded?.trains, trains.count >= count
            else { return }
            try? await Task.sleep(for: .milliseconds(1200))
            sheet = .chooseRide(Array(trains.prefix(count)))
        }
        .task(id: "\(itineraries.loaded?.trains.count ?? -1)") {
            guard itineraries.loaded != nil else { return }
            // Explicit synthetic UI input is isolated from production samples.
            // Pending records exercise rendering without claiming rail evidence.
            if let encoded = ProcessInfo.processInfo.environment["RAILMAP_UI_TEST_STORE_BASE64"],
               let data = Data(base64Encoded: encoded),
               let incoming = try? JSONDecoder().decode(TrainStore.self, from: data) {
                await itineraries.merge(incoming, into: library)
                return
            }
            guard let wanted = ProcessInfo.processInfo.environment["RAILMAP_UI_TEST_SAMPLE"],
                  let sample = RideLibrary.Sample.all.first(where: { $0.resource == wanted }),
                  let incoming = try? await library.sample(sample.resource) else { return }
            await itineraries.merge(incoming, into: library)
        }
#if DEBUG
        // What the reader would have typed into the search field.
        //
        // Same reason as every other hook in this block: a `simctl` harness
        // cannot type any more than it can tap, so without this the Search
        // destination is only ever reviewable in its EMPTY state — which is
        // exactly how it shipped with no field on it at all and nothing
        // noticed. The results state is now reachable from a screenshot run.
        .task {
            guard let wanted = ProcessInfo.processInfo
                .environment["RAILMAP_UI_TEST_QUERY"], !wanted.isEmpty
            else { return }
            query = wanted
        }
#endif
        .task(id: "\(riddenRoutes.rides.count)|\(controller.isMapReady)") {
            guard !didRunDebugPlayback,
                  ProcessInfo.processInfo.environment["RAILMAP_UI_TEST_PLAYBACK"] == "1",
                  controller.isMapReady, !riddenRoutes.rides.isEmpty,
                  let train = itineraries.loaded?.trains.first(where: {
                      let requestedID = ProcessInfo.processInfo
                          .environment["RAILMAP_UI_TEST_PLAYBACK_TRAIN_ID"]
                      return rideIDs.contains($0.id)
                          && (requestedID == nil || requestedID == $0.id)
                  }) else { return }
            didRunDebugPlayback = true
            try? await Task.sleep(for: .milliseconds(500))
            startPlayback([train])
            // Arming is not running. A harness that stopped at the overview
            // would screenshot a map with no train on it and call that
            // playback, so it presses play the way a reader does — after the
            // opening move has landed.
            try? await Task.sleep(
                for: .milliseconds(Int(Playback.Tuning.overviewMilliseconds) + 200))
            playback.begin()
        }
#endif
    }

    /// Everything this workspace can put OVER itself.
    ///
    /// Applied to the resident sheet's content rather than to the map beneath
    /// it (§9.5.6). A `UIViewController` that is already presenting cannot
    /// present again, and the resident sheet is always presenting — so an
    /// editor attached to the map root would be asking the one controller in
    /// the app that can never take it. Attached here, each of these stacks on
    /// top of the bottom chrome, which is also where the reader asked for it.
    private func withPresentations(_ content: some View) -> some View {
        content
        .modifier(WorkspacePresentations(
            dialog: $dialog, sheet: $sheet,
            onAddDate: { typed in
                guard let added = manualDates.add(typed) else { return }
                selectDate(added)
            },
            onDelete: { train in
                if itineraries.selectedTrainID == train.id {
                    itineraries.selectedTrainID = nil
                }
                editing.delete(train.id)
                signal(.deleted)
            },
            onSheetDismiss: {
                linePreview = nil
                // Expanding during the child's dismissal competes with UIKit's
                // sheet transition. Restore only after that presenter is free.
                workspaceMenuIsSuspended = false
                if journeyMenuOwnsSelection {
                    itineraries.selectedTrainID = selectionBeforeJourneyMenu
                    selectionBeforeJourneyMenu = nil
                    journeyMenuOwnsSelection = false
                }
                if journeyEditor == nil { presentationLayoutMode = nil }
            },
            sheetContent: presentedSheet))
        // Was attached to `statisticsPanel` directly, i.e. inside
        // `workspaceTabs` — which under the docked card is a
        // `.horizontalSizeClass` forced to `.compact` (see `dockedMenuContent`), so
        // this sheet presented at a compact size even in `.sideBySide`. Every
        // other presentation in this workspace already raises from here,
        // outside that override, and reads the WINDOW's own size class; this
        // one now does too.
        .sheet(item: $statisticsImage) { file in
            StatisticsShareView(file: file) { statisticsImage = nil }
        }
        // §13.2's harmony rule: the tap has to arrive with the change, so it is
        // driven by the same state the view is drawn from rather than by a
        // timer alongside it.
        .sensoryFeedback(trigger: feedback) { _, value in
            switch value?.kind {
            case .saved: .success
            case .deleted: .warning
            case .settled: .impact(flexibility: .soft)
            case nil: nil
            }
        }
        // The sheet settling on a stop. Not while it is dragged — that would be
        // a buzz following the finger; only on the value the system commits to.
        .onChange(of: stageSelection) { _, _ in signal(.settled) }
        .onDisappear {
            // The RECORDING cannot survive this: it captures the map view this
            // workspace owns. See `VideoExportFlow.abandonRecording` for why
            // the run itself is left playing.
            videoExport.abandonRecording()
            // The PLAYBACK deliberately does not stop here. §5.3.5 gives
            // Passport its own replay entry point over the same transport, and
            // the shell holds one `PlaybackController` for the whole app for
            // exactly that reason — so stopping it because a tab went off
            // screen would mean a run started in Journeys dying the moment the
            // reader opened Passport to watch it. A `TabView` calls
            // `onDisappear` on every tab switch, so this line was doing that
            // on each one. Stopping is a thing the reader asks for, from the
            // transport controls, in any workspace.
        }
    }

    private func presentedSheet(_ presented: WorkspaceSheet) -> some View {
        WorkspaceSheetContent(
            sheet: presented, itineraries: itineraries, library: library,
            controller: controller, network: store, importFlow: importFlow,
            videoSettings: videoExport.settings, videoSourceRect: playbackFilmedRect,
            videoSeconds: videoExport.plannedSeconds,
            videoDisplayScale: controller.mapView?.window?.screen.scale ?? 3,
            appearance: $appearance, categoryIndexesAreBuilding: categoryIndexes.isBuilding,
            selectedDateIsAllDates: selectedDate == Dates.allDates,
            presentation: { presentation(for: $0) },
            onSaveNew: { added in
                guard editing.add(added) != nil else { return }
                signal(.saved)
                sheet = nil
            },
            onSaveEdit: { edited, originalID in
                switch editing.replace(edited, replacing: originalID) {
                case .saved, .savedKeepingID:
                    sheet = nil
                case .refusedImportRunning, .notFound, .unsupportedRegion:
                    break
                }
            },
            onSaveDetail: { edited, originalID in
                editing.replace(edited, replacing: originalID)
            },
            onRebuild: rebuildRoute,
            onJourneyPrimary: { action, train in
                if action == .locate { stageSelection = .compact }
                perform(action, on: train)
            },
            onJourneySecondary: { action, train in perform(action, on: train) },
            onStartExport: startVideoExport,
            onDismiss: { sheet = nil },
            onPick: { train in PresentationHost.afterTeardown { pick(train) } },
            onLinePreview: { linePreview = $0 },
            onEditJourney: { train in
                sheet = nil
                presentJourneyEditor(JourneyEditorLaunch(
                    train: train, isNew: false, originalID: train.id))
            })
    }

    // MARK: - the map, and the resident sheet over it (§9.5.6)

    /// The whole compact interface: one map, and one sheet that never closes.
    ///
    /// The map is the ROOT, not a tab's content — every destination shares it
    /// (§4.2), which is why there is no map inside any of the panels any more.
    /// Everything else the reader touches lives in the sheet: the three
    /// destinations, the destination selector and the `+`.
    private func mapLayout(in geometry: GeometryProxy) -> some View {
        let metrics = chromeMetrics(in: geometry)
        return ResidentMapChrome(
            metrics: metrics,
            viewportHeight: geometry.size.height,
            bottomInset: geometry.safeAreaInsets.bottom,
            selectedStage: stageSelection,
            hidesMenu: hidesWorkspaceMenu,
            showsPlaybackBar: showsPlaybackBar,
            measurements: sheetMeasurements,
            morph: panelMorph,
            controller: controller,
            detent: detentBinding(metrics),
            mapContent: map,
            playbackContent: playbackBar,
            controls: controlStack(),
            menu: withPresentations(workspaceTabs()))
    }

    /// The detents, for this window AND this text size.
    private func chromeMetrics(in geometry: GeometryProxy) -> BottomChromeMetrics {
        BottomChromeMetrics(
            screenHeight: geometry.size.height,
            // The tab bar's band does not scale; the title row over it does.
            compactRow: BottomChromeMetrics.compactTabBand + compactHeaderRows,
            isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
    }

    /// The bound detent, derived from the stage rather than stored.
    ///
    /// Two of the three detents are `.height()` values computed from the
    /// window, so a STORED detent is a number from whatever the window used to
    /// be — and a detent that is not in the set the sheet was handed is one
    /// SwiftUI quietly replaces with another. Deriving it means the binding is
    /// always a member of `metrics.detents`, at every window size, including
    /// the frame after a rotation.
    private func detentBinding(_ metrics: BottomChromeMetrics) -> Binding<PresentationDetent> {
        Binding(
            get: {
                // Through `available(_:)`: at an accessibility text size there
                // is no half stop, and handing the sheet a detent that is not
                // in the set it was given is one SwiftUI quietly replaces —
                // with no way for this binding to learn what it picked.
                switch metrics.available(stageSelection) {
                case .compact: metrics.compactDetent
                case .medium: metrics.mediumDetent
                case .expanded: .large
                }
            },
            set: { chosen in
                if chosen == .large { stageSelection = .expanded }
                else if chosen == metrics.compactDetent { stageSelection = .compact }
                else { stageSelection = .medium }
            })
    }

    // MARK: - system destinations (§2.2, revised)

    /// Three destinations in the system capsule, with a trailing Search circle.
    @ViewBuilder private func workspaceTabs() -> some View {
        if let launch = journeyEditor {
            journeyEditorPage(launch)
        } else {
            WorkspaceTabs(selection: $selection) { tab in
                switch tab {
                case .upcoming:
                    page(tab) { upcomingPanel }
                case .stats:
                    page(tab) { statisticsPanel }
                case .all:
                    page(tab) { allJourneysPanel() }
                case .search:
                    page(tab) { searchPanel }
                }
            }
        }
    }

    private func journeyEditorPage(_ launch: JourneyEditorLaunch) -> some View {
        let title = localization.text(
            launch.isNew ? "ios.editorTitleNew" : "ios.edit",
            fallback: launch.isNew ? "New" : "Edit")
        return Group {
            if launch.isNew {
                NewTripView(
                    train: launch.train,
                    title: title,
                    onCancel: {
                        guard journeySaveAttemptID == nil else { return }
                        closeJourneyEditor()
                    },
                    onSave: { commitJourneyEditor($0, launch: launch) })
            } else {
                RideEditorView(
                    train: launch.train,
                    title: title,
                    isNew: launch.isNew,
                    suggestionTrains: itineraries.loaded?.trains ?? [],
                    onCancel: {
                        guard journeySaveAttemptID == nil else { return }
                        closeJourneyEditor()
                    },
                    onDraftMap: { snapshot in
                        guard controller.acceptsDraftMap else { return }
                        controller.draftMap = snapshot
                    },
                    highlightedStopID: $highlightedStopID,
                    onSave: { commitJourneyEditor($0, launch: launch) })
            }
        }
        .disabled(journeySaveAttemptID != nil)
        .alert(
            localization.journeyText(
                "ios.journey.saveFailedTitle", fallback: "Could not save this journey"),
            isPresented: Binding(
                get: { journeySaveFailureDetail != nil },
                set: { if !$0 { journeySaveFailureDetail = nil } })
        ) {
            Button(localization.text("ios.done", fallback: "Done"), role: .cancel) {
                journeySaveFailureDetail = nil
            }
        } message: {
            let kept = localization.journeyText(
                "ios.journey.saveFailedKept", fallback: "Your edits are still open.")
            if let detail = journeySaveFailureDetail, !detail.isEmpty {
                Text("\(kept)\n\n\(detail)")
            } else {
                Text(kept)
            }
        }
    }

    private func presentJourneyEditor(_ launch: JourneyEditorLaunch) {
        journeyEditorRecordID = nil
        journeySaveAttemptID = nil
        journeySaveFailureDetail = nil
        controller.acceptsDraftMap = true
        controller.draftMap = DraftMapSnapshot(
            revision: 0, pins: [], networkRideDate: launch.train.date)
        controller.onDraftPin = { highlightedStopID = $0 }
        journeyEditor = launch
    }

    private func closeJourneyEditor() {
        controller.acceptsDraftMap = false
        controller.onDraftPin = nil
        controller.draftMap = DraftMapSnapshot(revision: 0, pins: [])
        highlightedStopID = nil
        journeyEditorRecordID = nil
        journeySaveAttemptID = nil
        journeySaveFailureDetail = nil
        journeyEditor = nil
    }

    private func commitJourneyEditor(_ train: Train, launch: JourneyEditorLaunch) {
        guard journeySaveAttemptID == nil else { return }

        let persistence: Task<Bool, Never>
        let rollback: @MainActor () -> Bool
        if let committedID = journeyEditorRecordID {
            let attempt = editing.replaceAndPersist(train, replacing: committedID)
            guard let task = attempt.persistence, let undo = attempt.rollback else { return }
            switch attempt.outcome {
            case .saved:
                journeyEditorRecordID = train.id
            case let .savedKeepingID(keptID, _):
                journeyEditorRecordID = keptID
            case .refusedImportRunning, .notFound, .unsupportedRegion:
                return
            }
            persistence = task
            rollback = undo
        } else if launch.isNew {
            guard let attempt = editing.addAndPersist(train) else { return }
            journeyEditorRecordID = attempt.id
            persistence = attempt.persistence
            rollback = attempt.rollback
        } else {
            let attempt = editing.replaceAndPersist(
                train, replacing: launch.originalID ?? launch.train.id)
            guard let task = attempt.persistence, let undo = attempt.rollback else { return }
            switch attempt.outcome {
            case .saved:
                journeyEditorRecordID = train.id
            case let .savedKeepingID(keptID, _):
                journeyEditorRecordID = keptID
            case .refusedImportRunning, .notFound, .unsupportedRegion:
                return
            }
            persistence = task
            rollback = undo
        }

        let attemptID = UUID()
        journeySaveAttemptID = attemptID
        Task { @MainActor in
            let saved = await persistence.value
            guard journeySaveAttemptID == attemptID else { return }
            journeySaveAttemptID = nil
            guard saved else {
                if rollback() { journeyEditorRecordID = nil }
                journeySaveFailureDetail = library.lastSaveError ?? ""
                return
            }
            if launch.isNew { signal(.saved) }
            closeJourneyEditor()
        }
    }

    /// One destination's page, as a view of its own.
    ///
    /// `tabPage` composes the page; this is what MOUNTS it, and the two are
    /// separate for a reason that is not style. `TabView`'s builder folds its
    /// four `Tab`s into one value, and each one is built on top of the last —
    /// so the four pages accumulate on the main thread's stack, and the tab
    /// bar's own type names all four of them at once. That type is deep enough
    /// that instantiating its metadata recurses about forty frames on its own.
    ///
    /// Measured on an iPhone 16 Pro, whose main thread has 1,008 KB of stack:
    /// the first page reached its header row with 94 KB left, the second with
    /// 91, the third with 54, and the fourth with 13 — and the frame after
    /// that walked into the guard page. `EXC_BAD_ACCESS`, "Could not determine
    /// thread index for stack guard region", every time. Rotating is what made
    /// it certain rather than occasional: the docked card builds the same
    /// four pages INLINE in `body` (the sheet hosts them in a controller of
    /// its own, which is a stack of its own), and UIKit's rotation runs that
    /// body nested inside thirty-odd frames of its own transition machinery.
    ///
    /// None of this is reproducible in the simulator, where the main thread is
    /// a macOS main thread with 8 MB: twenty scenarios across iOS 26.5 and
    /// 27.0 — rotation, landscape launch, every tab, every sheet, the whole
    /// network drawn over Tokyo — all passed while the device failed on every
    /// single rotation.
    ///
    /// Erasing the page's type is what ends the accumulation. The tab bar's
    /// type stops naming the pages, and each page's content is built when
    /// SwiftUI asks THIS view for its body — from the graph's own stack, not
    /// from inside the pages built before it. The erased type is the same
    /// concrete type on every update, so the subtree keeps its identity, its
    /// scroll offsets and its focus.
    private func page<Content: View>(
        _ tab: PrimaryTab,
        @ViewBuilder content: @escaping () -> Content
    ) -> WorkspacePage {
        WorkspacePage {
            AnyView(tabPage(tab, content: content))
        }
    }

    private func tabPage<Content: View>(
        _ tab: PrimaryTab,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        WorkspacePanelPage {
            PanelHeader(
                title: panelTitle(for: tab),
                tabHeadings: PrimaryTab.allCases.map {
                    WorkspacePanelHeading(
                        title: panelTitle(for: $0),
                        hasSubtitle: !(panelSubtitle(for: $0)?
                            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true),
                        actionCount: $0.headerActionCount)
                },
                subtitle: panelSubtitle(for: tab)
            ) {
                panelActions(for: tab)
            }
        } content: {
            content()
        }
    }

    /// Selecting a journey presents its own sheet; this list stays mounted.
    private func allJourneysPanel() -> some View { ridesList }

    /// §5.3's scope, and the same answer as a set of ids for the map filter.
    ///
    /// Memoised together because the two are the same pass: `mapRides` used to
    /// rebuild the id set out of this list on every body evaluation, which on
    /// the Passport destination made a sheet drag a per-frame scan of every
    /// journey. See ``WorkspaceDerived``.
    ///
    /// Three filters, not two. A journey the record does not say was ridden is
    /// not in the numbers (see ``RailPresentation/RideLedger``), so it must not
    /// be on the coverage map either: §5.3.2 draws "the same records the
    /// numbers counted, and only those", and a line under a percentage that
    /// does not include it is the map contradicting the figure above it.
    private var statisticsScope: (trains: [Train], ids: Set<String>) {
        let trains = itineraries.loaded?.trains ?? []
        let date = statistics.selectedDate
        let region = regionScope
        return derived.statisticsScope(
            trains: trains, region: region, date: date, year: statistics.selectedYear,
            groupID: statistics.selectedJourneyGroupID, dates: statistics.dateSelection
        ) {
            WorkspaceJourneyRules.statisticsScope(
                trains: trains, regionCode: region?.code, selectedDate: date,
                rule: Region.scopeRule).filter {
                    statistics.includesYear($0) && statistics.includesJourneyGroup($0) && statistics.includesDate($0)
                }
        }
    }

    private func openData() {
        PresentationHost.afterTeardown { sheet = .utility(.data) }
    }

    private func openSettings() {
        PresentationHost.afterTeardown { sheet = .utility(.settings) }
    }

    /// §5.3's Passport, by its plainer name. The coverage map it used to draw
    /// inside itself is the root map now — one basemap for all three
    /// destinations, which is what stopped this screen from being a second
    /// `MKMapView` over the first one.
    /// The statistics destination's own presentation anchor — the first sheet
    /// in this app that is not raised through `WorkspaceSheet`.
    ///
    /// `WorkspaceSheet`'s note says why there is normally one anchor: four
    /// `isPresented` bindings racing for it is how a "Delete" dialog swallows
    /// the editor opening behind it. That is about four bindings on ONE view.
    /// `.utility`'s note states the other half — the shell cannot present these
    /// at all, because it is already presenting the resident sheet and one
    /// controller cannot present two.
    ///
    /// Neither says a destination inside that sheet may not have an anchor of
    /// its own, and it can: `ConsoleSweepTests.walkStatisticsShare` opens this
    /// one and then walks the shared anchor's sheets in the same run, with
    /// nothing in the console about presenting twice. What makes it safe is
    /// that the destinations are mutually exclusive — only the tab on screen
    /// can be trying to present.
    private enum StatisticsShareRequest: Hashable {
        case map(ColorScheme)
        case statistics(ColorScheme)

        var colorScheme: ColorScheme {
            switch self {
            case .map(let scheme), .statistics(let scheme): scheme
            }
        }
        var includesMap: Bool {
            if case .map = self { return true }
            return false
        }
    }

    @State private var statisticsShare = ShareRequestController<StatisticsShareRequest>()
    @State private var statisticsScopePresented = false
    @State private var statisticsImage: StatisticsPoster.File?

    private var statisticsPanel: some View {
        PassportWorkspaceView(
            itineraries: itineraries,
            statistics: statistics,
            riddenRoutes: riddenRoutes,
            network: store,
            controller: controller,
            playback: playback,
            region: $regionScope,
            scopedTrains: statisticsScope.trains,
            derived: derived,
            journeyPresentation: { presentation(for: $0) },
            openJourney: { sheet = .detail($0.id) },
            openData: openData,
            openSettings: openSettings)
    }

    // MARK: - the panel header (§9.5.6: 左上大标题, 右上功能按钮)

    /// The title changes with the destination or selected journey, never its height.
    private func panelTitle(for tab: PrimaryTab) -> String {
        switch tab {
        case .upcoming:
            localization.text("nav.upcoming", fallback: "Upcoming")
        case .stats:
            localization.text("nav.stats", fallback: "Stats")
        case .all:
            localization.text("nav.allJourneys", fallback: "All journeys")
        case .search:
            localization.countryText("sec.search", fallback: "Search & Add")
        }
    }

    private func panelSubtitle(for tab: PrimaryTab) -> String? {
        switch tab {
        case .upcoming:
            guard let count = upcomingCount else { return nil }
            return localization.journeyText(
                "ios.journey.daySummary", ["journeys": .number(Double(count))],
                fallback: "{journeys} journeys")
        case .stats:
            // Nothing. §5.3.1's Scope is the pair of capsules in the action
            // row beside this title — always visible, at every sheet stop —
            // and the subtitle used to spell the date one of them already
            // states. One value, one place it is written.
            return nil
        case .all:
            // The FILTERED counts, not the store's: this line is now the
            // list's own summary row (§5.1), which the search field and the
            // date filter both narrow. A header that kept saying "231
            // journeys" over four search results would be describing a list
            // that is not on screen.
            guard let loaded = itineraries.loaded else { return nil }
            let days = filteredDays(loaded, region: regionScope)
            let journeys = days.reduce(0) { $0 + $1.trains.count }
            return selectedDate == Dates.allDates
                ? localization.journeyText(
                    "ios.journey.listSummary",
                    [
                        "journeys": .number(Double(journeys)),
                        "days": .number(Double(days.count)),
                    ],
                    fallback: "{journeys} journeys · {days} days")
                : localization.journeyText(
                    "ios.journey.daySummary",
                    ["journeys": .number(Double(journeys))],
                    fallback: "{journeys} journeys")
        case .search:
            let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !needle.isEmpty, let loaded = itineraries.loaded else { return nil }
            let journeys = filteredDays(loaded, region: nil, query: needle)
                .reduce(0) { $0 + $1.trains.count }
            return localization.journeyText(
                "ios.journey.daySummary",
                ["journeys": .number(Double(journeys))],
                fallback: "{journeys} journeys")
        }
    }

    /// The function buttons, top right.
    ///
    /// The row is the destination's own scope and its own verb, then the
    /// Utility entry §4.1 requires in one place on every surface.
    ///
    /// ## The two scope buttons (§5.1, §5.3.1)
    ///
    /// Upcoming, All Journeys and 統計 each carry a round DATE button and a
    /// round REGION button, in that order, and they are the same two controls
    /// on all three. The date filter used to be a submenu inside the gear —
    /// the reader's own report is that a filter is not a setting, and a scope
    /// that has to be found under 設定 is one nobody finds. The region used to
    /// exist on 統計 alone, as a capsule wide enough to spell its value.
    ///
    /// Round and unlabelled, both of them state their value the only way a
    /// glyph can: ``SheetIconLabel/isActive`` tints the button when the scope
    /// is narrowed. What they are scoped TO is one tap away, and the menu
    /// marks it.
    ///
    /// Search keeps its date filter in the gear. It is the one destination
    /// whose question is the query, and its header already carries the `+`.
    private func panelActions(for tab: PrimaryTab) -> some View {
        return WorkspacePanelActions(
            tab: tab,
            newJourney: {
                presentJourneyEditor(JourneyEditorLaunch(
                    train: newJourneyScaffold(in: defaultRegion), isNew: true, originalID: nil))
            },
            playback: { playbackButton },
            journeyDate: { journeyDateMenu(for: tab) },
            region: { regionMenu },
            statisticsDate: { statisticsDateMenu },
            statisticsShare: { statisticsShareButton },
            destinationMenu: { destinationMenu(for: tab) })
    }

    @ViewBuilder
    private func destinationMenu(for tab: PrimaryTab) -> some View {
        if tab == .all || tab == .upcoming || tab == .search {
            // The date filter is a BUTTON on Upcoming and All Journeys now
            // (see ``panelActions(for:)``), so it appears here only for
            // Search — one filter must not have two entries in one state.
            if tab == .search, let loaded = itineraries.loaded, !loaded.days.isEmpty {
                dateFilterSection(loaded)
            }
            rideSourceSection
            Divider()
        }
        WorkspaceUtilityMenuItems(
            onOpenData: openData,
            onOpenSettings: openSettings)
    }

    /// The regions the globe menu offers: the ones this store has journeys in.
    ///
    /// Never date-filtered and never scope-filtered, or choosing a region
    /// would empty the menu that chose it — the same rule ``statisticsDates``
    /// keeps for the calendar beside it. Ridden or not, planned or past: a
    /// journey on record in a region is a reason that region can be scoped to,
    /// and the three destinations that share this control each answer a
    /// different question about that record.
    private var scopableRegions: [Region] {
        derived.regions(in: itineraries.loaded?.trains ?? [])
    }

    /// What the scope control reads, 全部 included.
    private var regionScopeName: String {
        guard let regionScope else {
            return localization.text("ios.region.all", fallback: "All regions")
        }
        return localization.text(
            regionScope.localizationKey, fallback: regionScope.fallbackName)
    }

    /// §5.3.1's date Scope, in the header row rather than in a card.
    ///
    /// It used to live inside 當日統計, where the numbers it scopes are — a
    /// reasonable place for it while the daily block was its own card. The
    /// daily block is now a stamp inside the passport page, and a control
    /// buried a scroll into the panel cannot be found from the top of it.
    /// Here it is the neighbour of the region button, which is the other half
    /// of the same scope, and both are on screen at every sheet stop.
    ///
    /// It changes the statistics only. §5.3.1: "Passport 的日期 Scope 独立于
    /// Journeys 筛选，切换后不扰动旅程列表" — ``journeyDateMenu(for:)`` is the
    /// other tabs' filter and is a different value with a different owner.
    private var statisticsDateMenu: some View {
        Button {
            statisticsScopePresented = true
        } label: {
            SheetIconLabel(
                systemImage: "calendar",
                isActive: !statistics.dateSelection.isEmpty || statistics.selectedJourneyGroupID != nil)
        }
        .popover(isPresented: $statisticsScopePresented) {
            StatisticsScopePicker(
                statistics: statistics,
                availableDates: statisticsDates,
                groups: statisticsJourneyGroups,
                selectGroup: { groupID in
                    if groupID != nil { regionScope = nil }
                    statistics.selectJourneyGroup(groupID)
                })
                .presentationCompactAdaptation(.sheet)
        }
        .accessibilityLabel(Text(localization.statsText("ios.stats.scope")))
        .accessibilityValue(Text(statisticsScopeLabel))
        .accessibilityIdentifier("statisticsDateButton")
    }

    private var statisticsJourneyGroups: [JourneyGroup] {
        var seen = Set<String>()
        return (itineraries.store?.trains ?? itineraries.loaded?.trains ?? [])
            .compactMap(\.journeyGroup).filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var statisticsScopeLabel: String {
        if let groupID = statistics.selectedJourneyGroupID {
            return statisticsJourneyGroups.first { $0.id == groupID }?.name
                ?? localization.groupText("all")
        }
        return localization.statisticsDateScopeLabel(statistics.dateSelection)
    }

    /// Choice availability ignores the active date and group filter, so
    /// switching classification always offers all ridden days in this region/year.
    private var statisticsDates: [String] {
        guard let loaded = itineraries.loaded else { return [] }
        return derived.scopedDates(
            trains: loaded.trains, days: loaded.days, region: regionScope,
            year: statistics.selectedYear)
    }

    /// §5.3.1's region scope, in the header rather than in a card — and now on
    /// all three destinations that ask a question about one network.
    ///
    /// A globe, at the reader's own request, rather than the capsule that
    /// spelled the region's name. What the round shape gives up is the value,
    /// so the button is TINTED whenever the scope is narrowed: the reader can
    /// still see at a glance that they are not looking at everything, and the
    /// menu below says which region when they ask.
    ///
    /// ## Only the regions the reader has been to
    ///
    /// The menu lists the regions this store actually holds journeys in, not
    /// the catalog's five. A scope that can only ever produce an empty list is
    /// not a choice — 澳門 offered to somebody who has never ridden there is a
    /// button whose whole effect is to blank the screen they were reading, and
    /// they then have to work out which of the six entries undoes it.
    ///
    /// 全部地區 is always there, and it is the reason this can be safe to
    /// narrow: it is the absence of the scope rather than a sixth region, so
    /// the way back is on the menu whatever the store contains. A reader whose
    /// last journey in a region is deleted while scoped to it keeps that scope
    /// — the list says it is empty and 全部地區 is one tap away — rather than
    /// having the app silently move them somewhere they did not ask to be.
    private var regionMenu: some View {
        Menu {
            // 全部 first, and above a divider: it is not a sixth region, it is
            // the absence of the scope the other five apply.
            Button {
                regionScope = nil
            } label: {
                Label(
                    localization.text("ios.region.all", fallback: "All regions"),
                    systemImage: regionScope == nil ? "checkmark" : "globe.asia.australia")
            }
            if !scopableRegions.isEmpty { Divider() }
            ForEach(scopableRegions) { candidate in
                Button {
                    selectRegion(candidate)
                } label: {
                    Label(
                        localization.text(
                            candidate.localizationKey, fallback: candidate.fallbackName),
                        systemImage: candidate == regionScope ? "checkmark" : "map")
                }
            }
        } label: {
            SheetIconLabel(
                systemImage: "globe.asia.australia", isActive: regionScope != nil)
        }
        .accessibilityLabel(Text(localization.text("country.label", fallback: "Region")))
        .accessibilityValue(Text(regionScopeName))
        .accessibilityIdentifier("regionScopeButton")
    }

    private func selectRegion(_ region: Region) {
        guard yieldRun() else { return }
        regionScope = region
        controller.cancelAutoFocus()
        controller.fit(region.completeNetworkExtent)
    }

    /// §5.3.5's share, for the numbers rather than for the film.
    ///
    /// The passport's own card offers a REPLAY and a JSON export; neither is a
    /// picture, and a picture is what somebody actually posts at the end of a
    /// year of travelling. It sits in the header rather than in that card for
    /// the reason the two scope buttons do: it is a thing this destination can
    /// do, and §9.5.6 gives every destination one row for exactly those.
    ///
    /// Rendered on the spot rather than kept ready. The page is several
    /// thousand points tall and its bitmap is measured in tens of megabytes,
    /// so holding one against the chance the reader taps this would be paying
    /// for the feature on every screen that never uses it.
    ///
    /// Disabled while there is nothing to draw: an image of a screen that is
    /// still calculating is a picture of a spinner.
    private var statisticsShareButton: some View {
        Menu {
            Menu {
                Button {
                    statisticsShare.begin(.map(.light))
                } label: {
                    Label(localization.statsText("ios.stats.shareLight"), systemImage: "sun.max")
                }
                .accessibilityIdentifier("mapShareLightButton")
                Button {
                    statisticsShare.begin(.map(.dark))
                } label: {
                    Label(localization.statsText("ios.stats.shareDark"), systemImage: "moon")
                }
                .accessibilityIdentifier("mapShareDarkButton")
            } label: {
                Label(localization.statsText("ios.stats.shareMapOption"), systemImage: "map")
            }
            .accessibilityIdentifier("mapShareOption")
            Menu {
                Button {
                    statisticsShare.begin(.statistics(.light))
                } label: {
                    Label(localization.statsText("ios.stats.shareLight"), systemImage: "sun.max")
                }
                .accessibilityIdentifier("statisticsShareLightButton")
                Button {
                    statisticsShare.begin(.statistics(.dark))
                } label: {
                    Label(localization.statsText("ios.stats.shareDark"), systemImage: "moon")
                }
                .accessibilityIdentifier("statisticsShareDarkButton")
            } label: {
                Label(localization.statsText("ios.stats.shareStatisticsOption"), systemImage: "chart.bar")
            }
            .accessibilityIdentifier("statisticsShareOption")
        } label: {
            SheetIconLabel(systemImage: "square.and.arrow.up")
        }
        .accessibilityLabel(Text(localization.statsText("ios.stats.shareImage")))
        .disabled(statistics.view == nil || statisticsShare.request != nil)
        .overlay { if statisticsShare.request != nil { ProgressView().allowsHitTesting(false) } }
        .task(id: statisticsShare.request?.id) {
            guard let ticket = statisticsShare.request else { return }
            let request = ticket.input
            let year = statistics.selectedYear
            let date = statistics.selectedDate
            let dates = statistics.dateSelection
            let groupID = statistics.selectedJourneyGroupID
            let region = regionScope
            let storeGeneration = itineraries.storeGeneration
            let isCurrent: @MainActor @Sendable () -> Bool = {
                statistics.selectedYear == year && statistics.selectedDate == date
                    && statistics.dateSelection == dates && statistics.selectedJourneyGroupID == groupID
                    && regionScope == region && statistics.view != nil
                    && itineraries.storeGeneration == storeGeneration
            }
            let file: StatisticsPoster.File? = await statisticsShare.perform(ticket, isCurrent: isCurrent, operation: {
                let mapImage = request.includesMap
                    ? await StatisticsMapSnapshot.render(
                        rides: mapRides,
                        fallback: regionScope?.networkExtent ?? controller.mapView?.region,
                        colorScheme: request.colorScheme)
                    : nil
                guard isCurrent(), !Task.isCancelled else { return nil }
                if request.includesMap && mapImage == nil { return nil }
                return await renderStatisticsImage(colorScheme: request.colorScheme, mapImage: mapImage)
            })
            guard let file else { return }
            PresentationHost.afterTeardown {
                guard statisticsShare.isLatest(ticket), isCurrent() else { return }
                statisticsImage = file
            }
        }
        .onDisappear { statisticsShare.cancel() }
        .accessibilityIdentifier("statisticsShareButton")
    }

    /// The statistics page, as a PNG on disk. `nil` if it could not be drawn
    /// or could not be written, in which case nothing is presented.
    private func renderStatisticsImage(
        colorScheme: ColorScheme, mapImage: UIImage?
    ) async -> StatisticsPoster.File? {
        await StatisticsPoster.render(
            itineraries: itineraries,
            statistics: statistics,
            region: regionScope,
            // The two scopes, spelled out. On screen they are the two round
            // buttons beside this one and they stay on screen while the
            // numbers are read; an image travels without them.
            scope: localization.statsText(
                "ios.stats.shareScope",
                params: [
                    "region": .string(regionScopeName),
                    "date": .string(!statistics.dateSelection.isEmpty || statistics.selectedJourneyGroupID != nil
                        ? statisticsScopeLabel : statistics.selectedYear.map(String.init)
                            ?? localization.statsText("ios.stats.allTime")),
                ]),
            title: mapImage == nil
                ? localization.text("nav.stats", fallback: "Stats")
                : localization.statsText("ios.stats.shareMapTitle"),
            localization: localization,
            journeyPresentation: { presentation(for: $0) },
            colorScheme: colorScheme,
            mapImage: mapImage)
    }

    private var playbackButton: some View {
        SheetIconButton(
            systemImage: playback.isActive ? "stop.fill" : "play.fill",
            accessibilityLabel: Text(
                playback.isActive
                    ? localization.countryText("play.stop", fallback: "Stop playback")
                    : localization.countryText("btn.play", fallback: "Play rides"))
        ) {
            if playback.isActive {
                stopPlayback()
            } else {
                startPlayback(playbackScope)
            }
        }
        .disabled(!playback.isActive && playbackScope.isEmpty)
    }

    // MARK: - §5.1 (new): what is coming

    /// The journeys that have not happened yet, soonest first.
    ///
    /// "Not yet" is decided by the date the record carries, not by a live
    /// service: §1.1 forbids implying departures, delays or operation. A dated
    /// record on or after today is upcoming; an undated one is not — it has no
    /// position on a calendar to be ahead of, and putting it here would be
    /// claiming one.
    ///
    /// **Today is the ride's, not the device's.** With five networks in one
    /// store there are five answers to "what day is it" at any instant, and
    /// the one that decides whether a journey is still ahead is the one where
    /// the journey is: a Tokyo ride dated 2026-08-27 stopped being upcoming
    /// when Japan reached the 28th, not when London did six hours later. One
    /// `Date()` for all five, so that two rides in one region cannot land on
    /// different days by being asked a millisecond apart.
    private var upcomingTrains: [Train] { upcomingScope.trains }

    /// The same answer, plus the ids the map filters on — one pass, for the
    /// same reason ``statisticsScope`` is a pair: the Upcoming destination
    /// draws exactly the journeys its list holds (§4.2), so the list and the
    /// map must not be able to disagree about what is still ahead.
    private var upcomingScope: (trains: [Train], ids: Set<String>) {
        let today = todayByRegion()
        let trains = itineraries.loaded?.trains ?? []
        let region = regionScope
        let scopedDate = selectedDate
        return derived.upcoming(
            trains: trains, today: today, region: region, date: scopedDate
        ) {
            WorkspaceJourneyRules.upcomingScope(
                trains: trains, regionCode: region?.code, selectedDate: scopedDate,
                todayByRegion: Dictionary(uniqueKeysWithValues: today.map { ($0.key.code, $0.value) }),
                rule: Region.scopeRule)
        }
    }

    /// Today, on each of the five clocks.
    ///
    /// One `Date()` for all of them, so that two rides in one region cannot
    /// land on different days by being asked a millisecond apart — and one
    /// owner, so that "is this ahead of me", "is this behind me" and "may the
    /// statistics count this yet" cannot come to answer against different
    /// todays. See ``RegionToday``, which is that owner.
    ///
    /// Nothing about the STATISTICS is asked of it. What the passport counts
    /// is a stated fact on the record, not a date — see
    /// ``RailPresentation/RideLedger``.
    private func todayByRegion() -> [Region: String] {
        RegionToday.byRegion()
    }

    // MARK: - where the map opens

    /// The box the map opens on, once something can answer for it.
    ///
    /// Two of the three modes answer immediately, because neither depends on
    /// the rides: a reader who has said 全球, or named a country, gets it in
    /// the same breath as the map. Only 自動 waits, and it waits on the rides
    /// rather than on the rail packages — see the framing task above.
    private var launchExtent: MKCoordinateRegion? {
        // An unrecognised stored value is `auto`, not a crash: preferences
        // outlive the builds that wrote them.
        switch LaunchMapScope(rawValue: launchScope) ?? .auto {
        case .world:
            return Region.everyNetworkExtent
        case .region:
            let region = Region(rawValue: launchScopeRegion) ?? .jp
            return region.isEnabled ? region.networkExtent : Region.eastAsiaNetworkExtent
        case .auto:
            switch itineraries.state {
            case .idle, .loading:
                return nil
            case .failed:
                return Region.eastAsiaNetworkExtent
            case .loaded(let loaded):
                let today = todayByRegion()
                guard let first = LaunchJourneySelector.first(
                    in: loaded.trains,
                    today: { train in today[Region.resolved(train)] }
                ) else {
                    // A route-only sample is not a journey. In particular, a
                    // loaded Macao network demonstration must not turn the
                    // neutral empty-store view into a Macao launch.
                    return Region.eastAsiaNetworkExtent
                }
                return Region.resolved(first).networkExtent
            }
        }
    }

    /// What the opening move is waiting on, as something cheap to compare.
    ///
    /// `LoadState` is not `Equatable` and ``launchExtent`` can cost a pass over
    /// every ride; this is read on every body evaluation, so it is neither.
    private var launchFramingKey: String {
        switch itineraries.state {
        case .idle: "idle"
        case .loading: "loading"
        case .failed: "failed"
        case .loaded(let loaded): "loaded:\(loaded.trains.count)"
        }
    }

    private var upcomingCount: Int? {
        guard itineraries.loaded != nil else { return nil }
        return upcomingTrains.count
    }

    @ViewBuilder
    private var upcomingPanel: some View {
        let trains = upcomingTrains
        if trains.isEmpty {
            // §13.1: an empty upcoming list is not a failure and not an empty
            // app — there is a whole log behind the next tab. Say which of the
            // two this is rather than showing a bare "nothing here".
            VStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text(localization.journeyText(
                    "ios.journey.noUpcoming", fallback: "No upcoming journeys."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(localization.text("nav.allJourneys", fallback: "All journeys")) {
                    selection = .all
                }
                .buttonStyle(.bordered)
                .railMinimumTouchTarget()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            // Scrollable so it survives the compact stop and an accessibility
            // text size, where an empty state can be taller than the panel.
            .modifier(ScrollableIfNeeded())
        } else {
            List {
                ForEach(trains, id: \.id) { train in
                    journeyRow(train, showsDate: true)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - the wide-window workspace

    /// The docked card's own margin from the window's edges. Read from
    /// `WorkspaceLayoutPolicy` rather than restated as a local 16, because
    /// `mode`'s own breakpoint now spends that same number twice deciding
    /// whether a window is wide enough to dock a card at all — a local
    /// constant here could drift from the one the policy actually measured
    /// against.
    private static let dockInset = CGFloat(WorkspaceLayoutPolicy.dockInset)

    /// The one wide-window composition: a full-window map with the same menu
    /// the phone presents as a resident sheet, docked as a floating card on
    /// the leading edge instead.
    ///
    /// This used to be two shapes — a two-column split for medium windows and
    /// a native three-column `NavigationSplitView` with its own `List`
    /// sidebar above 1,180 pt — and the wider of the two is gone. It drew
    /// iPadOS's own top tab capsule where the phone and the two-column
    /// composition both drew a bottom tab bar, so which of the reader's four
    /// destinations was a tap away, and which chrome was even on screen,
    /// depended on a window's WIDTH rather than on what the reader was doing.
    /// One docked card covers normal windows from 692 pt up and landscape
    /// windows from 632 pt up, on iPad and Mac Catalyst alike, and it is a
    /// function of window size the same way
    /// `mapLayout` is: no idiom check, no Catalyst check.
    ///
    /// The card now retracts and expands between the phone sheet's own three
    /// stops — compact, half, full — instead of always drawing expanded.
    /// There is no system sheet here to measure a fraction of the window and
    /// hand back a height, so its room determines `BottomChromeMetrics` and
    /// the selected stop determines the card's height. The adjacent toggle
    /// changes that stop; the title remains an ordinary header.
    private func sideBySideLayout(in geometry: GeometryProxy, panelWidth: CGFloat) -> some View {
        let safeAreaLeading = geometry.safeAreaInsets.leading
        // Kept out of `applyDockObstruction`'s inputs on purpose: the covered
        // strip is a function of the card's WIDTH, not its height, so the
        // camera does not get reframed every time the card breathes between
        // its stops — only when the window itself, or the card's width in
        // it, actually changes.
        // The card's bottom margin is measured from the window's edge, not
        // from the home indicator's safe area (see the padding below).
        let safeAreaBottom = geometry.safeAreaInsets.bottom
        let dockBottomGap = max(Self.dockInset, safeAreaBottom)
        let room = geometry.size.height + safeAreaBottom - Self.dockInset - dockBottomGap
        let metrics = BottomChromeMetrics(
            screenHeight: room,
            compactRow: BottomChromeMetrics.compactTabBand + compactHeaderRows,
            isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
        return ZStack(alignment: .bottomLeading) {
            wideMapSurface(in: geometry, panelWidth: panelWidth)
            HStack(alignment: .top, spacing: 8) {
                DockedCard(
                    content: dockedMenuContent(metrics: metrics),
                    width: panelWidth,
                    room: room,
                    metrics: metrics,
                    settledStage: metrics.available(stageSelection),
                    morph: panelMorph)
                dockPanelToggle(metrics: metrics)
            }
            .environment(panelMorph)
            .offset(y: hidesWorkspaceMenu ? room + safeAreaBottom : 0)
            .allowsHitTesting(!hidesWorkspaceMenu)
            .accessibilityHidden(hidesWorkspaceMenu)
            .railAnimation(
                RailMotion.spring, value: hidesWorkspaceMenu,
                reduceMotion: reduceMotion)
            // The adjacent toggle resizes the docked card with the app's
            // normal spring. Its title has no custom drag behavior.
            .railAnimation(RailMotion.spring, value: stageSelection, reduceMotion: reduceMotion)
                // Inside the safe area, not clipped to it: the phone sheet
                // reaches the same clearance from the status bar and the home
                // indicator by riding the safe area rather than padding past
                // it, and a card floating over a full-window map needs the
                // same margin for the same reason — the window's own chrome,
                // not this view's.
                .padding([.top, .horizontal], Self.dockInset)
                // …except the bottom, which is measured from the window's
                // edge: `dockInset`, or the home-indicator inset where that is
                // larger. Padding inside the safe area put the iPad card
                // 16 + 20 pt off the bottom against 16 pt on the leading side.
                // It cannot go below the indicator's inset either: once the
                // card overlaps that zone SwiftUI hands its tab controller the
                // whole 20 pt inset, and UIKit's floating bar then drops flush
                // onto the card's bottom edge.
                .padding(.bottom, dockBottomGap - safeAreaBottom)
        }
        .onAppear {
            applyDockObstruction(panelWidth, safeAreaLeading: safeAreaLeading)
            applyDockLogoMargin(bottomGap: dockBottomGap, safeAreaBottom: safeAreaBottom)
        }
        .onChange(of: dockBottomGap) { _, gap in
            applyDockLogoMargin(bottomGap: gap, safeAreaBottom: safeAreaBottom)
        }
        .onChange(of: panelWidth) { _, width in
            applyDockObstruction(width, safeAreaLeading: safeAreaLeading)
        }
        .onChange(of: safeAreaLeading) { _, leading in
            applyDockObstruction(panelWidth, safeAreaLeading: leading)
        }
        .onChange(of: hidesWorkspaceMenu) { _, _ in
            applyDockObstruction(panelWidth, safeAreaLeading: safeAreaLeading)
        }
        // The card is only real while this composition is mounted. Without
        // this, a resize down to `.compactOverlay` would leave the map
        // framing and MapKit's own Legal label shifted off a card that no
        // longer exists — `mapLayout`'s own `.onAppear` is the other half of
        // this handoff.
        .onDisappear {
            controller.leadingObstruction = 0
            controller.dockedBottomMargin = nil
        }
    }

    /// The phone's own menu, unmodified apart from the size class it reads.
    /// This is the STORED content `DockedCard` hosts as its shell — the
    /// frame and surface live there; the adjacent toggle owns resizing.
    ///
    /// `workspaceTabs` is what `mapLayout` puts inside the resident sheet —
    /// same four tabs, same pages, same resident-layer state. The only
    /// difference here is `.horizontalSizeClass`: a docked card is between
    /// 300 and 440 pt wide, which is a compact width whatever the surrounding
    /// window is, and forcing the environment to say so is what keeps its
    /// `TabView` drawing the phone's bottom tab bar instead of iPadOS's top
    /// tab capsule, which is what a `.regular` class would otherwise draw
    /// once the window itself is wide enough to be `.sideBySide` at all.
    ///
    /// Applied INSIDE `withPresentations` rather than around this whole
    /// function's result, so a sheet or confirmation dialog presented from
    /// the card keeps the WINDOW's own size class — full-width on iPad,
    /// exactly as `mapLayout`'s sheets already are — rather than inheriting a
    /// forced-compact presentation style meant only for the tab bar.
    ///
    /// `stageSelection` is shared with the phone sheet's own state — a
    /// rotation between the two compositions keeps the reader's stop instead
    /// of resetting it, the same way `detentBinding(_:)` keeps it for a
    /// rotation that stays on the phone.
    private func dockedMenuContent(metrics: BottomChromeMetrics) -> some View {
        withPresentations(
            workspaceTabs()
                .environment(\.horizontalSizeClass, .compact)
                .environment(\.railOnDockSurface, true)
                // The system bar sits 2 pt closer to the card's bottom than to
                // its sides; lifting it by that much makes all three gaps
                // 11.5 pt.
                .padding(.bottom, 2)
                // Expose the same panel sizes to assistive technology as the
                // adjacent toggle offers to touch and keyboard users.
                .environment(
                    \.railSheetStageAction,
                    RailSheetStageAction(
                        move: { requested in
                            settleDock(at: requested, metrics: metrics)
                        },
                        stages: metrics.stages)
                )
        )
    }

    /// Beside the card so narrow windows retain the phone header's reading
    /// width. This single control also owns the dock's keyboard shortcut.
    private func dockPanelToggle(metrics: BottomChromeMetrics) -> some View {
        PanelStageReader { stage in
            let label = stage == .compact
                ? localization.text("ios.panel.reopen", fallback: "Expand panel")
                : localization.text("ios.sheet.collapse", fallback: "Collapse panel")
            SheetIconButton(
                systemImage: stage == .compact ? "chevron.up" : "chevron.down",
                accessibilityLabel: Text(label)
            ) {
                // Accessibility layouts can omit the medium stop. Reopening
                // must choose an offered open stop, never resolve back to compact.
                let openStage = metrics.stages.contains(lastOpenDockStage)
                    && lastOpenDockStage != .compact ? lastOpenDockStage : .expanded
                settleDock(
                    at: stage == .compact ? openStage : .compact,
                    metrics: metrics)
            }
            // Match the phone header's chrome glyph ceiling; reading text still
            // follows the full accessibility size range.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .railGlass(in: Circle(), interactive: true)
            .help(label)
            .keyboardShortcut("s", modifiers: [.command, .option])
            .accessibilityIdentifier("dockPanelToggle")
            .accessibilityValue(Text(String(describing: stage)))
        }
    }

    private func settleDock(at requested: SheetStage, metrics: BottomChromeMetrics) {
        let target = metrics.available(requested)
        if target == .compact, stageSelection != .compact {
            lastOpenDockStage = stageSelection
        } else if target != .compact {
            lastOpenDockStage = target
        }
        withAnimation(RailMotion.animation(RailMotion.spring, reduceMotion: reduceMotion)) {
            stageSelection = target
            panelMorph.update(
                stage: target,
                expansion: metrics.headerExpansionProgress(for: metrics.height(of: target)))
        }
    }

    /// Tell the controller how much of the map's leading edge the card is
    /// covering, so both halves of §9.5.6's clearance rule — "frame this"
    /// and MapKit's own Legal label — read the strip the reader can actually
    /// see rather than the strip behind the card.
    ///
    /// `bottomObstruction` is reset to zero rather than left alone: nothing
    /// in this composition sits over the map's bottom edge, and a window that
    /// crossed into `.sideBySide` FROM `.compactOverlay` would otherwise carry
    /// the phone sheet's last reported height in ``RailMapController`` forever.
    ///
    /// `safeAreaLeading` accounts for a gap the root `GeometryReader` does
    /// not: it reports the safe-area-INSET size, but the map itself
    /// `.ignoresSafeArea()`, so on a notched phone in landscape the card's
    /// `.padding(Self.dockInset)` lands `safeAreaInsets.leading` further from
    /// the map's own left edge than `panelWidth + 2 × dockInset` alone would
    /// say — the card's trailing edge sits over map content this number
    /// leaves unaccounted for otherwise.
    /// Puts the bottom of MapKit's Apple Maps logo on the bottom of the
    /// card's tab bar. That bar sits 12 pt inside the card on every side (the
    /// system bar with `dockedMenuContent`'s lift, and the Mac's own bar), so
    /// its bottom is `bottomGap + 12` above the window's edge. MapKit measures
    /// its layout margin from the safe area, and the logo's glyphs sit 11 pt
    /// above that margin.
    private func applyDockLogoMargin(bottomGap: CGFloat, safeAreaBottom: CGFloat) {
        let barBottom = bottomGap + 12
        let logoGlyphPadding: CGFloat = 11
        controller.dockedBottomMargin = max(0, barBottom - safeAreaBottom - logoGlyphPadding)
    }

    private func applyDockObstruction(_ panelWidth: CGFloat, safeAreaLeading: CGFloat) {
        if hidesWorkspaceMenu {
            controller.leadingObstruction = 0
        } else {
            controller.leadingObstruction = panelWidth + Self.dockInset * 2 + safeAreaLeading
        }
        controller.bottomObstruction = 0
    }

    /// One map composition for the wide workspace. Kept separate from
    /// ``sideBySideLayout(in:panelWidth:)`` so the docked card's own
    /// `ZStack` reads as "map, then card" rather than as one long body.
    private func wideMapSurface(in geometry: GeometryProxy, panelWidth: CGFloat) -> some View {
        // The toggle beside the dock owns its own 44 pt column. Playback must
        // clear both that column and the menu, even on a landscape phone.
        let leading = panelWidth + Self.dockInset + 8 + WorkspaceMenuMetrics.touchSide + 12
        let width = max(0, geometry.size.width - leading - 12)
        let transportHeight = showsPlaybackBar ? playbackBarHeight + 12 : 0
        let railPresent = geometry.size.height >= railHeight + transportHeight + 24
        return ZStack(alignment: .bottomTrailing) {
            map
            Group {
                if railPresent { controlStack() }
                else { controlStack().hidden() }
            }
                .background {
                    GeometryReader { rail in
                        Color.clear.preference(key: RailControlHeightKey.self, value: rail.size.height)
                    }
                }
                .padding(.bottom, transportHeight)
                .padding(12)
                .opacity(railPresent ? 1 : 0)
                .allowsHitTesting(railPresent)
                .accessibilityHidden(!railPresent)
            playbackBar
                .frame(width: min(540, width))
                .frame(maxHeight: max(0, geometry.size.height - 24), alignment: .bottom)
                .padding(12)
                .railAnimation(
                    RailMotion.spring, value: showsPlaybackBar,
                    reduceMotion: reduceMotion)
        }
        // Floating controls align to the actual viewport, not the union of
        // the map and the transport's intrinsic bounds.
        .frame(width: geometry.size.width, height: geometry.size.height,
               alignment: .bottomTrailing)
        .onPreferenceChange(RailControlHeightKey.self) { height in
            if abs(height - railHeight) > 0.5 { railHeight = height }
        }
        .onPreferenceChange(PlaybackBarHeightKey.self) { height in
            if abs(height - playbackBarHeight) > 0.5 { playbackBarHeight = height }
        }
    }

    /// Which layer is on top. §4.4: closing a journey is returning to the list,
    /// and it does not clear the date filter.
    private var selectedTrain: Train? {
        guard let id = itineraries.selectedTrainID else { return nil }
        return itineraries.loaded?.trains.first { $0.id == id }
    }

    // MARK: - shared parts

    /// Withheld until the map exists: `MKCompassButton` cannot be built
    /// without an `MKMapView`, and showing the stack without it would leave a
    /// gap that fills in a frame later.
    @ViewBuilder
    private func controlStack() -> some View {
        controlStackBody
    }

    @ViewBuilder
    private var controlStackBody: some View {
        if controller.isMapReady, let mapView = controller.mapView {
            MapControlBar(
                mapView: mapView, controller: controller,
                onLayers: { sheet = .mapLayers },
                onInfo: { sheet = .mapInfo })
            // The native interactive glass grows beyond its resting shape on
            // touch-down. This is drawing room, not a clipping viewport.
            .padding(MapControlBar.interactionBleed)
            // Keep the resting buttons at their original 12 pt screen margin
            // after adding the interaction bleed.
            .offset(x: MapControlBar.interactionBleed)
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    /// §11.2's answer for one journey. The only caller of the resolver in the
    /// journey surfaces, so the priority order lives in one tested place.
    private func presentation(for train: Train) -> JourneyPresentation {
        JourneyPresentationResolver.selected(
            train: train,
            route: JourneyBridge.routeState(for: train.id, localization: localization),
            phase: playbackPhase(for: train))
    }

    /// The only sub-phase this workspace can be in for a *single* journey.
    ///
    /// Editing and saving belong to `RideEditorView`, which owns its own draft
    /// and its own atomic commit (§8.3); a failure to load is a workspace
    /// phase, not this journey's. So playback is what is left — and the
    /// resolver still refuses to report it while the route is not resolved.
    /// `exactProgress`, and the choice is the whole of why a run stopped
    /// rebuilding this view twenty times a second.
    ///
    /// `PlaybackController.progress` is `@Observable`, and its own note says
    /// what reading it here costs: "`@Observable` invalidates every view whose
    /// body READ a property", and this read is inside `RailWorkspaceView`'s.
    /// So the playhead's 20 Hz ladder was recomputing the workspace — its list,
    /// its derived summaries, its map inputs — twenty times a second for the
    /// length of every run. That is the exact cost `PlaybackTransportBar` was
    /// extracted to remove; this one line put it straight back.
    ///
    /// And it bought nothing: `JourneyPresentationResolver` matches
    /// `if case .playing(_, let isPaused)` and reads the progress in no branch,
    /// so the number was published, observed, passed down and discarded.
    /// ``PlaybackController/exactProgress`` is the same playhead — more
    /// precise, in fact — and is `@ObservationIgnored`, so it is free to read.
    ///
    /// **If a journey row ever draws a live bar from this**, it must not come
    /// back through here: the value would then only refresh when this body
    /// re-evaluates for some other reason. Give the row a small view of its own
    /// that reads `progress`, the way the transport does.
    private func playbackPhase(for train: Train) -> JourneyWorkspacePhase? {
        guard playback.isActive, playback.currentTrainID == train.id else { return nil }
        return .playing(progress: playback.exactProgress, isPaused: !playback.isPlaying)
    }

    // MARK: - §5.1 the journey list

    /// All Journeys is deliberately unfiltered by the Search destination's
    /// query. A hidden query must never make this list silently incomplete.
    private var ridesList: some View {
        journeyListState(searchQuery: "", region: regionScope, groupsByDate: false)
    }

    /// The search destination, and its own field.
    ///
    /// The field is drawn here rather than left to `.searchable`, and that is
    /// the fix rather than a preference. `.searchable` was attached to the
    /// `TabView`, which on iOS 26 hands the field to the semantic Search role —
    /// and the role presents it by MORPHING THE TAB BAR, which this app has
    /// switched off: `railPersistentTabBar()` sets
    /// `tabBarMinimizeBehavior(.never)` so the bar stays positionally
    /// continuous across Docked / Half / Full (§14.3). The two requirements are
    /// in direct conflict, and the bar won, silently — the search destination
    /// shipped with nothing on it that could be typed into, at every stop.
    ///
    /// It was never only an iOS 26 problem, which is what settles the choice:
    /// `legacyWorkspaceTabs` has no search role at all, so on iOS 17–25 the
    /// same `.searchable` had no field to give either. A destination whose
    /// whole job is a query cannot depend on machinery that only one OS
    /// version has and this app has disabled there.
    private var searchPanel: some View {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(spacing: 0) {
            JourneySearchField(query: $query, isFocused: $searchFocused)
            Group {
                if needle.isEmpty {
                    // No action in this empty state any more: the `+` in the
                    // panel header adds a journey, and it is on screen in this
                    // state and in the results state alike. §16's mapping rule
                    // — the same one this file argues for the gear a few
                    // screens up — is that one action does not get two entries
                    // in one state.
                    ContentUnavailableView {
                        Label(
                            localization.countryText("sec.search", fallback: "Search journeys"),
                            systemImage: "magnifyingglass")
                    } description: {
                        Text(localization.countryText(
                            "ph.search", fallback: "Train, station, or identifier"))
                    }
                    .modifier(ScrollableIfNeeded())
                } else {
                    journeyListState(searchQuery: needle, region: nil)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background { keyboardShortcuts }
    }

    @ViewBuilder
    private func journeyListState(
        searchQuery: String, region: Region?, groupsByDate: Bool = true
    ) -> some View {
        switch itineraries.state {
        case .idle, .loading:
            workspaceStatus(JourneyPresentationResolver.workspace(phase: .loading))
        case .failed(let message):
            workspaceUnavailable(
                JourneyPresentationResolver.workspace(phase: .failed(.load(message))),
                systemImage: "exclamationmark.triangle")
        case .loaded(let loaded) where loaded.days.isEmpty:
            workspaceUnavailable(
                JourneyPresentationResolver.workspace(phase: .empty),
                systemImage: "tram",
                description: localization.journeyText(
                    "ios.journey.noRegionRecords",
                    fallback: "This region has a railway package, but no recorded journeys yet."))
        case .loaded(let loaded):
            let days = filteredDays(loaded, region: region, query: searchQuery)
            List {
                if groupsByDate {
                    ForEach(days) { day in
                        Section(day.date) {
                            ForEach(day.trains, id: \.id) { train in
                                journeyRow(train)
                            }
                        }
                    }
                } else {
                    ForEach(days.flatMap(\.trains), id: \.id) { train in
                        journeyRow(train, showsDate: selectedDate == Dates.allDates)
                    }
                }
            }
            .listStyle(.plain)
            .listSectionSpacing(.custom(2))
            .scrollContentBackground(.hidden)
            .background { keyboardShortcuts }
            .overlay {
                // The spinner is for "nothing to show yet" only: `days` is
                // empty AND the in-flight search (if any) hasn't produced a
                // result — never merely "a newer query is still running",
                // since `days` keeps showing the previous completed results
                // through that window (see `filteredDays`).
                if !searchQuery.isEmpty && days.isEmpty
                    && journeySearch.completed != journeySearchRequest {
                    ProgressView()
                } else if days.isEmpty {
                    // §13.1: three empty states, three different single primary
                    // actions — and the search text is kept, not cleared.
                    workspaceUnavailable(
                        JourneyPresentationResolver.workspace(
                            phase: .empty,
                            hasSearchQuery: !searchQuery.isEmpty,
                            hasDateFilter: selectedDate != Dates.allDates),
                        systemImage: "magnifyingglass")
                }
            }
        }
    }

    /// The two shortcuts that have no button of their own (§10.3).
    ///
    /// Zero-opacity buttons rather than commands: `Commands` is a scene-level
    /// macOS concept, and on iPadOS a keyboard shortcut is delivered to a
    /// `Button` in the hierarchy. They are hidden from assistive technology —
    /// a reader using VoiceOver reaches search and the back-step through the
    /// search field and the panel's own close button, not through two unlabelled
    /// controls behind the list.
    @ViewBuilder
    private var keyboardShortcuts: some View {
        Button(localization.countryText("sec.search", fallback: "Search")) {
            selection = .search
            Task { @MainActor in
                await Task.yield()
                searchFocused = true
            }
        }
        .keyboardShortcut("f", modifiers: .command)
        .opacity(0)
        .accessibilityHidden(true)

        // §10.3: Escape clears the journey selection and leaves the reader's
        // date filter and search where they are — the same rule as a tap on
        // empty map (§4.4), and the same code.
        Button(localization.text("ios.cancel", fallback: "Cancel")) {
            RailMotion.withoutAnimation { selectFromMap([]) }
        }
        .keyboardShortcut(.escape, modifiers: [])
        .opacity(0)
        .accessibilityHidden(true)

        // ⌘N and Space used to hang off two toolbar items that the panel
        // header replaced (§9.5.6). The buttons moved; the shortcuts are the
        // same two actions and belong wherever the actions are reachable from.
        Button(localization.text("ios.newJourney", fallback: "New journey")) {
            presentJourneyEditor(JourneyEditorLaunch(
                train: newJourneyScaffold(in: defaultRegion), isNew: true, originalID: nil))
        }
        .keyboardShortcut("n", modifiers: .command)
        .opacity(0)
        .accessibilityHidden(true)

        // Space plays and pauses when focus is not in a text field. SwiftUI
        // withholds a modifier-less shortcut from a focused text field on its
        // own, which is what makes this safe on a key that also types.
        Button(localization.countryText("btn.play", fallback: "Play rides")) {
            RailMotion.withoutAnimation {
                if playback.isActive {
                    stopPlayback()
                } else if !playbackScope.isEmpty {
                    startPlayback(playbackScope)
                }
            }
        }
        .keyboardShortcut(.space, modifiers: [])
        .opacity(0)
        .accessibilityHidden(true)

        // Zoom, which no longer has a button.
        //
        // The rail dropped its ± pair because the rail must show all of itself
        // at Half without scrolling and pinch already covers touch
        // (`MapControlBar`'s note has the argument). Pinch is not available to
        // someone driving this from a keyboard, and §10.3 asks the keyboard to
        // reach the main map operations — so the two controller commands keep a
        // caller here rather than becoming dead code.
        //
        // `.command` with "+" and "-": the plus is typed as `=` on most
        // layouts, so both are bound, which is what every map app that offers
        // ⌘+ actually does.
        Button(localization.text("ios.zoomIn", fallback: "Zoom in")) {
            controller.zoomIn()
        }
        .keyboardShortcut("+", modifiers: .command)
        .opacity(0)
        .accessibilityHidden(true)

        Button(localization.text("ios.zoomIn", fallback: "Zoom in")) {
            controller.zoomIn()
        }
        .keyboardShortcut("=", modifiers: .command)
        .opacity(0)
        .accessibilityHidden(true)

        Button(localization.text("ios.zoomOut", fallback: "Zoom out")) {
            controller.zoomOut()
        }
        .keyboardShortcut("-", modifiers: .command)
        .opacity(0)
        .accessibilityHidden(true)
    }

    /// One row of the journey list — see ``JourneyListRow``, which is where the
    /// row's own 78 lines and its context menu went.
    ///
    /// What stays here is only what the row cannot know: which journey the
    /// playhead is on, where a detail sheet is presented, and which dialog the
    /// workspace raises for a delete.
    private func journeyRow(_ train: Train, showsDate: Bool? = nil) -> some View {
        JourneyListRow(
            train: train,
            presentation: presentation(for: train),
            showsDate: showsDate ?? (selectedDate == Dates.allDates),
            editing: editing,
            select: { pick(train) },
            play: { startPlayback([train]) },
            showDetail: { sheet = .detail(train.id) },
            setRidden: { setRidden(train, $0) },
            confirmDelete: { dialog = .delete(train) })
    }

    /// Say whether a journey was ridden, and write it down.
    ///
    /// Goes through `replace` — the one verified commit every other edit takes
    /// — rather than a store transition of its own, because that is all this
    /// is: the record's own `ride_segment` flags, set across the whole journey.
    /// See ``RailPresentation/RideLedger``.
    private func setRidden(_ train: Train, _ ridden: Bool) {
        guard RideLedger.hasBeenRidden(train) != ridden else { return }
        editing.replace(RideLedger.setRidden(train, ridden), replacing: train.id)
        signal(.saved)
    }

    // MARK: - workspace-level states (§13.1, §13.2, §13.3)

    // Both drawn by ``JourneyWorkspaceStates``. These stay as the injection
    // point: the views are pure functions of a resolved presentation, and the
    // one thing they cannot be pure about — what a chosen action DOES — is
    // this workspace's `perform`.

    private func workspaceStatus(_ presentation: JourneyPresentation) -> some View {
        WorkspaceStatusView(presentation: presentation)
    }

    private func workspaceUnavailable(
        _ presentation: JourneyPresentation,
        systemImage: String,
        description: String? = nil
    ) -> some View {
        WorkspaceUnavailableView(
            presentation: presentation,
            systemImage: systemImage,
            description: description,
            perform: { perform($0, on: nil) },
            performSecondary: { perform($0, on: nil) })
    }

    // MARK: - what a resolved action actually does (§8)

    private func perform(_ action: JourneyPresentation.PrimaryAction, on train: Train?) {
        switch action {
        case .add:
            presentJourneyEditor(JourneyEditorLaunch(
                train: newJourneyScaffold(in: defaultRegion), isNew: true, originalID: nil))
        case .importData:
            sheet = .importData
        case .locate:
            guard yieldRun() else { return }
            if let train { itineraries.selectedTrainID = train.id }
            if let id = train?.id ?? itineraries.selectedTrainID,
                let ride = mapRides.first(where: { $0.id == id }),
                let region = MapProjection.region(covering: ride.strokes) {
                controller.fit(region)
            } else {
                controller.fitToSelection()
            }
        case .showOnMap:
            guard let train else { return }
            editing.toggleVisibility(train.id)
        case .rebuildRoute:
            guard let train else { return }
            _ = rebuildRoute(train)
        case .save:
            // §8.3: the draft and its atomic commit belong to the editor.
            if let train {
                presentJourneyEditor(JourneyEditorLaunch(
                    train: train, isNew: false, originalID: train.id))
            }
        case .pause, .resume:
            playback.togglePause()
        case .retry:
            itineraries.load(from: library)
        case .clearSearch:
            query = ""
        }
    }

    private func perform(_ action: SecondaryAction, on train: Train?) {
        switch action {
        case .play:
            guard let train else { return }
            startPlayback([train])
        case .stop:
            stopPlayback()
        case .edit:
            if let train {
                presentJourneyEditor(JourneyEditorLaunch(
                    train: train, isNew: false, originalID: train.id))
            }
        case .duplicate:
            guard let train else { return }
            editing.duplicate(train.id)
        case .hide, .show:
            guard let train else { return }
            editing.toggleVisibility(train.id)
        case .delete:
            if let train {
                PresentationHost.afterTeardown { dialog = .delete(train) }
            }
        case .inspectDetails:
            if let train { sheet = .detail(train.id) }
        case .rebuildRoute:
            guard let train else { return }
            _ = rebuildRoute(train)
        case .cancel:
            itineraries.selectedTrainID = nil
        case .importData:
            sheet = .importData
        case .add:
            presentJourneyEditor(JourneyEditorLaunch(
                train: newJourneyScaffold(in: defaultRegion), isNew: true, originalID: nil))
        }
    }

    /// §8.4: rebuilding regenerates route sections from the stops. It never
    /// deletes the journey, and a section that still cannot be solved stays
    /// undrawn rather than being straightened.
    @discardableResult
    private func rebuildRoute(_ train: Train) -> Int? {
        editing.rebuildRouteSections(train.id)
    }

    /// The journeys the list shows, after every filter the header applies.
    ///
    /// `region` is passed rather than read off ``regionScope`` because the two
    /// destinations that use this do not want the same answer: the log and its
    /// summary are scoped to the region the globe button names, and Search is
    /// deliberately not — a query that silently skipped four networks would be
    /// a search that reports "no results" for a journey the reader can see two
    /// taps away. `nil` is every region.
    private func filteredDays(
        _ loaded: ItineraryStore.Loaded,
        region: Region?,
        query searchQuery: String = ""
    ) -> [ItineraryStore.Loaded.Day] {
        if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // `journeySearch.days` already holds exactly "the last completed
            // result": a cancelled search (superseded by a newer keystroke)
            // never touches it — see `JourneySearch.search`'s `catch {}` — so
            // it is always either this query's own answer or the previous
            // query's. Blanking here on every keystroke (while
            // `completed != journeySearchRequest`) was the bug: the 150 ms
            // debounce plus an off-main filter pass emptied the list on every
            // character typed. The matching "nothing to show yet" spinner is
            // the overlay in `journeyList(for:)`, keyed off this same array
            // being empty rather than off `completed`.
            return journeySearch.days
        }
        // Empty-query date/region filtering is cheap and memoized for the
        // header, list and playback scope. Nonempty queries read only the
        // completed background result above.
        return derived.days(
            of: loaded, selectedDate: selectedDate, region: region,
            query: searchQuery,
            naming: localization.stationNamingGeneration
        ) {
            computeFilteredDays(loaded, region: region)
        }
    }

    private func computeFilteredDays(
        _ loaded: ItineraryStore.Loaded,
        region: Region?
    ) -> [ItineraryStore.Loaded.Day] {
        WorkspaceJourneyRules.filteredDays(
            loaded.days, selectedDate: selectedDate, regionCode: region?.code,
            rule: Region.scopeRule)
    }

    private var journeySearchRequest: JourneySearch.Request {
        .init(days: itineraries.loaded?.days ?? [], date: selectedDate,
            query: selection == .search ? query.trimmingCharacters(in: .whitespacesAndNewlines) : "",
            naming: localization.stationNamingGeneration)
    }

    /// §5.1's date filter, as a submenu of the header's gear menu.
    ///
    /// Search only, now. The other two destinations that read this value carry
    /// it as a round button of their own — see ``journeyDateMenu(for:)`` —
    /// and the contents are shared rather than written twice.
    @ViewBuilder
    private func dateFilterSection(_ loaded: ItineraryStore.Loaded) -> some View {
        Menu {
            dateFilterMenuContent(loaded, dates: availableDates(loaded))
        } label: {
            Label(
                selectedDate == Dates.allDates
                    ? localization.countryText("date.all", fallback: "All dates")
                    : selectedDate,
                systemImage: "calendar")
        }
    }

    /// §5.1's date filter, as a round button in the header row.
    ///
    /// One value — ``selectedDate`` — shared by Upcoming and All Journeys,
    /// because the two are asking the same question of the same log from
    /// different ends of it, and a reader who scopes to one day in the log and
    /// finds the other tab still showing every day is reading two answers. It
    /// is NOT the statistics' date: §5.3.1 says so in as many words, and
    /// ``statisticsDateMenu`` is that other value's control.
    ///
    /// What differs between the two tabs is which days are on offer. The log
    /// offers every bucket the store has; Upcoming offers only the ones that
    /// still lie ahead, because a menu that lets the reader pick a day in the
    /// past on a list of what is coming is a control whose every entry empties
    /// the screen.
    @ViewBuilder
    private func journeyDateMenu(for tab: PrimaryTab) -> some View {
        Menu {
            if let loaded = itineraries.loaded {
                dateFilterMenuContent(loaded, dates: journeyDates(for: tab, in: loaded))
            }
        } label: {
            SheetIconLabel(
                systemImage: "calendar", isActive: selectedDate != Dates.allDates)
        }
        .accessibilityLabel(
            Text(localization.journeyText("ios.journey.dateFilter", fallback: "Date filter")))
        .accessibilityValue(Text(dateBucketLabel(selectedDate)))
        .accessibilityIdentifier("journeyDateButton")
    }

    /// The days one destination may be scoped to.
    ///
    /// Region-scoped in both cases, so the globe and the calendar cannot
    /// disagree: with the scope on 台灣, a Japanese-only day is not a day this
    /// screen has.
    private func journeyDates(
        for tab: PrimaryTab, in loaded: ItineraryStore.Loaded
    ) -> [String] {
        WorkspaceJourneyRules.journeyDates(
            trains: loaded.trains, regionCode: regionScope?.code, upcoming: tab == .upcoming,
            todayByRegion: tab == .upcoming
                ? Dictionary(uniqueKeysWithValues: todayByRegion().map { ($0.key.code, $0.value) }) : [:],
            manualDates: manualDates.dates, rule: Region.scopeRule)
    }

    /// The entries both spellings of the date filter show.
    ///
    /// The dates are passed in rather than derived here: the two destinations
    /// offer different slices of the calendar (see ``journeyDates(for:in:)``),
    /// and everything below the divider is the same everywhere.
    @ViewBuilder
    private func dateFilterMenuContent(
        _ loaded: ItineraryStore.Loaded, dates: [String]
    ) -> some View {
        Button {
            selectDate(Dates.allDates)
        } label: {
            Label(
                localization.countryText("date.all", fallback: "All dates"),
                systemImage: selectedDate == Dates.allDates ? "checkmark" : "calendar")
        }
        ForEach(dates, id: \.self) { date in
            Button {
                selectDate(date)
            } label: {
                Label(
                    dateBucketLabel(date),
                    systemImage: selectedDate == date ? "checkmark" : "calendar")
            }
        }
        Group {
            Divider()
            Button {
                PresentationHost.afterTeardown { dialog = .addDate }
            } label: {
                Label(
                    localization.countryText("btn.addDate", fallback: "Add date"),
                    systemImage: "calendar.badge.plus")
            }
            Button(role: .destructive) {
                manualDates.prune(keeping: Set(loaded.days.map(\.date)))
                if selectedDate != Dates.allDates,
                    !availableDates(loaded).contains(selectedDate)
                {
                    selectDate(Dates.allDates)
                }
            } label: {
                Label(
                    localization.journeyText(
                        "btn.removeEmptyDates", fallback: "Remove empty dates"),
                    systemImage: "calendar.badge.minus")
            }
            .disabled(manualDates.isEmpty)
            Toggle(
                localization.journeyText(
                    "toggle.currentDate", fallback: "Map shows the selected date only"),
                isOn: $mapFollowsSelectedDate)
            // Beside the date filter because they are the same kind of
            // decision — what the MAP does when the list's scope
            // changes — and the web app keeps its own 自動縮放 button in the
            // date bar for the same reason.
            Toggle(autoFocusLabel, isOn: $autoFocusZoom)
        }
    }

    /// A date bucket as the reader reads it — the two sentinels need a word,
    /// a real day labels itself.
    private func dateBucketLabel(_ date: String) -> String {
        let key = Dates.dateLabelKey(date)
        return localization.text(key, fallback: date)
    }

    /// 自動縮放, without the separator the web app's button needs.
    ///
    /// `btn.autoFocus` is "自動フォーカス：" — a label that expects `state.on`
    /// or `state.off` to be appended, because in the browser it is one button
    /// that reports its own state. A `Toggle` reports its state itself, so the
    /// separator is trimmed rather than a fifth translation of the same two
    /// words being introduced to carry the string without it.
    private var autoFocusLabel: String {
        localization.countryText("btn.autoFocus", fallback: "Auto-focus")
            .trimmingCharacters(in: CharacterSet(charactersIn: ": \u{FF1A}\u{3000}"))
    }

    private func availableDates(_ loaded: ItineraryStore.Loaded) -> [String] {
        Dates.availableDates(loaded.trains.map(\.forDates), manualDates: manualDates.dates)
    }

    /// The same buckets, narrowed to one region.
    ///
    /// The manual dates are not narrowed: a bucket the reader created by hand
    /// belongs to no region, and dropping it under a region scope would make
    /// the empty day they just added impossible to reach.
    private func availableDates(
        _ loaded: ItineraryStore.Loaded, region: Region?
    ) -> [String] {
        guard let region else { return availableDates(loaded) }
        let trains = loaded.trains.filter { Region.resolved($0) == region }
        return Dates.availableDates(trains.map(\.forDates), manualDates: manualDates.dates)
    }

    /// The web app's 載入示例資料 / 保存為我的資料 / 恢復我的資料, as one menu.
    ///
    /// One menu rather than eleven buttons because on a phone they are eleven
    /// buttons the reader has to read every time; grouped, the destructive one
    /// is also somewhere it cannot be hit by accident.
    @ViewBuilder
    private var rideSourceSection: some View {
        Group {
                if itineraries.selectedTrainID != nil {
                    Button {
                        itineraries.selectedTrainID = nil
                    } label: {
                        Label(
                            localization.journeyText(
                                "ios.journey.clearSelection", fallback: "Clear selection"),
                            systemImage: "xmark.circle")
                    }
                    Divider()
                }
                // The samples are on the data screen, one section per region,
                // because loading one is now an ordinary edit to the working
                // set rather than a switch between two ways of using the app.
                // This menu keeps the two actions that are about the reader's
                // own rides.

                Section(localization.text("ios.myRides", fallback: "My rides")) {
                    Button {
                        if let store = itineraries.store {
                            library.save(store)
                        }
                    } label: {
                        Label(localization.countryText("btn.saveAsMine", fallback: "Save as my rides"), systemImage: "square.and.arrow.down")
                    }
                    .disabled(itineraries.store == nil)

                    Button {
                        itineraries.load(from: library)
                    } label: {
                        Label(localization.countryText("btn.restoreMine", fallback: "Restore my rides"), systemImage: "arrow.uturn.backward")
                    }
                    .disabled(!library.hasSavedStore)
                }
        }
    }

    /// New journey — and, because there is no active region any more, which
    /// region it starts in.
    ///
    /// Start with the chosen network, without carrying sample stations or routes.
    private func newJourneyScaffold(in region: Region) -> Train {
        Train(
            id: "journey_" + UUID().uuidString.replacingOccurrences(of: "-", with: ""),
            number: "", origin: "", destination: "", visible: true,
            stops: [
                Stop(name: "", stopType: "origin", rideSegment: true),
                Stop(name: "", stopType: "destination", rideSegment: true),
            ],
            region: region.code)
    }

    /// Which region a new journey starts in when the reader just taps `+`:
    /// the one they are looking at, then the one they have most rides in,
    /// then Japan.
    private var defaultRegion: Region {
        let code = WorkspaceJourneyRules.defaultRegion(
            selectedTrain: itineraries.selectedTrain, trains: itineraries.loaded?.trains ?? [],
            orderedRegionCodes: Region.enabledOrdered.map(\.code), rule: Region.scopeRule)
        return Region(rawValue: code) ?? .jp
    }

    private var editing: JourneyEditing {
        JourneyEditing(itineraries: itineraries, library: library)
    }

    /// The one basemap all three destinations share (§9.5.6, and the reader's
    /// own "需要三个 tab 都共用一个底图").
    ///
    /// One `MKMapView`, at the root, under the sheet. What changes between
    /// destinations is not the map but the QUESTION being asked of it, so what
    /// varies here are its inputs: which rides are drawn, and whether the
    /// complete network is on.
    /// Normalized date of the selected train. Undated and unselected both
    /// pass nil so the ride-date era uses the Current predicate.
    private var selectedTrainNetworkDate: String? {
        if journeyEditor != nil, controller.acceptsDraftMap {
            return controller.draftMap.networkRideDate
        }
        guard let train = selectedTrain else { return nil }
        let day = Dates.normalizeTrainDate(train.forDates)
        return day == Dates.undated ? nil : day
    }

    private var map: some View {
        RailMapView(
            lines: lines,
            stations: store.mapStations,
            rides: linePreview.map { mapRides + [$0.ride] } ?? mapRides,
            networkExtent: store.networkExtent,
            selectedTrainID: linePreview?.ride.id ?? itineraries.selectedTrainID,
            selectedDate: selectedDate,
            networkRideDate: linePreview == nil ? selectedTrainNetworkDate : nil,

            // One display switch, one source of truth. Statistics can change
            // the reported region and frame the camera, but it must not force
            // the complete network back on after the reader turns it off.
            showsNetwork: controller.showsNetwork,
            categoryIndexes: categoryIndexes.byCountry,
            controller: controller,
            playback: playback,
            onSelectRide: { selectFromMap($0) },
            onSelectStation: { card in
                guard journeyEditor == nil, !journeyMenuOwnsSelection else { return }
                sheet = .station(card)
            },
            // Which countries the reader is actually looking at, from the rect
            // the map rebuilt for. Only while the network is on: with it off
            // there are no rails and no station dots to draw, so a pan across
            // Japan costs nothing at all.
            // The loader's historical `cameraZoom` parameter receives the
            // viewport-adjusted visibility zoom, matching the renderer's gate.
            onBuildRect: { rect, visibilityZoom in
                guard controller.showsNetwork else { return }
                store.ensure(regionsIntersecting: rect, cameraZoom: visibilityZoom)
            }
        ) { render = $0 }
        .ignoresSafeArea()
        // The one place the setting crosses from SwiftUI into the controller.
        //
        // `RailMapController` is not a `View`, so it cannot read
        // `@Environment` itself — its own note says the value is "pushed in
        // from the view", and until now nothing pushed it: the property held
        // its `false` default for the app's whole life, which made
        // `RailMotion.cameraAnimated(reduceMotion:)` a constant `true` at all
        // six camera call sites. Every zoom, every reset-north and every
        // "frame this" flew the camera with Reduce Motion on.
        //
        // Attached to `map` rather than to either layout, because both the
        // sheet layout and the docked-card layout mount it and the controller
        // must not depend on which one the window is in. `initial: true` is
        // what covers a reader who already had the setting on at launch.
        .onChange(of: reduceMotion, initial: true) { _, reduced in
            controller.reduceMotion = reduced
        }
#if DEBUG
        .overlay(alignment: .topLeading) {
            if ProcessInfo.processInfo.environment["RAILMAP_UI_TEST_JOURNEY_INVENTORY"] == "1" {
                Text(debugJourneyInventory)
                    .font(.caption)
                    .foregroundStyle(.clear)
                    .frame(width: 1, height: 1)
                    .clipped()
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("journeyLoadInventory")
            }
        }
#endif
    }

#if DEBUG
    private var debugJourneyInventory: String {
        let phase: String
        switch riddenRoutes.state {
        case .idle: phase = "idle"
        case .loading: phase = "loading"
        case .loaded: phase = "loaded"
        case .failed: phase = "failed"
        }
        let registered = itineraries.loaded?.trains.count ?? 0
        let drawable = mapRides.count
        return "registered:\(registered);phase:\(phase);drawable:\(drawable)"
    }
#endif

    /// §4.4: a tap on empty map clears the journey selection, and nothing else.
    ///
    /// It used to be a two-rung ladder — the selection first, then the date
    /// filter — and that second rung was the other half of a coupling this
    /// workspace no longer has. Picking a ride does not move the date filter
    /// (see ``pick(_:)``), so a date on screen is one the reader chose from
    /// the filter menu, and a tap on the sea is not an answer to that
    /// question. It also cost the reader a state they never asked to be in:
    /// clearing the selection left the ladder standing on that ride's day, so
    /// choosing another journey meant tapping empty water first to get back
    /// out of a day nobody had picked. Two states, two controls — the map
    /// clears what the map selected.
    ///
    /// A tap that lands on SEVERAL rides asks instead of choosing. That is the
    /// web app's `handleDeckRouteChoices`, and its reason is the same: a
    /// finger has no hover stage, so picking the nearest line silently selects
    /// a journey the reader may not have been pointing at — and where two
    /// rides run the same corridor, "nearest" is decided by a fraction of a
    /// point.
    private func selectFromMap(_ ids: [String]) {
        guard linePreview == nil else { return }
        let trains = ids.compactMap { id in
            itineraries.loaded?.trains.first { $0.id == id }
        }
        switch trains.count {
        case 0:
            if !journeyMenuOwnsSelection { itineraries.selectedTrainID = nil }
        case 1:
            pick(trains[0])
        default:
            // Background map taps must not replace an open journey card.
            if !journeyMenuOwnsSelection { sheet = .chooseRide(trains) }
        }
    }

    /// Focus the tapped journey and open its separate menu. The source
    /// destination, filters and panel size are retained while it slides away.
    private func pick(_ train: Train) {
        guard yieldRun() else { return }
        if !journeyMenuOwnsSelection {
            selectionBeforeJourneyMenu = itineraries.selectedTrainID
            journeyMenuOwnsSelection = true
        }
        itineraries.selectedTrainID = train.id
        controller.requestAutoFocus(
            .journey(train.id), enabled: true, playbackIsActive: playback.isActive)
        sheet = .detail(train.id)
    }

    /// A run gives way to the reader choosing a journey — or, while it is
    /// being filmed, does not. ``PickDuringRunRule`` is the tested decision;
    /// this is its hands. Returns whether the pick goes ahead.
    ///
    /// Before this, a pick during a run was taken and then taken away twice:
    /// the next hand-off overwrote it, and stopping restored the pre-run
    /// selection over it.
    ///
    /// Only the selection half of the web app's hook is ported. There, ANY
    /// repaint of the train layers ends a run — a date change, an edit, a
    /// deletion — because the queue the run froze is stale. Here those still
    /// leave a run playing, as they did.
    private func yieldRun() -> Bool {
        switch PickDuringRunRule.resolve(
            runOnScreen: playback.phase != .idle, filming: videoExport.isRecording)
        {
        case .proceed:
            return true
        case .stopRunThenProceed:
            playback.stop()
            playback.restoreSelectedTrainID = nil
            return true
        case .decline:
            return false
        }
    }

    private func selectDate(_ date: String) {
        selectedDate = date
        controller.requestAutoFocus(
            .date(date), enabled: autoFocusZoom && date != Dates.allDates,
            playbackIsActive: playback.isActive)
    }

    /// Every visible ride, INCLUDING the ones outside the selected date.
    ///
    /// This used to drop off-date rides. That is not what the web app does and
    /// it is not what `DisplaySettings.dimOpacity` is for: an off-date ride is
    /// drawn faint so the reader can see the day in the context of the trip,
    /// and removing it makes the slider a control over nothing. The renderer
    /// is handed `selectedDate` and decides.
    ///
    /// `map-date-filter` (`mapFollowsSelectedDate`) is the reader asking for
    /// the harder version — only this date on the map — so that one still
    /// filters here.
    ///
    /// ## What the destination narrows it to (§4.2)
    ///
    /// One basemap, three questions. The destination on top does not change
    /// how a ride is DRAWN — every switch under 已乘坐線路 in `MapLayers`
    /// still owns that, for what is ahead exactly as for what is behind, so
    /// there is no second set of switches for a second kind of line — it
    /// changes only WHICH rides are handed over:
    ///
    ///   - **Upcoming** — the journeys still ahead, and only those. The
    ///     destination's question is what is coming, and a map carrying the
    ///     whole log underneath that list answers a different one.
    ///   - **Passport** — the records the numbers counted, and only those
    ///     (§5.3.2). A map showing five networks under a Japanese percentage
    ///     invites the reader to read the percentage as covering all of them.
    ///   - **All journeys**, and Search — everything on record, which is what
    ///     those two destinations list.
    private var mapRides: [RiddenRouteStore.DrawnRide] {
        // Pre-filtered by the store so ordinary sheet-height updates keep the
        // same Array buffer all the way into `RailMapView.updateUIView`; the
        // narrowed answers below are held by `WorkspaceDerived` for the same
        // reason, because the destination the app OPENS on is a narrowed one.
        let visible = riddenRoutes.visibleRides
        switch selection {
        case .upcoming:
            return derived.rides(visible, scopedTo: upcomingScope.ids)
        case .stats:
            return derived.rides(visible, scopedTo: statisticsScope.ids)
        case .all, .search:
            break
        }
        let trains = itineraries.loaded?.trains ?? []
        var ids: Set<String>?
        // All Journeys carries the same globe button the other two do, so the
        // map under it draws that region and not the other four. Search does
        // not scope by region — see ``filteredDays(_:region:query:)`` — and a
        // map that narrowed while its list did not would be the second half of
        // the same lie.
        if selection == .all, let region = regionScope {
            ids = derived.trainIDs(inRegion: region, in: trains)
        }
        if mapFollowsSelectedDate, selectedDate != Dates.allDates {
            let dated = derived.trainIDs(spanning: selectedDate, in: trains)
            ids = ids.map { $0.intersection(dated) } ?? dated
        }
        guard let ids else { return visible }
        return derived.rides(visible, scopedTo: ids)
    }

    /// `resolveQueue` — what "play" means right now.
    ///
    ///   a chosen journey → just that one, **even if it is hidden**: the
    ///                      reader asked for it by name
    ///   otherwise        → the list as it stands, minus the hidden journeys
    ///                      and minus anything with fewer than two calls
    ///
    /// The hidden ones used to play anyway. A journey switched off is one the
    /// reader has taken off the map, and a queue that plays it puts it back on
    /// screen — with the camera following it — for as long as it runs.
    private var playbackScope: [Train] {
        guard let loaded = itineraries.loaded else { return [] }
        if let selected = itineraries.selectedTrainID,
           let train = loaded.trains.first(where: { $0.id == selected }) {
            return [train]
        }
        let searchQuery = selection == .search ? query : ""
        return filteredDays(
            loaded, region: selection == .search ? nil : regionScope,
            query: searchQuery)
            .flatMap(\.trains)
            .filter { $0.visible != false && $0.stops.count > 1 }
    }

    /// Start a run, remembering what was selected before it.
    ///
    /// `restoreSelected` in the web app: the transport moves the selection
    /// from journey to journey as it plays (`onChange(of:playback.currentTrainID)`
    /// above), so stopping has to put back whatever the reader was looking at
    /// when they pressed play. Every entry point goes through here so that
    /// none of them can forget to.
    @discardableResult
    private func startPlayback(_ trains: [Train]) -> Bool {
        if videoExport.isRecording { videoExport.abandonRecording() }
        let started = playback.start(
            trains: trains, rides: riddenRoutes.rides, reducedMotion: reduceMotion,
            restoringSelection: itineraries.selectedTrainID)
        if started { stageSelection = .compact }
        return started
    }

    private var rideIDs: Set<String> { derived.rideSummary(riddenRoutes.rides).ids }

    /// The regions the drawn rides belong to — the only ones whose network
    /// the category filter could ever need to classify against.
    ///
    /// Taken off the same memoised pass as ``rideIDs``: both were separate
    /// walks over every drawn ride, made on every body evaluation, for answers
    /// that change only when a route finishes solving.
    private var riddenCountries: [String] {
        derived.rideSummary(riddenRoutes.rides).countries
    }

    /// Re-run the index build when a category is first switched off, or when a
    /// region gains its first ride. Not on the filter's exact value: turning
    /// 私鐵 off after 地下鐵 needs no index that turning 地下鐵 off did not.
    private var categoryIndexKey: String {
        "\(controller.layers.categories.anyHidden)|\(riddenCountries.joined(separator: ","))"
    }

    /// Whether the transport is on screen.
    ///
    /// Named, because it is what the two layouts animate on. `.transition` is
    /// inert unless the insertion happens inside an animated transaction, and
    /// the state that drives it lives in `PlaybackController` — where a
    /// `withAnimation` would make a store own a presentation decision. The
    /// same split `MapControlBar` already uses for `locationRefusal`: the
    /// store names the state, the view decides how it arrives.
    private var showsPlaybackBar: Bool {
        playback.isActive || playback.phase == .ended || videoExport.exporter.hasPendingResult
    }

    @ViewBuilder
    private var playbackBar: some View {
        if showsPlaybackBar {
            // The transport is its own view, and that is a performance
            // contract rather than tidiness — see `PlaybackTransportBar`. The
            // eleven properties that used to live here read the playhead
            // inside THIS body, so a run rebuilt the whole workspace on every
            // published tick.
            PlaybackTransportBar(
                playback: playback,
                videoExporter: videoExport.exporter,
                onStop: { stopPlayback() },
                onRequestVideoOptions: {
                    videoExport.plan(
                        playback: playback,
                        trains: playbackScope, rides: riddenRoutes.rides,
                        reducedMotion: reduceMotion)
                    sheet = .videoOptions
                }
            )
            .background {
                GeometryReader { bar in
                    Color.clear.preference(key: PlaybackBarHeightKey.self, value: bar.size.height)
                }
            }
            .transition(RailMotion.panelTransition(reduceMotion: reduceMotion))
        }
    }


    private func startVideoExport() {
        guard let mapView = controller.mapView else { return }
        videoExport.start(
            playback: playback, mapView: mapView, filming: playbackFilmedRect,
            trains: playbackScope, rides: riddenRoutes.rides,
            reducedMotion: reduceMotion)
    }

    /// The part of the map a film is cropped from.
    ///
    /// The playback camera centres its train in the map LESS the room the
    /// resident sheet takes (`RailMapController.playbackFramingInsets`) — the
    /// web app's `uncoveredRect`. The crop is taken from the same rectangle,
    /// because the two have to agree about where the middle is or the train
    /// sits off-centre in the file. The whole view is the fallback for a map
    /// that has not been laid out yet.
    private var playbackFilmedRect: CGRect {
        guard let mapView = controller.mapView else { return .zero }
        let inset = mapView.bounds.inset(by: controller.playbackFramingInsets)
        return inset.width > 1 && inset.height > 1 ? inset : mapView.bounds
    }

    private func stopPlayback() {
        if playback.phase == .idle {
            videoExport.exporter.dismissResult()
            return
        }
        if videoExport.isRecording { videoExport.abandonRecording() }
        playback.stop()
        // `restoreSelected`. Deliberately on STOP and not when a run reaches
        // its end: an ended run leaves its last journey selected, which is
        // what the reader was just watching and what the closing overview is
        // framing. Stopping is the reader saying they are done with the run,
        // and that is when the interrupted selection comes back.
        itineraries.selectedTrainID = playback.restoreSelectedTrainID
        playback.restoreSelectedTrainID = nil
    }

    /// Every region's lines, in one list.
    ///
    /// The store no longer holds them inside its `.loaded` case, because they
    /// arrive one region at a time and the map draws each as it lands rather
    /// than waiting for Japan.
    private var lines: [RailNetworkStore.DrawnLine] { store.mapLines }
}

/// Lets an inflexible block scroll rather than overflow.
///
/// The empty states are `VStack`s of a fixed height, and the panel they sit in
/// can be 130 points tall (§9.5.6's compact stop) or holding an accessibility
/// text size. Either way the block has to give way, and a `ScrollView` is how
/// a block that cannot shrink gives way.
// Internal rather than `private`: `WorkspaceUnavailableView` moved to a file of
// its own and gives way the same way the panels here do.
struct ScrollableIfNeeded: ViewModifier {
    func body(content: Content) -> some View {
        ScrollView { content }
            .scrollBounceBehavior(.basedOnSize)
    }
}

extension Coordinate {
    var clLocation: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

extension Duration {
    var milliseconds: Int {
        Int(components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000)
    }
}

#Preview {
    @Previewable @State var selection = PrimaryTab.all
    @Previewable @State var region: Region? = .jp
    RailWorkspaceView(
        store: RailNetworkStore(),
        itineraries: ItineraryStore(),
        library: RideLibrary(),
        riddenRoutes: RiddenRouteStore(),
        controller: RailMapController(),
        playback: PlaybackController(),
        statistics: MileageStatisticsStore(),
        regionScope: $region,
        selection: $selection
    )
    .environment(AppLocalization())
}
