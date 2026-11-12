import Foundation

/// The one area trips and lines are prepared for.
///
/// The map builds line geometry for the screen plus half a screen of padding
/// (the "build rect"). A trip segment is searched for in that rect grown by a
/// further ``paddingScreenPoints`` so lane offsets and rounded corners at the
/// edge are covered. Line strokes must be prepared and selected with this same
/// larger rect, otherwise a trip segment inside it can name a chain that was
/// never built and resolve to the raw centreline until its lane arrives.
public enum MapBuildArea {
    /// Screen points added on every side of the build rect.
    public static let paddingScreenPoints: Double = 256

    /// A rect in map points, kept free of MapKit so the rule is testable on the host.
    public struct Rect: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }

    /// The trip-and-line area for `buildRect` at `mapPointsPerScreenPoint`.
    public static func expanded(_ buildRect: Rect, mapPointsPerScreenPoint: Double) -> Rect {
        let pad = paddingScreenPoints * mapPointsPerScreenPoint
        return Rect(
            x: buildRect.x - pad, y: buildRect.y - pad,
            width: buildRect.width + 2 * pad, height: buildRect.height + 2 * pad)
    }
}
