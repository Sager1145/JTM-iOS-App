/// An element a `BinaryMinHeap` can order. `precedes` is the strict "pops before"
/// relation; two elements that neither precede the other are ties.
protocol HeapOrdered {
    func precedes(_ other: Self) -> Bool
}

/// The one binary min-heap (array-backed, array-order sift). Several callers
/// (route solver, topology router, statistics corridor trace, local journey
/// search) depend on the exact order in which TIES pop, because that decides
/// which equally cheap predecessor a node keeps. So the algorithm is fixed and
/// only the ordering is the caller's:
///
/// - push appends, then sifts up while the element strictly precedes its parent;
/// - pop moves the last element to the root, then sifts down, each step choosing
///   the left child unless the right child strictly precedes the smaller so far
///   (so on a tie the parent stays and, between children, the left wins).
///
/// Generic over a concrete `Element`, so calls specialise: no existential or
/// closure per comparison. Priorities must not be NaN (the callers' never are).
struct BinaryMinHeap<Element: HeapOrdered> {
    private var items: [Element] = []
    var isEmpty: Bool { items.isEmpty }
    var count: Int { items.count }

    @inline(__always)
    mutating func push(_ item: Element) {
        items.append(item)
        var i = items.count - 1
        while i > 0 {
            let parent = (i - 1) / 2
            guard items[i].precedes(items[parent]) else { break }
            items.swapAt(i, parent)
            i = parent
        }
    }

    @inline(__always)
    mutating func pop() -> Element? {
        guard let top = items.first else { return nil }
        let last = items.removeLast()
        if !items.isEmpty {
            items[0] = last
            var i = 0
            let n = items.count
            while true {
                let l = 2 * i + 1, r = l + 1
                var smallest = i
                if l < n, items[l].precedes(items[smallest]) { smallest = l }
                if r < n, items[r].precedes(items[smallest]) { smallest = r }
                if smallest == i { break }
                items.swapAt(i, smallest)
                i = smallest
            }
        }
        return top
    }
}
