// Rasterize the app icon SVGs into the asset catalog, because Xcode cannot.
//
// The icon's source of truth is `ios/Resources/app-icon/*.svg`, lifted from
// the design deck that chose it. An `.appiconset` will only take PNG, so this
// writes one 1024×1024 PNG per SVG into
// `ios/RailMap/Assets.xcassets/AppIcon.appiconset` under the names that
// catalog's `Contents.json` already lists.
//
//   swift ios/tools/render-app-icon.swift            # write the PNGs
//   swift ios/tools/render-app-icon.swift --check    # fail if they are stale
//
// The renderer is WebKit, for the same reason `rasterize-badge-svgs.swift`
// uses it: it is the one SVG implementation on this machine that is also the
// one the artwork was drawn against, so what lands in the catalog is what the
// designer saw. That file's renderer is not shared with this one — both are
// `swift`-the-interpreter scripts, and script mode takes exactly one input
// file, so sharing would mean a build product where today there are two files
// anyone can run.
//
// Two things here that the badge rasterizer does not do, both because an app
// icon is not a badge:
//
//   * The output is opaque, with no alpha channel at all. App Store validation
//     rejects an icon that carries one, even when every pixel in it is opaque.
//   * The size is fixed at 1024, not derived from the artwork. That is the one
//     size an iOS `.appiconset` wants; the system scales the rest.
//
// macOS-only, run by hand when the artwork changes, and its output is
// committed. Nothing in the app or the build depends on it.

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import WebKit

// MARK: - where the files are

let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // tools
    .deletingLastPathComponent()  // ios
    .deletingLastPathComponent()  // repo
let sourceRoot = repoRoot.appending(path: "ios/Resources/app-icon")
let outputRoot = repoRoot.appending(
    path: "ios/RailMap/Assets.xcassets/AppIcon.appiconset")

/// The appearances the catalog declares, and the name each one's PNG has to
/// land under. Adding an appearance means adding it here *and* in
/// `AppIcon.appiconset/Contents.json`; the run below asserts the sources exist
/// but cannot tell whether the catalog is asking for them.
let variants = [
    (source: "icon-light.svg", output: "icon-light-1024.png"),
    (source: "icon-dark.svg", output: "icon-dark-1024.png"),
]

/// 1024 × 1024: the single size an iOS app icon set takes.
let side = 1024

let checkOnly = CommandLine.arguments.contains("--check")

// MARK: - the renderer

/// The markup, wrapped so the viewport is exactly the icon and nothing else.
///
/// The page ground is opaque black rather than transparent. Every one of these
/// SVGs paints a full-bleed rect of its own, so nothing of it is ever seen —
/// but an anti-aliased edge against a transparent ground blends toward
/// transparent, and the flatten below would then read those pixels as black.
func page(forSVG markup: String) -> String {
    """
    <!doctype html><html><head><meta charset="utf-8"><style>
    html, body { margin: 0; padding: 0; background: #000; overflow: hidden; }
    svg { display: block; width: 100vw; height: 100vh; }
    </style></head><body>\(markup)</body></html>
    """
}

/// One offscreen WebKit view, reused for every variant.
///
/// It lives in a window because a `WKWebView` with no window does not
/// necessarily have a layer to snapshot; the window is parked off every screen
/// and the process runs as an accessory, so nothing appears and nothing steals
/// focus. The snapshot comes back at whatever backing scale the host happens
/// to have, which is why it is redrawn into a bitmap of exactly 1024 × 1024 —
/// the committed PNGs must not differ between a Retina machine and a build
/// server.
final class Renderer: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private let window: NSWindow
    private var onFinish: ((Result<Void, Error>) -> Void)?

    override init() {
        let box = CGRect(x: 0, y: 0, width: side, height: side)
        webView = WKWebView(frame: box, configuration: WKWebViewConfiguration())
        window = NSWindow(
            contentRect: box.offsetBy(dx: -10_000, dy: -10_000),
            styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        window.contentView = webView
        window.orderBack(nil)
        webView.navigationDelegate = self
    }

    func render(svg: URL, completion: @escaping (Result<CGImage, Error>) -> Void) {
        let markup: String
        do { markup = try String(contentsOf: svg, encoding: .utf8) }
        catch { return completion(.failure(error)) }

        onFinish = { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success:
                let configuration = WKSnapshotConfiguration()
                configuration.rect = CGRect(x: 0, y: 0, width: side, height: side)
                self.webView.takeSnapshot(with: configuration) { image, error in
                    if let error { return completion(.failure(error)) }
                    guard let image, let bitmap = Self.flatten(image) else {
                        return completion(.failure(Failure("snapshot produced no bitmap")))
                    }
                    completion(.success(bitmap))
                }
            }
        }
        webView.loadHTMLString(page(forSVG: markup), baseURL: nil)
    }

    /// The snapshot, resampled onto an opaque context of exactly 1024 × 1024.
    ///
    /// `noneSkipLast` is the point of this: the context has no alpha channel,
    /// so neither does the PNG, so App Store validation has nothing to object
    /// to. It also means anything the artwork left translucent is composited
    /// against the black fill below rather than carried through.
    private static func flatten(_ image: NSImage) -> CGImage? {
        var rect = CGRect(x: 0, y: 0, width: side, height: side)
        guard let source = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              let context = CGContext(
                data: nil, width: side, height: side,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(rect)
        context.draw(source, in: rect)
        return context.makeImage()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // One turn of the run loop after `didFinish`: the document is parsed,
        // but a snapshot taken in the same turn can catch the frame before the
        // first paint and come back empty.
        DispatchQueue.main.async { [weak self] in self?.onFinish?(.success(())) }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onFinish?(.failure(error))
    }

    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        onFinish?(.failure(error))
    }
}

struct Failure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

// MARK: - PNG on disk

func encodePNG(_ image: CGImage) -> Data? {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        data, UTType.png.identifier as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return data as Data
}

// MARK: - the run

for variant in variants {
    let svg = sourceRoot.appending(path: variant.source)
    guard FileManager.default.fileExists(atPath: svg.path) else {
        FileHandle.standardError.write(Data("error: missing \(svg.path)\n".utf8))
        exit(1)
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)

let renderer = Renderer()
var remaining = variants.reversed().map { $0 }
var written = 0
var stale: [String] = []
var failures: [String] = []

func finish() -> Never {
    if checkOnly {
        if stale.isEmpty && failures.isEmpty {
            print("render-app-icon: \(variants.count) icons match their sources")
            exit(0)
        }
        for path in stale { print("stale: \(path)") }
        for message in failures { print("error: \(message)") }
        FileHandle.standardError.write(Data(
            "render-app-icon --check: \(stale.count) stale, \(failures.count) failed — rerun without --check\n".utf8))
        exit(1)
    }
    for message in failures { FileHandle.standardError.write(Data("error: \(message)\n".utf8)) }
    print("render-app-icon: wrote \(written) of \(variants.count) icons into \(outputRoot.path)")
    exit(failures.isEmpty ? 0 : 1)
}

func step() {
    guard let variant = remaining.popLast() else { finish() }
    let svg = sourceRoot.appending(path: variant.source)
    let target = outputRoot.appending(path: variant.output)

    renderer.render(svg: svg) { result in
        switch result {
        case .failure(let error):
            failures.append("\(variant.source): \(error.localizedDescription)")
        case .success(let image):
            guard let png = encodePNG(image) else {
                failures.append("\(variant.source): PNG encoding failed")
                break
            }
            if checkOnly {
                // Compared by presence and dimensions rather than byte
                // equality: WebKit's rasterizer is not bit-stable across OS
                // releases, and a gate that reddens on a system update is a
                // gate people turn off. What must not drift is that the
                // catalog has a file where it says it has one, at the size the
                // icon set declares.
                let existing = try? Data(contentsOf: target)
                if existing == nil {
                    stale.append("\(variant.output): not in the icon set")
                } else if let existing,
                          let source = CGImageSourceCreateWithData(existing as CFData, nil),
                          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                            as? [CFString: Any],
                          let w = properties[kCGImagePropertyPixelWidth] as? Int,
                          let h = properties[kCGImagePropertyPixelHeight] as? Int,
                          w != side || h != side {
                    stale.append("\(variant.output): \(w)×\(h) on disk, \(side)×\(side) declared")
                }
            } else {
                do {
                    try FileManager.default.createDirectory(
                        at: outputRoot, withIntermediateDirectories: true)
                    try png.write(to: target, options: .atomic)
                    written += 1
                } catch {
                    failures.append("\(variant.source): \(error.localizedDescription)")
                }
            }
        }
        DispatchQueue.main.async(execute: step)
    }
}

DispatchQueue.main.async(execute: step)
application.run()
