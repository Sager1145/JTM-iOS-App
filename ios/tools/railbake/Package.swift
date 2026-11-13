// swift-tools-version: 6.0
import PackageDescription

// Host-side bake of the prebuilt rail map pack (docs/maintenance/2026-11-12-prebuilt-rail-map-pack.md).
//
// RailBakeKit reads a builder output directory (`build-display-network.py`) and runs the stroke
// engine over a whole region. The engine itself is `RailCore.StrokeBake` / `NetworkStrokeBake`, the
// very code the app draws with; this package owns only the reading of builder output and, in later
// units, the piece cutter and the `RailBake` tool. The app never links it.
//
// It depends on RailKit by path, like `ios/tools/bench`, so it bakes exactly the sources the app
// ships. Run its tests with:
//
//     swift test --package-path ios/tools/railbake --scratch-path /tmp/jtm-railbake
let package = Package(
    name: "RailBake",
    platforms: [.macOS(.v14)],
    products: [.library(name: "RailBakeKit", targets: ["RailBakeKit"])],
    dependencies: [.package(path: "../../RailKit")],
    targets: [
        .target(
            name: "RailBakeKit",
            dependencies: [.product(name: "RailCore", package: "RailKit")]
        ),
        .testTarget(
            name: "RailBakeKitTests",
            dependencies: ["RailBakeKit", .product(name: "RailCore", package: "RailKit")]
        ),
    ]
)
