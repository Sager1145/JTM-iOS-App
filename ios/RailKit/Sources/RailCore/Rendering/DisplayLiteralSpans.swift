import Foundation

/// Explicit display approximations, independent of physical track or station identity.
public enum DisplayLiteralSpans {
    public struct SourceSpan: Sendable, Equatable {
        public let intervalIndex: Int
        public let sourceEdgeIndex: Int
        public let witnesses: [Coordinate]
        /// Nil retains the original literal-v1 interpolation.
        public let mode: String?
    }

    /// Bound to the caller's actual joined coordinate chain, before projection.
    public struct Span: Decodable, Sendable, Equatable {
        public let edgeIndex: Int
        public let witnesses: [Coordinate]
        public let mode: String?

        public init(edgeIndex: Int, witnesses: [Coordinate], mode: String? = nil) {
            self.edgeIndex = edgeIndex
            self.witnesses = witnesses
            self.mode = mode
        }

        public init(from decoder: any Decoder) throws {
            var row = try decoder.unkeyedContainer()
            edgeIndex = try row.decode(Int.self)
            let pairs = try row.decode([[Double]].self)
            if row.isAtEnd { mode = nil }
            else { mode = try row.decode(String.self) }
            guard edgeIndex >= 0, row.isAtEnd, (mode == nil || mode == "source-corners-v1"), pairs.count == 4,
                  pairs.allSatisfy({ DisplayLiteralSpans.validPair($0) }) else {
                throw DecodingError.dataCorruptedError(in: row, debugDescription: "Invalid literal display footprint")
            }
            witnesses = pairs.map { Coordinate(lon: $0[0], lat: $0[1]) }
        }
    }

    struct RawDeclaration: Decodable {
        var contract: String
        var spans: [RawSpan]
        private enum CodingKeys: String, CodingKey { case contract, spans }
        init(from decoder: any Decoder) throws {
            let row = try decoder.container(keyedBy: CodingKeys.self)
            contract = (try? row.decode(String.self, forKey: .contract)) ?? ""
            spans = ((try? row.decode([Lossy<RawSpan>].self, forKey: .spans)) ?? []).compactMap(\.value)
        }
    }

    struct RawSpan: Decodable {
        var intervalIndex: Int
        var sourceEdgeIndex: Int
        var endpoints: [[Double]]
    }

    private struct Lossy<Value: Decodable>: Decodable {
        let value: Value?
        init(from decoder: any Decoder) throws { value = try? Value(from: decoder) }
    }

    private static func validPair(_ pair: [Double]) -> Bool {
        pair.count == 2 && pair[0].isFinite && pair[1].isFinite
            && (-180...180).contains(pair[0]) && (-90...90).contains(pair[1])
    }

    /// Uses the original arrays: compacting malformed coordinates cannot create authority.
    static func admit(
        _ declaration: RawDeclaration?, rawIntervals: [String: [[Double]]], segmentCount: Int,
        stations: [CompactPackage.Station], aliases: [String: Coordinate], branchEndpoints: [Coordinate]
    ) -> [SourceSpan] {
        guard let declaration, ["display-literal-spans-v1", "display-source-corners-v1"].contains(declaration.contract) else { return [] }
        let mode: String? = declaration.contract == "display-source-corners-v1" ? "source-corners-v1" : nil
        let protected = stations.map(\.coordinate) + stations.compactMap { aliases[$0.id] } + branchEndpoints
        let sourceArrays = rawIntervals.compactMap { key, points -> [[Double]]? in
            guard let index = Int(key), index >= 0, index < segmentCount else { return nil }
            return points
        }
        var admitted: [SourceSpan] = []
        for span in declaration.spans {
            let index = span.sourceEdgeIndex
            guard span.intervalIndex >= 0, span.intervalIndex < segmentCount,
                  let source = rawIntervals[String(span.intervalIndex)], index >= 1,
                  source.count >= 4, index < source.count - 2, span.endpoints.count == 2,
                  span.endpoints.allSatisfy({ validPair($0) }), span.endpoints[0] != span.endpoints[1],
                  source[index] == span.endpoints[0], source[index + 1] == span.endpoints[1]
            else { continue }
            let rawFootprint = Array(source[(index - 1)...(index + 2)])
            guard rawFootprint.allSatisfy({ validPair($0) }) else { continue }
            let footprint = rawFootprint.map { Coordinate(lon: $0[0], lat: $0[1]) }
            guard Set(footprint).count == 4,
                  !footprint.contains(where: { protected.contains($0) }) else { continue }
            let occurrences = sourceArrays.reduce(0) { total, points in
                guard points.count > 1 else { return total }
                return total + (0..<(points.count - 1)).filter { i in
                    (points[i] == span.endpoints[0] && points[i + 1] == span.endpoints[1])
                        || (points[i] == span.endpoints[1] && points[i + 1] == span.endpoints[0])
                }.count
            }
            guard occurrences == 1 else { continue }
            admitted.append(SourceSpan(intervalIndex: span.intervalIndex,
                                       sourceEdgeIndex: index, witnesses: footprint, mode: mode))
        }
        return admitted.enumerated().compactMap { offset, span in
            let conflict = admitted.enumerated().contains { other, candidate in
                other != offset && candidate.intervalIndex == span.intervalIndex
                    && abs(candidate.sourceEdgeIndex - span.sourceEdgeIndex) <= 3
            }
            return conflict ? nil : span
        }
    }

    public static func resolve(_ line: CompactPackage.Line, parts: [[Coordinate]]) -> [[Span]] {
        var resolved = Array(repeating: [Span](), count: parts.count)
        for source in line.displayLiteralSpans {
            let footprint = source.witnesses
            guard footprint.count == 4, uniquelyOwned(footprint, in: parts),
                  pairOccurrences(footprint[1], footprint[2], in: parts) == 1 else { continue }
            var matches: [(Int, Int)] = []
            for (partIndex, part) in parts.enumerated() where part.count >= 6 {
                for start in 1..<(part.count - 4) where Array(part[start..<(start + 4)]) == footprint {
                    matches.append((partIndex, start + 1))
                }
            }
            guard matches.count == 1, let match = matches.first else { continue }
            resolved[match.0].append(Span(edgeIndex: match.1, witnesses: footprint, mode: source.mode))
        }
        return resolved.map { spans in
            spans.enumerated().compactMap { index, span in
                spans.enumerated().contains(where: { other, candidate in
                    other != index && abs(candidate.edgeIndex - span.edgeIndex) <= 3
                }) ? nil : span
            }.sorted { $0.edgeIndex < $1.edgeIndex }
        }
    }

    private static func pairOccurrences(_ a: Coordinate, _ b: Coordinate, in parts: [[Coordinate]]) -> Int {
        parts.reduce(0) { total, part in
            guard part.count > 1 else { return total }
            return total + (0..<(part.count - 1)).filter { index in
                (part[index] == a && part[index + 1] == b) || (part[index] == b && part[index + 1] == a)
            }.count
        }
    }

    private static func uniquelyOwned(_ witnesses: [Coordinate], in parts: [[Coordinate]]) -> Bool {
        guard Set(witnesses).count == witnesses.count else { return false }
        for witness in witnesses {
            var found = false
            for part in parts {
                for point in part where point == witness {
                    if found { return false }
                    found = true
                }
            }
            if !found { return false }
        }
        return true
    }

    /// The witnesses must match this exact representation, including its packing/datum.
    public static func projected(
        _ spans: [Span], coordinates: [Coordinate], project: (Coordinate) -> ContinuousStroke.Point
    ) -> [ContinuousStroke.LiteralSpan] {
        let valid = spans.filter { span in
            let index = span.edgeIndex
            return (span.mode == nil || span.mode == "source-corners-v1") && coordinates.count >= 6 && index >= 2 && index < coordinates.count - 3
                && span.witnesses.count == 4 && uniquelyOwned(span.witnesses, in: [coordinates])
                && Array(coordinates[(index - 1)...(index + 2)]) == span.witnesses
                && pairOccurrences(span.witnesses[1], span.witnesses[2], in: [coordinates]) == 1
        }
        return valid.enumerated().compactMap { index, span in
            guard !valid.enumerated().contains(where: { other, candidate in
                other != index && abs(candidate.edgeIndex - span.edgeIndex) <= 3
            }) else { return nil }
            return ContinuousStroke.LiteralSpan(edgeIndex: span.edgeIndex,
                                                witnesses: span.witnesses.map(project), mode: span.mode)
        }
    }
}
