// swift-tools-version: 6.0
import PackageDescription

// RailKit keeps platform-independent code in three compiler-enforced modules:
// RailCore: domain/data algorithms using Foundation and read-only SQLite.
// RailPresentation: display rules depending on RailCore, without UIKit or SwiftUI.
// RailApplication: snapshot use cases depending on RailCore, independent of presentation.
// RailMap owns native UI, MapKit, stores and platform side effects. Feature directories
// within each target do not change the module boundaries or Resources locations.
let package = Package(
    name: "RailKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RailCore", targets: ["RailCore"]),
        .library(name: "RailPresentation", targets: ["RailPresentation"]),
        .library(name: "RailApplication", targets: ["RailApplication"]),
    ],
    targets: [
        .target(
            name: "RailCore",
            resources: [.process("Resources")],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(name: "RailPresentation", dependencies: ["RailCore"]),
        .target(name: "RailApplication", dependencies: ["RailCore"]),
        .testTarget(name: "RailCoreTests", dependencies: ["RailCore"]),
        .testTarget(name: "RailPresentationTests", dependencies: ["RailPresentation"]),
        .testTarget(name: "RailApplicationTests", dependencies: ["RailApplication", "RailCore"]),
    ]
)
