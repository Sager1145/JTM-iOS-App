import Foundation

/// Add-trip autofill: turns the signals available when a ride is being added
/// (clock, nearby stations, a ticket reading, a timetable match, ride history)
/// into ranked field proposals. Pure and deterministic; the editor decides how
/// to show them and never receives a proposal for a field the user touched.
public enum TripInference {

    public enum Field: String, Hashable, Sendable, CaseIterable {
        case date, origin, destination
        case serviceName, serviceNumber, trainType, company, operatorID, direction
        case departureTime, arrivalTime, originPlatform, destinationPlatform
        case vehicleType, setNumber, carCount, car, livery
        case seat, seatClass, fare, currency, ticketKind
    }

    public enum Source: Int, Hashable, Sendable {
        // Declaration order is the tie-break priority at equal confidence.
        case ticket, timetable, nearby, history, now
    }

    public enum Confidence: Int, Hashable, Sendable, Comparable {
        case low, medium, high
        public static func < (lhs: Confidence, rhs: Confidence) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public struct Proposal: Hashable, Sendable {
        public let field: Field
        public let value: String
        public let source: Source
        public let confidence: Confidence
        /// Set for station proposals (`origin`/`destination`) when known.
        public let stationCode: String?

        public init(
            field: Field, value: String, source: Source, confidence: Confidence,
            stationCode: String? = nil
        ) {
            self.field = field
            self.value = value
            self.source = source
            self.confidence = confidence
            self.stationCode = stationCode
        }
    }

    public struct NearbyStation: Sendable, Equatable {
        public let name: String
        public let code: String?
        public let distanceMeters: Double

        public init(name: String, code: String? = nil, distanceMeters: Double) {
            self.name = name
            self.code = code
            self.distanceMeters = distanceMeters
        }

        public init(_ result: NearbyStations.Result) {
            self.init(name: result.place.name, code: result.place.code,
                      distanceMeters: result.distanceMeters)
        }
    }

    /// A service resolved from the timetable by name/number and date.
    public struct TimetableMatch: Sendable, Equatable {
        public var serviceName: String?
        public var serviceNumber: String?
        public var trainType: String?
        public var company: String?
        public var operatorID: String?
        public var direction: String?
        public var origin: String?
        public var destination: String?
        public var departureTime: String?
        public var arrivalTime: String?
        public var originPlatform: String?
        public var destinationPlatform: String?
        public var vehicleType: String?
        public var setNumber: String?
        public var carCount: Int?
        /// An exact trip on the exact service day is high confidence; a
        /// same-name service without that proof is medium.
        public var isExact: Bool

        public init(
            serviceName: String? = nil, serviceNumber: String? = nil, trainType: String? = nil,
            company: String? = nil, operatorID: String? = nil, direction: String? = nil,
            origin: String? = nil, destination: String? = nil,
            departureTime: String? = nil, arrivalTime: String? = nil,
            originPlatform: String? = nil, destinationPlatform: String? = nil,
            vehicleType: String? = nil, setNumber: String? = nil, carCount: Int? = nil,
            isExact: Bool = true
        ) {
            self.serviceName = serviceName
            self.serviceNumber = serviceNumber
            self.trainType = trainType
            self.company = company
            self.operatorID = operatorID
            self.direction = direction
            self.origin = origin
            self.destination = destination
            self.departureTime = departureTime
            self.arrivalTime = arrivalTime
            self.originPlatform = originPlatform
            self.destinationPlatform = destinationPlatform
            self.vehicleType = vehicleType
            self.setNumber = setNumber
            self.carCount = carCount
            self.isExact = isExact
        }
    }

    public struct Signals: Sendable {
        public var now: Date
        /// The date currently in the draft, if any (`YYYY-MM-DD`).
        public var date: String?
        public var region: String?
        public var nearby: [NearbyStation]
        public var ticket: TicketReading?
        public var timetable: TimetableMatch?
        public var history: [RideHistorySuggestions.Suggestion]
        /// Fields the user has edited; they never receive a proposal.
        public var touched: Set<Field>

        public init(
            now: Date, date: String? = nil, region: String? = nil,
            nearby: [NearbyStation] = [], ticket: TicketReading? = nil,
            timetable: TimetableMatch? = nil,
            history: [RideHistorySuggestions.Suggestion] = [],
            touched: Set<Field> = []
        ) {
            self.now = now
            self.date = date
            self.region = region
            self.nearby = nearby
            self.ticket = ticket
            self.timetable = timetable
            self.history = history
            self.touched = touched
        }
    }

    /// Stations nearer than this are a confident origin.
    public static let highConfidenceMeters = 300.0
    /// Stations up to this far are offered as lower-confidence chips.
    public static let chipMeters = 1500.0

    /// Proposals sorted by confidence (high first), then source priority
    /// (ticket, timetable, nearby, history, now), then input order. Several
    /// proposals for one field are alternatives; a consumer fills the field
    /// from the first and shows the rest as chips.
    public static func propose(signals: Signals) -> [Proposal] {
        var out: [Proposal] = []
        func add(
            _ field: Field, _ value: String?, _ source: Source, _ confidence: Confidence,
            code: String? = nil
        ) {
            guard !signals.touched.contains(field), let value else { return }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            out.append(Proposal(field: field, value: trimmed, source: source,
                                confidence: confidence, stationCode: code))
        }

        // Clock.
        if signals.date == nil {
            add(.date, Statistics.statisticsReferenceDate(
                country: signals.region ?? "jp", now: signals.now), .now, .high)
        }

        // Nearby stations: origin only.
        let near = signals.nearby.filter { $0.distanceMeters.isFinite && $0.distanceMeters <= chipMeters }
            .sorted { $0.distanceMeters < $1.distanceMeters }
        for (index, station) in near.enumerated() {
            let confidence: Confidence =
                index == 0 && station.distanceMeters < highConfidenceMeters ? .high : .medium
            add(.origin, station.name, .nearby, confidence, code: station.code)
        }

        // Ticket reading.
        if let ticket = signals.ticket {
            func level(_ field: Field) -> Confidence { ticket.confidence[field] ?? .medium }
            add(.origin, ticket.origin, .ticket, level(.origin))
            add(.destination, ticket.destination, .ticket, level(.destination))
            add(.date, ticket.date, .ticket, level(.date))
            add(.serviceName, ticket.serviceName, .ticket, level(.serviceName))
            add(.serviceNumber, ticket.serviceNumber, .ticket, level(.serviceNumber))
            add(.car, ticket.car, .ticket, level(.car))
            add(.seat, Ticket.normalizedSeat(ticket.seat), .ticket, level(.seat))
            add(.seatClass, ticket.seatClass, .ticket, level(.seatClass))
            add(.fare, ticket.fare.map(String.init), .ticket, level(.fare))
            add(.currency, ticket.currency?.uppercased() ?? ticket.fare.flatMap { _ in
                let set = Ticket.currencies(forRegion: signals.region)
                return set.count == 1 ? set.first : nil
            }, .ticket, ticket.currency == nil ? .medium : level(.currency))
            add(.ticketKind, ticket.kind, .ticket, level(.ticketKind))
        }

        // Timetable match.
        if let match = signals.timetable {
            let level: Confidence = match.isExact ? .high : .medium
            add(.serviceName, match.serviceName, .timetable, level)
            add(.serviceNumber, match.serviceNumber, .timetable, level)
            add(.trainType, match.trainType, .timetable, level)
            add(.company, match.company, .timetable, level)
            add(.operatorID, match.operatorID, .timetable, level)
            add(.direction, match.direction, .timetable, level)
            add(.origin, match.origin, .timetable, level)
            add(.destination, match.destination, .timetable, level)
            add(.departureTime, match.departureTime, .timetable, level)
            add(.arrivalTime, match.arrivalTime, .timetable, level)
            add(.originPlatform, match.originPlatform, .timetable, level)
            add(.destinationPlatform, match.destinationPlatform, .timetable, level)
            add(.vehicleType, match.vehicleType, .timetable, level)
            add(.setNumber, match.setNumber, .timetable, level)
            add(.carCount, match.carCount.map(String.init), .timetable, level)
        }

        // History.
        for suggestion in signals.history {
            add(suggestion.field, suggestion.value, .history, .medium)
        }

        return out.enumerated().sorted { lhs, rhs in
            let (a, b) = (lhs.element, rhs.element)
            if a.confidence != b.confidence { return a.confidence > b.confidence }
            if a.source != b.source { return a.source.rawValue < b.source.rawValue }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }
}

/// What a ticket scan produced. Plain values: the OCR parser returns one and
/// this layer never looks at images or text. Per-field confidence defaults to
/// `.medium` when a field is absent from `confidence`.
public struct TicketReading: Sendable, Equatable {
    public var origin: String?
    public var destination: String?
    /// `YYYY-MM-DD`.
    public var date: String?
    public var serviceName: String?
    public var serviceNumber: String?
    public var car: String?
    /// As printed; normalised when proposed.
    public var seat: String?
    public var seatClass: String?
    /// Whole units of `currency`.
    public var fare: Int?
    /// `JPY`, `TWD`, `HKD`, `MOP`, `KRW` (or `CNY`).
    public var currency: String?
    public var kind: String?
    public var confidence: [TripInference.Field: TripInference.Confidence]

    public init(
        origin: String? = nil, destination: String? = nil, date: String? = nil,
        serviceName: String? = nil, serviceNumber: String? = nil, car: String? = nil,
        seat: String? = nil, seatClass: String? = nil, fare: Int? = nil,
        currency: String? = nil, kind: String? = nil,
        confidence: [TripInference.Field: TripInference.Confidence] = [:]
    ) {
        self.origin = origin
        self.destination = destination
        self.date = date
        self.serviceName = serviceName
        self.serviceNumber = serviceNumber
        self.car = car
        self.seat = seat
        self.seatClass = seatClass
        self.fare = fare
        self.currency = currency
        self.kind = kind
        self.confidence = confidence
    }
}
