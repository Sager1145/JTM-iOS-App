import RailApplication
import RailCore
import RailPresentation
import SwiftUI

/// The route on screen: the saved route and its repair, the planner's
/// sections and candidates, an applied timetable's stations, closed-line
/// notices, and the direction of travel.
struct EditorRouteSection: View, JourneyEditorLabelling {
    typealias PlannedSection = JourneyEditorView.PlannedSection

    @Environment(AppLocalization.self) var localization
    @Environment(DisplaySettings.self) private var displaySettings: DisplaySettings?
    @Bindable var model: TripDraftModel
    /// The record as the editor opened it.
    let original: Train
    /// Gaps the route status reported for the saved journey; nil when
    /// nothing needs review.
    let reviewGaps: [SectionGap]?

    @State private var trackPairSections: [Int: String] = [:]

    /// Nil when nothing needs repair.
    private var repairGaps: [RouteRepair.Gap]? {
        reviewGaps?.map(RouteRepair.Gap.init)
    }

    var body: some View {
        Section {
            if let timetableTrain = model.timetableTrain {
                timetablePassStations(timetableTrain)
            } else if model.showsRecordRoute {
                recordRouteRows
            } else if model.searching {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(text("searching", fallback: "Searching routes"))
            } else {
                sectionRows
                if let outcome = model.outcome {
                    routeOutcome(outcome)
                }
                historicalNotices
            }
            if let routeProofFailure = model.routeProofFailure {
                Text(routeProofFailure)
                    .railText(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            directionRows
        } header: {
            Text(text("route", fallback: "Route"))
        }
        .id(EditorAnchor.route.rawValue)
        .task(id: trackPairKey) {
            let key = trackPairKey
            guard let package = model.package else { trackPairSections = [:]; return }
            let sections = model.draft.routeSections ?? []
            let offered = await Task.detached(priority: .utility) {
                Self.pairSections(sections, package: package)
            }.value
            guard !Task.isCancelled, key == trackPairKey else { return }
            trackPairSections = offered
        }
    }

    @ViewBuilder private var recordRouteRows: some View {
        // Same derivation as ride detail over the recorded sections (no solve
        // in the editor). Policy-only names keep the "Saved route" caption.
        let sequence = RiddenLineSequence(train: model.draft, continuations: nil)
        let lines = sequence.sections.contains { $0.source == .recorded } ? JourneyLineText.summary(sequence) : ""
        VStack(alignment: .leading, spacing: RailSpacing.s4) {
            Text(lines.isEmpty ? text("savedRoute", fallback: "Saved route") : lines)
                .font(.body.weight(.semibold))
            Text(text("stationCount", fallback: "{count} stations",
                      ["count": .string(String(model.draft.stops.count))]))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if model.draft.routeConfirmation == .pending {
                Text(localization.text("ios.route.pendingConfirmation", fallback: "Route pending confirmation"))
                    .railText(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("newTripSavedRoute")
        trackPreferenceRows
        // ADR 0007 amendment 1: a section drawn from guard-rejected track, in
        // the same per-section notice row as the closed-line notices. The
        // Repair route button below covers it.
        ForEach((reviewGaps ?? []).filter(\.isUnproven), id: \.segmentIndex) { gap in
            sectionNotice(
                title: nil, warning: true,
                message: localization.text("ios.route.unprovenSection", params: [
                    "from": .string(gap.from ?? "?"), "to": .string(gap.to ?? "?"),
                ]))
                .accessibilityIdentifier("newTripUnprovenNotice-\(gap.segmentIndex)")
        }
        // region-connectivity.json: a section between regions whose rail
        // networks do not connect is never planned or saved.
        ForEach(model.regionConflicts, id: \.index) { conflict in
            sectionNotice(
                title: nil, warning: true,
                message: localization.text("ios.editor.regionsNotConnected", params: [
                    "from": .string(regionName(conflict.from)), "to": .string(regionName(conflict.to)),
                ]))
                .accessibilityIdentifier("newTripRegionNotice-\(conflict.index)")
        }
        if model.repair.pause != nil {
            // The paused span is a section like any other: same rows, same map.
            sectionRows
            Button(text("repairSkip", fallback: "Leave this part as it is")) {
                model.skipRepair(text: repairText)
            }
            .accessibilityIdentifier("newTripRepairSkip")
        } else if model.repair.isRunning {
            ProgressView()
                .frame(maxWidth: .infinity)
                .accessibilityLabel(text("repairing", fallback: "Repairing route"))
        } else if repairGaps != nil {
            Button {
                model.startRepair(gaps: repairGaps, text: repairText)
            } label: {
                Label(localization.text("ios.route.repairRoute", fallback: "Repair route"),
                      systemImage: "wrench.and.screwdriver")
                    .frame(maxWidth: .infinity, minHeight: RailSize.touch, alignment: .leading)
            }
            .disabled(model.package == nil)
            .accessibilityIdentifier("newTripRepairRoute")
        }
        if let summary = model.repair.summary {
            Text(summary)
                .railText(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("newTripRepairSummary")
        }
    }

    /// What decides whether a saved section offers the track override.
    private struct TrackPairKey: Equatable {
        var sections: [[String?]]
        var loaded: Bool
    }

    private var trackPairKey: TrackPairKey {
        TrackPairKey(
            sections: (model.draft.routeSections ?? []).map {
                [$0.fromN02StationCode, $0.toN02StationCode, $0.lineIDs?.joined(separator: ","),
                 $0.sectionCodes?.joined(separator: ",")]
            },
            loaded: model.package != nil)
    }

    /// Per saved section that accepts the override (`overridablePairs`), the
    /// stretch it covers, so each picker is told apart.
    nonisolated private static func pairSections(_ sections: [RouteSection], package: CompactPackage) -> [Int: String] {
        let catalog = PairedTracks.Catalog.bundled.validated(against: package)
        var result: [Int: String] = [:]
        for (index, section) in sections.enumerated() {
            let pairs = catalog.overridablePairs(for: section, rows: package.lines)
            guard let first = pairs.first else { continue }
            result[index] = "\(first.from.name)–\(first.to.name)"
        }
        return result
    }

    /// One picker per section over a confirmed track pair. Automatic writes nil.
    @ViewBuilder private var trackPreferenceRows: some View {
        let sections = model.draft.routeSections ?? []
        ForEach(trackPairSections.keys.sorted().filter(sections.indices.contains), id: \.self) { index in
            let label = "\(localization.text("ios.editor.track")) (\(trackPairSections[index] ?? ""))"
            Picker(label, selection: trackPreference(at: index)) {
                Text(localization.text("ios.editor.track.automatic")).tag(TrackPreference?.none)
                Text(localization.text("ios.editor.track.up")).tag(TrackPreference?.some(.up))
                Text(localization.text("ios.editor.track.down")).tag(TrackPreference?.some(.down))
            }
            .accessibilityLabel(label)
            .accessibilityIdentifier("rideEditorTrackPreference-\(index)")
        }
    }

    private func trackPreference(at index: Int) -> Binding<TrackPreference?> {
        Binding(
            get: { model.draft.routeSections?.indices.contains(index) == true
                ? model.draft.routeSections?[index].trackPreference : nil },
            set: { value in
                guard model.draft.routeSections?.indices.contains(index) == true else { return }
                model.draft.routeSections?[index].trackPreference = value
            })
    }

    private func timetablePassStations(_ timetable: Train) -> some View {
        DisclosureGroup {
            ForEach(Array(timetable.stops.enumerated()), id: \.offset) { _, stop in
                let qualifier = recordedQualifier(code: stop.n02StationCode)
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: RailSpacing.labelValueGap) {
                        Text(BracketedStationText.title(
                            officialName: stop.name,
                            localizedTitle: localization.stationName(
                                stop.name, code: stop.n02StationCode, region: model.region),
                            regionCode: model.region.code, localization: localization))
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .layoutPriority(1)
                        StationQualifierCaption(text: BracketedStationText.secondary(
                            officialName: stop.name, regionCode: model.region.code,
                            qualifier: qualifier, localization: localization))
                    }
                    Spacer(minLength: 8)
                    Text([stop.arrival, stop.departure].compactMap { $0 }.joined(separator: " / "))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    StationQualifierCopy.spoken(
                        name: stop.name, countryCode: model.region.code.uppercased(),
                        qualifier: qualifier, localization: localization))
                .contextMenu {
                    let full = copyText(code: stop.n02StationCode, fallbackName: stop.name)
                    Button {
                        StationQualifierCopy.copy(full)
                    } label: {
                        Label(localization.text("ios.editor.copyStation", fallback: "Copy"), systemImage: "doc.on.doc")
                    }
                    ShareLink(item: full) {
                        Label(localization.text("ios.share", fallback: "Share"), systemImage: "square.and.arrow.up")
                    }
                }
            }
        } label: {
            Text(text("passStations", fallback: "Stations on this route ({count})",
                      ["count": .string(String(timetable.stops.count))]))
        }
        .accessibilityIdentifier("newTripPassStations")
    }

    /// Suggestions only. Nothing is written until the reader picks one.
    private var boundForSuggestions: [String] {
        var names = model.directionLegs.reversed().compactMap(\.terminalName)
        if let last = (model.directionSource(original: original) ?? model.draft).stops.last?.name { names.insert(last, at: 0) }
        var seen: Set<String> = []
        return names.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    @ViewBuilder private var directionRows: some View {
        ForEach(Array(model.directionLegs.enumerated()), id: \.offset) { index, leg in
            HStack(spacing: RailSpacing.s8) {
                Image(systemName: leg.direction == .up ? "arrow.up.circle.fill"
                      : leg.direction == .down ? "arrow.down.circle.fill" : "questionmark.circle")
                    .foregroundStyle(leg.direction == nil ? Color.secondary : Color.accentColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: RailSpacing.labelValueGap) {
                    Text(directionWord(leg.direction))
                        .font(.subheadline.weight(.semibold))
                    if let line = leg.lineID.flatMap(model.lineName(for:)) {
                        Text(line).railText(.tertiary)
                    }
                }
                Spacer(minLength: 8)
                if index == model.directionLegs.count - 1, let boundFor = model.boundFor {
                    Text(boundForText(boundFor)).railText(.tertiary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("newTripDirection-\(index)")
        }
        if !model.directionLegs.isEmpty || model.boundFor != nil {
            Menu {
                ForEach(boundForSuggestions, id: \.self) { name in
                    Button(boundForText(name)) { model.draft.direction = name }
                }
                Button(text("boundForOther", fallback: "Other…")) {
                    model.boundForDraft = model.boundFor ?? ""
                    model.showsBoundForEntry = true
                }
                if model.boundFor != nil {
                    Button(text("boundForClear", fallback: "Clear"), role: .destructive) { model.draft.direction = nil }
                }
            } label: {
                LabeledContent(text("boundForTitle", fallback: "方面")) {
                    Text(model.boundFor.map(boundForText) ?? text("boundForChoose", fallback: "Choose"))
                        .foregroundStyle(model.boundFor == nil ? .secondary : .primary)
                }
                .frame(minHeight: RailSize.touch)
            }
            .accessibilityIdentifier("newTripBoundFor")
            .alert(text("boundForTitle", fallback: "方面"), isPresented: $model.showsBoundForEntry) {
                TextField(text("boundForTitle", fallback: "方面"), text: $model.boundForDraft)
                Button(localization.text("ios.done", fallback: "Done")) {
                    let value = model.boundForDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    model.draft.direction = value.isEmpty ? nil : value
                }
                Button(localization.text("ios.cancel", fallback: "Cancel"), role: .cancel) {}
            }
        }
    }

    @ViewBuilder private func routeOutcome(_ outcome: TripRoutePlanner.Outcome) -> some View {
        switch outcome {
        case .corridors(let corridors):
            // Every section is chosen: the passing stations are filled in.
            if let joined = corridors.first, joined.id == model.selectedCorridorID {
                passStations(joined)
            }
            if model.corridorsRemovedByDate {
                Text(text(
                    corridors.isEmpty ? "noCorridorOnDate" : "corridorsHiddenByDate",
                    fallback: corridors.isEmpty
                        ? "No route was open on this date."
                        : "Some routes are hidden because they were not open on this date."))
                    .railText(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .disconnected(let junctions):
            VStack(alignment: .leading, spacing: RailSpacing.s8) {
                if !model.routeErrorCoveredByNotice {
                    routeError(disconnectedMessage(junctions))
                }
                Text(text("continueAnywayExplanation",
                          fallback: "Treat the listed stations as through-running connections."))
                    .railText(.tertiary)
                Button(text("continueAnyway", fallback: "Continue anyway")) {
                    model.allowUnverifiedConnections = true
                }
                .accessibilityIdentifier("newTripContinueAnyway")
            }
        case .noRoute:
            if !model.routeErrorCoveredByNotice {
                routeError(text(
                    "noRoute",
                    fallback: "No rail connection between these stations."))
            }
        case .noCompanyRoute(let name):
            routeError(text(
                "noCompanyRoute",
                fallback: "No route between these stations is operated by {company}.",
                ["company": .string(name)]))
        case .sameStation:
            routeError(text("sameStation", fallback: "Choose two different stations."))
        case .truncated:
            routeError(text(
                "truncated",
                fallback: "The search was too large. Try choosing a company or a different train type."))
        }
    }

    /// One per-section notice row: closed-line notices while planning, and
    /// unproven sections of a saved route. A warning is orange with a
    /// triangle; information is secondary with the history clock.
    private func sectionNotice(
        title: String?, warning: Bool, message: String, detail: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: RailSpacing.s4) {
            if let title {
                Text(title)
                    .font(.footnote.weight(.semibold)) // ui-token-ok: notice title
            }
            if warning {
                RailStatusLabel(kind: .warning, text: message)
            } else {
                Label {
                    Text(message)
                        .font(.footnote) // ui-token-ok: notice text, colour set by label
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .foregroundStyle(.secondary)
            }
            if let detail {
                Text(detail)
                    .font(.footnote) // ui-token-ok: notice detail stays at the notice's own text size
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Closed-line notices, one row per affected section, from the cached
    /// section state. No work happens here.
    @ViewBuilder private var historicalNotices: some View {
        let notices = model.plannedIdentity != model.routeIdentity ? [] : model.sections.enumerated().compactMap { index, section in
            model.historicalNotice(for: section).map { (index, section, $0) }
        }
        if !notices.isEmpty {
            let date = model.dayString(model.departure)
            ForEach(notices, id: \.0) { index, section, kind in
                sectionNotice(
                    title: model.sections.count > 1 ? "\(section.fromName) → \(section.toName)" : nil,
                    warning: kind == .warning,
                    message: kind == .info
                        ? text("historicalNotice",
                               fallback: "This trip uses a line that has since closed. It is checked against the network as it was on {date}.",
                               ["date": .string(date)])
                        : text("historicalNoRoute",
                               fallback: "No line connected these stations on {date}. If the line has closed, check the date you rode it, or add a stop along the way.",
                               ["date": .string(date)]),
                    detail: kind == .info && !model.vias.isEmpty && section.historicalProbe == .historicalOnly
                        ? text("historicalOwnTrip",
                               fallback: "Save the closed part as its own trip, without stops along the way.")
                        : nil)
                    .accessibilityIdentifier("newTripHistoricalNotice-\(index)")
            }
            if displaySettings?.networkEra == .current {
                Button(text("showHistoricalLines", fallback: "Show historical lines on the map")) {
                    displaySettings?.networkEra = .historicalOverlay
                    displaySettings?.persist()
                }
                .accessibilityIdentifier("newTripShowHistoricalLines")
            }
        }
    }

    /// Sections in order, then the active one's candidates. A section with one
    /// plausible path settles alone; only the others ask.
    @ViewBuilder private var sectionRows: some View {
        if shownSections.count > 1 {
            ForEach(Array(shownSections.enumerated()), id: \.offset) { index, section in
                Button {
                    model.activeSection = index
                    model.refreshDrawnRoutes()
                } label: {
                    HStack(spacing: RailSpacing.s8) {
                        Image(systemName: model.choice(for: section) != nil ? "checkmark.circle.fill"
                              : section.candidates.count > 1 ? "questionmark.circle.fill" : "exclamationmark.circle")
                            .foregroundStyle(model.choice(for: section) != nil ? Color.accentColor : Color.orange) // status-color-ok: row icon; the state is also written in the row text
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: RailSpacing.labelValueGap) {
                            Text(text("sectionTitle", fallback: "Section {n} of {count}: {from} → {to}", [
                                "n": .string(String(index + 1)), "count": .string(String(shownSections.count)),
                                "from": .string(section.fromName), "to": .string(section.toName)]))
                                .font(.subheadline.weight(index == shownActiveSection ? .semibold : .regular))
                                .foregroundStyle(.primary)
                            Text(sectionStatus(section))
                                .railText(.tertiary)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: RailSize.touch)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("newTripSection-\(index)")
                .accessibilityAddTraits(index == shownActiveSection ? .isSelected : [])
            }
        }
        if shownSections.indices.contains(shownActiveSection) {
            let candidates = shownSections[shownActiveSection].candidates
            if model.showsRecordRoute, let section = shownSections.first {
                Text(text("repairChoose", fallback: "Choose the route between {from} and {to}",
                          ["from": .string(section.fromName), "to": .string(section.toName)]))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if candidates.count > 1 {
                Text(text(
                    "multipleRoutes",
                    fallback: "Multiple routes connect these stations — choose one"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(candidates.enumerated()), id: \.element.id) { index, corridor in
                corridorRow(corridor, index: index)
            }
        }
        if !model.pendingSections.isEmpty, shownSections.count > 1 {
            RailStatusLabel(kind: .warning, text: text("sectionsToChoose", fallback: "{count} sections still to choose before the stations are filled in",
                      ["count": .string(String(model.pendingSections.count))]))
                .accessibilityIdentifier("newTripSectionsPending")
        }
    }

    private func sectionStatus(_ section: PlannedSection) -> String {
        if let id = model.choice(for: section), let corridor = section.candidates.first(where: { $0.id == id }) {
            return corridor.lineNames.joined(separator: " → ")
        }
        switch section.candidates.count {
        case 0: return text("sectionNoRoute", fallback: "No route")
        default:
            return text("sectionOptions", fallback: "{count} options", ["count": .string(String(section.candidates.count))])
        }
    }

    private func corridorRow(_ corridor: TripRoutePlanner.Corridor, index: Int) -> some View {
        let shown = shownSections
        let selected = !model.showsRecordRoute && shown.indices.contains(shownActiveSection)
            && model.choice(for: shown[shownActiveSection]) == corridor.id
        return Button {
            if model.showsRecordRoute { model.chooseRepair(index, text: repairText) } else { model.choose(corridor.id, inSection: model.activeSection) }
        } label: {
            HStack(alignment: .top, spacing: RailSpacing.s12) {
                VStack(alignment: .leading, spacing: RailSpacing.s4) {
                    Text(corridor.lineNames.joined(separator: " → "))
                        .font(.body)
                        .multilineTextAlignment(.leading)
                    if !corridor.operatorNames.isEmpty {
                        Text(corridor.operatorNames.joined(separator: " · "))
                            .railText(.tertiary)
                    }
                    Text(stationCountText(corridor))
                        .railText(.tertiary)
                    ForEach(Array(corridor.junctions.enumerated()), id: \.offset) { _, junction in
                        if let badge = junctionBadge(junction) {
                            Text(badge)
                                .font(.caption2)
                                .foregroundStyle(junction.link == .none ? Color.primary : Color.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if selected {
                    Image(systemName: "checkmark")
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("newTripCorridor-\(index)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func passStations(_ corridor: TripRoutePlanner.Corridor) -> some View {
        let stations = corridor.choice.stations
        return DisclosureGroup {
            ForEach(Array(stations.enumerated()), id: \.offset) { index, visit in
                let qualifier = visitQualifier(visit, corridor: corridor)
                VStack(alignment: .leading, spacing: RailSpacing.labelValueGap) {
                    Text(BracketedStationText.title(
                        officialName: visit.name,
                        localizedTitle: localization.stationName(
                            visit.name, code: visit.code, region: model.region),
                        regionCode: model.region.code, localization: localization))
                        .fontWeight(index == 0 || index == stations.count - 1 ? .bold : .regular)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                    StationQualifierCaption(text: BracketedStationText.secondary(
                        officialName: visit.name, regionCode: model.region.code,
                        qualifier: qualifier, localization: localization))
                }
                .frame(maxWidth: .infinity, minHeight: RailSize.touch, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(StationQualifierCopy.spoken(
                    name: visit.name, countryCode: model.region.code.uppercased(),
                    qualifier: qualifier, localization: localization))
                .contextMenu {
                    let full = copyText(
                        code: visit.code, fallbackName: visit.name,
                        contextLineIDs: Set(corridor.choice.lineIDs))
                    Button {
                        StationQualifierCopy.copy(full)
                    } label: {
                        Label(localization.text("ios.editor.copyStation", fallback: "Copy"), systemImage: "doc.on.doc")
                    }
                    ShareLink(item: full) {
                        Label(localization.text("ios.share", fallback: "Share"), systemImage: "square.and.arrow.up")
                    }
                }
            }
        } label: {
            Text(text(
                "passStations",
                fallback: "Stations on this route ({count})",
                ["count": .string(String(stations.count))]))
        }
        .accessibilityIdentifier("newTripPassStations")
    }

    private func routeError(_ message: String) -> some View {
        RailStatusLabel(kind: .error, text: message)
            .accessibilityIdentifier("newTripRouteError")
    }

    /// The sections on screen: the planner's, or the one span a paused route
    /// repair asks about. One list, one candidate row, one map treatment.
    private var shownSections: [PlannedSection] {
        guard model.showsRecordRoute else { return model.sections }
        guard let pause = model.repair.pause else { return [] }
        let candidates = pause.choices.map { TripRoutePlanner.Corridor(choice: $0) }
        return [PlannedSection(
            key: "repair", fromName: visitName(pause.fromVisitID), toName: visitName(pause.toVisitID),
            outcome: .corridors(candidates),
            geometry: Dictionary(zip(candidates.map(\.id), pause.geometry), uniquingKeysWith: { first, _ in first }),
            proven: [], proofFailure: nil, removedByDate: false)]
    }

    private var shownActiveSection: Int { model.showsRecordRoute ? 0 : model.activeSection }
}
