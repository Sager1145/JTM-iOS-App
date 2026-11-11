import RailApplication
import RailCore
import RailPresentation
import SwiftUI

/// Applying a timetable, a service pattern or a completion to the draft,
/// and the record a timetable makes.
extension TripDraftModel {
    var serviceSuggestions: [String] {
        let names = TrainServiceBranding.services.filter { $0.region == region.code }.flatMap(\.names)
        return Array(Set(names)).sorted().filter {
            limitedExpressName.isEmpty || $0.localizedCaseInsensitiveContains(limitedExpressName)
        }
    }

    var timetableBase: Train {
        var base = draft
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
    var timetableQuery: Train {
        // Quick match only looks up once the endpoints carry departure and
        // arrival clocks, so the query uses the Time section's values.
        // `registryEpoch` is read so a settle rebuilds this derived train.
        _ = registryEpoch
        var query = timetableBase
        if query.stops.count == 2 {
            writeHeaderClocks(into: &query, departureIndex: 0, arrivalIndex: 1, includingKnown: true)
        }
        return JourneyCompletion.resolvingUniqueStationNames(
            in: query, catalogs: catalog.map { [region.code: $0] } ?? [:])
    }

    /// The Time section's clocks. Setting one is the reader's change.
    func timetableTimeSelection(isDeparture: Bool) -> Binding<Date> {
        Binding(
            get: { isDeparture ? self.departure : self.arrival },
            set: { value in
                self.apply(isDeparture ? Patch(departure: value) : Patch(arrival: value), source: .reader)
            })
    }

    /// Remove puts the header back as it was before the timetable filled it.
    /// Only the header's own fields go back; whatever the reader set
    /// elsewhere while the timetable was applied stays theirs.
    func removeTimetable() {
        restoreHeaderBeforeTimetable()
        if filledBy[.serviceName] == .timetable {
            limitedExpressName = ""
            filledBy[.serviceName] = nil
        }
        clearTimetable()
    }

    /// Puts the header's fields back as the snapshot kept them. When
    /// `keepingReaderEdits`, a field the reader set while the timetable was
    /// applied keeps its value.
    func restoreHeaderBeforeTimetable(keepingReaderEdits: Bool = false) {
        guard let header = headerBeforeTimetable else { return }
        let kept = keepingReaderEdits ? touched.subtracting(header.touched) : []
        if !kept.contains(.trainType) { trainType = header.trainType }
        if !kept.contains(.departure) {
            departure = header.departure
            previousDeparture = header.previousDeparture
        }
        if !kept.contains(.arrival) { arrival = header.arrival }
        let restored = Self.headerFields.subtracting(kept)
        touched = touched.subtracting(restored).union(header.touched.intersection(restored))
        for field in restored { filledBy[field] = header.filledBy[field] }
    }

    /// The fields a timetable's header snapshot restores.
    static let headerFields: Set<Field> = [.departure, .arrival, .date, .trainType]

    /// A timetable no longer applies: the formation it filled goes with it.
    func clearTimetable() {
        clearFormationFill()
        restoreHeaderBeforeTimetable(keepingReaderEdits: true)
        headerBeforeTimetable = nil
        appliedTimetableTripID = nil
        timetableTrain = nil
        timetableRideSpan = nil
        timetableTrainTypeChanged = false
        timetableFailed = false
        saveIssues = []
    }

    /// `automatic` is a timetable a ticket scan found rather than one the
    /// reader picked: it then writes no field the reader set.
    func applyTimetableTrip(_ trip: TrainTimetableDatabase.Trip, automatic: Bool = false) {
        guard var drafted = JourneyDraftWork.timetableDraft(
            from: trip, appliedTo: timetableBase, ridden: riddenOverride ?? true) else {
            timetableFailed = true
            return
        }
        // The timetable's own clocks decide the default, by the same rule
        // that files the trip: one still ahead is not ridden yet.
        var timed = drafted.train
        timed.listByDate = nil
        if riddenOverride == nil, TripListRules.initialMembership(
            for: timed, clock: Region.resolved(timetableBase).clock, now: Date()) == .upcoming,
           let unridden = JourneyDraftWork.timetableDraft(
               from: trip, appliedTo: timetableBase, ridden: false) {
            drafted = unridden
        }
        if acceptTimetable(drafted.train, automatic: automatic) {
            if !(automatic && touched.contains(.serviceName)) {
                limitedExpressName = drafted.serviceName
                if !drafted.serviceName.isEmpty { filledBy[.serviceName] = .timetable }
            }
            if let kept = timetableTrain {
                TimetableRouteEvidence.rememberAppliedOccurrence(trip: trip, train: kept)
            }
            appliedTimetableTripID = trip.id
            fillFormation(of: trip)
        }
    }

    func applyPattern(_ pattern: TrainServicePatterns.Pattern, reversed: Bool) {
        _ = acceptTimetable(TrainServicePatterns.apply(
            pattern, to: timetableBase, reversed: reversed, ridden: isRidden))
    }

    @discardableResult
    func acceptTimetable(_ applied: Train, automatic: Bool = false) -> Bool {
        // A formation still being read for an earlier trip must not land here.
        appliedTimetableTripID = nil
        clearFormationFill()
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
        if headerBeforeTimetable == nil {
            headerBeforeTimetable = HeaderSnapshot(
                trainType: trainType, departure: departure, arrival: arrival,
                previousDeparture: previousDeparture,
                touched: touched, filledBy: filledBy)
        }
        timetableTrain = applied
        timetableRideSpan = span
        timetableTrainTypeChanged = false
        timetableFailed = false
        saveIssues = []
        let type = applied.trainType ?? ""
        let publishedType: String? =
            type.contains("新幹線") ? "highSpeed"
            : type.contains("特急") ? "limitedExpress"
            : type.contains("急行") ? "express"
            : type.contains("快速") ? "rapid" : nil
        if let publishedType, !(automatic && touched.contains(.trainType)) {
            trainType = publishedType
            filledBy[.trainType] = .timetable
        }
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
        // The timetable's clocks are not the reader's: nothing becomes touched.
        // A timetable a ticket found leaves a clock the reader set alone.
        if automatic, touched.contains(.departure) { appliedDeparture = nil }
        if automatic, touched.contains(.arrival) { appliedArrival = nil }
        apply(Patch(departure: appliedDeparture, arrival: appliedArrival), source: .timetable)
        // A clock the ticket printed stays the ticket's: it is a real time
        // even if this timetable is later removed.
        if appliedDeparture != nil, filledBy[.departure] != .ticket { filledBy[.departure] = .timetable }
        if appliedArrival != nil, filledBy[.arrival] != .ticket { filledBy[.arrival] = .timetable }
        if let appliedDeparture, appliedArrival != nil {
            previousDeparture = appliedDeparture
        }
        return true
    }

    func timetableDate(_ day: String, time: String) -> Date? {
        region.clock.instant(serviceDate: day, clock: time)
    }

    func timetableTimes(_ timetable: Train) -> String {
        let span = timetableRideSpan ?? 0...(timetable.stops.count - 1)
        return [timetable.stops[span.lowerBound].departure, timetable.stops[span.upperBound].arrival]
            .compactMap { $0 }.joined(separator: " → ")
    }

    func timetableResult(_ timetable: Train, original train: Train) -> Train {
        var result = timetable
        carryDetails(from: draft, into: &result, original: train)
        result.region = region.code
        let serviceDate = result.date ?? dayString(departure)
        result.date = serviceDate
        if timetableTrainTypeChanged || touched.contains(.trainType) { result.trainType = trainType }
        let span = timetableRideSpan ?? 0...(result.stops.count - 1)
        for index in result.stops.indices {
            result.stops[index].rideSegment = span.contains(index) && isRidden
        }
        let pickerDeparture = clock(
            departure, extraDays: extraDays(from: serviceDate, to: departure))
        if timeIsSet(.departure), result.stops[span.lowerBound].departure != pickerDeparture {
            result.stops[span.lowerBound].departure = pickerDeparture
        }
        let pickerArrival = clock(
            arrival, extraDays: extraDays(from: serviceDate, to: arrival))
        if timeIsSet(.arrival), result.stops[span.upperBound].arrival != pickerArrival {
            result.stops[span.upperBound].arrival = pickerArrival
        }
        // The header shows a saved journey's own number and operator. Only a
        // value the reader changed outranks the timetable's.
        if !companyName.isEmpty, companyName != seed.company {
            commitCompany(companyName, on: &result)
        }
        let typed = trainNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let number = typed == seed.number.trimmingCharacters(in: .whitespacesAndNewlines) ? "" : typed
        result.number = [number, result.number, limitedExpressName,
                         result.routeSections?.first?.lineNames?.first ?? originLine?.name ?? ""]
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
        result.origin = result.stops[span.lowerBound].name
        result.destination = result.stops[span.upperBound].name
        return result
    }

    /// Fields only the details sections edit. A timetable replaces the route
    /// and the service, never these.
    func carryDetails(from source: Train, into result: inout Train, original train: Train) {
        result.id = source.id
        result.notes = source.notes
        result.journeyGroup = source.journeyGroup
        result.style = source.style
        result.visible = source.visible
        // The timetable sets these from the service. Keep the draft's only
        // when the reader typed them in this session.
        if source.numberEn != train.numberEn { result.numberEn = source.numberEn }
        if source.vehicleType != train.vehicleType { result.vehicleType = source.vehicleType }
        // Set, cars, livery and ticket are the reader's or filled into the
        // draft; the timetable's own record never carries them.
        result.rollingStock = source.rollingStock
        result.ticket = source.ticket
        if source.direction != train.direction { result.direction = source.direction }
    }
}
