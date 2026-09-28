/// The date contract shared by an exact timetable occurrence and dated rail
/// history. A trip belongs to one railway service day even when its published
/// clock runs past 24:00. Stop times still describe the rollover for display
/// and date-bucket purposes, but rail identity and route validity are checked
/// against the occurrence's service day.
public struct TimetableServiceDayContext: Sendable, Equatable {
    public let serviceDate: String

    public init(serviceDate: String) {
        self.serviceDate = serviceDate
    }

    /// The map and route solver keep the occurrence's railway service day.
    public var networkRideDate: String { serviceDate }

    /// The one date supplied to every route section in this occurrence.
    /// `totalSeconds` is accepted to make the service-day choice explicit at
    /// call sites handling 24:xx / next-day clock values.
    public func railValidityDate(totalSeconds: Int? = nil) -> String {
        networkRideDate
    }

    public func contains(validFrom: String?, validUntil: String?) -> Bool {
        RouteGraph.RailValidity.isValid(
            validFrom: validFrom, validTo: validUntil, on: serviceDate)
    }
}
