import Foundation
import RailCore

/// The `RailBake` command line. Lives in the library so its argument handling is testable; the
/// executable's `main.swift` only calls ``run(arguments:)``.
///
///     RailBake --builder-dir DIR --region jp --inputs-sha256 HEX --output jp.railpack \
///         [--levels 8...34] [--budgets FILE] [--report]
///     RailBake --report-of jp.railpack
///     RailBake --compare a.railpack b.railpack
public enum RailBakeCommand {

    public static let usage = """
        usage: RailBake --builder-dir DIR --region CODE --inputs-sha256 HEX --output FILE \\
                        [--levels 8...34|8,12,34] [--budgets FILE] [--report]
               RailBake --report-of FILE
               RailBake --compare A B
        (the pack is WGS84; the app shifts it to GCJ-02 when it mounts a level)
        --levels   half-zoom indices k (level zoom k/2); default 8...34, the ladder z4.0 to z17.0
        --budgets  pack-budgets.json: fail (exit 1, nothing written) when the pack's bytes, a level's
                   vertices or a phone or pad view's mounted vertices exceed it (limits record
                   docs/maintenance/2026-11-13-rail-pack-limits.md)
        --report   print bytes, pieces, vertices and tiles per level after the bake
        """

    public struct Failure: Error, CustomStringConvertible {
        public var description: String
    }

    /// Runs one command; returns the process exit status and writes its output to `out`.
    public static func run(arguments: [String], out: @escaping (String) -> Void) -> Int32 {
        do {
            try execute(arguments: arguments, out: out)
            return 0
        } catch let failure as Failure {
            out("RailBake: \(failure.description)")
            return 2
        } catch {
            out("RailBake: \(error)")
            return 1
        }
    }

    /// Opens the finished pack bytes and checks them against the budgets file; throws
    /// `PackBudget.Violation` naming every limit broken.
    static func enforceBudgets(at url: URL, region: String, data: Data) throws {
        let reader = try RailPackReader(data: data)
        try reader.validateContents()
        try PackBudget.load(from: url).check(region: region, report: PackReport(reader: reader))
    }

    static func execute(arguments: [String], out: @escaping (String) -> Void) throws {
        var options: [String: String] = [:]
        var flags: Set<String> = []
        var compare: [String] = []
        var index = 0
        func value(_ name: String) throws -> String {
            index += 1
            guard index < arguments.count else { throw Failure(description: "\(name) needs a value\n\(usage)") }
            return arguments[index]
        }
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--builder-dir", "--region", "--inputs-sha256", "--output", "--levels", "--report-of", "--budgets":
                options[argument] = try value(argument)
            case "--compare":
                compare = [try value(argument), try value(argument)]
            case "--report":
                flags.insert(argument)
            default:
                throw Failure(description: "unknown argument \(argument)\n\(usage)")
            }
            index += 1
        }

        if !compare.isEmpty {
            let a = try RailPackReader(contentsOf: URL(fileURLWithPath: compare[0]))
            let b = try RailPackReader(contentsOf: URL(fileURLWithPath: compare[1]))
            let differences = try PackCompare.differences(a, b)
            if differences.isEmpty {
                out("packs agree: same structure, every vertex within one quantum")
                return
            }
            differences.forEach(out)
            throw Failure(description: "packs differ (\(differences.count) differences listed)")
        }
        if let path = options["--report-of"] {
            out(try PackReport(reader: RailPackReader(contentsOf: URL(fileURLWithPath: path))).text())
            return
        }

        guard let directory = options["--builder-dir"], let region = options["--region"],
              let inputsText = options["--inputs-sha256"], let output = options["--output"] else {
            throw Failure(description: usage)
        }
        guard let inputs = PackBake.hex(inputsText) else { throw Failure(description: "--inputs-sha256 is not 64 hex digits") }
        let levels = try options["--levels"].map(PackBake.parseLevels) ?? PackBake.defaultLevels
        let clock = ContinuousClock()
        var data = Data()
        let elapsed = try clock.measure {
            data = try PackBake.bake(
                region: region, directory: URL(fileURLWithPath: directory), levels: levels,
                inputsSHA256: inputs) { level, count in
                    if level < count { out("level \(level + 1)/\(count)") }
                }
        }
        // Over budget: fail before anything is written.
        if let path = options["--budgets"] { try enforceBudgets(at: URL(fileURLWithPath: path), region: region, data: data) }
        let url = URL(fileURLWithPath: output)
        try data.write(to: url, options: .atomic)
        let reader = try RailPackReader(contentsOf: url)
        try reader.validateContents()
        out("wrote \(output): \(data.count) bytes, \(levels.count) levels, baked in \(elapsed)")
        if flags.contains("--report") { out(try PackReport(reader: reader).text()) }
    }
}
