import Foundation

/// Every surface the workspace puts over, or beside, the map.
///
/// Adding a case forces a host decision in `WorkspaceSurfacePolicy.host`
/// (the switch is exhaustive) and a row in the policy tests (they iterate
/// `allCases`).
public enum WorkspaceSurfaceKind: CaseIterable, Equatable, Sendable {
    /// The trip card (`WorkspaceSheet.detail`).
    case tripCard
    /// The full trip details opened from the trip card.
    case tripDetails
    case stationCard
    case lineCard
    /// The chooser shown when a tap lands on several overlapping trips.
    case overlappingTripsChooser
    /// The chooser shown when a tap lands on several overlapping lines.
    case lineChooser
    case tripNoteRead
    case tripNoteForm
    case groupPicker
    /// The share composer; a full-window cover on purpose.
    case shareComposer
    /// The delete confirmation; a dialog on purpose.
    case deleteConfirmation
    /// The journey editor, which already replaces the panel's content.
    case journeyEditor
}

/// Where a surface is presented.
public enum WorkspaceSurfaceHost: Equatable, Sendable {
    /// Inside the docked or resident workspace panel, filling it.
    case panel
    /// A system sheet over the window.
    case systemSheet
    /// A full-window cover.
    case fullWindowCover
    /// A system dialog or confirmation dialog.
    case dialog
}

/// What a map tap landed on.
public enum MapTapKind: CaseIterable, Equatable, Sendable {
    case station, lines, trips, empty
}

/// What the workspace does with a map tap while a card may be open.
public enum MapTapCardAnswer: Equatable, Sendable {
    /// The tap is ignored.
    case blocked
    /// The tap does what it normally does.
    case proceed
    /// Only the selection is cleared.
    case clearSelection
    /// The selection is cleared and the panel card closes.
    case clearSelectionAndCloseCard
}

/// How a surface opened from another surface is hosted.
public struct WorkspaceNestedSurface: Equatable, Sendable {
    public var host: WorkspaceSurfaceHost
    /// True when the child replaces the parent inside the panel, so the
    /// child offers a back step to the parent.
    public var hasBackStep: Bool
    /// True when the parent is torn down before the child opens (the journey
    /// editor), so there is nothing to step back to.
    public var dismissesParent: Bool

    public init(host: WorkspaceSurfaceHost, hasBackStep: Bool, dismissesParent: Bool = false) {
        self.host = host
        self.hasBackStep = hasBackStep
        self.dismissesParent = dismissesParent
    }
}

/// Pure decision of which host presents each workspace surface.
///
/// Docked layout (`.sideBySide`: iPad, wide windows, and Mac Catalyst, which
/// is always `.sideBySide`) hosts map-covering popups inside the panel. The
/// phone's compact layout keeps system sheets. The hinged/foldable layout
/// (`hasHingedDisplay` in the app) is not a `WorkspaceLayoutMode`: its mode
/// still comes from width and can be `.sideBySide`, so every entry point takes
/// `isHinged` and a hinged layout keeps system sheets whatever the mode says.
public enum WorkspaceSurfacePolicy {
    public static func host(
        for kind: WorkspaceSurfaceKind, mode: WorkspaceLayoutMode, isHinged: Bool
    ) -> WorkspaceSurfaceHost {
        switch kind {
        case .shareComposer:
            return .fullWindowCover
        case .deleteConfirmation:
            return .dialog
        case .journeyEditor:
            // Replaces the panel's tab content in every layout today.
            return .panel
        case .tripCard, .tripDetails, .stationCard, .lineCard,
            .overlappingTripsChooser, .lineChooser, .tripNoteRead, .tripNoteForm,
            .groupPicker:
            if isHinged { return .systemSheet }
            switch mode {
            case .sideBySide: return .panel
            case .compactOverlay: return .systemSheet
            }
        }
    }

    /// The four tabs are hidden while a panel-hosted surface fills the panel.
    public static func hidesTabsWhilePresented(
        kind: WorkspaceSurfaceKind, mode: WorkspaceLayoutMode, isHinged: Bool
    ) -> Bool {
        host(for: kind, mode: mode, isHinged: isHinged) == .panel
    }

    /// In the docked layout the panel keeps its width and position whatever it
    /// shows, so the part of the map it covers never changes. The compact and
    /// hinged layouts' sheets change detent, and with it the obstruction.
    public static func keepsMapObstructionConstant(
        mode: WorkspaceLayoutMode, isHinged: Bool
    ) -> Bool {
        if isHinged { return false }
        switch mode {
        case .sideBySide: return true
        case .compactOverlay: return false
        }
    }

    /// Hosting for `child` opened from `parent` (details from the trip card,
    /// the line card from the station card). Panel to panel stays in the panel
    /// with a back step; anything else follows the child's own host. The
    /// journey editor never nests: the app dismisses the parent first, so it
    /// has no back step and reports `dismissesParent`.
    public static func nestedHost(
        child: WorkspaceSurfaceKind, from parent: WorkspaceSurfaceKind,
        mode: WorkspaceLayoutMode, isHinged: Bool
    ) -> WorkspaceNestedSurface {
        let childHost = host(for: child, mode: mode, isHinged: isHinged)
        if child == .journeyEditor {
            return WorkspaceNestedSurface(host: childHost, hasBackStep: false, dismissesParent: true)
        }
        let stays = childHost == .panel
            && host(for: parent, mode: mode, isHinged: isHinged) == .panel
        return WorkspaceNestedSurface(host: childHost, hasBackStep: stays)
    }

    /// Whether a map tap goes through while a card is open. A card in the
    /// docked panel does not cover the map, so the map keeps answering taps:
    /// a station, line or trip swaps the card, an empty tap closes it. A card
    /// in a system sheet keeps today's rules. The journey editor always owns
    /// station and line taps. A panel card with a nested surface up (details,
    /// a note draft, a group save) blocks every tap, as Esc stands down there,
    /// and an open editor also keeps an empty tap from closing the card.
    /// Decision (final): over a panel card a DOUBLE tap near a station or line
    /// only zooms. The single tap still swaps the card (the back step returns
    /// to the trip), but after the double-tap window, banked like the empty
    /// clear (`MapTapPolicy/defersAnswer(_:cardHost:)`). Trip taps stay
    /// immediate. Sheet hosts and no card answer at once.
    public static func mapTapAnswer(
        _ tap: MapTapKind, cardHost: WorkspaceSurfaceHost?, leaseHeld: Bool,
        linePreviewShown: Bool, editorOpen: Bool, nestedSurfaceUp: Bool = false
    ) -> MapTapCardAnswer {
        if editorOpen, tap == .station || tap == .lines { return .blocked }
        if cardHost == .panel {
            if nestedSurfaceUp { return .blocked }
            if tap == .empty { return editorOpen ? .blocked : .clearSelectionAndCloseCard }
            return .proceed
        }
        switch tap {
        case .station:
            return leaseHeld ? .blocked : .proceed
        case .lines:
            return leaseHeld || linePreviewShown ? .blocked : .proceed
        case .trips:
            return linePreviewShown ? .blocked : .proceed
        case .empty:
            return linePreviewShown || leaseHeld ? .blocked : .clearSelection
        }
    }
}
