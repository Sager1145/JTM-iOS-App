// swift-tools-version: 6.0
import PackageDescription

// AreaKit: area-scoped railway data capture, problem detection, scratch
// preview and guarded repair writes for the Rail Diagnostics app and the
// headless `jtm-area` CLI. Depends on RailCore (read-only) and InspectionKit.
let package = Package(
    name: "AreaRepair",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AreaKit", targets: ["AreaKit"]),
        .executable(name: "jtm-area", targets: ["jtm-area"]),
    ],
    dependencies: [
        .package(path: "../../../../RailKit"),
        .package(path: "../RailAlignmentInspector/InspectionKit"),
    ],
    targets: [
        .target(name: "AreaKit", dependencies: [
            .product(name: "RailCore", package: "RailKit"),
            .product(name: "RailInspection", package: "InspectionKit"),
        ]),
        .executableTarget(name: "jtm-area", dependencies: [
            "AreaKit",
            .product(name: "RailInspection", package: "InspectionKit"),
        ]),
        .testTarget(name: "AreaKitTests", dependencies: ["AreaKit"],
                    resources: [.copy("Fixtures")]),
    ]
)
