import RailPresentation
import SwiftUI

// =============================================================================
//  The bottom chrome — JRM_FLIGHTY_UI_REFACTOR_SPEC.md §9.5.6
// =============================================================================
//
//  One resident system Sheet carries the whole interface. A system `TabView`
//  lives inside it, so SwiftUI owns the Liquid Glass tab bar, selection lens,
//  Search separation, Dynamic Type and accessibility behavior. The Sheet owns
//  inset margins, corner interpolation, rubber banding, predicted-endpoint
//  snapping and the iOS 26 morph from inset card to edge-to-edge.
//
//      Bottom Sheet
//        ↓ shrink
//      Compact Bottom Bar
//
//  The bar is therefore not hand drawn. At the smallest detent the tab bar is
//  remains visible with the ordinary title bar; at Medium and Large its selected
//  page grows above it.

/// §2.2 (revised) — three primary destinations and semantic Search.
///
/// Not Journeys / Network / Passport any more. The railway network stopped
/// being a destination when the map became the root layer that all three
/// share: a "network" tab would have been a tab whose whole content is a set
/// of switches for the map already on screen behind it. Its package status and
/// diagnostics moved to Settings, where the rest of the app's plumbing lives.
///
/// What is left are the three questions a journey log actually answers:
/// what is coming, what does it all add up to, and what have I got.
enum PrimaryTab: String, CaseIterable, Identifiable {
    /// What is coming. Dated today or later, soonest first.
    case upcoming
    /// What it adds up to — §5.3's Passport, by its plainer name.
    case stats
    /// Everything on record, by date.
    case all
    /// System Search, also the entry point for adding a journey.
    case search

    var id: String { rawValue }

    var headerActionCount: Int {
        switch self {
        case .upcoming: 3
        case .stats, .all: 4
        case .search: 2
        }
    }

    /// The short name shown by the system tab bar.
    ///
    /// A tab item and a page heading have different space budgets. Reusing
    /// `nav.allJourneys` and `sec.search` here made the system compress some
    /// languages but not others (for example, 「すべての行程」 versus 「統計」).
    /// These iOS-only labels keep all four languages on the same one-concept,
    /// one-line footing while the panel header continues to use the complete
    /// shared-catalog wording.
    var tabLocalizationKey: String {
        switch self {
        case .upcoming: "ios.tab.upcoming"
        case .stats: "ios.tab.stats"
        case .all: "ios.tab.all"
        case .search: "ios.tab.search"
        }
    }

    var tabFallbackName: String {
        switch self {
        case .upcoming: "Upcoming"
        case .stats: "Stats"
        case .all: "All"
        case .search: "Search"
        }
    }

    var systemImage: String {
        switch self {
        case .upcoming: "calendar"
        case .stats: "chart.bar.xaxis"
        case .all: "tram"
        case .search: "magnifyingglass"
        }
    }
}

// MARK: - how tall each stop is

/// The three detents, for the window the sheet is in.
///
/// Medium is arithmetic, Large is the system detent, and Compact reserves the
/// system tab bar's standard vertical region plus one reduced title row. Full
/// panel content belongs to the two expanded stops; keeping only that short
/// identifying row at the smallest stop makes it read as a collapsed card
/// rather than either a bare bar or clipped content.
///
/// `medium` is a fraction of the SCREEN, not a `PresentationDetent.fraction`.
/// §9.5.5: `.fraction()` measures against the space a sheet is allowed, which
/// is not the same quantity and drifts between devices. A design that says
/// "about half the screen" means half the screen.
struct BottomChromeMetrics: Equatable {
    /// The window's full height, from the root `GeometryReader`.
    var screenHeight: CGFloat

    /// The compact stop's own height at the reader's text size.
    ///
    /// The tab bar's band is a system metric and does not move; the title row
    /// on top of it is TEXT, and at an accessibility size it is more than
    /// twice as tall. A single constant is right at one text size and clips at
    /// the others — which is the whole argument the ride card's own compact
    /// measurement used to make, before the resident sheet replaced it with
    /// `136`. The caller supplies this from a `@ScaledMetric`; see
    /// `RailWorkspaceView.chromeMetrics(in:)`.
    var compactRow: CGFloat = compactFallback

    /// Whether the reader is at one of the five accessibility text sizes.
    ///
    /// It changes the SET of stops rather than the content: see ``detents``.
    var isAccessibilitySize = false

    /// The system tab bar, the fixed title bar and their breathing room, at
    /// the standard text sizes. The Sheet adds the device's bottom safe area
    /// to a height detent itself.
    static let compactFallback: CGFloat = 168
    /// How much of ``compactFallback`` is the tab bar's own band — the part
    /// that does not scale with text. The rest is the title row.
    static let compactTabBand: CGFloat = 88
    /// §9.5.2's Medium. The `+ 8` is §9.5.5's: it keeps the stop clear of the
    /// rounding the system applies when a detent lands within a point or two
    /// of another one.
    static let mediumFraction: CGFloat = 0.52
    /// Below this the sheet reads as a bar rather than a card, and the map
    /// gains nothing for the loss.
    static let minimumCompact: CGFloat = 120

    /// One line of the header's subtitle, at the reader's text size.
    ///
    /// Asked of the font rather than written down, for the reason
    /// `PanelHeader`'s own note gives — a footnote line is 18 points at the
    /// standard size and a constant that says 16 clips its descenders. It is
    /// HERE rather than there because two things now need the same number: the
    /// header reserving the slot, and the compact detent that has to be tall
    /// enough to hold the ordinary title bar's visible subtitle rows.
    static var subtitleRow: CGFloat {
        AppTypographyPolicy.preferredFont(forTextStyle: .footnote).lineHeight
    }

    /// The legibility floor for the shared title fit and subtitle labels.
    /// Titles use one fit for every tab; subtitles fit their own summary text.
    static let smallestLegibleScale: CGFloat = 0.5

    var compact: CGFloat {
        let wanted = max(compactRow, Self.minimumCompact)
        // At an accessibility size there IS no medium stop (see `detents`), so
        // the clamp that keeps the two far enough apart to be different
        // gestures has nothing left to keep apart — and applying it anyway is
        // what would clip the title row it was just measured to fit. The map
        // still gets its share: 60 % of the window is the ceiling.
        guard !isAccessibilitySize else { return min(wanted, screenHeight * 0.6) }
        // Never so tall that compact and medium stop being different gestures.
        return min(wanted, max(Self.minimumCompact, medium * 0.7))
    }

    /// §9.5.2's Medium.
    ///
    /// Still computed at an accessibility size even though it is not a stop
    /// there: the map's controls are lifted by it (`mapLayout`'s `lift`) and
    /// the header's morph is measured against it, and both of those want the
    /// same reference height whether or not the sheet can rest at it.
    var medium: CGFloat {
        max(Self.minimumCompact + 1, screenHeight * Self.mediumFraction + 8)
    }

    var compactDetent: PresentationDetent { .height(compact) }
    var mediumDetent: PresentationDetent { .height(medium) }

    /// `.large` rather than a fourth measured number: §9.5.6 asks Expanded to
    /// be *really* full, and `.large` is the only detent the system morphs to
    /// edge-to-edge — dropping the side margins and the corner radius on the
    /// way, which is exactly §9.5.2's Expanded row and not something a
    /// `.height()` detent does.
    var detents: Set<PresentationDetent> {
        // Two stops at an accessibility text size, not three.
        //
        // AppTypographyPolicy permanently limits every app surface to
        // xSmall...xLarge by explicit product requirement. This alternative
        // detent rule remains useful for independently hosted layouts, but
        // must never replace or relax that app-wide hard limit.
        //
        // What actually does not fit at those sizes is the MIDDLE stop: a
        // half-height panel holding a 34-point-equivalent title and one row is
        // a panel showing a title and nothing else. So the half goes and the
        // two useful ends stay — collapsed, where the map is the point, and
        // full, where the reading is.
        isAccessibilitySize
            ? [compactDetent, .large]
            : [compactDetent, mediumDetent, .large]
    }

    /// The stops this window actually offers, smallest first.
    var stages: [SheetStage] {
        isAccessibilitySize ? [.compact, .expanded] : [.compact, .medium, .expanded]
    }

    /// Which stop a live height is nearest.
    ///
    /// §9.5.5 point 6: the bound `PresentationDetent` only changes once the
    /// sheet has settled, so content that keys off it changes a beat after the
    /// finger. Reading the real height every frame and picking the nearest stop
    /// is what lets the title, the rows and the map controls start moving while
    /// the drag is still happening.
    func stage(nearest height: CGFloat) -> SheetStage {
        // Only the stops this window offers. At an accessibility size medium
        // is not one of them, and answering with a stage the sheet cannot rest
        // at would put the content into a form the panel never reaches.
        let targets = stages.map { ($0, self.height(of: $0)) }
        return targets.min { abs($0.1 - height) < abs($1.1 - height) }?.0
            ?? stages.first ?? .compact
    }

    /// A stop's height. `.expanded` is the window, which is what `.large`
    /// resolves to once the system has dropped the sheet's side margins.
    func height(of stage: SheetStage) -> CGFloat {
        switch stage {
        case .compact: compact
        case .medium: medium
        case .expanded: screenHeight
        }
    }

    /// The nearest stop this window actually offers to a requested one — so a
    /// reader who asks for Half at an accessibility size gets Full rather than
    /// a detent SwiftUI silently substitutes.
    func available(_ stage: SheetStage) -> SheetStage {
        guard !stages.contains(stage) else { return stage }
        return stages.min {
            abs(height(of: $0) - height(of: stage))
                < abs(height(of: $1) - height(of: stage))
        } ?? .compact
    }

    /// The stop this height IS, if it is resting on one.
    ///
    /// The sheet reports its stops exactly: a `.height(136)` detent measures
    /// 136 and `.large` measures the window. A drag reports whatever the finger
    /// is holding, and lands on one of those numbers only by accident. So
    /// "this height is a stop's height" is how the panel tells the SYSTEM's
    /// settle — the spring that runs after the finger lifts, and the move an
    /// accessibility action asks for — from the finger itself. Both of those
    /// arrive as one discontinuous jump rather than as a stream, because UIKit
    /// animates the sheet's frame but lays its content out once, at the
    /// destination; see `ResidentBottomSheetModifier.settle(reporting:)`.
    ///
    /// The tolerance is a rounding allowance and not a window: the system
    /// quantises a detent to the device's point grid, which puts Medium's
    /// 412.57 on screen as 412.67 on a 3× phone, and `settle(reporting:)`
    /// rounds that to a whole point before asking. Half a point covered
    /// neither of those on its own — the two together can carry a genuine stop
    /// 0.67 points away from its own detent, and a stop that is not recognised
    /// is a settle that is not animated: the header would take its new size in
    /// one frame while the panel was still a third of a second from arriving.
    /// Whether that happened depended on the fractional part of the window's
    /// height, so it was a device-by-device coin toss. One point covers both
    /// allowances and is still two orders of magnitude short of the 276 points
    /// between the nearest pair of stops.
    func settledStage(at height: CGFloat) -> SheetStage? {
        stages.first { abs(self.height(of: $0) - height) <= 1 }
    }

    /// A continuous compact-to-medium value for chrome that must follow the
    /// reader's finger rather than change when the nearest detent changes.
    ///
    /// Medium and Expanded intentionally share `1`: the expanded title is
    /// already established at the half stop, so dragging farther should move
    /// the sheet without making its hierarchy grow a second time.
    func headerExpansionProgress(for height: CGFloat) -> CGFloat {
        let distance = medium - compact
        guard distance > 0 else { return 1 }
        return min(max((height - compact) / distance, 0), 1)
    }
}

// MARK: - measuring

/// The sheet's live height while it is being dragged.
struct SheetLiveHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The map control rail's drawn height.
///
/// Measured because it is not a constant: `MapControlBar` includes an
/// `MKCompassButton` only while the map has a heading, which is 52 pt of
/// difference, and the rail's contents have changed twice already. The one
/// reader is `RailWorkspaceView.mapLayout`, which needs the rail's TOP edge to
/// know when the constant sheet gap has pushed it into the status bar.
struct RailControlHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - the panel header

/// A fixed-height title bar. A visible subtitle selects the smaller title;
/// otherwise the large title occupies the shared text area on its own.
struct PanelHeader<Actions: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title2) private var titleSize = WorkspaceMenuMetrics.titleSize
    @ScaledMetric(relativeTo: .largeTitle) private var largeTitleSize = WorkspaceMenuMetrics.largeTitleSize
    @ScaledMetric(relativeTo: .title2) private var titleRow = WorkspaceMenuMetrics.titleRowHeight

    var title: String
    var tabHeadings: [WorkspacePanelHeading]
    var subtitle: String?
    @ViewBuilder var actions: Actions

    private var visibleSubtitle: String? {
        guard let subtitle,
              !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return subtitle
    }

    var body: some View {
        GeometryReader { geometry in
            let sharedTitleSize = fittedTitleSize(in: geometry.size.width)
            HStack(alignment: .center, spacing: WorkspaceMenuMetrics.titleActionSpacing) {
                titleBlock(size: sharedTitleSize)
                Spacer(minLength: 0)
                actionStrip
            }
        }
        .frame(height: WorkspaceMenuMetrics.headerContentHeight(
            titleRow: titleRow, stacked: false, drawsSubtitle: true))
        .padding(.horizontal, WorkspaceMenuMetrics.horizontalInset)
        .padding(.top, WorkspaceMenuMetrics.topInset)
        .padding(.bottom, WorkspaceMenuMetrics.bottomInset)
    }

    /// Each display mode shares one font fit, using each tab's actual action width.
    private func fittedTitleSize(in width: CGFloat) -> CGFloat {
        let hasSubtitle = visibleSubtitle != nil
        let size = hasSubtitle ? titleSize : largeTitleSize
        let font = UIFont.systemFont(ofSize: size, weight: .bold)
        let scale = tabHeadings.filter { $0.hasSubtitle == hasSubtitle }
            .reduce(CGFloat(1)) { scale, heading in
                let actions = CGFloat(heading.actionCount) * WorkspaceMenuMetrics.touchSide
                    + CGFloat(max(0, heading.actionCount - 1)) * WorkspaceMenuMetrics.actionSpacing
                let available = max(0, width - actions - WorkspaceMenuMetrics.titleActionSpacing)
                let textWidth = (heading.title as NSString).size(withAttributes: [.font: font]).width
                return textWidth > 0 ? min(scale, available / textWidth) : scale
            }
        return size * max(BottomChromeMetrics.smallestLegibleScale, scale)
    }

    private func titleBlock(size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: WorkspaceMenuMetrics.subtitleSpacing) {
            Text(title)
                .font(.system(size: size, weight: .bold))
                .lineLimit(1)
                .fixedSize(horizontal: false, vertical: true)
                .frame(height: visibleSubtitle == nil
                    ? WorkspaceMenuMetrics.headerTextHeight(
                        titleRow: titleRow, stacked: false, drawsSubtitle: true)
                    : titleRow,
                    alignment: visibleSubtitle == nil ? .leading : .topLeading)
                .accessibilityIdentifier("panelHeader")
                .accessibilityAddTraits(.isHeader)
                .railSheetStageActions()
                .modifier(ReduceMotionUITestProbe(enabled: reduceMotion))
            if let visibleSubtitle {
                subtitleLabel(visibleSubtitle)
                    .frame(height: BottomChromeMetrics.subtitleRow,
                           alignment: .topLeading)
            }
        }
    }

    private func subtitleLabel(_ value: String) -> some View {
        Text(value)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(BottomChromeMetrics.smallestLegibleScale)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var actionStrip: some View {
        HStack(spacing: WorkspaceMenuMetrics.actionSpacing) { actions }
            .buttonStyle(RailPressStyle())
            .fixedSize(horizontal: true, vertical: false)
    }
}

/// A debug-only observation point for the UI test that is run after the
/// simulator's *system* Reduce Motion setting has been enabled. It never
/// changes application behavior and is absent from release accessibility.
private struct ReduceMotionUITestProbe: ViewModifier {
    var enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        #if DEBUG
        if ProcessInfo.processInfo.environment["RAILMAP_UI_TEST_REPORT_REDUCE_MOTION"] == "1" {
            content.accessibilityValue(Text(enabled ? "enabled" : "disabled"))
        } else {
            content
        }
        #else
        content
        #endif
    }
}

/// Applies only the surface behavior shared by the modern and compatibility
/// TabViews. SwiftUI still owns every pixel of the actual tab bar.
struct SystemSheetTabSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: SheetLiveHeightKey.self, value: proxy.size.height)
                }
            }
    }
}

extension View {
    /// Flighty's bottom row stays present while its card scrolls. On iOS 26+
    /// use the system policy that expresses that directly; older systems keep
    /// their normal persistent tab bar behavior.
    @ViewBuilder
    func railPersistentTabBar() -> some View {
        if #available(iOS 26.0, *) {
            tabBarMinimizeBehavior(.never)
        } else {
            self
        }
    }
}

/// §10.2: how a reader who cannot drag moves the sheet between its stops.
///
/// The Pull Bar is hidden by §9.5.6, and the thing that replaces it —
/// a drag on the header — responds to a DRAG. VoiceOver
/// and Switch Control perform neither, so without this the panel is stuck at
/// whichever stop it opened on for anyone not driving the app by touch, and
/// two of the three stages are simply unreachable.
///
/// A closure in the environment rather than the detent itself: the headers are
/// used by every destination and at every stop, and none of them should have
/// to know what a `PresentationDetent` is in order to offer the action.
/// Boxed rather than passed as a bare closure: an `EnvironmentKey`'s
/// `defaultValue` is a static, so under strict concurrency the value it holds
/// has to be `Sendable`, and a bare `(SheetStage) -> Void` is not.
struct RailSheetStageAction: Sendable, Equatable {
    /// Compared by identity. A struct of closures cannot be compared by
    /// value, and an environment value SwiftUI cannot compare is one it
    /// treats as CHANGED every time it is re-applied — which pushed a new
    /// environment into the hosted tab pages on every frame of a drag.
    private let id = UUID()
    let move: @MainActor @Sendable (SheetStage) -> Void
    /// Which stops this window actually offers. At an accessibility text size
    /// there is no half stop (see ``BottomChromeMetrics/detents``), and an
    /// accessibility action named "Half-height panel" that lands somewhere
    /// else is worse than one that is not offered.
    var stages: [SheetStage] = [.compact, .medium, .expanded]

    @MainActor
    func callAsFunction(_ stage: SheetStage) { move(stage) }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

struct RailSheetStageActionKey: EnvironmentKey {
    static let defaultValue: RailSheetStageAction? = nil
}

extension EnvironmentValues {
    var railSheetStageAction: RailSheetStageAction? {
        get { self[RailSheetStageActionKey.self] }
        set { self[RailSheetStageActionKey.self] = newValue }
    }
}

/// The three stops, as named accessibility actions on whichever header is on
/// screen.
///
/// On the HEADER rather than on the sheet as a whole, which is where an
/// earlier revision put them. A named action belongs to one accessibility
/// element, and making the sheet carry them meant making the sheet an element
/// — `children: .contain` — after which the actions were only offered while
/// that container itself held focus. VoiceOver lands on the panel title, so
/// that is where the actions have to be to be found. They cost no pixels and
/// do not put the grabber back.
private struct SheetStageActions: ViewModifier {
    @Environment(AppLocalization.self) private var localization
    @Environment(\.railSheetStageAction) private var move

    @ViewBuilder
    func body(content: Content) -> some View {
        if let move {
            // Branched rather than filtered, because the actions are announced
            // in the order they are attached and the half stop belongs BETWEEN
            // the other two. `accessibilityAction` takes no availability flag,
            // so an action that does not apply has to be absent rather than
            // disabled — which is the honest form anyway: at an accessibility
            // text size there is no half stop to go to (see
            // ``BottomChromeMetrics/detents``), and an action named
            // "Half-height panel" that lands on Full is a label that lies.
            if move.stages.contains(.medium) {
                content
                    .accessibilityAction(named: expand) { move(.expanded) }
                    .accessibilityAction(named: half) { move(.medium) }
                    .accessibilityAction(named: collapse) { move(.compact) }
            } else {
                content
                    .accessibilityAction(named: expand) { move(.expanded) }
                    .accessibilityAction(named: collapse) { move(.compact) }
            }
        } else {
            content
        }
    }

    private var expand: Text {
        Text(localization.text("ios.sheet.expand", fallback: "Expand panel"))
    }

    private var half: Text {
        Text(localization.text("ios.sheet.half", fallback: "Half-height panel"))
    }

    private var collapse: Text {
        Text(localization.text("ios.sheet.collapse", fallback: "Collapse panel"))
    }
}

extension View {
    /// Offers the resident sheet's three stops from this element. See
    /// ``SheetStageActions``.
    func railSheetStageActions() -> some View {
        modifier(SheetStageActions())
    }
}

private struct ResidentBottomSheetModifier<SheetContent: View>: ViewModifier {
    var metrics: BottomChromeMetrics
    var isSuspended: Bool
    @Binding var detent: PresentationDetent
    @Binding var liveHeight: CGFloat
    @ViewBuilder var sheetContent: () -> SheetContent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The stop the panel is currently drawn against, the one before it, and
    /// when that changed. See ``settle(reporting:)``.
    @State private var restingHeight: CGFloat = 0
    @State private var previousRestingHeight: CGFloat = 0
    @State private var restedAt = Date.distantPast

    /// A resident presentation still needs owned lifecycle state.
    ///
    /// A constant `true` binding asks SwiftUI to present again every time the
    /// host is rebuilt. That normally goes unnoticed, but an alert or menu on
    /// top makes the duplicate request observable as "already presenting" and
    /// can briefly give MapKit a zero-sized drawable during recovery. The
    /// sheet cannot be dismissed interactively, so this value changes only at
    /// the two real lifecycle edges below.
    @State private var isPresented = false

    // Keep the presenter and its list alive while a journey card takes over.
    // A positive height is a valid system detent. Its safe-area band sits
    // beneath the journey sheet while the menu content stays hidden.
    private var suspendedDetent: PresentationDetent { .height(1) }
    private var visibleDetent: Binding<PresentationDetent> {
        Binding(
            get: { isSuspended ? suspendedDetent : detent },
            set: { if !isSuspended && $0 != suspendedDetent { detent = $0 } })
    }

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented, onDismiss: restoreIfNeeded) {
                sheetContent()
                .opacity(isSuspended ? 0 : 1)
                .allowsHitTesting(!isSuspended)
                .accessibilityHidden(isSuspended)
                .railAnimation(RailMotion.spring, value: isSuspended, reduceMotion: reduceMotion)
                .presentationDetents(
                    isSuspended ? metrics.detents.union([suspendedDetent]) : metrics.detents,
                    selection: visibleDetent)
                // The system owns the sheet's Liquid Glass and detent changes.
                .railMenuPresentationBackground()
                .railMenuPresentationCornerRadius()
                // §9.5.6: no Pull Bar.
                //
                // `.scrolls` rather than `.resizes`, which is what decides who
                // gets a drag that starts on the list. Under `.resizes` the
                // sheet took it: at the half stop a flick down the journeys
                // collapsed the panel instead of moving the list, so the only
                // way to read past the first screenful was to expand the sheet
                // first. The content's length has nothing to do with the
                // panel's height, and now neither does the gesture — the list
                // scrolls at every stop, full or half.
                //
                // Resizing keeps a touch route because the header is not a
                // scroll view: a drag that starts on the title still moves the
                // sheet between its stops, the way a place card does. For
                // anyone not driving it by touch, see `SheetStageActions`.
                .presentationDragIndicator(.hidden)
                .presentationContentInteraction(.scrolls)
                // The map underneath stays live at the two stops where it is
                // still visible. §4.2: the map is the app's spatial context,
                // not a picture behind a modal.
                .presentationBackgroundInteraction(
                    .enabled(upThrough: metrics.isAccessibilitySize
                        ? metrics.compactDetent : metrics.mediumDetent))
                .interactiveDismissDisabled()
                .environment(
                    \.railSheetStageAction,
                    RailSheetStageAction(
                        move: { stage in
                            switch metrics.available(stage) {
                            case .compact: detent = metrics.compactDetent
                            case .medium: detent = metrics.mediumDetent
                            case .expanded: detent = .large
                            }
                        },
                        stages: metrics.stages))
                .onPreferenceChange(SheetLiveHeightKey.self) { height in
                    guard !isSuspended else { return }
                    settle(reporting: height.rounded())
                }
        }
        .onAppear {
            guard !isPresented else { return }
            isPresented = true
        }
    }

    /// One channel, two kinds of change — and size alone does not tell them
    /// apart.
    ///
    /// While the reader drags, the height arrives as a STREAM: UIKit resizes
    /// the sheet under the finger and lays its content out at every step, so
    /// the panel header, the journey card and the map's rail follow 1:1. None
    /// of that may be animated — a spring on top of a gesture is lag, which is
    /// the opposite of what §9.3 asks for.
    ///
    /// When the finger lifts, it arrives as a single JUMP to the stop the sheet
    /// is springing to. UIKit animates the frame but lays the content out once,
    /// at the destination, so every value keyed off this number was finished
    /// while the panel was still a third of a second from arriving: measured on
    /// an iPhone 17 Pro, a drag released at 266 pt reported 413 pt on the very
    /// next sample, and the large title took its 34-point size there and then.
    /// Recorded at 60 fps, the title reached full size while the panel was
    /// still a quarter of the way up. That is the case this animates, on
    /// §9.2's sheet spring, and it is what §9.5.6's "one persistent header" was
    /// missing — the title, the subtitle and the rail travel WITH the panel now
    /// instead of landing ahead of it.
    ///
    /// The discriminator is a jump that lands ON a stop. A stop the finger
    /// happens to drag through moves a few points per sample and is left alone;
    /// only the system arrives at one from far away.
    private func settle(reporting height: CGFloat) {
        let settledStage = metrics.settledStage(at: height)
        // Below the smallest stop is not a height the panel is AT.
        //
        // The sheet cannot rest under Docked, so a shorter measurement means
        // something is inset over its content rather than that the reader has
        // collapsed it. The keyboard is that something: tapping the search
        // field reported 413, then 107, then 478, then 413 again inside about
        // 150 ms on an iPhone 17 Pro. Redrawing the panel against those made
        // the destination's content unmount and remount — taking the text
        // field that had just been tapped with it, so the keyboard never
        // appeared and the tap did nothing.
        // The measured stop has been rounded, while a journey's
        // subtitle makes the compact detent fractional. Accept the same
        // rounding allowance as settledStage, then use the exact stop so the
        // header reaches its fully collapsed form.
        guard height >= metrics.compact || settledStage == .compact else { return }
        let height = settledStage == .compact ? metrics.compact : height
        let travelled = abs(height - liveHeight)
        guard travelled > 0.5 else { return }
        guard settledStage != nil else {
            // The finger. 1:1, unanimated, and it ends the window below: a
            // height that is not a stop means the sheet is being moved again,
            // so the stop it left is no longer something to be suspicious of.
            restedAt = .distantPast
            liveHeight = height
            return
        }
        guard !isEndOfDragBounce(to: height) else { return }
        previousRestingHeight = restingHeight
        restingHeight = height
        restedAt = .now
        if travelled > 8 {
            withAnimation(
                RailMotion.animation(RailMotion.gesture, reduceMotion: reduceMotion)
            ) {
                liveHeight = height
            }
        } else {
            liveHeight = height
        }
    }

    /// Whether this stop is the presentation controller bouncing off the one it
    /// just left, rather than a height the panel should redraw itself against.
    ///
    /// `presentationDetents(_:selection:)` writes the settled detent into its
    /// binding only AFTER the sheet has come to rest, so for the whole of a
    /// drag the bound value still names the stop the drag STARTED from — and at
    /// the moment the gesture ends, SwiftUI reconciles the presentation against
    /// that value. Measured on an iPhone 17 Pro: a flick released short of Half
    /// laid the sheet out at 413 pt, then at 136, then at 413 again, the three
    /// about 90 ms apart. Released into Full it was 778, 413, 778.
    ///
    /// The binding cannot be corrected out of it. Writing the settled stop back
    /// as soon as it is measured is already too late, and writing it EARLY —
    /// while the finger is still down — hands UIKit a detent to move to and
    /// ends the drag: with that tried, a slow pull out of Docked stopped
    /// following the finger the moment it crossed Half and threw the sheet to
    /// Full. Dropping the `selection:` binding does remove the bounce, and
    /// costs more than it saves: without it the sheet can no longer be moved on
    /// request (§10.2's accessibility actions, and the stop the app opens at),
    /// and UIKit's own expansion when a text field takes the keyboard stops
    /// being mediated — the search destination lost focus mid-tap.
    ///
    /// So the bounce is answered where it is visible instead. It is a
    /// recognisable shape — the stop the panel was resting on immediately
    /// BEFORE this one, arriving within a frame or two of settling — and
    /// nothing the reader can do produces that shape, because reaching the
    /// previous stop again takes a gesture, and a gesture reports heights that
    /// are not stops on the way, which is what clears the window. The panel's
    /// own contents therefore hold still through it; the sheet's frame still
    /// twitches, which is SwiftUI's to fix.
    private func isEndOfDragBounce(to height: CGFloat) -> Bool {
        height == previousRestingHeight
            && Date.now.timeIntervalSince(restedAt) < 0.15
    }

    private func restoreIfNeeded() {
        // `interactiveDismissDisabled` covers the reader. This is for scene or
        // framework-driven dismissal: wait until UIKit has completed the old
        // controller's dismissal before asking SwiftUI for its replacement.
        Task { @MainActor in
            await Task.yield()
            guard !isPresented else { return }
            isPresented = true
        }
    }
}

extension View {
    /// §9.5.6's resident sheet, in one place.
    ///
    /// The sheet owns a real presentation binding even though the reader can
    /// never dismiss it. This lets SwiftUI distinguish "already on screen"
    /// from "please present now" while another system surface is visible.
    func residentBottomSheet<SheetContent: View>(
        metrics: BottomChromeMetrics,
        isSuspended: Bool = false,
        detent: Binding<PresentationDetent>,
        liveHeight: Binding<CGFloat>,
        @ViewBuilder sheet: @escaping () -> SheetContent
    ) -> some View {
        modifier(ResidentBottomSheetModifier(
            metrics: metrics,
            isSuspended: isSuspended,
            detent: detent,
            liveHeight: liveHeight,
            sheetContent: sheet))
    }
}
