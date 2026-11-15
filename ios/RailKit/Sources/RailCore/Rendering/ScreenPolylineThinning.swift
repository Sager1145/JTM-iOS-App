import Foundation

/// Thins a drawn network polyline in screen space.
///
/// At app zoom 8-9 over Tokyo and Osaka a network build needs 69,800-77,800
/// vertices before this runs, and 80% of the drawn segments are shorter than
/// half a pixel: the stroke is already smooth, and the extra vertices only
/// spend the vertex budget. Dropping every interior vertex that lies closer
/// than ``stepPx`` to the previously KEPT vertex removes them without moving
/// the line by more than ``stepPx``: each dropped vertex is within that
/// distance of the kept vertex that starts the chord replacing it, and the
/// distance from a point to a segment never exceeds the distance to one of its
/// ends. Measuring against the last kept vertex (not the previous input one)
/// is what makes a run of tiny steps around a curve still keep a vertex for
/// every ``stepPx`` of travel.
///
/// Network (all-lines) polylines only. Ride polylines are never thinned.
public enum ScreenPolylineThinning {
    /// Smallest segment worth drawing, in screen points.
    public static let stepPx: Double = 0.5

    /// Indices of the vertices to keep, ascending. The first and last vertex
    /// are always kept, so every drawn piece (a chunk, a family window, a dash
    /// pattern run) keeps its ends. Deterministic and O(n).
    public static func keptIndices(
        x: [Double], y: [Double], stepPx: Double = ScreenPolylineThinning.stepPx
    ) -> [Int] {
        precondition(x.count == y.count, "x and y must have the same length")
        let count = x.count
        guard count > 2 else { return Array(0..<count) }
        let limit = stepPx * stepPx
        var kept = [0]
        kept.reserveCapacity(count)
        var lastX = x[0], lastY = y[0]
        for index in 1..<(count - 1) {
            let dx = x[index] - lastX, dy = y[index] - lastY
            if dx * dx + dy * dy >= limit {
                kept.append(index)
                lastX = x[index]
                lastY = y[index]
            }
        }
        kept.append(count - 1)
        return kept
    }

    /// `values` filtered to the kept indices of the matching screen positions.
    public static func thinned<Element>(
        _ values: [Element], x: [Double], y: [Double],
        stepPx: Double = ScreenPolylineThinning.stepPx
    ) -> [Element] {
        precondition(values.count == x.count, "values and positions must match")
        let indices = keptIndices(x: x, y: y, stepPx: stepPx)
        return indices.count == values.count ? values : indices.map { values[$0] }
    }
}
