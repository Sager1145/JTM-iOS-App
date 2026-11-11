import SwiftUI

/// The one row for choosing from a list, form or sheet (decision "selected
/// style"): the selected row shows a trailing accent-coloured checkmark and the
/// others show nothing, with no empty circle. The selection is also exposed as
/// the `.isSelected` accessibility trait, so it is never colour-only.
///
/// A single choice keeps one row selected; a multiple choice passes each row's
/// own state and toggles in `action`. A selection mark is never produced by
/// swapping an icon (`selected ? "checkmark" : "x"`); `check-ui-tokens.sh`
/// rejects that. Menus use `Picker` or a select-only `Toggle`, whose system
/// checkmark this row does not replace.
struct RailChoiceRow<Label: View>: View {
    let isSelected: Bool
    let action: () -> Void
    private let label: Label

    init(isSelected: Bool, action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.isSelected = isSelected
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: RailSpacing.s12) {
                label
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: RailSize.touch)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension RailChoiceRow where Label == Text {
    init(_ title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.init(isSelected: isSelected, action: action) { Text(title) }
    }
}
