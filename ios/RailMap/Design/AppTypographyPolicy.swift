import SwiftUI
import UIKit

/// The user-selected text-size bounds apply to every app and test surface.
enum AppTypographyPolicy {
    static let supportedSizes: ClosedRange<DynamicTypeSize> = .xSmall ... .xLarge

    static func preferredFont(forTextStyle style: UIFont.TextStyle) -> UIFont {
        let requested = UIFont.preferredFont(forTextStyle: style)
        let minimum = UIFont.preferredFont(forTextStyle: style,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .extraSmall))
        let maximum = UIFont.preferredFont(forTextStyle: style,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .extraLarge))
        return requested.withSize(min(maximum.pointSize, max(minimum.pointSize, requested.pointSize)))
    }
}

