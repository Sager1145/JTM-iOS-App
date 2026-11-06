import Foundation
import MachO
import RailCore

/// The persisted ``RouteDigestIndex``: one file beside the route cache, read
/// once per process and written back after the loads that changed it.
///
/// It lives under `RailMap/Routes/index/`, so ``RiddenRouteStore`` Reload all
/// (which removes `RailMap/Routes`) wipes it with the routes, and the
/// per-region sweep (which lists only `RailMap/Routes/<region>`) never sees it.
final class RouteDigestIndexStore: @unchecked Sendable {
    static let shared = RouteDigestIndexStore()

    /// Two keys per journey cover an edit and its predecessor; the LRU keeps
    /// the working set of any shipped store well inside this.
    static let entryLimit = 4096

    private let lock = NSLock()
    private var index = RouteDigestIndex()
    private var loaded = false
    private var dirty = false

    private static var fileURL: URL {
        (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory)
            .appending(path: "RailMap/Routes/index/route-digests.json")
    }

    func lookup(_ key: String) -> RouteDigestIndex.Entry? {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()
        return index.lookup(key)
    }

    func record(_ key: String, digest: String, expectedSections: [RouteSection]) {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()
        if index.record(key, digest: digest, expectedSections: expectedSections) { dirty = true }
    }

    /// Writes the index if anything was recorded since the last write.
    func flush() {
        lock.lock()
        guard dirty else { lock.unlock(); return }
        index.trim(to: Self.entryLimit)
        let snapshot = index
        dirty = false
        lock.unlock()
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        let url = Self.fileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// Forgets every entry in memory; the caller removes the file.
    func clear() {
        lock.lock()
        index = RouteDigestIndex()
        loaded = true
        dirty = false
        lock.unlock()
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        if let data = try? Data(contentsOf: Self.fileURL) {
            index = RouteDigestIndex.decoded(from: data)
        }
    }
}

/// The digest each journey id last resolved to in this process, so the
/// route-cache sweep can keep every file the current working set reads.
final class CurrentRouteDigests: @unchecked Sendable {
    static let shared = CurrentRouteDigests()

    private let lock = NSLock()
    private var byID: [String: String] = [:]

    func note(id: String, digest: String) {
        lock.lock()
        byID[id] = digest
        lock.unlock()
    }

    func digests(for ids: Set<String>) -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return Set(ids.compactMap { byID[$0] })
    }
}

/// Identities that key ``RouteDigestIndex`` entries besides the bundled
/// resource revisions.
enum RouteDigestIndexIdentity {
    /// UUIDs of every Mach-O image loaded from inside the app bundle (the
    /// executable, a Debug `*.debug.dylib`, embedded frameworks). Any rebuild
    /// that changes code changes at least one, so normalisation, matching or
    /// digest logic changed without a version bump still misses. `nil` when
    /// no image could be identified, which disables the index.
    static let build: String? = {
        let bundlePath = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        var parts: [String] = []
        for image in 0..<_dyld_image_count() {
            guard let cName = _dyld_get_image_name(image),
                  let header = _dyld_get_image_header(image) else { continue }
            let path = URL(fileURLWithPath: String(cString: cName)).resolvingSymlinksInPath().path
            guard path.hasPrefix(bundlePath), let uuid = imageUUID(header) else { continue }
            parts.append(String(path.dropFirst(bundlePath.count)) + "=" + uuid)
        }
        guard !parts.isEmpty else { return nil }
        let version = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return ([version] + parts.sorted()).joined(separator: ";")
    }()

    private static func imageUUID(_ header: UnsafePointer<mach_header>) -> String? {
        let is64 = header.pointee.magic == UInt32(MH_MAGIC_64)
        let headerSize = is64 ? MemoryLayout<mach_header_64>.size : MemoryLayout<mach_header>.size
        var command = UnsafeRawPointer(header).advanced(by: headerSize)
        for _ in 0..<header.pointee.ncmds {
            let load = command.assumingMemoryBound(to: load_command.self).pointee
            if load.cmd == UInt32(LC_UUID) {
                let uuid = command.assumingMemoryBound(to: uuid_command.self).pointee.uuid
                return UUID(uuid: uuid).uuidString
            }
            command = command.advanced(by: Int(load.cmdsize))
        }
        return nil
    }

    private static let fileLock = NSLock()
    nonisolated(unsafe) private static var fileIdentities: [String: String] = [:]

    /// Phase and bundled-file identity of each region's registry, or `nil`
    /// while any is still decoding (the canonical train is not settled yet).
    static func registry(regions: [String]) -> String? {
        var parts: [String] = []
        for code in Set(regions.map { $0.lowercased() }).sorted() where !code.isEmpty {
            let phase: String
            switch RegistryIdentityLookup.phase(forRegion: code) {
            case .ready: phase = "ready"
            case .unavailable: phase = "unavailable"
            case .pending: return nil
            }
            parts.append("\(code):\(phase):\(registryFile(code))")
        }
        return parts.joined(separator: "|")
    }

    private static func registryFile(_ code: String) -> String {
        fileLock.lock()
        defer { fileLock.unlock() }
        if let known = fileIdentities[code] { return known }
        var identity = "none"
        if let url = Bundle.main.url(forResource: "registry-\(code)", withExtension: "json"),
           let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) {
            identity = "\(values.fileSize ?? -1)@\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        }
        fileIdentities[code] = identity
        return identity
    }
}
