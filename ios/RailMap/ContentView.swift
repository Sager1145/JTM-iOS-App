import CoreLocation
import MapKit
import RailCore
import RailPresentation
import SwiftUI

/// The railway over Apple Maps, in the two shapes iOS asks for.
///
/// The compact case is a persistent map workspace: the map and the ride panel
/// remain interactive members of the same hierarchy. It deliberately is not a
/// modal sheet. The panel snaps between three semantic sizes and reserves room
/// for the system tab bar, while the drag handle is the only surface that owns
/// the vertical resize gesture.
///
/// The layout is chosen by the window's shape, not the device. A phone in
/// landscape has almost no height for a sheet but plenty of width for a
/// sidebar, and it reports a *compact* horizontal size class on every model
/// but the largest — so size class alone would put a sheet there and leave the
/// map a letterbox.
///
///   tall windows   a resizable persistent panel over the map
///   wide windows   the ride list beside the map
///
/// The map's controls run down the right edge in both, and in the panel
/// layout they ride above it — at full height they are removed rather than
/// pushed off screen. A control the panel slides over is one that stops
/// working without ever looking broken.
///
/// ## The panel is one surface with two resident layers (§4.4)
///
/// Opening a journey does not push a screen and does not present a second
/// card: it changes which of two permanently-mounted layers is on top. The
/// list underneath keeps its search text, its date filter, its scroll offset
/// and its expanded sections because it was never torn down — which is exactly
/// what §4.4 requires of returning from a journey ("返回列表时应回到原旅程附
/// 近，而不是回到列表顶部"). See ``View/residentLayer(isTop:)``.
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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// Read for one reason: the share image is rendered off screen, and an
    /// `ImageRenderer` starts from the light appearance unless it is told
    /// otherwise — so a reader in Dark Mode would get a white poster of their
    /// own dark screen. See ``StatisticsPoster``.
    @Environment(\.colorScheme) private var colorScheme
    /// Read for one reason: `PanelHeader` drops its subtitle in a short
    /// window at an accessibility text size, and the compact stop must not
    /// reserve a row for a line that is not drawn. See ``compactHeaderRows``.
    @Environment(\.verticalSizeClass) private var verticalSizeClass
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
    /// destination is presented from this view now (see `RidesSheet.utility`)
    /// rather than from the shell — a controller that is already presenting
    /// the resident sheet cannot present a second one.
    @AppStorage("appearance") private var appearance = "system"
    @State private var render: RailMapView.RenderStats?
    @State private var query = ""
    @State private var selectedDate = Dates.allDates
    /// Alerts and confirmations share one presentation slot. Independent
    /// booleans here can all become true during the same map/menu callback,
    /// which asks one hosting controller to present twice.
    @State private var dialog: RidesDialog?
    /// §10.3's ⌘F target.
    @FocusState private var searchFocused: Bool
    @State private var sheet: RidesSheet?
    @State private var importFlow = ImportFlow()
    /// Filming a run — see ``VideoExportFlow``, which owns the recorder, the
    /// reader's choices and the length the options sheet quotes.
    @State private var videoExport = VideoExportFlow()
    @State private var didRunDebugPlayback = false
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
    /// The dates the reader typed in — see ``ManualDates``, which owns them
    /// and their persistence.
    @State private var manualDates = ManualDates()
    /// The text in the add-a-date alert. Transient view state, not a date yet.
    @State private var newManualDate = ""
    @AppStorage("map-follows-selected-date") private var mapFollowsSelectedDate = false
    /// `focusZoomEnabled` — 自動縮放. Off to start with, as in the web app: a
    /// map that moves itself every time a row is tapped is a map the reader
    /// cannot keep a place in, so it is asked for rather than assumed.
    @AppStorage("auto-focus-zoom") private var autoFocusZoom = false
    /// Where the resident sheet is resting, as a STAGE rather than as a
    /// `PresentationDetent`.
    ///
    /// The detent is derived from this (see ``detentBinding(_:)``) and never
    /// stored, because two of the three detents are `.height()` values
    /// computed from the window: a stored detent would be a number from the
    /// previous window size, and a detent that is not in the set the sheet was
    /// given is a detent SwiftUI silently replaces.
    @State private var stageSelection: SheetStage = Self.launchStage

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
    /// The sheet's height right now, reported every frame while it is dragged.
    @State private var sheetHeight: CGFloat = 0

    /// How tall the map's control rail actually draws, so the fade that keeps
    /// it out from under the status bar knows where its top edge is. See
    /// `mapLayout`'s `railFade`.
    @State private var railHeight: CGFloat = 0

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
    /// `PanelHeader` draws its collapsed title at `compactTitleSize`, relative
    /// to `.title3`; this is the row that title sits in, measured against the
    /// same style so the two move together.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title3) private var compactTitleRow: CGFloat = 48

    /// At accessibility sizes `PanelHeader` moves its controls onto their own
    /// 44-point row. The compact detent must reserve that row too; otherwise
    /// the adaptive layout is correct but the system sheet clips its bottom.
    ///
    /// …and one more row when the header is naming a journey, because there
    /// its subtitle stays through the collapse rather than being scaled away
    /// with the rest of the morph (``pinsSubtitle(for:)``). Measured from the
    /// same footnote line the header reserves the slot from, and gated on the
    /// same "is a subtitle drawn in this window at all" rule, so the stop
    /// cannot come to reserve a row the header does not draw or clip one it
    /// does.
    private var compactHeaderRows: CGFloat {
        let controls: CGFloat = dynamicTypeSize.isAccessibilitySize ? 50 : 0
        let drawsSubtitle = BottomChromeMetrics.drawsSubtitle(
            isAccessibilitySize: dynamicTypeSize.isAccessibilitySize,
            verticalSizeClass: verticalSizeClass)
        // Up to TWO rows, not one: the pinned subtitle is the journey's
        // stations and, under them, its times (``panelSubtitleDetail(for:)``).
        // Counted from the record rather than assumed, because a journey with
        // no times has one row and a stop reserved for two would open on a
        // strip of empty panel.
        //
        // Each row may wrap to a second line at an accessibility text size,
        // which is what `PanelHeader.subtitleLines` allows and what this has
        // to reserve — a stop measured for one line and drawn with two is the
        // clip `compactRow` exists to prevent.
        let rows: CGFloat = {
            guard drawsSubtitle, pinsSubtitle(for: selection), let train = selectedTrain
            else { return 0 }
            let content = journeyHeaderRows(train)
            return (content.stations.isEmpty ? 0 : 1) + (content.times.isEmpty ? 0 : 1)
        }()
        let wraps: CGFloat = dynamicTypeSize.isAccessibilitySize ? 2 : 1
        let subtitle =
            rows > 0
            ? BottomChromeMetrics.subtitleRow * wraps * rows
                + BottomChromeMetrics.pinnedSubtitleGap
            : 0
        return compactTitleRow + controls + subtitle
    }

    private enum RidesDialog {
        case addDate
        case delete(Train)
    }

    /// Everything this workspace can present over itself.
    ///
    /// One enum rather than four `isPresented` bindings on one view: SwiftUI
    /// presents a single sheet per anchor, and four bindings racing for it is
    /// how a "Delete" dialog swallows the editor that was opening behind it.
    private enum RidesSheet: Identifiable {
        case newJourney(Train)
        case edit(Train)
        case detail(Train)
        case importData
        /// §5.6: exporting is a SECONDARY flow — the shape, quality and
        /// bitrate appear once it is opened, not beside the transport.
        case videoOptions
        /// 圖例與資料來源 — the map's own information button.
        case mapInfo
        /// 地圖圖層 — what of the reader's rides is drawn, and which
        /// categories of ridden line. A sheet rather than a menu because the
        /// reader sets several of these in one visit and a `Menu` closes on
        /// the first one, which is the same reason the web app's popover
        /// stays open ("Multiple layer selections intentionally keep the menu
        /// open").
        case mapLayers
        /// A station's own card — what used to be the map's callout.
        case station(StationCard)
        /// The rides under one ambiguous tap — what used to be a
        /// `confirmationDialog`. It is here, beside the station card, because
        /// the two are the same event: a finger that landed on more than the
        /// map can answer by itself. See `RideChooserView`.
        case chooseRide([Train])
        /// §4.1's Data Library and Settings. They are presented from HERE
        /// rather than from the shell because the shell is already presenting
        /// the resident bottom sheet, and one controller cannot present two.
        case utility(UtilityDestination)
        /// §5.3.5's other share: the statistics page as a picture, already
        /// rendered, with the system share sheet one tap below it.
        case statisticsImage(StatisticsPoster.File)

        var id: String {
            switch self {
            case .newJourney(let train): "new:\(train.id)"
            case .edit(let train): "edit:\(train.id)"
            case .detail(let train): "detail:\(train.id)"
            case .importData: "import"
            case .videoOptions: "video"
            case .mapInfo: "info"
            case .mapLayers: "layers"
            case .station(let card): "station:\(card.id)"
            case .chooseRide(let trains): "choose:\(trains.map(\.id).joined(separator: ","))"
            case .utility(let destination): "utility:\(destination.rawValue)"
            case .statisticsImage(let file): "statisticsImage:\(file.id)"
            }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            // Wider than tall, or a regular-width window: sidebar. Read from
            // the geometry so a rotation or an iPad window resize switches
            // layouts as it happens.
            Group {
                if geometry.size.width > geometry.size.height
                    || horizontalSizeClass == .regular
                {
                    sidebarLayout
                } else {
                    mapLayout(in: geometry)
                }
            }
            // §4.3's bottom clearance is NOT published from here any more, and
            // there is nothing left to publish: the system already gives it to
            // every scroll view inside the sheet.
            //
            // What used to be here read `geometry.safeAreaInsets.bottom` off
            // THIS proxy — the root of the window, outside the sheet — and
            // called it "the bar's height plus the home indicator". It is not:
            // the tab bar lives inside the presented sheet, so the root proxy
            // never sees it and the number was the home indicator alone. Both
            // halves of that were wrong, because the strip it was trying to
            // reproduce is already handed to the sheet's own content — a
            // `GeometryProxy` inside a `TabView` page reports 83 points of
            // bottom safe area on an iPhone 17 Pro (49 of bar, 34 of
            // indicator), and SwiftUI insets scrolling content by it without
            // being asked.
            //
            // The hand-rolled margins that consumed this were therefore not
            // making up a shortfall, they were ADDING to a sufficient inset:
            // `.contentMargins(.bottom:for: .scrollContent)` composes with the
            // safe area rather than replacing it, which left the ride card
            // ending 200 points above the window instead of 83 — §14.1's
            // 多余空白, measured by scrolling each panel to its end.
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
        // Keyed on a cheap summary rather than on `launchRegion` itself: the
        // answer costs a pass over every ride, this key is read on every body
        // evaluation, and a sheet drag is a body evaluation per frame.
        .task(id: "\(controller.isMapReady)|\(launchFramingKey)") {
            guard controller.isMapReady, let launchRegion else { return }
            controller.frameAtLaunch(launchRegion.networkExtent)
        }
        // §5.3.2: while Passport is on top the map IS its coverage map, so
        // changing what is being reported on has to move the map to it.
        // Otherwise the reader switches to 韓國 and reads a Korean percentage
        // over a picture of Honshū.
        //
        // The globe button is on Upcoming and All Journeys now as well, and
        // the camera follows it there for the same reason it does here: those
        // two destinations narrow their list AND their map to the region (see
        // ``mapRides``), so a scope change that left the camera over Honshū
        // would be a map framed on a country whose journeys it is no longer
        // drawing.
        .onChange(of: regionScope) { _, region in
            frameRegionScope(region)
        }
        // …and ARRIVING at Passport is the same event.
        //
        // Only the region itself was watched, so the camera moved when the
        // scope changed but not when the reader switched INTO the destination
        // that scope belongs to. Opening 統計 with the scope already on 日本
        // therefore showed a card headed 日本 over whatever the map happened to
        // be framing — in practice the five-network view across China and
        // Korea. The overlays had switched to coverage mode; the spatial
        // meaning had not, which is the half of §4.2 that makes the map the
        // shared context rather than a backdrop.
        //
        // Guarded on the destination rather than fired on every switch: coming
        // back to the journey list must NOT move the camera, because there the
        // reader's own last framing is the thing they were looking at.
        // A `task(id:)` rather than an `onChange`, and the key carries the
        // NETWORK's readiness as well as the destination. Two reasons, both
        // found by testing rather than by reading:
        //
        //   - `onChange` fires on a CHANGE, so a launch that opens straight
        //     onto Passport — the screenshot harness does exactly this — never
        //     fired it at all.
        //   - `frameStatisticsRegion` measures a rect from `store.lines`, and
        //     for the first moments of a launch that array is empty, so the
        //     rect is null and the call returns having moved nothing. The tab
        //     was reached before the data it frames against existed.
        //
        // The key flips at most twice — arriving, then the packages landing —
        // so this is not a camera that keeps jumping while five regions decode.
        .task(id: "\(selection == .stats)|\(store.lines.isEmpty)") {
            guard selection == .stats else { return }
            // Coverage is a fraction of each network's OWN length, so this
            // screen is the one surface that is about all five countries at
            // once. A region that has not been decoded reads as zero rather
            // than as unknown, which is why the ask is unconditional here.
            store.ensureAll()
            guard !store.lines.isEmpty else { return }
            frameRegionScope(regionScope)
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
        // A headless way to put the workspace into its selected state.
        //
        // The Hero is reached by tapping a row, and a tap is the one thing a
        // screenshot harness driving `simctl` cannot perform — so every state
        // in §5.2, including the ones that only appear when a route fails,
        // would otherwise be unreviewable outside a human session. Same shape,
        // and the same DEBUG-only reach, as `RAILMAP_UI_TEST_PLAYBACK` above.
        .task(id: "\(itineraries.loaded?.trains.count ?? 0)") {
            guard let wanted = ProcessInfo.processInfo.environment["RAILMAP_UI_TEST_SELECT"],
                  itineraries.selectedTrainID == nil,
                  let trains = itineraries.loaded?.trains, !trains.isEmpty else { return }
            if let index = Int(wanted) {
                itineraries.selectedTrainID = trains[min(max(index, 0), trains.count - 1)].id
            } else {
                itineraries.selectedTrainID = wanted
            }
        }
        // Which region the camera starts on, and which sample is loaded —
        // the two things a `simctl` harness cannot tap its way to. The opening
        // camera is chosen from the reader's own rides now, so a harness that
        // has loaded no store at all still opens on the fallback country
        // rather than on the country the shot is meant to be of.
        .task(id: "\(store.lines.count)|\(controller.isMapReady)") {
            guard controller.isMapReady else { return }
            if let camera = ProcessInfo.processInfo.environment["RAILMAP_UI_TEST_CAMERA"] {
                let values = camera.split(separator: ",").compactMap { Double($0) }
                if values.count == 3 {
                    try? await Task.sleep(for: .milliseconds(700))
                    controller.mapView?.setRegion(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: values[0], longitude: values[1]),
                        span: MKCoordinateSpan(latitudeDelta: values[2], longitudeDelta: values[2])),
                        animated: false)
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
            try? await Task.sleep(for: .milliseconds(700))
            controller.mapView?.setVisibleMapRect(
                rect, edgePadding: UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40),
                animated: false)
        }
        // A sheet, for the same reason `RAILMAP_UI_TEST_SELECT` exists: the
        // legend, the importer and the export options are all reached by a tap
        // that a `simctl` harness cannot perform, so their layout would only
        // ever be reviewed by hand.
        .task(id: controller.isMapReady) {
            guard controller.isMapReady,
                  let wanted = ProcessInfo.processInfo.environment["RAILMAP_UI_TEST_SHEET"]
            else { return }
            try? await Task.sleep(for: .milliseconds(900))
            switch wanted {
            case "info": sheet = .mapInfo
            case "import": sheet = .importData
            case "edit":
                if let train = itineraries.selectedTrain ?? itineraries.loaded?.trains.first {
                    sheet = .edit(train)
                }
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
                if let station = store.stations.first {
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
            guard itineraries.loaded != nil,
                  let wanted = ProcessInfo.processInfo.environment["RAILMAP_UI_TEST_SAMPLE"],
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
                      rideIDs.contains($0.id)
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
        .alert(
            localization.journeyText("ios.journey.addDateTitle", fallback: "Add a date"),
            isPresented: addDateIsPresented
        ) {
            TextField("YYYY-MM-DD", text: $newManualDate)
            Button(localization.text("ios.cancel", fallback: "Cancel"), role: .cancel) {}
            Button(localization.journeyText("btn.add", fallback: "Add")) { addManualDate() }
                .disabled(Dates.normalizeDateString(newManualDate) == nil)
        } message: {
            Text(
                localization.journeyText(
                    "ios.journey.addDateDetail",
                    fallback: "Create an empty date to add journeys to later."))
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: confirmationIsPresented,
            titleVisibility: .visible
        ) {
            switch dialog {
            case .some(.delete(let train)):
                Button(
                    localization.countryText("btn.delete", fallback: "Delete"),
                    role: .destructive
                ) {
                    dialog = nil
                    PresentationHost.afterTeardown {
                        let id = train.id
                        if itineraries.selectedTrainID == id {
                            itineraries.selectedTrainID = nil
                        }
                        itineraries.delete(id)
                        persistMine()
                        signal(.deleted)
                    }
                }
            case .some(.addDate), .none:
                EmptyView()
            }
        } message: {
            if case .some(.delete) = dialog {
                // §13.3: say what the action affects before it is taken.
                Text(
                    localization.journeyText(
                        "ios.journey.deleteDetail",
                        fallback: "The journey is removed from the data on this device."))
            }
        }
        .sheet(item: $sheet) { presented in
            presentedSheet(presented)
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

    private var addDateIsPresented: Binding<Bool> {
        Binding(
            get: {
                if case .some(.addDate) = dialog { return true }
                return false
            },
            set: { presented in
                if !presented, case .some(.addDate) = dialog { dialog = nil }
            })
    }

    private var confirmationIsPresented: Binding<Bool> {
        Binding(
            get: {
                switch dialog {
                case .some(.delete): true
                case .some(.addDate), .none: false
                }
            },
            set: { presented in
                guard !presented else { return }
                switch dialog {
                case .some(.delete): dialog = nil
                case .some(.addDate), .none: break
                }
            })
    }

    private var confirmationTitle: String {
        switch dialog {
        case .some(.delete(let train)):
            localization.journeyText(
                "ios.journey.deleteConfirm",
                ["train": .string(train.number)],
                fallback: "Delete {train}?")
        case .some(.addDate), .none:
            ""
        }
    }

    /// Everything the workspace can present, by case.
    @ViewBuilder
    private func presentedSheet(_ presented: RidesSheet) -> some View {
        Group {
            switch presented {
            case .newJourney(let draft):
                RideEditorView(
                    train: draft,
                    title: localization.text("ios.editorTitleNew", fallback: "New"),
                    // The one place `isNew` is true, and the only place the
                    // ride switch is ever pre-filled from a date.
                    isNew: true
                ) { added in
                    // §8.2: saving selects the new journey, so the route state
                    // that follows is reported in its own Hero.
                    if let id = itineraries.add(added) {
                        itineraries.selectedTrainID = id
                    }
                    persistMine()
                    signal(.saved)
                    sheet = nil
                }
            case .edit(let train):
                RideEditorView(
                    train: train,
                    title: localization.text("ios.edit", fallback: "Edit")
                ) { edited in
                    itineraries.replace(edited, replacing: train.id)
                    persistMine()
                    sheet = nil
                }
            case .videoOptions:
                VideoExportOptionsView(
                    settings: videoExport.settings,
                    sourceRect: playbackFilmedRect,
                    displayScale: controller.mapView?.window?.screen.scale ?? 3,
                    seconds: videoExport.plannedSeconds
                ) {
                    sheet = nil
                    startVideoExport()
                }
            case .detail(let train):
                // §3.1: L4 metadata lives on a second surface, not in the Hero.
                NavigationStack {
                    RideDetailView(
                        train: train,
                        onSave: { edited in
                            itineraries.replace(edited, replacing: train.id)
                            persistMine()
                        },
                        onRebuild: { rebuildRoute(train) })
                    .toolbar {
                        // §14.4: a modal must be closable without a swipe, or
                        // Switch Control and keyboard readers cannot leave it.
                        ToolbarItem(placement: .cancellationAction) {
                            Button(localization.text("ios.cancel", fallback: "Cancel")) {
                                sheet = nil
                            }
                        }
                    }
                }
            case .importData:
                DataImportView(
                    flow: importFlow, itineraries: itineraries,
                    library: library)
            // §4.2: the map is the spatial context every destination shares,
            // and these three are the sheets ABOUT the map — so they are the
            // three that must not cover all of it. A legend that hides the
            // legend's subject, a layer switch whose effect is off screen, and
            // above all a station card that covers the station the reader just
            // tapped, are each a surface arguing with the thing it explains.
            //
            // Their detents are declared by the VIEWS, not here, which is the
            // pattern `VideoExportOptionsView` already set: a sheet knows what
            // shape it needs, and stating it at the presenter as well is a
            // second copy to keep in step. See each view's own
            // `presentationDetents`.
            case .mapInfo:
                MapInfoView()
            case .mapLayers:
                MapLayersView(controller: controller, classifying: categoryIndexes.isBuilding)
            case .station(let card):
                StationCardView(card: card)
            case .chooseRide(let trains):
                RideChooserView(
                    trains: trains,
                    // The date leads only when the list is not already scoped
                    // to one day: scoped, every candidate carries the same
                    // date and it says nothing about which is which.
                    showsDate: selectedDate == Dates.allDates,
                    presentation: { presentation(for: $0) }
                ) { train in
                    sheet = nil
                    PresentationHost.afterTeardown { pick(train) }
                }
            case .utility(let destination):
                UtilityDestinationView(
                    destination: destination,
                    itineraries: itineraries,
                    library: library,
                    appearance: $appearance,
                    network: store,
                    controller: controller)
            case .statisticsImage(let file):
                StatisticsShareView(file: file) { sheet = nil }
            }
        }
        // One surface for every sheet this workspace presents (§14.2, §6.5).
        //
        // Four of them did not set this and therefore took the system default,
        // which on iOS 26 is Liquid Glass — and then drew a `List` whose rows
        // add their own translucent grouped background on top. The legend, the
        // layer switches and the station card were light glass over light
        // glass over a moving map, which is the one stacking §6.5 rules out
        // ("内容层不得另叠一块相同强度的大玻璃") and the reason their body copy
        // sat on whatever terrain the reader had panned under it.
        //
        // The argument for the resident panel being opaque is in
        // `RailSheetBackground`, and it is the same argument: these are places
        // the reader READS. Applied here rather than in each view because the
        // four that were wrong were wrong by omission, and an omission is not
        // fixed by asking four more views to remember.
        .presentationBackground(Color.railMenuPresentationStyle)
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
        // Two heights, and they are NOT interchangeable.
        //
        // The live preference is measured inside the sheet and comes back in
        // the DETENT's own units: at `.height(134)` it reads 134 exactly
        // (measured on an iPhone 17 Pro), because the system adds the bottom
        // safe area to a height detent itself rather than taking it out of
        // one. So `sheetHeight` is directly comparable to `metrics.compact`
        // and `metrics.medium`, and `sheetFrame` — the strip the sheet
        // actually covers in the window — is that plus the home indicator.
        //
        // Use the frame for anything positioned against the WINDOW, and the
        // content height for anything interpolated between two DETENTS.
        let sheetFrame = sheetHeight > 0
            ? sheetHeight + geometry.safeAreaInsets.bottom
            : metrics.compact
        // The stage is the SECOND kind, not the first, and it used to be given
        // the first.
        //
        // `BottomChromeMetrics.stage(nearest:)` picks the closest of `compact`,
        // `medium` and `screenHeight`, and all three of those are detent
        // heights. Handing it `sheetFrame` — one home indicator taller —
        // therefore moved every crossover down by 34 points: measured on an
        // iPhone 17 Pro, the panel became `.medium` at 243 pt, where
        // `headerExpansion` reads 0.387. So one drag ran the header's morph on
        // one clock and everything keyed off the STAGE — the destination's
        // content mounting, the title's wording over a selected journey, the
        // Docked action row, Reduce Motion's whole named-state swap — on
        // another, a third of the way out of step. Both now measure against the
        // same stops, and the stage changes where the morph is half done.
        let stage = chromeStage(metrics, contentHeight: sheetHeight)
        // §9.5.6's header morph is one of the second kind: it runs from the
        // compact detent to the medium one, so it has to be fed the same units
        // those two are written in. It used to take `sheetFrame`, which is one
        // home indicator taller, and the compact stop therefore reported
        // itself 12 % expanded instead of 0 (measured 0.122). The panel never
        // reached its own collapsed state: the title drew 1.5 pt too large,
        // and the subtitle — `opacity(0.122)`, height `16 × 0.122 ≈ 2 pt`,
        // `.clipped()` — left the smear of clipped glyph tops under the title
        // that §14.1 names outright ("没有标题、正文、残影或多余空白").
        let headerExpansion = metrics.headerExpansionProgress(
            for: sheetHeight > 0 ? sheetHeight : metrics.compact)
        // The gap between the map's controls and the top of the sheet, and it
        // is CONSTANT for the whole drag.
        //
        // This used to be `min(sheetFrame, metrics.medium) + 12`, which held 12
        // pt only while the sheet was at or below Half. Past Half the lift
        // stopped following and the gap became `medium + 12 − sheetFrame` — it
        // closed, hit zero, and then the panel slid up over the rail, so the
        // last thing a reader saw before the controls vanished was the sheet
        // eating them from below.
        //
        // The clamp was there to stop the rail being pushed off the top of the
        // window. That is a real hazard, but it is the wrong instrument for it:
        // holding the rail still while the sheet keeps moving is a visible
        // collision, and the reader is dragging at the time. ``railFade``
        // answers the hazard instead, by taking the rail away before it can be
        // sliced by the status bar.
        let lift = sheetFrame + 12
        // How present the rail is, as the sheet rises past Half.
        //
        // The rail keeps a constant gap, so past a certain height its own top
        // leaves the safe area. `railHeight` is measured rather than assumed —
        // the compass comes and goes with the map's heading, which is 52 pt of
        // difference — and the fade runs over the 60 pt before the cut, so the
        // controls are gone by the time they would be clipped rather than
        // half-drawn under the clock.
        //
        // Everything here is expressed as a distance UP FROM THE WINDOW'S
        // BOTTOM, which is the one convention `lift` is in, because mixing the
        // two heights this file warns about is exactly how this went wrong the
        // first time: `metrics.medium` is a detent height and excludes the home
        // indicator, `sheetFrame` includes it, and `geometry.size.height` is
        // the SAFE-AREA height rather than the window's. Written against the
        // root proxy's own units, the fade read 0.88 at the Half stop — the
        // rail was permanently, slightly dimmed at the stop the app opens on.
        //
        // `railCeiling` is therefore the safe area's TOP edge measured from the
        // window's bottom, and the fade is keyed to how far the sheet has risen
        // ABOVE Half rather than to an absolute height. That makes "fully
        // opaque at and below Half" true by construction instead of true by
        // arithmetic that has to be re-derived on every device.
        let railCeiling = geometry.size.height + geometry.safeAreaInsets.bottom
        let mediumFrame = metrics.medium + geometry.safeAreaInsets.bottom
        let above = max(0, sheetFrame - mediumFrame)
        let headroom = max(0, railCeiling - (mediumFrame + 12 + railHeight))
        let railFade: Double = above <= headroom
            ? 1
            : Double(1 - min((above - headroom) / 60, 1))
        // Whether the rail is on screen AT ALL, as opposed to merely faded.
        //
        // Both halves matter and neither implies the other: `.expanded` is the
        // outright removal §4.3 asks for, and `railFade == 0` is the same
        // question asked of the drag that has not settled yet — the rail is
        // already invisible and already above the window by then. Anything
        // this is false for is not drawn, not hit-testable and not in the
        // accessibility tree; see the note on `.opacity` below for why the
        // last of those is not optional.
        let railPresent = stage != .expanded && railFade > 0
        return ZStack(alignment: .bottomTrailing) {
            map
            playbackBar
                .padding(.horizontal, 12)
                // Visual translation instead of animated bottom padding: the
                // bar follows the same live edge without invalidating layout on
                // every frame of the system sheet gesture.
                .offset(y: -lift)
                // §9.2's default spring: the transport arrives because the
                // reader pressed play, not because they threw it, so damping
                // is 1.0 and there is no overshoot.
                .railAnimation(
                    RailMotion.spring, value: showsPlaybackBar,
                    reduceMotion: reduceMotion)
            // No artificial upper viewport. The previous medium-detent band
            // kept this rail inside a ScrollView whose top edge permanently
            // clipped/faded the first control on some phone heights. The rail
            // still clears the live sheet through `lift`; above that it draws
            // as one uninterrupted control group.
            controlStack()
                .padding(.trailing, 12)
                // Measured, not computed: `MapControlBar` has a conditional
                // compass and its contents have changed twice. A constant here
                // would be a stale constant.
                .background {
                    GeometryReader { rail in
                        Color.clear.preference(
                            key: RailControlHeightKey.self, value: rail.size.height)
                    }
                }
                .offset(y: -lift)
                // §4.3: a control the sheet is about to cover is removed, not
                // left looking pressable under an opaque surface. `railFade`
                // also takes it away before the constant gap can push it under
                // the status bar; `.expanded` remains an outright zero so the
                // full-screen panel never leaves a ghost behind it.
                //
                // Opacity is not enough on its own, and this is the half the
                // constant gap made necessary. The old clamped lift left the
                // rail parked at the Half height, so a zero-opacity rail was
                // still sitting where it had always been; now it keeps rising
                // with the sheet, and at Full it is a hundred and sixty points
                // ABOVE the top of the window. A `.opacity(0)` view is still in
                // the accessibility tree and still hit-testable — VoiceOver
                // reached an invisible off-screen 列車経路 button and could not
                // scroll it into view, which is how the UI test found this.
                .opacity(railPresent ? railFade : 0)
                .allowsHitTesting(railPresent)
                .accessibilityHidden(!railPresent)
        }
        .ignoresSafeArea()
        .onPreferenceChange(RailControlHeightKey.self) { height in
            // Guarded: the rail republishes the same height on every layout
            // pass, and writing it back unconditionally would invalidate the
            // body that measured it once per frame of the sheet drag.
            if abs(height - railHeight) > 0.5 { railHeight = height }
        }
        // What the sheet is covering, so "frame this" lands in the strip the
        // reader can actually see rather than behind the panel.
        .onChange(of: sheetHeight) { _, height in
            controller.bottomObstruction = height + geometry.safeAreaInsets.bottom
        }
        .residentBottomSheet(
            metrics: metrics,
            detent: detentBinding(metrics),
            liveHeight: $sheetHeight
        ) {
            withPresentations(workspaceTabs(
                stage: stage,
                headerExpansion: headerExpansion))
        }
    }

    /// The detents, for this window AND this text size.
    private func chromeMetrics(in geometry: GeometryProxy) -> BottomChromeMetrics {
        BottomChromeMetrics(
            screenHeight: geometry.size.height,
            // The tab bar's band does not scale; the title row over it does.
            compactRow: BottomChromeMetrics.compactTabBand + compactHeaderRows,
            isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
    }

    /// Where the sheet is NOW, from its live height rather than from the bound
    /// detent — §9.5.5 point 6. The binding only changes once the sheet has
    /// settled, so content keyed off it changes a beat after the finger.
    private func chromeStage(
        _ metrics: BottomChromeMetrics, contentHeight: CGFloat
    ) -> SheetStage {
        guard sheetHeight > 0 else { return stageSelection }
        return metrics.stage(nearest: contentHeight)
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

    /// The system owns the bottom row: four destinations in one Liquid Glass
    /// capsule, each of them an icon over its own label, in whichever language
    /// the reader picked. Search is the fourth destination rather than the
    /// semantic role's separated circle — see the `Tab` below for why.
    @ViewBuilder
    private func workspaceTabs(
        stage: SheetStage,
        headerExpansion: CGFloat
    ) -> some View {
        if #available(iOS 18.0, *) {
            modernWorkspaceTabs(stage: stage, headerExpansion: headerExpansion)
        } else {
            legacyWorkspaceTabs(stage: stage, headerExpansion: headerExpansion)
        }
    }

    @available(iOS 18.0, *)
    private func modernWorkspaceTabs(
        stage: SheetStage,
        headerExpansion: CGFloat
    ) -> some View {
        TabView(selection: $selection) {
            Tab(
                tabTitle(.upcoming), systemImage: PrimaryTab.upcoming.systemImage,
                value: PrimaryTab.upcoming
            ) {
                page(.upcoming, stage: stage, headerExpansion: headerExpansion) {
                    upcomingPanel
                }
            }

            Tab(
                tabTitle(.stats), systemImage: PrimaryTab.stats.systemImage,
                value: PrimaryTab.stats
            ) {
                page(.stats, stage: stage, headerExpansion: headerExpansion) {
                    statisticsPanel
                }
            }

            Tab(
                tabTitle(.all), systemImage: PrimaryTab.all.systemImage,
                value: PrimaryTab.all
            ) {
                page(.all, stage: stage, headerExpansion: headerExpansion) {
                    allJourneysPanel(stage: stage, expansion: headerExpansion)
                }
            }

            // A titled destination like the other three, and deliberately
            // NOT `role: .search`.
            //
            // The role does not draw a destination, it draws a button: on
            // iOS 26 it leaves the capsule for a trailing glass circle with
            // its GLYPH ONLY, so the bottom row read as three named
            // destinations plus one unnamed control — and the name it dropped
            // is the only one of the four that a reader who does not already
            // read the magnifier as "search" has to be told. It is also not
            // stable across systems: the same build puts search back inside
            // the capsule, labelled, on iOS 27. One row, two shapes, neither
            // of them the one the other three tabs are in.
            //
            // Nothing functional goes with it. The role presents its field by
            // morphing the tab bar, and this app forbids that morph —
            // `railPersistentTabBar()` sets `tabBarMinimizeBehavior(.never)`
            // so the bar stays continuous across the three stops (§14.3) — so
            // `searchPanel` already draws the field itself, on every version
            // this app deploys to. See its own note.
            //
            // The title stays spelled out, for the reason it always was: a
            // `Tab` that leaves its label to the system is named by SwiftUI in
            // the BUNDLE's language, so the bar used to read 今後の行程 /
            // 統計 / すべての行程 / "Search" — the one word on it that ignored
            // the in-app language switch.
            Tab(
                tabTitle(.search), systemImage: PrimaryTab.search.systemImage,
                value: PrimaryTab.search
            ) {
                page(.search, stage: stage, headerExpansion: headerExpansion) {
                    searchPanel
                }
            }
        }
        // No `.searchable` here any more. It presented nothing: the semantic
        // Search role shows its field by morphing the tab bar, and
        // `railPersistentTabBar()` on the next line switches that morph off so
        // the bar stays continuous across the three stops (§14.3). The field
        // is drawn by `searchPanel` instead, on every OS version this app
        // deploys to. `railSearchFocused` went with it — ⌘F now moves focus to
        // that field directly, through the same `searchFocused` binding.
        .railPersistentTabBar()
        .modifier(SystemSheetTabSurface())
        // The visible titles are already resolved through AppLocalization,
        // but the system tab bar also owns selection/accessibility wording.
        // Keep that system-owned part in the same in-app language too.
        .environment(\.locale, localization.locale)
    }

    /// The app still deploys to iOS 17. It receives the same four semantic
    /// destinations through the old system TabView spelling; iOS 26+ is the
    /// path that gets the separately rendered Search role.
    private func legacyWorkspaceTabs(
        stage: SheetStage,
        headerExpansion: CGFloat
    ) -> some View {
        TabView(selection: $selection) {
            page(.upcoming, stage: stage, headerExpansion: headerExpansion) {
                upcomingPanel
            }
                .tabItem { Label(tabTitle(.upcoming), systemImage: PrimaryTab.upcoming.systemImage) }
                .tag(PrimaryTab.upcoming)

            page(.stats, stage: stage, headerExpansion: headerExpansion) {
                statisticsPanel
            }
                .tabItem { Label(tabTitle(.stats), systemImage: PrimaryTab.stats.systemImage) }
                .tag(PrimaryTab.stats)

            page(.all, stage: stage, headerExpansion: headerExpansion) {
                allJourneysPanel(stage: stage, expansion: headerExpansion)
            }
                .tabItem { Label(tabTitle(.all), systemImage: PrimaryTab.all.systemImage) }
                .tag(PrimaryTab.all)

            page(.search, stage: stage, headerExpansion: headerExpansion) {
                searchPanel
            }
                // Same as the iOS 18+ path above: the field belongs to
                // `searchPanel`. This `.searchable` had even less to give —
                // there is no search role before iOS 26 to hand it to.
                .tabItem { Label(tabTitle(.search), systemImage: PrimaryTab.search.systemImage) }
                .tag(PrimaryTab.search)
        }
        .modifier(SystemSheetTabSurface())
        .environment(\.locale, localization.locale)
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
    /// it certain rather than occasional: the sidebar builds the same four
    /// pages INLINE in `body` (the sheet hosts them in a controller of its own,
    /// which is a stack of its own), and UIKit's rotation runs that body
    /// nested inside thirty-odd frames of its own transition machinery.
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
        stage: SheetStage,
        headerExpansion: CGFloat,
        @ViewBuilder content: @escaping () -> Content
    ) -> WorkspacePage {
        WorkspacePage {
            AnyView(
                tabPage(
                    tab, stage: stage, headerExpansion: headerExpansion,
                    content: content))
        }
    }

    private func tabPage<Content: View>(
        _ tab: PrimaryTab,
        stage: SheetStage,
        headerExpansion: CGFloat,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            PanelHeader(
                title: panelTitle(for: tab, stage: .expanded),
                compactTitle: panelTitle(for: tab, stage: .compact),
                subtitle: panelSubtitle(for: tab),
                subtitleDetail: panelSubtitleDetail(for: tab),
                pinsSubtitle: pinsSubtitle(for: tab),
                stage: stage,
                expansionProgress: headerExpansion
            ) {
                panelActions(for: tab, stage: stage)
            }
            .layoutPriority(1)

            if stage != .compact {
                // Runs UNDER the tab bar, not up to it.
                //
                // iOS 26's bottom bar is a floating glass capsule, and the
                // rule that comes with it is that scrolling content passes
                // beneath it and is dimmed by the scroll edge effect — the bar
                // is a layer over the content, not the end of it.
                //
                // A scroll view does all of that by itself when it is the
                // thing holding the safe area: it draws through the inset and
                // adds the same inset to its CONTENT, so rows pass under the
                // glass and the last one still scrolls clear of it. What broke
                // it was the wrapper that used to be here — a `GeometryReader`
                // plus `.clipped()`, which took the safe area for itself, left
                // the list a region ending at the top of the bar, and then cut
                // every row along that line.
                //
                // Handing the region straight to `content()` is the fix, and
                // the reason there is no `ignoresSafeArea` here: that would
                // extend the drawing but take the content inset away with it,
                // trading a clipped last row for one parked under the glass
                // that cannot be scrolled out.
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        // The header is anchored to the top of the page, not floated in the
        // middle of it.
        //
        // Below the Half stop the branch above contributes nothing, so this
        // stack held a single view — and a lone child of a stack that is
        // handed the whole page is centred in it. That put the panel header
        // half of the leftover space below the card's top edge, which is a
        // distance that GROWS with the sheet: the title drifted downwards
        // through the first half of the drag and then jumped 76 points back up
        // at the stop where `content()` appeared and claimed the slack. See
        // `PanelHeader.collapsedTopInset` for the measurements. The header's
        // own padding states its distance from the top now, which is a
        // function of the morph rather than of what happens to be mounted
        // under it.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func tabTitle(_ tab: PrimaryTab) -> String {
        localization.text(tab.tabLocalizationKey, fallback: tab.tabFallbackName)
    }

    /// §5.1's list, and §5.2's journey card, as one surface with two layers.
    private func allJourneysPanel(stage: SheetStage, expansion: CGFloat) -> some View {
        ZStack(alignment: .top) {
            ridesList
                .residentLayer(isTop: panelRoute.isHome)
            // The card's header morphs against the SAME live number the panel
            // header does, so one drag moves both on one clock. See
            // `RideCard.expansionProgress`.
            rideHero(stage: stage, expansion: expansion)
                .residentLayer(isTop: !panelRoute.isHome)
        }
    }

    /// The journeys the statistics destination is reporting on.
    ///
    /// The same two filters `PassportWorkspaceView` applies, spelled here as
    /// well because the map is outside that view now — and derived from the
    /// same two values, so the two cannot disagree about what is in scope.
    private var statisticsScopedTrains: [Train] { statisticsScope.trains }

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
        return derived.statisticsScope(trains: trains, region: region, date: date) {
            trains.filter { train in
                if let region, Region.resolved(train) != region { return false }
                guard RideLedger.hasBeenRidden(train) else { return false }
                guard date != Dates.allDates else { return true }
                return Dates.trainSpans(train.forDates, date: date)
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
    private var statisticsPanel: some View {
        PassportWorkspaceView(
            itineraries: itineraries,
            statistics: statistics,
            riddenRoutes: riddenRoutes,
            network: store,
            controller: controller,
            playback: playback,
            region: $regionScope,
            openData: openData,
            openSettings: openSettings)
    }

    // MARK: - the panel header (§9.5.6: 左上大标题, 右上功能按钮)

    /// The panel's title, which at the smallest stop is not always the
    /// destination's name.
    ///
    /// §5.1.2 keeps the selected journey's Hero for Half and above — Docked
    /// gets "缩小标题行" — but a reduced title row still has to answer that
    /// section's own main question, 「这趟车从哪里到哪里，地图上是哪一条？」.
    /// Collapsed, this row was reading 「現在の行程」: the name of the STATE,
    /// not of the journey, while the one line that named the journey was the
    /// subtitle, which `PanelHeader` correctly fades out at that stop. So the
    /// panel could be collapsed over a route drawn on the map with nothing on
    /// screen saying which route it was.
    ///
    /// At Docked the row therefore carries the train, and at the two open
    /// stops it goes back to naming the state — because there the card below
    /// is already spelling the number, the endpoints and the times in full,
    /// and two headings saying the same thing is what §3.2 calls competing for
    /// the same level.
    private func panelTitle(for tab: PrimaryTab, stage: SheetStage) -> String {
        switch tab {
        case .upcoming:
            localization.text("nav.upcoming", fallback: "Upcoming")
        case .stats:
            localization.text("nav.stats", fallback: "Stats")
        case .all:
            if let train = selectedTrain {
                // Not `train.number` itself: that field is a caption, and at
                // this stop it is one line over a tab bar. See
                // ``JourneyTitle``, which is where the cut is decided and
                // where the cases are held to it.
                stage == .compact
                    ? JourneyTitle.compact(train)
                    : localization.text("ios.currentJourney", fallback: "Current journey")
            } else {
                localization.text("nav.allJourneys", fallback: "All journeys")
            }
        case .search:
            localization.countryText("sec.search", fallback: "Search & Add")
        }
    }

    /// Whether this destination's subtitle survives the collapse (§9.5.6).
    ///
    /// Only where the header has stopped naming a STATE and started naming a
    /// journey. Docked over the map, that header is all there is: the title
    /// says which service — 普通, 特急 はるか38号（1038M） — and without the
    /// line under it nothing on screen says between which stations or when.
    /// The card that states the pair properly is content, and the collapsed
    /// stop does not mount content.
    ///
    /// The other three destinations' subtitles are summaries of the list
    /// behind them (「231 趟旅程」), and a summary of something the reader
    /// cannot see is not worth the line of map it costs.
    ///
    /// ``compactHeaderRows`` reads the same answer, because the stop has to be
    /// tall enough for what this puts in it.
    private func pinsSubtitle(for tab: PrimaryTab) -> Bool {
        tab == .all && selectedTrain != nil
    }

    /// The header's second subtitle row: the selected journey's times, under
    /// its stations.
    ///
    /// A row of its own rather than a tail on the station line. Docked, the
    /// header has the panel's whole width and one thing to say, and the two
    /// facts do not compete for it when they are stacked — 「北小金 → 我孫子 ·
    /// 08:05—08:17」 is one line long enough to need shrinking on a phone,
    /// where the same content on two lines needs none.
    ///
    /// `nil` for a record with no times at all, which is a record that has
    /// nothing to put here — not an empty row to keep the layout tidy.
    private func panelSubtitleDetail(for tab: PrimaryTab) -> String? {
        guard tab == .all, let train = selectedTrain else { return nil }
        let times = journeyHeaderRows(train).times
        return times.isEmpty ? nil : times
    }

    /// The two rows the header says about one journey: between where, and
    /// when.
    ///
    /// One function because they are one reading of the same record, and
    /// because the pair decides how tall the collapsed stop has to be — see
    /// ``compactHeaderRows``.
    private func journeyHeaderRows(_ train: Train) -> (stations: String, times: String) {
        let stations = [
            localization.originName(of: train),
            localization.destinationName(of: train),
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " → ")
        let departure = train.stops.first?.departure ?? train.stops.first?.arrival
        let arrival = train.stops.last?.arrival ?? train.stops.last?.departure
        let times = [departure, arrival]
            .compactMap { time in
                guard let time, !time.isEmpty else { return nil }
                return time
            }
            .joined(separator: "—")
        return (stations, times)
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
            if let train = selectedTrain {
                // Stations only. The times are the row UNDER this one — see
                // ``panelSubtitleDetail(for:)`` — because a journey's where
                // and its when are two facts, and running them together
                // behind a interpunct made one line that had to be truncated
                // before either of them was finished.
                let stations = journeyHeaderRows(train).stations
                return stations.isEmpty ? nil : stations
            }
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
    @ViewBuilder
    private func panelActions(for tab: PrimaryTab, stage: SheetStage) -> some View {
        // Docked, over a selected journey, this row IS the journey's controls.
        //
        // §5.1.2 holds the Hero back until Half, so at this stop the card's
        // own action group is not on screen — and a panel collapsed over a
        // route the reader is looking at needs the one action the resolver
        // picked for that state, and a way back to the list. Both come from
        // the same `JourneyPresentation` the Hero would have used, so the
        // action here and the action there can never disagree.
        if tab == .all, stage == .compact, let train = selectedTrain {
            let presentation = presentation(for: train)
            if let primary = presentation.primaryAction {
                let appearance = primary.appearance(localization)
                SheetIconButton(
                    systemImage: appearance.systemImage,
                    accessibilityLabel: Text(appearance.label),
                    action: { perform(primary, on: train) }
                )
            }
            SheetIconButton(
                systemImage: "xmark",
                accessibilityLabel: Text(
                    localization.journeyText(
                        "ios.journey.backToList", fallback: "Back to the list"))
            ) {
                itineraries.selectedTrainID = nil
            }
        }
        // The list's transport, and ONLY while the list is what is on screen.
        //
        // With a journey selected there were two play buttons a thumb's width
        // apart — this one and the card's own — and both played the same
        // journey. §16's mapping rule: a control belongs beside what it
        // affects, and one action must not have two entries in one state. So
        // the scope is split by state rather than duplicated: selected, the
        // CARD owns playing that journey; back at the list, this one returns
        // and plays the queue the list defines.
        if tab == .all, panelRoute.isHome {
            playbackButton
        }
        // §5.1's two scopes, on the three destinations that have them. Not
        // over a selected journey: there the row is that journey's controls
        // (see the branch above), and four more glyphs would push them off it.
        if tab == .upcoming || (tab == .all && panelRoute.isHome) {
            journeyDateMenu(for: tab)
            regionMenu
        }
        if tab == .stats {
            statisticsDateMenu
            regionMenu
            statisticsShareButton
        }
        if tab == .search {
            SheetIconButton(
                systemImage: "plus",
                accessibilityLabel: Text(
                    localization.text("ios.newJourney", fallback: "New journey"))
            ) {
                sheet = .newJourney(newJourneyScaffold(in: defaultRegion))
            }
        }
        Menu {
            destinationMenu(for: tab)
        } label: {
            // A gear, not a second ellipsis.
            //
            // This is the GLOBAL entry — Data Library, Settings, the sample
            // and working-set actions — and the journey card below carries its
            // own ellipsis for that journey's secondary actions. (The date
            // filter used to be in here too. It is a filter, not a setting,
            // and it is a round button of its own now on every destination but
            // Search.) Two identical glyphs on one
            // screen with two different scopes is precisely the ambiguity §16
            // calls a weak mapping: the reader cannot tell which "more" they
            // are about to open, and the label that would explain it is not
            // drawn. A gear says "this app's settings" without being read.
            SheetIconLabel(systemImage: "gearshape")
        }
        .accessibilityLabel(
            Text(localization.text("nav.utilities", fallback: "Data and settings")))
        // The label is the READER's language, so it is not an address. A UI
        // test that looked this control up by "Data and settings" found
        // nothing on a Japanese simulator and reported the utility menu
        // unreachable — which is the same trap `MapControlBar`'s controls were
        // pulled out of. Identifiers are language-independent; labels are for
        // people.
        .accessibilityIdentifier("utilityMenuButton")
    }

    @ViewBuilder
    private func destinationMenu(for tab: PrimaryTab) -> some View {
        if tab == .all || tab == .upcoming || tab == .search {
            // The date filter is a BUTTON on Upcoming and All Journeys now
            // (see ``panelActions(for:stage:)``), so it appears here only for
            // Search — one filter must not have two entries in one state.
            if tab == .search, let loaded = itineraries.loaded, !loaded.days.isEmpty {
                dateFilterSection(loaded)
            }
            rideSourceSection
            Divider()
        }
        // Identified for the same reason the gear itself is, and it is the
        // same lesson a third time: `ConsoleSweepTests` looked these two up by
        // the English "Data" and "Settings", found neither on a Chinese
        // simulator, and walked past the Data Library and Settings without
        // failing loudly enough to be noticed — which is precisely the "clean
        // console that is a lie" that suite's own comments warn about.
        Button(action: openData) {
            Label(
                localization.text(
                    UtilityDestination.data.localizationKey,
                    fallback: UtilityDestination.data.fallbackName),
                systemImage: UtilityDestination.data.systemImage)
        }
        .accessibilityIdentifier("utilityDataButton")
        Button(action: openSettings) {
            Label(
                localization.text(
                    UtilityDestination.settings.localizationKey,
                    fallback: UtilityDestination.settings.fallbackName),
                systemImage: UtilityDestination.settings.systemImage)
        }
        .accessibilityIdentifier("utilitySettingsButton")
    }

    /// Move the map to the network the reader has scoped to — or, for 全部,
    /// back out to all five of them.
    ///
    /// Framed from the LINES rather than from the rides: the coverage figure
    /// is a fraction of the network, and a reader who has ridden two stations
    /// in Korea is being shown how little of Korea that is.
    private func frameRegionScope(_ region: Region?) {
        let rect = store.lines
            .filter { region == nil || $0.region == region }
            .reduce(MKMapRect.null) { $0.union($1.mapRect) }
        guard !rect.isNull else { return }
        controller.fit(rect)
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
        Menu {
            // 全部 first and above a divider, for the same reason the region
            // menu puts it there: it is the absence of a scope, not a date.
            Button {
                statistics.selectDate(Dates.allDates)
            } label: {
                Label(
                    localization.countryText("date.all", fallback: "All dates"),
                    systemImage: statistics.selectedDate == Dates.allDates
                        ? "checkmark" : "calendar")
            }
            Divider()
            ForEach(statisticsDates, id: \.self) { date in
                Button {
                    statistics.selectDate(date)
                } label: {
                    Label(
                        dateBucketLabel(date),
                        systemImage: date == statistics.selectedDate ? "checkmark" : "calendar")
                }
            }
        } label: {
            SheetIconLabel(
                systemImage: "calendar",
                isActive: statistics.selectedDate != Dates.allDates)
        }
        // `statsText`, not `text`: the label lives in the statistics screen's
        // own string table, and `text` would have handed VoiceOver the English
        // fallback in every language.
        .accessibilityLabel(Text(localization.statsText("ios.stats.scope")))
        .accessibilityValue(Text(dateBucketLabel(statistics.selectedDate)))
        .accessibilityIdentifier("statisticsDateButton")
    }

    /// The days the statistics can be scoped to: this region's, in order.
    ///
    /// Region-filtered but never date-filtered, or choosing a day would empty
    /// the menu that chose it. Same slice `StatisticsDashboardContent.scoped`
    /// takes, so the menu cannot offer a day the numbers have no rides for.
    private var statisticsDates: [String] {
        guard let loaded = itineraries.loaded else { return [] }
        let trains = regionScope.map { region in
            loaded.trains.filter { Region.resolved($0) == region }
        } ?? loaded.trains
        let ids = Set(trains.map(\.id))
        return loaded.days.compactMap { day in
            day.trains.contains { ids.contains($0.id) } ? day.date : nil
        }
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
                    regionScope = candidate
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
        SheetIconButton(
            systemImage: "square.and.arrow.up",
            accessibilityLabel: Text(localization.statsText("ios.stats.shareImage"))
        ) {
            guard let file = renderStatisticsImage() else { return }
            PresentationHost.afterTeardown { sheet = .statisticsImage(file) }
        }
        .disabled(statistics.view == nil)
        .accessibilityIdentifier("statisticsShareButton")
    }

    /// The statistics page, as a PNG on disk. `nil` if it could not be drawn
    /// or could not be written, in which case nothing is presented.
    private func renderStatisticsImage() -> StatisticsPoster.File? {
        StatisticsPoster.render(
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
                    "date": .string(dateBucketLabel(statistics.selectedDate)),
                ]),
            title: localization.text("nav.stats", fallback: "Stats"),
            localization: localization,
            colorScheme: colorScheme)
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
            trains
                .filter { train in
                    // The header's two scopes first — they are the reader's,
                    // and they are the reason the two round buttons above this
                    // list are not decoration. The date is the SAME value the
                    // log filters on (`selectedDate`): one filter, one owner,
                    // whichever of the two destinations it was set from.
                    if let region, Region.resolved(train) != region { return false }
                    if scopedDate != Dates.allDates,
                        !Dates.trainSpans(train.forDates, date: scopedDate) { return false }
                    guard let date = train.date, !date.isEmpty,
                        let regionToday = today[Region.resolved(train)]
                    else { return false }
                    return date >= regionToday
                }
                .sorted { lhs, rhs in
                    let a = lhs.date ?? "", b = rhs.date ?? ""
                    return a == b ? lhs.id < rhs.id : a < b
                }
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

    /// The country the map is framed on at launch.
    ///
    /// The soonest journey that has not happened yet; for a reader with
    /// nothing ahead of them, the most recent one that has; and for a store
    /// with no dated ride in it at all, ``defaultRegion``'s answer — which
    /// ends at Japan, as every other "which region did you mean" in the app
    /// does.
    ///
    /// `nil` until the rides have been read, and that is load-bearing rather
    /// than tidy: the opening move happens ONCE, so an answer given while the
    /// store is still on disk would be Japan for everybody, for good.
    private var launchRegion: Region? {
        switch itineraries.state {
        case .idle, .loading:
            return nil
        case .failed:
            // Nothing to choose from and nothing coming. Better the fallback
            // country than a camera left sitting on the whole globe waiting
            // for rides that are not going to arrive.
            return defaultRegion
        case .loaded:
            if let next = upcomingTrains.first { return Region.resolved(next) }
            if let first = earliestPastTrain { return Region.resolved(first) }
            return defaultRegion
        }
    }

    /// What the opening move is waiting on, as something cheap to compare.
    ///
    /// `LoadState` is not `Equatable` and ``launchRegion`` costs a pass over
    /// every ride; this is read on every body evaluation, so it is neither.
    private var launchFramingKey: String {
        switch itineraries.state {
        case .idle: "idle"
        case .loading: "loading"
        case .failed: "failed"
        case .loaded(let loaded): "loaded:\(loaded.trains.count)"
        }
    }

    /// The FIRST journey in the log — the oldest record behind today, on its
    /// own region's clock.
    ///
    /// "The first of the history" read literally: earliest by date, which is
    /// also the first row the journey list shows, because `Dates` orders its
    /// buckets ascending. Not "the most recent one" — that is the other end of
    /// the same list, and the two disagree for anybody whose travel has
    /// crossed a border.
    ///
    /// An undated record is not in the running, for the reason it is not
    /// upcoming either: it has no position on a calendar to be behind.
    private var earliestPastTrain: Train? {
        let today = todayByRegion()
        let trains = itineraries.loaded?.trains ?? []
        return derived.earliestPast(trains: trains, today: today) {
            trains
                .filter { train in
                    guard let date = train.date, !date.isEmpty,
                        let regionToday = today[Region.resolved(train)]
                    else { return false }
                    return date < regionToday
                }
                .min { lhs, rhs in
                    let a = lhs.date ?? "", b = rhs.date ?? ""
                    return a == b ? lhs.id < rhs.id : a < b
                }
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

    // MARK: - wide windows: a sidebar, on iPad and on a phone in landscape

    private var sidebarLayout: some View {
        HStack(spacing: 0) {
            withPresentations(workspaceTabs(stage: .expanded, headerExpansion: 1))
            // Narrower on a phone, where the map has little enough width as it
            // is; a fixed 320 would eat half of a landscape iPhone.
            .frame(width: horizontalSizeClass == .regular ? 360 : 300)
            // The same opaque reading surface the resident sheet uses, not a
            // material. `RailSheetBackground`'s own note is the argument: the
            // panel is where the reader READS, and a surface that takes its
            // colour from whatever the map happens to be showing gives that
            // text a different background in every part of the country. It
            // applied only to the phone-portrait sheet, so one rotation turned
            // the same workspace from an opaque page into a translucent one.
            .background { RailSheetBackground() }

            Divider()

            ZStack(alignment: .bottomTrailing) {
                map
                controlStack().padding(12)
                playbackBar
                    .padding(12)
                    .railAnimation(
                        RailMotion.spring, value: showsPlaybackBar,
                        reduceMotion: reduceMotion)
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    /// Which layer is on top. §4.4: closing a journey is returning to the list,
    /// and it does not clear the date filter.
    private var panelRoute: RideRoute {
        guard let id = itineraries.selectedTrainID, selectedTrain != nil else { return .home }
        return .ride(id)
    }

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

    // MARK: - §5.2 the selected journey

    @ViewBuilder
    private func rideHero(stage: SheetStage, expansion: CGFloat) -> some View {
        if let train = selectedTrain {
            let presentation = presentation(for: train)
            RideCard(
                train: train,
                presentation: presentation,
                stage: stage,
                expansionProgress: expansion,
                dateChipTitle: train.date,
                onClose: { itineraries.selectedTrainID = nil },
                onPrimary: { perform($0, on: train) },
                onSecondary: { perform($0, on: train) },
                onSetRidden: { setRidden(train, $0) }
            )
            .padding(.top, 4)
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
                if days.isEmpty {
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
            sheet = .newJourney(newJourneyScaffold(in: defaultRegion))
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
            itineraries: itineraries,
            persist: persistMine,
            play: { startPlayback([train]) },
            showDetail: { sheet = .detail(train) },
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
        itineraries.replace(RideLedger.setRidden(train, ridden), replacing: train.id)
        persistMine()
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
            sheet = .newJourney(newJourneyScaffold(in: defaultRegion))
        case .importData:
            sheet = .importData
        case .locate:
            if let train { itineraries.selectedTrainID = train.id }
            controller.fitToSelection()
        case .showOnMap:
            guard let train else { return }
            itineraries.toggleVisibility(train.id)
            persistMine()
        case .rebuildRoute:
            guard let train else { return }
            _ = rebuildRoute(train)
        case .save:
            // §8.3: the draft and its atomic commit belong to the editor.
            if let train { sheet = .edit(train) }
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
            if let train { sheet = .edit(train) }
        case .duplicate:
            guard let train else { return }
            itineraries.duplicate(train.id)
            persistMine()
        case .hide, .show:
            guard let train else { return }
            itineraries.toggleVisibility(train.id)
            persistMine()
        case .delete:
            if let train {
                PresentationHost.afterTeardown { dialog = .delete(train) }
            }
        case .inspectDetails:
            if let train { sheet = .detail(train) }
        case .rebuildRoute:
            guard let train else { return }
            _ = rebuildRoute(train)
        case .cancel:
            itineraries.selectedTrainID = nil
        case .importData:
            sheet = .importData
        case .add:
            sheet = .newJourney(newJourneyScaffold(in: defaultRegion))
        }
    }

    /// §8.4: rebuilding regenerates route sections from the stops. It never
    /// deletes the journey, and a section that still cannot be solved stays
    /// undrawn rather than being straightened.
    @discardableResult
    private func rebuildRoute(_ train: Train) -> Int? {
        let count = itineraries.rebuildRouteSections(train.id)
        persistMine()
        return count
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
        // Memoised, because one body evaluation asks this up to three times —
        // the header's count, the list itself, and `playbackScope` behind the
        // play button's `disabled` — and with a query in the field each of
        // those is a locale-aware substring search over every field of every
        // journey. See ``WorkspaceDerived``.
        //
        // Keyed on the naming generation as well, because the search now reads
        // names the store does not carry: the same query over the same store
        // answers differently once the reader switches language, or once a
        // readings table lands. See ``StationNamingGeneration``.
        derived.days(
            of: loaded, selectedDate: selectedDate, region: region,
            query: searchQuery,
            naming: localization.stationNamingGeneration
        ) {
            computeFilteredDays(loaded, region: region, query: searchQuery)
        }
    }

    private func computeFilteredDays(
        _ loaded: ItineraryStore.Loaded,
        region: Region?,
        query searchQuery: String
    ) -> [ItineraryStore.Loaded.Day] {
        var source = selectedDate == Dates.allDates
            ? loaded.days
            : loaded.days.filter { $0.date == selectedDate }
        // The region scope, before the query rather than after it: a day left
        // with no journey in this region is not an empty day, it is a day this
        // scope does not have — and a section header over nothing is the one
        // thing a filtered list must not draw.
        if let region {
            source = source.compactMap { day in
                let trains = day.trains.filter { Region.resolved($0) == region }
                return trains.isEmpty ? nil : .init(date: day.date, trains: trains)
            }
        }
        let needle = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return source }
        // §5.1's field list lives in `JourneySearchMatcher`, not in this
        // closure. It used to be spelled here, and it was missing `date` and
        // `direction` — which no test noticed, because every test searched by
        // train number. A contract that exists in one place can be checked;
        // one that exists inside a filter cannot.
        //
        // `alsoNamed` is the one field the matcher cannot see for itself: the
        // journey surfaces name stations through the readings table, so a
        // Taiwanese ride reads "Taipei Main Station" to an English reader
        // while the record says 台北車站. Searching only the record meant the
        // name on the screen found nothing. The table is in the app bundle
        // behind a `@MainActor` object, which is why this is the caller that
        // supplies it — see ``AppLocalization/localizedStationNames(of:)``
        // for what it costs and why it costs nothing in Japan.
        let alsoNamed = localization.localizedStationNames(of:)
        return source.compactMap { day in
            let trains = JourneySearchMatcher.filter(
                day.trains, query: needle, alsoNamed: alsoNamed)
            return trains.isEmpty ? nil : .init(date: day.date, trains: trains)
        }
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
        guard tab == .upcoming else { return availableDates(loaded, region: regionScope) }
        // Deliberately built from the region filter and the calendar ALONE:
        // `upcomingScope` also applies `selectedDate`, and a menu built from
        // that would collapse to the one day it had already been set to.
        let today = todayByRegion()
        let trains = loaded.trains.filter { train in
            if let region = regionScope, Region.resolved(train) != region { return false }
            guard let date = train.date, !date.isEmpty,
                let regionToday = today[Region.resolved(train)]
            else { return false }
            return date >= regionToday
        }
        return Dates.availableDates(trains.map(\.forDates))
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
            selectedDate = Dates.allDates
        } label: {
            Label(
                localization.countryText("date.all", fallback: "All dates"),
                systemImage: selectedDate == Dates.allDates ? "checkmark" : "calendar")
        }
        ForEach(dates, id: \.self) { date in
            Button {
                selectedDate = date
            } label: {
                Label(
                    dateBucketLabel(date),
                    systemImage: selectedDate == date ? "checkmark" : "calendar")
            }
        }
        Group {
            Divider()
            Button {
                newManualDate = ""
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
                    selectedDate = Dates.allDates
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
            // decision — what the MAP does when the list's scope or selection
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

    /// Add what was typed, and go and look at it — the reason for adding it.
    private func addManualDate() {
        guard let added = manualDates.add(newManualDate) else { return }
        selectedDate = added
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
    /// `StoreOperations.createBlankTrain` is regional DATA, not a template
    /// with a parameter: Japan starts 東京→熱海 with N02 codes the solver can
    /// route immediately, Taiwan on the airport-MRT corridor with TDX
    /// StationUIDs, and so on. So the choice cannot be deferred to the editor
    /// without handing the reader a scaffold from the wrong country. A plain
    /// tap takes the region the reader is already working in; the menu offers
    /// the other four.
    private func newJourneyScaffold(in region: Region) -> Train {
        StoreOperations.createBlankTrain(country: region.code).taggingRegion()
    }

    /// Which region a new journey starts in when the reader just taps `+`:
    /// the one they are looking at, then the one they have most rides in,
    /// then Japan.
    private var defaultRegion: Region {
        if let train = itineraries.selectedTrain { return Region.resolved(train) }
        let trains = itineraries.loaded?.trains ?? []
        let counts = Dictionary(grouping: trains, by: Region.resolved).mapValues(\.count)
        return counts.max {
            $0.value != $1.value
                ? $0.value < $1.value
                : (Region.ordered.firstIndex(of: $0.key) ?? 0)
                    > (Region.ordered.firstIndex(of: $1.key) ?? 0)
        }?.key ?? .jp
    }

    private func persistMine() {
        // Any edit forks a bundled sample into the reader's own store. A
        // sample remains immutable on disk and the user's change is durable.
        guard let store = itineraries.store else { return }
        library.save(store)
    }

    /// The one basemap all three destinations share (§9.5.6, and the reader's
    /// own "需要三个 tab 都共用一个底图").
    ///
    /// One `MKMapView`, at the root, under the sheet. What changes between
    /// destinations is not the map but the QUESTION being asked of it, so what
    /// varies here are its inputs: which rides are drawn, and whether the
    /// complete network is on.
    private var map: some View {
        RailMapView(
            lines: lines,
            stations: store.stations,
            rides: mapRides,
            selectedTrainID: itineraries.selectedTrainID,
            selectedDate: selectedDate,
            // One display switch, one source of truth. Statistics can change
            // the reported region and frame the camera, but it must not force
            // the complete network back on after the reader turns it off.
            showsNetwork: controller.showsNetwork,
            basemapOpacity: controller.basemapOpacity,
            categoryIndexes: categoryIndexes.byCountry,
            autoFocus: autoFocusZoom,
            controller: controller,
            playback: playback,
            onSelectRide: { selectFromMap($0) },
            onSelectStation: { sheet = .station($0) },
            // Which countries the reader is actually looking at, from the rect
            // the map rebuilt for. Only while the network is on: with it off
            // there are no rails and no station dots to draw, so a pan across
            // Japan costs nothing at all.
            onBuildRect: { rect in
                guard controller.showsNetwork else { return }
                store.ensure(regionsIntersecting: rect)
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
        // sheet layout and the sidebar layout mount it and the controller must
        // not depend on which one the window is in. `initial: true` is what
        // covers a reader who already had the setting on at launch.
        .onChange(of: reduceMotion, initial: true) { _, reduced in
            controller.reduceMotion = reduced
        }
    }

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
        let trains = ids.compactMap { id in
            itineraries.loaded?.trains.first { $0.id == id }
        }
        switch trains.count {
        case 0:
            itineraries.selectedTrainID = nil
        case 1:
            pick(trains[0])
        default:
            sheet = .chooseRide(trains)
        }
    }

    /// Select the ride the reader pointed at. Only that.
    ///
    /// The web app's `selectTrain` also jumps the date filter to the picked
    /// ride's own day, and this used to carry half of that: a ride outside the
    /// filtered day dropped the filter back to 全部. Both directions are gone.
    /// A pick that moves the date filter answers a question the reader did not
    /// ask — they pointed at one line and the whole list under the map became
    /// a different day — and it is the reason choosing a second journey took
    /// three taps instead of one, because the day it left behind then had to
    /// be stepped back out of before the next line was reachable.
    ///
    /// Nothing is hidden by leaving the filter alone. The selected journey's
    /// card reads from the store rather than from the filtered days
    /// (``selectedTrain``), and on the map a selected ride draws at full
    /// strength whichever day it runs on — that is exactly what
    /// ``MapDateScope/alpha(own:span:scope:isSelected:hasSelection:)`` puts
    /// the selection wrap after the date wrap for.
    ///
    /// A second tap on the already-selected line is still an interaction even
    /// though it does not change `selectedTrainID`. The map surface normally
    /// drives auto-focus from that state change, so answer this no-change case
    /// here, where the tap itself is still visible. At this point the selected
    /// line is already drawn and `selectionRegion` is available; a newly
    /// selected line continues through the surface so it cannot accidentally
    /// frame the previous selection's region.
    private func pick(_ train: Train) {
        let reselectsCurrentTrain = itineraries.selectedTrainID == train.id
        itineraries.selectedTrainID = train.id
        if reselectsCurrentTrain, autoFocusZoom {
            controller.fitToSelection()
        }
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
        playback.start(
            trains: trains, rides: riddenRoutes.rides, reducedMotion: reduceMotion,
            restoringSelection: itineraries.selectedTrainID)
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
        playback.isActive || playback.phase == .ended
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
                        trains: playbackScope, rides: riddenRoutes.rides)
                    sheet = .videoOptions
                }
            )
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
    private var lines: [RailNetworkStore.DrawnLine] { store.lines }
}

/// A workspace destination's page, mounted rather than composed.
///
/// Deliberately NOT generic, and that is the whole of it: a generic wrapper
/// would still name the page in its own type, and it is the type that costs.
/// The closure is what defers the page, and `AnyView` is what stops the tab
/// bar's type from naming it. See `RailWorkspaceView.page(_:stage:headerExpansion:content:)`
/// for the crash both halves answer.
private struct WorkspacePage: View {
    let build: () -> AnyView

    var body: some View { build() }
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
