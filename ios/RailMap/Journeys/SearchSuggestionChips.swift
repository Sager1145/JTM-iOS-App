import RailCore
import SwiftUI

/// One row of tappable suggestion chips under a search field: up to three
/// "Did you mean" corrections, the top completion while typing, or recent
/// searches in an empty box. Shared by the station picker and journey search.
struct SearchSuggestionChips: View {
    typealias Kind = SearchChipKind

    struct Chip: Identifiable, Hashable {
        var kind: Kind
        /// What the chip shows.
        var label: String
        /// What the field becomes when it is tapped.
        var text: String
        var id: String { "\(kind)-\(text)" }
    }

    @Environment(AppLocalization.self) private var localization
    let chips: [Chip]
    let identifierPrefix: String
    let action: (Chip) -> Void
    /// Long-press "Remove" on a recent chip. Nil leaves the chips without the menu.
    var onRemove: ((Chip) -> Void)? = nil
    /// The one Clear, pinned at the trailing edge of a Recent row. Nil hides it.
    var onClear: (() -> Void)? = nil
    var clearIdentifier = "searchRecentClear"

    static func chips(corrections: [SearchCorrection]) -> [Chip] {
        corrections.prefix(3).map { Chip(kind: .didYouMean, label: $0.displayText, text: $0.text) }
    }

    /// The row's label comes from its first labelled chip, so a completion chip
    /// in front does not hide "Did you mean".
    private var lead: String? {
        switch Kind.lead(of: chips.map(\.kind)) {
        case .didYouMean: localization.text("ios.search.didYouMeanLabel", fallback: "Did you mean")
        case .recent: localization.text("ios.search.recentLabel", fallback: "Recent")
        case .frequent: localization.text("ios.search.frequentLabel", fallback: "Often")
        default: nil
        }
    }

    var body: some View {
        if !chips.isEmpty {
            HStack(spacing: RailSpacing.s8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: RailSpacing.s8) {
                        if let lead { Text(lead).railText(.secondary) }
                        ForEach(chips) { chip in chipButton(chip) }
                    }
                    .padding(.leading, RailSpacing.screenInset)
                    .padding(.trailing, onClear == nil ? RailSpacing.screenInset : 0)
                }
                if let onClear, chips.contains(where: { $0.kind == .recent }) {
                    Button(localization.text("ios.search.clearRecent", fallback: "Clear"), action: onClear)
                        .railText(.secondary)
                        .frame(minHeight: RailSize.touch)
                        .padding(.trailing, RailSpacing.screenInset)
                        .accessibilityIdentifier(clearIdentifier)
                }
            }
        }
    }

    private func chipButton(_ chip: Chip) -> some View {
        Button { action(chip) } label: {
            HStack(spacing: RailSpacing.s4) {
                if chip.kind == .completion { Image(systemName: "arrow.turn.down.right") }
                Text(chip.label).lineLimit(1)
            }
            .railText(.secondary)
            .foregroundStyle(.primary)
            .padding(.horizontal, RailSpacing.s12)
            .padding(.vertical, RailSpacing.s8)
            .background(Color(.tertiarySystemFill), in: Capsule())
            .frame(minHeight: RailSize.touch)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if chip.kind == .recent, let onRemove {
                Button(localization.text("ios.search.removeRecent", fallback: "Remove"), role: .destructive) {
                    onRemove(chip)
                }
            }
        }
        .accessibilityIdentifier("\(identifierPrefix)-\(chip.id)")
    }
}
