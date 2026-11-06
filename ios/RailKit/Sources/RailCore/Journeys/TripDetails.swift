import Foundation

/// Rolling stock ridden on one itinerary. Every field is optional and written
/// only when present, so a train without any of it round-trips unchanged.
/// `Train.vehicleType` remains the series field; this adds the set, the cars
/// and the livery.
public struct RollingStock: Codable, Equatable, Sendable {
    public struct Car: Codable, Equatable, Sendable {
        public var sequence: Int
        public var number: String?
        public var series: String?

        public init(sequence: Int, number: String? = nil, series: String? = nil) {
            self.sequence = sequence
            self.number = number
            self.series = series
        }

        private enum CodingKeys: String, CodingKey { case sequence, number, series }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(sequence, forKey: .sequence)
            try container.encodeIfPresent(number, forKey: .number)
            try container.encodeIfPresent(series, forKey: .series)
        }
    }

    public var setNumber: String?
    public var carCount: Int?
    public var cars: [Car]?
    public var riddenCar: Int?
    public var livery: String?

    public init(
        setNumber: String? = nil, carCount: Int? = nil, cars: [Car]? = nil,
        riddenCar: Int? = nil, livery: String? = nil
    ) {
        self.setNumber = setNumber
        self.carCount = carCount
        self.cars = cars
        self.riddenCar = riddenCar
        self.livery = livery
    }

    private enum CodingKeys: String, CodingKey {
        case setNumber = "set_number"
        case carCount = "car_count"
        case cars
        case riddenCar = "ridden_car"
        case livery
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(setNumber, forKey: .setNumber)
        try container.encodeIfPresent(carCount, forKey: .carCount)
        try container.encodeIfPresent(cars, forKey: .cars)
        try container.encodeIfPresent(riddenCar, forKey: .riddenCar)
        try container.encodeIfPresent(livery, forKey: .livery)
    }

    /// True when no field carries a value.
    public var isEmpty: Bool {
        setNumber == nil && carCount == nil && (cars?.isEmpty ?? true)
            && riddenCar == nil && livery == nil
    }
}

/// Ticket facts for one itinerary. `fare` is in the currency's minor units as
/// printed on the ticket (yen, NT dollars and won have no subunit in practice).
public struct Ticket: Codable, Equatable, Sendable {
    public var seat: String?
    public var seatClass: String?
    public var fare: Int?
    public var currency: String?
    public var kind: String?

    public init(
        seat: String? = nil, seatClass: String? = nil, fare: Int? = nil,
        currency: String? = nil, kind: String? = nil
    ) {
        self.seat = seat
        self.seatClass = seatClass
        self.fare = fare
        self.currency = currency
        self.kind = kind
    }

    private enum CodingKeys: String, CodingKey {
        case seat
        case seatClass = "seat_class"
        case fare, currency, kind
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(seat, forKey: .seat)
        try container.encodeIfPresent(seatClass, forKey: .seatClass)
        try container.encodeIfPresent(fare, forKey: .fare)
        try container.encodeIfPresent(currency, forKey: .currency)
        try container.encodeIfPresent(kind, forKey: .kind)
    }

    public var isEmpty: Bool {
        seat == nil && seatClass == nil && fare == nil && currency == nil && kind == nil
    }

    /// Currencies accepted for a region code (`jp`, `tw`, `hk`, `mo`, `kr`,
    /// `cn`). A missing or unknown region accepts the union.
    public static func currencies(forRegion region: String?) -> Set<String> {
        switch region?.lowercased() {
        case "jp": ["JPY"]
        case "tw": ["TWD"]
        case "hk": ["HKD"]
        case "mo": ["MOP", "HKD"]
        case "kr": ["KRW"]
        case "cn": ["CNY"]
        default: ["JPY", "TWD", "HKD", "MOP", "KRW", "CNY"]
        }
    }

    /// Seat spelling used in the store: ASCII, upper case, no spaces or
    /// 番/号 suffix ("５ Ａ" and "5a" both become "5A"). Nil when nothing remains.
    public static func normalizedSeat(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let folded = raw.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? raw
        let kept = folded.uppercased().filter {
            !$0.isWhitespace && $0 != "番" && $0 != "号" && $0 != "號"
        }
        return kept.isEmpty ? nil : String(kept)
    }
}

extension TrainValidation {
    /// Lenient JSON reading, mirroring `optionalText`: wrong-typed members are
    /// dropped so that validation can report on the canonical value.
    static func rollingStock(_ value: JSON?) -> RollingStock? {
        guard let value, case .object = value else { return nil }
        var cars: [RollingStock.Car]?
        if case .array(let items)? = value["cars"] {
            cars = items.compactMap { item in
                guard case .object = item, let sequence = item["sequence"]?.exactInt else { return nil }
                return RollingStock.Car(
                    sequence: sequence, number: item["number"]?.stringOrNilIfNotString,
                    series: item["series"]?.stringOrNilIfNotString)
            }
        }
        return RollingStock(
            setNumber: value["set_number"]?.stringOrNilIfNotString,
            carCount: value["car_count"]?.exactInt, cars: cars,
            riddenCar: value["ridden_car"]?.exactInt,
            livery: value["livery"]?.stringOrNilIfNotString)
    }

    static func ticket(_ value: JSON?) -> Ticket? {
        guard let value, case .object = value else { return nil }
        return Ticket(
            seat: value["seat"]?.stringOrNilIfNotString,
            seatClass: value["seat_class"]?.stringOrNilIfNotString,
            fare: value["fare"]?.exactInt,
            currency: value["currency"]?.stringOrNilIfNotString,
            kind: value["kind"]?.stringOrNilIfNotString)
    }

    static func json(_ stock: RollingStock) -> JSON {
        var pairs: [(String, JSON)] = []
        if let value = stock.setNumber { pairs.append(("set_number", .string(value))) }
        if let value = stock.carCount { pairs.append(("car_count", .number(Double(value)))) }
        if let cars = stock.cars {
            pairs.append(("cars", .array(cars.map { car in
                var row: [(String, JSON)] = [("sequence", .number(Double(car.sequence)))]
                if let number = car.number { row.append(("number", .string(number))) }
                if let series = car.series { row.append(("series", .string(series))) }
                return .object(JSON.Object(row))
            })))
        }
        if let value = stock.riddenCar { pairs.append(("ridden_car", .number(Double(value)))) }
        if let value = stock.livery { pairs.append(("livery", .string(value))) }
        return .object(JSON.Object(pairs))
    }

    static func json(_ ticket: Ticket) -> JSON {
        var pairs: [(String, JSON)] = []
        if let value = ticket.seat { pairs.append(("seat", .string(value))) }
        if let value = ticket.seatClass { pairs.append(("seat_class", .string(value))) }
        if let value = ticket.fare { pairs.append(("fare", .number(Double(value)))) }
        if let value = ticket.currency { pairs.append(("currency", .string(value))) }
        if let value = ticket.kind { pairs.append(("kind", .string(value))) }
        return .object(JSON.Object(pairs))
    }

    /// Shape and range facts for the two optional blocks.
    static func tripDetailDiagnostics(_ train: Train) -> [Diagnostic] {
        var issues: [Diagnostic] = []
        func negative(_ path: String, _ value: Int?) {
            if let value, value < 0 {
                issues.append(Diagnostic(path: path, reason: "\(path) must be a non-negative integer."))
            }
        }
        if let stock = train.rollingStock {
            negative("rolling_stock.car_count", stock.carCount)
            negative("rolling_stock.ridden_car", stock.riddenCar)
            for (offset, car) in (stock.cars ?? []).enumerated() {
                negative("rolling_stock.cars[\(offset)].sequence", car.sequence)
            }
        }
        if let ticket = train.ticket {
            negative("ticket.fare", ticket.fare)
            if let currency = ticket.currency,
               !Ticket.currencies(forRegion: train.region).contains(currency) {
                issues.append(Diagnostic(
                    path: "ticket.currency",
                    reason: "ticket.currency must be one of "
                        + Ticket.currencies(forRegion: train.region).sorted().joined(separator: ", ") + "."))
            }
        }
        return issues
    }
}

extension TrainValidation.JSON {
    /// A finite whole number as `Int`, else nil.
    var exactInt: Int? {
        if case .number(let number) = self, number.isFinite, number.rounded(.towardZero) == number {
            return Int(exactly: number)
        }
        return nil
    }
}
