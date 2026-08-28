import RailPresentation
import SwiftUI

/// §13.2's waiting state: the workspace has nothing to show yet and says which
/// nothing it is.
///
/// Both views in this file are pure functions of a resolved
/// ``JourneyPresentation``. That is the point of them being here rather than on
/// the workspace: `JourneyPresentationResolver` already decided what a phase
/// means, these two decide only how it is drawn, and nothing between the two
/// decisions needs a store, a map or a sheet.
struct WorkspaceStatusView: View {
    let presentation: JourneyPresentation

    @Environment(AppLocalization.self) private var localization

    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text(localization.journeyText(presentation.title))
                .font(.headline)
            if let status = presentation.status {
                Text(localization.journeyText(status.title))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// §13.1 and §13.3: an empty or failed workspace, with the single primary
/// action the resolver chose for that phase.
struct WorkspaceUnavailableView: View {
    let presentation: JourneyPresentation
    let systemImage: String
    var description: String? = nil

    /// The resolver's two action slots, kept apart because they carry
    /// different types — the workspace answers both with an overload named
    /// `perform`, and which one runs is decided by the action, not by the
    /// slot's name. Collapsing them into one closure does not typecheck, and
    /// that is the compiler being right: a primary action and a secondary one
    /// are not the same vocabulary.
    ///
    /// Both stay closures because the actions are the workspace's — `sheet`,
    /// `controller.fitToSelection`, the store — and none of them is this
    /// view's to perform.
    let perform: (JourneyPresentation.PrimaryAction) -> Void
    let performSecondary: (SecondaryAction) -> Void

    @Environment(AppLocalization.self) private var localization

    var body: some View {
        ContentUnavailableView {
            Label(localization.journeyText(presentation.title), systemImage: systemImage)
        } description: {
            VStack(spacing: 8) {
                if let subtitle = presentation.subtitle {
                    Text(localization.journeyText(subtitle))
                }
                if let description { Text(description) }
                if let status = presentation.status {
                    // §13.3: what was kept, next to what went wrong.
                    Text(localization.journeyText(status.title))
                        .foregroundStyle(status.tone.color)
                }
            }
        } actions: {
            QuietActionGroup(
                presentation: presentation,
                perform: perform,
                performSecondary: performSecondary
            )
            .frame(maxWidth: 320)
        }
        // §4.1: "按钮、列表最后一行和滚动指示器必须避开底栏". The panel's
        // content region ends where the destination selector begins, and a
        // `ContentUnavailableView` is an inflexible block — at the medium stop
        // its action button was being cut in half by that edge. Scrolling is
        // how a block that cannot shrink gives way.
        .modifier(ScrollableIfNeeded())
    }
}
