import Foundation

extension TrainTimetableDatabase {
    /// What a published formation contributes to a draft ride: the series for
    /// `Train.vehicleType` and the set/cars for `Train.rollingStock`.
    public struct RollingStockDraft: Sendable, Equatable {
        public var vehicleType: String?
        public var rollingStock: RollingStock?

        public init(vehicleType: String? = nil, rollingStock: RollingStock? = nil) {
            self.vehicleType = vehicleType
            self.rollingStock = rollingStock
        }
    }

    /// Maps published consist facts without inventing any. Livery and the
    /// ridden car are not timetable facts and stay nil. Returns nil when the
    /// formation names nothing usable.
    public static func rollingStockDraft(from formation: Formation) -> RollingStockDraft? {
        func clean(_ text: String?) -> String? {
            guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
            else { return nil }
            return text
        }
        let cars = formation.cars.map {
            RollingStock.Car(sequence: $0.sequence, number: clean($0.number),
                             series: clean($0.vehicleSeries))
        }
        let series = clean(formation.vehicleSeries) ?? cars.compactMap(\.series).first
        let stock = RollingStock(
            setNumber: clean(formation.label),
            carCount: formation.carCount ?? (cars.isEmpty ? nil : cars.count),
            cars: cars.isEmpty ? nil : cars)
        if series == nil && stock.isEmpty { return nil }
        return RollingStockDraft(vehicleType: series, rollingStock: stock.isEmpty ? nil : stock)
    }

    /// The draft for one exact service day, or nil when none is published.
    public func rollingStockDraft(for trip: Trip) throws -> RollingStockDraft? {
        try formation(for: trip).flatMap(Self.rollingStockDraft(from:))
    }
}

extension TrainTimetableDatabase.Trip {
    /// ``publishedStopsDraft(to:ridden:)`` plus the published formation. The
    /// existing method is unchanged; fields the draft already carries
    /// (`vehicleType`, `rollingStock`) are kept rather than overwritten.
    public func publishedStopsDraft(
        to train: Train, ridden: Bool = true, formation: TrainTimetableDatabase.Formation?
    ) -> Train? {
        guard var result = publishedStopsDraft(to: train, ridden: ridden) else { return nil }
        if let formation, let draft = TrainTimetableDatabase.rollingStockDraft(from: formation) {
            if result.vehicleType?.isEmpty ?? true { result.vehicleType = draft.vehicleType }
            if result.rollingStock == nil { result.rollingStock = draft.rollingStock }
        }
        return result
    }
}
