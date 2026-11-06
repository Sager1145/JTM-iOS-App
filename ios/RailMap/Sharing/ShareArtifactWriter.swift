import Foundation
import UIKit

/// Names, writes and retires every file the app hands to the share sheet.
///
/// There used to be three: the statistics composer's `SharePNGWriter`, which
/// retired its old files; the journey poster, which wrote
/// `rail-journey-<UUID>.png` on every render (each kind switch, language
/// change or retry) and never removed one; and the video exporter, which
/// cleaned up after itself within a session but not files a previous launch
/// left behind (audit A19). This is the one place a share file is named, so
/// it is also the one place they are cleaned up:
///
/// - files of a kind from an earlier launch are removed on the next write of
///   that kind;
/// - an image superseded by a newer render of the same kind is removed when
///   the newer one lands — the preview keeps its `UIImage`, and the file only
///   exists for the share sheet, which is only offered the newest.
///
/// Video is named here but written by `AVAssetWriter`; the exporter keeps its
/// own rules for retiring a film in flight.
enum ShareArtifactWriter {
    enum Kind: String, CaseIterable, Sendable {
        case journey = "rail-journey"
        case statistics = "rail-statistics"
        case video = "RailMap"

        var fileExtension: String { self == .video ? "mp4" : "png" }
    }

    private static let sessionStarted = Date()
    @MainActor private static var latest: [Kind: URL] = [:]

    /// A fresh temporary URL for a file of `kind`. Retires that kind's files
    /// from earlier launches as a side effect.
    static func reserveURL(for kind: Kind) -> URL {
        retireEarlierSessions(of: kind)
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("\(kind.rawValue)-\(UUID().uuidString).\(kind.fileExtension)")
    }

    /// Encode and write `image` off the main actor.
    ///
    /// `destination` is for the DEBUG export hooks that write to a known
    /// path; such a file is never retired here.
    @MainActor
    static func writePNG(_ image: UIImage, kind: Kind, to destination: URL? = nil) async -> URL? {
        let url = destination ?? reserveURL(for: kind)
        let superseded = destination == nil ? latest[kind] : nil
        nonisolated(unsafe) let image = image
        let written = await Task.detached(priority: .userInitiated) { () -> Bool in
            guard let data = image.pngData() else { return false }
            do {
                if destination != nil {
                    try FileManager.default.createDirectory(
                        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                }
                try data.write(to: url, options: .atomic)
                return true
            } catch { return false }
        }.value
        guard written else { return nil }
        if destination == nil {
            if let superseded, superseded != url {
                try? FileManager.default.removeItem(at: superseded)
            }
            latest[kind] = url
        }
        return url
    }

    private static func retireEarlierSessions(of kind: Kind) {
        let cutoff = sessionStarted
        let manager = FileManager.default
        guard let files = try? manager.contentsOfDirectory(
            at: manager.temporaryDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for file in files where file.lastPathComponent.hasPrefix(kind.rawValue + "-")
            && file.pathExtension == kind.fileExtension {
            guard let date = try? file.resourceValues(
                forKeys: [.contentModificationDateKey]).contentModificationDate,
                  date < cutoff else { continue }
            try? manager.removeItem(at: file)
        }
    }
}
