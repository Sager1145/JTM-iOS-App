import CoreGraphics
import Foundation
import ImageIO
import RailCore
import Vision

// =========================================================================
//  TransferGuideOCR.swift — running Vision over a screenshot that may be
//  twenty thousand pixels tall.
//
//  This is the half of the screenshot importer that cannot be unit-tested:
//  it is a live text recogniser reading a bitmap, and what it returns depends
//  on the OS revision, the device and the font the screenshot was captured
//  at. Everything it produces goes straight into ``TransferGuide/parse(_:)``,
//  which is the half that IS tested, so the only judgement made here is how
//  to hand a very tall picture to a recogniser that was not designed for one.
//
//  ## Why tiles
//
//  Vision resizes its input to a working resolution before recognising. A
//  1290 × 18000 screenshot resized to fit that budget leaves station names
//  two or three pixels tall, and the request comes back with almost nothing —
//  not an error, just a page of empty. Cutting the page into overlapping
//  tiles keeps every tile close to the shape Vision expects, and the overlap
//  is what stops a row from being lost because it fell across a seam.
//
//  The tiles are cropped from the source and drawn one at a time, so the peak
//  cost is one tile, not one decoded copy of the page per tile.
// =========================================================================

enum TransferGuideOCR {

    /// What was read, in one coordinate space.
    ///
    /// Several screenshots of one route are stacked end to end here rather
    /// than parsed separately, because a leg that begins on the first and ends
    /// on the second is one leg. The parser reads a document; this decides
    /// what the document is.
    struct Reading: Sendable {
        var lines: [TransferGuide.TextLine]
        var documentWidth: Double
        var documentHeight: Double
        var pageCount: Int
        var tileCount: Int
        /// Every row read, top to bottom, for the preview's raw-text
        /// disclosure. A screenshot that parsed into nothing is a screenshot
        /// whose reader needs to see what the recogniser actually saw.
        var rawRows: [String]
    }

    enum Failure: LocalizedError, Equatable {
        case undecodable
        case tooLarge(megapixels: Int)
        case noText
        case unavailable

        var errorDescription: String? {
            switch self {
            case .undecodable:
                "The image could not be read."
            case .tooLarge(let megapixels):
                "The image is \(megapixels) megapixels, which is too large to read."
            case .noText:
                "No text was found in the image."
            case .unavailable:
                "Text recognition is not available on this device."
            }
        }
    }

    /// Above this, refuse rather than run the device out of memory.
    ///
    /// A 1290-wide capture of the longest route Yahoo will plan is about 23
    /// megapixels; this is five times that, which is comfortably past
    /// anything a screenshot can be and comfortably short of what a phone
    /// cannot hold.
    private static let pixelLimit = 120_000_000

    /// The width a tile is recognised at.
    ///
    /// Yahoo's station names are about 3 % of the screen width. At 1400 px
    /// that is a 40-pixel glyph, which is where the accurate recogniser stops
    /// improving; below about 900 the kana in 新函館北斗 start merging.
    private static let recognitionWidth = 1400.0
    private static let tileHeight = 1600.0
    /// One leg header block is about 200 px tall at the recognition width.
    /// The overlap has to clear a whole one, or a seam that lands inside a
    /// block can lose the row that names the train.
    private static let tileOverlap = 360.0

    /// Reads one or more screenshots as a single top-to-bottom document.
    ///
    /// `pages` is the encoded image data rather than decoded images so that
    /// nothing that is not `Sendable` has to cross into this function — and so
    /// that the decode, which is the expensive part, happens here rather than
    /// on whichever actor picked the files.
    static func read(
        _ pages: [Data], onProgress: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> Reading {
        guard !pages.isEmpty else { throw Failure.undecodable }
        guard supportsJapanese() else { throw Failure.unavailable }

        var images: [CGImage] = []
        for page in pages {
            guard let image = decode(page) else { throw Failure.undecodable }
            let pixels = image.width * image.height
            if pixels > pixelLimit { throw Failure.tooLarge(megapixels: pixels / 1_000_000) }
            images.append(image)
        }

        // One document width, so a route captured on two devices — or the same
        // device before and after a text-size change — still lines its columns
        // up. Everything after this point is in document points.
        let documentWidth = Double(images[0].width)
        let plans = images.map { image in
            (image: image,
             scale: documentWidth / Double(image.width),
             tiles: tileOrigins(height: image.height, scale: recognitionScale(image)))
        }
        let totalTiles = plans.reduce(0) { $0 + $1.tiles.count }

        // Read one page at a time, in its own space. The pages are only joined
        // afterwards, because where the second one BEGINS is a question that
        // cannot be answered until both have been read.
        var read: [[TransferGuide.TextLine]] = []
        var done = 0
        onProgress(0, totalTiles)
        for plan in plans {
            let scale = recognitionScale(plan.image)
            let tileSourceHeight = Int((tileHeight / scale).rounded())
            var collected = Collector()
            for origin in plan.tiles {
                try Task.checkCancellation()
                let height = min(tileSourceHeight, plan.image.height - origin)
                if let tile = render(plan.image, sourceY: origin, sourceHeight: height, scale: scale)
                {
                    let edges = Edges(
                        cutAtTop: origin > 0,
                        cutAtBottom: origin + height < plan.image.height)
                    for found in recognize(tile.image, edges: edges) {
                        collected.add(
                            found.mapped(
                                tileScale: scale, sourceY: Double(origin),
                                documentScale: plan.scale, documentY: 0),
                            clipped: found.clipped)
                    }
                }
                done += 1
                onProgress(done, totalTiles)
            }
            read.append(collected.sorted())
        }

        let stitched = stitch(read)
        guard !stitched.isEmpty else { throw Failure.noText }
        return Reading(
            lines: stitched,
            documentWidth: documentWidth,
            documentHeight: (stitched.map(\.box.maxY).max() ?? 0),
            pageCount: images.count,
            tileCount: totalTiles,
            rawRows: stitched.map(\.text))
    }

    // MARK: - joining the pages

    /// Lays several screenshots end to end, and refuses to say the same thing
    /// twice where they overlap.
    ///
    /// A reader capturing a long route in two shots scrolls between them, and
    /// what they scroll past appears at the bottom of one and the top of the
    /// next. Stacked naively that is a journey that visits 高崎 twice — and
    /// the parser, which has no way to know a document is two documents,
    /// would believe it.
    ///
    /// The overlap is found by the only evidence there is: the longest run of
    /// rows at the top of the next page that repeats the tail of this one.
    /// Matching that run also fixes the OTHER seam problem, because it says
    /// where the next page's first NEW row belongs — where a naive stack would
    /// have inserted both screenshots' margins between a transfer's 着 and its
    /// 発, and put them far enough apart to be read as two different stations.
    private static func stitch(_ pages: [[TransferGuide.TextLine]]) -> [TransferGuide.TextLine] {
        guard var document = pages.first else { return [] }
        for page in pages.dropFirst() where !page.isEmpty {
            guard !document.isEmpty else {
                document = page
                continue
            }
            let offset: Double
            let kept: ArraySlice<TransferGuide.TextLine>
            if let overlap = overlap(tail: document, head: page) {
                kept = page.dropFirst(overlap)
                // Anchor on the last row the two pages agree on, so the new
                // rows keep the spacing they were printed with.
                offset = document[document.count - 1].box.minY - page[overlap - 1].box.minY
            } else {
                kept = page[...]
                let gap = medianPitch(document)
                offset = (document.map(\.box.maxY).max() ?? 0) + gap
                    - (page.first?.box.minY ?? 0)
            }
            for var line in kept {
                line.box.y += offset
                document.append(line)
            }
        }
        return document.sorted {
            $0.box.minY == $1.box.minY ? $0.box.minX < $1.box.minX : $0.box.minY < $1.box.minY
        }
    }

    /// How many of the next page's rows the previous page already said.
    ///
    /// Longest first, and at least four rows: three rows of `10:45` and a
    /// station could repeat honestly in a timetable, and cutting an honest
    /// repeat would delete a stop.
    private static func overlap(
        tail: [TransferGuide.TextLine], head: [TransferGuide.TextLine]
    ) -> Int? {
        let window = min(160, min(tail.count, head.count))
        guard window >= 4 else { return nil }
        let tailText = tail.suffix(window).map(\.text)
        let headText = head.prefix(window).map(\.text)
        for length in stride(from: window, through: 4, by: -1)
        where Array(tailText.suffix(length)) == Array(headText.prefix(length)) {
            return length
        }
        return nil
    }

    /// The document's own row spacing, for the gap between two pages that do
    /// not overlap. Anything else — a constant, or the pages' own margins —
    /// is a distance the parser would have to be told about separately.
    private static func medianPitch(_ lines: [TransferGuide.TextLine]) -> Double {
        let centres = lines.map(\.box.midY).sorted()
        var steps: [Double] = []
        steps.reserveCapacity(centres.count)
        for (index, centre) in centres.enumerated() where index > 0 {
            let step = centre - centres[index - 1]
            // Two boxes on one row are not a row apart. Only the gaps that
            // separate rows say anything about the pitch.
            if step > 0.5 { steps.append(step) }
        }
        guard !steps.isEmpty else { return lines.first.map { $0.box.height * 1.6 } ?? 24 }
        steps.sort()
        return steps[steps.count / 2]
    }

    // MARK: - the picture

    private static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(
            source, 0, [kCGImageSourceShouldCache: false] as CFDictionary)
    }

    /// How much to enlarge a page so its text reaches the recogniser's stride.
    ///
    /// Never shrinks: a screenshot captured at 3× is already at a good size,
    /// and a downscale would throw away the only thing that makes the small
    /// intermediate-stop rows legible.
    private static func recognitionScale(_ image: CGImage) -> Double {
        min(4, max(1, recognitionWidth / Double(image.width)))
    }

    private static func tileOrigins(height: Int, scale: Double) -> [Int] {
        let tile = max(Int((tileHeight / scale).rounded()), 1)
        let overlap = min(Int((tileOverlap / scale).rounded()), tile - 1)
        let stride = max(tile - overlap, 1)
        guard height > tile else { return [0] }
        var origins: [Int] = []
        var y = 0
        while y < height {
            origins.append(y)
            if y + tile >= height { break }
            y += stride
        }
        return origins
    }

    private struct Tile {
        var image: CGImage
        var height: Double
    }

    private static func render(
        _ image: CGImage, sourceY: Int, sourceHeight: Int, scale: Double
    ) -> Tile? {
        guard sourceHeight > 0,
            let crop = image.cropping(
                to: CGRect(x: 0, y: sourceY, width: image.width, height: sourceHeight))
        else { return nil }
        let width = max(Int((Double(image.width) * scale).rounded()), 1)
        let height = max(Int((Double(sourceHeight) * scale).rounded()), 1)
        guard scale > 1.001 else { return Tile(image: crop, height: Double(height)) }
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return Tile(image: crop, height: Double(sourceHeight)) }
        context.interpolationQuality = .high
        context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { return Tile(image: crop, height: Double(sourceHeight)) }
        return Tile(image: scaled, height: Double(height))
    }

    // MARK: - the recogniser

    /// Whether this OS can read Japanese at all.
    ///
    /// Asked rather than assumed: the language list is a property of the
    /// recogniser's revision, and a device that cannot answer in Japanese
    /// would otherwise return a page of confident Latin nonsense.
    private static func supportsJapanese() -> Bool {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        guard let languages = try? request.supportedRecognitionLanguages() else { return false }
        return languages.contains { $0.hasPrefix("ja") }
    }

    private struct Found {
        var text: String
        var box: CGRect  // tile pixels, top-left origin
        var confidence: Double
        /// Whether this reading touches the edge the tile was cut at, and so
        /// lost glyphs to it. See ``Collector``.
        var clipped: Bool

        func mapped(
            tileScale: Double, sourceY: Double, documentScale: Double, documentY: Double
        ) -> TransferGuide.TextLine {
            let x = box.minX / tileScale * documentScale
            let y = (sourceY + box.minY / tileScale) * documentScale + documentY
            return TransferGuide.TextLine(
                text: text,
                box: TransferGuide.Box(
                    x: x, y: y,
                    width: box.width / tileScale * documentScale,
                    height: box.height / tileScale * documentScale),
                confidence: confidence)
        }
    }

    /// Which of a tile's horizontal edges is a cut rather than the page's own.
    private struct Edges {
        var cutAtTop: Bool
        var cutAtBottom: Bool
    }

    private static func recognize(_ image: CGImage, edges: Edges) -> [Found] {
        let interval = RailSignpost.jobs.begin("ocr.recognize")
        defer { RailSignpost.jobs.end("ocr.recognize", interval) }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ja-JP", "en-US"]
        // Off, deliberately. Language correction turns 尾久 into 御久 and
        // 籠原 into 篭原 — plausible Japanese, and a station that then matches
        // nothing. A raw misreading is at least visible as one.
        request.usesLanguageCorrection = false
        request.automaticallyDetectsLanguage = false

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil,
            let results = request.results
        else { return [] }

        let width = Double(image.width)
        let height = Double(image.height)
        // A reading within this much of a cut edge lost glyphs to it.
        let margin = max(height * 0.005, 2)
        return results.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox
            let top = (1 - box.maxY) * height
            let bottom = (1 - box.minY) * height
            return Found(
                // Vision's normalised box has its origin at the BOTTOM left,
                // and everything downstream reads a document downwards.
                text: candidate.string,
                box: CGRect(x: box.minX * width, y: top, width: box.width * width, height: bottom - top),
                confidence: Double(candidate.confidence),
                clipped: (edges.cutAtTop && top <= margin)
                    || (edges.cutAtBottom && bottom >= height - margin))
        }
    }

    // MARK: - the seams

    /// Keeps one copy of each row read from two overlapping tiles.
    ///
    /// Bucketed by POSITION rather than by text, and that is the whole point:
    /// the same pixels read in two tiles do not always come back as the same
    /// string. `(N700A)` was read once as `(N700A)` and once as `(ND9OA)`, and
    /// a collector keyed on the text kept both — which the parser then read as
    /// a 直通 service changing trains at its own departure station. Two boxes
    /// standing in the same place are one row, whatever they say.
    ///
    /// Which of the two survives is decided by the SEAM before it is decided
    /// by confidence. いわて沼宮内 lies across a cut: the tile it sits inside
    /// read it correctly, the tile it sits at the edge of read the top half of
    /// it as `いわイ辺ウ大＃` — and both came back at 0.30. Confidence alone
    /// would keep whichever tile happened to finish first.
    private struct Collector {
        private struct Reading {
            var line: TransferGuide.TextLine
            var clipped: Bool
        }

        private var buckets: [Int: [Reading]] = [:]
        /// Tall enough that a row cannot straddle three buckets, small enough
        /// that a bucket is never long. Document points.
        private static let bucketHeight = 24.0

        mutating func add(_ line: TransferGuide.TextLine, clipped: Bool) {
            guard !line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            let arriving = Reading(line: line, clipped: clipped)
            let key = Int(line.box.midY / Self.bucketHeight)
            for neighbour in (key - 1)...(key + 1) {
                guard let rows = buckets[neighbour] else { continue }
                for (index, existing) in rows.enumerated()
                where overlaps(existing.line, line) {
                    if prefers(arriving, over: existing) {
                        buckets[neighbour]?[index] = arriving
                    }
                    return
                }
            }
            buckets[key, default: []].append(arriving)
        }

        /// Which of two readings of one row to keep.
        ///
        /// Whole beats sliced, then MORE GLYPHS beats fewer, and only then
        /// does confidence decide. The middle rule is the one the real
        /// screenshots asked for: 北本 came back as `北` from one tile and as
        /// 北本 from the other, both at 0.30, and a station name one character
        /// short of the truth matches nothing. Area rather than character
        /// count, because it measures what the recogniser covered rather than
        /// what it made of it.
        private func prefers(_ arriving: Reading, over existing: Reading) -> Bool {
            if existing.clipped != arriving.clipped { return existing.clipped }
            let grew = area(arriving.line) - area(existing.line)
            // A tenth of a line is noise between two readings of one row.
            if abs(grew) > area(existing.line) * 0.1 { return grew > 0 }
            return arriving.line.confidence > existing.line.confidence
        }

        private func area(_ line: TransferGuide.TextLine) -> Double {
            line.box.width * line.box.height
        }

        /// Whether two boxes are the same row seen twice.
        ///
        /// Measured against the SMALLER box rather than against their union: a
        /// seam sometimes clips a row, and the clipped reading of 新函館北斗 is
        /// a box two thirds the height of the whole one — still the same row,
        /// and still not to be kept alongside it.
        private func overlaps(_ a: TransferGuide.TextLine, _ b: TransferGuide.TextLine) -> Bool {
            let x = min(a.box.maxX, b.box.maxX) - max(a.box.minX, b.box.minX)
            let y = min(a.box.maxY, b.box.maxY) - max(a.box.minY, b.box.minY)
            guard x > 0, y > 0 else { return false }
            let smallest = min(a.box.width * a.box.height, b.box.width * b.box.height)
            guard smallest > 0 else { return false }
            return (x * y) / smallest > 0.5
        }

        func sorted() -> [TransferGuide.TextLine] {
            buckets.values.flatMap { $0 }.map(\.line).sorted {
                $0.box.minY == $1.box.minY ? $0.box.minX < $1.box.minX : $0.box.minY < $1.box.minY
            }
        }
    }
}
