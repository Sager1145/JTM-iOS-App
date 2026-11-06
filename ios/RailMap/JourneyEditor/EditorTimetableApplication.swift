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
            query.stops[0].departure = clock(departure, extraDays: 0)
            query.stops[1].arrival = clock(arrival, extraDays: extraDays(from: departure, to: arrival))
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
    func removeTimetable() {
        if let header = headerBeforeTimetable {
            trainType = header.trainType
            departure = header.departure
            arrival = header.arrival
            previousDeparture = header.previousDeparture
            touched = header.touched
        }
        clearTimetable()
    }

    func clearTimetable() {
        headerBeforeTimetable = nil
        timetableTrain = nil
        timetableRideSpan = nil
        timetableTrainTypeChanged = false
        timetableFailed = false
        saveIssues = []
    }

    func applyTimetableTrip(_ trip: TrainTimetableDatabase.Trip) {
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

    func applyPattern(_ pattern: TrainServicePatterns.Pattern, reversed: Bool) {
        _ = acceptTimetable(TrainServicePatterns.apply(
            pattern, to: timetableBase, reversed: reversed, ridden: isRidden))
    }

    @discardableResult
    func acceptTimetable(_ applied: Train) -> Bool {
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
                touched: touched)
        }
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
        // The timetable's clocks are not the reader's: nothing becomes touched.
        apply(Patch(departure: appliedDeparture, arrival: appliedArrival), source: .timetable)
        if let appliedDeparture, appliedArrival != nil {
            previousDeparture = appliedDeparture
        }
        return true
    }

    func timetableDate(_ day: String, time: String) -> Date? {
        EditorSeed.date(day: day, time: time)
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
        if timetableTrainTypeChanged { result.trainType = trainType }
        let span = timetableRideSpan ?? 0...(result.stops.count - 1)
        for index in result.stops.indices {
            result.stops[index].rideSegment = span.contains(index) && isRidden
        }
        let pickerDeparture = clock(
            departure, extraDays: extraDays(from: serviceDate, to: departure))
        if result.stops[span.lowerBound].departure != pickerDeparture {
            result.stops[span.lowerBound].departure = pickerDeparture
        }
        let pickerArrival = clock(
            arrival, extraDays: extraDays(from: serviceDate, to: arrival))
        if result.stops[span.upperBound].arrival != pickerArrival {
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
        if source.direction != train.direction { result.direction = source.direction }
    }
}
