import Foundation

/// A clock time folded onto a service date. Hours at or after 24 are carried in `dayOffset`.
public struct ServiceClockTime: Hashable, Sendable, Codable {
    /// Whole days beyond the service date.
    public var dayOffset: Int
    /// 0...23 after folding.
    public var hour: Int
    /// 0...59.
    public var minute: Int

    public init(dayOffset: Int, hour: Int, minute: Int) {
        self.dayOffset = dayOffset
        self.hour = hour
        self.minute = minute
    }

    /// Minutes from service-date midnight. 25:10 → 1510.
    public var serviceMinutes: Int { dayOffset * 1440 + hour * 60 + minute }
}

public enum ServiceTimeParse: Hashable, Sendable {
    case unset
    case invalid(raw: String)
    case valid(raw: String, time: ServiceClockTime)
}

public struct EditorTimeInput: Hashable, Sendable {
    public var raw: String
    /// True only after the user typed a value or confirmed a picker.
    /// A picker merely displaying "now" is not confirmed.
    public var confirmed: Bool
    public var parsed: ServiceTimeParse

    public init(raw: String, confirmed: Bool, parsed: ServiceTimeParse) {
        self.raw = raw
        self.confirmed = confirmed
        self.parsed = parsed
    }

    public var unlocksAI: Bool {
        guard confirmed else { return false }
        if case .valid = parsed { return true }
        return false
    }
}

public enum ServiceDateParse: Hashable, Sendable {
    case unset
    case invalid(raw: String)
    case valid(year: Int, month: Int, day: Int, canonical: String)
}

public enum EditorTime {
    /// Empty / whitespace → unset.
    /// Fullwidth digits and fullwidth colon are normalized first.
    /// Strict whole-string match (after trim + fullwidth fold):
    /// - `H:MM` / `HH:MM` with minute 0...59 and hour 0...99
    /// - 3 digits `HMM` or 4 digits `HHMM` (930 → 9:30, 0930 → 09:30, 2510 → 25:10)
    /// - 1–2 digits, minute 60, hour > 99, trailing junk, `9:99` → invalid (keep raw)
    /// Hour >= 24 folds into dayOffset and hour%24.
    /// Also accept a trailing `+N` day offset (optional spaces around +) ADDED to the folded offset,
    /// with the same 0...366 bound as `Dates.parseTimeToMinutes` and Journey Completion.
    public static func parseTime(_ raw: String?) -> ServiceTimeParse {
        guard let raw else { return .unset }
        let trimmed = trim(foldFullwidth(raw))
        if trimmed.isEmpty { return .unset }
        guard let time = strictTime(trimmed) else { return .invalid(raw: raw) }
        return .valid(raw: raw, time: time)
    }

    /// Canonical storage text. 25:10 stays `25:10`, not `01:10`.
    /// Service hour below 10 is unpadded (`9:30`). Minute is always two digits.
    /// dayOffset 1 + 01:10 → `25:10`. Values through hour 99 use extended-hour form;
    /// larger values use the runtime-compatible `H:MM+N` form instead of emitting a
    /// three-digit hour that `Dates.parseTimeToMinutes` cannot read.
    public static func canonical(_ time: ServiceClockTime) -> String {
        let serviceHour = time.dayOffset * 24 + time.hour
        if serviceHour <= 99 {
            return "\(serviceHour):" + String(format: "%02d", time.minute)
        }

        // Inputs can combine a 99-hour clock with +366, yielding dayOffset 370.
        // Carry only the days beyond the suffix limit into the clock hour so both
        // portions remain inside the shared storage grammar.
        let carriedDays = max(0, time.dayOffset - Dates.maxDayOffset)
        let storageHour = time.hour + carriedDays * 24
        let suffix = time.dayOffset - carriedDays
        return "\(storageHour):" + String(format: "%02d", time.minute) + "+\(suffix)"
    }

    /// Build an input. `confirmed` is the caller's statement that the user committed it.
    /// Invalid or empty text is stored as-is and is not rewritten to 00:00 or now.
    public static func input(_ raw: String, confirmed: Bool) -> EditorTimeInput {
        EditorTimeInput(raw: raw, confirmed: confirmed, parsed: parseTime(raw))
    }

    /// Apply a confirmed picker choice. This is the only way a wheel value becomes text.
    public static func confirmPicker(dayOffset: Int, hour: Int, minute: Int) -> EditorTimeInput {
        guard dayOffset >= 0, hour >= 0, (0...59).contains(minute) else {
            let raw = "\(hour):\(minute)"
            return EditorTimeInput(raw: raw, confirmed: true, parsed: .invalid(raw: raw))
        }
        let time = ServiceClockTime(
            dayOffset: dayOffset + hour / 24,
            hour: hour % 24,
            minute: minute
        )
        let text = canonical(time)
        return EditorTimeInput(raw: text, confirmed: true, parsed: .valid(raw: text, time: time))
    }

    /// Empty → unset. `YYYY-MM-DD` and `YYYY/MM/DD` (and fullwidth digits).
    /// Month 1...12, day must exist in that month (Gregorian, leap years).
    /// 2026-02-31, 2026-02-30, and 2026-06-31 are invalid.
    public static func parseDate(_ raw: String?) -> ServiceDateParse {
        guard let raw else { return .unset }
        let trimmed = trim(foldFullwidth(raw))
        if trimmed.isEmpty { return .unset }
        guard let parsed = strictDate(trimmed) else { return .invalid(raw: raw) }
        return parsed
    }

    // MARK: - time

    private static func strictTime(_ text: String) -> ServiceClockTime? {
        let scalars = Array(text.unicodeScalars)
        guard let (body, plus) = splitDayOffset(scalars) else { return nil }
        guard let (hour, minute) = clock(body), (0...99).contains(hour), (0...59).contains(minute) else {
            return nil
        }
        return ServiceClockTime(dayOffset: hour / 24 + plus, hour: hour % 24, minute: minute)
    }

    /// `nil` when a `+` is present but is not an integer in the runtime's supported range,
    /// with only spaces around it.
    private static func splitDayOffset(
        _ scalars: [Unicode.Scalar]
    ) -> (body: ArraySlice<Unicode.Scalar>, plus: Int)? {
        guard let plusIndex = scalars.firstIndex(of: "+") else {
            return (scalars[...], 0)
        }
        guard !scalars[(plusIndex + 1)...].contains("+") else { return nil }

        var bodyEnd = plusIndex
        while bodyEnd > 0, isSpace(scalars[bodyEnd - 1]) { bodyEnd -= 1 }
        let body = scalars[..<bodyEnd]
        guard !body.isEmpty else { return nil }

        var cursor = plusIndex + 1
        while cursor < scalars.count, isSpace(scalars[cursor]) { cursor += 1 }
        guard cursor < scalars.count, isDigit(scalars[cursor]) else { return nil }
        var plus = 0
        while cursor < scalars.count, isDigit(scalars[cursor]) {
            let digit = Int(scalars[cursor].value - 48)
            guard plus <= (Dates.maxDayOffset - digit) / 10 else { return nil }
            plus = plus * 10 + digit
            cursor += 1
        }
        guard cursor == scalars.count, plus <= Dates.maxDayOffset else { return nil }
        return (body, plus)
    }

    private static func clock(_ body: ArraySlice<Unicode.Scalar>) -> (hour: Int, minute: Int)? {
        if let colon = body.firstIndex(of: ":") {
            let hourDigits = body[..<colon]
            let minuteDigits = body[body.index(after: colon)...]
            guard (1...2).contains(hourDigits.count), minuteDigits.count == 2 else { return nil }
            guard hourDigits.allSatisfy(isDigit), minuteDigits.allSatisfy(isDigit) else { return nil }
            return (decimal(hourDigits), decimal(minuteDigits))
        }
        guard body.count == 3 || body.count == 4, body.allSatisfy(isDigit) else { return nil }
        let minuteDigits = body.suffix(2)
        let hourDigits = body.dropLast(2)
        return (decimal(hourDigits), decimal(minuteDigits))
    }

    // MARK: - date

    private static func strictDate(_ text: String) -> ServiceDateParse? {
        let scalars = Array(text.unicodeScalars)
        guard scalars.count == 10 else { return nil }
        for index in [0, 1, 2, 3, 5, 6, 8, 9] where !isDigit(scalars[index]) {
            return nil
        }
        let separator = scalars[4]
        guard separator == "-" || separator == "/", scalars[7] == separator else { return nil }
        let year = decimal(scalars[0...3])
        let month = decimal(scalars[5...6])
        let day = decimal(scalars[8...9])
        guard (1...12).contains(month), (1...daysInMonth(year: year, month: month)).contains(day) else {
            return nil
        }
        let canonical = String(format: "%04d-%02d-%02d", year, month, day)
        return .valid(year: year, month: month, day: day, canonical: canonical)
    }

    private static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12:
            return 31
        case 4, 6, 9, 11:
            return 30
        case 2:
            return isLeapYear(year) ? 29 : 28
        default:
            return 0
        }
    }

    private static func isLeapYear(_ year: Int) -> Bool {
        if year % 400 == 0 { return true }
        if year % 100 == 0 { return false }
        return year % 4 == 0
    }

    // MARK: - characters

    /// Fullwidth digits (U+FF10...FF19) and fullwidth colon (U+FF1A) → ASCII.
    private static func foldFullwidth(_ text: String) -> String {
        var folded = ""
        folded.unicodeScalars.reserveCapacity(text.unicodeScalars.count)
        for scalar in text.unicodeScalars {
            if (0xFF10...0xFF19).contains(scalar.value) {
                folded.unicodeScalars.append(Unicode.Scalar(scalar.value - 0xFF10 + 0x30)!)
            } else if scalar.value == 0xFF1A {
                folded.unicodeScalars.append(":")
            } else {
                folded.unicodeScalars.append(scalar)
            }
        }
        return folded
    }

    private static func trim(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isDigit(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value >= 48 && scalar.value <= 57
    }

    private static func isSpace(_ scalar: Unicode.Scalar) -> Bool {
        Character(scalar).isWhitespace
    }

    private static func decimal(_ digits: some Sequence<Unicode.Scalar>) -> Int {
        digits.reduce(0) { $0 * 10 + Int($1.value - 48) }
    }
}

public enum EditorAIDenial: Hashable, Sendable {
    case noResolvedStation
    case noExplicitTime
    case invalidTime
    case timeNotOnThatStation
    case providerUnavailable
    case requestInFlight
}

public struct EditorAIStop: Hashable, Sendable {
    public var occurrenceID: UUID
    public var stationResolved: Bool
    /// Arrival and departure are the two fields. Pass-through uses departure only; pass arrival as unset input.
    public var arrival: EditorTimeInput
    public var departure: EditorTimeInput

    public init(
        occurrenceID: UUID,
        stationResolved: Bool,
        arrival: EditorTimeInput,
        departure: EditorTimeInput
    ) {
        self.occurrenceID = occurrenceID
        self.stationResolved = stationResolved
        self.arrival = arrival
        self.departure = departure
    }
}

public enum EditorAIEligibility {
    /// Nil means a request is allowed.
    ///
    /// Allowed when the provider is available, nothing is in flight, and at least one stop has
    /// `stationResolved` and an `unlocksAI` time on arrival or departure of that same stop.
    /// A resolved station on stop A plus an explicit time only on stop B is `timeNotOnThatStation`
    /// when no stop has both.
    ///
    /// Priority when denied: `requestInFlight`, `providerUnavailable`, then
    /// `timeNotOnThatStation` if some stop has a station and some other stop has an explicit time,
    /// `invalidTime` if a resolved station has confirmed invalid text and no good anchor,
    /// `noExplicitTime` if a resolved station exists but its times are unconfirmed or unset,
    /// `noResolvedStation` otherwise.
    public static func denial(
        stops: [EditorAIStop],
        providerAvailable: Bool,
        requestInFlight: Bool
    ) -> EditorAIDenial? {
        if requestInFlight { return .requestInFlight }
        if !providerAvailable { return .providerUnavailable }

        let explicit: (EditorAIStop) -> Bool = { $0.arrival.unlocksAI || $0.departure.unlocksAI }
        if stops.contains(where: { $0.stationResolved && explicit($0) }) { return nil }

        let anyStation = stops.contains(where: \.stationResolved)
        if anyStation && stops.contains(where: explicit) { return .timeNotOnThatStation }

        if stops.contains(where: { stop in
            stop.stationResolved && (confirmedInvalid(stop.arrival) || confirmedInvalid(stop.departure))
        }) {
            return .invalidTime
        }
        if anyStation { return .noExplicitTime }
        return .noResolvedStation
    }

    private static func confirmedInvalid(_ input: EditorTimeInput) -> Bool {
        guard input.confirmed else { return false }
        if case .invalid = input.parsed { return true }
        return false
    }
}
