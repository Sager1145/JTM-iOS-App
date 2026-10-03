import CoreGraphics
import Foundation

/// Screen-space paint produced from a single public MapKit camera projection.
/// Colors and opacity belong to the rail scene, independently of the basemap
/// veil behind it. This type does not own camera or canonical rail geometry.
nonisolated struct MapProjectedRailScene {
    struct Stroke {
        let path: CGPath
        let color: CGColor
        let width: CGFloat
        let alpha: CGFloat
        var dash: [CGFloat] = []
    }
    struct Bead {
        let center: CGPoint
        let radius: CGFloat
        let fill: CGColor
        let rim: CGColor
        let rimWidth: CGFloat
        let alpha: CGFloat
        var diamond = false
    }
    var strokes: [Stroke] = []
    var beads: [Bead] = []

    func draw(in context: CGContext) {
        for stroke in strokes {
            context.saveGState()
            context.setAlpha(stroke.alpha)
            context.setStrokeColor(stroke.color)
            context.setLineWidth(stroke.width)
            context.setLineCap(stroke.dash.isEmpty ? .round : .butt)
            context.setLineJoin(.round)
            context.setLineDash(phase: 0, lengths: stroke.dash)
            context.addPath(stroke.path)
            context.strokePath()
            context.restoreGState()
        }
        for bead in beads {
            let box = CGRect(
                x: bead.center.x - bead.radius, y: bead.center.y - bead.radius,
                width: bead.radius * 2, height: bead.radius * 2)
            let shape = CGMutablePath()
            if bead.diamond {
                shape.move(to: CGPoint(x: box.midX, y: box.minY))
                shape.addLine(to: CGPoint(x: box.maxX, y: box.midY))
                shape.addLine(to: CGPoint(x: box.midX, y: box.maxY))
                shape.addLine(to: CGPoint(x: box.minX, y: box.midY))
                shape.closeSubpath()
            } else {
                shape.addEllipse(in: box)
            }
            context.saveGState()
            context.setAlpha(bead.alpha)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            context.setFillColor(bead.fill)
            context.addPath(shape)
            context.fillPath()
            if bead.rimWidth > 0 {
                context.setStrokeColor(bead.rim)
                context.setLineWidth(bead.rimWidth)
                context.addPath(shape)
                context.strokePath()
            }
            context.endTransparencyLayer()
            context.restoreGState()
        }
    }
}
