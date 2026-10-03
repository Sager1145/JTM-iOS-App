import SwiftUI

private struct JourneyMenuNamespaceKey: EnvironmentKey {
    static var defaultValue: Namespace.ID? { nil }
}

private struct JourneyMenuSourceIsActiveKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var railJourneyMenuNamespace: Namespace.ID? {
        get { self[JourneyMenuNamespaceKey.self] }
        set { self[JourneyMenuNamespaceKey.self] = newValue }
    }

    var railJourneyMenuSourceIsActive: Bool {
        get { self[JourneyMenuSourceIsActiveKey.self] }
        set { self[JourneyMenuSourceIsActiveKey.self] = newValue }
    }
}

private struct JourneyMenuSource: ViewModifier {
    let id: String
    @Environment(\.railJourneyMenuNamespace) private var namespace
    @Environment(\.railJourneyMenuSourceIsActive) private var isActive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), let namespace, isActive, !reduceMotion {
            content.matchedTransitionSource(id: id, in: namespace) { source in
                source
                    .background(Color.railMenuBackground)
                    .clipShape(RoundedRectangle(
                        cornerRadius: RailStyle.cardCornerRadius, style: .continuous))
            }
        } else {
            content
        }
    }
}

private struct JourneyMenuDestination: ViewModifier {
    // Retain the opening identity even if an edit changes the record ID.
    let id: String
    @Environment(\.railJourneyMenuNamespace) private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), let namespace, !reduceMotion {
            // UIKit owns the reversible spring and interactive cancellation.
            // A missing/offscreen source falls back to system presentation.
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
        }
    }
}

extension View {
    func railJourneyMenuSource(id: String) -> some View {
        modifier(JourneyMenuSource(id: id))
    }

    func railJourneyMenuDestination(id: String) -> some View {
        modifier(JourneyMenuDestination(id: id))
    }
}
