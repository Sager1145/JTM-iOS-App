import Observation
import RailApplication
import RailCore
import RailPresentation
import SwiftUI

/// The journey editor's draft: every value the reader is editing, the
/// planner's caches for it, and the work that turns them into a record.
/// `JourneyEditorView` owns one for its lifetime; its sections read and
/// write it. Values that came from the reader are recorded in `touched`.
@MainActor
@Observable
final class TripDraftModel {
    typealias PlannedSection = JourneyEditorView.PlannedSection

    static let serviceTypes = JourneyDraftWork.serviceTypeIDs
    static let recordRouteID = "record"
    static let repairRoutePrefix = "repair-"
    static let alternativePrefix = "alt"

    /// A value the reader set. A shift that follows the departure, or a
    /// value a ticket, timetable or history filled, does not count: those
    /// are in `filledBy`, and no fill ever writes a field in `touched`.
    enum Field: Hashable, CaseIterable {
        case departure
        case arrival
        /// The departure's day, from a ticket that printed no time.
        case date
        /// The arrival's day, set on its own without a clock.
        case arrivalDate
        case origin
        case destination
        case trainType
        case number
        case company
        case serviceName
        case vehicleType
        case setNumber
        case carCount
        case riddenCar
        case carNumbers
        case livery
        case seat
        case seatClass
        case fare
        case ticketKind
        /// Observed clocks. Only the reader writes them; no source fills them.
        case actualDeparture
        case actualArrival
    }

    /// Where an automatic value came from, shown beside the field.
    enum FillSource: String, Equatable {
        case ticket
        case timetable
        case nearby
    }

    /// Where a change to the header comes from.
    enum PatchSource: Equatable {
        /// The reader, in a picker or field.
        case reader
        /// A timetable being applied: nothing becomes touched and the
        /// applied timetable is kept.
        case timetable
        /// A ticket scan: nothing becomes touched.
        case ticket
    }

    /// Header values to change together. A nil value is left as it is.
    struct Patch {
        var trainType: String?
        var departure: Date?
        var arrival: Date?
    }

    struct HeaderSnapshot {
        var trainType: String
        var departure: Date
        var arrival: Date
        var previousDeparture: Date
        var touched: Set<Field>
        var filledBy: [Field: FillSource]
        var cleared: Set<Field> = []
    }

    /// A route change that would drop recorded stops, waiting for the reader.
    struct RemovalRequest: Identifiable {
        enum Action { case save, repair(Int) }
        let id = UUID()
        var action: Action
        var stations: [String]
    }

    enum StationField: String, Identifiable {
        case origin
        case via
        case destination
        var id: String { rawValue }
    }

    /// A reader-chosen station the route must pass. Narrows the planner's
    /// candidates; saved only as an ordinary visit of the chosen route.
    struct ViaStop: Identifiable, Equatable {
        let id = UUID()
        var station: CatalogStation
        var stationID: String?
    }

    var region: Region
    var catalog: EditorCatalog?
    var package: CompactPackage?
    var loadFailed = false
    var origin: CatalogStation?
    var destination: CatalogStation?
    var originLine: CatalogLine?
    var destinationLine: CatalogLine?
    var originStationID: String?
    var destinationStationID: String?
    var trainType: String
    var timetableTrain: Train?
    var timetableRideSpan: ClosedRange<Int>?
    var timetableTrainTypeChanged = false
    var limitedExpressName = ""
    var showsTimetablePicker = false
    var timetableFailed = false
    var trainNumber = ""
    var companyName = ""
    var departure: Date
    var arrival: Date
    var previousDeparture: Date
    var draftMapRevision = 0
    /// Date prefill remains live until the reader makes an explicit choice.
    var riddenOverride: Bool?
    var picking: StationField?
    var allowUnverifiedConnections = false
    var outcome: TripRoutePlanner.Outcome?
    /// `routeIdentity` that `outcome` was planned for. A newer identity makes the outcome stale.
    var plannedIdentity = ""
    var physicallyResolvedCorridorIDs: Set<String> = []
    /// Why the corridors on screen were not marked proven. Saving them stays allowed.
    var routeProofFailure: String?
    /// Bumped when the region changes. A search or plan started earlier must not write this draft.
    var draftGeneration = 0
    /// Bumped when this region's registry settles so the timetable query resolves again.
    var registryEpoch = 0
    var searching = false
    var selectedCorridorID: String?
    var corridorsRemovedByDate = false
    /// The corridor the reader last picked, kept across replans that are
    /// cancelled before they finish and so never restore the live selection.
    /// The trip in station-to-station sections, in travel order.
    var sections: [PlannedSection] = []
    /// The reader's corridor per section, by section key, kept across replans.
    var sectionChoices: [String: String] = [:]
    /// The section whose candidates are listed and drawn as alternatives.
    var activeSection = 0
    /// Planned sections by key for this session, so moving one via only
    /// re-plans the sections next to it.
    var sectionCache: [String: PlannedSection] = [:]
    /// Dated-network probes by from/to/ride date, so a train-type or company
    /// change does not ask again.
    var historicalProbeCache: [String: PlannedSection.HistoricalProbe] = [:]
    var wholeTripCache: [String: [TripRoutePlanner.Corridor]] = [:]
    var wholeTrip: [TripRoutePlanner.Corridor] = []
    var activeSectionKey: String?
    /// Interchange codes folded together, for joining sections at a via.
    var sectionAliases: [String: String] = [:]
    var autofillFailed = false
    var saveIssues: [RideDraftIssue] = []
    /// Catalog operator id → display name. Rebuilt when the catalog or stations change.
    var operatorNameByID: [String: String] = [:]
    /// Catalog display name → `CompactPackage.Line.operator`, the string the planner compares.
    var packageOperatorByDisplayName: [String: String] = [:]
    var companyOptions: [String] = []
    var lineLabelByID: [String: String] = [:]
    var vias: [ViaStop] = []
    /// Station the reader tapped on the map, waiting for From / Via / To.
    var tappedStation: CatalogStation?
    /// Track geometry for each planned corridor id, built off the main actor.
    var corridorGeometry: [String: [TripRouteGeometry.Piece]] = [:]
    var lineColorByID: [String: String] = [:]
    var mapFitRevision = 0
    var mapZoomedIn = false
    var mapStations: [CatalogStation] = []
    /// Routes on the map. Kept through a replan so the line does not blink out.
    var drawnRoutes: [TripMapContent.Route] = []
    var routeFitIdentity = ""
    /// The record being edited. Route planning, a timetable and repair write
    /// into it only through `commit`, `applyCorridor` and the repair controller.
    var draft: Train
    var seed: EditorSeed
    /// `stationIdentity` of the saved route once its stations are found in
    /// the catalog. Nil until then. While the identity still matches, the
    /// saved stops are the route and nothing is replanned.
    var seededStationIdentity: String?
    /// Track of the saved route, drawn while it is unchanged.
    var recordGeometry: [TripRouteGeometry.Piece] = []
    let repair = RouteRepairController()
    /// Interval track decoded once per line for this editor session, over the
    /// shared resident package. Planning, the saved route and repair reuse it.
    var geometryCache: TripRouteGeometry.Cache?
    var repairStarted = false
    var showsFillDetails = false
    var detailIssues: [RideDraftIssue] = []
    var showsCompletion = false
    /// Header fields the reader set (`apply(_:source:)` with `.reader`).
    var touched: Set<Field> = []
    /// Clocks (`.departure`, `.arrival`) the reader emptied: no source writes
    /// them again, and a saved journey's clock on that side is removed.
    var clearedClocks: Set<Field> = []
    /// Fields an automatic source wrote, and which source. Cleared for a
    /// field the moment the reader sets it.
    var filledBy: [Field: FillSource] = [:]
    /// The ticket scan sheet.
    var showsTicketScan = false
    /// What the last ticket scan filled, for the summary under Quick fill.
    var ticketFillCount: Int?
    /// A timetable lookup a ticket started.
    var ticketMatchTask: Task<Void, Never>?
    /// The timetable trip last applied, so a late formation lookup lands
    /// only on the trip it was read for.
    var appliedTimetableTripID: String?
    /// Stations near the reader, offered under From on a new trip.
    var nearbyStations: [NearbyStation] = []
    /// Observed clocks as typed (`actual_departure` on the boarding stop,
    /// `actual_arrival` on the alighting stop). Stored on save.
    var actualDeparture: String?
    var actualArrival: String?
    /// The Time section shows the two actual-time rows.
    var showsActualTimes = false
    /// Actual clocks a chip wrote and the reader has not typed over. A chip
    /// replaces only these (or an empty field), never a typed value.
    var chipSetActuals: Set<Field> = []
    /// The record's own actual departure and arrival, for `isDirty`.
    var seededActualTimes: [String?] = [nil, nil]

    struct NearbyStation: Identifiable, Equatable {
        var station: CatalogStation
        var meters: Double
        var id: StationKey { station.key }
    }
    /// Header values before a timetable was applied, restored by Remove.
    var headerBeforeTimetable: HeaderSnapshot?
    var removal: RemovalRequest?
    /// Passenger direction per line stretch of the route on screen. Read
    /// from the route, never typed.
    var directionLegs: [TravelDirection.Leg] = []
    var showsBoundForEntry = false
    var showsVehiclePicker = false
    /// Platforms typed before the route has stops of its own (a new trip);
    /// written onto the ride's first and last stop when it is saved.
    var pendingDeparturePlatform: Int?
    var pendingArrivalPlatform: Int?
    var boundForDraft = ""
    var detailsExpanded: Bool
    /// The draft's stops are the route: a saved journey, or a completion the
    /// reader applied. False only for a new trip still choosing its route.
    var hasRecordRoute: Bool
    /// The editor was opened to add a trip, not to edit a saved one.
    let isNewTrip: Bool

    init(train: Train, isNew: Bool) {
        draft = train
        hasRecordRoute = !isNew
        isNewTrip = isNew
        // Collapsed until asked for: its lookups (the official English name
        // reads the timetable database) are work a route edit does not need.
        detailsExpanded = false
        let initialRegion = Region(rawValue: train.region ?? "") ?? Region.resolved(train)
        region = initialRegion
        let seeded = EditorSeed(train: train, isNew: isNew, clock: initialRegion.clock)
        seed = seeded
        trainType = seeded.trainType
        trainNumber = seeded.number
        companyName = seeded.company
        departure = seeded.departure
        arrival = seeded.arrival
        previousDeparture = seeded.departure
        if !isNew { seedActualTimes(from: train) }
    }

    // MARK: - actual times

    /// The stop the reader boarded at and the one they left at; RailKit's
    /// one rule (`Train.boardingStopIndex` / `alightingStopIndex`).
    nonisolated static func boardingIndex(_ stops: [Stop]) -> Int? {
        stops.boardingStopIndex
    }

    nonisolated static func alightingIndex(_ stops: [Stop]) -> Int? {
        stops.alightingStopIndex
    }

    func seedActualTimes(from train: Train) {
        actualDeparture = Self.boardingIndex(train.stops).flatMap { train.stops[$0].actualDeparture }
        actualArrival = Self.alightingIndex(train.stops).flatMap { train.stops[$0].actualArrival }
        seededActualTimes = [actualDeparture, actualArrival]
        showsActualTimes = actualDeparture != nil || actualArrival != nil
    }

    func seededActual(isDeparture: Bool) -> String? {
        seededActualTimes[isDeparture ? 0 : 1]
    }

    /// The text field's binding. Typing is kept as typed (a half-typed clock
    /// must not be rewritten); it is normalized on save.
    func actualTimeText(isDeparture: Bool) -> Binding<String> {
        Binding(
            get: { (isDeparture ? self.actualDeparture : self.actualArrival) ?? "" },
            set: { raw in
                // Spaces carry no meaning in a clock, so they never reach the record.
                let trimmed = raw.trimmingCharacters(in: .whitespaces)
                let value = trimmed.isEmpty ? nil : trimmed
                guard value != (isDeparture ? self.actualDeparture : self.actualArrival) else { return }
                self.markTouched(isDeparture ? .actualDeparture : .actualArrival)
                self.chipSetActuals.remove(isDeparture ? .actualDeparture : .actualArrival)
                if isDeparture { self.actualDeparture = value } else { self.actualArrival = value }
            })
    }

    /// A typed (not chip-set) actual clock is present: chips leave it alone.
    func actualIsTyped(isDeparture: Bool) -> Bool {
        let field: Field = isDeparture ? .actualDeparture : .actualArrival
        return (isDeparture ? actualDeparture : actualArrival) != nil && !chipSetActuals.contains(field)
    }

    /// A chip: the actual clock is the scheduled clock plus `minutes`, done on
    /// the clock text alone (no calendar, no time zone). A typed value stays.
    func applyActualChip(minutes: Int, isDeparture: Bool) {
        guard !actualIsTyped(isDeparture: isDeparture),
              let scheduled = scheduledClock(isDeparture: isDeparture),
              case .valid(_, let planned) = EditorTime.parseTime(scheduled)
        else { return }
        let total = planned.serviceMinutes + minutes
        let time = ServiceClockTime(dayOffset: total / 1440, hour: total % 1440 / 60, minute: total % 60)
        let field: Field = isDeparture ? .actualDeparture : .actualArrival
        markTouched(field)
        chipSetActuals.insert(field)
        if isDeparture { actualDeparture = EditorTime.canonical(time) } else { actualArrival = EditorTime.canonical(time) }
    }

    /// The scheduled clock an actual one is compared with, as stored.
    func scheduledClock(isDeparture: Bool) -> String? {
        guard scheduledIsSet(isDeparture: isDeparture) else { return nil }
        let date = isDeparture ? departure : arrival
        return clock(date, extraDays: extraDays(from: headerServiceDate(), to: date))
    }

    /// The clock a typed one is read against: the scheduled clock when it is
    /// real, else the actual departure for an arrival. Never a placeholder.
    func plannedReference(isDeparture: Bool) -> String? {
        if let scheduled = scheduledClock(isDeparture: isDeparture) { return scheduled }
        guard !isDeparture, case .valid(_, let left) = EditorTime.parseTime(actualDeparture) else { return nil }
        return EditorTime.canonical(left)
    }

    /// A typed clock as stored: canonical, and read as past midnight when it
    /// is more than twelve hours before its scheduled clock (`0:10` against
    /// `23:55` is `24:10`). Nil for blank or unreadable text.
    func normalizedActual(_ raw: String?, isDeparture: Bool) -> String? {
        guard case .valid(_, var time) = EditorTime.parseTime(raw) else { return nil }
        if case .valid(_, let planned) = EditorTime.parseTime(plannedReference(isDeparture: isDeparture)),
           time.serviceMinutes - planned.serviceMinutes < -720 {
            time.dayOffset += 1
        }
        return EditorTime.canonical(time)
    }

    /// Writes the observed clocks onto the ride's boarding and alighting
    /// stops. Unreadable text is kept as typed, like a stop's own field.
    func applyActualTimes(to result: inout Train) {
        // Per side: the reader's Time-section change wins (normalized);
        // otherwise the value the trip was saved with, as stored. A stop that
        // already holds a value on an unchanged side keeps it (a stop-editor
        // edit); a replaced stop that lost it gets the stored value back.
        func resolve(_ current: String?, shown: String?, isDeparture: Bool) -> String?? {
            let seeded = seededActual(isDeparture: isDeparture)
            let changed = shown != seeded
            let desired: String?
            if changed {
                desired = shown.map { normalizedActual($0, isDeparture: isDeparture) ?? $0 }
            } else {
                desired = seeded
            }
            if current == desired || (!changed && current != nil) { return nil }
            return .some(desired)
        }
        if let index = Self.boardingIndex(result.stops),
           let write = resolve(result.stops[index].actualDeparture, shown: actualDeparture, isDeparture: true) {
            result.stops[index].actualDeparture = write
        }
        if let index = Self.alightingIndex(result.stops),
           let write = resolve(result.stops[index].actualArrival, shown: actualArrival, isDeparture: false) {
            result.stops[index].actualArrival = write
        }
    }

    // MARK: - header changes

    /// The one way header values change from outside the model. The
    /// reader's changes are recorded in `touched`; a timetable's are not.
    func apply(_ patch: Patch, source: PatchSource) {
        if let value = patch.trainType {
            if source == .reader, timetableTrain != nil, value != trainType { timetableTrainTypeChanged = true }
            if source == .reader { markTouched(.trainType) }
            trainType = value
        }
        if let value = patch.departure { setTime(value, field: .departure, source: source) }
        if let value = patch.arrival { setTime(value, field: .arrival, source: source) }
    }

    private func setTime(_ value: Date, field: Field, source: PatchSource) {
        let isDeparture = field == .departure
        let previous = isDeparture ? departure : arrival
        // Only the departure day identifies the service; overnight
        // arrivals legitimately fall on the next civil day.
        // A reader moving the day, or a ticket naming another day, replaces
        // a timetable that ran on a different day.
        if isDeparture, let timetableTrain, dayString(value) != timetableTrain.date,
           source == .ticket || (source == .reader && dayString(value) != dayString(previous)) {
            clearTimetable()
        }
        if source == .reader {
            touched.insert(field)
            clearedClocks.remove(field)
            filledBy[field] = nil
            if isDeparture { filledBy[.date] = nil }
        }
        if isDeparture { departure = value } else { arrival = value }
    }

    /// The reader moved only the day: the side keeps its wall clock, and
    /// neither clock becomes set. A departure day other than the applied
    /// timetable's replaces it, like a time on another day.
    func setDay(_ day: Date, isDeparture: Bool) {
        let calendar = region.clock.calendar
        if isDeparture, let timetableTrain, dayString(day) != timetableTrain.date,
           dayString(day) != dayString(departure) {
            clearTimetable()
        }
        let current = isDeparture ? departure : arrival
        var parts = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: current)
        let civil = calendar.dateComponents([.year, .month, .day], from: day)
        parts.year = civil.year
        parts.month = civil.month
        parts.day = civil.day
        guard let next = calendar.date(from: parts) else { return }
        markTouched(isDeparture ? .date : .arrivalDate)
        if isDeparture { departure = next } else { arrival = next }
    }

    /// The reader emptied a clock: it is unset, and the day it was on stays counted.
    func clearTime(isDeparture: Bool) {
        let side: Field = isDeparture ? .departure : .arrival
        if isDeparture {
            if touched.contains(.departure) {
                touched.insert(.date)
            } else if filledBy[.departure] == .ticket {
                filledBy[.date] = .ticket
            }
        }
        touched.remove(side)
        filledBy[side] = nil
        clearedClocks.insert(side)
    }

    // MARK: - editor events

    /// The departure moved: the arrival follows by the same amount.
    func departureChanged(to newValue: Date) {
        // Wall-clock minutes on the region's calendar, not a raw interval.
        let calendar = region.clock.calendar
        // A blank departure clock shows a placeholder hour. A typed arrival
        // follows a day move by whole days, keeping its own clock, and is
        // never clamped onto that placeholder.
        if !scheduledIsSet(isDeparture: true), timeIsSet(.arrival) {
            let days = calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: previousDeparture),
                to: calendar.startOfDay(for: newValue)).day ?? 0
            arrival = calendar.date(byAdding: .day, value: days, to: arrival) ?? arrival
            previousDeparture = newValue
            saveIssues = []
            return
        }
        let moved = calendar.dateComponents([.minute], from: previousDeparture, to: newValue).minute ?? 0
        let shiftedArrival = calendar.date(byAdding: .minute, value: moved, to: arrival) ?? arrival
        arrival = max(shiftedArrival, newValue)
        previousDeparture = newValue
        saveIssues = []
    }

    /// A station chosen in the picker, unless the region changed since it opened.
    func pick(
        _ station: CatalogStation, line: CatalogLine?, stationID: String?,
        for field: StationField, generation: Int
    ) {
        guard generation == draftGeneration else {
            picking = nil
            return
        }
        clearTimetable()
        markStationTouched(field)
        switch field {
        case .origin:
            origin = station
            originLine = line
            originStationID = stationID
        case .via:
            vias.append(ViaStop(station: station, stationID: stationID))
        case .destination:
            destination = station
            destinationLine = line
            destinationStationID = stationID
        }
        picking = nil
    }

    /// Re-reads every held `Date` on the current region's calendar with the
    /// wall clock it had on `old`.
    private func keepWallClock(from old: RegionClock) {
        let parts: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        func moved(_ date: Date) -> Date {
            region.clock.calendar.date(from: old.calendar.dateComponents(parts, from: date)) ?? date
        }
        departure = moved(departure)
        arrival = moved(arrival)
        previousDeparture = moved(previousDeparture)
        seed.departure = moved(seed.departure)
        seed.arrival = moved(seed.arrival)
    }

    /// A new region starts the route over in that region's network.
    ///
    /// The clocks the reader set keep their wall clock: every held `Date` is
    /// read on the region's calendar, so each is re-expressed from the old
    /// region's calendar to the new one (09:30 stays 09:30).
    func regionChanged(from old: Region) {
        draftGeneration += 1
        picking = nil
        // Another network: its stations and any ticket's values start over.
        ticketMatchTask?.cancel()
        // First: undoing a timetable restores header instants captured on
        // the OLD region's clock, so the wall-clock move must come after it
        // or a restored 10:30 JST would read 09:30 in Taipei.
        clearTimetable()
        keepWallClock(from: old.clock)
        filledBy = [:]
        touched.subtract([.origin, .destination, .serviceName])
        nearbyStations = []
        ticketFillCount = nil
        allowUnverifiedConnections = false
        if isNewTrip {
            // Each side separately: the reader's clock stays, the other
            // starts over on the new region's wall clock.
            let now = Date()
            if !timeIsSet(.departure), !touched.contains(.date) { departure = now }
            previousDeparture = departure
            if !timeIsSet(.arrival), !touched.contains(.arrivalDate) { arrival = now }
        }
        limitedExpressName = ""
        origin = nil
        destination = nil
        originLine = nil
        destinationLine = nil
        originStationID = nil
        destinationStationID = nil
        vias = []
        tappedStation = nil
        corridorGeometry = [:]
        drawnRoutes = []
        routeFitIdentity = ""
        lineColorByID = [:]
        mapStations = []
        if hasRecordRoute {
            // Relabelling a saved journey: find its stations again in the
            // new region's catalog, and keep the operator it already names.
            seededStationIdentity = nil
        } else {
            companyName = ""
        }
        catalog = nil
        package = nil
        geometryCache = nil
        outcome = nil
        plannedIdentity = ""
        physicallyResolvedCorridorIDs.removeAll()
        routeProofFailure = nil
        selectedCorridorID = nil
        corridorsRemovedByDate = false
        sections = []
        sectionChoices = [:]
        sectionCache = [:]
        wholeTripCache = [:]
        wholeTrip = []
        activeSection = 0
        activeSectionKey = nil
        sectionAliases = [:]
        autofillFailed = false
        loadFailed = false
        saveIssues = []
        refreshCompanyCache()
    }

    /// Leaving asks only when Save would write something.
    func isDirty(original train: Train) -> Bool {
        if draft != train || timetableTrain != nil || riddenOverride != nil
            || pendingDeparturePlatform != nil || pendingArrivalPlatform != nil { return true }
        if actualDeparture != seededActual(isDeparture: true) || actualArrival != seededActual(isDeparture: false) {
            return true
        }
        if trainType != seed.trainType || trainNumber != seed.number || companyName != seed.company
            || departure != seed.departure || arrival != seed.arrival { return true }
        if clearedClocks.contains(.departure) && seed.departureKnown
            || clearedClocks.contains(.arrival) && seed.arrivalKnown { return true }
        if hasRecordRoute { return routeEdited }
        return origin != nil || destination != nil || !vias.isEmpty
    }

    struct RecordGeometryKey: Equatable {
        var sections: [RouteSection]
        var loaded: Bool
    }

    func loadRecordGeometry() async {
        guard showsRecordRoute, let geometryCache else {
            if !recordGeometry.isEmpty {
                recordGeometry = []
                refreshDrawnRoutes()
            }
            return
        }
        let sections = draft.routeSections ?? []
        let pieces = await Task.detached(priority: .userInitiated) {
            TripRouteGeometry.pieces(for: sections, cache: geometryCache)
        }.value
        guard !Task.isCancelled else { return }
        let firstDraw = recordGeometry.isEmpty
        recordGeometry = pieces
        refreshDrawnRoutes()
        if firstDraw, !pieces.isEmpty { mapFitRevision += 1 }
    }

    func applyRepair(_ expected: Train, _ result: Train) -> Bool {
        guard draft == expected else { return false }
        draft = result
        return true
    }

    func startRepair(gaps repairGaps: [RouteRepair.Gap]?, text repairText: @escaping RouteRepairController.Text) {
        guard let package, let geometryCache, let gaps = repairGaps else { return }
        repairStarted = true
        repair.start(train: draft, gaps: gaps, package: package, geometry: geometryCache, text: repairText, apply: applyRepair)
    }

    func chooseRepair(
        _ index: Int, confirmedRemoval: Bool = false, text repairText: @escaping RouteRepairController.Text
    ) {
        guard let package, let geometryCache, let pause = repair.pause, pause.choices.indices.contains(index) else { return }
        let choice = pause.choices[index]
        if !confirmedRemoval, let plan = repair.plan(for: choice), plan.requiresConfirmation {
            removal = RemovalRequest(action: .repair(index), stations: plan.conflictingStops.map(\.name))
            return
        }
        repair.choose(choice, package: package, geometry: geometryCache, text: repairText, apply: applyRepair)
    }

    func skipRepair(text repairText: @escaping RouteRepairController.Text) {
        guard let package, let geometryCache else { return }
        repair.skip(package: package, geometry: geometryCache, text: repairText, apply: applyRepair)
    }

    enum MapRole: Equatable { case origin, via(UUID), destination }

    func mapRole(of station: CatalogStation) -> MapRole? {
        if origin?.key == station.key { return .origin }
        if destination?.key == station.key { return .destination }
        if let via = vias.first(where: { $0.station.key == station.key }) { return .via(via.id) }
        return nil
    }

    func assign(_ station: CatalogStation, to field: StationField, reduceMotion: Bool) {
        clearTimetable()
        markStationTouched(field)
        switch field {
        case .origin:
            origin = station
            originLine = nil
            originStationID = nil
        case .via:
            vias.append(ViaStop(station: station, stationID: nil))
        case .destination:
            destination = station
            destinationLine = nil
            destinationStationID = nil
        }
        withAnimation(RailMotion.animation(RailMotion.enter, reduceMotion: reduceMotion)) {
            tappedStation = nil
        }
    }

    func removeFromTrip(_ station: CatalogStation, role: MapRole, reduceMotion: Bool) {
        clearTimetable()
        switch role {
        case .origin:
            origin = nil
            originLine = nil
            originStationID = nil
        case .destination:
            destination = nil
            destinationLine = nil
            destinationStationID = nil
        case .via(let id):
            vias.removeAll { $0.id == id }
        }
        withAnimation(RailMotion.animation(RailMotion.enter, reduceMotion: reduceMotion)) {
            tappedStation = nil
        }
    }

    /// Endpoints and vias only; a change reframes the camera.
    var endpointIdentity: String {
        ([origin, destination].map { $0?.key.sourceCode ?? "" }
            + vias.map(\.station.key.sourceCode)).joined(separator: ",")
    }

    func mapRoute(id: String, pieces: [TripRouteGeometry.Piece], selected: Bool) -> TripMapContent.Route {
        TripMapContent.Route(
            id: id,
            pieces: pieces.map { piece in
                TripMapContent.Piece(
                    coordinates: AppleMapDatum.display(piece.coordinates, country: region.code)
                        .map(\.clLocation),
                    colorHex: piece.lineID.flatMap { lineColorByID[$0] },
                    isConnector: piece.isConnector)
            },
            isSelected: selected)
    }

    func refreshDrawnRoutes() {
        if showsRecordRoute {
            var routes: [TripMapContent.Route] = []
            if !recordGeometry.isEmpty {
                routes.append(mapRoute(id: Self.recordRouteID, pieces: recordGeometry, selected: true))
            }
            // A paused repair offers its span's tracks as the alternatives.
            for (index, pieces) in (repair.pause?.geometry ?? []).prefix(JourneyEditorView.maximumDrawnRoutes).enumerated()
            where !pieces.isEmpty {
                routes.append(mapRoute(id: Self.repairRoutePrefix + String(index), pieces: pieces, selected: false))
            }
            drawnRoutes = routes
            return
        }
        guard origin != nil, destination != nil, timetableTrain == nil else {
            drawnRoutes = []
            return
        }
        // Mid-replan the previous routes stay until the new sections land.
        guard !sections.isEmpty else { return }
        var routes: [TripMapContent.Route] = []
        // The active section's other candidates, grey and tappable.
        if sections.indices.contains(activeSection) {
            let section = sections[activeSection]
            let chosen = choice(for: section)
            for corridor in section.candidates.prefix(JourneyEditorView.maximumDrawnRoutes) where corridor.id != chosen
                || section.candidates.count > 1 && chosen == nil {
                guard let pieces = section.geometry[corridor.id], !pieces.isEmpty else { continue }
                routes.append(mapRoute(
                    id: [Self.alternativePrefix, String(activeSection), corridor.id].joined(separator: "|"),
                    pieces: pieces, selected: false))
            }
        }
        // Every section's choice so far, as one selected route.
        let chosenPieces = sections.flatMap { section -> [TripRouteGeometry.Piece] in
            guard let id = choice(for: section) else { return [] }
            return section.geometry[id] ?? []
        }
        if !chosenPieces.isEmpty {
            routes.append(mapRoute(id: selectedCorridorID ?? "chosen", pieces: chosenPieces, selected: true))
        }
        drawnRoutes = routes
    }

    /// The standard service types, plus a saved journey's own type so it
    /// is shown and kept rather than replaced by the first standard one.
    var trainTypeOptions: [String] {
        var options = Self.serviceTypes
        for type in [seed.trainType, trainType] where !options.contains(type) { options.append(type) }
        return options
    }

    var shownCompanyOptions: [String] {
        guard !companyName.isEmpty, !companyOptions.contains(companyName) else { return companyOptions }
        return companyOptions + [companyName]
    }

    /// The ride's first and last stop: the saved stops, or values held until
    /// a new route has stops to put them on.
    var departurePlatform: Binding<Int?> {
        showsRecordRoute && !draft.stops.isEmpty
            ? Binding(get: { self.draft.stops.first?.platformNumber },
                      set: { if !self.draft.stops.isEmpty { self.draft.stops[0].platformNumber = $0 } })
            : Binding(get: { self.pendingDeparturePlatform }, set: { self.pendingDeparturePlatform = $0 })
    }

    var arrivalPlatform: Binding<Int?> {
        showsRecordRoute && draft.stops.count >= 2
            ? Binding(get: { self.draft.stops.last?.platformNumber },
                      set: { if self.draft.stops.count >= 2 { self.draft.stops[self.draft.stops.count - 1].platformNumber = $0 } })
            : Binding(get: { self.pendingArrivalPlatform }, set: { self.pendingArrivalPlatform = $0 })
    }

    var missingDetails: MissingTripDetails {
        MissingTripDetails(
            train: showsRecordRoute ? draft : { var t = draft; t.stops = []; return t }(),
            departurePlatform: departurePlatform.wrappedValue,
            arrivalPlatform: arrivalPlatform.wrappedValue)
    }

    /// The applied timetable's own vehicle first, then the reader's history.
    func vehicleSuggestions(among suggestionTrains: [Train]) -> [String] {
        var base = draft
        if let timetableTrain { base.routeSections = timetableTrain.routeSections }
        else if routeEdited, let corridor = selectedCorridor { base.routeSections = corridor.choice.routeSections }
        var values = VehiclePickerView.suggestions(for: base, among: suggestionTrains)
        if let official = timetableTrain?.vehicleType, !official.isEmpty, !values.contains(official) {
            values.insert(official, at: 0)
        }
        return values
    }

    /// Platforms typed before the route existed go onto the saved ride's ends.
    func applyPendingPlatforms(to result: inout Train, span: ClosedRange<Int>? = nil) {
        guard result.stops.count >= 2 else { return }
        let range = span ?? 0...(result.stops.count - 1)
        if let pendingDeparturePlatform { result.stops[range.lowerBound].platformNumber = pendingDeparturePlatform }
        if let pendingArrivalPlatform { result.stops[range.upperBound].platformNumber = pendingArrivalPlatform }
    }

    /// Lines of the route on screen, for the line's service types.
    var routeLineIDs: [String] {
        let sections: [RouteSection]
        if let timetableTrain {
            sections = timetableTrain.routeSections ?? []
        } else if routeEdited {
            return selectedCorridor?.choice.lineIDs ?? []
        } else {
            sections = draft.routeSections ?? []
        }
        var seen: Set<String> = []
        return sections.flatMap { $0.lineIDs ?? [] }.filter { seen.insert($0).inserted }
    }

    /// What Save would write now, without validating it.
    func currentResult(original train: Train) -> Train? {
        if let timetableTrain { return timetableResult(timetableTrain, original: train) }
        if routeEdited { return selectedCorridor.flatMap(corridorDraft(for:)) ?? historicalDraft() }
        var result = draft
        result.region = region.code
        applyHeader(to: &result)
        return result
    }

    /// A reviewed completion becomes the record: its stops are the route,
    /// and the header shows its values.
    func adoptCompletedRecord(_ completed: Train) {
        var completed = completed
        if completed.stops != draft.stops || completed.routeSections != draft.routeSections,
           completed.routeConfirmation == .confirmed {
            completed.routeConfirmation = nil
        }
        clearTimetable()
        vias = []
        draft = completed
        hasRecordRoute = completed.stops.count >= 2
        let seeded = EditorSeed(train: completed, isNew: false, clock: region.clock)
        seed = seeded
        trainType = seeded.trainType
        trainNumber = seeded.number
        companyName = seeded.company
        departure = seeded.departure
        arrival = seeded.arrival
        previousDeparture = seeded.departure
        riddenOverride = nil
        clearedClocks = []
        seedActualTimes(from: completed)
        seededStationIdentity = nil
        if let catalog { seedStations(from: catalog) }
    }

    var isRidden: Bool {
        riddenOverride ?? (hasRecordRoute ? RideLedger.hasBeenRidden(draft) : prefillRidden(
            forDate: dayString(departure), startClock: startClock, timeIsSet: startClock != nil))
    }

    /// The clock the trip starts at: the actual departure, else a real
    /// scheduled one. Nil when every clock is the editor's placeholder.
    private var startClock: String? {
        if let actual = normalizedActual(actualDeparture, isDeparture: true) { return actual }
        if scheduledIsSet(isDeparture: true) { return clock(departure, extraDays: 0) }
        if scheduledIsSet(isDeparture: false) {
            return clock(arrival, extraDays: extraDays(from: departure, to: arrival))
        }
        return nil
    }

    /// A header clock is real: the reader, a ticket, a timetable or the saved
    /// journey gave it. A new trip's untouched header shows only the moment
    /// the editor opened, which is a date and not a time.
    var headerTimeIsSet: Bool {
        scheduledIsSet(isDeparture: true) || scheduledIsSet(isDeparture: false)
    }

    /// The reader or a ticket gave this clock, and it was not emptied since;
    /// the editor's placeholder did not.
    func timeIsSet(_ field: Field) -> Bool {
        !clearedClocks.contains(field) && (touched.contains(field) || filledBy[field] == .ticket)
    }

    /// The departure's day is the reader's or a ticket's: set on its own, or
    /// carried by a departure clock (even one since emptied).
    var dayIsSet: Bool {
        timeIsSet(.departure) || touched.contains(.date) || filledBy[.date] != nil
    }

    /// One scheduled clock is real: the reader or a ticket set it, a
    /// timetable supplied it, or the saved journey had it. Anything else is
    /// the editor's placeholder and is never written, compared or labelled.
    func scheduledIsSet(isDeparture: Bool) -> Bool {
        let side: Field = isDeparture ? .departure : .arrival
        return !clearedClocks.contains(side)
            && (timeIsSet(side) || timetableSupplies(isDeparture: isDeparture)
                || (isDeparture ? seed.departureKnown : seed.arrivalKnown))
    }

    /// The applied timetable has a readable clock at the ride's boarding
    /// (departure) or alighting (arrival) stop.
    private func timetableSupplies(isDeparture: Bool) -> Bool {
        guard let timetableTrain, !timetableTrain.stops.isEmpty else { return false }
        let span = timetableRideSpan ?? 0...(timetableTrain.stops.count - 1)
        let index = isDeparture ? span.lowerBound : span.upperBound
        guard timetableTrain.stops.indices.contains(index),
              let time = isDeparture ? timetableTrain.stops[index].departure : timetableTrain.stops[index].arrival
        else { return false }
        return timetableDate(timetableTrain.date ?? dayString(departure), time: time) != nil
    }

    /// Both scheduled clocks are real and arrival is before departure.
    var scheduledTimesConflict: Bool {
        scheduledIsSet(isDeparture: true) && scheduledIsSet(isDeparture: false) && arrival < departure
    }

    /// Both actual clocks are readable and the actual arrival is before the
    /// actual departure, in service minutes.
    var actualTimesConflict: Bool {
        guard case .valid(_, let left) = EditorTime.parseTime(normalizedActual(actualDeparture, isDeparture: true)),
              case .valid(_, let arrived) = EditorTime.parseTime(normalizedActual(actualArrival, isDeparture: false))
        else { return false }
        return arrived.serviceMinutes < left.serviceMinutes
    }

    /// The time part of saving: only the date is required, and a clock the
    /// reader never set cannot make the order wrong.
    var timesAllowSave: Bool { !scheduledTimesConflict && !actualTimesConflict }

    /// Writes only the scheduled clocks that are real onto a new trip's
    /// boarding and alighting stops; an untouched one leaves the stop clockless.
    /// `includingKnown` (the timetable query) also takes a saved journey's clocks.
    func writeHeaderClocks(
        into train: inout Train, departureIndex: Int, arrivalIndex: Int, includingKnown: Bool = false
    ) {
        if includingKnown ? scheduledIsSet(isDeparture: true) : timeIsSet(.departure) {
            train.stops[departureIndex].departure = clock(departure, extraDays: 0)
        }
        if includingKnown ? scheduledIsSet(isDeparture: false) : timeIsSet(.arrival) {
            train.stops[arrivalIndex].arrival = clock(arrival, extraDays: extraDays(from: departure, to: arrival))
        }
    }

    /// What Ridden defaults to: a trip that would be filed under past now is
    /// ridden, one filed upcoming is not (``TripListRules``). An unset time
    /// is read as its date only.
    func prefillRidden(forDate date: String?, startClock: String?, timeIsSet: Bool) -> Bool {
        TripListRules.initialMembership(
            date: date, startClock: timeIsSet ? startClock : nil,
            clock: Region.resolved(timetableBase).clock, now: Date()) == .past
    }

    // MARK: - direction

    /// What decides the legs: the route on screen, not every render's draft.
    struct DirectionKey: Equatable {
        var stops: [String?]
        var sections: [RouteSection]
        var loaded: Bool
    }

    /// The route the direction is read from: the saved route, the chosen
    /// corridor, or the applied timetable. Built only when its key changes.
    func directionSource(original train: Train) -> Train? {
        if let timetableTrain { return timetableResult(timetableTrain, original: train) }
        if routeEdited { return selectedCorridor.flatMap(corridorDraft(for:)) ?? historicalDraft() }
        return draft
    }

    var directionKey: DirectionKey {
        // Cheap inputs only; the source train itself is built in the task.
        DirectionKey(
            stops: (timetableTrain?.stops ?? (routeEdited ? [] : draft.stops)).map(\.n02StationCode)
                + [selectedCorridorID, routeEdited ? "edited" : nil],
            sections: timetableTrain?.routeSections ?? (routeEdited ? [] : draft.routeSections ?? []),
            loaded: package != nil)
    }

    func loadDirections(original train: Train) async {
        guard let package, let source = directionSource(original: train), source.stops.count >= 2 else {
            directionLegs = []
            return
        }
        let legs = await Task.detached(priority: .utility) {
            (try? TravelDirection.legs(train: source, package: package)) ?? []
        }.value
        guard !Task.isCancelled else { return }
        directionLegs = legs
    }

    /// The reader's 方面, from the record's direction field. A stored
    /// up/down word is a direction, not a 方面, and is not shown here.
    var boundFor: String? {
        let value = draft.direction?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty || ["up", "down", "unknown"].contains(value) ? nil : value
    }

    func lineName(for id: String) -> String? {
        lineLabelByID[id] ?? package?.lines.first(where: { $0.id == id })?.name
    }

    func historicalNotice(for section: PlannedSection) -> JourneyEditorView.HistoricalNotice? {
        JourneyEditorView.historicalNotice(for: section, choice: choice(for: section))
    }

    var routeErrorCoveredByNotice: Bool {
        plannedIdentity == routeIdentity
            && JourneyEditorView.routeErrorCoveredByNotice(sections) { choice(for: $0) }
    }

    /// Single-section trip on a closed line: the planner has no corridor, but
    /// the dated network joins the two stations.
    var historicalSaveAllowed: Bool {
        !hasRecordRoute && plannedIdentity == routeIdentity
            && sections.count == 1 && vias.isEmpty && sections[0].candidates.isEmpty
            && sections[0].historicalProbe == .historicalOnly
    }

    /// Two endpoint stops, no route sections, pending confirmation.
    func historicalDraft() -> Train? {
        guard historicalSaveAllowed, let origin, let destination else { return nil }
        var result = draft
        result.region = region.code
        result.stops = [
            endpointStop(origin, stationID: originStationID, stopType: "origin", ridden: isRidden),
            endpointStop(destination, stationID: destinationStationID, stopType: "destination", ridden: isRidden),
        ]
        result.routeSections = nil
        result.routeConfirmation = .pending
        result.date = dayString(departure)
        writeHeaderClocks(into: &result, departureIndex: 0, arrivalIndex: 1)
        result.trainType = trainType
        let typedNumber = trainNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        result.number = typedNumber.isEmpty
            ? (originLine?.name ?? "\(origin.name) → \(destination.name)") : typedNumber
        commitCompany(companyName, on: &result)
        result.origin = origin.name
        result.destination = destination.name
        return result
    }

    /// Consecutive picked stops whose regions' rail networks do not connect,
    /// one per section. A stop without a registry identity is in the
    /// editor's region.
    var regionConflicts: [(index: Int, from: String, to: String)] {
        let ids = [originStationID] + vias.map(\.stationID) + [destinationStationID]
        let regions = ids.map { RegionConnectivity.region(ofStationID: $0) ?? region.code }
        return regions.indices.dropLast().compactMap { i in
            RegionConnectivity.areConnected(regions[i], regions[i + 1])
                ? nil : (i, regions[i], regions[i + 1])
        }
    }

    var canSave: Bool {
        guard draft.journeyGroup?.name.isEmpty != true, !repair.isRunning, regionConflicts.isEmpty else { return false }
        if let timetableTrain { return timetableTrain.stops.count >= 2 && timesAllowSave }
        if !routeEdited { return hasRecordRoute && timesAllowSave }
        return origin != nil && destination != nil && timesAllowSave
            && plannedIdentity == routeIdentity
            && (selectedCorridor != nil || historicalSaveAllowed) && !searching
    }

    /// Stations, lines and vias: the inputs that pick a physical route.
    var stationIdentity: String {
        [
            region.code,
            origin?.key.sourceCode ?? "",
            destination?.key.sourceCode ?? "",
            originLine?.id ?? "",
            destinationLine?.id ?? "",
            vias.map(\.station.key.sourceCode).joined(separator: ","),
        ].joined(separator: "\u{1f}")
    }

    /// The reader asked for a route other than the saved one. Always true
    /// for a new trip, which has no saved route.
    var routeEdited: Bool {
        !hasRecordRoute || seededStationIdentity.map { $0 != stationIdentity } == true
    }

    /// Whether the editor still shows the saved stops as the route.
    var showsRecordRoute: Bool {
        !routeEdited && timetableTrain == nil
    }

    var selectedCorridor: TripRoutePlanner.Corridor? {
        guard plannedIdentity == routeIdentity,
              let selectedCorridorID,
              let outcome,
              case .corridors(let corridors) = outcome else { return nil }
        return corridors.first { $0.id == selectedCorridorID }
    }

    var routeIdentity: String {
        [
            region.code,
            origin?.key.sourceCode ?? "",
            destination?.key.sourceCode ?? "",
            originLine?.id ?? "",
            destinationLine?.id ?? "",
            vias.map(\.station.key.sourceCode).joined(separator: ","),
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
    func refreshCompanyCache() {
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
    static func packageOperatorNames(_ package: CompactPackage) -> [String: String] {
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

    /// Finds the saved journey's end stations in the catalog. The saved
    /// stops stay the route until the reader picks another station or via.
    func seedStations(from catalog: EditorCatalog) {
        func station(_ stop: Stop?) -> CatalogStation? {
            guard let code = stop?.n02StationCode else { return nil }
            return catalog.station(StationKey(regionCode: region.code, sourceCode: code))
        }
        if draft.stops.count >= 2 {
            origin = station(draft.stops.first)
            originStationID = draft.stops.first?.stationID
            destination = station(draft.stops.last)
            destinationStationID = draft.stops.last?.stationID
        }
        seededStationIdentity = stationIdentity
    }

    func swapStations() {
        clearTimetable()
        markStationTouched(.origin)
        markStationTouched(.destination)
        let previous = origin
        let previousLine = originLine
        origin = destination
        originLine = destinationLine
        destination = previous
        destinationLine = previousLine
        let previousID = originStationID
        originStationID = destinationStationID
        destinationStationID = previousID
        vias.reverse()
    }

    func endpointStop(
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

    func commitCompany(_ text: String, on train: inout Train) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            RegistryIdentityUpgrade.reassignCompany(nil, on: &train)
        } else if !RegistryOperatorCommit.apply(text: trimmed, region: region.code, to: &train) {
            RegistryIdentityUpgrade.reassignCompany(trimmed, on: &train)
        }
    }

    func loadRegion() async {
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
            geometryCache = TripRouteGeometry.Cache(package: loaded.1)
            mapStations = loaded.0.stations(in: region.code)
            if hasRecordRoute, seededStationIdentity == nil { seedStations(from: loaded.0) }
            lineColorByID = Dictionary(
                loaded.1.lines.compactMap { line in line.color.map { (line.id, $0) } },
                uniquingKeysWith: { first, _ in first })
            refreshCompanyCache()
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, region == self.region, generation == draftGeneration else { return }
            catalog = nil
            package = nil
            geometryCache = nil
            loadFailed = true
        }
    }

    /// Builds and validates the record Save writes, and hands it to `onSave`.
    /// A route change that drops recorded stops asks first (`removal`).
    func commit(
        confirmedRemoval: Bool, original train: Train, existingIDs: Set<String>, onSave: (Train) -> Void
    ) {
        guard canSave else { return }
        var result: Train
        if let timetableTrain {
            result = timetableResult(timetableTrain, original: train)
            applyPendingPlatforms(to: &result, span: timetableRideSpan)
        } else if routeEdited {
            if selectedCorridor == nil, let drafted = historicalDraft() {
                result = drafted
            } else {
                guard let corridor = selectedCorridor, let drafted = corridorDraft(for: corridor) else {
                    autofillFailed = true
                    return
                }
                let dropped = corridorConflicts(corridor)
                if !confirmedRemoval, !dropped.isEmpty {
                    removal = RemovalRequest(action: .save, stations: dropped.map(\.name))
                    return
                }
                result = drafted
            }
            applyPendingPlatforms(to: &result)
        } else {
            result = draft
            // An untouched legacy record keeps having no region field.
            if train.region != nil || region != Region.resolved(train) { result.region = region.code }
            applyHeader(to: &result)
        }
        applyActualTimes(to: &result)
        // Notes are edited from the trip card, never here: whatever path built
        // the result (timetable, corridor, record), the trip keeps its notes.
        result.tripNotes = train.tripNotes
        fileByDateIfUntimed(&result)
        Self.trimDetails(&result)
        let blocking = RideDraftValidation.issues(
            for: result, originalID: train.id, existingIDs: existingIDs).blocking
        guard blocking.isEmpty else {
            saveIssues = blocking
            return
        }
        saveIssues = []
        onSave(result)
    }

    /// A new trip whose time nobody set is filed by its date alone: its
    /// clocks are a placeholder, so it is upcoming while its date is today or
    /// later and overdue only once that date has ended. A time the reader, a
    /// timetable or a completion set leaves filing to the store's exact-time
    /// rule. Editing a date-only trip's time makes it a timed one.
    func fileByDateIfUntimed(_ result: inout Train) {
        if isNewTrip, !headerTimeIsSet {
            result.listByDate = true
            result.listMembership = TripListRules.initialMembership(
                for: result, clock: Region.resolved(result).clock, now: Date())
        } else if timetableTrain != nil || timeIsSet(.departure) || timeIsSet(.arrival) {
            result.listByDate = nil
        }
    }

    /// Header fields of a saved journey are written back only when the
    /// reader changed them. A placeholder clock (none was saved and the
    /// reader did not set one) is never written.
    func applyHeader(to result: inout Train) {
        let last = result.stops.count - 1
        let serviceDate = headerServiceDate()
        if dayIsSet { result.date = serviceDate }
        if last >= 1 {
            if clearedClocks.contains(.departure) {
                result.stops[0].departure = nil
            } else if dayIsSet, timeIsSet(.departure) || seed.departureKnown {
                result.stops[0].departure = untouchedClockText(
                    seed.departureText, seed: seed.departure, now: departure, isSet: timeIsSet(.departure))
                    ?? clock(departure, extraDays: extraDays(from: serviceDate, to: departure))
            }
            if clearedClocks.contains(.arrival) {
                result.stops[last].arrival = nil
            } else if timeIsSet(.arrival) || seed.arrivalKnown && touched.contains(.arrivalDate) {
                result.stops[last].arrival = untouchedClockText(
                    seed.arrivalText, seed: seed.arrival, now: arrival, isSet: timeIsSet(.arrival))
                    ?? clock(arrival, extraDays: extraDays(from: serviceDate, to: arrival))
            }
        }
        let number = trainNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        if number != seed.number.trimmingCharacters(in: .whitespacesAndNewlines), !number.isEmpty {
            result.number = number
        }
        if trainType != seed.trainType { result.trainType = trainType.isEmpty ? nil : trainType }
        if companyName != seed.company { commitCompany(companyName, on: &result) }
        if let riddenOverride { result = RideLedger.setRidden(result, riddenOverride) }
    }

    /// The saved clock text, verbatim, when the reader never set this clock and
    /// the instant moved only by the same whole days as the service date, so a
    /// date-only edit does not rewrite "10:30:15" or "10:00+1".
    private func untouchedClockText(_ text: String?, seed: Date, now: Date, isSet: Bool) -> String? {
        guard !isSet, let text else { return nil }
        let calendar = region.clock.calendar
        let moved = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: self.seed.departure),
            to: calendar.startOfDay(for: departure)).day ?? 0
        return calendar.date(byAdding: .day, value: moved, to: seed) == now ? text : nil
    }

    /// The saved service day, moved by as many days as the reader moved the
    /// departure. A first departure after midnight ("24:30") stays on the
    /// day the service started, not on the calendar day it left.
    func headerServiceDate() -> String {
        let saved = Dates.normalizeDateString(draft.date)
        guard dayIsSet else { return saved ?? dayString(departure) }
        let calendar = region.clock.calendar
        let moved = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: seed.departure),
            to: calendar.startOfDay(for: departure)).day ?? 0
        return saved.flatMap { Dates.addDays($0, moved) } ?? dayString(departure)
    }

    /// Recorded stops of a saved journey that this corridor does not pass.
    func corridorConflicts(_ corridor: TripRoutePlanner.Corridor) -> [Stop] {
        guard hasRecordRoute, draft.stops.count >= 2 else { return [] }
        return LocalJourneyAutofill.proposal(train: draft, choice: corridor.choice)?.conflictingStops ?? []
    }

    /// Build exactly the candidate that saving this corridor would persist.
    /// A saved journey keeps its visits that the new route still passes,
    /// with their clocks; only the route between them is replaced.
    func corridorDraft(for corridor: TripRoutePlanner.Corridor) -> Train? {
        guard let origin, let destination else { return nil }
        var result = draft
        result.region = region.code
        if !hasRecordRoute || result.stops.count < 2 {
            // Same mapping StationPickerView uses: CatalogStation.key.sourceCode.
            result.stops = [
                endpointStop(origin, stationID: originStationID, stopType: "origin", ridden: isRidden),
                endpointStop(destination, stationID: destinationStationID, stopType: "destination", ridden: isRidden),
            ]
        }
        // Physical confirmation comes from the resolver result for this exact planning input.
        guard let proposal = LocalJourneyAutofill.proposal(train: result, choice: corridor.choice),
              proposal.train.stops.count >= 2 else { return nil }
        result = proposal.train
        result.routeConfirmation = plannedIdentity == routeIdentity
            && physicallyResolvedCorridorIDs.contains(corridor.id) ? .confirmed : .pending
        result.region = region.code
        let last = result.stops.count - 1
        for (index, station, stationID) in [(0, origin, originStationID), (last, destination, destinationStationID)]
        where result.stops[index].n02StationCode == station.key.sourceCode && stationID != nil
            && result.stops[index].stationID != stationID {
            RegistryStationSelection.fill(
                &result.stops[index], regionCode: region.code, sourceCode: station.key.sourceCode,
                catalogName: station.name, stationID: stationID)
        }
        if !hasRecordRoute {
            result.date = dayString(departure)
            writeHeaderClocks(into: &result, departureIndex: 0, arrivalIndex: last)
            result.trainType = trainType
            let typedNumber = trainNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            result.number = typedNumber.isEmpty
                ? (corridor.lineNames.first ?? originLine?.name ?? "")
                : typedNumber
        } else {
            applyHeader(to: &result)
            if result.number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.number = corridor.lineNames.first ?? originLine?.name ?? ""
            }
        }
        if companyName.isEmpty, !hasRecordRoute || seed.company.isEmpty {
            let joined = corridor.operatorNames.filter { !$0.isEmpty }.joined(separator: "・")
            commitCompany(joined, on: &result)
        } else if !hasRecordRoute {
            commitCompany(companyName, on: &result)
        }
        result.origin = origin.name
        result.destination = destination.name
        return result
    }

    func dayString(_ date: Date) -> String {
        RecordDate.text(from: date, in: region.clock)
    }

    /// Hours run past 24 when arrival falls on a later calendar day (`25:10`).
    func clock(_ date: Date, extraDays: Int) -> String {
        let calendar = region.clock.calendar
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        // Padded up to hour 99, as ordinary records store it. Beyond that the
        // storage grammar's `H:MM+N` form, which every reader can parse.
        if extraDays * 24 + hour > 99 {
            return EditorTime.canonical(ServiceClockTime(dayOffset: extraDays, hour: hour, minute: minute))
        }
        return String(format: "%02d:%02d", extraDays * 24 + hour, minute)
    }

    func extraDays(from departure: Date, to arrival: Date) -> Int {
        let calendar = region.clock.calendar
        let start = calendar.startOfDay(for: departure)
        let end = calendar.startOfDay(for: arrival)
        return max(0, calendar.dateComponents([.day], from: start, to: end).day ?? 0)
    }

    func extraDays(from serviceDate: String, to date: Date) -> Int {
        guard let serviceDay = timetableDate(serviceDate, time: "00:00") else { return 0 }
        return extraDays(from: serviceDay, to: date)
    }

    func kilometerString(_ kilometers: Double) -> String? {
        guard kilometers > 0 else { return nil }
        let rounded = (kilometers * 10).rounded() / 10
        guard rounded > 0 else { return nil }
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(format: "%.1f", rounded)
    }
}
