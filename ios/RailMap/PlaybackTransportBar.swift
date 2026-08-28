import RailCore
import SwiftUI

/// §5.6's transport, as a view of its own rather than as a computed property
/// of the workspace.
///
/// ## Why it moved out of `RailWorkspaceView`
///
/// It was eleven computed properties on that one struct, which meant every
/// value it read — `playback.progress`, `playback.stationName`,
/// `playback.speed`, `videoExporter.state` — was read *inside
/// `RailWorkspaceView.body`*. `@Observable` tracks reads against the body that
/// made them, so the playhead advancing invalidated the entire workspace: the
/// map's inputs, the journey list, the derived summaries, the sheet's whole
/// content. A run was therefore a full recomputation of the app's largest view
/// twenty times a second.
///
/// Reading the same values inside this struct's own body confines the
/// invalidation to this struct. Nothing about what is drawn changes; what
/// changes is who has to be redrawn when it does.
///
/// The three things it cannot own — stopping a run, opening the export
/// options, and what "play" currently means — arrive as closures, because each
/// of them is a decision about state that lives above the transport.
struct PlaybackTransportBar: View {
    @Bindable var playback: PlaybackController
    var videoExporter: PlaybackVideoExporter
    /// Stop the run AND put back whatever selection it interrupted — the
    /// second half is the workspace's, which is why this is handed in.
    var onStop: () -> Void
    /// Open §5.6's export options, having first measured how long the film
    /// would be. The queue it would film is the workspace's answer, not the
    /// transport's.
    var onRequestVideoOptions: () -> Void

    @Environment(AppLocalization.self) private var localization
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 9) {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityLayout
            } else {
                standardLayout
            }
        }
        .buttonStyle(RailPressStyle(dims: false))
        .padding(12)
        // The transport is a control floating over the map, so it takes the
        // same surface every other floating control does. It used to spell
        // `.regularMaterial` here, which made it the ONE piece of chrome that
        // stayed a material while the rest became Liquid Glass on iOS 26 —
        // and, more seriously, the one that answered neither Reduce
        // Transparency nor Increase Contrast, because both of those are
        // handled inside `RailGlassSurface` and nowhere else.
        //
        // `interactive` is deliberately off: the buttons inside carry their
        // own press feedback, and a capsule that deforms wherever it is
        // touched would compete with them.
        .railGlass(in: RoundedRectangle(
            cornerRadius: RailStyle.chromeCornerRadius, style: .continuous))
        // Kept, and it is not decoration: §6.5 uses a heavy shadow for the one
        // job of separating a floating surface from the map.
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .frame(maxWidth: 540)
        .accessibilityElement(children: .contain)
    }

    /// The compact transport used at ordinary text sizes.
    private var standardLayout: some View {
        VStack(spacing: 9) {
            HStack(spacing: 10) {
                transportControls
                identity(titleLines: 1, stationLines: 1)
                Spacer(minLength: 4)
                stopButton
            }

            progressBar

            HStack(spacing: 10) {
                queueLabel
                focusToggle
                Spacer()
                speedSlider.frame(maxWidth: 120)
                speedReadout
                    .frame(minWidth: 34, alignment: .trailing)
                    .fixedSize(horizontal: true, vertical: false)
                videoControl
            }
        }
    }

    /// Accessibility text gets a content-led composition instead of a scaled
    /// copy of the two dense horizontal rows. Text may grow; transport chrome
    /// keeps a familiar size and each group gets the full available width.
    private var accessibilityLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            identity(titleLines: 3, stationLines: 2)

            HStack(spacing: 8) {
                transportControls
                stopButton
                Spacer(minLength: 0)
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)

            progressBar

            HStack(spacing: 8) {
                queueLabel
                focusToggle
                videoControl
                Spacer(minLength: 0)
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)

            HStack(spacing: 10) {
                speedSlider
                speedReadout
                    .fixedSize(horizontal: true, vertical: false)
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        // In map layouts the vertical control rail shares this overlay. Keep
        // accessibility-sized text and controls out of its resting footprint;
        // the glass surfaces may overlap visually, but their hit targets must
        // never overlap.
        .padding(
            .trailing,
            MapControlBar.side + (2 * MapControlBar.interactionBleed) + 12)
    }

    private var transportControls: some View {
        HStack(spacing: 10) {
            Button { playback.previous() } label: {
                Image(systemName: "backward.end.fill")
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .disabled(!playback.canGoPrevious)
            .accessibilityLabel(
                Text(localization.journeyText("play.prev", fallback: "Previous train")))

            Button { playback.togglePause() } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .contentTransition(.symbolEffect(.replace))
                    .animation(RailMotion.replace, value: playback.isPlaying)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .disabled(playback.phase == .ended)
            .accessibilityLabel(
                Text(localization.journeyText(
                    playback.isPlaying ? "play.pause" : "play.resume",
                    fallback: playback.isPlaying ? "Pause" : "Resume")))

            Button { playback.next() } label: {
                Image(systemName: "forward.end.fill")
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .disabled(!playback.canGoNext)
            .accessibilityLabel(
                Text(localization.journeyText("play.next", fallback: "Next train")))
        }
    }

    private func identity(titleLines: Int, stationLines: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(playback.title)
                .font(.caption.weight(.semibold))
                .lineLimit(titleLines)
                .fixedSize(horizontal: false, vertical: true)
            if !playback.stationName.isEmpty {
                Text(playback.stationName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(stationLines)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var stopButton: some View {
        Button { onStop() } label: {
            Image(systemName: "xmark.circle.fill")
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .accessibilityLabel(localization.countryText("play.stop", fallback: "Stop playback"))
        .accessibilityIdentifier("playbackStopButton")
    }

    private var progressBar: some View {
        ProgressView(value: playback.progress)
            .tint(.accentColor)
    }

    private var queueLabel: some View {
        Label(
            "\(playback.queueIndex + 1)/\(max(playback.queueCount, 1))", systemImage: "tram"
        )
        .font(.caption2.monospacedDigit())
        .accessibilityLabel(
            localization.journeyText("ios.journey.playbackQueue", fallback: "Journey"))
        .accessibilityValue(
            Text("\(playback.queueIndex + 1)/\(max(playback.queueCount, 1))"))
    }

    private var focusToggle: some View {
        Toggle(isOn: $playback.autoFocus) {
            Label(
                localization.countryText("play.follow", fallback: "Follow"),
                systemImage: "scope")
        }
        .labelsHidden()
        .toggleStyle(.button)
        .accessibilityLabel(
            localization.countryText("play.follow", fallback: "Follow the train"))
    }

    private var speedSlider: some View {
        Slider(
            value: Binding(get: { playback.speed }, set: { playback.setSpeed($0) }),
            in: Playback.Tuning.speedMin...Playback.Tuning.speedMax,
            step: Playback.Tuning.speedStep
        )
        .accessibilityLabel(localization.countryText("play.speed", fallback: "Playback speed"))
    }

    private var speedReadout: some View {
        Text("\(playback.speed.formatted(.number.precision(.fractionLength(2))))×")
            .font(.caption2.monospacedDigit())
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var videoControl: some View {
        switch videoExporter.state {
        case .recording:
            Button { videoExporter.cancel() } label: {
                Image(systemName: "record.circle.fill").foregroundStyle(.red)
            }
            .accessibilityLabel(
                localization.journeyText("video.cancel", fallback: "Cancel video export"))
        case .finishing:
            ProgressView().controlSize(.small)
                .accessibilityLabel(
                    localization.journeyText("video.finishing", fallback: "Finishing video"))
        case .finished(let url, let partial):
            ShareLink(item: url) {
                Image(systemName: "square.and.arrow.up.fill")
                    // A cancelled run's film is offered like any other, and
                    // says so: `video.readyPartial` rather than `video.ready`.
                    .foregroundStyle(partial ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
            }
            .accessibilityLabel(
                localization.journeyText(
                    partial ? "video.readyPartial" : "video.share",
                    fallback: partial ? "Share partial video" : "Share video"))
        case .idle, .failed:
            Button { onRequestVideoOptions() } label: {
                Image(systemName: "video.badge.plus")
            }
            .accessibilityLabel(
                localization.countryText("video.export", fallback: "Export playback video"))
        }
    }
}
