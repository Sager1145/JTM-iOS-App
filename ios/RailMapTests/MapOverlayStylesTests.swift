import MapKit
import QuartzCore
import Testing
import UIKit
@testable import RailMap

private final class RedrawSpyRenderer: MKMultiPolylineRenderer {
    var redrawRequests = 0
    override func setNeedsDisplay() {
        redrawRequests += 1
        super.setNeedsDisplay()
    }
}

@MainActor
struct MapOverlayStylesTests {
    private func renderer() -> RedrawSpyRenderer {
        let points = [CLLocationCoordinate2D(latitude: 33.087, longitude: 129.801),
                      CLLocationCoordinate2D(latitude: 33.086, longitude: 129.802)]
        let line = MKPolyline(coordinates: points, count: points.count)
        return RedrawSpyRenderer(multiPolyline: MKMultiPolyline([line]))
    }

    @Test func opacityOnlyRescaleInvalidatesPreviouslyTransparentTiles() {
        let styles = MapOverlayStyles(), renderer = renderer(), key = "network|test"
        defer { styles.removeAll() }
        styles[key] = .init(color: .cyan, widthToken: 1.5, alpha: 0)
        styles.remember(renderer, forKey: key)
        styles.rescale(to: 1)
        renderer.redrawRequests = 0
        styles[key] = .init(color: .cyan, widthToken: 1.5, alpha: 1)
        styles.rescale(to: 1)
        #expect(renderer.alpha == 1)
        #expect(renderer.lineWidth == 1.5)
        #expect(renderer.strokeColor == .cyan)
        #expect(renderer.redrawRequests > 0)
        renderer.redrawRequests = 0
        styles.rescale(to: 1)
        #expect(renderer.redrawRequests == 0)
    }

    @Test func delayedRendererFadeCompletionInvalidatesItsTransparentTiles() {
        let styles = MapOverlayStyles(), renderer = renderer(), key = "network|test"
        defer { styles.removeAll() }
        var completions = 0
        styles[key] = .init(color: .cyan, widthToken: 1.5, alpha: 1)
        styles.animateOpacity(forKey: key, duration: 10, fromAlpha: 0) { completions += 1 }
        styles.remember(renderer, forKey: key)
        #expect(renderer.alpha >= 0 && renderer.alpha < 0.00001)
        renderer.redrawRequests = 0
        styles.advanceOpacity(at: CACurrentMediaTime() + 20)
        #expect(renderer.alpha == 1)
        #expect(renderer.redrawRequests > 0)
        #expect(completions == 1)
        styles.advanceOpacity(at: CACurrentMediaTime() + 30)
        #expect(completions == 1)
    }
}
