import RailCore
import SwiftUI

/// Presented from the ride editor's stops section so a JP limited-express
/// stop pattern can prefill the draft's stop list. Tapping a row hands the
/// chosen pattern back to the caller and dismisses; the resulting stops stay
/// ordinary, editable rows afterwards.
struct ServicePatternPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let region: String
    let rideDate: String?
    let onSelectTrip: ((TrainTimetableDatabase.Trip) -> Void)?
    let onSelect: (TrainServicePatterns.Pattern, Bool) -> Void

    @State private var query = ""
    @State private var showsAllHistory = false
    @State private var companyFilter: String?
    @State private var lineFilter: String?
    @State private var pendingSelection: Selection?
    @State private var timetablePatterns: [TrainServicePatterns.Pattern] = []
    @State private var timetableDetails: [String: TimetableDetail] = [:]
    @State private var timetableTripsByPatternID: [String: TrainTimetableDatabase.Trip] = [:]
    @State private var incompleteTimetableTrips: [TrainTimetableDatabase.Trip] = []
    @State private var timetableCoverage: TrainTimetableDatabase.Coverage?
    @State private var timetableTripCount = 0
    @State private var incompleteTimetableTripCount = 0
    @State private var timetableQueryFailed = false

    private static let timetableDatabase = TrainTimetableDatabase.bundled()
    private static let jrAndNationalOperatorNames: Set<String> = [
        "北海道旅客鉄道", "東日本旅客鉄道", "東海旅客鉄道",
        "西日本旅客鉄道", "四国旅客鉄道", "九州旅客鉄道",
        "日本国有鉄道", "国鉄",
    ]

    init(
        region: String, rideDate: String?,
        onSelectTrip: ((TrainTimetableDatabase.Trip) -> Void)? = nil,
        onSelect: @escaping (TrainServicePatterns.Pattern, Bool) -> Void
    ) {
        self.region = region
        self.rideDate = rideDate
        self.onSelectTrip = onSelectTrip
        self.onSelect = onSelect
    }

    private struct Selection: Identifiable {
        let pattern: TrainServicePatterns.Pattern
        let reversed: Bool
        var id: String { "\(pattern.id):\(reversed)" }
    }

    private struct TimetableDetail: Sendable {
        let serviceName: String
        let departureTime: String?
    }

    private var legacyMatches: [TrainServicePatterns.Pattern] {
        TrainServicePatterns.search(query, region: region, filter: .init(
            company: companyFilter, status: .any, line: lineFilter, rideDate: rideDate))
    }

    private var exactMatches: [TrainServicePatterns.Pattern] {
        let needle = normalized(query.trimmingCharacters(in: .whitespacesAndNewlines))
        return timetablePatterns.filter { pattern in
            if let companyFilter, pattern.companyLabel != companyFilter { return false }
            if let lineFilter {
                let line = TrainServiceBranding.canonicalLineName(lineFilter)
                guard pattern.lines.contains(where: {
                    TrainServiceBranding.canonicalLineName($0) == line
                }) else { return false }
            }
            guard !needle.isEmpty else { return true }
            return [pattern.name, pattern.label, pattern.origin, pattern.destination]
                .contains { normalized($0).contains(needle) }
                || pattern.stops.contains { normalized($0).contains(needle) }
                || pattern.lines.contains { normalized($0).contains(needle) }
        }
    }

    private var incompleteTripMatches: [TrainTimetableDatabase.Trip] {
        let needle = normalized(query.trimmingCharacters(in: .whitespacesAndNewlines))
        return incompleteTimetableTrips.filter { trip in
            if let companyFilter,
               !trip.operatorSegments.map(\.displayName).contains(companyFilter) { return false }
            if let lineFilter {
                let line = TrainServiceBranding.canonicalLineName(lineFilter)
                guard trip.lineSegments.contains(where: {
                    TrainServiceBranding.canonicalLineName($0.lineName) == line
                }) else { return false }
            }
            guard !needle.isEmpty else { return true }
            let values = [
                trip.service.canonicalName, trip.publicNumber ?? trip.trainNumber,
                trip.origin?.station.name ?? "", trip.destination?.station.name ?? "",
            ] + trip.stops.map(\.station.name) + trip.lineSegments.map(\.lineName)
            return values.contains { normalized($0).contains(needle) }
        }
    }

    private var knownMatches: [TrainServicePatterns.Pattern] {
        guard rideDate != nil else { return legacyMatches }
        if !timetablePatterns.isEmpty { return exactMatches }
        if timetableCoverage == .verified && timetableTripCount == 0 { return [] }
        return []
    }

    private var unknownMatches: [TrainServicePatterns.Pattern] {
        guard rideDate != nil else { return [] }
        return legacyMatches.filter { pattern in
            guard let rideDate else { return false }
            return pattern.applicability(on: rideDate) != .notApplicable
                && (shouldShowLegacyFallback || !isJROrNationalRailway(pattern))
        }
    }

    private var outsideMatches: [TrainServicePatterns.Pattern] {
        guard let rideDate, showsAllHistory else { return [] }
        return legacyMatches.filter { $0.applicability(on: rideDate) == .notApplicable }
    }

    private var shouldShowLegacyFallback: Bool {
        guard rideDate != nil else { return false }
        return timetableQueryFailed
            || timetableCoverage != .verified
            || incompleteTimetableTripCount > 0
            || (timetableTripCount > 0 && timetablePatterns.isEmpty)
    }

    private var companyLabels: [String] {
        Array(Set(
            TrainServicePatterns.companyLabels(region: region)
                + timetablePatterns.map(\.companyLabel).filter { !$0.isEmpty }
                + incompleteTimetableTrips.flatMap { $0.operatorSegments.map(\.displayName) }
        )).sorted()
    }

    private var lineNames: [String] {
        Array(Set(
            TrainServicePatterns.lineNames(region: region) + timetablePatterns.flatMap(\.lines)
                + incompleteTimetableTrips.flatMap { $0.lineSegments.map(\.lineName) }
        )).sorted()
    }

    private var groups: [(name: String, companyLabel: String, patterns: [TrainServicePatterns.Pattern])] {
        var order: [String] = []
        var byName: [String: [TrainServicePatterns.Pattern]] = [:]
        for pattern in knownMatches {
            let name = timetableDetails[pattern.id]?.serviceName ?? pattern.name
            if byName[name] == nil { order.append(name) }
            byName[name, default: []].append(pattern)
        }
        return order.map { name in
            (name: name, companyLabel: byName[name]?.first?.companyLabel ?? "", patterns: byName[name] ?? [])
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let rideDate {
                        Toggle("すべての履歴を表示", isOn: $showsAllHistory)
                            .accessibilityIdentifier("servicePatternHistoryFilter")
                        Text("乗車日: \(rideDate)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("乗車日を設定すると、その日に有効なパターンを表示します")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let rideDate {
                        timetableStatus(date: rideDate)
                    }

                    HStack {
                        Menu {
                            Button("すべての会社") { companyFilter = nil }
                            ForEach(companyLabels, id: \.self) { label in
                                Button(label) { companyFilter = label }
                            }
                        } label: {
                            Label(companyFilter ?? "すべての会社", systemImage: "building.2")
                        }
                        .accessibilityIdentifier("servicePatternCompanyFilter")

                        Spacer()

                        Menu {
                            Button("すべての路線") { lineFilter = nil }
                            ForEach(lineNames, id: \.self) { line in
                                Button(line) { lineFilter = line }
                            }
                        } label: {
                            Label(lineFilter ?? "すべての路線", systemImage: "arrow.triangle.swap")
                        }
                        .accessibilityIdentifier("servicePatternLineFilter")
                    }
                }
                ForEach(groups, id: \.name) { group in
                    Section(header: Text("\(group.name) · \(group.companyLabel)")) {
                        ForEach(group.patterns) { pattern in
                            patternRow(pattern)
                        }
                    }
                }
                if !incompleteTripMatches.isEmpty {
                    Section("当日ダイヤ（調査中・適用不可）") {
                        ForEach(incompleteTripMatches) { trip in incompleteTripRow(trip) }
                    }
                }
                if !unknownMatches.isEmpty {
                    Section("互換パターン（当日ダイヤ未確認）") {
                        ForEach(unknownMatches) { pattern in patternRow(pattern) }
                    }
                }
                if !outsideMatches.isEmpty {
                    Section("乗車日の対象外・有効期間未確認") {
                        ForEach(outsideMatches) { pattern in patternRow(pattern) }
                    }
                }
                if groups.isEmpty && incompleteTripMatches.isEmpty
                    && unknownMatches.isEmpty && outsideMatches.isEmpty
                {
                    Text(timetableCoverage == .verified && timetableTripCount == 0
                         ? "この日は運行予定の特急がありません"
                         : "該当する列車パターンが見つかりません")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("列車パターンから入力")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: Text("列車名・行き先で検索"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
            .task(id: "\(region):\(rideDate ?? "")") { await loadTimetable() }
            .confirmationDialog(
                "このパターンは乗車日の対象外です。適用しますか？",
                isPresented: Binding(get: { pendingSelection != nil },
                                     set: { if !$0 { pendingSelection = nil } }),
                titleVisibility: .visible
            ) {
                Button("確認して適用") {
                    guard let selection = pendingSelection else { return }
                    apply(selection)
                }
                Button("キャンセル", role: .cancel) { pendingSelection = nil }
            }
        }
    }

    private func patternRow(_ pattern: TrainServicePatterns.Pattern) -> some View {
        HStack(spacing: 0) {
            Button { select(pattern, reversed: false) } label: { row(for: pattern) }
            // A timetable trip has a direction, train number, and times of its
            // own. Reversing it would fabricate a train that the database does
            // not contain. Legacy route summaries keep their direction toggle.
            if !pattern.id.hasPrefix("timetable:") {
                Button { select(pattern, reversed: true) } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("逆方向: \(pattern.destination) → \(pattern.origin)")
            }
        }
        .frame(minHeight: 44)
    }

    private func select(_ pattern: TrainServicePatterns.Pattern, reversed: Bool) {
        if let trip = timetableTripsByPatternID[pattern.id], let onSelectTrip {
            onSelectTrip(trip)
            dismiss()
            return
        }
        let selection = Selection(pattern: pattern, reversed: reversed)
        if let rideDate, pattern.applicability(on: rideDate) == .notApplicable {
            pendingSelection = selection
        } else {
            apply(selection)
        }
    }

    private func apply(_ selection: Selection) {
        onSelect(selection.pattern, selection.reversed)
        pendingSelection = nil
        dismiss()
    }

    private func row(for pattern: TrainServicePatterns.Pattern) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(pattern.label)
                if pattern.confidence == "low" {
                    Text("要確認")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .clipShape(Capsule())
                }
                if let rideDate, let applicability = pattern.applicability(on: rideDate),
                   applicability != .applicable {
                    Text(applicability == .unknown ? "有効期間未確認" : "乗車日の対象外")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.2))
                        .clipShape(Capsule())
                }
                if pattern.completeness.stops != .complete
                    || pattern.completeness.lines != .complete
                    || pattern.completeness.validity != .complete
                {
                    Text("停站\(mark(pattern.completeness.stops)) 路線\(mark(pattern.completeness.lines)) 日付\(mark(pattern.completeness.validity))")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            Text("\(pattern.origin) → \(pattern.destination) · \(pattern.stops.count)駅")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let departure = timetableDetails[pattern.id]?.departureTime {
                Text("始発 \(departure)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if pattern.validFrom != nil || pattern.validUntil != nil {
                Text(validityCaption(for: pattern))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !pattern.lines.isEmpty {
                Text("経由: \(pattern.lines.joined(separator: "・"))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !pattern.optionalStops.isEmpty {
                Text("一部列車停車: \(pattern.optionalStops.joined(separator: "、"))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func incompleteTripRow(_ trip: TrainTimetableDatabase.Trip) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text([trip.service.canonicalName, trip.publicNumber ?? trip.trainNumber]
                .filter { !$0.isEmpty }.joined(separator: " "))
            Text("\(trip.origin?.station.name ?? "?") → \(trip.destination?.station.name ?? "?") · \(trip.passengerStops.count)駅")
                .font(.caption).foregroundStyle(.secondary)
            if let departure = trip.origin?.departureTime ?? trip.origin?.arrivalTime {
                Text("始発 \(departure)").font(.caption2).foregroundStyle(.secondary)
            }
            let missing = [
                "operator": "運行会社", "validity_calendar": "運転日", "stops": "停車駅",
                "times": "時刻", "route_lines": "経路", "station_refs": "駅参照",
                "provenance": "出典",
            ].compactMap { key, label in
                trip.factCompleteness[key] == .verified ? nil : label
            }
            Text("未確認: \(missing.joined(separator: "・"))")
                .font(.caption2).foregroundStyle(.orange)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("timetableIncompleteTrip-\(trip.id)")
        .accessibilityHint("調査中のため停車駅へ適用できません")
    }

    private func validityCaption(for pattern: TrainServicePatterns.Pattern) -> String {
        let from = pattern.validFrom ?? "?"
        if let until = pattern.validUntil {
            return "\(from)〜\(until)未満"
        }
        return "\(from)〜"
    }

    private func mark(_ level: TrainServicePatterns.Pattern.Level) -> String {
        switch level {
        case .complete: "✓"
        case .partial: "△"
        case .missing: "?"
        }
    }

    @ViewBuilder private func timetableStatus(date: String) -> some View {
        if timetableQueryFailed || Self.timetableDatabase == nil {
            Text("当日ダイヤDBを利用できないため、互換パターンを表示しています")
                .font(.caption).foregroundStyle(.orange)
        } else if timetableCoverage == .conflict {
            Text("\(date) の当日ダイヤには未解決の資料競合があります。互換パターンも別に表示します")
                .font(.caption).foregroundStyle(.orange)
        } else if timetableCoverage == .verified && timetableTripCount == 0 {
            Text("\(date) はJR・国鉄の運行予定特急がありません。私鉄の互換パターンは引き続き表示します")
                .font(.caption).foregroundStyle(.secondary)
        } else if incompleteTimetableTripCount > 0 {
            Text("当日ダイヤ \(timetableTripCount)本中 \(incompleteTimetableTripCount)本は停車駅・経路・出典の確認が未完了のため適用できません")
                .font(.caption).foregroundStyle(.orange)
        } else if timetableCoverage == .partial || timetableCoverage == .unknown {
            Text("\(date) の当日ダイヤは調査途中です。互換パターンも別に表示します")
                .font(.caption).foregroundStyle(.orange)
        } else if !timetablePatterns.isEmpty {
            Text("\(date) の列車番号別ダイヤ")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @MainActor private func loadTimetable() async {
        timetablePatterns = []
        timetableDetails = [:]
        timetableTripsByPatternID = [:]
        incompleteTimetableTrips = []
        timetableCoverage = nil
        timetableTripCount = 0
        incompleteTimetableTripCount = 0
        timetableQueryFailed = false
        guard region == "jp", let rideDate, let database = Self.timetableDatabase else { return }

        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                let trips = try database.trips(on: rideDate)
                let coverage = try database.coverage(on: rideDate)
                return (trips, coverage)
            }.value
            guard !Task.isCancelled else { return }
            timetableCoverage = loaded.1.status
            timetableTripCount = loaded.0.count
            incompleteTimetableTripCount = loaded.0.filter { !$0.canApplyToRouteEditor }.count
            for trip in loaded.0 {
                guard let pattern = trip.compatibilityPattern() else {
                    incompleteTimetableTrips.append(trip)
                    continue
                }
                timetablePatterns.append(pattern)
                timetableTripsByPatternID[pattern.id] = trip
                timetableDetails[pattern.id] = TimetableDetail(
                    serviceName: trip.service.canonicalName,
                    departureTime: trip.origin?.departureTime ?? trip.origin?.arrivalTime)
            }
        } catch {
            timetableQueryFailed = true
        }
    }

    private func normalized(_ value: String) -> String {
        let folded = value.precomposedStringWithCompatibilityMapping.lowercased()
        return folded.applyingTransform(.hiraganaToKatakana, reverse: false) ?? folded
    }

    private func isJROrNationalRailway(_ pattern: TrainServicePatterns.Pattern) -> Bool {
        pattern.company.split(separator: "/").contains { component in
            Self.jrAndNationalOperatorNames.contains(
                component.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
