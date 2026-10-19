import SwiftUI

/// Allows fixed-size panel content to scroll when the available height is smaller.
struct ScrollableIfNeeded: ViewModifier {
    func body(content: Content) -> some View {
        ScrollView { content }
            .scrollBounceBehavior(.basedOnSize)
    }
}

