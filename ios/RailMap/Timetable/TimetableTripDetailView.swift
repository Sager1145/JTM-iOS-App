import RailCore
import SwiftUI

/// Source clocks remain visible even when route evidence is incomplete.
struct TimetableTripDetailView: View {
    @Environment(AppLocalization.self) private var localization
    @Environment(\.dismiss) private var dismiss
    @State private var sources: [TrainTimetableDatabase.SourceDocument] = []
    @State private var sourceQueryFailed = false
    @State private var showsAICheck = false
    @ScaledMetric(relativeTo: .body) private var timeColumnWidth: CGFloat = 52
    let trip: TrainTimetableDatabase.Trip
    let onUseDraft: ((TrainTimetableDatabase.Trip) -> Void)?
    private static let openedDatabase: Result<TrainTimetableDatabase, TrainTimetableDatabase.OpenFailure> = {
        do { return .success(try TrainTimetableDatabase.bundled()) }
        catch let error as TrainTimetableDatabase.OpenFailure { return .failure(error) }
        catch { return .failure(.damaged(String(describing: error))) }
    }()

    var body: some View {
        let stopsByStationID = trip.stops.reduce(
            into: [String: TrainTimetableDatabase.StopTime]()) { result, stop in
                if result[stop.station.id] == nil { result[stop.station.id] = stop }
            }
        let stopsBySequence = trip.stops.reduce(
            into: [Int: TrainTimetableDatabase.StopTime]()) { result, stop in
                if result[stop.sequence] == nil { result[stop.sequence] = stop }
            }
        NavigationStack {
            List {
                Section {
                    Text(detailText("serviceDate", ["date": .string(trip.serviceDate)]))
                    LabeledContent(localization.text("ios.ai.researchTrainNumber", fallback: "Operating train number"),
                                   value: trip.trainNumber)
                    Text("\(trip.origin?.station.name ?? "?") → \(trip.destination?.station.name ?? "?")")
                    if let englishName = trip.service.englishName {
                        Text(englishName).foregroundStyle(.secondary)
                    }
                    Text(detailText("edition", ["edition": .string(trip.timetableEditionName)]))
                        .railText(.tertiary)
                    if !trip.canApplyToRouteEditor {
                        Text(trip.timetableCompleteness == .conflict
                             ? detailText("conflictDraft")
                             : detailText("unverifiedRoute"))
                            .foregroundStyle(.orange)
                    }
                    if trip.factCompleteness["stops"] != .verified {
                        Text(detailText("publishedOnly"))
                            .railText(.tertiary)
                    }
                    if onUseDraft != nil, trip.timetableCompleteness != .conflict,
                       trip.passengerStops.count >= 2 {
                        Button(detailText("useDraft")) { onUseDraft?(trip) }
                            .accessibilityIdentifier("timetableUseDraft-\(trip.id)")
                        Text(detailText("draftHelp"))
                            .railText(.tertiary)
                    }
                    Button(localization.text("ios.ai.researchCheck", fallback: "Check with ChatGPT")) { showsAICheck = true }
                        .accessibilityIdentifier("timetableAICheck-\(trip.id)")
                }
                Section(detailText("stopsTimes")) {
                    ForEach(trip.stops) { stop in
                        HStack(alignment: .top, spacing: RailSpacing.s12) {
                            Text(stop.station.name).font(.headline)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: RailSpacing.s8)
                            VStack(alignment: .trailing, spacing: RailSpacing.labelValueGap) {
                                if stop.callType == "pass" {
                                    Text("レ")
                                        .font(.body.monospaced())
                                        .frame(width: timeColumnWidth)
                                        .foregroundStyle(.secondary)
                                        .accessibilityLabel(detailText("pass"))
                                } else {
                                    Text(detailText("arrival", ["time": .string(clock(stop.arrivalTime, seconds: stop.arrivalSeconds))]))
                                    Text(detailText("departure", ["time": .string(clock(stop.departureTime, seconds: stop.departureSeconds))]))
                                }
                                if !stop.isPassengerCall && stop.callType != "pass" {
                                    Text(detailText("nonPassenger")).railText(.tertiary)
                                }
                            }
                            .frame(minWidth: timeColumnWidth, alignment: .trailing)
                            .fixedSize(horizontal: true, vertical: false)
                        }
                        .monospacedDigit()
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("timetableStop-\(stop.sequence)")
                        ForEach(trip.timetableSymbols.filter { $0.afterStopSequence == stop.sequence }) { row in
                            HStack(alignment: .top, spacing: RailSpacing.s12) {
                                Text(row.stationName).font(.headline)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: RailSpacing.s8)
                                Text(row.symbol)
                                    .font(.body.monospaced())
                                    .frame(width: timeColumnWidth)
                                    .accessibilityLabel(row.symbol == "レ" ? detailText("pass") : detailText("notVia"))
                            }
                            .foregroundStyle(.secondary)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("timetableSymbol-\(row.id)")
                        }
                    }
                }
                if !trip.lineSegments.isEmpty {
                    Section(localization.text("ios.ai.lines", fallback: "Lines")) {
                        ForEach(trip.lineSegments) { segment in
                            VStack(alignment: .leading, spacing: RailSpacing.labelValueGap) {
                                Text(segment.lineName)
                                if let from = stopsByStationID[segment.fromStationID],
                                   let to = stopsByStationID[segment.toStationID] {
                                    Text("\(from.station.name) → \(to.station.name)")
                                        .railText(.tertiary)
                                }
                            }
                        }
                    }
                }
                if !trip.operatorSegments.isEmpty {
                    Section(localization.text("ios.ai.company", fallback: "Operator")) {
                        ForEach(trip.operatorSegments) { segment in
                            VStack(alignment: .leading, spacing: RailSpacing.labelValueGap) {
                                Text(segment.displayName)
                                if let from = stopsBySequence[segment.fromSequence],
                                   let to = stopsBySequence[segment.toSequence] {
                                    Text("\(from.station.name) → \(to.station.name)")
                                        .railText(.tertiary)
                                }
                            }
                        }
                    }
                }
                Section(detailText("completeness")) {
                    ForEach(trip.factCompleteness.keys.sorted(), id: \.self) { key in
                        LabeledContent(dimension(key), value: status(trip.factCompleteness[key]))
                    }
                }
                Section(detailText("sources")) {
                    if sourceQueryFailed {
                        Text(detailText("sourceFailed")).foregroundStyle(.secondary)
                    }
                    ForEach(sources) { source in
                        VStack(alignment: .leading, spacing: RailSpacing.labelValueGap) {
                            if let url = URL(string: source.urlOrLocator),
                               ["https", "http"].contains(url.scheme ?? "") {
                                Link(source.title, destination: url)
                            } else {
                                Text(source.title)
                            }
                            Text(source.publisher).railText(.tertiary)
                        }
                    }
                }
            }
            .accessibilityIdentifier("timetableDetailList")
            .navigationTitle("\(trip.displayName) \(trip.publicNumber ?? trip.trainNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .railSheetClose(Text(localization.text("ios.close", fallback: "Close")),
                            identifier: "timetableTripClose") { dismiss() }
            .task {
                guard case .success(let database) = Self.openedDatabase else {
                    sourceQueryFailed = true
                    return
                }
                do {
                    sources = try database.sources(for: trip)
                } catch {
                    sourceQueryFailed = true
                }
            }
            .sheet(isPresented: $showsAICheck) {
                TrainResearchView(region: "jp",
                                  query: "\(trip.displayName) \(trip.publicNumber ?? trip.trainNumber)",
                                  rideDate: trip.serviceDate, trip: trip, sources: sources)
                .railSheet(.full)
            }
        }
    }

    private func clock(_ source: String?, seconds: Int?) -> String {
        guard let source else { return detailText("notListed") }
        guard let seconds, seconds >= 86400,
              let civilDate = Dates.addDays(trip.serviceDate, seconds / 86400)
        else { return source }
        return "\(source)（\(civilDate)）"
    }

    private func status(_ coverage: TrainTimetableDatabase.Coverage?) -> String {
        switch coverage {
        case .verified: detailText("status.verified")
        case .partial: detailText("status.partial")
        case .conflict: detailText("status.conflict")
        case .notApplicable: detailText("status.notApplicable")
        default: detailText("status.unknown")
        }
    }

    private func dimension(_ key: String) -> String {
        switch key {
        case "identity", "train_number", "origin_destination", "station_refs":
            detailText("dimension." + key)
        case "operator", "validity_calendar", "stops", "times", "route_lines", "provenance":
            localization.text("ios.editor.pattern.fact." + key)
        default:
            detailText("dimension.other")
        }
    }

    private func detailText(_ key: String, _ params: [String: Localization.Param]? = nil) -> String {
        localization.text("ios.editor.pattern.detail." + key, params: params)
    }
}
