// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "WorkbenchCore", platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "WorkbenchCore", targets: ["WorkbenchCore"])],
    targets: [.target(name: "WorkbenchCore", resources: [.process("Resources")]), .testTarget(name: "WorkbenchCoreTests", dependencies: ["WorkbenchCore"])])
