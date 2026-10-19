import SwiftUI
import UIKit

/// `#rrggbb` — the only colour spelling the rail packages and the train store
/// carry, read once.
///
/// There were three readers of it: one nested inside the map coordinator, one
/// private to the video exporter, and one hung off `Color` in the middle of
/// `RailNetworkStore`. The first two were the same eleven lines twice over;
/// the third differed only in which framework's colour it returned.
///
/// The channel decode is shared and the *trimming* is not, deliberately. The
/// two `UIColor` callers accepted a value padded with newlines and the `Color`
/// one did not, and a shared trim would have had to pick one — quietly
/// widening what one of them accepts. Each keeps the tolerance it shipped
/// with; what they now share is the part that decides what a colour IS.
enum HexColor {

    /// The three channels of an already-trimmed `#rrggbb`, or nil where the
    /// string is not one.
    ///
    /// A leading `#` is optional because the packages write it and the app's
    /// own literals sometimes do not.
    static func channels(_ text: String) -> (red: Double, green: Double, blue: Double)? {
        var body = text
        if body.hasPrefix("#") { body.removeFirst() }
        guard body.count == 6, let value = UInt32(body, radix: 16) else { return nil }
        return (
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }
}

extension UIColor {
    /// A rail package's colour, for the tiers that draw in UIKit — the map's
    /// annotation views, its overlay renderers and the video exporter.
    ///
    /// Named `railHex` rather than `hex` because this is an extension on a
    /// system type: a bare `UIColor(hex:)` in a target this size is a name
    /// every future file will assume is the system's own.
    convenience init?(railHex hex: String) {
        guard let channels = HexColor.channels(
            hex.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }
        self.init(
            red: CGFloat(channels.red), green: CGFloat(channels.green),
            blue: CGFloat(channels.blue), alpha: 1)
    }
}

extension Color {
    /// Reads the `#rrggbb` strings the rail packages store.
    ///
    /// The packages also carry `colorDark` for operators that publish a
    /// separate dark-mode colour; wiring that to the colour scheme is a
    /// follow-up, and doing it here rather than in `RailCore` is deliberate —
    /// which colour a theme picks is presentation, and presentation does not
    /// go in the pure tier.
    init?(hex: String?) {
        guard let hex,
            let channels = HexColor.channels(hex.trimmingCharacters(in: .whitespaces))
        else { return nil }
        self.init(red: channels.red, green: channels.green, blue: channels.blue)
    }
}
