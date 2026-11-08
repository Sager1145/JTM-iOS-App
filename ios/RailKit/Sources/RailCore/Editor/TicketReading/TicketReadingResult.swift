import Foundation

/// Which country's paper-ticket conventions a scan is read with.
///
/// Hong Kong and Macau have no paper tickets, so they have no case here.
public enum TicketRegion: String, CaseIterable, Sendable, Hashable {
    case jp, tw, kr
}

/// One line of text as a recogniser read it, in reading order (top to bottom).
public struct RecognizedLine: Equatable, Sendable {
    public var text: String
    /// 0...1, as reported by the recogniser.
    public var confidence: Double

    public init(text: String, confidence: Double = 1) {
        self.text = text
        self.confidence = confidence
    }
}

/// What kind of document the ticket is.
public enum TicketKind: String, Sendable, Hashable {
    /// 乗車券 / 車票 / 승차권 — the right to travel.
    case ticket
    /// 特急券 — an express supplement without a seat.
    case expressSupplement
    /// 指定席 / 對號座 / 지정석 — a reserved seat.
    case seatReservation
}

/// A calendar date as printed. The year is `nil` when the ticket omits it.
public struct TicketDate: Hashable, Sendable {
    public var year: Int?
    public var month: Int
    public var day: Int

    public init(year: Int?, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }
}

/// An extracted value with how sure the parser is of it (0...1: the recogniser's
/// confidence in the source line times the strength of the pattern that matched).
public struct TicketField<Value: Hashable & Sendable>: Hashable, Sendable {
    public var value: Value
    public var confidence: Double

    public init(_ value: Value, confidence: Double) {
        self.value = value
        self.confidence = confidence
    }
}

/// The text a ticket scan yielded. Station names are raw text, to be resolved by
/// the editor's station search; nothing here is matched against the catalog.
public struct TicketReadingResult: Hashable, Sendable {
    public var region: TicketRegion
    public var origin: TicketField<String>?
    public var destination: TicketField<String>?
    public var date: TicketField<TicketDate>?
    /// Departure clock time; hours of 24 or more are folded into `dayOffset`.
    public var departureTime: TicketField<ServiceClockTime>?
    /// Printed arrival clock (着 / 抵達 / 도착, or the time after the route
    /// arrow). Its day offset is the hour's own (24:10 is +1); an arrival
    /// before the departure is overnight, which the editor resolves.
    public var arrivalTime: TicketField<ServiceClockTime>?
    /// のぞみ, 自強, KTX …
    public var serviceName: TicketField<String>?
    /// Printed number without the 号/次 suffix. Leading zeros are kept (`0123`).
    public var serviceNumber: TicketField<String>?
    /// Car number without leading zeros or the 号車/車廂/호차 suffix.
    public var car: TicketField<String>?
    /// Seat label such as `12A`.
    public var seat: TicketField<String>?
    /// Printed class label: グリーン車, 商務車廂, 일반실 …
    public var seatClass: TicketField<String>?
    /// Fare in ISO 4217 minor units: JPY and KRW have no minor unit (¥14,720 is 14720),
    /// TWD has two (NT$1,490 is 149000).
    public var fare: TicketField<Int>?
    /// ISO 4217 code of `fare`.
    public var currency: TicketField<String>?
    public var kind: TicketField<TicketKind>?

    public init(region: TicketRegion) {
        self.region = region
    }

    /// True when nothing at all was extracted.
    public var isEmpty: Bool {
        origin == nil && destination == nil && date == nil && departureTime == nil && arrivalTime == nil
            && serviceName == nil && serviceNumber == nil && car == nil && seat == nil
            && seatClass == nil && fare == nil && currency == nil && kind == nil
    }
}
