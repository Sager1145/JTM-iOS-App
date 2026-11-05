import Foundation

/// One query against one index: keyword parsing, the scan, ranking,
/// did-you-mean and empty-query suggestions.
struct SearchQueryRunner {
    let index: SearchIndex
    let text: String
    let scope: SearchScope
    let context: SearchContext

    // MARK: Parsing

    private struct Parsed {
        var applied: [SearchFilter] = []
        var suggested: [SearchFilter] = []
        var typeHint: SearchScope?
        var residual: [String] = []
        var companyDocs: [Int32] = []
        var lineDocs: [Int32] = []
    }

    private static func tokens(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace || $0 == "\u{3000}" }).map(String.init)
    }

    private static func string(_ units: [UInt16]) -> String { String(decoding: units, as: UTF16.self) }

    private func filter(_ doc: Int32, source: String) -> SearchFilter {
        let d = Int(doc)
        var title = index.titles[d]
        if index.kinds[d] == .line,
           let op = index.operatorRefStart[d] < index.operatorRefStart[d + 1]
            ? index.operatorDocByRef[Int(index.operatorRefs[Int(index.operatorRefStart[d])])] : nil,
           op >= 0 {
            title = index.titles[Int(op)] + " " + title
        }
        return SearchFilter(entity: SearchEntityID(kind: index.kinds[d], id: index.ids[d]), title: title, sourceText: source)
    }

    private func operatorRefs(of doc: Int32) -> ArraySlice<UInt32> {
        let d = Int(doc)
        return index.operatorRefs[Int(index.operatorRefStart[d])..<Int(index.operatorRefStart[d + 1])]
    }

    private func lineRefs(of doc: Int32) -> ArraySlice<UInt32> {
        let d = Int(doc)
        return index.lineRefs[Int(index.lineRefStart[d])..<Int(index.lineRefStart[d + 1])]
    }

    private func resolveCompany(_ docs: [Int32], source: String, into parsed: inout Parsed) {
        let unique = Array(Set(docs)).sorted()
        if unique.count == 1 {
            if !parsed.companyDocs.contains(unique[0]) {
                parsed.companyDocs.append(unique[0])
                parsed.applied.append(filter(unique[0], source: source))
            }
        } else {
            parsed.suggested.append(contentsOf: unique.prefix(6).map { filter($0, source: source) })
            parsed.residual.append(source)
        }
    }

    private func resolveLine(_ docs: [Int32], source: String, into parsed: inout Parsed) {
        let unique = Array(Set(docs)).sorted()
        var companies = Set(parsed.companyDocs.flatMap { operatorRefs(of: $0) })
        for id in context.operatorIDs {
            if let ref = index.operatorTable.firstIndex(of: id) { companies.insert(UInt32(ref)) }
        }
        let narrowed = companies.isEmpty
            ? unique : unique.filter { !companies.isDisjoint(with: operatorRefs(of: $0)) }
        if narrowed.count == 1 {
            if !parsed.lineDocs.contains(narrowed[0]) {
                parsed.lineDocs.append(narrowed[0])
                parsed.applied.append(filter(narrowed[0], source: source))
            }
        } else {
            let offered = narrowed.isEmpty ? unique : narrowed
            let ranked = offered.sorted { index.importance[Int($0)] > index.importance[Int($1)] }
            parsed.suggested.append(contentsOf: ranked.prefix(6).map { filter($0, source: source) })
            parsed.residual.append(source)
            if parsed.typeHint == nil { parsed.typeHint = .lines }
        }
    }

    /// Company keys that are a proper prefix of `key` with a line name left over ("东急目黑线").
    private func companyPrefix(of key: [UInt16]) -> (docs: [Int32], rest: [UInt16])? {
        var best: (docs: [Int32], rest: [UInt16])?
        var bestLength = 0
        for (company, docs) in index.companyExact where company.count >= 2 && company.count < key.count
            && company.count > bestLength && key.starts(with: company) {
            let rest = Array(key[company.count...])
            let isLine = index.lineExact[rest] != nil
                || SearchKeywords.stripLineSuffix(rest).map { index.lineStem[$0] != nil || index.lineExact[$0] != nil } == true
            guard isLine else { continue }
            best = (docs, rest)
            bestLength = company.count
        }
        return best
    }

    private func parse() -> Parsed {
        var parsed = Parsed()
        var remaining: [String] = []
        // Phase 1: companies (they narrow the line lookup that follows).
        let raw = Self.tokens(text)
        var i = 0
        while i < raw.count {
            if i + 1 < raw.count {
                let pair = raw[i] + " " + raw[i + 1]
                if let docs = index.companyExact[SearchNormalizer.canonical(pair)] {
                    resolveCompany(docs, source: pair, into: &parsed)
                    i += 2
                    continue
                }
            }
            let token = raw[i]
            let key = SearchNormalizer.canonical(token)
            i += 1
            guard !key.isEmpty else { continue }
            if let docs = index.companyExact[key], index.lineExact[key] == nil {
                resolveCompany(docs, source: token, into: &parsed)
            } else if let docs = index.companyExact[key] {
                parsed.suggested.append(contentsOf: Array(Set(docs)).sorted().prefix(6).map { filter($0, source: token) })
                remaining.append(token)
            } else if let split = companyPrefix(of: key) {
                let rest = Self.string(split.rest)
                let companyText = Self.string(Array(key.prefix(key.count - split.rest.count)))
                resolveCompany(split.docs, source: companyText, into: &parsed)
                remaining.append(rest)
            } else if let stem = SearchKeywords.stripCompanySuffix(key), let docs = index.companyExact[stem],
                      index.lineExact[key] == nil {
                resolveCompany(docs, source: token, into: &parsed)
            } else {
                remaining.append(token)
            }
        }
        // Phase 2: type words, lines, station suffixes.
        for token in remaining {
            let key = SearchNormalizer.canonical(token)
            if SearchKeywords.lineWords.contains(key) { parsed.typeHint = .lines; continue }
            if SearchKeywords.stationWords.contains(key) { parsed.typeHint = .stations; continue }
            if SearchKeywords.companyWords.contains(key) { parsed.typeHint = .companies; continue }
            if parsed.suggested.contains(where: { $0.sourceText == token }) {
                parsed.residual.append(token)
                continue
            }
            if let docs = index.lineExact[key] {
                resolveLine(docs, source: token, into: &parsed)
            } else if let stem = SearchKeywords.stripLineSuffix(key) {
                if let docs = index.lineStem[stem] ?? index.lineExact[stem] {
                    resolveLine(docs, source: token, into: &parsed)
                } else {
                    parsed.typeHint = .lines
                    parsed.residual.append(token)
                }
            } else if let stem = SearchKeywords.stripStationSuffix(key), !stem.isEmpty {
                parsed.typeHint = .stations
                parsed.residual.append(Self.string(stem))
            } else {
                parsed.residual.append(token)
            }
        }
        return parsed
    }

    // MARK: Run

    func run() -> SearchResponse {
        var parsed = parse()
        // A bare type word ("railway", "駅") names no filter: search it as text.
        if parsed.residual.isEmpty, parsed.applied.isEmpty, parsed.typeHint != nil {
            parsed.residual = Self.tokens(text)
            parsed.typeHint = nil
        }
        var effective = scope
        if let hint = parsed.typeHint, !scope.intersection(hint).isEmpty { effective = scope.intersection(hint) }
        let residualText = parsed.residual.joined(separator: " ")
        let parsedQuery = SearchParsedQuery(
            applied: parsed.applied, suggested: dedupe(parsed.suggested), typeHint: parsed.typeHint,
            residualText: residualText)
        return index.withScratch { scratch in
            computeAllowed(scratch, scope: effective, parsed: parsed)
            let limit = max(1, context.limit)
            if SearchNormalizer.canonical(residualText).isEmpty {
                var response = SearchResponse(query: text, parsed: parsedQuery)
                response.results = suggestions(scratch, parsed: parsed, limit: limit)
                if parsed.applied.isEmpty { response.recentQueries = Array(context.recentQueries.prefix(10)) }
                return response
            }
            return match(scratch, residual: parsed.residual, parsed: parsed, parsedQuery: parsedQuery, limit: limit)
        }
    }

    private func dedupe(_ filters: [SearchFilter]) -> [SearchFilter] {
        var seen: Set<SearchEntityID> = []
        return filters.filter { seen.insert($0.entity).inserted }
    }

    private func computeAllowed(_ scratch: SearchScratch, scope: SearchScope, parsed: Parsed) {
        var companies = Set(parsed.companyDocs.flatMap { operatorRefs(of: $0) })
        var lines = Set(parsed.lineDocs.flatMap { lineRefs(of: $0) })
        var missingConstraint = false
        for id in context.operatorIDs {
            if let ref = index.operatorTable.firstIndex(of: id) { companies.insert(UInt32(ref)) } else { missingConstraint = true }
        }
        for id in context.lineIDs {
            if let ref = index.lineTable.firstIndex(of: id) { lines.insert(UInt32(ref)) } else { missingConstraint = true }
        }
        if missingConstraint && companies.isEmpty && lines.isEmpty {
            for d in 0..<index.count { scratch.allowed[d] = false }
            return
        }
        for d in 0..<index.count {
            var ok = scope.contains(kind: index.kinds[d])
            if ok, !companies.isEmpty {
                ok = false
                for r in Int(index.operatorRefStart[d])..<Int(index.operatorRefStart[d + 1])
                where companies.contains(index.operatorRefs[r]) { ok = true; break }
            }
            if ok, !lines.isEmpty {
                ok = false
                for r in Int(index.lineRefStart[d])..<Int(index.lineRefStart[d + 1])
                where lines.contains(index.lineRefs[r]) { ok = true; break }
            }
            scratch.allowed[d] = ok
        }
    }

    // MARK: Relevance

    private struct Signals {
        var recent: [Int32: Int] = [:]
        var rides: [Int32: Int] = [:]
    }

    private func signals() -> Signals {
        var s = Signals()
        for (position, entity) in context.recentPicks.prefix(30).enumerated() {
            if let doc = index.docByEntity[entity], s.recent[doc] == nil { s.recent[doc] = position }
        }
        for (entity, count) in context.rideCounts where count > 0 {
            if let doc = index.docByEntity[entity] { s.rides[doc, default: 0] += count }
        }
        return s
    }

    /// 0…190: importance, the user's history, and the visible map area.
    private func relevance(_ doc: Int32, _ s: Signals) -> Float {
        let d = Int(doc)
        var score = index.importance[d] * 50
        if let position = s.recent[doc] { score += 80 * (1 - Float(position) / 30) }
        if let rides = s.rides[doc] { score += min(40, 14 * log2(1 + Float(rides))) }
        if let rect = context.visibleRegion, !index.latitudes[d].isNaN {
            let lat = Double(index.latitudes[d]), lon = Double(index.longitudes[d])
            if rect.contains(latitude: lat, longitude: lon) {
                score += 20
            } else {
                let latSpan = max(0.01, rect.maxLatitude - rect.minLatitude)
                let lonSpan = max(0.01, rect.maxLongitude - rect.minLongitude)
                let dLat = max(0, max(rect.minLatitude - lat, lat - rect.maxLatitude)) / latSpan
                let dLon = max(0, max(rect.minLongitude - lon, lon - rect.maxLongitude)) / lonSpan
                score += Float(20 * max(0, 1 - max(dLat, dLon) / 3))
            }
        }
        return score
    }

    // MARK: Matching

    private static func baseScore(_ hit: SearchMatching.Hit, _ record: SearchIndex.KeyRecord, queryLength: Int) -> Float {
        var score: Float
        switch hit.kind {
        case .exact: score = 1000
        case .prefix: score = 800
        case .substring: score = 600
        default: score = 450 - 100 * Float(hit.distance) - (hit.prefixFuzzy ? 40 : 0)
        }
        switch record.source {
        case .name: score += 30
        case .code: score += 25
        case .alias, .reading: score += 20
        case .romaji: score += 15
        }
        let extra = Int(record.length) - queryLength
        if hit.kind == .prefix || hit.kind == .substring { score -= min(40, Float(max(0, extra)) * 4) }
        if hit.kind == .substring { score -= min(20, Float(hit.position) * 2) }
        return score
    }

    private func match(
        _ scratch: SearchScratch, residual: [String], parsed: Parsed, parsedQuery: SearchParsedQuery, limit: Int
    ) -> SearchResponse {
        let residualText = residual.joined(separator: " ")
        let qc = SearchNormalizer.canonical(residualText)
        let ql = SearchNormalizer.loose(fromCanonical: qc, profile: index.profile) ?? []
        let tokenKeys: [[UInt16]] = residual.count > 1
            ? Array(residual.prefix(12).map { SearchNormalizer.canonical($0) }.filter { !$0.isEmpty }) : []
        let tokenLoose: [[UInt16]] = tokenKeys.map { SearchNormalizer.loose(fromCanonical: $0, profile: index.profile) ?? [] }
        let allTokens: UInt16 = tokenKeys.isEmpty ? 0 : UInt16((1 << tokenKeys.count) - 1)
        let qcMask = SearchMatching.mask(qc), qlMask = SearchMatching.mask(ql)
        var cancelled = false

        qc.withUnsafeBufferPointer { qcBuf in
        ql.withUnsafeBufferPointer { qlBuf in
        index.units.withUnsafeBufferPointer { arena in
        index.keys.withUnsafeBufferPointer { keys in
            let budgetCanonical = SearchMatching.budget(qcBuf, loose: false)
            let budgetLoose = SearchMatching.budget(qlBuf, loose: true)
            for k in 0..<keys.count {
                if k & 4095 == 0, Task.isCancelled { cancelled = true; return }
                let record = keys[k]
                let doc = Int(record.doc)
                guard scratch.allowed[doc] else { continue }
                let key = UnsafeBufferPointer(rebasing: arena[Int(record.start)..<(Int(record.start) + Int(record.length))])
                let loose = record.isLoose
                let q = loose ? qlBuf : qcBuf
                if q.count > 0 {
                    let budget = record.noFuzzy ? 0 : (loose ? budgetLoose : budgetCanonical)
                    if let hit = SearchMatching.compare(
                        q, qMask: loose ? qlMask : qcMask, key, keyMask: record.mask, budget: budget, rows: scratch.rows) {
                        let score = Self.baseScore(hit, record, queryLength: q.count)
                        if score > scratch.bestScore[doc] {
                            if scratch.bestKey[doc] < 0 && scratch.tokenMask[doc] == 0 { scratch.touched.append(Int32(doc)) }
                            scratch.bestScore[doc] = score
                            scratch.bestKey[doc] = Int32(k)
                            scratch.bestHit[doc] = hit
                        }
                    }
                }
                if allTokens != 0 {
                    var bits: UInt16 = 0
                    for (t, token) in (loose ? tokenLoose : tokenKeys).enumerated() where !token.isEmpty {
                        if Self.contains(key, token) { bits |= 1 << UInt16(t) }
                    }
                    if bits != 0 {
                        if scratch.bestKey[doc] < 0 && scratch.tokenMask[doc] == 0 { scratch.touched.append(Int32(doc)) }
                        if scratch.bestKey[doc] < 0 { scratch.bestKey[doc] = Int32(k) }
                        scratch.tokenMask[doc] |= bits
                    }
                }
            }
        }}}}
        if cancelled { return SearchResponse(query: text, parsed: parsedQuery) }

        let signals = signals()
        var ranked: [(doc: Int32, score: Float, hit: SearchMatching.Hit)] = []
        ranked.reserveCapacity(scratch.touched.count)
        for doc in scratch.touched {
            let d = Int(doc)
            var hit = scratch.bestHit[d]
            var score = scratch.bestScore[d]
            if allTokens != 0, scratch.tokenMask[d] == allTokens, hit == nil || hit!.kind == .fuzzy {
                hit = SearchMatching.Hit(kind: .substring, distance: 0, position: 0, prefixFuzzy: false)
                score = 560
            }
            guard let hit, scratch.bestKey[d] >= 0 else { continue }
            ranked.append((doc, score + relevance(doc, signals), hit))
        }
        ranked.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            let lt = index.titles[Int(lhs.doc)], rt = index.titles[Int(rhs.doc)]
            if lt.count != rt.count { return lt.count < rt.count }
            return lt < rt
        }

        var results: [SearchResult] = []
        results.reserveCapacity(min(limit, ranked.count))
        for entry in ranked.prefix(limit) {
            let record = index.keys[Int(scratch.bestKey[Int(entry.doc)])]
            results.append(result(entry.doc, record: record, hit: entry.hit, score: entry.score,
                                  queryLength: record.isLoose ? ql.count : qc.count))
        }

        var response = SearchResponse(query: text, parsed: parsedQuery, results: results)
        let solid = ranked.lazy.filter { $0.hit.kind != .fuzzy }.prefix(3).count
        let hasExact = ranked.contains { $0.hit.kind == .exact }
        if solid < 3, !hasExact, let best = ranked.filter({ $0.hit.kind == .fuzzy })
            .min(by: { ($0.hit.distance, -$0.score) < ($1.hit.distance, -$1.score) }) {
            let title = index.titles[Int(best.doc)]
            if SearchNormalizer.canonical(title) != qc {
                let kept = parsed.applied.map(\.sourceText)
                response.didYouMean = SearchCorrection(
                    text: (kept + [title]).joined(separator: " "),
                    entity: SearchEntityID(kind: index.kinds[Int(best.doc)], id: index.ids[Int(best.doc)]))
            }
        }
        return response
    }

    @inline(__always)
    private static func contains(_ key: UnsafeBufferPointer<UInt16>, _ token: [UInt16]) -> Bool {
        let n = token.count, m = key.count
        guard n > 0, n <= m else { return false }
        var start = 0
        while start <= m - n {
            if key[start] == token[0] {
                var equal = true
                for i in 1..<n where token[i] != key[start + i] { equal = false; break }
                if equal { return true }
            }
            start += 1
        }
        return false
    }

    private func result(
        _ doc: Int32, record: SearchIndex.KeyRecord, hit: SearchMatching.Hit, score: Float, queryLength: Int
    ) -> SearchResult {
        let d = Int(doc)
        let matched = index.nameText(record.name)
        let match = SearchMatch(
            kind: hit.kind, source: record.source, matchedText: matched,
            highlights: Self.highlights(matched, record: record, hit: hit, queryLength: queryLength,
                                        profile: index.profile),
            editDistance: hit.distance, alias: record.aliasKind)
        return makeResult(d, match: match, score: score)
    }

    private func makeResult(_ d: Int, match: SearchMatch, score: Float) -> SearchResult {
        SearchResult(
            entity: SearchEntityID(kind: index.kinds[d], id: index.ids[d]), title: index.titles[d], match: match,
            score: Double(score), lineIDs: index.lineIDs(d), operatorIDs: index.operatorIDs(d),
            stationID: index.stationIDs[d], complexID: index.complexIDs[d],
            latitude: index.latitudes[d].isNaN ? nil : Double(index.latitudes[d]),
            longitude: index.longitudes[d].isNaN ? nil : Double(index.longitudes[d]))
    }

    /// UTF-16 ranges of `text` covered by the match.
    static func highlights(
        _ text: String, record: SearchIndex.KeyRecord, hit: SearchMatching.Hit, queryLength: Int,
        profile: SearchNormalizer.Profile = .japanese
    ) -> [Range<Int>] {
        let length = Int(record.length)
        let whole = 0..<text.utf16.count
        if record.isLoose {
            switch hit.kind {
            case .exact: return [whole]
            case .fuzzy where !hit.prefixFuzzy: return [whole]
            case .prefix, .fuzzy:
                var prefix = ""
                for character in text {
                    prefix.append(character)
                    let key = SearchNormalizer.loose(
                        fromCanonical: SearchNormalizer.canonical(prefix), profile: profile) ?? []
                    if key.count >= queryLength { return [0..<prefix.utf16.count] }
                }
                return [whole]
            default: return []
            }
        }
        var offsets: [Range<Int>] = []
        _ = SearchNormalizer.canonical(text, offsets: &offsets)
        guard offsets.count == length, length > 0 else { return [] }
        let range: Range<Int>
        switch hit.kind {
        case .prefix: range = 0..<min(length, queryLength)
        case .substring: range = hit.position..<min(length, hit.position + queryLength)
        case .fuzzy where hit.prefixFuzzy: range = 0..<min(length, queryLength)
        default: range = 0..<length
        }
        guard !range.isEmpty else { return [] }
        return [offsets[range.lowerBound].lowerBound..<offsets[range.upperBound - 1].upperBound]
    }

    // MARK: Empty query

    private func suggestions(_ scratch: SearchScratch, parsed: Parsed, limit: Int) -> [SearchResult] {
        let s = signals()
        func plain(_ d: Int, _ kind: SearchMatchKind, _ score: Float) -> SearchResult {
            makeResult(d, match: SearchMatch(kind: kind, source: .name, matchedText: index.titles[d]), score: score)
        }
        if !parsed.companyDocs.isEmpty || !parsed.lineDocs.isEmpty {
            // Browse what the filter selects: the filter entities first, then members by relevance.
            // A member whose own name carries the filter word ("京王八王子" for 京王) ranks as that match.
            let words = parsed.applied.map { SearchTextQuery($0.sourceText) }
            var ranked: [(Int, Float, SearchMatch?)] = []
            for d in 0..<index.count where scratch.allowed[d] {
                let kindRank: Float = switch index.kinds[d] {
                case .company: 0
                case .line: 1
                default: 2
                }
                var score = 1000 - kindRank * 300 + relevance(Int32(d), s)
                // The most specific filter leads: the line when one is set, else the company.
                if parsed.lineDocs.contains(Int32(d)) { score += 1500 }
                if parsed.lineDocs.isEmpty, parsed.companyDocs.contains(Int32(d)) { score += 1000 }
                var named: SearchMatch?
                for word in words {
                    if let hit = word.match(index.titles[d], allowFuzzy: false), named == nil || hit.kind < named!.kind {
                        named = hit
                    }
                }
                if let named { score += named.kind == .exact ? 250 : (named.kind == .prefix ? 200 : 150) }
                ranked.append((d, score, named))
            }
            ranked.sort { $0.1 != $1.1 ? $0.1 > $1.1 : index.titles[$0.0] < index.titles[$1.0] }
            return ranked.prefix(limit).map { entry in
                if let named = entry.2 { return makeResult(entry.0, match: named, score: entry.1) }
                return plain(entry.0, .browse, entry.1)
            }
        }
        var results: [SearchResult] = []
        var seen: Set<Int32> = []
        for (position, entity) in context.recentPicks.enumerated() where results.count < limit {
            guard let doc = index.docByEntity[entity], scratch.allowed[Int(doc)], seen.insert(doc).inserted else { continue }
            results.append(plain(Int(doc), .recent, 3000 - Float(position)))
        }
        let frequent = s.rides.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        for (doc, count) in frequent where results.count < limit {
            guard scratch.allowed[Int(doc)], seen.insert(doc).inserted else { continue }
            results.append(plain(Int(doc), .frequent, 2000 + Float(min(count, 999))))
        }
        if results.count < min(limit, 10), let rect = context.visibleRegion {
            var nearby: [(Int, Float)] = []
            for d in 0..<index.count where scratch.allowed[d] && index.kinds[d] == .station && !seen.contains(Int32(d)) {
                guard !index.latitudes[d].isNaN,
                      rect.contains(latitude: Double(index.latitudes[d]), longitude: Double(index.longitudes[d]))
                else { continue }
                nearby.append((d, index.importance[d]))
            }
            nearby.sort { $0.1 != $1.1 ? $0.1 > $1.1 : index.titles[$0.0] < index.titles[$1.0] }
            for (d, importance) in nearby.prefix(min(limit, 10) - results.count) {
                results.append(plain(d, .browse, 1000 + importance))
            }
        }
        return results
    }
}
