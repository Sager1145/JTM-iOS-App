// Rebuild the Japanese operator badges around the ink their sources draw.
//
// Each of the 33 `cropped-emblem` rows in `jp-badges/manifest.json` carries a
// fractional window — `[0, 0, 0.18, 1]` — picked by eye off a combination mark
// to keep the emblem and drop the company lettering. Picking by eye is a guess
// about where the emblem ends, and several of the guesses fall short of it:
// `badge-026.png` (長野電鉄) came out 118 × 128 with ink on all four canvas
// edges, which is a round emblem cut flat down both sides.
//
// Ink on a canvas edge is wrong twice over. The badge is drawn `scaledToFit`
// inside a rounded-rectangle tile, so artwork that reaches its own edge reads
// as cut off even when it is whole; and where the window really did clip, the
// missing arc is gone from the file and no amount of layout puts it back.
//
// So the window stops being the answer and becomes the question. The source is
// rendered, every connected run of ink the window lands on is followed out to
// its own extent, and those runs — and nothing else that happens to stand
// between them — are the emblem, including the parts the fraction sliced off.
// That box is squared and given a transparent margin for the tile to breathe
// in. The manifest keeps its `crop`, since it still records which region of the
// source was meant, and gains the measured `cropResolved` and `badgePixels`
// beside it.
//
//   swift ios/tools/rebuild-operator-badges.swift          # rewrite the badges
//   swift ios/tools/rebuild-operator-badges.swift --check  # report, write nothing
//
// WebKit draws the SVG sources, for the reason `rasterize-badge-svgs.swift`
// sets out at length: these are real-world logos and ImageIO decodes no SVG.
// Its renderer is copied here rather than shared, because both files are loose
// scripts run by hand and a script that needs a second file is a script nobody
// runs.
//
// macOS-only, and that is fine: it runs by hand when artwork or a crop moves,
// and its output is committed. Nothing in the app or the build calls it.

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
let publicRoot = repoRoot.appending(path: "app/public")
let manifestURL = publicRoot.appending(path: "rail/operator-logos/jp-badges/manifest.json")

let checkOnly = CommandLine.arguments.contains("--check")

// MARK: - the numbers a badge is decided by

/// Above this a pixel counts as artwork. An order of magnitude below half
/// opacity, so a soft vector edge still belongs to the shape it feathers out
/// of, while the near-nothing a rasterizer leaves around a curve does not
/// drag the emblem's bounds outwards.
let inkFloor: UInt8 = 24

/// The emblem is measured at this many pixels on its longer side at least, so
/// that a bound is off by a fraction of a percent rather than by a pixel of a
/// 35-pixel window. The second number caps what that is allowed to cost: one
/// source is 9509 px wide, and rendering it whole to satisfy a narrow window
/// buys nothing a flood fill can use.
let measuredWindowSide = 512.0
let widestSource = 6000.0

/// How far past the seed window the ink is allowed to reach before the answer
/// stops being an emblem. A clipped emblem overruns its window by a slice; a
/// source whose background is opaque, or whose emblem touches the lettering,
/// hands back the whole canvas instead, and that has to be caught rather than
/// written out as a badge.
let runawayFactor = 2.5

/// Ink over this much of a source means the source is paper rather than
/// artwork on transparency: a JPEG, a GIF, or a PNG flattened onto white before
/// anybody downloaded it. Five of these sources are, and on those a flood fill
/// answers with the sheet of paper, so it is not asked.
let paperCoverage = 0.98

/// Transparent border on each side of the squared emblem, as a fraction of the
/// finished side. The tile needs the badge to stop short of its own edge; 6%
/// is enough to read as deliberate at the 16 pt the popup draws it.
let marginFraction = 0.06

/// The written badge is square and lands in this range: large enough for the
/// 3× tile with room over, small enough that 33 of them stay a rounding error
/// in the app bundle.
let smallestBadge = 256
let largestBadge = 512

// MARK: - the manifest

struct Row {
    let operatorName: String
    let sourceAsset: String
    let runtimeAsset: String
    let crop: [Double]
    /// What a previous run recorded, if one has run: the yardstick `--check`
    /// holds the manifest to.
    let recorded: [Int]?
    var badgeName: String { (runtimeAsset as NSString).lastPathComponent }
}

func readRows() throws -> [Row] {
    let data = try Data(contentsOf: manifestURL)
    guard let entries = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
        throw Failure("\(manifestURL.lastPathComponent) is not an array of objects")
    }
    return entries.compactMap { entry in
        guard entry["mode"] as? String == "cropped-emblem",
              let operatorName = entry["operator"] as? String,
              let sourceAsset = entry["sourceAsset"] as? String,
              let runtimeAsset = entry["runtimeAsset"] as? String,
              let crop = entry["crop"] as? [Double], crop.count == 4
        else { return nil }
        return Row(
            operatorName: operatorName, sourceAsset: sourceAsset,
            runtimeAsset: runtimeAsset, crop: crop,
            recorded: entry["badgePixels"] as? [Int])
    }
}

/// A number spelled the way the rest of the manifest spells one.
///
/// Four decimals is the precision already in the file (`0.2593`), and past it
/// the digits describe rounding in the rasterizer rather than the artwork.
func manifestNumber(_ value: Double) -> String {
    let rounded = (value * 10_000).rounded() / 10_000
    if rounded == rounded.rounded() { return String(Int(rounded)) }
    var text = String(format: "%.4f", rounded)
    while text.hasSuffix("0") { text.removeLast() }
    if text.hasSuffix(".") { text.removeLast() }
    return text
}

/// The manifest with two keys added to the rows that were rebuilt.
///
/// Spliced into the text rather than re-encoded from a parsed object, because
/// `JSONSerialization` has no ordered dictionary: a round trip would sort
/// `operator` after `mode` and rewrite all 122 rows to add two keys to 32 of
/// them. This appends inside the object's own closing brace, so every existing
/// key keeps its place, its spelling and its indent.
func manifestUpdating(_ text: String, _ additions: [(runtimeAsset: String, lines: String)])
    throws -> String
{
    // A rerun replaces its own last answer rather than stacking a second copy
    // of it. Both keys hold arrays and only ever arrive by being appended, so
    // the pair `,\n    "key": [` and the next `\n    ]` bracket exactly one of
    // them.
    var text = text
    for key in ["cropResolved", "badgePixels"] {
        while let start = text.range(of: ",\n    \"\(key)\": [") {
            guard let end = text.range(of: "\n    ]", range: start.upperBound..<text.endIndex)
            else { break }
            text.removeSubrange(start.lowerBound..<end.upperBound)
        }
    }
    for addition in additions {
        guard let anchor = text.range(of: "\"runtimeAsset\": \"\(addition.runtimeAsset)\"") else {
            throw Failure("no manifest row names \(addition.runtimeAsset)")
        }
        // Top-level rows close at indent 2; their arrays close at indent 4, so
        // the first such brace after the row's own key is the row's own end.
        guard let close = text.range(of: "\n  }", range: anchor.upperBound..<text.endIndex) else {
            throw Failure("the row for \(addition.runtimeAsset) never closes")
        }
        text.replaceSubrange(close, with: ",\n\(addition.lines)\n  }")
    }
    return text
}

// MARK: - SVG, measured and wrapped

/// The intrinsic aspect, from the root `<svg>` element.
///
/// `viewBox` first because it is what actually scales; `width`/`height` are the
/// fallback, and `q6958437.svg` — the one this file exists for — is a file that
/// needs it.
func intrinsicSize(ofSVG markup: String) -> CGSize? {
    guard let tagRange = markup.range(of: "<svg\\b[^>]*>", options: .regularExpression) else {
        return nil
    }
    let tag = String(markup[tagRange])

    func attribute(_ name: String) -> String? {
        guard let range = tag.range(of: "\\b\(name)\\s*=\\s*\"[^\"]*\"", options: .regularExpression)
        else { return nil }
        let pair = tag[range]
        guard let open = pair.firstIndex(of: "\""), let close = pair.lastIndex(of: "\""),
              open < close
        else { return nil }
        return String(pair[pair.index(after: open)..<close])
    }

    if let box = attribute("viewBox") {
        let parts = box.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\n" || $0 == "\t" })
        if parts.count == 4, let w = Double(parts[2]), let h = Double(parts[3]), w > 0, h > 0 {
            return CGSize(width: w, height: h)
        }
    }
    // `40px` and `40pt` both appear; the unit does not matter because only the
    // ratio of the two is used.
    func length(_ raw: String?) -> Double? {
        guard let raw else { return nil }
        let digits = raw.prefix { $0.isNumber || $0 == "." }
        return Double(digits)
    }
    if let w = length(attribute("width")), let h = length(attribute("height")), w > 0, h > 0 {
        return CGSize(width: w, height: h)
    }
    return nil
}

/// The markup, wrapped so that CSS can size it and nothing paints a ground.
///
/// The XML prolog and any DOCTYPE go, because inside an HTML document they are
/// parse errors rather than declarations, and a `viewBox` is injected when the
/// file has none: without one an SVG does not scale at all, and CSS width and
/// height would crop it instead of resizing it.
func page(forSVG markup: String, intrinsic: CGSize) -> String {
    var svg = markup
    while let prolog = svg.range(of: "<\\?xml[^>]*\\?>", options: .regularExpression) {
        svg.removeSubrange(prolog)
    }
    while let doctype = svg.range(
        of: "<!DOCTYPE[^>]*>", options: [.regularExpression, .caseInsensitive])
    {
        svg.removeSubrange(doctype)
    }
    if let tagRange = svg.range(of: "<svg\\b[^>]*>", options: .regularExpression),
       !svg[tagRange].contains("viewBox") {
        let injected = svg[tagRange].replacingOccurrences(
            of: "<svg",
            with: "<svg viewBox=\"0 0 \(intrinsic.width) \(intrinsic.height)\"",
            options: [],
            range: svg[tagRange].startIndex..<svg[tagRange].index(svg[tagRange].startIndex, offsetBy: 4))
        svg.replaceSubrange(tagRange, with: injected)
    }
    return """
        <!doctype html><html><head><meta charset="utf-8"><style>
        html, body { margin: 0; padding: 0; background: transparent; overflow: hidden; }
        svg { display: block; width: 100vw; height: 100vh; }
        </style></head><body>\(svg)</body></html>
        """
}

// MARK: - the renderer

/// One offscreen WebKit view, reused for every SVG source.
///
/// It lives in a window because a `WKWebView` with no window does not
/// necessarily have a layer to snapshot; the window is parked off every screen
/// and the process runs as an accessory, so nothing appears and nothing steals
/// focus. The snapshot arrives at the host's backing scale, which is why the
/// caller redraws it at an exact pixel size — a badge must not depend on which
/// machine rebuilt it.
final class Renderer: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private let window: NSWindow
    private var onFinish: ((Result<Void, Error>) -> Void)?

    override init() {
        webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 1, height: 1),
            configuration: WKWebViewConfiguration())
        window = NSWindow(
            contentRect: CGRect(x: -10_000, y: -10_000, width: 1, height: 1),
            styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        // Transparent all the way down: the window, its backing, and the page.
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = webView
        window.orderBack(nil)
        webView.navigationDelegate = self
        webView.underPageBackgroundColor = .clear
        // `underPageBackgroundColor` covers the overscroll ground; the page's
        // own ground is a separate, older switch with no public spelling.
        webView.setValue(false, forKey: "drawsBackground")
    }

    func render(svg: URL, size: CGSize, completion: @escaping (Result<NSImage, Error>) -> Void) {
        let markup: String
        do { markup = try String(contentsOf: svg, encoding: .utf8) }
        catch { return completion(.failure(error)) }
        guard let intrinsic = intrinsicSize(ofSVG: markup) else {
            return completion(.failure(Failure("no viewBox and no width/height on the root <svg>")))
        }

        window.setContentSize(size)
        webView.frame = CGRect(origin: .zero, size: size)
        onFinish = { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success:
                let configuration = WKSnapshotConfiguration()
                configuration.rect = CGRect(origin: .zero, size: size)
                self.webView.takeSnapshot(with: configuration) { image, error in
                    if let error { return completion(.failure(error)) }
                    guard let image else {
                        return completion(.failure(Failure("snapshot produced no bitmap")))
                    }
                    completion(.success(image))
                }
            }
        }
        webView.loadHTMLString(page(forSVG: markup, intrinsic: intrinsic), baseURL: nil)
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

// MARK: - pixels

/// An image and its own bytes, so that the ink can be read and then redrawn
/// without decoding twice.
struct Raster {
    let width: Int
    let height: Int
    /// RGBA, premultiplied, four bytes per pixel.
    let pixels: [UInt8]
    let image: CGImage

    func alpha(_ x: Int, _ y: Int) -> UInt8 { pixels[(y * width + x) * 4 + 3] }
}

/// Any image, resampled onto a transparent canvas of an exact pixel size.
func redraw(_ image: CGImage, width: Int, height: Int) -> Raster? {
    let width = max(1, width)
    let height = max(1, height)
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    var made: CGImage?
    pixels.withUnsafeMutableBytes { buffer in
        guard let context = CGContext(
            data: buffer.baseAddress, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }
        context.interpolationQuality = .high
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        made = context.makeImage()
    }
    guard let made else { return nil }
    return Raster(width: width, height: height, pixels: pixels, image: made)
}

/// A half-open pixel rectangle, y downwards, in the coordinates of a ``Raster``.
struct Box {
    var minX: Int
    var minY: Int
    var maxX: Int
    var maxY: Int

    var width: Int { maxX - minX }
    var height: Int { maxY - minY }
    var isEmpty: Bool { width <= 0 || height <= 0 }

    func clamped(to raster: Raster) -> Box {
        Box(
            minX: max(0, min(minX, raster.width)), minY: max(0, min(minY, raster.height)),
            maxX: max(0, min(maxX, raster.width)), maxY: max(0, min(maxY, raster.height)))
    }
}

/// The manifest's fractions as pixels.
///
/// Rounded outwards so that a window is never one pixel short of the ink it was
/// drawn around; a seed that misses the emblem by a pixel finds nothing to
/// follow.
func seedBox(crop: [Double], in raster: Raster) -> Box {
    Box(
        minX: Int((crop[0] * Double(raster.width)).rounded(.down)),
        minY: Int((crop[1] * Double(raster.height)).rounded(.down)),
        maxX: Int((crop[2] * Double(raster.width)).rounded(.up)),
        maxY: Int((crop[3] * Double(raster.height)).rounded(.up))
    ).clamped(to: raster)
}

/// What the window found, and what it turned out to be part of.
struct Reach {
    /// The ink actually inside the manifest's window. The window itself is a
    /// poor yardstick — most of these leave transparent room on one axis — so
    /// this is what the recovered emblem is measured against, and it is also
    /// what the old badge showed.
    let seeded: Box
    /// The whole of every shape that ink belongs to.
    let whole: Box
    /// One flag per pixel of the source: true where the fill went.
    let followed: [Bool]
}

/// Everything the ink inside `seed` is joined to.
///
/// A single flood fill started from every ink pixel in the window, rather than
/// a fill per component and a union afterwards: the two produce the same set,
/// and one visited mark is the cheap way to say it. Diagonal neighbours count,
/// because a stroke rasterized at an angle is a staircase and eight-
/// connectivity is what keeps it one shape.
func inkReachedFrom(_ seed: Box, in raster: Raster) -> Reach? {
    let width = raster.width
    var visited = [Bool](repeating: false, count: width * raster.height)
    var stack: [Int] = []
    var seeded = Box(minX: width, minY: raster.height, maxX: -1, maxY: -1)
    for y in seed.minY..<seed.maxY {
        for x in seed.minX..<seed.maxX {
            let index = y * width + x
            if raster.pixels[index * 4 + 3] > inkFloor && !visited[index] {
                visited[index] = true
                stack.append(index)
                seeded.minX = min(seeded.minX, x)
                seeded.minY = min(seeded.minY, y)
                seeded.maxX = max(seeded.maxX, x)
                seeded.maxY = max(seeded.maxY, y)
            }
        }
    }
    guard !stack.isEmpty else { return nil }
    seeded.maxX += 1
    seeded.maxY += 1

    var whole = Box(minX: width, minY: raster.height, maxX: -1, maxY: -1)
    while let index = stack.popLast() {
        let x = index % width
        let y = index / width
        whole.minX = min(whole.minX, x)
        whole.minY = min(whole.minY, y)
        whole.maxX = max(whole.maxX, x)
        whole.maxY = max(whole.maxY, y)
        for ny in max(0, y - 1)...min(raster.height - 1, y + 1) {
            for nx in max(0, x - 1)...min(width - 1, x + 1) {
                let neighbour = ny * width + nx
                if !visited[neighbour] && raster.pixels[neighbour * 4 + 3] > inkFloor {
                    visited[neighbour] = true
                    stack.append(neighbour)
                }
            }
        }
    }
    whole.maxX += 1
    whole.maxY += 1
    return Reach(seeded: seeded, whole: whole, followed: visited)
}

/// How much of a source is drawn on at all.
///
/// A JPEG has no alpha, and three of the PNGs and the one GIF were flattened
/// onto white before anyone downloaded them. On those, every pixel is ink, the
/// fill runs to the paper's edge, and there is no emblem to find — only a
/// rectangle. Better to notice that up front than to hand back a rectangle that
/// happens to be under 2.5 times the window.
func inkCoverage(of raster: Raster) -> Double {
    var count = 0
    for index in stride(from: 3, to: raster.pixels.count, by: 4)
    where raster.pixels[index] > inkFloor {
        count += 1
    }
    return Double(count) / Double(raster.width * raster.height)
}

/// A source with everything the fill did not follow rubbed out.
///
/// Cropping to the emblem's box is not the same as keeping only the emblem.
/// えちごトキめき鉄道 writes its company name in the bay of its own mountain,
/// so the box around that mountain has the lettering inside it, and a badge
/// cropped to the box would carry the words the crop exists to drop. What the
/// fill followed is the emblem; the rest goes, including out of the margin.
///
/// The two-pixel reprieve is for antialiasing: the fringe a rasterizer leaves
/// around a stroke falls under the ink floor and so is never followed, and
/// erasing it would hand the emblem a hard edge it does not have.
func masked(_ sheet: Raster, keeping followed: [Bool], within box: Box) -> Raster? {
    let reprieve = 2
    var pixels = sheet.pixels
    for y in box.minY..<box.maxY {
        for x in box.minX..<box.maxX {
            let index = y * sheet.width + x
            if followed[index] || pixels[index * 4 + 3] == 0 { continue }
            var near = false
            for ny in max(0, y - reprieve)...min(sheet.height - 1, y + reprieve) {
                for nx in max(0, x - reprieve)...min(sheet.width - 1, x + reprieve)
                where followed[ny * sheet.width + nx] {
                    near = true
                    break
                }
                if near { break }
            }
            if !near {
                for channel in 0..<4 { pixels[index * 4 + channel] = 0 }
            }
        }
    }
    var made: CGImage?
    pixels.withUnsafeMutableBytes { buffer in
        guard let context = CGContext(
            data: buffer.baseAddress, width: sheet.width, height: sheet.height,
            bitsPerComponent: 8, bytesPerRow: sheet.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }
        made = context.makeImage()
    }
    guard let made else { return nil }
    return Raster(width: sheet.width, height: sheet.height, pixels: pixels, image: made)
}

/// The bounds of every ink pixel in an image, wherever it is.
///
/// Used on the badge already on disk, to say which of its canvas edges the
/// artwork was touching, and on the badge just composed, to prove it touches
/// none of them.
func inkBounds(of raster: Raster) -> Box? {
    var box = Box(minX: raster.width, minY: raster.height, maxX: -1, maxY: -1)
    for y in 0..<raster.height {
        for x in 0..<raster.width where raster.alpha(x, y) > inkFloor {
            box.minX = min(box.minX, x)
            box.minY = min(box.minY, y)
            box.maxX = max(box.maxX, x)
            box.maxY = max(box.maxY, y)
        }
    }
    guard box.maxX >= 0 else { return nil }
    box.maxX += 1
    box.maxY += 1
    return box
}

// MARK: - composing the badge

/// The emblem, squared, centred, and surrounded by transparency.
///
/// Drawing is clipped to the ink box rather than merely positioned by it. The
/// margin sits over whatever the source has next door — for most of these that
/// is the company lettering the crop was drawn to exclude — and a margin with
/// the neighbour's ink in it is not a margin.
func compose(_ raster: Raster, ink: Box, side: Int) -> CGImage? {
    let side = Double(side)
    let scale = side / (1 + 2 * marginFraction) / Double(max(ink.width, ink.height))
    let drawnWidth = Double(ink.width) * scale
    let drawnHeight = Double(ink.height) * scale
    let insetX = (side - drawnWidth) / 2
    let insetY = (side - drawnHeight) / 2

    guard let context = CGContext(
        data: nil, width: Int(side), height: Int(side),
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.interpolationQuality = .high
    context.clear(CGRect(x: 0, y: 0, width: side, height: side))
    // Core Graphics counts y upwards from the bottom while the ink box counts
    // it downwards from the top, so the inset measured from the top of the
    // canvas becomes a distance from the bottom of the drawn emblem.
    context.clip(to: CGRect(
        x: insetX, y: side - insetY - drawnHeight, width: drawnWidth, height: drawnHeight))
    context.draw(
        raster.image,
        in: CGRect(
            x: insetX - Double(ink.minX) * scale,
            y: side - insetY - Double(raster.height) * scale + Double(ink.minY) * scale,
            width: Double(raster.width) * scale,
            height: Double(raster.height) * scale))
    return context.makeImage()
}

func encodePNG(_ image: CGImage) -> Data? {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        data, UTType.png.identifier as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return data as Data
}

func loadRaster(_ url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

// MARK: - what a row came to

struct Outcome {
    let row: Row
    var skipped: String?
    var failure: String?
    var rejected: String?
    var oldPixels: (width: Int, height: Int)?
    var oldFlush: [String] = []
    var seen: (width: Int, height: Int)?
    var ink: (width: Int, height: Int)?
    var newPixels: (width: Int, height: Int)?
    var margins: (left: Double, top: Double, right: Double, bottom: Double)?
    var resolved: [Double]?
    var png: Data?
}

/// The pixel size to measure a source at.
///
/// Enough that the manifest's window covers ``measuredWindowSide`` on its
/// longer side, capped at ``widestSource``. Raster sources are never enlarged
/// past their own pixels: interpolation invents no ink for a flood fill to
/// find, and the one resample the badge needs is better spent going straight
/// from those pixels to the finished square.
func measuringWidth(for intrinsic: CGSize, crop: [Double], isVector: Bool) -> Int {
    let windowWidth = max(1.0, (crop[2] - crop[0]) * Double(intrinsic.width))
    let windowHeight = max(1.0, (crop[3] - crop[1]) * Double(intrinsic.height))
    let wanted = measuredWindowSide / max(windowWidth, windowHeight)
    let scale = isVector ? max(1, wanted) : 1
    return Int(min(Double(intrinsic.width) * scale, widestSource).rounded())
}

func resolve(_ sheet: Raster, _ row: Row, into result: inout Outcome) {
    let seed = seedBox(crop: row.crop, in: sheet)
    guard !seed.isEmpty else {
        result.failure = "the manifest window is empty at \(sheet.width)×\(sheet.height)"
        return
    }

    var raster = sheet
    var ink = seed
    var seen = seed
    if inkCoverage(of: sheet) > paperCoverage {
        result.rejected = "the source is opaque paper, not artwork on transparency"
    } else if let reached = inkReachedFrom(seed, in: sheet) {
        seen = reached.seeded
        let runaway = Double(reached.whole.width) > runawayFactor * Double(seed.width)
            || Double(reached.whole.height) > runawayFactor * Double(seed.height)
        if runaway {
            result.rejected = "the ink runs past \(manifestNumber(runawayFactor))× the window"
        } else {
            ink = reached.whole
            raster = masked(sheet, keeping: reached.followed, within: ink) ?? sheet
        }
    } else {
        result.rejected = "the window holds no ink"
    }
    result.seen = (seen.width, seen.height)
    result.ink = (ink.width, ink.height)
    result.resolved = [
        Double(ink.minX) / Double(raster.width), Double(ink.minY) / Double(raster.height),
        Double(ink.maxX) / Double(raster.width), Double(ink.maxY) / Double(raster.height),
    ]

    let square = Double(max(ink.width, ink.height)) * (1 + 2 * marginFraction)
    let side = min(max(Int(square.rounded()), smallestBadge), largestBadge)
    guard let badge = compose(raster, ink: ink, side: side),
          let png = encodePNG(badge),
          let measured = redraw(badge, width: side, height: side),
          let bounds = inkBounds(of: measured)
    else {
        result.failure = "the badge would not compose at \(side)×\(side)"
        return
    }
    result.newPixels = (side, side)
    result.png = png
    result.margins = (
        left: Double(bounds.minX) / Double(side),
        top: Double(bounds.minY) / Double(side),
        right: Double(side - bounds.maxX) / Double(side),
        bottom: Double(side - bounds.maxY) / Double(side))
}

/// What the badge on disk looks like now, for the before half of the report.
func describeExisting(_ url: URL, into result: inout Outcome) {
    guard let image = loadRaster(url),
          let existing = redraw(image, width: image.width, height: image.height)
    else { return }
    result.oldPixels = (existing.width, existing.height)
    guard let bounds = inkBounds(of: existing) else { return }
    if bounds.minX == 0 { result.oldFlush.append("L") }
    if bounds.minY == 0 { result.oldFlush.append("T") }
    if bounds.maxX == existing.width { result.oldFlush.append("R") }
    if bounds.maxY == existing.height { result.oldFlush.append("B") }
}

// MARK: - the run

let rows: [Row]
let manifestText: String
do {
    rows = try readRows()
    manifestText = try String(contentsOf: manifestURL, encoding: .utf8)
} catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(1)
}
guard !rows.isEmpty else {
    FileHandle.standardError.write(Data("error: no cropped-emblem rows in the manifest\n".utf8))
    exit(1)
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)

let renderer = Renderer()
var pending = rows.reversed().map { $0 }
var results: [Outcome] = []

func report() -> Never {
    var lines: [String] = []
    var grew: [String] = []
    var failures: [String] = []

    for result in results.sorted(by: { $0.row.badgeName < $1.row.badgeName }) {
        let name = result.row.badgeName
        if let skipped = result.skipped {
            lines.append("\(name)  skipped — \(skipped)")
            continue
        }
        if let failure = result.failure {
            failures.append("\(name): \(failure)")
            continue
        }
        let old = result.oldPixels.map { "\($0.width)×\($0.height)" } ?? "absent"
        let new = result.newPixels.map { "\($0.width)×\($0.height)" } ?? "—"
        let flush = result.oldFlush.isEmpty ? "none" : result.oldFlush.joined()
        var line = "\(name)  \(old) → \(new)  flush \(flush)"
        // Against the ink the window actually held, not against the window:
        // most of these windows run to the full height of a source that leaves
        // room above and below the mark, and a percentage off that measures the
        // whitespace rather than the recovery.
        if let seen = result.seen, let ink = result.ink {
            let dw = Double(ink.width - seen.width) / Double(seen.width) * 100
            let dh = Double(ink.height - seen.height) / Double(seen.height) * 100
            line += String(
                format: "  ink %d×%d → %d×%d (%+.1f%% / %+.1f%%)",
                seen.width, seen.height, ink.width, ink.height, dw, dh)
            if dw > 10 || dh > 10 {
                grew.append(String(format: "%@ %@ (%+.1f%% / %+.1f%%)",
                    name, result.row.operatorName, dw, dh))
            }
        }
        if let margins = result.margins {
            line += String(
                format: "  margins %.3f/%.3f/%.3f/%.3f",
                margins.left, margins.top, margins.right, margins.bottom)
            if min(margins.left, margins.top, margins.right, margins.bottom) <= 0 {
                failures.append("\(name): the finished badge still touches a canvas edge")
            }
        }
        if let rejected = result.rejected { line += "  kept the window — \(rejected)" }
        line += "  \(result.row.operatorName)"
        lines.append(line)
    }

    for line in lines { print(line) }
    if !grew.isEmpty {
        print("\nclipped by the manifest window — ink recovered beyond 10%:")
        for line in grew { print("  \(line)") }
    }

    let writable = results.filter { $0.png != nil }
    let additions: [(runtimeAsset: String, lines: String)] = writable.compactMap { result in
        guard let resolved = result.resolved, let pixels = result.newPixels else { return nil }
        let fractions = resolved.map { "      \(manifestNumber($0))" }.joined(separator: ",\n")
        return (
            result.row.runtimeAsset,
            """
                "cropResolved": [
            \(fractions)
                ],
                "badgePixels": [
                  \(pixels.width),
                  \(pixels.height)
                ]
            """)
    }

    if checkOnly {
        // Compared by pixel size and by what the manifest recorded, never by
        // the bytes of the PNG: WebKit's rasterizer is not bit-stable across OS
        // releases, and a gate that reddens on a system update is a gate people
        // turn off. What must not drift is that every badge is the square the
        // source's own ink asks for, and that the manifest still says so.
        var stale: [String] = []
        for result in results where result.skipped == nil {
            let name = result.row.badgeName
            guard let new = result.newPixels else { continue }
            switch result.oldPixels {
            case nil:
                stale.append("\(name): no badge on disk")
            case let old? where old != new:
                stale.append("\(name): \(old.width)×\(old.height) on disk, "
                    + "\(new.width)×\(new.height) from source")
            default: break
            }
            if result.row.recorded != [new.width, new.height] {
                stale.append("\(name): the manifest records \(result.row.recorded.map(String.init(describing:)) ?? "nothing")")
            }
        }
        for line in stale { print("stale: \(line)") }
        for message in failures { print("error: \(message)") }
        if stale.isEmpty && failures.isEmpty {
            print("\nrebuild-operator-badges: \(writable.count) badges match their sources, "
                + "\(results.count - writable.count) left alone")
            exit(0)
        }
        let summary = "rebuild-operator-badges --check: \(stale.count) stale, "
            + "\(failures.count) failed — rerun without --check\n"
        FileHandle.standardError.write(Data(summary.utf8))
        exit(1)
    }

    for result in writable {
        let target = publicRoot.appending(path: String(result.row.runtimeAsset.dropFirst()))
        do { try result.png!.write(to: target, options: .atomic) }
        catch { failures.append("\(result.row.badgeName): \(error.localizedDescription)") }
    }
    do {
        try manifestUpdating(manifestText, additions).write(
            to: manifestURL, atomically: true, encoding: .utf8)
    } catch {
        failures.append("manifest.json: \(error.localizedDescription)")
    }

    for message in failures { FileHandle.standardError.write(Data("error: \(message)\n".utf8)) }
    print("\nrebuild-operator-badges: wrote \(writable.count) badges and "
        + "\(additions.count) manifest rows")
    exit(failures.isEmpty ? 0 : 1)
}

func step() {
    guard let row = pending.popLast() else { report() }
    var result = Outcome(row: row)
    let target = publicRoot.appending(path: String(row.runtimeAsset.dropFirst()))
    describeExisting(target, into: &result)

    // The one row sourced from a live operator header, which this cannot reach
    // and must not guess at: its badge stays exactly as the download left it.
    guard row.sourceAsset.hasPrefix("/") else {
        result.skipped = "sourceAsset is \(row.sourceAsset)"
        results.append(result)
        return DispatchQueue.main.async(execute: step)
    }

    let source = publicRoot.appending(path: String(row.sourceAsset.dropFirst()))
    let isVector = source.pathExtension.lowercased() == "svg"

    if isVector {
        guard let markup = try? String(contentsOf: source, encoding: .utf8),
              let intrinsic = intrinsicSize(ofSVG: markup)
        else {
            result.failure = "no intrinsic size in \(source.lastPathComponent)"
            results.append(result)
            return DispatchQueue.main.async(execute: step)
        }
        let width = measuringWidth(for: intrinsic, crop: row.crop, isVector: true)
        let height = max(1, Int((Double(width) * intrinsic.height / intrinsic.width).rounded()))
        renderer.render(svg: source, size: CGSize(width: width, height: height)) { rendered in
            switch rendered {
            case .failure(let error):
                result.failure = "\(source.lastPathComponent): \(error.localizedDescription)"
            case .success(let image):
                var rect = CGRect(x: 0, y: 0, width: width, height: height)
                if let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
                   let sheet = redraw(cgImage, width: width, height: height) {
                    resolve(sheet, row, into: &result)
                } else {
                    result.failure = "\(source.lastPathComponent): the snapshot held no bitmap"
                }
            }
            results.append(result)
            DispatchQueue.main.async(execute: step)
        }
        return
    }

    guard let image = loadRaster(source) else {
        result.failure = "ImageIO decoded nothing from \(source.lastPathComponent)"
        results.append(result)
        return DispatchQueue.main.async(execute: step)
    }
    let intrinsic = CGSize(width: image.width, height: image.height)
    let width = measuringWidth(for: intrinsic, crop: row.crop, isVector: false)
    let height = max(1, Int((Double(width) * intrinsic.height / intrinsic.width).rounded()))
    guard let sheet = redraw(image, width: width, height: height) else {
        result.failure = "\(source.lastPathComponent) would not redraw at \(width)×\(height)"
        results.append(result)
        return DispatchQueue.main.async(execute: step)
    }
    resolve(sheet, row, into: &result)
    results.append(result)
    DispatchQueue.main.async(execute: step)
}

DispatchQueue.main.async(execute: step)
application.run()
