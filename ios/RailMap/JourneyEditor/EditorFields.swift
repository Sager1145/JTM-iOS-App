import RailCore
import RailPresentation
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
        VStack(alignment: .leading, spacing: RailSpacing.s4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            content
        }
        .frame(minHeight: RailSize.touch)
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



/// Where an automatic value came from, as a small tag beside its field. It
/// disappears the moment the reader edits the value.
struct FillSourceBadge: View {
    @Environment(AppLocalization.self) private var localization
    let source: TripDraftModel.FillSource?

    var body: some View {
        if let source {
            // One capsule: a Label inside a LabeledContent label is split
            // into separate icon and title pieces.
            HStack(spacing: RailSpacing.s4) {
                Image(systemName: source.symbol)
                Text(localization.text("ios.newTrip.fillSource.\(source.rawValue)",
                                       fallback: source.rawValue.capitalized))
            }
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tint)
                .padding(.horizontal, RailSpacing.s8)
                .padding(.vertical, 2)
                .background(.tint.opacity(0.12), in: Capsule())
                .fixedSize()
                .accessibilityElement(children: .combine)
        }
    }
}

extension TripDraftModel.FillSource {
    var symbol: String {
        switch self {
        case .ticket: "ticket"
        case .timetable: "clock"
        case .nearby: "location"
        }
    }
}

/// One compact row: the label and its source tag on the leading side, the
/// value on the trailing side. Most detail fields are a single line.
struct EditorCompactRow<Value: View>: View {
    let title: String
    var source: TripDraftModel.FillSource? = nil
    @ViewBuilder var value: Value

    var body: some View {
        LabeledContent {
            value
        } label: {
            HStack(spacing: RailSpacing.s8) {
                Text(title)
                FillSourceBadge(source: source)
            }
        }
        .frame(minHeight: RailSize.touch)
    }
}

/// A one-line text entry for `EditorCompactRow`, right-aligned like a
/// Settings value.
struct EditorInlineTextField: View {
    let title: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default

    var body: some View {
        TextField(title, text: $text)
            .multilineTextAlignment(.trailing)
            .keyboardType(keyboard)
            .autocorrectionDisabled()
            .labelsHidden()
    }
}

/// A value the reader has used before, offered under an empty field.
struct EditorSuggestionChip: View {
    @Environment(AppLocalization.self) private var localization
    let value: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(value, systemImage: "clock.arrow.circlepath")
                .font(.footnote)
                .lineLimit(1)
        }
        .buttonStyle(.railSecondary)
        .controlSize(.small)
        .accessibilityHint(localization.text("ios.newTrip.suggestionHint", fallback: "Fills in this value"))
        .accessibilityIdentifier(identifier)
    }
}
