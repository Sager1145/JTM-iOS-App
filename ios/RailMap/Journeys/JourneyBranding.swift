import RailCore
import RailPresentation
import SwiftUI

/// A journey's own mark, colour and route wording, resolved once.
///
/// These four answers used to be private computed properties on the journey
/// row, which was fine while the row was the only surface with a logo in it.
/// It is not: the selected-journey card and the pushed detail screen show the
/// same journey, and a reader who taps a row must not find a different mark
/// (or no mark) on the screen it opens. One lookup, three surfaces.
enum JourneyBranding {

    private static func detectedApplies(_ train: Train, detected: [Statistics.TraversedLine]) -> Bool {
        JourneyRouteIdentity.detectedApplies(train, detected: detected)
    }

    /// Passenger-facing route hints — the railways this journey ran over.
    ///
    /// `detected` is what the drawn route actually crossed, walked off the
    /// N02 edge index by ``TraversedLineDetector`` and already unique and in
    /// first-seen order along the path; when ``detectedApplies(_:detected:)``
    /// it supplies the observed legs, while recorded legs remain available
    /// during partial route loading. A through-running record (サンライズ出雲:
    /// 東海道線→山陽線→伯備線→山陰線) must show every railway it crossed
    /// whether or not the import listed it. An ORDINARY service with a
    /// recorded name is the one case detection does not win — see
    /// ``TrainServiceBranding/usesDetectedLines(_:)``. `badges` translates a detected name to the
    /// passenger spelling where N02 files a subway under its administrative
    /// name (``RouteBadgeIndex/passengerName(region:operatorName:lineName:)``);
    /// the extra unique pass is because the map can collapse two N02 lines
    /// (2号線/4号線名城線) into the one 名城線 a rider knows.
    static func lineNames(
        of train: Train, detected: [Statistics.TraversedLine] = [], badges: RouteBadgeIndex? = nil
    ) -> [String] {
        let region = Region.resolved(train).code
        return uniqueNonEmpty(JourneyRouteIdentity.lineNames(of: train, detected: detected).map { name in
            let operatorName = detected.first { $0.name == name }?.operatorName
            return badges?.passengerName(region: region, operatorName: operatorName, lineName: name) ?? name
        })
    }

    /// The operators this journey ran under, spelled the way the source
    /// spells them.
    ///
    /// Two spellings reach the recorded list and both have to stay: a route
    /// section carries the operator's full legal name (`東日本旅客鉄道`)
    /// because that is what the rail package's line ids are built from, and
    /// the itinerary's own `company` field carries the short one
    /// (`JR東日本`). Nothing here shortens either, because ``logoPath(of:in:detected:)``
    /// looks a mark up by this exact string — `lineLogos` is keyed
    /// `jp-東日本旅客鉄道-東北新幹線`, so a list that had already been through
    /// `companyLabel` would find nothing.
    ///
    /// What a reader SEES is ``operatorLabels(of:)``.
    static func operatorNames(
        of train: Train, detected: [Statistics.TraversedLine] = []
    ) -> [String] {
        JourneyRouteIdentity.operatorNames(of: train, detected: detected)
    }

    /// The same operators, as a passenger names them: 「JR東日本」, not
    /// 「東日本旅客鉄道 / JR東日本」.
    ///
    /// `OperatorBranding.companyLabel` is the web app's own shortener — the
    /// four regional label tables, then the legal-suffix strip — so this is
    /// not a second opinion about what a railway is called. It also does the
    /// deduplication that matters: the legal name and the brand name are two
    /// strings for one company, and they collapse to one only AFTER both have
    /// been through the table, which is why the unique pass runs here rather
    /// than on the raw list above.
    static func operatorLabels(
        of train: Train, detected: [Statistics.TraversedLine] = []
    ) -> [String] {
        let labelled = uniqueNonEmpty(JourneyRouteIdentity.operatorLabels(of: train, detected: detected))
        // One more collapse, and it is not the table's job. The table maps a
        // LEGAL name to a short one (京浜急行電鉄 → 京急); a record whose own
        // `company` field is already half-short (京急電鉄, 都営地下鉄) is left
        // exactly as written, and the row then prints 「京急 / 京急電鉄」 —
        // one company, twice, which is the thing the shortening was for. So a
        // label that merely extends another label is dropped in favour of the
        // shorter one, which is the 简称 by definition.
        return labelled.filter { label in
            !labelled.contains { other in other != label && label.hasPrefix(other) }
        }
    }

    /// 「東海道本線 · JR東海」 — the line, then who runs it.
    static func routeText(
        of train: Train, detected: [Statistics.TraversedLine] = [], badges: RouteBadgeIndex? = nil
    ) -> String {
        [lineNames(of: train, detected: detected, badges: badges).joined(separator: " / "),
         operatorLabels(of: train, detected: detected).joined(separator: " / ")]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    /// A limited express wears its dedicated service mark; failing that, its
    /// operator's logo; failing that, the default train glyph. It never falls
    /// back to a line mark. Other trains resolve their railway mark from the
    /// loaded network.
    ///
    /// Route sections carry passenger names rather than internal line ids, so
    /// this used to CONSTRUCT one: `<region>-<operator>-<line>`, which is the
    /// packages' canonical spelling and matches for most railways. It cannot
    /// match for the ones that matter most here. A subway's id is built from
    /// the administrative name (`jp-東京地下鉄-3号線銀座線`) while its `operator`
    /// field and its passenger-facing name are the brand ones (東京メトロ,
    /// 銀座線) — 33 of jp-2025.json's 655 lines carry a passenger `nameNorm`
    /// that differs from the administrative `name`, most of them subways. So
    /// the constructed id missed exactly the lines whose route
    /// symbol is the most recognisable thing about them, and every Tokyo Metro
    /// journey fell through to the one 東京メトロ company badge.
    ///
    /// ``RouteBadgeIndex`` is the loaded package's own answer, keyed by both
    /// spellings of the operator and both of the name. Consulting it is also
    /// what makes this surface agree with the station card, which has always
    /// resolved through the network (`StationDisplay.buildPopupModel`): one
    /// railway, one mark, whichever screen a reader is looking at.
    static func logoPath(
        of train: Train, in badges: RouteBadgeIndex?,
        detected: [Statistics.TraversedLine] = []
    ) -> String? {
        JourneyRouteIdentity.logoPath(
            for: train,
            lineLogo: lineLogoPath(of: train, in: badges, detected: detected),
            operatorLogo: operatorLogoPath(of: train, detected: detected))
    }

    /// The operators a limited express's service mark falls back to when it
    /// has no dedicated logo of its own — never a line mark.
    private static func operatorLogoPath(
        of train: Train, detected: [Statistics.TraversedLine]
    ) -> String? {
        if let logo = JourneyRouteIdentity.operatorLogo(of: train, detected: detected) { return logo }
        let identity = train.region.flatMap { RegistryIdentityCache.identity(forRegion: $0) }
        for operatorName in operatorLogoCandidates(of: train, detected: detected) {
            if let identity,
               let identifier = identity.operatorID(forExactName: operatorName),
               let logo = identity.operatorLogo(identifier) {
                return logo
            }
            if identity == nil || identity?.operatorID(forExactName: operatorName) == nil,
               let logo = OperatorBranding.operatorLogoForAnySpelling(operatorName) {
                return logo
            }
        }
        return nil
    }

    /// Candidate operators for a service mark's fallback, most specific
    /// first: the route sections actually ridden, then the itinerary's own
    /// recorded `company`, then the route policy's alternative operators,
    /// and — only when detection applies to this train at all, see
    /// ``TrainServiceBranding/usesDetectedLines(_:)`` — the operators the drawn route crossed.
    /// Policy sits after `company` rather than before it: `company` is the
    /// record's own claim about who ran the train, while a policy operator
    /// is only a corridor hint that may never have been ridden. This is a
    /// local ordering for the service-logo fallback only — it does not
    /// change ``badgeOperators(of:detected:)``, which the line-logo path
    /// uses and which folds sections/policy together instead of layering
    /// them.
    private static func operatorLogoCandidates(
        of train: Train, detected: [Statistics.TraversedLine]
    ) -> [String] {
        let sectionOperators = (train.routeSections ?? []).flatMap { $0.operatorNames ?? [] }
        let policyOperators = train.routePolicy?.preferredOperatorNames ?? []
        let detectedOperators = detectedApplies(train, detected: detected)
            ? detected.compactMap(\.operatorName) : []
        return uniqueNonEmpty(
            sectionOperators + [train.company].compactMap { $0 } + policyOperators + detectedOperators)
    }

    private static func badgeOperators(
        of train: Train, detected: [Statistics.TraversedLine]
    ) -> [String] {
        uniqueNonEmpty(
            operatorNames(of: train) + (detectedApplies(train, detected: detected)
                ? detected.compactMap(\.operatorName) : []))
    }

    private static func lineLogoPath(
        of train: Train, in badges: RouteBadgeIndex?, detected: [Statistics.TraversedLine]
    ) -> String? {
        let region = Region.resolved(train).code
        // Raw N02 spelling on purpose — `RouteBadgeIndex` is keyed by both
        // spellings of a line's name, so the badge lookup below does not
        // need the passenger translation ``lineNames(of:detected:badges:)``
        // applies for on-screen text.
        let lines = lineNames(of: train, detected: detected)
        let usesDetected = detectedApplies(train, detected: detected)
        // Recorded operators come first: the OPERATOR label a reader sees
        // must stay the record's own answer, not detection's "owns most of
        // the line" — a JR東日本 ride on 東海道線 must pair with JR East's
        // own route mark, not fall through to JR東海. The detected
        // operator is appended only so a record with no usable operator of
        // its own can still find a mark, and only when detection applies to
        // this train at all — see ``TrainServiceBranding/usesDetectedLines(_:)``.
        let operators = badgeOperators(of: train, detected: detected)
        // Km-major, not line-major: the primary railway is the one the
        // journey ran FARTHEST on when detection applies, so an up run and
        // a down run of the same through service wear the same mark
        // regardless of which end of the line they started from. The
        // recorded list's first entry is primary otherwise — an ordinary
        // service with a recorded name, or nothing detected to rank by.
        // Sorted by km descending, stably — ties keep first-seen order —
        // because `sorted` alone is not guaranteed stable and travel order
        // must not leak into the badge choice through an unstable tie-break.
        let badgeLines: [String]
        if usesDetected {
            let kmMajorDetected = detected.enumerated()
                .sorted { ($0.element.km, -$0.offset) > ($1.element.km, -$1.offset) }
                .map(\.element.name)
            // The recorded names come last, not first: a detected line with
            // its own published art must win, but a recorded line with art
            // must still beat falling through to the plain operator mark
            // when nothing detected has art of its own.
            badgeLines = uniqueNonEmpty(kmMajorDetected + lines)
        } else {
            badgeLines = lines
        }
        if let badges {
            for lineName in badgeLines {
                for operatorName in operators {
                    if let hit = badges.logo(
                        region: region, operatorName: operatorName, lineName: lineName) {
                        return hit
                    }
                }
            }
        }
        let lineName = badgeLines.first
        let operatorName = operators.first
        let lineID: String?
        if let lineName, let operatorName {
            lineID = "\(region)-\(operatorName)-\(lineName)"
        } else {
            lineID = nil
        }
        return OperatorBranding.logoForLine(
            OperatorBranding.Line(lineId: lineID, operator: operatorName))
    }

    /// The journey's recorded colour, which is what a mark falls back to.
    static func color(of train: Train) -> Color {
        if let color = train.style?.color, let resolved = Color(hex: color) {
            return resolved
        }
        return Color(hex: TrainValidation.defaultTrainColor) ?? .accentColor
    }

    private static func uniqueNonEmpty(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

