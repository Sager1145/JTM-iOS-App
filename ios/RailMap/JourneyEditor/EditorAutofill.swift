import CoreLocation
import RailApplication
import RailCore
import RailPresentation
import SwiftUI

/// Every automatic source the editor has, in one place: a ticket scan, the
/// timetable's formation, ride history and the stations near the reader.
/// Each fill goes through `fill(_:source:_:)`, which never writes a field the
/// reader set and records where the value came from.
extension TripDraftModel {
    // MARK: - provenance

    /// Writes `apply` unless the reader set `field`. True when written.
    @discardableResult
    func fill(_ field: Field, source: FillSource, _ apply: () -> Void) -> Bool {
        guard !touched.contains(field) else { return false }
        apply()
        filledBy[field] = source
        return true
    }

    /// The reader set `field`: no fill writes it again.
    func markTouched(_ field: Field) {
        touched.insert(field)
        filledBy[field] = nil
    }

    func markStationTouched(_ field: StationField) {
        switch field {
        case .origin: markTouched(.origin)
        case .destination: markTouched(.destination)
        case .via: break
        }
    }

    /// A binding for a reader-edited value: setting it marks `field` touched.
    func readerBinding<Value: Equatable>(
        _ field: Field, get: @escaping () -> Value, set: @escaping (Value) -> Void
    ) -> Binding<Value> {
        Binding(get: get, set: { value in
            guard value != get() else { return }
            self.markTouched(field)
            set(value)
        })
    }

    // MARK: - draft detail bindings

    /// `nil` and empty text are the same: no value.
    func optionalText(_ field: Field, _ keyPath: WritableKeyPath<Train, String?>) -> Binding<String> {
        readerBinding(field, get: { self.draft[keyPath: keyPath] ?? "" }, set: { value in
            self.draft[keyPath: keyPath] = Self.stored(value)
        })
    }

    func stockText(_ field: Field, _ keyPath: WritableKeyPath<RollingStock, String?>) -> Binding<String> {
        readerBinding(field, get: { self.draft.rollingStock?[keyPath: keyPath] ?? "" }, set: { value in
            self.updateStock { $0[keyPath: keyPath] = Self.stored(value) }
        })
    }

    func stockNumber(_ field: Field, _ keyPath: WritableKeyPath<RollingStock, Int?>) -> Binding<String> {
        readerBinding(field, get: { self.draft.rollingStock?[keyPath: keyPath].map(String.init) ?? "" },
                      set: { value in
            // A set is at most a few dozen cars; zero is no value.
            let number = Int(value.filter(\.isASCIIDigit).prefix(2)).flatMap { $0 > 0 ? $0 : nil }
            self.updateStock { $0[keyPath: keyPath] = number }
        })
    }

    func ticketText(_ field: Field, _ keyPath: WritableKeyPath<Ticket, String?>) -> Binding<String> {
        readerBinding(field, get: { self.draft.ticket?[keyPath: keyPath] ?? "" }, set: { value in
            self.updateTicket { $0[keyPath: keyPath] = Self.stored(value) }
        })
    }

    /// Text while typing: blank is no value, anything else is kept as typed
    /// (a space between words must survive the keystroke). Save trims it
    /// (`trimDetails`).
    nonisolated static func stored(_ value: String) -> String? {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
    }

    /// The saved record's detail text without stray leading or trailing space.
    nonisolated static func trimDetails(_ result: inout Train) {
        func trim(_ text: String?) -> String? {
            let value = text?.trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == false ? value : nil
        }
        if var stock = result.rollingStock {
            stock.setNumber = trim(stock.setNumber)
            stock.livery = trim(stock.livery)
            result.rollingStock = stock.isEmpty ? nil : stock
        }
        if var ticket = result.ticket {
            ticket.seat = Ticket.normalizedSeat(ticket.seat)
            ticket.seatClass = trim(ticket.seatClass)
            ticket.kind = trim(ticket.kind)
            result.ticket = ticket.isEmpty ? nil : ticket
        }
    }

    /// The fare in whole units, with the region's currency when it has one.
    var fareText: Binding<String> {
        readerBinding(.fare, get: { self.draft.ticket?.fare.map(String.init) ?? "" }, set: { value in
            let fare = Int(value.filter(\.isASCIIDigit).prefix(9))
            self.updateTicket { ticket in
                ticket.fare = fare
                if fare == nil {
                    ticket.currency = nil
                } else if ticket.currency == nil {
                    ticket.currency = self.regionCurrency
                }
            }
        })
    }

    /// The one currency a region's tickets use, when it has only one.
    var regionCurrency: String? {
        let set = Ticket.currencies(forRegion: region.code)
        return set.count == 1 ? set.first : nil
    }

    func updateStock(_ change: (inout RollingStock) -> Void) {
        var stock = draft.rollingStock ?? RollingStock()
        change(&stock)
        draft.rollingStock = stock.isEmpty ? nil : stock
    }

    func updateTicket(_ change: (inout Ticket) -> Void) {
        var ticket = draft.ticket ?? Ticket()
        change(&ticket)
        draft.ticket = ticket.isEmpty ? nil : ticket
    }

    /// One car's number, for the car-numbers list. Cars are kept in order and
    /// only while they carry a number or series.
    func carNumber(_ sequence: Int) -> Binding<String> {
        readerBinding(.carNumbers, get: {
            self.draft.rollingStock?.cars?.first { $0.sequence == sequence }?.number ?? ""
        }, set: { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            self.updateStock { stock in
                var cars = stock.cars ?? []
                if let index = cars.firstIndex(where: { $0.sequence == sequence }) {
                    cars[index].number = trimmed.isEmpty ? nil : trimmed
                    if cars[index].number == nil, cars[index].series == nil { cars.remove(at: index) }
                } else if !trimmed.isEmpty {
                    cars.append(RollingStock.Car(sequence: sequence, number: trimmed))
                }
                cars.sort { $0.sequence < $1.sequence }
                stock.cars = cars.isEmpty ? nil : cars
            }
        })
    }

    /// Rows of the car-numbers list: the set's length, or the cars recorded.
    var carSequences: [Int] {
        let recorded = draft.rollingStock?.cars?.map(\.sequence) ?? []
        let count = min(max(draft.rollingStock?.carCount ?? 0, recorded.max() ?? 0), 99)
        return Array(1...max(count, 1))
    }

    // MARK: - ticket

    /// The scan's region for this editor's region; Hong Kong and Macau have
    /// no paper tickets.
    var ticketRegion: TicketRegion? { TicketRegion(rawValue: region.code) }

    /// One shot: every value the ticket gives goes into every field the
    /// reader has not set, then the timetable is searched for the train it
    /// names. Returns how many fields were written.
    @discardableResult
    func fillFromTicket(_ reading: TicketReadingResult, now: Date = Date()) -> Int {
        var written = 0
        func count(_ didWrite: Bool) { if didWrite { written += 1 } }

        if let name = reading.origin?.value, let station = ticketStation(name), station != origin {
            count(fill(.origin, source: .ticket) {
                clearTimetable()
                origin = station
                originLine = nil
                originStationID = nil
            })
        }
        if let name = reading.destination?.value, let station = ticketStation(name), station != destination {
            count(fill(.destination, source: .ticket) {
                clearTimetable()
                destination = station
                destinationLine = nil
                destinationStationID = nil
            })
        }

        // The reader's own day outranks the ticket's.
        let day = touched.contains(.date)
            ? nil : reading.date?.value.dayString(near: now, calendar: region.clock.calendar)
        // The service day, before this fill moves the departure.
        let serviceDay = day ?? dayString(departure)
        if let time = reading.departureTime?.value, !touched.contains(.departure),
           !clearedClocks.contains(.departure),
           let base = day ?? Optional(dayString(departure)),
           let date = timetableDate(Dates.addDays(base, time.dayOffset) ?? base,
                                    time: String(format: "%02d:%02d", time.hour, time.minute)) {
            // An arrival the reader set does not follow the departure.
            if touched.contains(.arrival) { previousDeparture = date }
            apply(Patch(departure: date), source: .ticket)
            filledBy[.departure] = .ticket
            filledBy[.date] = nil
            written += 1
        } else if let day, !touched.contains(.departure), day != dayString(departure),
                  let date = timetableDate(day, time: clock(departure, extraDays: 0)) {
            if touched.contains(.arrival) { previousDeparture = date }
            apply(Patch(departure: date), source: .ticket)
            filledBy[.date] = .ticket
            written += 1
        }

        // The printed arrival, on the service day; a clock before a set
        // departure's is the next morning. Writing it also pins the
        // departure the arrival follows, so the onChange shift adds nothing.
        if let time = reading.arrivalTime?.value, !touched.contains(.arrival),
           !clearedClocks.contains(.arrival),
           let value = ticketArrival(time, serviceDay: serviceDay) {
            previousDeparture = departure
            apply(Patch(arrival: value), source: .ticket)
            filledBy[.arrival] = .ticket
            written += 1
        }

        let serviceName = reading.serviceName?.value
        if region == .jp, let serviceName {
            count(fill(.serviceName, source: .ticket) { limitedExpressName = serviceName })
        }
        if let ticketRegion, let number = TicketServiceType.displayNumber(
            serviceName: serviceName, serviceNumber: reading.serviceNumber?.value, region: ticketRegion) {
            count(fill(.number, source: .ticket) { trainNumber = number })
        }
        if let ticketRegion, let type = TicketServiceType.trainType(
            serviceName: serviceName, region: ticketRegion, kind: reading.kind?.value) {
            count(fill(.trainType, source: .ticket) { trainType = type })
        }
        if let car = reading.car?.value, let value = Int(car.filter(\.isASCIIDigit)) {
            count(fill(.riddenCar, source: .ticket) { updateStock { $0.riddenCar = value } })
        }
        if let ticket = Ticket(reading: reading) {
            if let seat = ticket.seat { count(fill(.seat, source: .ticket) { updateTicket { $0.seat = seat } }) }
            if let seatClass = ticket.seatClass {
                count(fill(.seatClass, source: .ticket) { updateTicket { $0.seatClass = seatClass } })
            }
            if let fare = ticket.fare {
                count(fill(.fare, source: .ticket) {
                    updateTicket { $0.fare = fare; $0.currency = ticket.currency ?? regionCurrency }
                })
            }
            if let kind = ticket.kind {
                count(fill(.ticketKind, source: .ticket) { updateTicket { $0.kind = kind } })
            }
        }
        ticketFillCount = written
        // The day and clock on screen: the ticket's, unless the reader set them.
        matchTicketTimetable(reading, day: dayString(departure),
                             minutes: timeIsSet(.departure) ? clockMinutes(departure) : nil)
        return written
    }

    /// A printed arrival clock as a date after the departure on screen.
    /// Deliberately routed through the header helpers (`dayString`, `clock`,
    /// `timetableDate`) on day strings, never `Calendar`: it follows the
    /// header's zone until that is pinned to the region.
    func ticketArrival(_ time: ServiceClockTime, serviceDay: String) -> Date? {
        // Rolled one day only against a departure that is really set, both
        // measured from the service day.
        var later = 0
        if timeIsSet(.departure) {
            let left = clockMinutes(departure) + 1440 * extraDays(from: serviceDay, to: departure)
            later = time.serviceMinutes < left ? 1 : 0
        }
        guard let day = Dates.addDays(serviceDay, time.dayOffset + later) else { return nil }
        return timetableDate(day, time: String(format: "%02d:%02d", time.hour, time.minute))
    }

    /// The catalog station a printed name means: the name as printed, then
    /// without a bracketed area (東京(都区内)) or a trailing 駅/站/역.
    func ticketStation(_ printed: String) -> CatalogStation? {
        guard let catalog else { return nil }
        var names = [printed.trimmingCharacters(in: .whitespacesAndNewlines)]
        if let bracket = names[0].firstIndex(where: { "(（".contains($0) }) {
            names.append(String(names[0][..<bracket]).trimmingCharacters(in: .whitespaces))
        }
        for name in names where ["駅", "站", "역"].contains(where: name.hasSuffix) && name.count > 1 {
            names.append(String(name.dropLast()))
        }
        for name in names where !name.isEmpty {
            if let station = catalog.candidates(named: name, regionCode: region.code).first { return station }
        }
        return nil
    }

    /// A Japanese ticket that names a train: when exactly one published trip
    /// fits it, that timetable fills the rest (arrival, type, formation).
    func matchTicketTimetable(_ reading: TicketReadingResult, day: String, minutes: Int?) {
        ticketMatchTask?.cancel()
        guard region == .jp, reading.serviceName != nil || reading.serviceNumber != nil,
              let origin, let destination else { return }
        let query = TimetableTicketMatch.Query(
            date: day, serviceName: reading.serviceName?.value, serviceNumber: reading.serviceNumber?.value,
            originCode: origin.key.sourceCode, destinationCode: destination.key.sourceCode,
            departureMinutes: minutes)
        let identity = endpointIdentity
        ticketMatchTask = Task { [weak self] in
            let trips = await Task.detached(priority: .userInitiated) { () -> [TrainTimetableDatabase.Trip] in
                guard let database = try? TrainTimetableDatabase.bundled(country: "jp"),
                      let trips = try? database.trips(on: query.date) else { return [] }
                return TimetableTicketMatch.candidates(for: query, among: trips)
            }.value
            guard !Task.isCancelled, let self, self.endpointIdentity == identity,
                  self.dayString(self.departure) == day,
                  self.timetableTrain == nil, trips.count == 1 else { return }
            self.applyTimetableTrip(trips[0], automatic: true)
        }
    }

    // MARK: - timetable formation

    /// The published formation of the applied trip fills the vehicle and the
    /// set, where the reader has not.
    func fillFormation(of trip: TrainTimetableDatabase.Trip) {
        let tripID = trip.id
        Task { [weak self] in
            let stock = await Task.detached(priority: .utility) { () -> TrainTimetableDatabase.RollingStockDraft? in
                guard let database = try? TrainTimetableDatabase.bundled(country: "jp") else { return nil }
                return try? database.rollingStockDraft(for: trip)
            }.value
            guard let self, let stock, self.timetableTrain != nil,
                  self.appliedTimetableTripID == tripID else { return }
            if let series = stock.vehicleType, !series.isEmpty {
                self.fill(.vehicleType, source: .timetable) { self.draft.vehicleType = series }
            }
            guard let published = stock.rollingStock else { return }
            if let set = published.setNumber {
                self.fill(.setNumber, source: .timetable) { self.updateStock { $0.setNumber = set } }
            }
            if let count = published.carCount {
                self.fill(.carCount, source: .timetable) { self.updateStock { $0.carCount = count } }
            }
            if let cars = published.cars, !cars.isEmpty {
                self.fill(.carNumbers, source: .timetable) { self.updateStock { $0.cars = cars } }
            }
        }
    }

    /// Values the last timetable's formation wrote and the reader never
    /// changed. They describe that train only.
    func clearFormationFill() {
        if filledBy[.vehicleType] == .timetable { draft.vehicleType = nil }
        if filledBy[.setNumber] == .timetable { updateStock { $0.setNumber = nil } }
        if filledBy[.carCount] == .timetable { updateStock { $0.carCount = nil } }
        if filledBy[.carNumbers] == .timetable { updateStock { $0.cars = nil } }
        for field: Field in [.vehicleType, .setNumber, .carCount, .carNumbers] where filledBy[field] == .timetable {
            filledBy[field] = nil
        }
    }

    func clockMinutes(_ date: Date) -> Int {
        Int(Dates.parseTimeToMinutes(clock(date, extraDays: 0)) ?? 0)
    }

    // MARK: - history and nearby

    /// The reader's most frequent values on this route or line, offered as
    /// suggestions for empty fields; never filled without a tap.
    func historySuggestions(among trains: [Train]) -> [Field: String] {
        guard !trains.isEmpty else { return [:] }
        let suggestions = RideHistorySuggestions.suggestions(
            from: trains, origin: origin?.name, destination: destination?.name,
            line: originLine?.name)
        var result: [Field: String] = [:]
        for suggestion in suggestions {
            switch suggestion.field {
            case .trainType: result[.trainType] = suggestion.value
            case .company: result[.company] = suggestion.value
            case .vehicleType: result[.vehicleType] = suggestion.value
            case .livery: result[.livery] = suggestion.value
            case .setNumber: result[.setNumber] = suggestion.value
            default: break
            }
        }
        return result
    }

    /// Stations within `TripInference.chipMeters` of the device's last known
    /// position, nearest first. Reads a position only when location access was
    /// already granted; the editor never asks for it.
    func locateNearbyStations() {
        nearbyStations = []
        guard isNewTrip, origin == nil, !touched.contains(.origin), let catalog else { return }
        let manager = CLLocationManager()
        guard [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus),
              let location = manager.location,
              location.timestamp.timeIntervalSinceNow > -15 * 60 else { return }
        let here = Coordinate(lon: location.coordinate.longitude, lat: location.coordinate.latitude)
        let found = catalog.stations(in: region.code)
            .map { ($0, Geometry.distanceMeters(here, Coordinate(lon: $0.longitude, lat: $0.latitude))) }
            .filter { $0.1 <= TripInference.chipMeters }
            .sorted { $0.1 < $1.1 }
            .prefix(3)
        nearbyStations = found.map { NearbyStation(station: $0.0, meters: $0.1) }
        // A station this close is where the reader is boarding.
        if let first = nearbyStations.first, first.meters < TripInference.highConfidenceMeters {
            fill(.origin, source: .nearby) {
                origin = first.station
                originLine = nil
                originStationID = nil
            }
        }
    }
}

extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
