#!/usr/bin/env python3
"""Compile unchanged production exporter lifecycle bodies against host doubles.

Usage: python3 ios/tools/verify-playback-video-lifecycle.py
No simulator, package build, AVFoundation encoding, or Xcode command is needed.
The doubles model writer completion explicitly; these checks cover ownership and
cleanup, not frame rendering or the validity of an encoded movie.
"""
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / "ios/RailMap/PlaybackVideoExporter.swift").read_text()


def extract(marker):
    """Keep each selected declaration and its body byte-for-byte unchanged."""
    start = source.index(marker)
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        if source[end] == "{":
            depth += 1
        elif source[end] == "}":
            depth -= 1
        end += 1
    return source[start:end]


collaborators = r'''
import Foundation
import CoreGraphics
@MainActor func CACurrentMediaTime() -> Double { 100 }
struct Train {}
enum RiddenRouteStore { struct DrawnRide {} }
struct PlaybackMapSnapshot {}
@MainActor final class PlaybackController {
    var restoreSelectedTrainID: String? = "selected"
    var onFrame: ((PlaybackMapSnapshot) -> Void)?
    var onFinish: (() -> Void)?
    var canStart = true
    var stops = 0
    func start(trains: [Train], rides: [RiddenRouteStore.DrawnRide],
               reducedMotion: Bool, restoringSelection: String?, autoBegin: Bool) -> Bool {
        canStart
    }
    func stop() { stops += 1 }
}
@MainActor final class UIScreen {
    static let main = UIScreen()
    let scale: CGFloat = 2
}
@MainActor final class UIWindow { let screen = UIScreen.main }
@MainActor final class UIView {
    var bounds = CGRect(x: 0, y: 0, width: 400, height: 800)
    var window: UIWindow? = UIWindow()
}
struct VideoExportSettings {
    static let framesPerSecond = 30
    struct Plan { let size: CGSize; let crop: CGRect; let bitsPerSecond = 1_000_000 }
    func plan(sourceRect: CGRect, displayScale: CGFloat) -> Plan {
        Plan(size: sourceRect.size, crop: sourceRect)
    }
}
let AVVideoCodecKey = "codec", AVVideoWidthKey = "width", AVVideoHeightKey = "height"
let AVVideoCompressionPropertiesKey = "compression", AVVideoAverageBitRateKey = "bitrate"
let AVVideoExpectedSourceFrameRateKey = "fps", AVVideoMaxKeyFrameIntervalKey = "keyframe"
let kCVPixelBufferPixelFormatTypeKey = "format", kCVPixelBufferWidthKey = "width"
let kCVPixelBufferHeightKey = "height", kCVPixelBufferIOSurfacePropertiesKey = "surface"
let kCVPixelFormatType_32BGRA = 1
enum AVVideoCodecType { static let h264 = "h264" }
enum FileType { case mp4 }
enum MediaType { case video }
struct CMTime { static let zero = CMTime() }
enum TestError: LocalizedError {
    case initialization, encoding
    var errorDescription: String? { "test encoder failure" }
}
@MainActor final class AVAssetWriterInput {
    var expectsMediaDataInRealTime = false
    var finishes = 0
    init(mediaType: MediaType, outputSettings: [String: Any]) {}
    func markAsFinished() { finishes += 1 }
}
@MainActor final class AVAssetWriterInputPixelBufferAdaptor {
    init(assetWriterInput: AVAssetWriterInput, sourcePixelBufferAttributes: [String: Any]) {}
}
@MainActor final class AVAssetWriter {
    enum Status { case unknown, writing, completed, failed, cancelled }
    static var rejectInitialization = false
    var status = Status.unknown
    var error: Error?
    var cancels = 0
    var finishRequests = 0
    var completion: (@Sendable () -> Void)?
    let url: URL
    init(outputURL: URL, fileType: FileType) throws {
        if Self.rejectInitialization { throw TestError.initialization }
        url = outputURL
        try Data("host movie placeholder".utf8).write(to: outputURL)
    }
    func canAdd(_ input: AVAssetWriterInput) -> Bool { true }
    func add(_ input: AVAssetWriterInput) {}
    func startWriting() -> Bool { status = .writing; return true }
    func startSession(atSourceTime: CMTime) {}
    func cancelWriting() { cancels += 1; status = .cancelled }
    func finishWriting(completionHandler: @escaping @Sendable () -> Void) {
        finishRequests += 1
        completion = completionHandler
    }
    func resolve(success: Bool = true) {
        status = success ? .completed : .failed
        if !success { error = TestError.encoding }
        let callback = completion
        completion = nil
        callback?()
    }
}
@MainActor final class PlaybackVideoExporter {
    var state: State = .idle
    var progress = 0.0
    var appendedFrames = 0
    var writer: AVAssetWriter?
    var retiringWriters: [URL: AVAssetWriter] = [:]
    var input: AVAssetWriterInput?
    var adapter: AVAssetWriterInputPixelBufferAdaptor?
    weak var mapView: UIView?
    weak var playback: PlaybackController?
    var outputURL: URL?
    var startedAt = 0.0
    var latestSnapshot: PlaybackMapSnapshot?
    var outputSize = CGSize.zero
    var crop = CGRect.zero
    var clockRunning = false
    var cacheResets = 0
    func startCaptureClock() { clockRunning = true }
    func stopCaptureClock() { clockRunning = false }
    func resetFrameCaches() { cacheResets += 1 }
    func naturalFinish() { finish() }
'''

checks = r'''
}
@main struct Checks {
    @MainActor static func main() async throws {
        var count = 0
        var files: [URL] = []
        defer { for file in files { try? FileManager.default.removeItem(at: file) } }
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            count += 1
        }
        let view = UIView()
        let playback = PlaybackController()
        let exporter = PlaybackVideoExporter()
        func start(frames: Int = 0) -> AVAssetWriter {
            exporter.start(playback: playback, mapView: view, filming: .zero,
                           trains: [], rides: [], reducedMotion: true,
                           settings: VideoExportSettings())
            precondition(exporter.state == .recording)
            exporter.appendedFrames = frames
            let writer = exporter.writer!
            files.append(writer.url)
            return writer
        }
        func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
        func drain() async throws { try await Task.sleep(for: .milliseconds(10)) }
        func callbacksCleared() -> Bool { playback.onFrame == nil && playback.onFinish == nil }
        func resourcesCleared() -> Bool {
            exporter.writer == nil && exporter.input == nil && exporter.adapter == nil
                && exporter.mapView == nil && exporter.playback == nil && exporter.outputURL == nil
                && exporter.latestSnapshot == nil && !exporter.clockRunning
        }

        check(!exporter.hasPendingResult, "idle has no result")
        let empty = start()
        exporter.latestSnapshot = PlaybackMapSnapshot()
        check(!exporter.hasPendingResult, "recording has no result")
        playback.onFinish?()
        if case .failed = exporter.state {} else { preconditionFailure("empty finish must fail") }
        check(empty.cancels == 1 && empty.finishRequests == 0 && !exists(empty.url),
              "zero frames never offers an unplayable file")
        check(resourcesCleared() && callbacksCleared() && playback.stops == 1,
              "zero frame failure clears resources and playback callbacks")
        check(exporter.hasPendingResult, "failure remains dismissible")
        exporter.dismissResult()
        check(exporter.state == .idle && exporter.progress == 0, "failure dismissal resets offer")

        let abandoned = start()
        exporter.cancel()
        check(exporter.state == .idle && abandoned.cancels == 1 && !exists(abandoned.url),
              "zero frame cancel discards empty recording")
        check(resourcesCleared() && callbacksCleared(), "empty cancel clears resources")

        let partial = start(frames: 4)
        let partialInput = exporter.input!
        exporter.progress = 0.4
        exporter.cancel()
        check(exporter.state == .finishing && partial.finishRequests == 1
              && partialInput.finishes == 1 && partial.cancels == 0,
              "partial cancel closes writer exactly once")
        check(callbacksCleared() && exporter.playback == nil && !exporter.clockRunning,
              "partial cancel releases callback owner and capture clock")
        exporter.dismissResult()
        check(exporter.state == .finishing && exporter.hasPendingResult,
              "finishing offer cannot be dismissed")
        var externalFrames = 0
        playback.onFrame = { _ in externalFrames += 1 }
        playback.onFinish = {}
        let stops = playback.stops
        exporter.cancel()
        playback.onFrame?(PlaybackMapSnapshot())
        check(externalFrames == 1 && playback.onFinish != nil && playback.stops == stops
              && partial.finishRequests == 1 && partial.cancels == 0,
              "repeated finishing cancel leaves newly installed callbacks untouched")
        partial.resolve()
        try await drain()
        check(exporter.state == .finished(partial.url, partial: true) && exporter.progress == 0.4,
              "partial result retains captured progress")
        check(resourcesCleared() && exists(partial.url), "finished partial retains file only")
        exporter.cancel()
        check(exporter.state == .finished(partial.url, partial: true), "cancel retains finished offer")
        exporter.dismissResult()
        check(exporter.state == .idle && exporter.progress == 0 && exists(partial.url),
              "dismissal retains file for an existing share operation")

        let natural = start(frames: 2)
        playback.onFinish?()
        check(exporter.state == .finishing && callbacksCleared() && exporter.playback == nil,
              "natural finish detaches callbacks")
        natural.resolve()
        try await drain()
        check(exporter.state == .finished(natural.url) && exporter.progress == 1
              && resourcesCleared() && exists(natural.url), "natural completion offers full film")

        let old = start(frames: 2)
        exporter.naturalFinish()
        let replacement = start(frames: 1)
        check(exporter.retiringWriters[old.url] === old && old.cancels == 0,
              "replacement retains old finishing writer")
        old.resolve()
        try await drain()
        check(exporter.state == .recording && exporter.writer === replacement
              && exporter.outputURL == replacement.url && exporter.clockRunning
              && playback.onFrame != nil && playback.onFinish != nil,
              "stale completion cannot reset new writer or callbacks")
        check(exporter.retiringWriters.isEmpty && !exists(old.url) && exists(replacement.url),
              "stale completion releases old writer and deletes only its file")

        exporter.cancel(clearPlayback: false)
        check(callbacksCleared(), "replacement cancellation clears callbacks without stopping playback")
        AVAssetWriter.rejectInitialization = true
        exporter.start(playback: playback, mapView: view, filming: .zero,
                       trains: [], rides: [], reducedMotion: true, settings: VideoExportSettings())
        AVAssetWriter.rejectInitialization = false
        if case .failed = exporter.state {} else { preconditionFailure("replacement init must fail") }
        check(replacement.cancels == 0 && exporter.retiringWriters[replacement.url] === replacement
              && exists(replacement.url) && resourcesCleared(),
              "failed replacement initialization preserves retiring writer until completion")
        let failureState = exporter.state
        replacement.resolve()
        try await drain()
        check(exporter.state == failureState && exporter.retiringWriters.isEmpty
              && !exists(replacement.url), "retiring completion preserves replacement failure")
        exporter.cancel()
        check(exporter.state == failureState && exporter.hasPendingResult, "cancel retains failure offer")

        let broken = start(frames: 1)
        exporter.naturalFinish()
        broken.resolve(success: false)
        try await drain()
        if case .failed = exporter.state {} else { preconditionFailure("writer failure must fail") }
        check(!exists(broken.url) && resourcesCleared() && callbacksCleared(),
              "failed completion removes unusable file and releases resources")

        playback.canStart = false
        exporter.start(playback: playback, mapView: view, filming: .zero,
                       trains: [], rides: [], reducedMotion: true, settings: VideoExportSettings())
        if case .failed = exporter.state {} else { preconditionFailure("playback failure must fail") }
        check(resourcesCleared() && callbacksCleared(), "playback start failure clears installed callbacks")
        print("PASS \(count) production playback video lifecycle checks")
    }
}
'''

markers = ["enum State: Equatable", "var hasPendingResult: Bool", "func dismissResult()",
           "func start(", "func cancel(clearPlayback:", "private func finish()",
           "private func completeFinish(", "private func fail(", "private func resetWriter()",
           "private enum ExportError:"]
production = "\n\n".join(extract(marker) for marker in markers)
compiler = Path("/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc")
sdk = Path("/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk")
if not compiler.is_file() or not sdk.is_dir():
    raise SystemExit("Host Swift compiler or MacOSX SDK unavailable; lifecycle checks not run")
with tempfile.TemporaryDirectory(prefix="jtm-playback-video-lifecycle-") as temporary:
    folder = Path(temporary)
    harness = folder / "Checks.swift"
    harness.write_text(collaborators + production + checks)
    executable = folder / "checks"
    environment = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(folder / "ModuleCache"))
    subprocess.run([str(compiler), "-swift-version", "6", "-parse-as-library", "-sdk", str(sdk),
                    "-module-cache-path", str(folder / "ModuleCache"), str(harness),
                    "-o", str(executable)], check=True, env=environment)
    subprocess.run([str(executable)], check=True)
