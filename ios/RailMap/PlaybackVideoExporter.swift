import AVFoundation
import Observation
import RailCore
import UIKit

/// Records the native MapKit playback into an H.264 movie. Unlike the web
/// captureStream path, every frame is rendered directly into an AVAssetWriter
/// pixel buffer, with the journey caption and progress burned into the image.
@MainActor
@Observable
final class PlaybackVideoExporter {
    enum State: Equatable {
        case idle
        case recording
        case finishing
        /// `partial` is the run that was cancelled part-way. The file is
        /// still written and still offered — `video.readyPartial` in the web
        /// app, whose cancel "stop[s] the recorder — the partial file is still
        /// written rather than thrown away". Minutes of rendering deleted
        /// because the reader stopped a few seconds early is a worse answer
        /// than a shorter film.
        case finished(URL, partial: Bool = false)
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var progress = 0.0

    /// Frames actually written. A cancel with none of them has no film to
    /// keep, only a zero-length file that no player will open.
    @ObservationIgnored private var appendedFrames = 0

    @ObservationIgnored private var writer: AVAssetWriter?
    @ObservationIgnored private var input: AVAssetWriterInput?
    @ObservationIgnored private var adapter: AVAssetWriterInputPixelBufferAdaptor?
    @ObservationIgnored private weak var mapView: UIView?
    @ObservationIgnored private weak var playback: PlaybackController?
    @ObservationIgnored private var outputURL: URL?
    @ObservationIgnored private var startedAt: CFTimeInterval = 0
    @ObservationIgnored private var lastFrameAt: CFTimeInterval = -.infinity
    @ObservationIgnored private var outputSize = CGSize.zero
    /// The rectangle of the map being filmed, in the map view's own points.
    /// The whole view until a shape narrows it — see `VideoExportSettings`.
    @ObservationIgnored private var crop = CGRect.zero
    @ObservationIgnored private var frameInterval = 1.0 / 60.0

    // Frame-invariant drawing state.
    //
    // `append` runs on the main actor at display-link cadence, sharing that
    // actor with the playback renderer's own MapKit work — so anything built
    // inside it is built sixty times a second in competition with the map.
    // None of these change between frames, so none of them are.
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private let backdrop = UIColor.black.cgColor
    private let panelFill = UIColor.black.withAlphaComponent(0.72)
    private let trackFill = UIColor.white.withAlphaComponent(0.2)
    private let titleAttributes: [NSAttributedString.Key: Any] = {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        return [
            .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: UIColor.white,
            .paragraphStyle: paragraph,
        ]
    }()
    private let stationAttributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 12, weight: .medium),
        .foregroundColor: UIColor.white.withAlphaComponent(0.8),
    ]

    @ObservationIgnored private var contexts: [BitmapKey: CGContext] = [:]
    @ObservationIgnored private var layoutCache: CaptionLayout?
    /// The caption's two strings, already laid out. The title changes once per
    /// journey and the station name once per station, not once per frame.
    @ObservationIgnored private var titleCache: (text: String, line: NSAttributedString)?
    @ObservationIgnored private var stationCache: (text: String, line: NSAttributedString)?
    /// The journey's colour, which arrives as `#rrggbb` and would otherwise be
    /// re-parsed out of that string for every frame of the run.
    @ObservationIgnored private var colorCache: (hex: String, color: UIColor)?

    var isRecording: Bool { state == .recording || state == .finishing }

    func start(
        playback: PlaybackController,
        mapView: UIView,
        trains: [Train],
        rides: [RiddenRouteStore.DrawnRide],
        reducedMotion: Bool,
        settings: VideoExportSettings
    ) {
        cancel(clearPlayback: false)
        do {
            // The WHOLE map view, where the web app films only the map the
            // menu is not covering (`uncoveredRect`).
            //
            // That is not an oversight and it is not a shortcut: the web app
            // crops there because its playback camera PADS for the menu and
            // therefore centres the train in the uncovered part. This one does
            // not — `mapRendererViewSize` is the full view — so filming a
            // smaller rectangle would take the train off centre in the file.
            // The crop and the camera have to agree about where the middle is;
            // the day the camera learns about the panel, this should follow it.
            let plan = settings.plan(
                sourceSize: mapView.bounds.size,
                displayScale: mapView.window?.screen.scale ?? UIScreen.main.scale)
            let size = plan.size
            crop = plan.crop
            frameInterval = 1.0 / Double(VideoExportSettings.framesPerSecond)
            let url = FileManager.default.temporaryDirectory
                .appending(path: "RailMap-\(UUID().uuidString).mp4")
            let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
            let settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(size.width),
                AVVideoHeightKey: Int(size.height),
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: Int(plan.bitsPerSecond),
                    AVVideoExpectedSourceFrameRateKey: VideoExportSettings.framesPerSecond,
                    AVVideoMaxKeyFrameIntervalKey: VideoExportSettings.framesPerSecond * 2,
                ],
            ]
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = true
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            ]
            let adapter = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input, sourcePixelBufferAttributes: attributes)
            guard writer.canAdd(input) else { throw ExportError.cannotAddInput }
            writer.add(input)
            guard writer.startWriting() else {
                throw writer.error ?? ExportError.cannotStartWriter
            }
            writer.startSession(atSourceTime: .zero)

            self.writer = writer
            self.input = input
            self.adapter = adapter
            self.mapView = mapView
            self.playback = playback
            self.outputURL = url
            self.outputSize = size
            self.startedAt = CACurrentMediaTime()
            self.lastFrameAt = -.infinity
            self.appendedFrames = 0
            self.progress = 0
            resetFrameCaches()
            self.state = .recording

            playback.onFrame = { [weak self] snapshot in
                self?.append(snapshot)
            }
            playback.onFinish = { [weak self] in self?.finish() }
            // `autoBegin`: nobody is going to press play on a recording, so
            // the run begins once the opening overview has landed.
            guard playback.start(
                trains: trains, rides: rides, reducedMotion: reducedMotion,
                autoBegin: true)
            else { throw ExportError.noPlayableGeometry }
        } catch {
            fail(error)
        }
    }

    /// Stop early and keep what was filmed.
    ///
    /// The writer is FINISHED rather than cancelled: `cancelWriting` leaves no
    /// readable file, so a reader who stopped a five-minute export at four
    /// minutes was left with nothing at all. What has been appended so far is
    /// a valid film of the part that ran, and it is offered as one — marked
    /// partial so the offer does not claim to be the whole run.
    ///
    /// A cancel before the first frame lands has nothing to finish, and that
    /// path still discards the empty file rather than offering an unplayable
    /// one.
    func cancel(clearPlayback: Bool = true) {
        playback?.onFrame = nil
        playback?.onFinish = nil
        if clearPlayback { playback?.stop() }

        guard state == .recording, let writer, let input, let outputURL,
            writer.status == .writing, appendedFrames > 0
        else {
            writer?.cancelWriting()
            if let outputURL { try? FileManager.default.removeItem(at: outputURL) }
            resetWriter()
            state = .idle
            progress = 0
            return
        }
        state = .finishing
        input.markAsFinished()
        writer.finishWriting { [weak self] in
            Task { @MainActor [weak self] in
                self?.completeFinish(outputURL: outputURL, partial: true)
            }
        }
    }

    private func append(_ snapshot: PlaybackMapSnapshot) {
        guard state == .recording, let input, input.isReadyForMoreMediaData,
              let adapter, let pool = adapter.pixelBufferPool,
              let mapView else { return }
        let now = CACurrentMediaTime()
        guard now - lastFrameAt >= frameInterval else { return }
        lastFrameAt = now
        let interval = RailSignpost.jobs.begin("video.frame")
        defer { RailSignpost.jobs.end("video.frame", interval) }
        var optionalBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &optionalBuffer) == kCVReturnSuccess,
              let buffer = optionalBuffer else { return }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = context(for: buffer) else { return }

        // The crop FILLS the frame rather than being letterboxed into it: it
        // was chosen to have the frame's shape precisely so there are no bars.
        // A `native` shape makes the crop the whole view and this is a plain
        // scale, which is what the old code did for every shape.
        let filmed = crop.isEmpty ? CGRect(origin: .zero, size: mapView.bounds.size) : crop
        let layout = captionLayout(filmed: filmed)
        context.setFillColor(backdrop)
        context.fill(CGRect(origin: .zero, size: outputSize))
        context.saveGState()
        // Flip into UIKit's orientation, then shift so the crop's top-left
        // corner — not the view's — lands on the frame's.
        context.translateBy(
            x: -filmed.minX * layout.scale,
            y: outputSize.height + filmed.minY * layout.scale)
        context.scaleBy(x: layout.scale, y: -layout.scale)
        mapView.layer.render(in: context)
        drawCaption(snapshot, in: context, layout: layout)
        context.restoreGState()

        let elapsed = max(0, now - startedAt)
        adapter.append(buffer, withPresentationTime: CMTime(seconds: elapsed, preferredTimescale: 600))
        appendedFrames += 1
        publish(progress: snapshot.frame.progress)
    }

    /// The context that draws into `buffer`, built once per buffer rather than
    /// once per frame.
    ///
    /// The adaptor's pool hands the same handful of buffers back in rotation,
    /// so the context built for one of them is the context every later frame
    /// filmed into it needs. Reuse is keyed on the address and the row layout,
    /// and a context is only ever handed back for a LOCKED buffer reporting
    /// that exact pair — so it can write nowhere but into the frame being
    /// filmed right now, even if the pool has since released and re-made the
    /// buffer that address belongs to.
    private func context(for buffer: CVPixelBuffer) -> CGContext? {
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let key = BitmapKey(
            base: UInt(bitPattern: base),
            width: CVPixelBufferGetWidth(buffer),
            height: CVPixelBufferGetHeight(buffer),
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer))
        if let cached = contexts[key] { return cached }
        guard let context = CGContext(
            data: base, width: key.width, height: key.height, bitsPerComponent: 8,
            bytesPerRow: key.bytesPerRow, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        // More entries than a pixel buffer pool holds means the addresses are
        // not being recycled and every one of these is a context for a buffer
        // that no longer exists, so the cache starts again rather than growing
        // for the length of a film.
        if contexts.count >= 8 { contexts.removeAll() }
        contexts[key] = context
        return context
    }

    private func drawCaption(
        _ snapshot: PlaybackMapSnapshot, in context: CGContext, layout: CaptionLayout
    ) {
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }
        panelFill.setFill()
        layout.panel.fill()

        titleLine(playback?.title ?? "").draw(in: layout.titleRect)
        let station = playback?.stationName ?? ""
        if !station.isEmpty {
            stationLine(station).draw(at: layout.stationOrigin)
        }
        trackFill.setFill()
        layout.trackPath.fill()
        let fill = CGRect(
            x: layout.track.minX, y: layout.track.minY,
            width: layout.track.width * CGFloat(min(max(snapshot.frame.progress, 0), 1)),
            height: layout.track.height)
        trackColor(hex: snapshot.path.color).setFill()
        UIBezierPath(roundedRect: fill, cornerRadius: 2).fill()
    }

    /// Where the caption sits and the furniture that never moves inside it.
    ///
    /// Rebuilt only when the filmed rectangle changes, which for the length of
    /// one export it does not.
    private func captionLayout(filmed: CGRect) -> CaptionLayout {
        if let layoutCache, layoutCache.filmed == filmed { return layoutCache }
        // Placed against the FILMED rectangle, not the whole view: a square
        // crop of a phone in portrait discards a third of the height at the
        // bottom, and a caption laid out against the view would be cropped
        // straight out of the picture it is captioning.
        let margin: CGFloat = 18
        let height: CGFloat = 84
        let box = CGRect(
            x: filmed.minX + margin, y: filmed.maxY - height - margin,
            width: max(filmed.width - margin * 2, 1), height: height)
        let track = CGRect(x: box.minX + 14, y: box.maxY - 13, width: box.width - 28, height: 4)
        let layout = CaptionLayout(
            filmed: filmed,
            scale: outputSize.width / max(filmed.width, 1),
            panel: UIBezierPath(roundedRect: box, cornerRadius: 16),
            titleRect: box.insetBy(dx: 14, dy: 11),
            stationOrigin: CGPoint(x: box.minX + 14, y: box.minY + 36),
            track: track,
            trackPath: UIBezierPath(roundedRect: track, cornerRadius: 2))
        layoutCache = layout
        return layout
    }

    private func titleLine(_ text: String) -> NSAttributedString {
        if let titleCache, titleCache.text == text { return titleCache.line }
        let line = NSAttributedString(string: text, attributes: titleAttributes)
        titleCache = (text, line)
        return line
    }

    private func stationLine(_ text: String) -> NSAttributedString {
        if let stationCache, stationCache.text == text { return stationCache.line }
        let line = NSAttributedString(string: text, attributes: stationAttributes)
        stationCache = (text, line)
        return line
    }

    private func trackColor(hex: String) -> UIColor {
        if let colorCache, colorCache.hex == hex { return colorCache.color }
        let color = UIColor(railHex: hex) ?? .systemBlue
        colorCache = (hex, color)
        return color
    }

    /// Published when the number moves rather than on every frame: an
    /// `@Observable` write is a promise to redraw whoever reads it, and at
    /// sixty a second that is a SwiftUI invalidation competing with the render
    /// this method just did — for a bar that cannot show a thousandth.
    private func publish(progress value: Double) {
        guard abs(value - progress) >= 0.001 else { return }
        progress = value
    }

    private func finish() {
        guard state == .recording, let writer, let input, let outputURL else { return }
        state = .finishing
        playback?.onFrame = nil
        playback?.onFinish = nil
        input.markAsFinished()
        writer.finishWriting { [weak self] in
            Task { @MainActor [weak self] in self?.completeFinish(outputURL: outputURL) }
        }
    }

    private func completeFinish(outputURL: URL, partial: Bool = false) {
        guard let writer else { return }
        if writer.status == .completed {
            resetWriter()
            progress = 1
            state = .finished(outputURL, partial: partial)
        } else {
            // A partial film that will not close is not a failure the reader
            // caused — they asked to stop — but the file is unusable either
            // way, so it goes rather than being offered.
            try? FileManager.default.removeItem(at: outputURL)
            fail(writer.error ?? ExportError.cannotFinishWriter)
        }
    }

    private func fail(_ error: Error) {
        writer?.cancelWriting()
        playback?.onFrame = nil
        playback?.onFinish = nil
        resetWriter()
        state = .failed(error.localizedDescription)
    }

    private func resetWriter() {
        writer = nil
        input = nil
        adapter = nil
        mapView = nil
        playback = nil
        outputURL = nil
        resetFrameCaches()
    }

    /// Everything held for one film's frames.
    ///
    /// Cleared with the writer because every entry belongs to that run: the
    /// contexts point into a pixel buffer pool that goes with the adaptor, and
    /// the layout is measured against a rectangle the next run may not film.
    private func resetFrameCaches() {
        contexts.removeAll()
        layoutCache = nil
        titleCache = nil
        stationCache = nil
        colorCache = nil
    }

    /// A bitmap context is bound to the address and row layout it writes into,
    /// so it may only be reused for a buffer reporting both.
    private struct BitmapKey: Hashable {
        let base: UInt
        let width: Int
        let height: Int
        let bytesPerRow: Int
    }

    private struct CaptionLayout {
        let filmed: CGRect
        let scale: CGFloat
        let panel: UIBezierPath
        let titleRect: CGRect
        let stationOrigin: CGPoint
        let track: CGRect
        let trackPath: UIBezierPath
    }

    private enum ExportError: LocalizedError {
        case cannotAddInput
        case cannotStartWriter
        case cannotFinishWriter
        case noPlayableGeometry
        var errorDescription: String? {
            switch self {
            case .cannotAddInput: "The video encoder could not accept its input."
            case .cannotStartWriter: "The video encoder could not start."
            case .cannotFinishWriter: "The video encoder could not finish the movie."
            case .noPlayableGeometry: "No routed journey is available to record."
            }
        }
    }
}
