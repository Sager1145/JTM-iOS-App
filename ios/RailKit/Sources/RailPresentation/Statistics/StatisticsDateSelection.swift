/// An inclusive selection of ISO calendar days (`YYYY-MM-DD`), with optional holes.
/// Empty means no statistics filter; `contains` reports explicit selection for calendar highlights.
public struct StatisticsDateSelection: Equatable, Sendable {
    public private(set) var start: String?
    public private(set) var end: String?
    public private(set) var excludedDates: Set<String> = []
    public private(set) var isRangeComplete = false

    public init() {}

    public var isEmpty: Bool { start == nil }

    public func contains(_ date: String) -> Bool {
        isWithinBounds(date) && !excludedDates.contains(date)
    }

    /// Occupied days can become endpoints. Any interior day can be toggled after a range is complete.
    public func canSelect(_ date: String, availableDates: Set<String>) -> Bool {
        availableDates.contains(date) || (isRangeComplete && isWithinBounds(date))
    }

    public mutating func clear() {
        self = Self()
    }

    public mutating func tap(_ date: String, availableDates: Set<String>) {
        guard canSelect(date, availableDates: availableDates) else { return }

        guard let start else {
            selectAnchor(date)
            return
        }

        if !isRangeComplete {
            if date == start {
                clear()
            } else {
                self.start = min(start, date)
                end = max(start, date)
                isRangeComplete = true
            }
            return
        }

        guard isWithinBounds(date) else {
            selectAnchor(date)
            return
        }

        if excludedDates.remove(date) != nil { return }
        excludedDates.insert(date)

        // Removing an endpoint also removes the unoccupied fringe before the next occupied day.
        if date == start || date == end {
            let remaining = availableDates.filter { contains($0) }.sorted()
            guard let first = remaining.first, let last = remaining.last else {
                clear()
                return
            }
            self.start = first
            end = last
            excludedDates = excludedDates.filter { first <= $0 && $0 <= last }
        }
    }

    private func isWithinBounds(_ date: String) -> Bool {
        guard let start, let end else { return false }
        return start <= date && date <= end
    }

    private mutating func selectAnchor(_ date: String) {
        start = date
        end = date
        excludedDates.removeAll()
        isRangeComplete = false
    }
}
