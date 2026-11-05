import Foundation

/// Immutable compact index over one region's documents. Build it once
/// (off the main thread); query it from any thread.
///
/// Layout: every distinct spelling key of every document is one 20-byte
/// `KeyRecord` pointing into one flat `[UInt16]` arena; original names live
/// in one UTF-8 blob and are decoded only for the returned rows. A query is a
/// single linear scan with allocation-free comparisons; per-query scratch
/// buffers are pooled and reused across keystrokes.
public final class SearchIndex: Sendable {
    public let regionCode: String

    struct KeyRecord {
        var mask: UInt32
        var start: UInt32
        var doc: UInt32
        var name: UInt32
        var length: UInt16
        var flags: UInt8

        var source: SearchMatchSource { SearchMatchSource(rawValue: flags & 7) ?? .name }
        var isLoose: Bool { flags & 8 != 0 }
        var noFuzzy: Bool { flags & 16 != 0 }
    }

    // Documents (parallel arrays).
    let kinds: [SearchEntityKind]
    let ids: [String]
    let titles: [String]
    let importance: [Float]
    let latitudes: [Float]
    let longitudes: [Float]
    let lineRefStart: [UInt32]
    let lineRefs: [UInt32]
    let operatorRefStart: [UInt32]
    let operatorRefs: [UInt32]
    let lineTable: [String]
    let operatorTable: [String]
    let stationIDs: [String?]
    let complexIDs: [String?]
    let docByEntity: [SearchEntityID: Int32]
    /// Line table index → line document.
    let lineDocByRef: [Int32]
    let operatorDocByRef: [Int32]

    // Names and keys.
    let nameBlob: [UInt8]
    let nameStart: [UInt32]
    let keys: [KeyRecord]
    let units: [UInt16]

    // Filter lookups (canonical key → documents).
    let companyExact: [[UInt16]: [Int32]]
    let lineExact: [[UInt16]: [Int32]]
    let lineStem: [[UInt16]: [Int32]]

    private let pool: SearchScratchPool

    public init(regionCode: String, documents: [SearchDocument]) {
        self.regionCode = regionCode
        var kinds: [SearchEntityKind] = [], ids: [String] = [], titles: [String] = []
        var importance: [Float] = [], latitudes: [Float] = [], longitudes: [Float] = []
        var lineRefStart: [UInt32] = [0], lineRefs: [UInt32] = []
        var operatorRefStart: [UInt32] = [0], operatorRefs: [UInt32] = []
        var lineTable: [String] = [], operatorTable: [String] = []
        var lineIndex: [String: UInt32] = [:], operatorIndex: [String: UInt32] = [:]
        var stationIDs: [String?] = [], complexIDs: [String?] = []
        var docByEntity: [SearchEntityID: Int32] = [:]
        var nameBlob: [UInt8] = [], nameStart: [UInt32] = []
        var keys: [KeyRecord] = [], units: [UInt16] = []
        var companyExact: [[UInt16]: [Int32]] = [:]
        var lineExact: [[UInt16]: [Int32]] = [:]
        var lineStem: [[UInt16]: [Int32]] = [:]
        let count = documents.count
        kinds.reserveCapacity(count); ids.reserveCapacity(count); titles.reserveCapacity(count)
        keys.reserveCapacity(count * 5); units.reserveCapacity(count * 30)

        func ref(_ value: String, _ table: inout [String], _ index: inout [String: UInt32]) -> UInt32 {
            if let existing = index[value] { return existing }
            let next = UInt32(table.count)
            table.append(value)
            index[value] = next
            return next
        }

        for document in documents {
            guard docByEntity[document.entity] == nil else { continue }
            let doc = Int32(kinds.count)
            docByEntity[document.entity] = doc
            kinds.append(document.entity.kind)
            ids.append(document.entity.id)
            titles.append(document.title)
            importance.append(max(0, min(1, document.importance)))
            latitudes.append(document.latitude.map(Float.init) ?? .nan)
            longitudes.append(document.longitude.map(Float.init) ?? .nan)
            for line in document.lineIDs { lineRefs.append(ref(line, &lineTable, &lineIndex)) }
            lineRefStart.append(UInt32(lineRefs.count))
            for op in document.operatorIDs { operatorRefs.append(ref(op, &operatorTable, &operatorIndex)) }
            operatorRefStart.append(UInt32(operatorRefs.count))
            stationIDs.append(document.stationID)
            complexIDs.append(document.complexID)

            var seenCanonical: Set<[UInt16]> = []
            var seenLoose: Set<[UInt16]> = []
            let names = [SearchDocument.Name(document.title, source: .name)] + document.names
                .sorted { Self.sourceOrder($0.source) < Self.sourceOrder($1.source) }
            for name in names {
                let text = name.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let canonical = SearchNormalizer.canonical(text)
                guard !canonical.isEmpty, canonical.count < Int(UInt16.max) else { continue }
                let loose = name.source == .code ? nil : SearchNormalizer.loose(fromCanonical: canonical)
                let newCanonical = seenCanonical.insert(canonical).inserted
                let newLoose = loose.map { seenLoose.insert($0).inserted } ?? false
                guard newCanonical || newLoose else { continue }
                let nameRef = UInt32(nameStart.count)
                nameStart.append(UInt32(nameBlob.count))
                nameBlob.append(contentsOf: text.utf8)
                let noFuzzy: UInt8 = name.source == .code ? 16 : 0
                if newCanonical {
                    keys.append(KeyRecord(
                        mask: SearchMatching.mask(canonical), start: UInt32(units.count), doc: UInt32(doc),
                        name: nameRef, length: UInt16(canonical.count), flags: name.source.rawValue | noFuzzy))
                    units.append(contentsOf: canonical)
                    switch document.entity.kind {
                    case .company: companyExact[canonical, default: []].append(doc)
                    case .line:
                        lineExact[canonical, default: []].append(doc)
                        if let stem = SearchKeywords.stripLineSuffix(canonical) {
                            lineStem[stem, default: []].append(doc)
                        }
                    default: break
                    }
                }
                if newLoose, let loose, loose.count < Int(UInt16.max) {
                    keys.append(KeyRecord(
                        mask: SearchMatching.mask(loose), start: UInt32(units.count), doc: UInt32(doc),
                        name: nameRef, length: UInt16(loose.count),
                        flags: SearchMatchSource.romaji.rawValue | 8))
                    units.append(contentsOf: loose)
                }
            }
        }
        nameStart.append(UInt32(nameBlob.count))
        // Line documents also carry their operators' names (so "JR" finds JR lines);
        // those spellings name the company, not a line, for keyword filters.
        for key in companyExact.keys {
            lineExact[key] = nil
            lineStem[key] = nil
        }

        var lineDocByRef = [Int32](repeating: -1, count: lineTable.count)
        var operatorDocByRef = [Int32](repeating: -1, count: operatorTable.count)
        for (index, line) in lineTable.enumerated() {
            if let doc = docByEntity[.line(line)] { lineDocByRef[index] = doc }
        }
        for (index, op) in operatorTable.enumerated() {
            if let doc = docByEntity[.company(op)] { operatorDocByRef[index] = doc }
        }

        self.kinds = kinds; self.ids = ids; self.titles = titles
        self.importance = importance; self.latitudes = latitudes; self.longitudes = longitudes
        self.lineRefStart = lineRefStart; self.lineRefs = lineRefs
        self.operatorRefStart = operatorRefStart; self.operatorRefs = operatorRefs
        self.lineTable = lineTable; self.operatorTable = operatorTable
        self.stationIDs = stationIDs; self.complexIDs = complexIDs
        self.docByEntity = docByEntity
        self.lineDocByRef = lineDocByRef; self.operatorDocByRef = operatorDocByRef
        self.nameBlob = nameBlob; self.nameStart = nameStart
        self.keys = keys; self.units = units
        self.companyExact = companyExact; self.lineExact = lineExact; self.lineStem = lineStem
        self.pool = SearchScratchPool()
    }

    private static func sourceOrder(_ source: SearchMatchSource) -> Int {
        switch source {
        case .name: 0
        case .alias: 1
        case .reading: 2
        case .romaji: 3
        case .code: 4
        }
    }

    /// Number of documents.
    public var count: Int { kinds.count }

    /// Approximate resident bytes of the index (keys, arena, names, document
    /// arrays and filter maps). Excludes the catalog the index was built from.
    public var memoryFootprint: Int {
        func strings(_ values: [String]) -> Int {
            values.reduce(values.count * 16) { $0 + ($1.utf8.count > 15 ? $1.utf8.count + 32 : 0) }
        }
        func optionalStrings(_ values: [String?]) -> Int {
            values.reduce(values.count * 16) { $0 + (($1?.utf8.count ?? 0) > 15 ? $1!.utf8.count + 32 : 0) }
        }
        func map(_ m: [[UInt16]: [Int32]]) -> Int {
            m.reduce(m.capacity * 24) { $0 + 64 + $1.key.count * 2 + $1.value.count * 4 }
        }
        var bytes = keys.capacity * MemoryLayout<KeyRecord>.stride + units.capacity * 2
        bytes += nameBlob.capacity + nameStart.capacity * 4
        bytes += kinds.capacity + importance.capacity * 4 + latitudes.capacity * 4 + longitudes.capacity * 4
        bytes += (lineRefStart.capacity + lineRefs.capacity + operatorRefStart.capacity + operatorRefs.capacity) * 4
        bytes += strings(ids) + strings(titles) + strings(lineTable) + strings(operatorTable)
        bytes += optionalStrings(stationIDs) + optionalStrings(complexIDs)
        bytes += docByEntity.capacity * (MemoryLayout<SearchEntityID>.stride + 8)
        bytes += (lineDocByRef.capacity + operatorDocByRef.capacity) * 4
        bytes += map(companyExact) + map(lineExact) + map(lineStem)
        return bytes
    }

    /// The document for an entity, when indexed (names are not reconstructed).
    public func document(for entity: SearchEntityID) -> SearchDocument? {
        guard let doc = docByEntity[entity] else { return nil }
        return document(Int(doc))
    }

    func document(_ doc: Int) -> SearchDocument {
        SearchDocument(
            entity: SearchEntityID(kind: kinds[doc], id: ids[doc]), title: titles[doc],
            importance: importance[doc], lineIDs: lineIDs(doc), operatorIDs: operatorIDs(doc),
            stationID: stationIDs[doc], complexID: complexIDs[doc],
            latitude: latitudes[doc].isNaN ? nil : Double(latitudes[doc]),
            longitude: longitudes[doc].isNaN ? nil : Double(longitudes[doc]))
    }

    func lineIDs(_ doc: Int) -> [String] {
        (Int(lineRefStart[doc])..<Int(lineRefStart[doc + 1])).map { lineTable[Int(lineRefs[$0])] }
    }

    func operatorIDs(_ doc: Int) -> [String] {
        (Int(operatorRefStart[doc])..<Int(operatorRefStart[doc + 1])).map { operatorTable[Int(operatorRefs[$0])] }
    }

    func nameText(_ ref: UInt32) -> String {
        let from = Int(nameStart[Int(ref)]), to = Int(nameStart[Int(ref) + 1])
        return nameBlob[from..<to].withUnsafeBufferPointer { String(decoding: $0, as: UTF8.self) }
    }

    func keyUnits(_ record: KeyRecord) -> ArraySlice<UInt16> {
        units[Int(record.start)..<(Int(record.start) + Int(record.length))]
    }

    func withScratch<T>(_ body: (SearchScratch) -> T) -> T {
        let scratch = pool.take(documents: kinds.count)
        defer { pool.give(scratch) }
        return body(scratch)
    }

    /// Parse filters, match, rank. Empty text returns suggestions.
    public func query(_ text: String, scope: SearchScope = .all, context: SearchContext) -> SearchResponse {
        SearchQueryRunner(index: self, text: text, scope: scope, context: context).run()
    }
}

/// Reusable per-query buffers (one per concurrent query).
final class SearchScratch {
    var bestScore: [Float] = []
    var bestKey: [Int32] = []
    var bestHit: [SearchMatching.Hit?] = []
    var tokenMask: [UInt16] = []
    var allowed: [Bool] = []
    var touched: [Int32] = []
    let rows = UnsafeMutablePointer<Int32>.allocate(capacity: SearchMatching.rowCapacity)

    deinit { rows.deallocate() }

    func prepare(documents: Int) {
        if bestScore.count != documents {
            bestScore = [Float](repeating: -.infinity, count: documents)
            bestKey = [Int32](repeating: -1, count: documents)
            bestHit = [SearchMatching.Hit?](repeating: nil, count: documents)
            tokenMask = [UInt16](repeating: 0, count: documents)
            allowed = [Bool](repeating: true, count: documents)
            touched.reserveCapacity(1024)
        }
    }

    func reset() {
        for doc in touched {
            let d = Int(doc)
            bestScore[d] = -.infinity
            bestKey[d] = -1
            bestHit[d] = nil
            tokenMask[d] = 0
        }
        touched.removeAll(keepingCapacity: true)
    }
}

final class SearchScratchPool: @unchecked Sendable {
    private let lock = NSLock()
    private var free: [SearchScratch] = []

    func take(documents: Int) -> SearchScratch {
        let scratch = lock.withLock { free.popLast() } ?? SearchScratch()
        scratch.prepare(documents: documents)
        return scratch
    }

    func give(_ scratch: SearchScratch) {
        scratch.reset()
        lock.withLock { if free.count < 4 { free.append(scratch) } }
    }
}
