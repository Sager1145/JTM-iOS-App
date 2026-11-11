import SwiftUI
import UIKit

/// The one status-message style: a warning or an error shown to the reader.
///
/// Audit finding H4: messages were caption-size orange or red text, about 2.2:1
/// (orange) and 3.6:1 (red) on a white row. Here the message is `.primary` text
/// at footnote size, which meets 4.5:1 in light and dark mode. The severity is
/// carried by a leading SF Symbol, one fixed symbol per kind, so the state is
/// never colour-only; the symbol is tinted with a colour that keeps at least
/// 3:1 against the system backgrounds. Messages wrap; there is no line limit.
///
/// `ios/tools/check-ui-tokens.sh` rejects orange or red foreground styles on
/// text outside `Design/`, so new messages come through this view.
enum RailStatusKind {
    case warning
    case error

    var symbol: String {
        switch self {
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    /// Icon tint. Darker than `systemOrange`/`systemRed` in light mode (those
    /// are 2.2:1 and 3.6:1 on white); the system values in dark mode.
    var tint: Color {
        switch self {
        case .warning:
            Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
                ? UIColor.systemOrange : UIColor(red: 0.62, green: 0.30, blue: 0, alpha: 1) })
        case .error:
            Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
                ? UIColor.systemRed : UIColor(red: 0.74, green: 0.10, blue: 0.10, alpha: 1) })
        }
    }

    fileprivate var labelKey: String {
        switch self {
        case .warning: "ios.status.warning"
        case .error: "ios.status.error"
        }
    }

    fileprivate var labelFallback: String {
        switch self {
        case .warning: "Warning"
        case .error: "Error"
        }
    }
}

struct RailStatusLabel<Content: View>: View {
    @Environment(AppLocalization.self) private var localization
    let kind: RailStatusKind
    private let font: Font
    private let content: Content

    init(kind: RailStatusKind, font: Font = .footnote, @ViewBuilder content: () -> Content) {
        self.kind = kind
        self.font = font
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: RailSpacing.s8) {
            Image(systemName: kind.symbol)
                .foregroundStyle(kind.tint)
                .accessibilityLabel(localization.text(kind.labelKey, fallback: kind.labelFallback))
            content
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(font)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

extension RailStatusLabel where Content == Text {
    init(kind: RailStatusKind, text: String) {
        self.init(kind: kind) { Text(text) }
    }
}
