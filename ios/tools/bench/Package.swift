// swift-tools-version: 6.0
import PackageDescription

// Micro-benchmarks for the pure tiers.
//
// A separate package rather than a test target, for two reasons. `swift test`
// is the gate and has to stay fast and deterministic; a benchmark is neither.
// And a benchmark that runs under the test runner reports a pass/fail where
// what is wanted is a NUMBER — the before and after of one change, on one
// machine, repeated enough times to have a median.
//
// It depends on RailKit by path, so it measures exactly the sources the app
// ships rather than a copy. Run it in release, which is the only configuration
// whose numbers mean anything:
//
//     cd ios/tools/bench && swift run -c release --scratch-path /tmp/jtm-bench
let package = Package(
    name: "RailBench",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../RailKit")],
    targets: [
        .executableTarget(
            name: "RailBench",
            dependencies: [
                .product(name: "RailCore", package: "RailKit"),
                .product(name: "RailPresentation", package: "RailKit"),
            ]
        )
    ]
)
