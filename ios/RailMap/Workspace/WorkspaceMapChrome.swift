import SwiftUI

/// Map, playback, and the floating control stack, defined once.
/// Compact, side-by-side, and hinged layouts choose only where that content sits.
/// Portrait sheet lift, dock frames, and the hinged card stay with their owners.
struct WorkspaceMapChrome<MapContent: View, PlaybackContent: View, Controls: View>: View {
    enum Placement {
        /// Phone sheet overlay. The caller owns the portrait arithmetic.
        case compactOverlay(
            transportRoom: CGFloat,
            stageExpanded: Bool,
            showsPlaybackBar: Bool,
            lift: CGFloat,
            railPresent: Bool,
            railFade: Double,
            railLift: CGFloat
        )
        /// Docked card. The map fills the window; playback and controls float
        /// on the trailing edge.
        case sideBySide(
            playbackWidth: CGFloat,
            viewportHeight: CGFloat,
            transportHeight: CGFloat,
            railPresent: Bool,
            showsPlaybackBar: Bool
        )
        /// Hinged card column. The map stays in the Duo shell background and
        /// the Duo toolbar owns controls, so this placement is playback only.
        case hingedPlayback(width: CGFloat, bottomPadding: CGFloat)
    }

    let placement: Placement
    let map: MapContent
    let playback: PlaybackContent
    let controls: Controls

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder var body: some View {
        switch placement {
        case let .compactOverlay(
            transportRoom, stageExpanded, showsPlaybackBar, lift, railPresent, railFade, railLift):
            compactBody(
                transportRoom: transportRoom, stageExpanded: stageExpanded,
                showsPlaybackBar: showsPlaybackBar, lift: lift, railPresent: railPresent,
                railFade: railFade, railLift: railLift)
        case let .sideBySide(
            playbackWidth, viewportHeight, transportHeight, railPresent, showsPlaybackBar):
            sideBySideBody(
                playbackWidth: playbackWidth, viewportHeight: viewportHeight,
                transportHeight: transportHeight, railPresent: railPresent,
                showsPlaybackBar: showsPlaybackBar)
        case let .hingedPlayback(width, bottomPadding):
            hingedBody(width: width, bottomPadding: bottomPadding)
        }
    }

    private func compactBody(
        transportRoom: CGFloat,
        stageExpanded: Bool,
        showsPlaybackBar: Bool,
        lift: CGFloat,
        railPresent: Bool,
        railFade: Double,
        railLift: CGFloat
    ) -> some View {
        ZStack(alignment: .bottomTrailing) {
            map
            playback
                .frame(maxHeight: transportRoom, alignment: .bottom)
                .opacity(stageExpanded ? 0 : 1)
                .allowsHitTesting(!stageExpanded)
                .accessibilityHidden(stageExpanded)
                .padding(.horizontal, 12)
                .offset(y: -lift)
                .railAnimation(
                    RailMotion.spring, value: showsPlaybackBar,
                    reduceMotion: reduceMotion)
            Group {
                if railPresent { controls }
                else { controls.hidden() }
            }
                .padding(.trailing, 12)
                .background {
                    GeometryReader { rail in
                        Color.clear.preference(
                            key: RailControlHeightKey.self, value: rail.size.height)
                    }
                }
                .offset(y: -railLift)
                .opacity(railPresent ? railFade : 0)
                .allowsHitTesting(railPresent)
                .accessibilityHidden(!railPresent)
        }
    }

    private func sideBySideBody(
        playbackWidth: CGFloat,
        viewportHeight: CGFloat,
        transportHeight: CGFloat,
        railPresent: Bool,
        showsPlaybackBar: Bool
    ) -> some View {
        ZStack(alignment: .bottomTrailing) {
            map
            Group {
                if railPresent { controls }
                else { controls.hidden() }
            }
                .background {
                    GeometryReader { rail in
                        Color.clear.preference(key: RailControlHeightKey.self, value: rail.size.height)
                    }
                }
                .padding(.bottom, transportHeight)
                .padding(12)
                .opacity(railPresent ? 1 : 0)
                .allowsHitTesting(railPresent)
                .accessibilityHidden(!railPresent)
            playback
                .frame(width: playbackWidth)
                .frame(maxHeight: max(0, viewportHeight - 24), alignment: .bottom)
                .padding(12)
                .railAnimation(
                    RailMotion.spring, value: showsPlaybackBar,
                    reduceMotion: reduceMotion)
        }
    }

    private func hingedBody(width: CGFloat, bottomPadding: CGFloat) -> some View {
        playback
            .frame(width: width)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, bottomPadding)
    }
}
