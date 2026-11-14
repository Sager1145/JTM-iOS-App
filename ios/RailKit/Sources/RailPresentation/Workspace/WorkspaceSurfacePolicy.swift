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

/// How a surface opened from another surface is hosted.
public struct WorkspaceNestedSurface: Equatable, Sendable {
    public var host: WorkspaceSurfaceHost
    /// True when the child replaces the parent inside the panel, so the
    /// child offers a back step to the parent.
    public var hasBackStep: Bool

    public init(host: WorkspaceSurfaceHost, hasBackStep: Bool) {
        self.host = host
        self.hasBackStep = hasBackStep
    }
}

/// Pure decision of which host presents each workspace surface.
///
/// Docked layout (`.sideBySide`: iPad, wide windows, and Mac Catalyst, which
/// is always `.sideBySide`) hosts map-covering popups inside the panel. The
/// phone's compact layout keeps system sheets. The hinged/foldable layout is
/// not a separate `WorkspaceLayoutMode` and so stays with its mode's rules.
public enum WorkspaceSurfacePolicy {
    public static func host(
        for kind: WorkspaceSurfaceKind, mode: WorkspaceLayoutMode
    ) -> WorkspaceSurfaceHost {
        switch kind {
        case .shareComposer:
            return .fullWindowCover
        case .deleteConfirmation:
            return .dialog
        case .journeyEditor:
            // Replaces the panel's tab content in both layouts today.
            return .panel
        case .tripCard, .tripDetails, .stationCard, .lineCard,
            .overlappingTripsChooser, .lineChooser, .tripNoteRead, .tripNoteForm,
            .groupPicker:
            switch mode {
            case .sideBySide: return .panel
            case .compactOverlay: return .systemSheet
            }
        }
    }

    /// The four tabs are hidden while a panel-hosted surface fills the panel.
    public static func hidesTabsWhilePresented(
        kind: WorkspaceSurfaceKind, mode: WorkspaceLayoutMode
    ) -> Bool {
        host(for: kind, mode: mode) == .panel
    }

    /// In the docked layout the panel keeps its width and position whatever it
    /// shows, so the part of the map it covers never changes. The compact
    /// layout's sheets change detent, and with it the obstruction.
    public static func keepsMapObstructionConstant(mode: WorkspaceLayoutMode) -> Bool {
        switch mode {
        case .sideBySide: true
        case .compactOverlay: false
        }
    }

    /// Hosting for `child` opened from `parent` (details from the trip card,
    /// the line card from the station card). Panel to panel stays in the panel
    /// with a back step; anything else follows the child's own host.
    public static func nestedHost(
        child: WorkspaceSurfaceKind, from parent: WorkspaceSurfaceKind,
        mode: WorkspaceLayoutMode
    ) -> WorkspaceNestedSurface {
        let childHost = host(for: child, mode: mode)
        let stays = childHost == .panel && host(for: parent, mode: mode) == .panel
        return WorkspaceNestedSurface(host: childHost, hasBackStep: stays)
    }
}
