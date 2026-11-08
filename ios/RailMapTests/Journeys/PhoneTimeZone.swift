import Foundation
import Testing

/// Runs `body` with the phone's time zone set to `identifier`, the way a
/// system zone change does: `TimeZone.current` is cached apart from
/// `NSTimeZone.default`, so TZ, tzset and both are moved. The process zone is
/// one global, so callers loop zones inside one test, never across tests.
@MainActor
func withPhoneTimeZone<T>(_ identifier: String, _ body: () throws -> T) rethrows -> T {
    let originalDefault = NSTimeZone.default
    let originalTZ = getenv("TZ").map { String(cString: $0) }
    defer {
        if let originalTZ { setenv("TZ", originalTZ, 1) } else { unsetenv("TZ") }
        tzset()
        NSTimeZone.resetSystemTimeZone()
        NSTimeZone.default = originalDefault
    }
    setenv("TZ", identifier, 1)
    tzset()
    NSTimeZone.resetSystemTimeZone()
    NSTimeZone.default = TimeZone(identifier: identifier) ?? originalDefault
    #expect(TimeZone.current.identifier == identifier && Calendar.current.timeZone.identifier == identifier)
    return try body()
}
