import Foundation

/// What the map does in response to one update's set of changed inputs.
/// A selection change used to fold into the full rebuild; it is its own plan
/// now, because it changes paint, one casing overlay, stacking and the
/// markers — never geometry.
public enum MapUpdatePlan: Equatable, Sendable {
    case none, paintOnly, selectionOnly, rebuild
}

/// The scalar outcomes of one update's diff, in the same spirit as
/// `MapRebuildPolicy` — the coordinator computes the flags, this decides.
public struct MapDrawChanges: Equatable, Sendable {
    public var linesChanged: Bool
    public var stationsChanged: Bool
    public var ridesChanged: Bool
    public var selectionChanged: Bool
    public var visibilityChanged: Bool
    public var indexesChanged: Bool
    public var displayChanged: Bool
    /// The display change touched only ride paint (width/opacity tokens), not what is drawn.
    public var routePaintOnly: Bool
    public var dateChanged: Bool
    public var namingChanged: Bool
    public var showsNetwork: Bool
    public var hasRides: Bool
    public var hasContinuousLines: Bool

    public init(
        linesChanged: Bool,
        stationsChanged: Bool,
        ridesChanged: Bool,
        selectionChanged: Bool,
        visibilityChanged: Bool,
        indexesChanged: Bool,
        displayChanged: Bool,
        routePaintOnly: Bool,
        dateChanged: Bool,
        namingChanged: Bool,
        showsNetwork: Bool,
        hasRides: Bool,
        hasContinuousLines: Bool
    ) {
        self.linesChanged = linesChanged
        self.stationsChanged = stationsChanged
        self.ridesChanged = ridesChanged
        self.selectionChanged = selectionChanged
        self.visibilityChanged = visibilityChanged
        self.indexesChanged = indexesChanged
        self.displayChanged = displayChanged
        self.routePaintOnly = routePaintOnly
        self.dateChanged = dateChanged
        self.namingChanged = namingChanged
        self.showsNetwork = showsNetwork
        self.hasRides = hasRides
        self.hasContinuousLines = hasContinuousLines
    }

    public var visibleNetworkChanged: Bool { showsNetwork && (linesChanged || stationsChanged) }
    public var strokeableNetworkChanged: Bool {
        (linesChanged || stationsChanged) && hasRides && hasContinuousLines
    }

    /// Everything that needs a full geometry rebuild — selection excluded.
    public var needsRebuild: Bool {
        visibleNetworkChanged
            || strokeableNetworkChanged
            || ridesChanged
            || visibilityChanged
            || indexesChanged
            || (displayChanged && !routePaintOnly)
            || dateChanged
            || namingChanged
    }

    public var plan: MapUpdatePlan {
        if needsRebuild { return .rebuild }
        if selectionChanged { return .selectionOnly }
        if routePaintOnly && displayChanged { return .paintOnly }
        return .none
    }
}
