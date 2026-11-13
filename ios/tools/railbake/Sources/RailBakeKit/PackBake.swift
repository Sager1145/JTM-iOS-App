import CryptoKit
import Foundation
import RailCore

/// The whole of one `RailBake` run for one region: builder directory in, `.railpack` bytes out.
public enum PackBake {

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case missing(String)
        case displayHashMismatch(topology: String, actual: String)
        case datumNotForRegion(String)
        case badLevels(String)

        public var description: String {
            switch self {
            case .missing(let name): "builder output has no \(name)"
            case .displayHashMismatch(let topology, let actual):
                "topology.bin was built for display blob \(topology), but the blob is \(actual)"
            case .datumNotForRegion(let region): "\(region) has no GCJ-02 variant"
            case .badLevels(let text): "cannot read --levels \(text)"
            }
        }
    }

    /// The default ladder's half-zoom indices, `k = 8...34`.
    public static let defaultLevels = Array(8...34)

    /// `8...34`, `8-34`, or a comma list `8,12,20`; ascending and distinct. `k` is twice the zoom.
    public static func parseLevels(_ text: String) throws -> [Int] {
        let bad = Failure.badLevels(text)
        let separators = ["...", "-"]
        for separator in separators where text.contains(separator) {
            let ends = text.components(separatedBy: separator)
            guard ends.count == 2, let low = Int(ends[0]), let high = Int(ends[1]), low <= high, low >= 0 else { throw bad }
            return Array(low...high)
        }
        let values = try text.split(separator: ",").map { part -> Int in
            guard let value = Int(part), value >= 0 else { throw bad }
            return value
        }
        guard !values.isEmpty, zip(values, values.dropFirst()).allSatisfy({ $0 < $1 }) else { throw bad }
        return values
    }

    public static func ladder(levels: [Int]) throws -> RailPackLadder {
        try RailPackLadder(zooms: levels.map { Double($0) / 2 })
    }

    public static func hex(_ text: String) -> [UInt8]? {
        guard text.count == 64 else { return nil }
        var bytes: [UInt8] = []
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            guard let byte = UInt8(text[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return bytes
    }

    public static func sha256(of url: URL) throws -> [UInt8] {
        Array(SHA256.hash(data: try Data(contentsOf: url, options: .alwaysMapped)))
    }

    /// Bakes `region` of `directory` at `levels` and returns the pack bytes. Deterministic: the
    /// same directory, levels, datum and `inputsSHA256` give the same bytes.
    public static func bake(
        region: String, directory: URL, datum: DisplayInput.Datum, levels: [Int], inputsSHA256: [UInt8],
        progress: ((Int, Int) -> Void)? = nil
    ) throws -> Data {
        if datum == .gcj02, !GCJ02.candidateRegions.contains(region) { throw Failure.datumNotForRegion(region) }
        let topologyURL = directory.appending(path: "\(region).topology.bin")
        guard FileManager.default.fileExists(atPath: topologyURL.path) else { throw Failure.missing("\(region).topology.bin") }
        let topology = try PackTopology.read(from: topologyURL)
        let display = try DisplayInput.load(region: region, from: directory, datum: datum)
        let blob = directory.appending(path: "\(region).display.bin")
        let actual = try sha256(of: blob)
        guard actual == topology.displaySHA256 else {
            throw Failure.displayHashMismatch(
                topology: topology.displaySHA256.map { String(format: "%02x", $0) }.joined(),
                actual: actual.map { String(format: "%02x", $0) }.joined())
        }
        let source = try PackAssembler.assemble(
            region: region, display: display, topology: topology, ladder: ladder(levels: levels), datum: datum,
            inputsSHA256: inputsSHA256, progress: progress)
        return try RailPackWriter.write(source)
    }
}
