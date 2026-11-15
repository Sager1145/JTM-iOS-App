import Foundation
import RailCore

/// A small thread-safe memo for a pure function of its key. When it reaches
/// `capacity` it empties and starts over, so memory stays bounded without an
/// eviction order to maintain on a hot path.
///
/// Only for functions whose answer depends on the key alone; there is nothing
/// to invalidate. A key whose answer can change must not use it.
public final class BoundedLookupCache<Key: Hashable & Sendable, Value: Sendable>: @unchecked Sendable {
    private let capacity: Int
    private let lock = NSLock()
    private var storage: [Key: Value] = [:]

    public init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage.count
    }

    public func value(for key: Key, compute: (Key) -> Value) -> Value {
        lock.lock()
        if let hit = storage[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()
        let computed = compute(key)
        lock.lock()
        if storage.count >= capacity { storage.removeAll(keepingCapacity: true) }
        storage[key] = computed
        lock.unlock()
        return computed
    }
}

/// `Stations.normalizeStationName` (NFKC then NFC) memoized per name: the
/// marker pass normalizes the same few thousand names on every rebuild.
public enum StationNameKeyCache {
    private static let cache = BoundedLookupCache<String, String>(capacity: 16_384)

    public static func key(_ name: String) -> String {
        cache.value(for: name) { Stations.normalizeStationName($0) }
    }

    static var cachedCount: Int { cache.count }
}
