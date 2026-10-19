import RailCore
import SwiftUI

/// A form field that keeps its label visible once it has a value.
///
/// A bare `TextField("車次", text:)` in a `Form` shows its title *only while
/// the field is empty* — the moment a value arrives, the one word saying what
/// the value means disappears. On a form of ten fields that leaves a column of
/// unlabelled strings, and it is worse in the three CJK interface languages,
/// where a station name and an operator name are the same shape.
///
/// So the label is a caption above the value, which also keeps a long label
/// and a long value from competing for one line (§10.1, §14.5).
struct EditorField<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            content
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

/// `EditorField` around a plain text field, which is nearly all of them.
///
/// `focus`/`field` are threaded in rather than left to the caller's
/// `.focused(...)` on the wrapper: the focus binding has to land on the
/// focusable element itself for "查看错误" to be able to put the cursor in the
/// first bad field, and a modifier on the enclosing `VStack` is not a
/// guarantee that it does.
struct EditorTextField: View {
    let title: String
    @Binding var text: String
    var prompt: String?
    var focus: FocusState<RideDraftIssue.Field?>.Binding?
    var field: RideDraftIssue.Field?
    var onSubmit: (() -> Void)? = nil

    var body: some View {
        EditorField(title: title) {
            if let focus, let field {
                textField.focused(focus, equals: field)
            } else {
                textField
            }
        }
    }

    private var textField: some View {
        TextField(title, text: $text, prompt: Text(prompt ?? title))
            .labelsHidden()
            .onSubmit { onSubmit?() }
    }
}

/// Text remains editable even when a catalog or previous record has no match.
struct EditorSearchField: View {
    let title: String
    @Binding var text: String
    let suggestions: [String]
    var prompt: String? = nil
    var focus: FocusState<RideDraftIssue.Field?>.Binding?
    var field: RideDraftIssue.Field?
    @FocusState private var hasFocus: Bool

    private var matches: [String] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prepared = SearchFold.PreparedQuery(query)
        return Array(Set(suggestions.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }))
            .filter { query.isEmpty || prepared.matches(fields: OperatorIdentity.searchNames(for: $0)) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .prefix(6).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            EditorField(title: title) {
                textField
            }
            if isFocused {
                ForEach(matches, id: \.self) { value in
                    Button {
                        text = value
                        dismissFocus()
                    } label: {
                        Label(value, systemImage: "arrow.up.left")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("editorSuggestion-\(value)")
                }
            }
        }
    }

    // Bind the native field to the same focus state as the editor's other fields.
    // The private Boolean is only used by search fields without an editor binding.
    @ViewBuilder private var textField: some View {
        if let focus, let field {
            baseTextField.focused(focus, equals: field)
        } else {
            baseTextField.focused($hasFocus)
        }
    }

    private var baseTextField: some View {
        TextField(title, text: $text, prompt: Text(prompt ?? title))
            .submitLabel(.done)
            .onSubmit { dismissFocus() }
            .autocorrectionDisabled()
    }

    private var isFocused: Bool {
        if let focus, let field { return focus.wrappedValue == field }
        return hasFocus
    }

    private func dismissFocus() {
        if let focus, let field {
            if focus.wrappedValue == field { focus.wrappedValue = nil }
        } else {
            hasFocus = false
        }
    }
}

