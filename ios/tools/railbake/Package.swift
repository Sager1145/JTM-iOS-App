// swift-tools-version: 6.0
import PackageDescription

// Host-side bake of the prebuilt rail map pack (docs/maintenance/2026-11-12-prebuilt-rail-map-pack.md).
//
// RailBakeKit reads a builder output directory (`build-display-network.py`), runs the stroke
// engine over a whole region (`RailCore.StrokeBake` / `NetworkStrokeBake`, the very code the app
// draws with), cuts the finished geometry into tile-homed pieces and assembles the `.railpack`
// source that `RailCore.RailPackWriter` writes. `RailBake` is the command-line tool around it.
// The app never links any of this.
//
// It depends on RailKit by path, like `ios/tools/bench`, so it bakes exactly the sources the app
// ships. Run its tests with:
//
//     swift test --package-path ios/tools/railbake --scratch-path /tmp/jtm-railbake
let package = Package(
    name: "RailBake",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RailBakeKit", targets: ["RailBakeKit"]),
        .executable(name: "RailBake", targets: ["RailBake"]),
    ],
    dependencies: [.package(path: "../../RailKit")],
    targets: [
        .target(
            name: "RailBakeKit",
            dependencies: [
                .product(name: "RailCore", package: "RailKit"),
                .product(name: "RailPresentation", package: "RailKit"),
            ]
        ),
        .executableTarget(name: "RailBake", dependencies: ["RailBakeKit"]),
        .testTarget(
            name: "RailBakeKitTests",
            dependencies: ["RailBakeKit", .product(name: "RailCore", package: "RailKit")]
        ),
    ]
)
