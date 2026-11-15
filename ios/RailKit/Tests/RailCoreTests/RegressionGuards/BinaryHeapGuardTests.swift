import Foundation
import RailTestSupport
import Testing
@testable import RailCore

/// One shared heap. The four heaps it replaced are kept below VERBATIM (only
/// renamed with a `Legacy` prefix) and the shared `BinaryMinHeap` must pop the
/// identical sequence on seeded, tie-heavy random inputs: route answers and
/// statistics depend on the order equal-priority items pop.
///
/// The shared heap is always filled with the PRODUCTION element types
/// (`RouteSolver.Item`, `RouteSolver.StationGroupIndex`, `Statistics.CorridorHeapItem`,
/// `NodeItem`, `LocalJourneySearch.Entry`), so their real `precedes` is what is
/// compared against the frozen legacy ordering: an edit to a production comparator
/// fails here. Never replace them with copies declared in this file.
@Suite("RegressionGuardBinaryHeap")
struct RegressionGuardBinaryHeap {

    // MARK: Deterministic generator

    private struct SplitMix64 {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func below(_ n: Int) -> Int { Int(next() % UInt64(n)) }
    }

    /// A random interleaving of pushes and pops, ending in a full drain. `true` = push.
    private static func script(seed: UInt64) -> [Bool] {
        var g = SplitMix64(state: seed)
        var ops: [Bool] = []
        var live = 0
        for _ in 0..<(200 + g.below(400)) {
            if live == 0 || g.below(100) < 60 { ops.append(true); live += 1 }
            else { ops.append(false); live -= 1 }
        }
        ops += [Bool](repeating: false, count: live)
        return ops
    }

    private static let seeds: [UInt64] = (1...300).map { UInt64($0) &* 7919 }

    // MARK: Priority-only (RouteSolver, Statistics) — verbatim legacy heap

    private struct LegacyItem { var tag: Int; var priority: Double }

    private struct LegacyMinHeap {
        private var items: [LegacyItem] = []
        var isEmpty: Bool { items.isEmpty }
        /// Test-only read of the next priority (not part of the legacy algorithm).
        var peekPriority: Double? { items.first?.priority }

        mutating func push(_ item: LegacyItem) {
            items.append(item)
            bubbleUp(items.count - 1)
        }

        mutating func pop() -> LegacyItem? {
            guard !items.isEmpty else { return nil }
            if items.count == 1 { return items.removeLast() }
            let top = items[0]
            items[0] = items.removeLast()
            bubbleDown(0)
            return top
        }

        private mutating func bubbleUp(_ start: Int) {
            var index = start
            while index > 0 {
                let parent = (index - 1) / 2
                if items[parent].priority <= items[index].priority { break }
                items.swapAt(parent, index)
                index = parent
            }
        }

        private mutating func bubbleDown(_ start: Int) {
            var index = start
            while true {
                let left = index * 2 + 1
                let right = left + 1
                var smallest = index
                if left < items.count && items[left].priority < items[smallest].priority {
                    smallest = left
                }
                if right < items.count && items[right].priority < items[smallest].priority {
                    smallest = right
                }
                if smallest == index { break }
                items.swapAt(smallest, index)
                index = smallest
            }
        }
    }

    private struct LegacyTupleMinHeap {
        private var items: [(priority: Double, value: Int)] = []
        var size: Int { items.count }

        mutating func push(_ priority: Double, _ value: Int) {
            items.append((priority, value))
            var i = items.count - 1
            while i > 0 {
                let p = (i - 1) >> 1
                if items[p].priority <= items[i].priority { break }
                items.swapAt(p, i)
                i = p
            }
        }

        mutating func pop() -> (priority: Double, value: Int) {
            let top = items[0]
            let last = items.removeLast()
            if !items.isEmpty {
                items[0] = last
                var i = 0
                let n = items.count
                while true {
                    let l = 2 * i + 1
                    let r = l + 1
                    var s = i
                    if l < n && items[l].priority < items[s].priority { s = l }
                    if r < n && items[r].priority < items[s].priority { s = r }
                    if s == i { break }
                    items.swapAt(s, i)
                    i = s
                }
            }
            return top
        }
    }

    /// `RouteSolver.Item` and `Statistics.CorridorHeapItem` order by priority alone,
    /// so equal priorities are real ties; the tag (carried in the production payload
    /// field) shows which of the tied items popped.
    @Test func priorityOnlyHeapsPopTiesIdentically() {
        for seed in Self.seeds {
            var g = SplitMix64(state: seed ^ 0xA5A5)
            var legacy = LegacyMinHeap()
            var legacyTuple = LegacyTupleMinHeap()
            var solver = BinaryMinHeap<RouteSolver.Item>()
            var corridor = BinaryMinHeap<Statistics.CorridorHeapItem>()
            var tag = 0
            var tiedPops = 0
            for isPush in Self.script(seed: seed) {
                if isPush {
                    // Few distinct priorities (and fractional ones) force ties.
                    let p = Double(g.below(6)) * 0.5
                    legacy.push(LegacyItem(tag: tag, priority: p))
                    legacyTuple.push(p, tag)
                    solver.push(RouteSolver.Item(
                        state: .init(key: String(tag), usedRequiredRail: tag % 2 == 0), priority: p))
                    corridor.push(Statistics.CorridorHeapItem(priority: p, value: String(tag)))
                    tag += 1
                } else {
                    let a = legacy.pop(), b = legacyTuple.pop(), c = solver.pop(), d = corridor.pop()
                    let expected = a.map { String($0.tag) }
                    #expect(expected != nil && String(b.value) == expected
                            && c?.state.key == expected && d?.value == expected
                            && c?.priority == a?.priority && d?.priority == a?.priority
                            && b.priority == a?.priority,
                            "seed \(seed): pop diverged")
                    if let a, let next = legacy.peekPriority, next == a.priority { tiedPops += 1 }
                }
            }
            #expect(legacy.isEmpty && legacyTuple.size == 0 && solver.isEmpty && corridor.isEmpty)
            #expect(tiedPops > 20, "seed \(seed): the input must be tie-heavy (\(tiedPops) tied pops)")
        }
    }

    /// `RouteSolver.StationGroupIndex` orders by the index alone. The app never
    /// queues an index twice (`enqueueStationGroupIndex` goes through a `queued`
    /// set), and two items with the same index are the same value, so a tie
    /// cannot change what pops: there is no tie order to pin. Repeats are pushed
    /// here anyway, to show the pops still match the legacy heap.
    @Test func stationGroupIndexHeapPopsIdentically() {
        for seed in Self.seeds {
            var g = SplitMix64(state: seed ^ 0x0F0F)
            var legacy = LegacyMinHeap()
            var shared = BinaryMinHeap<RouteSolver.StationGroupIndex>()
            for isPush in Self.script(seed: seed) {
                if isPush {
                    let index = g.below(40)
                    legacy.push(LegacyItem(tag: index, priority: Double(index)))
                    shared.push(RouteSolver.StationGroupIndex(index: index))
                } else {
                    let a = legacy.pop(), b = shared.pop()
                    #expect(a != nil && a?.tag == b?.index, "seed \(seed): pop diverged")
                }
            }
            #expect(legacy.isEmpty && shared.isEmpty)
        }
    }

    // MARK: Topology router — verbatim legacy heap

    private struct LegacyNodeHeap {
        typealias Item = (cost: UInt64, changes: UInt32, key: UInt64, node: UInt32)
        private var items: [Item] = []
        var isEmpty: Bool { items.isEmpty }

        @inline(__always)
        private static func less(_ a: Item, _ b: Item) -> Bool {
            if a.cost != b.cost { return a.cost < b.cost }
            if a.changes != b.changes { return a.changes < b.changes }
            return a.key != b.key ? a.key < b.key : a.node < b.node
        }

        mutating func push(_ cost: UInt64, _ changes: UInt32, _ key: UInt64, _ node: UInt32) {
            items.append((cost, changes, key, node))
            var i = items.count - 1
            while i > 0 {
                let parent = (i - 1) / 2
                guard Self.less(items[i], items[parent]) else { break }
                items.swapAt(i, parent)
                i = parent
            }
        }

        mutating func pop() -> Item? {
            guard let top = items.first else { return nil }
            let last = items.removeLast()
            if !items.isEmpty {
                items[0] = last
                var i = 0
                while true {
                    let l = 2 * i + 1, r = l + 1
                    var smallest = i
                    if l < items.count, Self.less(items[l], items[smallest]) { smallest = l }
                    if r < items.count, Self.less(items[r], items[smallest]) { smallest = r }
                    if smallest == i { break }
                    items.swapAt(i, smallest)
                    i = smallest
                }
            }
            return top
        }
    }

    /// Why this test has no tie order to pin: `NodeItem.precedes` compares every
    /// stored field (cost, changes, key, node), so two items that neither precede
    /// the other are equal in all four fields, that is the same value, and which of
    /// them pops first cannot be observed. `nodeItemOrderingIsTotal` proves that
    /// property on the production comparator, so a future field left out of
    /// `precedes` (which would make real ties possible) fails there and must then
    /// get a tie-order test here.
    @Test func nodeHeapPopsIdentically() {
        for seed in Self.seeds {
            var g = SplitMix64(state: seed ^ 0x5A5A)
            var legacy = LegacyNodeHeap()
            var shared = BinaryMinHeap<NodeItem>()
            for isPush in Self.script(seed: seed) {
                if isPush {
                    // Tiny ranges on every field, including duplicate whole items.
                    let cost = UInt64(g.below(3)), changes = UInt32(g.below(3))
                    let key = UInt64(g.below(3)), node = UInt32(g.below(4))
                    legacy.push(cost, changes, key, node)
                    shared.push(NodeItem(cost: cost, changes: changes, key: key, node: node))
                } else {
                    let a = legacy.pop(), b = shared.pop()
                    #expect(a != nil && a?.cost == b?.cost && a?.changes == b?.changes
                            && a?.key == b?.key && a?.node == b?.node,
                            "seed \(seed): pop diverged")
                }
            }
            #expect(legacy.isEmpty && shared.isEmpty)
        }
    }

    /// Every pair of the small field ranges: exactly one of "a pops first",
    /// "b pops first", "a and b are the same value" holds for the production
    /// `NodeItem.precedes`, and it agrees with the frozen legacy ordering.
    @Test func nodeItemOrderingIsTotal() {
        var all: [NodeItem] = []
        for cost in 0..<3 { for changes in 0..<3 { for key in 0..<3 { for node in 0..<3 {
            all.append(NodeItem(cost: UInt64(cost), changes: UInt32(changes), key: UInt64(key), node: UInt32(node)))
        } } } }
        for a in all {
            for b in all {
                let same = a.cost == b.cost && a.changes == b.changes && a.key == b.key && a.node == b.node
                let ab = a.precedes(b), ba = b.precedes(a)
                #expect((ab ? 1 : 0) + (ba ? 1 : 0) + (same ? 1 : 0) == 1, "not a strict total order")
                let legacy = (a.cost, a.changes, a.key, a.node) < (b.cost, b.changes, b.key, b.node)
                #expect(ab == legacy, "NodeItem.precedes left the (cost, changes, key, node) order")
            }
        }
    }

    // MARK: Local journey search — verbatim legacy heap

    private struct LegacyEntry {
        let id: Int
        let distance: Double
        let transfers: Int
        let hops: Int
        func precedes(_ other: LegacyEntry) -> Bool {
            if distance != other.distance { return distance < other.distance }
            if transfers != other.transfers { return transfers < other.transfers }
            if hops != other.hops { return hops < other.hops }
            return id < other.id
        }
    }

    private struct LegacyEntryHeap {
        var items: [LegacyEntry] = []
        mutating func push(_ entry: LegacyEntry) {
            items.append(entry)
            var index = items.count - 1
            while index > 0 {
                let parent = (index - 1) / 2
                guard items[index].precedes(items[parent]) else { break }
                items.swapAt(index, parent)
                index = parent
            }
        }
        mutating func pop() -> LegacyEntry? {
            guard !items.isEmpty else { return nil }
            let first = items[0]
            let last = items.removeLast()
            if items.isEmpty { return first }
            items[0] = last
            var index = 0
            while index * 2 + 1 < items.count {
                let left = index * 2 + 1, right = left + 1
                let child = right < items.count && items[right].precedes(items[left]) ? right : left
                guard items[child].precedes(items[index]) else { break }
                items.swapAt(index, child)
                index = child
            }
            return first
        }
    }

    /// Why this test has no tie order to pin: `LocalJourneySearch.Entry.precedes`
    /// ends on `id`, and the app gives every entry its own id (the index of its
    /// record), so two different entries never tie. Entries with the same id AND
    /// the same other three fields are the same value. Distance, transfers and
    /// hops do tie heavily below (three values each), which exercises every
    /// fall-through of the comparator down to the id. `journeyEntryOrderingIsTotal`
    /// proves the no-tie property on the production comparator.
    @Test func journeyEntryHeapPopsIdentically() {
        for seed in Self.seeds {
            var g = SplitMix64(state: seed ^ 0x1234)
            var legacy = LegacyEntryHeap()
            var shared = BinaryMinHeap<LocalJourneySearch.Entry>()
            var id = 0
            for isPush in Self.script(seed: seed) {
                if isPush {
                    // Distinct ids (as in the app) but ties on every other field;
                    // ids are pushed in a scrambled order so id order is exercised.
                    let d = Double(g.below(3)), t = g.below(3), h = g.below(3)
                    let scrambled = (id &* 7) % 1009
                    legacy.push(LegacyEntry(id: scrambled, distance: d, transfers: t, hops: h))
                    shared.push(LocalJourneySearch.Entry(id: scrambled, distance: d, transfers: t, hops: h))
                    id += 1
                } else {
                    let a = legacy.pop(), b = shared.pop()
                    #expect(a != nil && a?.id == b?.id && a?.distance == b?.distance
                            && a?.transfers == b?.transfers && a?.hops == b?.hops,
                            "seed \(seed): pop diverged")
                }
            }
            #expect(legacy.items.isEmpty && shared.isEmpty)
        }
    }

    /// Exactly one of "a pops first", "b pops first", "same value" holds for the
    /// production `Entry.precedes`, and it agrees with the frozen legacy ordering.
    @Test func journeyEntryOrderingIsTotal() {
        var all: [LocalJourneySearch.Entry] = []
        for d in 0..<3 { for t in 0..<3 { for h in 0..<3 { for id in 0..<3 {
            all.append(LocalJourneySearch.Entry(id: id, distance: Double(d) * 0.5, transfers: t, hops: h))
        } } } }
        for a in all {
            for b in all {
                let same = a.id == b.id && a.distance == b.distance && a.transfers == b.transfers && a.hops == b.hops
                let ab = a.precedes(b), ba = b.precedes(a)
                #expect((ab ? 1 : 0) + (ba ? 1 : 0) + (same ? 1 : 0) == 1, "not a strict total order")
                let legacy = LegacyEntry(id: a.id, distance: a.distance, transfers: a.transfers, hops: a.hops)
                    .precedes(LegacyEntry(id: b.id, distance: b.distance, transfers: b.transfers, hops: b.hops))
                #expect(ab == legacy, "Entry.precedes left the (distance, transfers, hops, id) order")
            }
        }
    }

    // MARK: Source guard — no second heap implementation

    @Test func replacedFilesUseTheSharedHeapAndCarryNoSecondOne() {
        let files = ["Routing/RouteSolver.swift", "Statistics/Statistics.swift",
                     "Topology/RailTopologyRouter.swift", "Routing/LocalJourneySearch.swift"]
        for file in files {
            let text = SourceFiles.textRecording(file, relativeTo: SourceFiles.railCoreSources)
            #expect(!text.isEmpty, "\(file) not readable")
            #expect(text.contains("BinaryMinHeap<"), "\(file) must use the shared heap")
            for marker in ["bubbleUp", "bubbleDown", "swapAt(", "struct MinHeap", "struct NodeHeap",
                           "struct TupleMinHeap", "struct Heap", "removeLast()"] {
                #expect(!text.contains(marker), "\(file) re-implements a heap (\(marker))")
            }
        }
        let shared = SourceFiles.textRecording("Utilities/BinaryHeap.swift", relativeTo: SourceFiles.railCoreSources)
        #expect(shared.contains("struct BinaryMinHeap<Element: HeapOrdered>"))
    }

    /// The differential tests above must run the production comparators. A
    /// `HeapOrdered` type declared in this file would be a copy that keeps passing
    /// after the production one changes.
    @Test func thisGuardDeclaresNoComparatorCopy() throws {
        let own = try SourceFiles.text("RailKit/Tests/RailCoreTests/RegressionGuards/BinaryHeapGuardTests.swift")
        let conformance = ": " + "HeapOrdered {"
        #expect(!own.contains(conformance), "declare no HeapOrdered type in the guard; use the production ones")
        for type in ["BinaryMinHeap<RouteSolver.Item>", "BinaryMinHeap<RouteSolver.StationGroupIndex>",
                     "BinaryMinHeap<Statistics.CorridorHeapItem>", "BinaryMinHeap<NodeItem>",
                     "BinaryMinHeap<LocalJourneySearch.Entry>"] {
            #expect(own.contains(type), "the guard no longer exercises \(type)")
        }
        // Every HeapOrdered type in RailCore is one of the five exercised above.
        let known: Set<String> = ["Item", "StationGroupIndex", "CorridorHeapItem", "NodeItem", "Entry"]
        let root = SourceFiles.railCoreSources
        let files = try #require(FileManager.default.enumerator(atPath: root.path)).compactMap { $0 as? String }
            .filter { $0.hasSuffix(".swift") }
        #expect(files.count > 50, "RailCore sources not found")
        var found: Set<String> = []
        for file in files {
            let text = try SourceFiles.text(file, relativeTo: root)
            for line in text.split(separator: "\n") where line.contains(conformance) && line.contains("struct ") {
                let name = line.components(separatedBy: "struct ")[1].prefix { $0.isLetter || $0.isNumber }
                found.insert(String(name))
                #expect(!line.contains("private "), "\(file): \(name) must stay internal so this guard can use it")
            }
        }
        #expect(found == known, "HeapOrdered types changed (\(found.sorted())): add a differential test for each new one")
    }
}
