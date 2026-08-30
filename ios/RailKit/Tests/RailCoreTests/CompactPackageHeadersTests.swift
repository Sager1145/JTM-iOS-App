import Foundation
import Testing

@testable import RailCore

/// The header decoder answers what the full decoder answers.
///
/// `CompactPackage.Headers` exists because the launch badge index reads six
/// strings per railway and was taking every coordinate in the country to get
/// them — 234.6 ms for Japan against 29.4 ms, measured in `ios/tools/bench`.
/// A second decoder over a cross-language data contract is exactly the kind of
/// thing that drifts, so it is held here to the one the parity suites already
/// check, over every package this repository ships and field by field.
///
/// Two spellings are in play, as they are for the full decoder: `logo` and
/// `isLoop` are written by the builders as the number `1` and by the port
/// fixtures' synthetic packages as `true`. Both decoders restate the
/// truthiness rule because they key on different `CodingKeys` types, so both
/// spellings are exercised below rather than assumed to agree.
struct CompactPackageHeadersTests {

    /// Every country, every line, every field.
    @Test(
        "the header decode equals the full decode",
        arguments: ["mo", "hk", "tw", "kr", "ca", "jp", "us"])
    func matchesTheFullDecode(country: String) throws {
        let url = try PortFixtures.repositoryRoot()
            .appending(path: "app/public/rail/\(country)-2025.json")
        let headers = try CompactPackage.Headers.load(contentsOf: url)
        let full = try PortFixtures.package(country: country)

        #expect(
            headers.lines.count == full.lines.count,
            "\(country): the header decode sees a different number of railways")

        for (header, line) in zip(headers.lines, full.lines) {
            #expect(header.id == line.id)
            #expect(header.name == line.name, "\(country) \(line.id): name")
            #expect(header.nameRoma == line.nameRoma, "\(country) \(line.id): nameRoma")
            #expect(header.operator == line.operator, "\(country) \(line.id): operator")
            #expect(
                header.operatorShort == line.operatorShort,
                "\(country) \(line.id): operatorShort")
            #expect(
                header.operatorLogo == line.operatorLogo,
                "\(country) \(line.id): operatorLogo")
            #expect(header.kind == line.kind, "\(country) \(line.id): kind")
            #expect(header.rank == line.rank, "\(country) \(line.id): rank")
            #expect(header.color == line.color, "\(country) \(line.id): color")
            #expect(header.colorDark == line.colorDark, "\(country) \(line.id): colorDark")
            #expect(header.hasLogo == line.hasLogo, "\(country) \(line.id): logo")
            #expect(header.isLoop == line.isLoop, "\(country) \(line.id): isLoop")
            #expect(header.lineCode == line.lineCode, "\(country) \(line.id): lineCode")
            #expect(header.nameNorm == line.nameNorm, "\(country) \(line.id): nameNorm")
        }
    }

    /// The projection a caller holding a full package uses is the same value.
    ///
    /// This is what keeps the badge index one piece of code rather than two:
    /// the app reaches it through `Headers.load`, anything already holding a
    /// package reaches it through `CompactPackage.headers`, and neither may
    /// produce a line the other would not.
    @Test("the projection from a decoded package equals the header decode")
    func projectionAgrees() throws {
        let url = try PortFixtures.repositoryRoot()
            .appending(path: "app/public/rail/tw-2025.json")
        let decoded = try CompactPackage.Headers.load(contentsOf: url)
        let projected = try PortFixtures.package(country: "tw").headers

        #expect(decoded.lines.count == projected.lines.count)
        for (left, right) in zip(decoded.lines, projected.lines) {
            #expect(left.id == right.id)
            #expect(left.name == right.name)
            #expect(left.nameNorm == right.nameNorm)
            #expect(left.operator == right.operator)
            #expect(left.operatorLogo == right.operatorLogo)
            #expect(left.hasLogo == right.hasLogo)
            #expect(left.isLoop == right.isLoop)
            #expect(left.rank == right.rank)
            #expect(left.color == right.color)
        }
    }

    /// The boolean spelling, which no shipped package uses and every synthetic
    /// fixture does. The full decoder accepts both; so must this one, or the
    /// two disagree on precisely the input that has no coordinates to hide
    /// behind.
    @Test("logo and isLoop decode from true as well as from 1")
    func bothFlagSpellings() throws {
        let json = Data(
            """
            {"format":"compact-v1","version":"1","country":"zz","lines":[
              {"id":"zz-a-one","name":"One","rank":1,"logo":1,"isLoop":1,
               "stations":[],"segments":[]},
              {"id":"zz-a-two","name":"Two","rank":2,"logo":true,"isLoop":true,
               "stations":[],"segments":[]},
              {"id":"zz-a-three","name":"Three","rank":3,
               "stations":[],"segments":[]}
            ]}
            """.utf8)
        let headers = try JSONDecoder().decode(CompactPackage.Headers.self, from: json)
        let full = try JSONDecoder().decode(CompactPackage.self, from: json)

        #expect(headers.lines.map(\.hasLogo) == [true, true, false])
        #expect(headers.lines.map(\.isLoop) == [true, true, false])
        #expect(headers.lines.map(\.hasLogo) == full.lines.map(\.hasLogo))
        #expect(headers.lines.map(\.isLoop) == full.lines.map(\.isLoop))
    }

    /// A line whose `stations` and `segments` are absent still decodes.
    ///
    /// Not a shape any builder writes, and that is the point: the header
    /// decoder must not carry a dependency on the two keys it exists to skip,
    /// or it would fail on exactly the trimmed input someone would reach for
    /// when testing it.
    @Test("a line with no geometry keys still decodes as a header")
    func geometryIsNotRequired() throws {
        let json = Data(
            """
            {"format":"compact-v1","version":"1","country":"zz","lines":[
              {"id":"zz-a-one","name":"One","rank":1,"nameNorm":"1"}
            ]}
            """.utf8)
        let headers = try JSONDecoder().decode(CompactPackage.Headers.self, from: json)
        #expect(headers.lines.count == 1)
        #expect(headers.lines[0].nameNorm == "1")
        #expect(headers.lines[0].hasLogo == false)
    }
}
