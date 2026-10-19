import Foundation
import SwiftUI

/// Shared text adapters for optional persisted editor fields.
@MainActor
enum EditorBindings {
    /// Only an empty string clears the field; whitespace is preserved for validation.
    static func optionalText<Root>(
        _ root: Binding<Root>, _ keyPath: WritableKeyPath<Root, String?>
    ) -> Binding<String> {
        Binding(
            get: { root.wrappedValue[keyPath: keyPath] ?? "" },
            set: { root.wrappedValue[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    /// Trims comma-separated entries while retaining their order and duplicates.
    static func commaSeparated<Root>(
        _ root: Binding<Root>, _ keyPath: WritableKeyPath<Root, [String]?>
    ) -> Binding<String> {
        Binding(
            get: { (root.wrappedValue[keyPath: keyPath] ?? []).joined(separator: ", ") },
            set: { text in
                let values = text.split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }.filter { !$0.isEmpty }
                root.wrappedValue[keyPath: keyPath] = values.isEmpty ? nil : values
            }
        )
    }
}
