import SwiftUI

/// The live shape of the menu panel — the stop it is nearest and how far its
/// header has opened, 0…1 — as a value the few views that morph with it
/// OBSERVE, rather than one the whole page tree is rebuilt around.
///
/// Written by whichever layout owns the panel's height: the docked card's
/// header drag (``DockedCard``) and the phone sheet's live height
/// (`mapLayout`). Read by `PanelHeader`, `RideCard` and `WorkspacePanelPage`.
/// Nothing else should depend on it, so a drag frame re-evaluates those
/// three and nothing above them.
@MainActor @Observable
final class PanelMorph {
    var stage: SheetStage
    /// Header expansion between the compact and half stops, 0…1.
    var expansion: CGFloat

    init(stage: SheetStage = .expanded, expansion: CGFloat = 1) {
        self.stage = stage
        self.expansion = expansion
    }

    func update(stage: SheetStage, expansion: CGFloat) {
        if self.stage != stage { self.stage = stage }
        if self.expansion != expansion { self.expansion = expansion }
    }
}

/// Reads the live stage for one small piece of the tree that has to branch
/// on it, so that piece — and only that piece — is rebuilt when the stop
/// changes. Falls back to expanded when no `PanelMorph` is in the environment
/// (previews, or a card hosted outside the workspace).
struct PanelStageReader<Content: View>: View {
    @Environment(PanelMorph.self) private var morph: PanelMorph?
    @ViewBuilder var content: (SheetStage) -> Content

    var body: some View {
        content(morph?.stage ?? .expanded)
    }
}
