/// The one place that knows proleptic-Gregorian civil-date arithmetic: leap
/// years, month lengths and the days-since-1970 serial. Pure integer maths, no
/// `Calendar`, `TimeZone` or `DateFormatter`, so the answer never depends on
/// the device (the JS reference does the same in UTC integers).
///
/// Callers keep their own string syntax rules (digit counts, separators, year
/// range, canonical output) and only share the arithmetic below. Sites that
/// consult Foundation's `Calendar` are NOT interchangeable with this: its
/// Gregorian calendar switches to Julian before 1582.
enum CivilDate {
    /// Gregorian leap-year rule (valid for every `Int`).
    static func isLeapYear(_ year: Int) -> Bool {
        year.isMultiple(of: 400) || (year.isMultiple(of: 4) && !year.isMultiple(of: 100))
    }

    /// Days in `month` (1...12) of `year`; 0 for a month outside 1...12.
    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        case 2: return isLeapYear(year) ? 29 : 28
        default: return 0
        }
    }

    /// Days since 1970-01-01 for a proleptic Gregorian civil date.
    static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        // The era trick: shift the year so March starts it, which makes the
        // leap day the last day of the year and removes every special case.
        let y = year - (month <= 2 ? 1 : 0)
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400                              // 0…399
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146097 + dayOfEra - 719468
    }

    /// The inverse of ``daysFromCivil(year:month:day:)``.
    static func civilFromDays(_ serial: Int) -> (year: Int, month: Int, day: Int) {
        let z = serial + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let dayOfEra = z - era * 146097                            // 0…146096
        let yearOfEra =
            (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146096) / 365
        let year = yearOfEra + era * 400
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let mp = (5 * dayOfYear + 2) / 153                         // 0…11, March-based
        let day = dayOfYear - (153 * mp + 2) / 5 + 1
        let month = mp + (mp < 10 ? 3 : -9)
        return (year + (month <= 2 ? 1 : 0), month, day)
    }
}
