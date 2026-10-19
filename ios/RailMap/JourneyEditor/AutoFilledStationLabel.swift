import SwiftUI

/// A compact source label shared by route previews and both editor modes.
struct AutoFilledStationLabel: View {
    @Environment(AppLocalization.self) private var localization

    var body: some View {
        Label(localization.text("ios.editor.generatedStation"), systemImage: "wand.and.stars")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
            .fixedSize(horizontal: false, vertical: true)
    }
}
