import RailCore
import SwiftUI

/// Endpoint form for a new trip. Replaces the ride-editor wizard only when
/// the journey is new; the host supplies the sheet or panel chrome.
struct NewTripView: View {
    @Environment(AppLocalization.self) private var localization

    let train: Train
    let title: String
    let onCancel: () -> Void
    let onSave: (Train) -> Void

    private static let serviceTypes = ["local", "rapid", "express", "limitedExpress", "highSpeed"]

    private enum StationField: String, Identifiable {
        case origin
        case destination
        var id: String { rawValue }
    }

    @State private var region: Region
    @State private var catalog: EditorCatalog?
    @State private var package: CompactPackage?
    @State private var loadFailed = false
    @State private var origin: CatalogStation?
    @State private var destination: CatalogStation?
    @State private var originLine: CatalogLine?
    @State private var destinationLine: CatalogLine?
    @State private var trainType: String
    @State private var timetableTrain: Train?
    @State private var timetableRideSpan: ClosedRange<Int>?
    @State private var applyingTimetable = false
    @State private var timetableTrainTypeChanged = false
    @State private var limitedExpressName = ""
    @State private var showsTimetablePicker = false
    @State private var timetableFailed = false
    @State private var trainNumber = ""
    @State private var companyName = ""
    @State private var departure: Date
    @State private var arrival: Date
    @State private var picking: StationField?
    @State private var outcome: TripRoutePlanner.Outcome?
    /// `routeIdentity` that `outcome` was planned for. A newer identity makes the outcome stale.
    @State private var plannedIdentity = ""
    @State private var searching = false
    @State private var selectedCorridorID: String?
    @State private var autofillFailed = false
    @State private var saveIssues: [RideDraftIssue] = []
    /// Catalog operator id → display name. Rebuilt when the catalog or stations change.
    @State private var operatorNameByID: [String: String] = [:]
    /// Catalog display name → `CompactPackage.Line.operator`, the string the planner compares.
    @State private var packageOperatorByDisplayName: [String: String] = [:]
    @State private var companyOptions: [String] = []

    init(
        train: Train,
        title: String,
        onCancel: @escaping () -> Void,
        onSave: @escaping (Train) -> Void
    ) {
        self.train = train
        self.title = title
        self.onCancel = onCancel
        self.onSave = onSave
        _region = State(initialValue: Region(rawValue: train.region ?? "") ?? .jp)
        let type = train.trainType ?? ""
        _trainType = State(initialValue: Self.serviceTypes.contains(type) ? type : "local")
        let now = Date()
        _departure = State(initialValue: now)
        _arrival = State(initialValue: now)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Form {
                if loadFailed {
                    Text(text(
                        "loadFailed",
                        fallback: "The rail data for this region could not be loaded."))
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if Region.enabledOrdered.count > 1 {
                    regionSection
                }
                stationsSection
                serviceSection
                timeSection
                if region == .jp { timetableSection }
                if timetableTrain != nil || (origin != nil && destination != nil) {
                    routeSection
                }
                if !saveIssues.isEmpty {
                    Section {
                        ForEach(saveIssues) { issue in
                            Text(validationMessage(issue))
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .sheet(item: $picking) { field in
            if let catalog {
                TripStationSearchView(
                    catalog: catalog,
                    regionCode: region.code,
                    companyFilter: companyName.isEmpty ? nil : companyName,
                    onSelect: { station, line in
                        clearTimetable()
                        switch field {
                        case .origin:
                            origin = station
                            originLine = line
                        case .destination:
                            destination = station
                            destinationLine = line
                        }
                        picking = nil
                    })
            }
        }
        .sheet(isPresented: $showsTimetablePicker) {
            ServicePatternPickerView(
                region: region.code,
                rideDate: dayString(departure),
                onSelectDate: { day in
                    if let day, let date = timetableDate(day, time: clock(departure, extraDays: 0)) {
                        timetableTimeSelection(isDeparture: true).wrappedValue = date
                    }
                },
                onSelectTrip: { applyTimetableTrip($0) },
                onSelectDraft: { applyTimetableTrip($0) }
            ) { pattern, reversed in
                applyPattern(pattern, reversed: reversed)
            }
        }
        .onChange(of: departure) { _, newValue in
            if arrival < newValue { arrival = newValue }
            saveIssues = []
        }
        .onChange(of: arrival) { _, _ in
            saveIssues = []
        }
        .onChange(of: trainNumber) { _, _ in
            saveIssues = []
        }
        .onChange(of: region) { _, _ in
            clearTimetable()
            limitedExpressName = ""
            origin = nil
            destination = nil
            originLine = nil
            destinationLine = nil
            companyName = ""
            catalog = nil
            package = nil
            outcome = nil
            plannedIdentity = ""
            selectedCorridorID = nil
            autofillFailed = false
            loadFailed = false
            saveIssues = []
            refreshCompanyCache()
        }
        .onChange(of: origin) { _, _ in
            refreshCompanyCache()
        }
        .onChange(of: destination) { _, _ in
            refreshCompanyCache()
        }
        .onChange(of: companyOptions) { _, options in
            if !companyName.isEmpty, !options.contains(companyName) {
                companyName = ""
            }
        }
        .onChange(of: selectedCorridorID) { _, _ in
            autofillFailed = false
            saveIssues = []
        }
        .task(id: region) { await loadRegion() }
        .task(id: routeIdentity) { await planRoute() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button(text("cancel", fallback: "Cancel"), action: onCancel)
                .accessibilityIdentifier("newTripCancel")
            Spacer(minLength: 8)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            Button(text("save", fallback: "Save"), action: commit)
                .fontWeight(.semibold)
                .disabled(!canSave)
                .accessibilityIdentifier("newTripSave")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var regionSection: some View {
        Section {
            Picker(text("region", fallback: "Region"), selection: $region) {
                ForEach(Region.enabledOrdered) { region in
                    Text(localization.text(region.localizationKey, fallback: region.fallbackName))
                        .tag(region)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var stationsSection: some View {
        Section {
            if catalog == nil, !loadFailed {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
            stationButton(
                title: text("from", fallback: "From"),
                station: origin,
                line: originLine,
                identifier: "newTripOrigin") { picking = .origin }
            Button(action: swapStations) {
                Image(systemName: "arrow.up.arrow.down")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .accessibilityIdentifier("newTripSwap")
            .accessibilityLabel(text("swap", fallback: "Swap stations"))
            .disabled(origin == nil && destination == nil)
            stationButton(
                title: text("to", fallback: "To"),
                station: destination,
                line: destinationLine,
                identifier: "newTripDestination") { picking = .destination }
        } header: {
            Text(text("stations", fallback: "Stations"))
        }
    }

    private var serviceSection: some View {
        Section {
            Picker(text("trainType", fallback: "Train type"), selection: Binding(
                get: { trainType },
                set: { value in
                    if timetableTrain != nil, value != trainType { timetableTrainTypeChanged = true }
                    trainType = value
                })) {
                ForEach(Self.serviceTypes, id: \.self) { type in
                    Text(localization.editorText("ios.editor.serviceType.\(type)")).tag(type)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("newTripTrainType")
            TextField(text("trainNumber", fallback: "Train number or name"), text: $trainNumber)
                .accessibilityIdentifier("newTripNumber")
            Picker(text("company", fallback: "Company"), selection: $companyName) {
                Text(text("anyCompany", fallback: "Any company")).tag("")
                ForEach(companyOptions, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("newTripCompany")
        } header: {
            Text(text("service", fallback: "Service"))
        }
    }

    private var timeSection: some View {
        Section {
            DatePicker(
                text("departure", fallback: "Departure"),
                selection: timetableTimeSelection(isDeparture: true),
                displayedComponents: [.date, .hourAndMinute])
                .accessibilityIdentifier("newTripDeparture")
            DatePicker(
                text("arrival", fallback: "Arrival"),
                selection: timetableTimeSelection(isDeparture: false),
                displayedComponents: [.date, .hourAndMinute])
                .accessibilityIdentifier("newTripArrival")
            if arrival < departure {
                Text(text(
                    "arrivalBeforeDeparture",
                    fallback: "Arrival is before departure."))
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text(text("time", fallback: "Time"))
        }
    }

    private var timetableSection: some View {
        Section {
            TextField(text("serviceName", fallback: "Service name"), text: $limitedExpressName)
                .accessibilityIdentifier("newTripLimitedExpressName")
            Menu(text("serviceSuggestions", fallback: "Service suggestions")) {
                ForEach(serviceSuggestions, id: \.self) { name in
                    Button(name) { limitedExpressName = name }
                }
            }
            Button { showsTimetablePicker = true } label: {
                Label(text("timetableBrowse", fallback: "Browse timetables"), systemImage: "magnifyingglass")
            }
            .accessibilityIdentifier("newTripTimetableBrowse")
            if origin != nil, destination != nil {
                TimetableQuickMatchView(
                    train: timetableQuery,
                    serviceName: limitedExpressName) { applyTimetableTrip($0) }
            }
            if timetableFailed {
                Text(text("timetableFailed", fallback: "This timetable could not be applied."))
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            if let timetableTrain {
                VStack(alignment: .leading, spacing: 6) {
                    Text(limitedExpressName.isEmpty ? timetableTrain.number : limitedExpressName)
                        .font(.headline)
                    Text("\(timetableTrain.origin) → \(timetableTrain.destination)")
                    Text(text("stationCount", fallback: "{count} stations",
                              ["count": .string(String(timetableTrain.stops.count))]))
                    Text(timetableTimes(timetableTrain))
                        .font(.caption.monospacedDigit())
                    Button(text("timetableRemove", fallback: "Remove"), action: clearTimetable)
                        .accessibilityIdentifier("newTripTimetableRemove")
                }
                // Keep the Remove button's own identifier reachable.
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("newTripTimetableApplied")
            }
        } header: {
            Text(text("timetable", fallback: "Timetable"))
        }
    }

    private var serviceSuggestions: [String] {
        let names = TrainServiceBranding.services.filter { $0.region == region.code }.flatMap(\.names)
        return Array(Set(names)).sorted().filter {
            limitedExpressName.isEmpty || $0.localizedCaseInsensitiveContains(limitedExpressName)
        }
    }

    private var timetableBase: Train {
        var base = train
        base.region = region.code
        base.date = dayString(departure)
        base.stops = [origin, destination].enumerated().compactMap { index, station in
            guard let station else { return nil }
            return Stop(name: station.name, n02StationCode: station.key.sourceCode,
                        stopType: index == 0 ? "origin" : "destination", rideSegment: false)
        }
        base.origin = origin?.name ?? ""
        base.destination = destination?.name ?? ""
        return base
    }

    /// Derived on every render (two stops, cheap) so the lookup can never run
    /// against an older copy of the Time section.
    private var timetableQuery: Train {
        // Quick match only looks up once the endpoints carry departure and
        // arrival clocks, so the query uses the Time section's values.
        var query = timetableBase
        if query.stops.count == 2 {
            query.stops[0].departure = clock(departure, extraDays: 0)
            query.stops[1].arrival = clock(arrival, extraDays: extraDays(from: departure, to: arrival))
        }
        return JourneyCompletion.resolvingUniqueStationNames(
            in: query, catalogs: catalog.map { [region.code: $0] } ?? [:])
    }

    private func timetableTimeSelection(isDeparture: Bool) -> Binding<Date> {
        Binding(
            get: { isDeparture ? departure : arrival },
            set: { value in
                let previous = isDeparture ? departure : arrival
                // Only the departure day identifies the service; overnight
                // arrivals legitimately fall on the next civil day.
                if isDeparture, !applyingTimetable, dayString(value) != dayString(previous),
                   let timetableTrain, dayString(value) != timetableTrain.date {
                    clearTimetable()
                }
                if isDeparture { departure = value } else { arrival = value }
            })
    }

    private func prefillRidden(forDate date: String?) -> Bool {
        Dates.normalizeDateString(date).map {
            $0 <= RecordDate.today(in: Region.resolved(timetableBase).clock)
        } ?? true
    }

    private func clearTimetable() {
        timetableTrain = nil
        timetableRideSpan = nil
        timetableTrainTypeChanged = false
        timetableFailed = false
        saveIssues = []
    }

    private func applyTimetableTrip(_ trip: TrainTimetableDatabase.Trip) {
        let day = trip.serviceDate.isEmpty ? dayString(departure) : trip.serviceDate
        let ridden = prefillRidden(forDate: day)
        guard let applied = trip.canApplyToRouteEditor
            ? trip.applying(to: timetableBase, ridden: ridden)
            : trip.publishedStopsDraft(to: timetableBase, ridden: ridden) else {
            timetableFailed = true
            return
        }
        if acceptTimetable(applied) { limitedExpressName = trip.service.canonicalName }
    }

    private func applyPattern(_ pattern: TrainServicePatterns.Pattern, reversed: Bool) {
        let ridden = prefillRidden(forDate: dayString(departure))
        _ = acceptTimetable(TrainServicePatterns.apply(
            pattern, to: timetableBase, reversed: reversed, ridden: ridden))
    }

    @discardableResult
    private func acceptTimetable(_ applied: Train) -> Bool {
        guard applied.stops.count >= 2 else {
            timetableFailed = true
            return false
        }
        var applied = applied
        var span = 0...(applied.stops.count - 1)
        if let origin, let destination {
            let codes = [origin.key.sourceCode, destination.key.sourceCode]
                + applied.stops.compactMap(\.n02StationCode)
            let aliases = package.map { loadJourneyStationAliases(for: codes, package: $0) } ?? [:]
            func matches(_ stop: Stop, _ station: CatalogStation) -> Bool {
                guard let code = stop.n02StationCode else { return false }
                let selected = station.key.sourceCode
                return (aliases[code] ?? code) == (aliases[selected] ?? selected)
            }
            guard let first = applied.stops.firstIndex(where: { matches($0, origin) }),
                  let last = applied.stops.indices.first(where: {
                      $0 > first && matches(applied.stops[$0], destination)
                  }) else {
                timetableFailed = true
                return false
            }
            span = first...last
            // Keep published passenger calls and route facts. Pass-through flags
            // inherit adjacent calls in Statistics, so do not turn unboarded
            // passenger calls into pass-throughs to represent a partial ride.
            for index in applied.stops.indices {
                applied.stops[index].rideSegment = span.contains(index) && applied.stops[index].rideSegment
                if applied.stops[index].stopType == "origin" || applied.stops[index].stopType == "destination" {
                    applied.stops[index].stopType = "passenger_stop"
                }
            }
            applied.stops[first].stopType = "origin"
            applied.stops[last].stopType = "destination"
            applied.origin = applied.stops[first].name
            applied.destination = applied.stops[last].name
        } else {
            if let code = applied.stops.first?.n02StationCode,
               let station = catalog?.station(StationKey(regionCode: region.code, sourceCode: code)) {
                origin = station
                originLine = nil
            }
            if let code = applied.stops.last?.n02StationCode,
               let station = catalog?.station(StationKey(regionCode: region.code, sourceCode: code)) {
                destination = station
                destinationLine = nil
            }
        }
        applyingTimetable = true
        defer { applyingTimetable = false }
        timetableTrain = applied
        timetableRideSpan = span
        timetableTrainTypeChanged = false
        timetableFailed = false
        saveIssues = []
        let type = applied.trainType ?? ""
        if type.contains("新幹線") { trainType = "highSpeed" }
        else if type.contains("特急") { trainType = "limitedExpress" }
        else if type.contains("急行") { trainType = "express" }
        else if type.contains("快速") { trainType = "rapid" }
        let day = applied.date ?? dayString(departure)
        if let time = applied.stops[span.lowerBound].departure,
           let date = timetableDate(day, time: time) {
            timetableTimeSelection(isDeparture: true).wrappedValue = date
        }
        if let time = applied.stops[span.upperBound].arrival,
           let date = timetableDate(day, time: time) {
            timetableTimeSelection(isDeparture: false).wrappedValue = date
        }
        return true
    }

    private func timetableDate(_ day: String, time: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        let parts = time.split(separator: ":")
        guard let date = formatter.date(from: day), parts.count >= 2,
              let hours = Int(parts[0]), let minutes = Int(parts[1]) else { return nil }
        return Calendar.current.date(byAdding: .minute, value: hours * 60 + minutes, to: date)
    }

    private func timetableTimes(_ timetable: Train) -> String {
        let span = timetableRideSpan ?? 0...(timetable.stops.count - 1)
        return [timetable.stops[span.lowerBound].departure, timetable.stops[span.upperBound].arrival]
            .compactMap { $0 }.joined(separator: " → ")
    }

    private func timetablePassStations(_ timetable: Train) -> some View {
        DisclosureGroup {
            ForEach(Array(timetable.stops.enumerated()), id: \.offset) { _, stop in
                HStack {
                    Text(localization.stationName(stop.name, code: stop.n02StationCode, region: region))
                    Spacer()
                    Text([stop.arrival, stop.departure].compactMap { $0 }.joined(separator: " / "))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            Text(text("passStations", fallback: "Stations on this route ({count})",
                      ["count": .string(String(timetable.stops.count))]))
        }
        .accessibilityIdentifier("newTripPassStations")
    }

    private var routeSection: some View {
        Section {
            if let timetableTrain {
                timetablePassStations(timetableTrain)
            } else if searching {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(text("searching", fallback: "Searching routes"))
            } else if let outcome {
                routeOutcome(outcome)
            }
            if autofillFailed {
                Text(text("autofillFailed", fallback: "This route could not be applied."))
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text(text("route", fallback: "Route"))
        }
    }

    @ViewBuilder private func routeOutcome(_ outcome: TripRoutePlanner.Outcome) -> some View {
        switch outcome {
        case .corridors(let corridors):
            if corridors.count > 1 {
                Text(text(
                    "multipleRoutes",
                    fallback: "Multiple routes connect these stations — choose one"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(corridors.enumerated()), id: \.element.id) { index, corridor in
                VStack(alignment: .leading, spacing: 8) {
                    corridorRow(corridor, index: index)
                    if selectedCorridorID == corridor.id {
                        passStations(corridor)
                    }
                }
            }
        case .disconnected(let junctions):
            routeError(disconnectedMessage(junctions))
        case .noRoute:
            routeError(text(
                "noRoute",
                fallback: "No rail connection between these stations."))
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

    private func corridorRow(_ corridor: TripRoutePlanner.Corridor, index: Int) -> some View {
        let selected = selectedCorridorID == corridor.id
        return Button {
            selectedCorridorID = corridor.id
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(corridor.lineNames.joined(separator: " → "))
                        .font(.body)
                        .multilineTextAlignment(.leading)
                    if !corridor.operatorNames.isEmpty {
                        Text(corridor.operatorNames.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(stationCountText(corridor))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(Array(corridor.junctions.enumerated()), id: \.offset) { _, junction in
                        if let badge = junctionBadge(junction) {
                            Text(badge)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(localization.stationName(visit.name, code: visit.code, region: region))
                        .fontWeight(index == 0 || index == stations.count - 1 ? .bold : .regular)
                    if let caption = lineChangeCaption(for: visit, junctions: corridor.junctions) {
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
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
        Text(message)
            .font(.footnote)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("newTripRouteError")
    }

    private func stationButton(
        title: String,
        station: CatalogStation?,
        line: CatalogLine?,
        identifier: String,
        choose: @escaping () -> Void
    ) -> some View {
        Button(action: choose) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(stationTitle(station))
                    .font(.body)
                    .foregroundStyle(station == nil ? Color.secondary : Color.primary)
                if let station, let subtitle = stationSubtitle(station, line: line) {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(catalog == nil)
        .accessibilityIdentifier(identifier)
    }

    private var canSave: Bool {
        if let timetableTrain { return timetableTrain.stops.count >= 2 && arrival >= departure }
        return origin != nil && destination != nil && arrival >= departure
            && plannedIdentity == routeIdentity
            && selectedCorridor != nil && !searching
    }

    private var selectedCorridor: TripRoutePlanner.Corridor? {
        guard plannedIdentity == routeIdentity,
              let selectedCorridorID,
              let outcome,
              case .corridors(let corridors) = outcome else { return nil }
        return corridors.first { $0.id == selectedCorridorID }
    }

    private var routeIdentity: String {
        [
            region.code,
            origin?.key.sourceCode ?? "",
            destination?.key.sourceCode ?? "",
            originLine?.id ?? "",
            destinationLine?.id ?? "",
            trainType,
            companyName,
            package == nil ? "0" : "1",
        ].joined(separator: "\u{1f}")
    }

    /// Operators of the lines that serve the chosen origin, the chosen
    /// destination, or both. Sorted and deduped by display name.
    /// Called when the catalog or the endpoint stations change, not from `body`.
    private func refreshCompanyCache() {
        guard let catalog else {
            operatorNameByID = [:]
            packageOperatorByDisplayName = [:]
            companyOptions = []
            return
        }
        let names = Dictionary(
            catalog.operators(in: region.code).map { ($0.id, $0.name) },
            uniquingKeysWith: { first, _ in first })
        operatorNameByID = names
        if let package {
            packageOperatorByDisplayName = Self.packageOperatorNames(package)
        }
        var found: Set<String> = []
        for station in [origin, destination].compactMap({ $0 }) {
            for member in catalog.memberships(stationKey: station.key) {
                guard let line = catalog.line(id: member.lineID, regionCode: member.regionCode) else { continue }
                for identifier in line.operatorIDs {
                    if let name = names[identifier], !name.isEmpty { found.insert(name) }
                }
            }
        }
        companyOptions = found.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// `CatalogOperator.name` is the package operator with whitespace collapsed.
    /// Prefer a raw `line.operator` that already equals that name; otherwise keep
    /// the package spelling, which is what corridor `operatorNames` contain.
    private static func packageOperatorNames(_ package: CompactPackage) -> [String: String] {
        var chosen: [String: String] = [:]
        for line in package.lines {
            guard let raw = line.operator else { continue }
            let collapsed = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard !collapsed.isEmpty else { continue }
            if let existing = chosen[collapsed] {
                if existing != collapsed, raw == collapsed { chosen[collapsed] = raw }
            } else {
                chosen[collapsed] = raw
            }
        }
        return chosen
    }

    private func stationTitle(_ station: CatalogStation?) -> String {
        guard let station else { return text("chooseStation", fallback: "Choose station") }
        return localization.stationName(station.name, code: station.key.sourceCode, region: region)
    }

    /// Picked line as "line · operator". Without a picked line, the first two memberships.
    private func stationSubtitle(_ station: CatalogStation, line: CatalogLine?) -> String? {
        if let line {
            if let name = line.operatorIDs.compactMap({ operatorNameByID[$0] }).first(where: { !$0.isEmpty }) {
                return "\(line.name) · \(name)"
            }
            return line.name
        }
        guard let catalog else { return nil }
        let labels = catalog.memberships(stationKey: station.key).prefix(2).map { member -> String in
            guard let memberLine = catalog.line(id: member.lineID, regionCode: member.regionCode) else {
                return member.lineID
            }
            if let name = memberLine.operatorIDs.compactMap({ operatorNameByID[$0] }).first(where: { !$0.isEmpty }) {
                return "\(memberLine.name) · \(name)"
            }
            return memberLine.name
        }
        let joined = labels.joined(separator: "\n")
        return joined.isEmpty ? nil : joined
    }

    private func swapStations() {
        clearTimetable()
        let previous = origin
        let previousLine = originLine
        origin = destination
        originLine = destinationLine
        destination = previous
        destinationLine = previousLine
    }

    private func loadRegion() async {
        loadFailed = false
        let region = region
        let worker = Task.detached(priority: .utility) { () throws -> (EditorCatalog, CompactPackage) in
            let catalog = try loadCatalog(for: region)
            let package = try EditorRoutePackageCache.load(region: region)
            return (catalog, package)
        }
        do {
            let loaded = try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled, region == self.region else { return }
            catalog = loaded.0
            package = loaded.1
            refreshCompanyCache()
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            catalog = nil
            package = nil
            loadFailed = true
        }
    }

    private func planRoute() async {
        let identity = routeIdentity
        outcome = nil
        plannedIdentity = ""
        selectedCorridorID = nil
        autofillFailed = false
        guard let origin, let destination, let package else {
            searching = false
            return
        }
        searching = true
        let originCode = origin.key.sourceCode
        let destinationCode = destination.key.sourceCode
        let originLineID = originLine?.id
        let destinationLineID = destinationLine?.id
        let trainType = trainType
        let operatorName = companyName.isEmpty
            ? nil
            : (packageOperatorByDisplayName[companyName] ?? companyName)
        let worker = Task.detached(priority: .userInitiated) {
            let request = TripRoutePlanner.Request(
                originCode: originCode,
                destinationCode: destinationCode,
                trainType: trainType,
                operatorName: operatorName,
                stationAliases: loadJourneyStationAliases(
                    for: [originCode, destinationCode], package: package),
                originLineID: originLineID,
                destinationLineID: destinationLineID)
            return TripRoutePlanner.plan(package: package, request: request)
        }
        let result = await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
        guard !Task.isCancelled, identity == routeIdentity else { return }
        plannedIdentity = identity
        outcome = result
        searching = false
        if case .corridors(let corridors) = result, corridors.count == 1 {
            selectedCorridorID = corridors[0].id
        }
    }

    private func commit() {
        if var draft = timetableTrain {
            guard canSave else { return }
            draft.id = train.id
            draft.region = region.code
            draft.date = dayString(departure)
            if timetableTrainTypeChanged { draft.trainType = trainType }
            let span = timetableRideSpan ?? 0...(draft.stops.count - 1)
            if draft.stops[span.lowerBound].departure == nil {
                draft.stops[span.lowerBound].departure = clock(departure, extraDays: 0)
            }
            if draft.stops[span.upperBound].arrival == nil {
                draft.stops[span.upperBound].arrival = clock(
                    arrival, extraDays: extraDays(from: departure, to: arrival))
            }
            if !companyName.isEmpty { draft.company = companyName }
            let number = trainNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            draft.number = [number, draft.number, limitedExpressName,
                            draft.routeSections?.first?.lineNames?.first ?? originLine?.name ?? ""]
                .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
            draft.origin = draft.stops[span.lowerBound].name
            draft.destination = draft.stops[span.upperBound].name
            let issues = RideDraftValidation.issues(
                for: draft, originalID: train.id, existingIDs: RideStatusCenter.shared.trainIDs)
            saveIssues = issues.blocking
            guard saveIssues.isEmpty else { return }
            onSave(draft)
            return
        }
        guard canSave, let origin, let destination, let corridor = selectedCorridor else { return }
        var draft = train
        draft.region = region.code
        // Same mapping StationPickerView uses: CatalogStation.key.sourceCode.
        draft.stops = [
            Stop(
                name: origin.name,
                n02StationCode: origin.key.sourceCode,
                stopType: "origin",
                rideSegment: true),
            Stop(
                name: destination.name,
                n02StationCode: destination.key.sourceCode,
                stopType: "destination",
                rideSegment: true),
        ]
        // requiresConfirmation is ignored because the draft only has two endpoint stops.
        guard let proposal = LocalJourneyAutofill.proposal(train: draft, choice: corridor.choice),
              proposal.train.stops.count >= 2 else {
            autofillFailed = true
            return
        }
        draft = proposal.train
        draft.region = region.code
        draft.date = dayString(departure)
        let last = draft.stops.count - 1
        draft.stops[0].departure = clock(departure, extraDays: 0)
        draft.stops[last].arrival = clock(arrival, extraDays: extraDays(from: departure, to: arrival))
        draft.trainType = trainType
        let typedNumber = trainNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.number = typedNumber.isEmpty
            ? (corridor.lineNames.first ?? originLine?.name ?? "")
            : typedNumber
        if companyName.isEmpty {
            let joined = corridor.operatorNames.filter { !$0.isEmpty }.joined(separator: "・")
            draft.company = joined.isEmpty ? nil : joined
        } else {
            draft.company = companyName
        }
        draft.origin = origin.name
        draft.destination = destination.name
        let issues = RideDraftValidation.issues(
            for: draft, originalID: train.id, existingIDs: RideStatusCenter.shared.trainIDs)
        let blocking = issues.blocking
        guard blocking.isEmpty else {
            saveIssues = blocking
            return
        }
        saveIssues = []
        onSave(draft)
    }

    private func validationMessage(_ issue: RideDraftIssue) -> String {
        if let literal = issue.literal { return literal }
        return localization.editorText(issue.key, issue.params)
    }

    private func stationCountText(_ corridor: TripRoutePlanner.Corridor) -> String {
        let count = String(corridor.passStationCount)
        guard let kilometers = kilometerString(corridor.distanceKm) else {
            return text("stationCount", fallback: "{count} stations", ["count": .string(count)])
        }
        return text(
            "stationCountDistance",
            fallback: "{count} stations · {km} km",
            ["count": .string(count), "km": .string(kilometers)])
    }

    private func junctionBadge(_ junction: TripRoutePlanner.Junction) -> String? {
        let station = localization.stationName(junction.stationName, code: junction.stationCode, region: region)
        switch junction.link {
        case .throughService:
            return text(
                "throughService",
                fallback: "Through service at {station}",
                ["station": .string(station)])
        case .network:
            return text(
                "continuesAt",
                fallback: "Continues at {station}",
                ["station": .string(station)])
        case .sameLine, .none:
            return nil
        }
    }

    private func lineChangeCaption(
        for visit: RailwayRouteChoices.Visit,
        junctions: [TripRoutePlanner.Junction]
    ) -> String? {
        let captions = junctions.filter { $0.stationCode == visit.code }.map { junction in
            text(
                "lineChange",
                fallback: "{from} → {to}",
                ["from": .string(junction.fromLineName), "to": .string(junction.toLineName)])
        }
        guard !captions.isEmpty else { return nil }
        return captions.joined(separator: "\n")
    }

    private func disconnectedMessage(_ junctions: [TripRoutePlanner.Junction]) -> String {
        let changes = junctions.map { junction in
            text(
                "changeAt",
                fallback: "{station} ({from} → {to})",
                [
                    "station": .string(localization.stationName(
                        junction.stationName, code: junction.stationCode, region: region)),
                    "from": .string(junction.fromLineName),
                    "to": .string(junction.toLineName),
                ])
        }.joined(separator: "\n")
        let lead = text(
            "disconnected",
            fallback: "These lines are not connected — one train cannot run this way. Change trains at: {changes}",
            ["changes": .string(changes)])
        return lead + "\n" + text("addLegs", fallback: "Add each leg as its own trip.")
    }

    private func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// Hours run past 24 when arrival falls on a later calendar day (`25:10`).
    private func clock(_ date: Date, extraDays: Int) -> String {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date) + extraDays * 24
        let minute = calendar.component(.minute, from: date)
        return String(format: "%02d:%02d", hour, minute)
    }

    private func extraDays(from departure: Date, to arrival: Date) -> Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: departure)
        let end = calendar.startOfDay(for: arrival)
        return max(0, calendar.dateComponents([.day], from: start, to: end).day ?? 0)
    }

    private func kilometerString(_ kilometers: Double) -> String? {
        guard kilometers > 0 else { return nil }
        let rounded = (kilometers * 10).rounded() / 10
        guard rounded > 0 else { return nil }
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(format: "%.1f", rounded)
    }

    private func text(
        _ key: String,
        fallback: String,
        _ params: [String: Localization.Param]? = nil
    ) -> String {
        localization.text("ios.newTrip.\(key)", params: params, fallback: fallback)
    }
}
