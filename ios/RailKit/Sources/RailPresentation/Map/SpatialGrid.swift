import Foundation

/// A uniform grid over points, so a pass that only needs what is on screen
/// reads the visible rect's cells instead of scanning every point.
///
/// Built once per resident set (stations, trip station records). A query
/// returns the indices of the points inside a closed rect, ascending, which is
/// the order a full scan would have visited them in.
public struct SpatialGrid: Sendable {
    public struct Rect: Equatable, Sendable {
        public var minX: Double
        public var minY: Double
        public var maxX: Double
        public var maxY: Double

        public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
            self.minX = minX
            self.minY = minY
            self.maxX = maxX
            self.maxY = maxY
        }

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.init(minX: x, minY: y, maxX: x + width, maxY: y + height)
        }

        public func inset(by margin: Double) -> Rect {
            Rect(minX: minX - margin, minY: minY - margin,
                 maxX: maxX + margin, maxY: maxY + margin)
        }
    }

    private struct Cell: Hashable, Sendable {
        var x: Int
        var y: Int
    }

    public let cellSize: Double
    private let xs: [Double]
    private let ys: [Double]
    private var cells: [Cell: [Int]] = [:]

    public var count: Int { xs.count }

    public init(cellSize: Double, xs: [Double], ys: [Double]) {
        precondition(xs.count == ys.count, "one y per x")
        self.cellSize = max(cellSize, .leastNormalMagnitude)
        self.xs = xs
        self.ys = ys
        for index in xs.indices {
            cells[cell(x: xs[index], y: ys[index]), default: []].append(index)
        }
    }

    private func cell(x: Double, y: Double) -> Cell {
        Cell(x: Int((x / cellSize).rounded(.down)), y: Int((y / cellSize).rounded(.down)))
    }

    /// Indices of the points with `minX <= x <= maxX` and `minY <= y <= maxY`,
    /// ascending.
    public func indices(in rect: Rect) -> [Int] {
        guard rect.minX <= rect.maxX, rect.minY <= rect.maxY, !xs.isEmpty else { return [] }
        let low = cell(x: rect.minX, y: rect.minY)
        let high = cell(x: rect.maxX, y: rect.maxY)
        var found: [Int] = []
        func collect(_ members: [Int]) {
            for index in members
            where xs[index] >= rect.minX && xs[index] <= rect.maxX
                && ys[index] >= rect.minY && ys[index] <= rect.maxY {
                found.append(index)
            }
        }
        let span = (high.x - low.x + 1).multipliedReportingOverflow(by: high.y - low.y + 1)
        if span.overflow || span.partialValue > cells.count {
            // A rect covering more cells than exist: walk the occupied cells.
            for (key, members) in cells
            where key.x >= low.x && key.x <= high.x && key.y >= low.y && key.y <= high.y {
                collect(members)
            }
        } else {
            for cx in low.x...high.x {
                for cy in low.y...high.y {
                    if let members = cells[Cell(x: cx, y: cy)] { collect(members) }
                }
            }
        }
        found.sort()
        return found
    }
}

/// Whether a camera-moving rebuild owes the settled full marker pass.
///
/// A rebuild during a gesture installs overlays but does not run the full
/// marker pass (label election over every resident station and trip record,
/// annotation reconcile, restyle). That pass is owed and runs once when the
/// camera settles; any full pass that runs clears the debt.
public struct MarkerPassDebt: Equatable, Sendable {
    public enum RebuildPass: Equatable, Sendable {
        /// Election, annotation reconcile, restyle.
        case full
        /// Install overlays only; the full pass waits for the camera to settle.
        case deferred
    }

    public private(set) var isOwed = false

    public init() {}

    /// The marker work a rebuild does. Only the mid-pinch level swap defers it;
    /// a moving load-ahead extension runs the full pass so the newly shown
    /// area has stations and dots. The second rule is whether it may reset
    /// the moving label pass's cost budget.
    public static func pass(deferMarkers: Bool) -> RebuildPass {
        deferMarkers ? .deferred : .full
    }

    public static func resetsMovingBudget(duringGesture: Bool) -> Bool { !duringGesture }

    public mutating func noteDeferred() { isOwed = true }
    public mutating func noteFullPassRan() { isOwed = false }
}

/// The one-turn hand-off that pays a camera settle's marker debt.
///
/// A settled camera rebuild installs overlays and leaves the marker pass and
/// label redraw owed, so a display-link frame can fire between the two. The
/// owed pass is scheduled for the next main run-loop turn under a token; a
/// newer schedule, a cancel or a camera move invalidates the token, and the
/// turn that finds its token stale does nothing, so a stale pass can never
/// run over newer state. The debt itself (``MarkerPassDebt``) stays owed
/// until a full pass runs, so a cancelled turn is paid by the next settle.
public struct MarkerSettleTurn: Equatable, Sendable {
    public private(set) var pendingToken: Int?
    private var nextToken = 0

    public init() {}

    /// True while a turn is scheduled and not yet claimed or cancelled.
    public var isPending: Bool { pendingToken != nil }

    /// Supersedes any scheduled turn and returns the new turn's token.
    public mutating func schedule() -> Int {
        nextToken += 1
        pendingToken = nextToken
        return nextToken
    }

    /// Invalidates the scheduled turn, if any.
    public mutating func cancel() { pendingToken = nil }

    /// Called by the turn when it runs: true exactly once, for the newest
    /// token that has not been cancelled.
    public mutating func claim(_ token: Int) -> Bool {
        guard pendingToken == token else { return false }
        pendingToken = nil
        return true
    }

    /// Whether the claimed turn should run the full pass now: only while the
    /// debt is still owed and the camera is not moving again.
    public static func runsFullPass(debtOwed: Bool, cameraMoving: Bool) -> Bool {
        debtOwed && !cameraMoving
    }
}
