import SwiftUI

private struct SearchPreferencesKey: EnvironmentKey {
    static var defaultValue: UserDefaults { .standard }
}

extension EnvironmentValues {
    /// The preferences store recent searches and picks live in: the shell's
    /// (isolated under UI test), not always `UserDefaults.standard`.
    var searchPreferences: UserDefaults {
        get { self[SearchPreferencesKey.self] }
        set { self[SearchPreferencesKey.self] = newValue }
    }
}
