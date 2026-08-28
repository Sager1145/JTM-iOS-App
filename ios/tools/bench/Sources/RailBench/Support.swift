import Foundation
import RailCore

/// Where the repository is, found the way `PortFixtures` finds it.
enum Repo {
    static func root(from file: StaticString = #filePath) -> URL {
        var directory = URL(filePath: "\(file)").deletingLastPathComponent()
        for _ in 0..<10 {
            if FileManager.default.fileExists(
                atPath: directory.appending(path: "port-fixtures").path) {
                return directory
            }
            directory = directory.deletingLastPathComponent()
        }
        fatalError("repository root not found from \(file)")
    }
}

/// One measurement: the median and the 95th percentile of `repeats` runs.
///
/// Median rather than mean because a benchmark on a machine with other work on
/// it has a long right tail, and p95 rather than max because the maximum of a
/// handful of runs is a sample of the scheduler rather than of the code.
struct Timing {
    var name: String
    var samples: [Double]   // seconds

    var median: Double { percentile(0.5) }
    var p95: Double { percentile(0.95) }
    var min: Double { samples.min() ?? 0 }

    func percentile(_ fraction: Double) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sorted = samples.sorted()
        let index = Swift.min(
            sorted.count - 1,
            Swift.max(0, Int((Double(sorted.count - 1) * fraction).rounded())))
        return sorted[index]
    }

    var line: String {
        String(
            format: "%-52@  median %9.3f ms   p95 %9.3f ms   min %9.3f ms",
            name as NSString, median * 1000, p95 * 1000, min * 1000)
    }
}

/// Run `body` `repeats` times after `warmup` untimed runs.
///
/// The result is consumed through `blackHole` so the optimiser cannot delete
/// the work being measured — the classic way a micro-benchmark reports zero.
@discardableResult
func measure(
    _ name: String, repeats: Int = 9, warmup: Int = 2, _ body: () -> Int
) -> Timing {
    for _ in 0..<warmup { blackHole(body()) }
    var samples: [Double] = []
    samples.reserveCapacity(repeats)
    for _ in 0..<repeats {
        let started = DispatchTime.now().uptimeNanoseconds
        blackHole(body())
        let ended = DispatchTime.now().uptimeNanoseconds
        samples.append(Double(ended - started) / 1_000_000_000)
    }
    let timing = Timing(name: name, samples: samples)
    print(timing.line)
    return timing
}

@inline(never)
func blackHole<T>(_ value: T) {
    withExtendedLifetime(value) {}
}
