import UIKit

/// An operator's badge, from the web tables' own path to a decoded image.
///
/// Lived on the map's station-callout builder until the callout became a card
/// in a sheet (`StationCardView`). It is here rather than there because the
/// rule it applies belongs to the artwork and not to whoever is drawing it:
/// one table names the files, and every surface that shows a badge has to
/// resolve a name the same way or the two disagree about which operators have
/// a mark at all.
///
/// `@MainActor` because that is where it is read from — a SwiftUI view body,
/// and before that an `MKAnnotationView` — and because the decoded-image cache
/// is shared mutable state that would otherwise need a lock of its own to say
/// so. `NSCache` is thread-safe, but "thread-safe" is not what the compiler is
/// asking; it is asking who owns it.
@MainActor
enum OperatorBadge {

    /// A web path — `/rail/logos/<id>.png` — resolved in the bundle.
    ///
    /// The ported rule returns the path the JavaScript hands to an `<img>`, so
    /// the leading slash is stripped and the rest used as-is. Keeping the web's
    /// own directory names is what lets one table serve both clients; inventing
    /// a second naming scheme here would be a second thing to keep in step.
    ///
    /// With one exception, and it is not a naming scheme: **ImageIO has no SVG
    /// decoder on iOS**, and 95 of the files the tables name are SVG. An
    /// `<img>` renders them; `UIImage` returns nil, and the row silently falls
    /// back to a colour swatch — which is what about a quarter of them did.
    /// `rasterize-badge-svgs.swift` writes a PNG beside each one under the
    /// SVG's own name plus `.png`, so the fix is to append four characters to
    /// the answer the table already gave. The table still decides.
    ///
    /// macOS *does* decode SVG, which is why this survived review: the artwork
    /// opens in Preview, in Xcode, and under `sips`, and only the simulator and
    /// the device disagree.
    static func image(_ path: String?) -> UIImage? {
        guard let path, !path.isEmpty else { return nil }
        if let cached = cache.object(forKey: path as NSString) { return cached }
        let relative = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let decodable = relative.hasSuffix(".svg") ? relative + ".png" : relative
        guard let url = Bundle.main.resourceURL?.appending(path: decodable),
              let image = UIImage(contentsOfFile: url.path)
        else { return nil }
        cache.setObject(image, forKey: path as NSString)
        return image
    }

    /// A station complex can list a dozen railways and a reader opens one
    /// station card after another, so the same handful of badges is decoded
    /// over and over without this.
    private static let cache = NSCache<NSString, UIImage>()

    /// Whether a mark paints its own ground out to the edge of a near-square
    /// canvas — a line badge like 東武's TN square or 台北捷運's red R — rather
    /// than being a glyph that needs a tile behind it.
    ///
    /// It decides one thing in ``RouteLogoSquare``: how much of the tile the
    /// mark is given. A block is a shape already — it brings its own ground
    /// and its own corners — so at equal size it weighs more on the page than
    /// a bare glyph does, and it is drawn to a wider box. It is NOT drawn out
    /// to the tile's edge: a badge with no margin left the tile invisible
    /// behind it, which is what made 山手線's JY run its own white border
    /// straight into the rounded edge of the square it sits in.
    ///
    /// Measured from the artwork rather than listed in a table, because a
    /// table is a second thing to update when a package ships new line art —
    /// and the measurement is unambiguous. Every badge in the repository was
    /// run through it (507 files): the ring coverage is bimodal, 0.0–0.40 for
    /// glyphs and wordmarks and 0.60–1.00 for blocks, with three files in
    /// between and none at all between 0.50 and 0.65. So the threshold sits in
    /// a gap rather than on a slope, and the widest-cornered square in the set
    /// (台中捷運's, at 0.65) lands on the block side where it belongs.
    ///
    /// The aspect bound is what keeps a long wordmark on a coloured bar out:
    /// those are opaque to the edge too, and stretching one to fill a square
    /// would crop the name it spells.
    static func fillsItsBox(_ path: String?) -> Bool { shape(path).fillsItsBox }

    /// What the artwork's own pixels say about how to mount it.
    ///
    /// Neither field moves the mark out to the tile's edge any more. A block
    /// used to fill the square outright, which cropped it: `scaledToFill`
    /// trimmed whichever axis was long, and across the 190 files `fillsItsBox`
    /// claims that took pixels off 54 of them — up to 8.5 % of an axis on
    /// 鹿児島市's badge, and through the mark itself rather than through its
    /// ground on nine, worst of them 甘木鉄道 at 4.1 % of its own content.
    /// ``RouteLogoSquare`` crops nothing now: a block FITS the square instead,
    /// which leaves a bar on the short axis, and the bar has to be the colour
    /// the badge already paints its own edge — otherwise a coloured square
    /// sits on two slivers of system grey and reads as a mistake.
    struct Shape {
        var fillsItsBox: Bool
        /// The one colour the artwork paints its own border in, or `nil` where
        /// it paints its border in more than one — a glyph on transparency, or
        /// a block whose edge carries part of the mark rather than its ground.
        var edgeColor: UIColor?
        /// Where the mark actually is inside its canvas, in unit coordinates.
        ///
        /// The canvases are not consistently padded and never were: 立山黒部貫光's
        /// badge leaves the top 40 % of its file empty, 野岩鉄道's leaves the
        /// left 35 %, twelve 西武鉄道 line badges run flush to the top and stop
        /// 3 % short of the bottom, and the seven 名古屋市 subway badges are
        /// flush on three sides with a 14 % gap on the fourth. Fitting the
        /// CANVAS into a tile therefore centres the padding rather than the
        /// mark, and a row of them reads as a row of marks each nudged a
        /// different way. Fitting this instead is what makes them line up.
        var inkBounds: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    }

    static func shape(_ path: String?) -> Shape {
        guard let path, !path.isEmpty else { return Shape(fillsItsBox: false) }
        if let cached = shapeCache.object(forKey: path as NSString) { return cached.shape }
        let answer = image(path).map(measure) ?? Shape(fillsItsBox: false)
        shapeCache.setObject(Measured(answer), forKey: path as NSString)
        return answer
    }

    private static func measure(_ image: UIImage) -> Shape {
        guard let cg = image.cgImage, cg.width > 0, cg.height > 0 else {
            return Shape(fillsItsBox: false)
        }
        let ink = measureInkBounds(cg)
        let none = Shape(fillsItsBox: false, inkBounds: ink)
        let aspect = CGFloat(cg.width) / CGFloat(cg.height)
        guard aspect >= 0.86, aspect <= 1.16 else { return none }

        // Redrawn small on purpose: this asks whether the artwork covers its
        // border, which survives being answered at 24 points a side, and the
        // whole measurement is then 2 KB of scratch rather than a full-size
        // bitmap per badge.
        let side = 24
        let border = 2
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side,
                bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return none }

        var opaque: [(r: Double, g: Double, b: Double)] = []
        var total = 0
        for y in 0..<side {
            for x in 0..<side {
                guard x < border || y < border || x >= side - border || y >= side - border
                else { continue }
                total += 1
                let base = (y * side + x) * 4
                let alpha = Double(pixels[base + 3])
                guard alpha > 128 else { continue }
                // The bitmap is premultiplied, so a component has to be
                // divided back out by its own alpha before it means a colour.
                opaque.append((
                    Double(pixels[base]) / alpha,
                    Double(pixels[base + 1]) / alpha,
                    Double(pixels[base + 2]) / alpha))
            }
        }
        guard total > 0, Double(opaque.count) / Double(total) >= 0.60 else { return none }
        return Shape(fillsItsBox: true, edgeColor: uniformColor(of: opaque), inkBounds: ink)
    }

    /// The one colour a border is painted in, or nil if it is painted in more
    /// than one.
    ///
    /// The tolerance is what keeps a badge whose edge carries part of the mark
    /// — a wordmark bleeding into the corner, a two-tone square — from being
    /// averaged into a colour that appears nowhere in it. Such a badge simply
    /// gets no bar colour and falls back to the tile, which is the honest
    /// answer rather than an invented one.
    private static func uniformColor(
        of samples: [(r: Double, g: Double, b: Double)]
    ) -> UIColor? {
        guard !samples.isEmpty else { return nil }
        let count = Double(samples.count)
        let mean = samples.reduce(into: (r: 0.0, g: 0.0, b: 0.0)) {
            $0.r += $1.r / count
            $0.g += $1.g / count
            $0.b += $1.b / count
        }
        let tolerance = 24.0 / 255
        let agreeing = samples.filter {
            abs($0.r - mean.r) <= tolerance
                && abs($0.g - mean.g) <= tolerance
                && abs($0.b - mean.b) <= tolerance
        }
        guard Double(agreeing.count) / count >= 0.80 else { return nil }
        return UIColor(red: mean.r, green: mean.g, blue: mean.b, alpha: 1)
    }

    /// The unit rectangle the artwork's non-transparent pixels occupy.
    ///
    /// A second draw rather than a wider read of the 24-point one above: that
    /// bitmap answers a yes/no question about a border and its resolution was
    /// chosen for that, while a bounding box read off it would be quantised to
    /// 4 % — a point and a half of error on a 36-point mark. 64 is 1.6 %, and
    /// still 16 KB of scratch, computed once per badge for the life of the
    /// process. Squashing a non-square canvas into a square bitmap is what
    /// makes the answer come out in unit coordinates directly.
    ///
    /// The threshold is low on purpose. Antialiasing and soft shadows put a
    /// long tail of nearly-transparent pixels around a mark, and a cut-off
    /// high enough to ignore them would also trim the feathered edge of the
    /// mark itself and scale the artwork up past its own outline.
    private static func measureInkBounds(_ cg: CGImage) -> CGRect {
        let whole = CGRect(x: 0, y: 0, width: 1, height: 1)
        let side = 64
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side,
                bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return whole }

        var minX = side, minY = side, maxX = -1, maxY = -1
        for y in 0..<side {
            for x in 0..<side where pixels[(y * side + x) * 4 + 3] > 12 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return whole }
        // No flip. A bitmap context's user space has its origin at the bottom
        // left, which invites one — but its BUFFER is stored top row first and
        // `draw(_:in:)` accounts for the difference, so row 0 here is the top
        // of the artwork and matches the direction SwiftUI offsets in. Checked
        // rather than reasoned about: a four-pixel image inked along its top
        // row comes back with buffer row 0 inked.
        let unit = 1.0 / CGFloat(side)
        return CGRect(
            x: CGFloat(minX) * unit,
            y: CGFloat(minY) * unit,
            width: CGFloat(maxX - minX + 1) * unit,
            height: CGFloat(maxY - minY + 1) * unit)
    }

    /// One answer per path, for the same reason ``cache`` exists: a list
    /// redraws its rows constantly and the shape of a badge never changes.
    private static let shapeCache = NSCache<NSString, Measured>()

    /// `NSCache` stores objects, and ``Shape`` is a value. This is the box.
    private final class Measured {
        let shape: Shape
        init(_ shape: Shape) { self.shape = shape }
    }

    /// The matte a handful of marks need, and only they.
    ///
    /// Not decoration and not a theme rule: a few operators' current mark is
    /// drawn predominantly in WHITE because their own site puts it on a dark
    /// header. `OperatorBranding.logoNeedsDarkMatte` names them, and the
    /// original artwork then stays legible in both appearances.
    static let matte = UIColor(
        red: 0x24 / 255, green: 0x31 / 255, blue: 0x3a / 255, alpha: 1)
}
