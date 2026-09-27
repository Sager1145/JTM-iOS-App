import Foundation
import RailCore

/// Which dated picture of the display network the map draws.
///
/// This is a draw filter. It does not change stored intervals, continuous
/// strokes, or the cross-day ride dash. `today` is the region's own civil
/// day, never the journey list's selected date.
public enum DisplayNetworkEra: String, Codable, Sendable, CaseIterable, Identifiable {
    case current
    case rideDate
    case historicalOverlay

    public var id: String { rawValue }

    /// Whether one decorated span is drawn.
    ///
    /// Undecorated geometry — nil id, nil bounds, `.current` — is always
    /// shown. Validity is half-open, the same rule as ``RouteGraph/RailValidity``:
    /// valid on `validFrom`, invalid on `validTo`.
    ///
    /// - Current: decorated geometry only when it is valid on `today` and its
    ///   kind is `.current` or `.relocatedNew`.
    /// - Ride date: valid on `rideDate` for every kind. `rideDate == nil`
    ///   (or not a plain `YYYY-MM-DD`) uses the Current predicate. A missing
    ///   date is never "any `validTo` is closed".
    /// - Overlay: the Current set, plus `.historical` and `.relocatedOld`,
    ///   plus stations that carry `validTo` or an overlay history id.
    public func shows(
        _ decoration: DisplayTemporalDecoration?,
        today: String,
        rideDate: String?,
        isStation: Bool = false
    ) -> Bool {
        guard let decoration, !decoration.isUndecorated else { return true }
        switch self {
        case .current:
            return Self.showsCurrent(decoration, today: today)
        case .rideDate:
            guard let rideDate, Dates.isValidDateString(rideDate) else {
                return Self.showsCurrent(decoration, today: today)
            }
            return RouteGraph.RailValidity.isValid(
                validFrom: decoration.validFrom, validTo: decoration.validTo, on: rideDate)
        case .historicalOverlay:
            if Self.showsCurrent(decoration, today: today) { return true }
            if decoration.kind == .historical || decoration.kind == .relocatedOld { return true }
            guard isStation else { return false }
            let closed = !(decoration.validTo?.isEmpty ?? true)
            let overlayID = decoration.isOverlayStation && !(decoration.historyId?.isEmpty ?? true)
            return closed || overlayID
        }
    }

    /// Network-stroke mark. Historical and relocated-old geometry may take
    /// the dotted historical mark. Relocated-new and in-place current do not.
    /// Cross-day rides stay on ``DisplayNetworkStrokeStyle/crossDayDash``.
    public static func strokeStyle(for kind: RouteGraph.TemporalKind) -> DisplayNetworkStrokeStyle {
        switch kind {
        case .historical, .relocatedOld: .historical
        case .current, .relocatedNew: .solid
        }
    }

    private static func showsCurrent(_ decoration: DisplayTemporalDecoration, today: String) -> Bool {
        guard decoration.kind == .current || decoration.kind == .relocatedNew else { return false }
        guard Dates.isValidDateString(today) else { return false }
        return RouteGraph.RailValidity.isValid(
            validFrom: decoration.validFrom, validTo: decoration.validTo, on: today)
    }
}

/// Dates and kind hung on one display part or station. Absent bounds and a
/// nil history id with `.current` are undecorated — the map draws them in
/// every era.
public struct DisplayTemporalDecoration: Sendable, Equatable {
    public var historyId: String?
    public var validFrom: String?
    public var validTo: String?
    public var kind: RouteGraph.TemporalKind
    /// A station that came from the history overlay, not a retirement stamp
    /// on a current-package platform.
    public var isOverlayStation: Bool

    public init(
        historyId: String? = nil,
        validFrom: String? = nil,
        validTo: String? = nil,
        kind: RouteGraph.TemporalKind = .current,
        isOverlayStation: Bool = false
    ) {
        self.historyId = historyId
        self.validFrom = validFrom
        self.validTo = validTo
        self.kind = kind
        self.isOverlayStation = isOverlayStation
    }

    public var isUndecorated: Bool {
        (historyId?.isEmpty ?? true)
            && (validFrom?.isEmpty ?? true)
            && (validTo?.isEmpty ?? true)
            && kind == .current
            && !isOverlayStation
    }
}

/// The two dotted rhythms on the map. Cross-day is `ride-xday`; historical
/// network strokes must not reuse it.
public struct DisplayNetworkDash: Equatable, Sendable {
    public var on: Double
    public var off: Double

    public init(on: Double, off: Double) {
        self.on = on
        self.off = off
    }

    /// `RailStyle.dashRatio` — the cross-day / withheld dash, in line widths.
    public static let crossDay = DisplayNetworkDash(on: 1.6, off: 1.4)
    /// Shorter on, longer off. Not the cross-day pair.
    public static let history = DisplayNetworkDash(on: 0.45, off: 1.35)
}

public enum DisplayNetworkStrokeStyle: String, Sendable, Equatable {
    case solid
    case crossDayDash
    case historical
}
