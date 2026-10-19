import Foundation

/// Resolves category visibility from physical source geometry, retaining the
/// coordinator's cache until the owning ride/index inputs change.
public struct RiddenCategoryVisibility {
    private var categories: [String: String] = [:]
    public init() {}
    public mutating func invalidate() { categories.removeAll(keepingCapacity: true) }

    public mutating func draws(
        key: String, isRidden: Bool, sourceCoordinates: [Coordinate],
        sectionSourceLines: @autoclosure () -> [[Coordinate]], from: String?, to: String?,
        country: String, index: Statistics.EdgeIndex?, filter: Statistics.RiddenCategoryFilter
    ) -> Bool {
        guard filter.anyHidden, isRidden else { return true }
        if let category = categories[key] { return filter[category] }
        guard let index else { return true }
        // A repaired zero-distance terminal branch inherits its source section's
        // category; it contributes no invented railway distance.
        let lines = sourceCoordinates.allSatisfy { $0 == sourceCoordinates.first }
            ? sectionSourceLines() : [sourceCoordinates]
        let category = Statistics.riddenFeatureCategory(
            .init(lines: lines, rideSegment: true, from: from, to: to),
            index: index, country: country)
        categories[key] = category ?? ""
        return filter[category ?? ""]
    }
}
