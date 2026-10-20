import RailApplication
import RailCore
import SwiftUI

/// Endpoint form for a new trip. Replaces the ride-editor wizard only when
/// the journey is new; the host supplies the sheet or panel chrome.
struct NewTripView: View {
    @Environment(AppLocalization.self) private var localization
    @Environment(ItineraryStore.self) private var itineraries: ItineraryStore?

    let train: Train
    let title: String
    let onCancel: () -> Void
    let onSave: (Train) -> Void

    private static let serviceTypes = JourneyDraftWork.serviceTypeIDs

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
    @State private var originStationID: String?
    @State private var destinationStationID: String?
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
    @State private var previousDeparture: Date
    /// Date prefill remains live until the reader makes an explicit choice.
    @State private var riddenOverride: Bool?
    @State private var picking: StationField?
    @State private var allowUnverifiedConnections = false
    @State private var outcome: TripRoutePlanner.Outcome?
    /// `routeIdentity` that `outcome` was planned for. A newer identity makes the outcome stale.
    @State private var plannedIdentity = ""
    @State private var physicallyResolvedCorridorIDs: Set<String> = []
    /// Why the corridors on screen were not marked proven. Saving them stays allowed.
    @State private var routeProofFailure: String?
    /// Bumped when the region changes. A search or plan started earlier must not write this draft.
    @State private var draftGeneration = 0
    /// Bumped when this region's registry settles so the timetable query resolves again.
    @State private var registryEpoch = 0
    @State private var searching = false
    @State private var selectedCorridorID: String?
    @State private var corridorsRemovedByDate = false
    /// The corridor the reader last picked, kept across replans that are
    /// cancelled before they finish and so never restore the live selection.
    @State private var preferredCorridorID: String?
    @State private var autofillFailed = false
    @State private var saveIssues: [RideDraftIssue] = []
    /// Catalog operator id → display name. Rebuilt when the catalog or stations change.
    @State private var operatorNameByID: [String: String] = [:]
    /// Catalog display name → `CompactPackage.Line.operator`, the string the planner compares.
    @State private var packageOperatorByDisplayName: [String: String] = [:]
    @State private var companyOptions: [String] = []
    @State private var lineLabelByID: [String: String] = [:]

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
        _previousDeparture = State(initialValue: now)
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
                Section {
                    Toggle(text("ridden", fallback: "I have ridden this journey"), isOn: Binding(
                        get: { isRidden }, set: { riddenOverride = $0 }))
                        .accessibilityIdentifier("newTripRidden")
                }
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
                NavigationStack {
                    StationPickerView(
                        regionCode: region.code,
                        sourceCatalog: catalog,
                        companyFilter: companyName.isEmpty ? nil : companyName,
                        onSelectWithLine: { [generation = draftGeneration] station, line, stationID in
                            guard generation == draftGeneration else {
                                picking = nil
                                return
                            }
                            clearTimetable()
                            switch field {
                            case .origin:
                                origin = station
                                originLine = line
                                originStationID = stationID
                            case .destination:
                                destination = station
                                destinationLine = line
                                destinationStationID = stationID
                            }
                            picking = nil
                        })
                }
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
            let shiftedArrival = arrival.addingTimeInterval(
                newValue.timeIntervalSince(previousDeparture))
            arrival = max(shiftedArrival, newValue)
            previousDeparture = newValue
            saveIssues = []
        }
        .onChange(of: arrival) { _, _ in
            saveIssues = []
        }
        .onChange(of: trainType) { _, _ in
            saveIssues = []
        }
        .onChange(of: trainNumber) { _, _ in
            saveIssues = []
        }
        .onChange(of: companyName) { _, _ in
            saveIssues = []
        }
        .task(id: region.code) {
            await SolverRegistryInput.awaitReady(region: region.code)
            registryEpoch += 1
        }
        .onChange(of: region) { _, _ in
            draftGeneration += 1
            picking = nil
            allowUnverifiedConnections = false
            clearTimetable()
            limitedExpressName = ""
            origin = nil
            destination = nil
            originLine = nil
            destinationLine = nil
            originStationID = nil
            destinationStationID = nil
            companyName = ""
            catalog = nil
            package = nil
            outcome = nil
            plannedIdentity = ""
            physicallyResolvedCorridorIDs.removeAll()
            routeProofFailure = nil
            selectedCorridorID = nil
            corridorsRemovedByDate = false
            preferredCorridorID = nil
            autofillFailed = false
            loadFailed = false
            saveIssues = []
            refreshCompanyCache()
        }
        .onChange(of: origin) { _, _ in
            allowUnverifiedConnections = false
            refreshCompanyCache()
        }
        .onChange(of: destination) { _, _ in
            allowUnverifiedConnections = false
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
                    Text(localization.text("ios.editor.serviceType.\(type)")).tag(type)
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
            return endpointStop(
                station, stationID: index == 0 ? originStationID : destinationStationID,
                stopType: index == 0 ? "origin" : "destination", ridden: false)
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
        // `registryEpoch` is read so a settle rebuilds this derived train.
        _ = registryEpoch
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

    private var isRidden: Bool {
        riddenOverride ?? prefillRidden(forDate: dayString(departure))
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
        let ridden = riddenOverride ?? prefillRidden(forDate: day)
        guard let drafted = JourneyDraftWork.timetableDraft(
            from: trip, appliedTo: timetableBase, ridden: ridden) else {
            timetableFailed = true
            return
        }
        if acceptTimetable(drafted.train) {
            limitedExpressName = drafted.serviceName
            if let kept = timetableTrain {
                TimetableRouteEvidence.rememberAppliedOccurrence(trip: trip, train: kept)
            }
        }
    }

    private func applyPattern(_ pattern: TrainServicePatterns.Pattern, reversed: Bool) {
        _ = acceptTimetable(TrainServicePatterns.apply(
            pattern, to: timetableBase, reversed: reversed, ridden: isRidden))
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
            let aliases: [String: String]
            do {
                aliases = try package.map { try loadJourneyStationAliases(for: codes, package: $0) } ?? [:]
            } catch {
                timetableFailed = true
                routeProofFailure = error.localizedDescription
                return false
            }
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
            if origin == nil,
               let code = applied.stops.first?.n02StationCode,
               let station = catalog?.station(StationKey(regionCode: region.code, sourceCode: code)) {
                origin = station
                originLine = nil
                originStationID = applied.stops.first?.stationID
            }
            if destination == nil,
               let code = applied.stops.last?.n02StationCode,
               let station = catalog?.station(StationKey(regionCode: region.code, sourceCode: code)) {
                destination = station
                destinationLine = nil
                destinationStationID = applied.stops.last?.stationID
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
        var appliedDeparture: Date?
        var appliedArrival: Date?
        if let time = applied.stops[span.lowerBound].departure,
           let date = timetableDate(day, time: time) {
            appliedDeparture = date
        }
        if let time = applied.stops[span.upperBound].arrival,
           let date = timetableDate(day, time: time) {
            appliedArrival = date
        }
        if let appliedDeparture {
            timetableTimeSelection(isDeparture: true).wrappedValue = appliedDeparture
        }
        if let appliedArrival {
            timetableTimeSelection(isDeparture: false).wrappedValue = appliedArrival
        }
        if let appliedDeparture, appliedArrival != nil {
            previousDeparture = appliedDeparture
        }
        return true
    }

    private func timetableDate(_ day: String, time: String) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        let parts = time.split(separator: ":")
        guard let date = formatter.date(from: day), parts.count >= 2,
              let hours = Int(parts[0]), let minutes = Int(parts[1]) else { return nil }
        let serviceDay = calendar.startOfDay(for: date)
        guard let civilDay = calendar.date(byAdding: .day, value: hours / 24, to: serviceDay) else {
            return nil
        }
        return calendar.date(
            bySettingHour: hours % 24, minute: minutes, second: 0, of: civilDay)
    }

    private func timetableTimes(_ timetable: Train) -> String {
        let span = timetableRideSpan ?? 0...(timetable.stops.count - 1)
        return [timetable.stops[span.lowerBound].departure, timetable.stops[span.upperBound].arrival]
            .compactMap { $0 }.joined(separator: " → ")
    }

    private func timetablePassStations(_ timetable: Train) -> some View {
        DisclosureGroup {
            ForEach(Array(timetable.stops.enumerated()), id: \.offset) { _, stop in
                let qualifier = recordedQualifier(code: stop.n02StationCode)
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(BracketedStationText.title(
                            officialName: stop.name,
                            localizedTitle: localization.stationName(
                                stop.name, code: stop.n02StationCode, region: region),
                            regionCode: region.code, localization: localization))
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .layoutPriority(1)
                        StationQualifierCaption(text: BracketedStationText.secondary(
                            officialName: stop.name, regionCode: region.code,
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
                        name: stop.name, countryCode: region.code.uppercased(),
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
            if let routeProofFailure {
                Text(routeProofFailure)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
            if corridorsRemovedByDate {
                Text(text(
                    corridors.isEmpty ? "noCorridorOnDate" : "corridorsHiddenByDate",
                    fallback: corridors.isEmpty
                        ? "No route was open on this date."
                        : "Some routes are hidden because they were not open on this date."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .disconnected(let junctions):
            VStack(alignment: .leading, spacing: 8) {
                routeError(disconnectedMessage(junctions))
                Text(text("continueAnywayExplanation",
                          fallback: "Treat the listed stations as through-running connections."))
                    .font(.caption).foregroundStyle(.secondary)
                Button(text("continueAnyway", fallback: "Continue anyway")) {
                    allowUnverifiedConnections = true
                }
                .accessibilityIdentifier("newTripContinueAnyway")
            }
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
            preferredCorridorID = corridor.id
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
                            if junction.link == .none {
                                Label(badge, systemImage: "exclamationmark.triangle")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                Text(badge)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(BracketedStationText.title(
                        officialName: visit.name,
                        localizedTitle: localization.stationName(
                            visit.name, code: visit.code, region: region),
                        regionCode: region.code, localization: localization))
                        .fontWeight(index == 0 || index == stations.count - 1 ? .bold : .regular)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                    StationQualifierCaption(text: BracketedStationText.secondary(
                        officialName: visit.name, regionCode: region.code,
                        qualifier: qualifier, localization: localization))
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(StationQualifierCopy.spoken(
                    name: visit.name, countryCode: region.code.uppercased(),
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
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(catalog == nil)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(stationAccessibility(title: title, station: station, line: line))
        .accessibilityIdentifier(identifier)
        .contextMenu {
            if let station {
                let full = copyText(for: station, line: line)
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
            dayString(departure),
            String(departure.timeIntervalSinceReferenceDate),
            String(arrival.timeIntervalSinceReferenceDate),
            trainNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            trainType,
            companyName,
            package == nil ? "0" : "1",
            allowUnverifiedConnections ? "1" : "0",
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
            lineLabelByID = [:]
            return
        }
        let names = Dictionary(
            catalog.operators(in: region.code).map { ($0.id, $0.name) },
            uniquingKeysWith: { first, _ in first })
        operatorNameByID = names
        lineLabelByID = StationLabel.lineLabels(in: catalog, regionCode: region.code)
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

    private func copyText(for station: CatalogStation, line: CatalogLine?) -> String {
        guard let catalog else {
            return StationLabel.countryOnly(
                name: station.name, countryCode: station.key.regionCode.uppercased()).full
        }
        return StationReferenceResolution.copyLabel(
            for: station, catalog: catalog, preferredLineID: line?.id)
    }

    private func copyText(
        code: String?, fallbackName: String, contextLineIDs: Set<String> = []
    ) -> String {
        let country = region.code.uppercased()
        guard let catalog, let code, !code.isEmpty,
              let station = catalog.station(StationKey(regionCode: region.code, sourceCode: code))
        else { return StationLabel.countryOnly(name: fallbackName, countryCode: country).full }
        return StationReferenceResolution.copyLabel(
            for: station, catalog: catalog, contextLineIDs: contextLineIDs)
    }

    private func stationTitle(_ station: CatalogStation?) -> String {
        guard let station else { return text("chooseStation", fallback: "Choose station") }
        return BracketedStationText.title(
            officialName: station.name,
            localizedTitle: localization.stationName(
                station.name, code: station.key.sourceCode, region: region),
            regionCode: station.key.regionCode, localization: localization)
    }

    /// Bracket qualifier for the chosen station. A picked line names that line.
    private func stationQualifier(_ station: CatalogStation, line: CatalogLine?) -> String {
        guard let catalog else {
            return StationLabel.caption(countryCode: station.key.regionCode.uppercased(), detail: nil)
        }
        let labels = lineLabelByID.isEmpty
            ? StationLabel.lineLabels(in: catalog, regionCode: station.key.regionCode) : lineLabelByID
        return StationLabel.text(
            for: station, catalog: catalog, labels: labels, preferredLineID: line?.id).qualifier
    }

    private func stationSubtitle(_ station: CatalogStation, line: CatalogLine?) -> String? {
        let qualifier = stationQualifier(station, line: line)
        return BracketedStationText.secondary(
            officialName: station.name, regionCode: station.key.regionCode,
            qualifier: qualifier, localization: localization)
    }

    private func stationAccessibility(title: String, station: CatalogStation?, line: CatalogLine?) -> String {
        guard let station else { return title }
        let qualifier = stationQualifier(station, line: line)
        return title + "，" + StationQualifierCopy.spoken(
            name: station.name, countryCode: station.key.regionCode.uppercased(),
            qualifier: qualifier, localization: localization)
    }

    private func recordedQualifier(code: String?) -> String {
        let country = region.code.uppercased()
        guard let catalog, let code, !code.isEmpty,
              let station = catalog.station(StationKey(regionCode: region.code, sourceCode: code))
        else { return StationLabel.caption(countryCode: country, detail: nil) }
        let labels = lineLabelByID.isEmpty
            ? StationLabel.lineLabels(in: catalog, regionCode: region.code) : lineLabelByID
        return StationLabel.text(for: station, catalog: catalog, labels: labels).qualifier
    }

    private func visitQualifier(
        _ visit: RailwayRouteChoices.Visit, corridor: TripRoutePlanner.Corridor
    ) -> String {
        let country = region.code.uppercased()
        if let change = lineChangeCaption(for: visit, junctions: corridor.junctions) {
            let detail = change.replacingOccurrences(of: "\n", with: " · ")
            return StationLabel.caption(countryCode: country, detail: detail)
        }
        guard let catalog,
              let station = catalog.station(StationKey(regionCode: region.code, sourceCode: visit.code))
        else {
            if corridor.lineNames.count == 1, let name = corridor.lineNames.first {
                return StationLabel.caption(countryCode: country, detail: name)
            }
            return StationLabel.caption(countryCode: country, detail: nil)
        }
        let labels = lineLabelByID.isEmpty
            ? StationLabel.lineLabels(in: catalog, regionCode: region.code) : lineLabelByID
        return StationLabel.text(
            for: station, catalog: catalog, labels: labels,
            contextLineIDs: Set(corridor.choice.lineIDs)).qualifier
    }

    private func swapStations() {
        clearTimetable()
        let previous = origin
        let previousLine = originLine
        origin = destination
        originLine = destinationLine
        destination = previous
        destinationLine = previousLine
        let previousID = originStationID
        originStationID = destinationStationID
        destinationStationID = previousID
    }

    private func endpointStop(
        _ station: CatalogStation, stationID: String?, stopType: String, ridden: Bool
    ) -> Stop {
        var stop = Stop(
            name: station.name, n02StationCode: station.key.sourceCode,
            stopType: stopType, rideSegment: ridden)
        RegistryStationSelection.fill(
            &stop, regionCode: region.code, sourceCode: station.key.sourceCode,
            catalogName: station.name, stationID: stationID)
        stop.stopType = stopType
        stop.rideSegment = ridden
        return stop
    }

    private func commitCompany(_ text: String, on train: inout Train) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            RegistryIdentityUpgrade.reassignCompany(nil, on: &train)
        } else if !RegistryOperatorCommit.apply(text: trimmed, region: region.code, to: &train) {
            RegistryIdentityUpgrade.reassignCompany(trimmed, on: &train)
        }
    }

    private func loadRegion() async {
        loadFailed = false
        let region = region
        let generation = draftGeneration
        let worker = Task.detached(priority: .utility) { () async throws -> (EditorCatalog, CompactPackage) in
            let catalog = try loadCatalog(for: region)
            let package = try await DisplayNetworkCache.shared.package(country: region.code).package
            return (catalog, package)
        }
        do {
            let loaded = try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled, region == self.region, generation == draftGeneration else { return }
            catalog = loaded.0
            package = loaded.1
            refreshCompanyCache()
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, region == self.region, generation == draftGeneration else { return }
            catalog = nil
            package = nil
            loadFailed = true
        }
    }

    private func planRoute() async {
        let generation = draftGeneration
        let identity = routeIdentity
        let previousSelectedCorridorID = selectedCorridorID ?? preferredCorridorID
        outcome = nil
        plannedIdentity = ""
        physicallyResolvedCorridorIDs.removeAll()
        routeProofFailure = nil
        selectedCorridorID = nil
        corridorsRemovedByDate = false
        autofillFailed = false
        guard let origin, let destination, let package else {
            searching = false
            return
        }
        searching = true
        let originCode = origin.key.sourceCode
        let destinationCode = destination.key.sourceCode
        let allowUnverifiedConnections = allowUnverifiedConnections
        let originLineID = originLine?.id
        let destinationLineID = destinationLine?.id
        let rideDate = dayString(departure)
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
                stationAliases: try loadJourneyStationAliases(
                    for: [originCode, destinationCode], package: package),
                originLineID: originLineID,
                destinationLineID: destinationLineID,
                allowUnverifiedConnections: allowUnverifiedConnections)
            return try TripRoutePlanner.plan(package: package, request: request, rideDate: rideDate)
        }
        let result: TripRoutePlanner.Outcome
        do {
            result = try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: { worker.cancel() }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, identity == routeIdentity, generation == draftGeneration else { return }
            searching = false
            routeProofFailure = error.localizedDescription
            return
        }
        guard !Task.isCancelled, identity == routeIdentity, generation == draftGeneration else { return }
        var publishedResult = result
        var removedByDate = false
        var physicallyResolvedIDs: Set<String> = []
        var proofFailure: String?
        if case .corridors(let corridors) = result {
            let hasDatedNetwork = RiddenRouteStore.hasDatedNetwork(region: region.code)
            var latestValidFrom: String?
            do {
                if hasDatedNetwork {
                    latestValidFrom = try RiddenRouteStore.latestValidFrom(region: region.code)
                }
            } catch {
                // Unknown date bounds cannot exclude otherwise valid corridors.
                // Keep the proposals, show the actual resource failure, and leave them unproven.
                proofFailure = error.localizedDescription
            }
            let normalizedRideDate = Dates.normalizeDateString(rideDate)
            // Today's network cannot reject a date after its newest opening.
            let needsDateValidation = hasDatedNetwork && proofFailure == nil && (
                normalizedRideDate != rideDate
                    || latestValidFrom.map { rideDate < $0 } == true)
            if needsDateValidation {
                let candidates = corridors.map {
                    TripRouteValidation.Candidate(id: $0.id, train: draft(for: $0))
                }
                do {
                    let validation = try await TripRouteValidation.validate(candidates: candidates) { trains in
                        try await RiddenRouteStore.routeAvailabilities(trains).map {
                            .init(datedResolved: $0.datedResolved, undatedResolved: $0.undatedResolved)
                        }
                    }
                    physicallyResolvedIDs = validation.physicallyResolvedIDs
                    proofFailure = validation.unprovenReason
                    if validation.unprovenReason != nil { physicallyResolvedIDs = [] }
                    let filtered = corridors.filter { validation.retainedIDs.contains($0.id) }
                    removedByDate = filtered.count < corridors.count
                    publishedResult = .corridors(filtered)
                } catch is CancellationError {
                    return
                } catch {
                    // The records stay savable. Retained ids are not proof.
                    physicallyResolvedIDs = []
                    proofFailure = "Route proof is unavailable, so these records stay savable and unproven."
                }
            }
            guard !Task.isCancelled, identity == routeIdentity, generation == draftGeneration else { return }
        }
        physicallyResolvedCorridorIDs = physicallyResolvedIDs
        routeProofFailure = proofFailure
        plannedIdentity = identity
        outcome = publishedResult
        corridorsRemovedByDate = removedByDate
        searching = false
        if case .corridors(let corridors) = publishedResult {
            if let previousSelectedCorridorID,
               corridors.contains(where: { $0.id == previousSelectedCorridorID }) {
                selectedCorridorID = previousSelectedCorridorID
            } else if corridors.count == 1 {
                selectedCorridorID = corridors[0].id
            }
        }
    }

    private func commit() {
        if var draft = timetableTrain {
            guard canSave else { return }
            draft.id = train.id
            draft.region = region.code
            let serviceDate = draft.date ?? dayString(departure)
            draft.date = serviceDate
            if timetableTrainTypeChanged { draft.trainType = trainType }
            let span = timetableRideSpan ?? 0...(draft.stops.count - 1)
            for index in draft.stops.indices {
                draft.stops[index].rideSegment = span.contains(index) && isRidden
            }
            let pickerDeparture = clock(
                departure, extraDays: extraDays(from: serviceDate, to: departure))
            if draft.stops[span.lowerBound].departure != pickerDeparture {
                draft.stops[span.lowerBound].departure = pickerDeparture
            }
            let pickerArrival = clock(
                arrival, extraDays: extraDays(from: serviceDate, to: arrival))
            if draft.stops[span.upperBound].arrival != pickerArrival {
                draft.stops[span.upperBound].arrival = pickerArrival
            }
            if !companyName.isEmpty {
                commitCompany(companyName, on: &draft)
            }
            let number = trainNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            draft.number = [number, draft.number, limitedExpressName,
                            draft.routeSections?.first?.lineNames?.first ?? originLine?.name ?? ""]
                .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
            draft.origin = draft.stops[span.lowerBound].name
            draft.destination = draft.stops[span.upperBound].name
            saveIssues = RideDraftValidation.issues(
                for: draft, originalID: train.id, existingIDs: itineraries?.trainIDs ?? []).blocking
            guard saveIssues.isEmpty else { return }
            onSave(draft)
            return
        }
        guard canSave, let corridor = selectedCorridor else { return }
        guard let draft = draft(for: corridor) else {
            autofillFailed = true
            return
        }
        let blocking = RideDraftValidation.issues(
            for: draft, originalID: train.id, existingIDs: itineraries?.trainIDs ?? []).blocking
        guard blocking.isEmpty else {
            saveIssues = blocking
            return
        }
        saveIssues = []
        onSave(draft)
    }

    /// Build exactly the candidate that saving this corridor would persist.
    private func draft(for corridor: TripRoutePlanner.Corridor) -> Train? {
        guard let origin, let destination else { return nil }
        var draft = train
        draft.region = region.code
        // Same mapping StationPickerView uses: CatalogStation.key.sourceCode.
        draft.stops = [
            endpointStop(origin, stationID: originStationID, stopType: "origin", ridden: isRidden),
            endpointStop(destination, stationID: destinationStationID, stopType: "destination", ridden: isRidden),
        ]
        // Only endpoint stops are replaced here. Physical confirmation comes
        // from the resolver result for this exact planning input.
        guard let proposal = LocalJourneyAutofill.proposal(train: draft, choice: corridor.choice),
              proposal.train.stops.count >= 2 else { return nil }
        draft = proposal.train
        draft.routeConfirmation = plannedIdentity == routeIdentity
            && physicallyResolvedCorridorIDs.contains(corridor.id) ? .confirmed : .pending
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
            commitCompany(joined, on: &draft)
        } else {
            commitCompany(companyName, on: &draft)
        }
        draft.origin = origin.name
        draft.destination = destination.name
        return draft
    }

    private func validationMessage(_ issue: RideDraftIssue) -> String {
        if let literal = issue.literal { return literal }
        return localization.text(issue.key, params: issue.params)
    }

    private func stationCountText(_ corridor: TripRoutePlanner.Corridor) -> String {
        let count = String(corridor.passStationCount)
        guard plannedIdentity == routeIdentity,
              physicallyResolvedCorridorIDs.contains(corridor.id),
              let kilometers = kilometerString(corridor.distanceKm) else {
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
        case .none:
            return text("unverifiedConnection", fallback: "Unverified connection at {station}",
                        ["station": .string(station)])
        case .sameLine:
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
        RecordDate.text(from: date)
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

    private func extraDays(from serviceDate: String, to date: Date) -> Int {
        guard let serviceDay = timetableDate(serviceDate, time: "00:00") else { return 0 }
        return extraDays(from: serviceDay, to: date)
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
