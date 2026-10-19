// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "InspectionKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "RailInspection", targets: ["RailInspection"])],
    targets: [
        .target(name: "RailInspection"),
        .testTarget(name: "RailInspectionTests", dependencies: ["RailInspection"])
    ]
)
