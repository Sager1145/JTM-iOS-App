import Foundation
import Testing

/// Source guards for the annotation-churn fixes: level changes keep and move
/// annotations, overlay-drawn trip dots are not map annotations, and stacking
/// is written only when it changes. They read app sources, so they live in RailKit.
@Suite("RegressionGuardAnnotationChurn")
struct RegressionGuardAnnotationChurn {
    private static func source(_ path: String) -> String {
        let ios = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // RegressionGuards
            .deletingLastPathComponent() // RailCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // RailKit
            .deletingLastPathComponent() // ios
        return (try? String(contentsOf: ios.appendingPathComponent(path), encoding: .utf8)) ?? ""
    }

    @Test func theReconcilerMatchesThroughTheRailKitDiffAndKeysCarryNoCoordinate() {
        let text = Self.source("RailMap/Map/MapAnnotationReconciler.swift")
        #expect(text.contains("AnnotationDiff.make("))
        #expect(!text.contains("item.coordinate.latitude)|"))
        #expect(!text.contains("keyIgnoringCoordinate"))
        #expect(text.contains("private func updateInPlace("))
    }

    @Test func overlayDrawnTripDotsAreNotAddedAsAnnotations() throws {
        let text = Self.source("RailMap/Map/RailMapCoordinator.swift")
        #expect(text.contains("func placeDot(_ dot: RideStationAnnotation)"))
        #expect(text.contains("if dot.drawsInOverlay { overlayDots.append(dot) }"))
        #expect(!text.contains("markerAnnotations.append(annotation)"))
        #expect(!text.contains("markerAnnotations.append(RideStationAnnotation("))
        #expect(text.contains("Dictionary(grouping: overlayRideDots, by: \\.rideID)"))
        // Their touch target is answered on the tap, never per frame.
        #expect(text.contains("tappedOverlayRideDot(at: point, on: mapView)"))
        #expect(text.contains("DotHitTest.hit("))
    }

    @Test func stackingIsWrittenOnlyWhenItDiffers() {
        for path in ["RailMap/Map/StationAnnotationViews.swift", "RailMap/Map/JourneyLabelAnnotationViews.swift"] {
            let text = Self.source(path)
            #expect(text.contains("if layer.zPosition != "), Comment(rawValue: path))
            #expect(text.contains("if zPriority != "), Comment(rawValue: path))
            #expect(!text.contains("\n        layer.zPosition = "), Comment(rawValue: path))
        }
    }
}
