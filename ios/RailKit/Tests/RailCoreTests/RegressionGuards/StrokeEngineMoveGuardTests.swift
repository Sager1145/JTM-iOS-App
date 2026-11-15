import Foundation
import RailTestSupport
import Testing

/// Pins where the stroke engine lives. It moved out of the app target into RailCore so a host
/// tool can run it (prebuilt rail map pack, unit P1); these keep it from drifting back, and keep
/// the RailCore side free of anything a host cannot import.
@Suite("RegressionGuardStrokeEngineMove")
struct RegressionGuardStrokeEngineMove {
    /// RailCore files that make up the engine, its inputs and its entry points.
    private static let engineFiles = [
        "RailKit/Sources/RailCore/Rendering/StrokeBake.swift",
        "RailKit/Sources/RailCore/Rendering/ScreenPolylineThinning.swift",
        "RailKit/Sources/RailCore/Rendering/NetworkStrokeBake.swift",
        "RailKit/Sources/RailCore/Rendering/StrokeLineInput.swift",
        "RailKit/Sources/RailCore/Rendering/StrokeProjection.swift",
        "RailKit/Sources/RailCore/Rendering/DisplayChunk.swift",
        "RailKit/Sources/RailCore/Rendering/RailStrokeTokens.swift",
        "RailKit/Sources/RailCore/Utilities/GCJ02.swift",
    ]

    @Test("the engine files import no platform UI or map framework")
    func engineIsHostImportable() throws {
        for file in Self.engineFiles {
            let source = try SourceFiles.text(file)
            for forbidden in ["import MapKit", "import CoreLocation", "import SwiftUI", "import UIKit", "import AppKit"] {
                #expect(!source.contains(forbidden), "\(file) must not contain \(forbidden)")
            }
        }
    }

    @Test("the app's map geometry file keeps the adapters and none of the engine")
    func appKeepsNoEngine() throws {
        let geometry = try SourceFiles.text("RailMap/Map/MapLineGeometry.swift")
        for moved in [
            "ContinuousStroke.buildStroke(", "StrokeJunctionIndex(", "func continuousJoin(",
            "func continuousStrokeBuild(", "cancellableDouglasPeuckerIndices", "func joinedChainCoordinates(",
            "final class JoinedChainCache", "final class ChainPixelCache", "struct JunctionCandidateIndex",
            "measuredSliceChunks", "familyPartition(",
        ] {
            #expect(!geometry.contains(moved), "MapLineGeometry.swift must not define or call \(moved)")
        }
        #expect(geometry.contains("StrokeBake.prepareLines("))
        #expect(geometry.contains("StrokeBake.strokeBuild("))
        #expect(geometry.contains("StrokeBake.parallelLaneCoordinates("))
    }

    @Test("RailStyle takes the stroke tokens from RailStrokeTokens, not from literals of its own")
    func styleAliasesTokens() throws {
        let style = try SourceFiles.text("RailMap/Design/RailStyle.swift")
        for alias in [
            "CGFloat(RailStrokeTokens.stationDiameter)", "CGFloat(RailStrokeTokens.railWidth)",
            "CGFloat(RailStrokeTokens.parallelGap)", "CGFloat(RailStrokeTokens.parallelLaneCentreDistance)",
            "CGFloat(RailStrokeTokens.minCornerRadius)", "CGFloat(RailStrokeTokens.strokeCornerRadius)",
            "RailStrokeTokens.strokeMinRamp", "RailStrokeTokens.simplifyTolerance",
            "RailStrokeTokens.minimumCornerRadius(atScale:", "RailStrokeTokens.hardCornerMaxDeviation(atScale:",
            "RailStrokeTokens.fullWeightZoom", "RailStrokeTokens.scale(atZoom:",
        ] {
            #expect(style.contains(alias), "RailStyle must alias \(alias)")
        }
        for literal in [
            "stationDiameter: CGFloat = 6", "parallelGap: CGFloat = 1.2", "strokeMinRamp: Double = 24",
            "simplifyTolerance: Double = 0.0625",
        ] {
            #expect(!style.contains(literal), "RailStyle must not restate \(literal)")
        }
    }

    @Test("the datum shift has one body, in RailCore")
    func gcjHasOneBody() throws {
        let datum = try SourceFiles.text("RailMap/Map/AppleMapDatum.swift")
        #expect(datum.contains("GCJ02.fromWGS84("))
        #expect(!datum.contains("transformLatitude") && !datum.contains("6_378_245"))
        #expect(datum.contains("GCJ02.candidateRegions"))
    }

    @Test("the display chunk document is decoded in one place")
    func chunkDecodedOnce() throws {
        let formats = try SourceFiles.text("RailMap/Infrastructure/Network/RailDisplayNetworkFormats.swift")
        #expect(formats.contains("typealias LineFragment = DisplayChunk.LineFragment"))
        #expect(!formats.contains("struct LineFragment"))
        let store = try SourceFiles.text("RailMap/Infrastructure/Network/RailNetworkStore.swift")
        #expect(store.contains("StrokeLineInput.make("))
    }
}
