import Foundation

/// One shell command a guard (or topology regeneration) runs in the repository.
public struct GuardCommand: Codable, Equatable, Sendable {
    public var guardClass: GuardClass?
    /// Arguments for `/bin/bash -c`, run from the repository root.
    public var shell: String
    /// Swift commands run inside the heavy-job lock and must execute ≥1 test.
    public var isSwiftTest: Bool

    public init(guardClass: GuardClass?, shell: String, isSwiftTest: Bool) {
        self.guardClass = guardClass; self.shell = shell; self.isSwiftTest = isSwiftTest
    }
}

public struct GuardCommandResult: Equatable, Sendable {
    public var exitCode: Int32
    public var output: String
    public init(exitCode: Int32, output: String) { self.exitCode = exitCode; self.output = output }
}

/// Runs guard commands. Tests inject results; production uses ``ProcessGuardCommandRunner``.
public protocol GuardCommandRunning: Sendable {
    func run(_ command: GuardCommand, repo: URL) throws -> GuardCommandResult
}

/// The outcome of one guard command.
public struct GuardOutcome: Codable, Equatable, Sendable {
    public var guardClass: GuardClass?
    public var command: String
    public var passed: Bool
    public var exitCode: Int32
    public var executedTests: Int?
    public var reason: String
    public var outputTail: String
}

/// The single table of regression guards per repair class, and the runner.
public struct GuardRunner: Sendable {
    public static let heavyJobLock = "/private/tmp/jtm-heavy-job.lock"
    public static let topologyCheck = "python3 -I ios/tools/build-physical-rail-topology.py --check"
    public static let topologyRegenerate = "python3 -I ios/tools/build-physical-rail-topology.py"

    static func swift(_ filter: String, _ guardClass: GuardClass) -> GuardCommand {
        GuardCommand(guardClass: guardClass, shell: "bash ios/verify.sh swift --filter '\(filter)'", isSwiftTest: true)
    }

    /// Guard commands per class (the one table).
    public static func commands(for guardClass: GuardClass) -> [GuardCommand] {
        switch guardClass {
        case .junction:
            [swift("ShortLinkJunctionTests|JunctionApproachTests|PhysicalTopologyRoutingTests|PhysicalSectionContinuityTests", .junction),
             GuardCommand(guardClass: .junction, shell: topologyCheck, isSwiftTest: false)]
        case .history: [swift("RailHistory|RailValidity", .history)]
        case .paired:
            [swift("OnEdgeCertificationTests|DirectionalAlignmentSelectionTests|RideRouteResolutionTests|RecordedRouteAdmissionTests|RouteBatchInspectionTests", .paired)]
        case .station: [swift("StationDisplayParityTests|PassengerStationApproachTests|PhysicalEndpointTrimTests", .station)]
        case .rounding: [swift("ContinuousStroke", .rounding)]
        }
    }

    public var runner: any GuardCommandRunning
    public init(runner: any GuardCommandRunning = ProcessGuardCommandRunner()) { self.runner = runner }

    /// Runs every command of `classes` in order; never stops early, so the
    /// receipt shows each guard's result.
    public func run(_ classes: [GuardClass], repo: URL) -> [GuardOutcome] {
        classes.flatMap(Self.commands(for:)).map { evaluate($0, repo: repo) }
    }

    /// Runs one command and judges it: exit ≠ 0 fails; a Swift test command
    /// that executed zero tests (or whose count cannot be read) fails.
    public func evaluate(_ command: GuardCommand, repo: URL) -> GuardOutcome {
        let result: GuardCommandResult
        do { result = try runner.run(command, repo: repo) } catch {
            return GuardOutcome(guardClass: command.guardClass, command: command.shell, passed: false, exitCode: -1,
                                executedTests: nil, reason: "could not run: \(error.localizedDescription)", outputTail: "")
        }
        let tail = String(result.output.suffix(4_000))
        let executed = command.isSwiftTest ? Self.executedTestCount(result.output) : nil
        let reason: String
        let passed: Bool
        if result.exitCode != 0 { passed = false; reason = "exit \(result.exitCode)" }
        else if command.isSwiftTest, (executed ?? 0) == 0 { passed = false; reason = "0 tests executed (a filter that selects nothing is not a pass)" }
        else { passed = true; reason = command.isSwiftTest ? "\(executed!) tests passed" : "ok" }
        return GuardOutcome(guardClass: command.guardClass, command: command.shell, passed: passed, exitCode: result.exitCode,
                            executedTests: executed, reason: reason, outputTail: tail)
    }

    /// Total tests executed across swift-testing ("Test run with N tests") and
    /// XCTest ("Executed N tests") summaries; nil when neither appears.
    public static func executedTestCount(_ output: String) -> Int? {
        var total: Int?
        let patterns = [#"Test run with (\d+) tests?"#, #"Executed (\d+) tests?"#]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(output.startIndex..., in: output)
            // XCTest prints a summary per suite; the last one is the total.
            if let match = regex.matches(in: output, range: range).last,
               let r = Range(match.range(at: 1), in: output), let n = Int(output[r]) {
                total = (total ?? 0) + n
            }
        }
        return total
    }
}

/// Runs commands with `/bin/bash -c` from the repository root (macOS only;
/// elsewhere it throws). Swift test
/// commands are wrapped in the shared heavy-job lock so only one heavy build
/// runs on the machine at a time.
public struct ProcessGuardCommandRunner: GuardCommandRunning {
    public init() {}

    public func run(_ command: GuardCommand, repo: URL) throws -> GuardCommandResult {
        #if os(macOS)
        let lock = GuardRunner.heavyJobLock
        let script = command.isSwiftTest
            ? "until mkdir \(lock) 2>/dev/null; do sleep 20; done; trap 'rmdir \(lock)' EXIT; DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \(command.shell)"
            : command.shell
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script]
        process.currentDirectoryURL = repo
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return GuardCommandResult(exitCode: process.terminationStatus, output: String(decoding: output, as: UTF8.self))
        #else
        // Foundation.Process is unavailable on iOS / Mac Catalyst; run guards through the jtm-area CLI.
        throw AreaRepairError.refused("guard commands can only run on macOS (use the jtm-area CLI).")
        #endif
    }
}
