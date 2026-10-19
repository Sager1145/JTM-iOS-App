import RailCore
import RailPresentation
import SwiftUI

/// Which mark each railway in a loaded package wears, under every spelling a
/// recorded journey might name it by.
///
/// One dictionary rather than a search, because the answer is asked for once
/// per drawn row and a journeys list scrolls. It is built where the package is
/// decoded (`RailNetworkStore.decode`) and off the main actor, which is also
/// the only place the package's `logo` flag is in scope.
///
/// The keys are deliberately redundant. A railway is named four ways between
/// the package and an itinerary — the id's administrative operator (東京地下鉄)
/// or the brand one (東京メトロ), crossed with the full name (3号線銀座線) or the
/// passenger one (銀座線) — and a record may carry any pairing of them. Storing
/// all four costs about 2,600 entries for all five countries and removes the
/// entire class of "the mark is right on one screen and wrong on the next".
struct RouteBadgeIndex: Sendable {
    private var pathByKey: [String: String] = [:]
    private struct LineColors: Sendable {
        let light: String
        let dark: String
    }
    private var colorsByKey: [String: LineColors] = [:]
    private var nameByLineID: [String: String] = [:]
    /// The passenger name for a railway whose N02 name is administrative
    /// rather than the one riders know it by — 33 of jp-2025.json's 655
    /// lines, most of them subways, where `nameNorm` (銀座線) and `name`
    /// (3号線銀座線) disagree. `TraversedLineDetector`
    /// walks the N02 edge index and can only ever report `name`; this is
    /// what lets a detected line be SHOWN as the passenger spelling instead.
    private var passengerNameByKey: [String: String] = [:]

    init() {}

    /// Built from the package's line ATTRIBUTES, not from the package.
    ///
    /// Every field read below is a string on a line; not one of them is a
    /// coordinate. Taking the whole package to get them decoded ~394,000
    /// vertices per launch so they could be released again — see
    /// ``CompactPackage/Headers``, which is the same decode eight times
    /// cheaper. `CompactPackage.headers` is the projection a caller that
    /// already holds a full package uses, so both reach this by one route.
    init(region: Region, headers: CompactPackage.Headers) {
        for line in headers.lines {
            nameByLineID[line.id] = line.nameNorm ?? line.name
            guard let color = line.color else { continue }
            let colors = LineColors(light: color, dark: line.colorDark ?? color)
            colorsByKey[line.id] = colors
            let operators = [line.operator, line.operatorShort, Self.operatorComponent(of: line.id)]
                .compactMap { $0 }
            for name in [line.name, line.nameNorm].compactMap({ $0 }) where !name.isEmpty {
                for operatorName in operators where !operatorName.isEmpty {
                    let key = Self.key(region: region.code, operatorName, name)
                    if colorsByKey[key] == nil { colorsByKey[key] = colors }
                }
                let key = Self.key(region: region.code, "", name)
                if colorsByKey[key] == nil { colorsByKey[key] = colors }
            }
        }
        // Two passes, and the order is the point: a railway with its own
        // published art claims a shared key before one that would only bring
        // its operator's company mark to it. 名城線 is in the package twice
        // (2号線 and 4号線) under one passenger name, and the reader should get
        // the route symbol from whichever of the two carries it.
        add(headers: headers, region: region, withPackageArt: true)
        add(headers: headers, region: region, withPackageArt: false)
    }

    private mutating func add(
        headers: CompactPackage.Headers, region: Region, withPackageArt: Bool
    ) {
        for line in headers.lines where line.hasLogo == withPackageArt {
            let packageLogo = line.hasLogo
                ? "/rail/logos/\(StationDisplay.Network.badgeIDForLine(line.id)).png"
                : line.operatorLogo
            guard let logo = OperatorBranding.logoForLine(
                OperatorBranding.Line(
                    lineId: line.id, operator: line.operator, logo: packageLogo))
            else { continue }
            claim(line.id, logo)
            let operators = [line.operator, Self.operatorComponent(of: line.id)]
                .compactMap { $0 }
            let names = [line.name, line.nameNorm].compactMap { $0 }
            for operatorName in operators where !operatorName.isEmpty {
                for name in names where !name.isEmpty {
                    claim(Self.key(region: region.code, operatorName, name), logo)
                }
            }
            if let norm = line.nameNorm, !norm.isEmpty, norm != line.name {
                for operatorName in operators where !operatorName.isEmpty {
                    claimPassengerName(Self.key(region: region.code, operatorName, line.name), norm)
                }
                claimPassengerName(Self.key(region: region.code, "", line.name), norm)
            }
        }
    }

    /// First writer wins, so that package order decides a tie rather than
    /// dictionary order. A split part (`-2`) resolves to its parent's art
    /// anyway, so the loser is the same answer in every case seen today.
    private mutating func claim(_ key: String, _ logo: String) {
        if pathByKey[key] == nil { pathByKey[key] = logo }
    }

    /// Same first-writer rule as ``claim(_:_:)``, kept as its own table
    /// because a name-only key here must not collide with the logo table's
    /// name-only entries — there are none, but the two answers are asked for
    /// independently and merging them would make one dictionary do two jobs.
    private mutating func claimPassengerName(_ key: String, _ name: String) {
        if passengerNameByKey[key] == nil { passengerNameByKey[key] = name }
    }

    mutating func merge(_ other: RouteBadgeIndex) {
        pathByKey.merge(other.pathByKey) { existing, _ in existing }
        passengerNameByKey.merge(other.passengerNameByKey) { existing, _ in existing }
        colorsByKey.merge(other.colorsByKey) { existing, _ in existing }
        nameByLineID.merge(other.nameByLineID) { existing, _ in existing }
    }

    func logo(region: String, operatorName: String, lineName: String) -> String? {
        pathByKey[Self.key(region: region, operatorName, lineName)]
    }

    func logo(lineID: String) -> String? { pathByKey[lineID] }

    func color(lineID: String, dark: Bool) -> String? {
        colorsByKey[lineID].map { dark ? $0.dark : $0.light }
    }

    func lineName(lineID: String) -> String? { nameByLineID[lineID] }

    func color(region: String, operatorName: String?, lineName: String, dark: Bool) -> String? {
        let colors = colorsByKey[Self.key(region: region, operatorName ?? "", lineName)]
        return colors.map { dark ? $0.dark : $0.light }
    }

    /// The passenger name for a detected line, where the N02 name is
    /// administrative — `nil` when the line's own name is already the one a
    /// rider would recognise, which is true for all but 33 of jp-2025.json's
    /// 655 lines, most of them subways.
    func passengerName(region: String, operatorName: String?, lineName: String) -> String? {
        if let operatorName, !operatorName.isEmpty,
           let hit = passengerNameByKey[Self.key(region: region, operatorName, lineName)] {
            return hit
        }
        return passengerNameByKey[Self.key(region: region, "", lineName)]
    }

    /// NUL, for the reason `StationDisplay` gives where it builds its own
    /// composite key: it cannot occur in either half, so no name can forge a
    /// key belonging to a different operator.
    private static func key(region: String, _ operatorName: String, _ line: String) -> String {
        "\(region)\u{0000}\(operatorName)\u{0000}\(line)"
    }

    /// `jp-東京地下鉄-3号線銀座線` → `東京地下鉄`. The country prefix is a fixed
    /// two letters and the rest of the id is the name, so one split at each of
    /// the first two hyphens is the whole rule.
    private static func operatorComponent(of lineID: String) -> String? {
        let parts = lineID.split(separator: "-", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        return String(parts[1])
    }
}

