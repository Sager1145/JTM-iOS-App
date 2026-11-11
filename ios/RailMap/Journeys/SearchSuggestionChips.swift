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
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: RailSpacing.s8) {
                    if let lead { Text(lead).railText(.secondary) }
                    ForEach(chips) { chip in
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
                        .accessibilityIdentifier("\(identifierPrefix)-\(chip.id)")
                    }
                }
                .padding(.horizontal, RailSpacing.screenInset)
            }
        }
    }
}
