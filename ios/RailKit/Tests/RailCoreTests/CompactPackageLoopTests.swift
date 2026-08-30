import Foundation
import Testing

@testable import RailCore

/// `isLoop`, from the JSON on disk to the two decisions it makes.
///
/// It was never decoded. `rail-network.js` has read `compactLine.isLoop` since
/// the loops were added, and this side of the port simply did not carry the
/// field — so a circular railway drew one way on the web and another on the
/// device: its first and last stations dressed as termini when a loop has
/// none, and a hop across the seam sliced the long way round the circle.
///
/// Nothing caught it, and the reason is worth writing down. The parity suites
/// build a `StationDisplay.Network` by handing it
/// `loopLineIDs: Set(entry.lines.filter(\.isLoop).map(\.lineId))` — taken from
/// the FIXTURE's expected line table, not from the decoded package — and then
/// compare the network's `isLoop` back against that same fixture. Whatever the
/// decoder answered was never asked. So the tests here drive the flag from the
/// decoder and from nothing else.
///
/// ## Two spellings, both of which ship
///
/// The builders write `1`, and JSON `1` is not a JSON boolean: a synthesised
/// `Bool` decode throws on every line that carries one. The port fixtures'
/// synthetic packages write `true`. The web app asks `compactLine.isLoop ? …`,
/// which is true of the number and of the boolean alike — so the decoder has
/// to accept both, and accepting only one of them is how it first went in and
/// how it failed.
struct CompactPackageLoopTests {

    // MARK: - the two spellings

    /// `1`, which is what every shipped package writes — checked against the
    /// real file rather than a copy of it. 大阪環状線 is the loop everyone
    /// knows; ユーカリが丘線 and ディズニーリゾートライン are the other two in
    /// Japan's package, and the Tōkaidō main line is there to prove the flag
    /// is not simply true for everything.
    @Test("a package's isLoop: 1 decodes as a loop")
    func numericSpelling() throws {
        let japan = try PortFixtures.package(country: "jp")
        let byID = Dictionary(
            japan.lines.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let osakaLoop = try #require(byID["jp-西日本旅客鉄道-大阪環状線"])
        #expect(osakaLoop.isLoop, "大阪環状線 is a loop and the package says so")

        let loops = japan.lines.filter(\.isLoop).map(\.id)
        #expect(loops.count == 3, "Japan ships three loop lines: \(loops)")
        #expect(loops.contains("jp-山万-ユーカリが丘線"))
        #expect(loops.contains("jp-舞浜リゾートライン-ディズニーリゾートライン"))

        let tokaido = try #require(byID["jp-東海旅客鉄道-東海道線"])
        #expect(tokaido.isLoop == false)
    }

    /// The North American packages include audited streetcar loops, while
    /// Canada currently has none.  Use Atlanta Streetcar rather than a
    /// fail-closed system so this decoder test follows the released package
    /// without requiring an unverified alignment to remain published.
    @Test("the North American packages' loops decode too")
    func northAmericanSpelling() throws {
        let unitedStates = try PortFixtures.package(country: "us")
        let loops = unitedStates.lines.filter(\.isLoop)
        #expect(!loops.isEmpty, "the US package ships streetcar loops")
        #expect(loops.contains { $0.id == "metropolitan-atlanta-rapid-t-atlsc" })

        let canada = try PortFixtures.package(country: "ca")
        #expect(canada.lines.contains { !$0.isLoop })
        #expect(canada.lines.allSatisfy { !$0.isLoop }, "no Canadian line closes on itself")
    }

    /// `true`, which is what the port fixtures' synthetic packages write. The
    /// `loop` case in `station-display.json` exists for exactly this field,
    /// and it is the spelling a strict `Bool`-only decoder passes and a strict
    /// `Int`-only decoder throws on.
    @Test("a fixture's isLoop: true decodes as a loop")
    func booleanSpelling() throws {
        let package = try Self.syntheticPackage(named: "loop")
        let loop = try #require(package.lines.first { $0.id == "syn-loop" })
        #expect(loop.isLoop)
        let crossing = try #require(package.lines.first { $0.id == "syn-loop-cross" })
        #expect(crossing.isLoop == false, "a line with no isLoop key at all is not a loop")
    }

    /// `0`, `false` and an absent key are all "not a loop", and the same
    /// lenient reading applies to the other flag stored as a number.
    @Test("every falsy spelling is not a loop")
    func falsySpellings() throws {
        let bare = try Self.line(carrying: nil)
        #expect(try Self.line(carrying: #""isLoop": 1"#).isLoop)
        #expect(try Self.line(carrying: #""isLoop": true"#).isLoop)
        #expect(try Self.line(carrying: #""isLoop": 0"#).isLoop == false)
        #expect(try Self.line(carrying: #""isLoop": false"#).isLoop == false)
        #expect(bare.isLoop == false)
        // `logo` is the other flag the builders write as `1`, and it goes
        // through the same lenient reading for the same reason.
        #expect(try Self.line(carrying: #""logo": 1"#).hasLogo)
        #expect(try Self.line(carrying: #""logo": true"#).hasLogo)
        #expect(bare.hasLogo == false)
    }

    // MARK: - where the flag lands: the terminal markers

    /// A loop has no terminals, and a line that is not a loop has two.
    ///
    /// This is the popup and marker election `StationDisplay` makes, driven
    /// from the DECODER — `loopLineIDs` is built out of the package that was
    /// just parsed, which is what `RailNetworkStore` does and what the parity
    /// fixtures do not.
    ///
    /// The consequence of getting it wrong is not subtle: a terminal keeps the
    /// LINE's own minimum zoom while every other station is thinned by
    /// spacing, so 大阪環状線 was drawing 大阪 and 京橋 as endpoints of a
    /// circle several zoom levels before its other stations appeared.
    @Test("a loop's stations are none of them terminals")
    func loopHasNoTerminals() throws {
        let package = try Self.syntheticPackage(named: "loop")
        let network = StationDisplay.Network(
            package: package,
            loopLineIDs: Set(package.lines.filter(\.isLoop).map(\.id)))

        let loopIndex = try #require(network.lines.firstIndex { $0.lineID == "syn-loop" })
        #expect(network.lines[loopIndex].isLoop)
        let loopStations = network.stations.filter { $0.lineIndex == loopIndex }
        #expect(loopStations.count == 3)
        #expect(loopStations.allSatisfy { !$0.isTerminal })

        let crossIndex = try #require(
            network.lines.firstIndex { $0.lineID == "syn-loop-cross" })
        let crossStations = network.stations.filter { $0.lineIndex == crossIndex }
        #expect(crossStations.count == 2)
        #expect(
            crossStations.allSatisfy { $0.isTerminal },
            "an open line's two ends are terminals")

        // And the flag genuinely drives it: told the same package carries no
        // loops — which is what an undecoded `isLoop` amounted to — the ring's
        // first and last stations become termini of a circle.
        let undecoded = StationDisplay.Network(package: package, loopLineIDs: [])
        let mistaken = undecoded.stations.filter { $0.lineIndex == loopIndex }
        #expect(mistaken.filter(\.isTerminal).count == 2)
    }

    // MARK: - where the flag lands: the drawn slice

    /// A hop across a loop's seam is drawn the short way round.
    ///
    /// `RouteFeature.canonicalLineSlice` may only wrap when the line is a
    /// closed one drawn as a single part. On a genuine loop both arcs are
    /// legal and no geometric test can separate them — through the seam, the
    /// vertex "behind" the start and the one "ahead" of it are the same place
    /// — so the two are measured against the length of the path the solver
    /// actually walked and the nearer one wins. With the flag lost, the wrap
    /// is simply unreachable and the hop is drawn the long way round the
    /// circle: five stations of track for a journey between two neighbours.
    ///
    /// The app-side wire from the package to this flag is
    /// `DisplayNetworkCache.build(country:)`, which has no test target under
    /// it; what is checked here is that the flag is load-bearing, so that a
    /// wire which stopped carrying it changes an answer rather than nothing.
    @Test("a loop slices across its seam, and an open line cannot")
    func loopSlicesAcrossTheSeam() throws {
        let ring = Self.ring
        // The hop: from the west side of the square, anticlockwise past the
        // origin — which is the seam — and a little way along the south side.
        let hop = RouteFeature(
            geometry: .lineString([
                Coordinate(lon: 0, lat: 0.04),
                Coordinate(lon: 0, lat: 0),
                Coordinate(lon: 0.01, lat: 0),
            ]),
            hints: RouteHints(requiredLineNames: ["環"]))

        let closed = RouteNetwork(lines: [Self.line(named: "環", parts: [ring], isLoop: true)])
        let open = RouteNetwork(lines: [Self.line(named: "環", parts: [ring], isLoop: false)])

        let short = try #require(closed.canonicalizeRouteFeature(hop)?.geometry.lines.first)
        let long = try #require(open.canonicalizeRouteFeature(hop)?.geometry.lines.first)

        // Both run between the same two points on the same ring — only the way
        // round differs: the loop takes the 0.05° arc through the seam and the
        // open line is forced the 0.15° way about.
        #expect(short.first == long.first)
        #expect(short.last == long.last)
        #expect(Self.degrees(short) < 0.06)
        #expect(Self.degrees(long) > 0.14)
    }

    // MARK: - fixtures and helpers

    /// A square ring, ~5.5 km on a side, closed: the last vertex repeats the
    /// first, which is what makes the seam a seam.
    private static let ring: [Coordinate] = [
        Coordinate(lon: 0, lat: 0),
        Coordinate(lon: 0.05, lat: 0),
        Coordinate(lon: 0.05, lat: 0.05),
        Coordinate(lon: 0, lat: 0.05),
        Coordinate(lon: 0, lat: 0),
    ]

    private static func line(
        named name: String, parts: [[Coordinate]], isLoop: Bool
    ) -> RouteNetwork.Line {
        RouteNetwork.Line(
            lineId: "syn-\(name)-\(isLoop)", name: name, operator: "試験鉄道",
            isLoop: isLoop, alignmentDirection: nil, parts: parts)
    }

    /// Path length in degrees. The unit does not matter — the two arcs are
    /// being compared with each other, on geometry a degree wide.
    private static func degrees(_ path: [Coordinate]) -> Double {
        guard path.count > 1 else { return 0 }
        var total = 0.0
        for index in 1..<path.count {
            let dx = path[index].lon - path[index - 1].lon
            let dy = path[index].lat - path[index - 1].lat
            total += (dx * dx + dy * dy).squareRoot()
        }
        return total
    }

    /// One line decoded on its own, with the required fields spelled around
    /// whatever flag the case is about. Written as text rather than assembled
    /// from a dictionary because the SPELLING is the subject: `1` and `true`
    /// have to survive as far as the decoder unchanged.
    private static func line(carrying flag: String?) throws -> CompactPackage.Line {
        let json = """
            {"id": "syn", "name": "試験線", "rank": 3,
             "stations": [["S1", "甲", 139.7, 35.68], ["S2", "乙", 139.71, 35.69]],
             "segments": [[1.0, 0, [[139.7, 35.68], [139.71, 35.69]]]]
             \(flag.map { ", \($0)" } ?? "")}
            """
        return try JSONDecoder().decode(CompactPackage.Line.self, from: Data(json.utf8))
    }

    /// One of `station-display.json`'s synthetic packages, decoded through the
    /// real ``CompactPackage`` decoder — which is the point: the fixture is
    /// where the `true` spelling lives.
    private static func syntheticPackage(named key: String) throws -> CompactPackage {
        struct File: Decodable {
            struct Entry: Decodable {
                let key: String
                let package: CompactPackage
            }
            let synthetic: [Entry]
        }
        let file = try PortFixtures.decode(File.self, "station-display.json")
        return try #require(file.synthetic.first { $0.key == key }?.package)
    }
}
