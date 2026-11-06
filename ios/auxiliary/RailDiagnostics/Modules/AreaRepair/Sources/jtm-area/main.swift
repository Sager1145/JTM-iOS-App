import Foundation
import AreaKit
import RailInspection

// jtm-area: headless area capture, problem detection, scratch preview and
// guarded repair writes. Every verb prints one compact JSON object on stdout.
// Exit: 0 ok, 2 invalid input or refused, 4 problems / guard failure, 1 internal error.

struct CLIError: Error { var message: String; var code: Int32 = 2 }

// MARK: output

func emit(_ object: Any) {
    let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
    print(String(decoding: data, as: UTF8.self))
}

func fail(_ message: String, code: Int32 = 2) -> Never {
    emit(["error": message])
    exit(code)
}

func prettyEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return encoder
}

func seconds(_ duration: Duration) -> Double {
    (Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15).rounded() / 1000
}

// MARK: arguments

struct Options {
    var values: [String: [String]] = [:]
    var flags: Set<String> = []

    func one(_ name: String) -> String? { values[name]?.last }
    func many(_ name: String) -> [String] { values[name] ?? [] }
    func number(_ name: String) throws -> Double? {
        guard let text = one(name) else { return nil }
        guard let value = Double(text), value.isFinite else { throw CLIError(message: "--\(name) must be a number, got \(text).") }
        return value
    }

    static func parse(_ args: [String], valueFlags: Set<String>, boolFlags: Set<String>) throws -> Options {
        var options = Options()
        var index = 0
        while index < args.count {
            var arg = args[index]
            index += 1
            guard arg.hasPrefix("--") else { throw CLIError(message: "Unexpected argument \(arg); options start with --.") }
            arg.removeFirst(2)
            var inline: String?
            if let eq = arg.firstIndex(of: "=") {
                inline = String(arg[arg.index(after: eq)...])
                arg = String(arg[..<eq])
            }
            if boolFlags.contains(arg) {
                guard inline == nil else { throw CLIError(message: "--\(arg) takes no value.") }
                options.flags.insert(arg)
            } else if valueFlags.contains(arg) {
                if let inline { options.values[arg, default: []].append(inline) }
                else {
                    guard index < args.count else { throw CLIError(message: "--\(arg) needs a value.") }
                    options.values[arg, default: []].append(args[index])
                    index += 1
                }
            } else {
                throw CLIError(message: "Unknown option --\(arg).")
            }
        }
        return options
    }
}

/// Inline JSON when the text starts with `{` or `[`, else a file path.
func jsonData(_ text: String) throws -> Data {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") { return Data(trimmed.utf8) }
    do { return try Data(contentsOf: URL(fileURLWithPath: trimmed)) }
    catch { throw CLIError(message: "Cannot read \(trimmed).") }
}

func fileURL(_ path: String) -> URL { URL(fileURLWithPath: path).standardizedFileURL }

// MARK: shared flag sets and help

let selectorValueFlags: Set<String> = ["stations", "line", "intervals", "rect", "centre", "radius", "margin", "area"]
let dataValueFlags: Set<String> = ["repo", "overlay", "journeys", "thresholds", "zoom", "out"]
let dataBoolFlags: Set<String> = ["no-default-rides", "help"]

let selectorHelp = """
  Selector (exactly one):
    --stations LINE:A-B        station IDs or station names on that line
    --line LINE --intervals a-b   display interval range
    --rect minLon,minLat,maxLon,maxLat
    --centre lon,lat --radius METRES
    --area JSON|FILE           an AreaSelection object
  --margin M                   metres around the area (default 500)
"""
let dataHelp = """
  --repo DIR                   repository root (default: discovered from the working directory)
  --overlay DIR                read patched data files from a scratch overlay
  --journeys FILE              extra journey store; repeatable
  --no-default-rides           skip app/data/sample-data and default-trains.json
  --thresholds JSON|FILE       override any AreaThresholds keys
  --zoom Z                     rounding/geometry zoom (default 15)
"""

let helpText: [String: String] = [
    "capture-data": """
    jtm-area capture-data <selector> --out DIR [options]
      Writes DIR/area-evidence.json (jtm-area-evidence-v1, no views) and prints a summary.
    \(selectorHelp)
    \(dataHelp)
    """,
    "problems": """
    jtm-area problems <selector> [--out DIR] [--propose PATCH.json] [options]
      Lists detected problems; --out also writes DIR/problems.json. --propose writes a draft
      patch with every proposal; reason and source are blanked (the patch fails validation
      until a reason and at least one source are filled). Exit 4 if any error/warning problem.
    \(selectorHelp)
    \(dataHelp)
    """,
    "apply": """
    jtm-area apply --patch FILE --scratch DIR [--repo DIR]
      Materialises the patch into a scratch overlay (the repository is not touched).
    """,
    "preview": """
    jtm-area preview --patch FILE [<selector>] --out DIR [options]
      Baseline vs patched: ride certification, problems cleared/introduced. Writes
      DIR/preview.json and DIR/area-evidence.json (patched state). Selector defaults to the patch area.
    \(selectorHelp)
    \(dataHelp)
    """,
    "write": """
    jtm-area write --patch FILE [--confirm] [--allow-generated] [--patch-dir DIR] [--repo DIR]
      Without --confirm prints the dry-run plan and exits 2 having written nothing.
      Default patch dir: <evidence root>/area-repairs/<patch id> (RAILWAY_EVIDENCE_ROOT or the
      mounted /Volumes/JTM Evidence archive).
    """,
    "undo": """
    jtm-area undo --receipt FILE --confirm [--repo DIR]
      Restores the files of a written receipt from its backups, then re-runs the guards.
    """,
    "guard": """
    jtm-area guard --patch FILE [--dry-run] [--repo DIR]
      Prints (--dry-run) or runs the regression guard commands for the patch's op classes.
    """,
]

let topHelp = """
usage: jtm-area <capture-data|problems|apply|preview|write|undo|guard> [options]
  jtm-area <verb> --help for a verb's options. Output: one compact JSON object on stdout.
  Exit: 0 ok, 2 invalid input or refused, 4 problems or guard failure, 1 internal error.
"""

// MARK: data helpers

func repoURL(_ options: Options) throws -> URL {
    if let repo = options.one("repo") { return fileURL(repo) }
    return try DataRoot.discoverRepo(from: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
}

func loadData(_ options: Options, overlay: URL? = nil) throws -> AreaData {
    let overlayURL = overlay ?? options.one("overlay").map(fileURL)
    return try AreaData.load(DataRoot(repo: try repoURL(options), overlay: overlayURL))
}

func thresholds(_ options: Options) throws -> AreaThresholds {
    guard let text = options.one("thresholds") else { return .default }
    do { return try JSONDecoder().decode(AreaThresholds.self, from: try jsonData(text)) }
    catch let error as CLIError { throw error }
    catch { throw CLIError(message: "Invalid --thresholds: \(error.localizedDescription)") }
}

func zoom(_ options: Options) throws -> Double { try options.number("zoom") ?? 15 }

func hasSelector(_ options: Options) -> Bool { !selectorValueFlags.intersection(options.values.keys).subtracting(["margin", "intervals", "radius"]).isEmpty }

/// Builds the selection; station names on `--stations` resolve against the loaded data.
func selection(_ options: Options, data: AreaData) throws -> AreaSelection {
    let primary = ["stations", "line", "rect", "centre", "area"].filter { options.values[$0] != nil }
    guard primary.count == 1 else {
        throw CLIError(message: "Give exactly one of --stations, --line (with --intervals), --rect, --centre (with --radius), --area.")
    }
    var result: AreaSelection
    do {
        switch primary[0] {
        case "stations":
            let text = options.one("stations")!
            guard let colon = text.lastIndex(of: ":") else { throw CLIError(message: "--stations expects LINE:A-B.") }
            let lineID = String(text[..<colon])
            let ends = text[text.index(after: colon)...].split(separator: "-", maxSplits: 1).map(String.init)
            guard ends.count == 2 else { throw CLIError(message: "--stations expects LINE:A-B.") }
            guard let line = data.linesByID[lineID] else { throw CLIError(message: "Unknown line \(lineID).") }
            func resolve(_ ref: String) throws -> String {
                if line.stations.contains(where: { $0.id == ref }) { return ref }
                let hits = line.stations.filter { $0.name == ref }
                guard hits.count == 1 else {
                    throw CLIError(message: hits.isEmpty ? "No station \(ref) on \(lineID)." : "Station name \(ref) matches \(hits.count) stations on \(lineID); use a station ID.")
                }
                return hits[0].id
            }
            result = AreaSelection(mode: .stationPair(lineID: lineID, fromStationID: try resolve(ends[0]), toStationID: try resolve(ends[1])))
        case "line":
            guard let range = options.one("intervals") else { throw CLIError(message: "--line needs --intervals FIRST-LAST.") }
            let ends = range.split(separator: "-", maxSplits: 1).compactMap { Int($0) }
            guard ends.count == 2 else { throw CLIError(message: "--intervals expects FIRST-LAST integers.") }
            result = AreaSelection(mode: .lineSection(lineID: options.one("line")!, firstInterval: ends[0], lastInterval: ends[1]))
        case "rect":
            let v = options.one("rect")!.split(separator: ",", omittingEmptySubsequences: false).map { Double($0) }
            guard v.count == 4, v.allSatisfy({ $0 != nil }) else { throw CLIError(message: "--rect expects minLon,minLat,maxLon,maxLat.") }
            result = AreaSelection(mode: .rect(minLon: v[0]!, minLat: v[1]!, maxLon: v[2]!, maxLat: v[3]!))
        case "centre":
            let v = options.one("centre")!.split(separator: ",", omittingEmptySubsequences: false).map { Double($0) }
            guard v.count == 2, v.allSatisfy({ $0 != nil }) else { throw CLIError(message: "--centre expects lon,lat.") }
            guard let radius = try options.number("radius") else { throw CLIError(message: "--centre needs --radius METRES.") }
            result = AreaSelection(mode: .centre(lon: v[0]!, lat: v[1]!, radiusMetres: radius))
        default:
            result = try JSONDecoder().decode(AreaSelection.self, from: try jsonData(options.one("area")!))
        }
        if let margin = try options.number("margin") { result.marginMetres = margin }
        try result.validate()
    } catch let error as CLIError { throw error }
    catch { throw CLIError(message: error.localizedDescription) }
    return result
}

func rideSources(_ options: Options, root: DataRoot) -> [RideSource] {
    (options.flags.contains("no-default-rides") ? [] : RideSource.defaults(root))
        + options.many("journeys").map { RideSource.store(fileURL($0)) }
}

func loadPatch(_ options: Options) throws -> AreaPatch {
    guard let path = options.one("patch") else { throw CLIError(message: "--patch FILE is required.") }
    let data: Data
    do { data = try Data(contentsOf: fileURL(path)) } catch { throw CLIError(message: "Cannot read patch \(path).") }
    return try AreaPatch.decode(data)
}

func required(_ options: Options, _ name: String) throws -> String {
    guard let value = options.one(name) else { throw CLIError(message: "--\(name) is required.") }
    return value
}

func problemRow(_ problem: Problem) -> [String: Any] {
    var row: [String: Any] = [
        "id": problem.id, "kind": problem.kind.rawValue, "severity": problem.severity.rawValue,
        "lines": problem.lineIDs, "measure": problem.measure, "message": problem.message,
        "hasProposal": problem.proposal != nil,
    ]
    if let station = problem.stationCode { row["station"] = station }
    return row
}

func countsByKind(_ problems: [Problem]) -> [String: Int] {
    Dictionary(grouping: problems, by: { $0.kind.rawValue }).mapValues(\.count)
}

/// Patch guard classes: the patch's own plus those its ops imply.
func guardClasses(_ patch: AreaPatch) -> [GuardClass] {
    var classes = patch.guards
    for implied in AreaPatch.guards(for: patch.ops) where !classes.contains(implied) { classes.append(implied) }
    return classes
}

func outcomeRow(_ outcome: GuardOutcome) -> [String: Any] {
    var row: [String: Any] = ["command": outcome.command, "passed": outcome.passed, "reason": outcome.reason, "exitCode": Int(outcome.exitCode)]
    if let guardClass = outcome.guardClass { row["class"] = guardClass.rawValue }
    if let tests = outcome.executedTests { row["executedTests"] = tests }
    if !outcome.passed { row["outputTail"] = outcome.outputTail }
    return row
}

func evidenceRoot() -> URL? {
    if let override = ProcessInfo.processInfo.environment["RAILWAY_EVIDENCE_ROOT"], !override.isEmpty {
        return URL(fileURLWithPath: override, isDirectory: true).standardizedFileURL
    }
    // Mirrors RailwayEvidenceRoot.canonicalRoot (RailInspection), only when the archive is mounted.
    let volume = "/Volumes/JTM Evidence"
    guard FileManager.default.fileExists(atPath: volume) else { return nil }
    return URL(fileURLWithPath: volume + "/99 Compatibility/Workspace/JTM-iOS-App/railway-evidence/local", isDirectory: true)
}

// MARK: verbs

func captureData(_ options: Options, problemsOnly: Bool) throws -> Int32 {
    let clock = ContinuousClock()
    let start = clock.now
    let data = try loadData(options)
    let scope = try AreaScope.resolve(try selection(options, data: data), data: data)
    let limits = try thresholds(options)
    let trains = RideSelection.ridesCrossing(scope, trains: try RideSelection.loadTrains(rideSources(options, root: data.root)), data: data)
    let problems = AreaProblems.detect(scope: scope, data: data, trains: trains, thresholds: limits)
    let out = options.one("out").map(fileURL)

    if problemsOnly {
        if let out {
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            try prettyEncoder().encode(problems).write(to: out.appending(path: "problems.json"), options: .atomic)
        }
        var summary: [String: Any] = ["problems": problems.map(problemRow), "count": problems.count, "byKind": countsByKind(problems),
                                      "rides": trains.count, "elapsed": seconds(clock.now - start)]
        if let propose = options.one("propose") {
            let ops = problems.compactMap(\.proposal)
            guard !ops.isEmpty else { throw CLIError(message: "No problem in this area has a repair proposal.") }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            var draft = ops
            for index in draft.indices { draft[index].reason = ""; draft[index].source = [] }
            let patch = AreaPatch(id: "area-propose-" + formatter.string(from: Date()), area: scope.selection, ops: draft)
            let url = fileURL(propose)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try patch.encoded().write(to: url, options: .atomic)
            summary["patch"] = url.path
            summary["needsReview"] = "Every op has an empty reason and source; fill both before preview-to-write (write validates them)."
            summary["hints"] = ops.map { ["key": $0.key, "op": $0.op.rawValue, "proposedReason": $0.reason] as [String: String] }
        }
        emit(summary)
        return problems.contains { $0.severity == .error || $0.severity == .warning } ? 4 : 0
    }

    let out2 = try required(options, "out")
    let rides = RideOutcome.resolve(trains, data: data, scope: scope)
    let evidence = try AreaEvidence.make(data: data, scope: scope, rides: rides, problems: problems, zoom: try zoom(options))
    let written = try evidence.write(to: fileURL(out2))
    emit([
        "evidence": written.path, "lines": scope.lines.count, "stations": scope.stations.count,
        "junctions": scope.junctionIDs.count, "pairedTracks": evidence.pairedTracks.count,
        "historyRows": evidence.history.retirements.count + evidence.history.identityPeriods.count,
        "rides": rides.count, "problems": problems.count, "problemsByKind": countsByKind(problems),
        "elapsed": seconds(clock.now - start),
    ] as [String: Any])
    return 0
}

func apply(_ options: Options) throws -> Int32 {
    let patch = try loadPatch(options)
    try patch.validate(requireProvenance: false)
    let scratch = fileURL(try required(options, "scratch"))
    let repo = try repoURL(options)
    let root = try ScratchOverlay.materialize(repo: repo, patches: [patch], into: scratch)
    let files = DataFile.allCases.filter { root.isOverlaid($0) }.map(\.relativePath)
    emit(["patch": patch.id, "scratch": scratch.path, "files": files, "ops": patch.ops.count,
          "reportOnly": patch.ops.filter { !$0.writable }.count] as [String: Any])
    return 0
}

func preview(_ options: Options) throws -> Int32 {
    let clock = ContinuousClock()
    let start = clock.now
    let patch = try loadPatch(options)
    try patch.validate(requireProvenance: false)
    let out = fileURL(try required(options, "out"))
    let repo = try repoURL(options)
    let baseline = try AreaData.load(DataRoot(repo: repo, overlay: options.one("overlay").map(fileURL)))
    let selected = hasSelector(options) ? try selection(options, data: baseline) : patch.area
    let scope = try AreaScope.resolve(selected, data: baseline)
    let scratch = out.appending(path: "scratch")
    let root = try ScratchOverlay.materialize(repo: repo, patches: [patch], into: scratch)
    let patched = try AreaData.load(root)
    let trains = RideSelection.ridesCrossing(scope, trains: try RideSelection.loadTrains(rideSources(options, root: baseline.root)), data: baseline)
    let level = try zoom(options)
    let result = try Preview.run(baseline: baseline, patched: patched, scope: scope, trains: trains,
                                 thresholds: try thresholds(options), zoom: level)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    try prettyEncoder().encode(result).write(to: out.appending(path: "preview.json"), options: .atomic)
    let evidence = try AreaEvidence.write(to: out, data: patched, scope: result.scopeAfter, rides: result.ridesAfter,
                                          problems: result.problemsAfter, zoom: level)

    var changes: [[String: Any]] = []
    var inAreaBefore = 0, inAreaAfter = 0
    for (before, after) in zip(result.ridesBefore, result.ridesAfter) {
        for (b, a) in zip(before.sections, after.sections) {
            if b.inArea, b.certified { inAreaBefore += 1 }
            if a.inArea, a.certified { inAreaAfter += 1 }
            if b.certified != a.certified {
                changes.append(["train": before.trainID, "section": b.index, "from": b.from ?? "", "to": b.to ?? "",
                                "certifiedBefore": b.certified, "certifiedAfter": a.certified])
            }
        }
    }
    let inAreaTotal = result.ridesBefore.reduce(0) { $0 + $1.sections.filter(\.inArea).count }
    emit([
        "patch": patch.id, "preview": out.appending(path: "preview.json").path, "evidence": evidence.path,
        "rides": result.ridesBefore.count,
        "inAreaSections": inAreaTotal, "certifiedBefore": inAreaBefore, "certifiedAfter": inAreaAfter, "certificationChanges": changes,
        "problemsBefore": result.problemsBefore.count, "problemsAfter": result.problemsAfter.count,
        "cleared": result.cleared, "introduced": result.introduced,
        "introducedDetail": result.problemsAfter.filter { result.introduced.contains($0.id) }.map(problemRow),
        "elapsed": seconds(clock.now - start),
    ] as [String: Any])
    return result.introduced.isEmpty ? 0 : 4
}

func write(_ options: Options) throws -> Int32 {
    let patch = try loadPatch(options)
    let repo = try repoURL(options)
    let allowGenerated = options.flags.contains("allow-generated")
    let confirm = options.flags.contains("confirm")

    var plan: [[String: Any]] = []
    for op in patch.ops {
        var row: [String: Any] = ["op": op.op.rawValue, "key": op.key, "file": op.file]
        if op.op.file == .package {
            row["status"] = "report-only"
            row["note"] = "generated package; mirror into \(op.mirror ?? "its source") in the website repository"
        } else if op.op.file == .history, !allowGenerated {
            row["status"] = "refused"
            row["note"] = "generated rail-history.json; pass --allow-generated and mirror into \(op.mirror ?? "its source")"
        } else if !op.writable {
            row["status"] = "refused"
            row["note"] = "marked not writable"
        } else {
            row["status"] = "writable"
            if let mirror = op.mirror { row["note"] = "mirror into \(mirror)" }
        }
        plan.append(row)
    }
    var patchDirectory = options.one("patch-dir").map(fileURL)
    if patchDirectory == nil, let root = evidenceRoot() {
        patchDirectory = root.appending(path: "area-repairs").appending(path: patch.id)
    }

    guard confirm else {
        var problem: String?
        do { try patch.validate(requireProvenance: true) } catch { problem = error.localizedDescription }
        var summary: [String: Any] = ["dryRun": true, "patch": patch.id, "plan": plan, "guards": guardClasses(patch).map(\.rawValue),
                                      "wrote": false, "message": AreaRepairError.confirmationRequired.localizedDescription]
        if let problem { summary["invalid"] = problem }
        if let patchDirectory { summary["patchDirectory"] = patchDirectory.path }
        else { summary["patchDirectory"] = "unresolved: mount /Volumes/JTM Evidence, set RAILWAY_EVIDENCE_ROOT or pass --patch-dir" }
        emit(summary)
        return 2
    }
    guard let patchDirectory else {
        throw CLIError(message: "No evidence root: the external archive /Volumes/JTM Evidence is not mounted and RAILWAY_EVIDENCE_ROOT is unset. Pass --patch-dir DIR or set RAILWAY_EVIDENCE_ROOT.")
    }
    let receipt = try WriteTransaction(repo: repo, patchDirectory: patchDirectory, allowGenerated: allowGenerated)
        .write(patch, confirm: true)
    emit(["patch": patch.id, "status": receipt.status.rawValue, "receipt": receipt.receiptURL.path,
          "files": receipt.files.map(\.relativePath), "topologyRegenerated": receipt.topologyRegenerated,
          "guards": receipt.guards.map(outcomeRow), "plan": plan] as [String: Any])
    return receipt.status == .written ? 0 : 4
}

func undo(_ options: Options) throws -> Int32 {
    let receiptURL = fileURL(try required(options, "receipt"))
    let repo = try repoURL(options)
    let receipt = try WriteTransaction(repo: repo, patchDirectory: receiptURL.deletingLastPathComponent())
        .undo(receiptAt: receiptURL, confirm: options.flags.contains("confirm"))
    let guards = receipt.undoGuards ?? []
    emit(["patch": receipt.patchID, "status": receipt.status.rawValue, "receipt": receiptURL.path,
          "files": receipt.files.map(\.relativePath), "guards": guards.map(outcomeRow)] as [String: Any])
    return guards.allSatisfy(\.passed) ? 0 : 4
}

func guardVerb(_ options: Options) throws -> Int32 {
    let patch = try loadPatch(options)
    let classes = guardClasses(patch)
    if options.flags.contains("dry-run") {
        let commands = classes.flatMap(GuardRunner.commands(for:)).map {
            ["class": $0.guardClass?.rawValue ?? "", "command": $0.shell, "swiftTest": $0.isSwiftTest] as [String: Any]
        }
        emit(["patch": patch.id, "dryRun": true, "commands": commands])
        return 0
    }
    let outcomes = GuardRunner().run(classes, repo: try repoURL(options))
    emit(["patch": patch.id, "passed": outcomes.allSatisfy(\.passed), "guards": outcomes.map(outcomeRow)] as [String: Any])
    return outcomes.allSatisfy(\.passed) ? 0 : 4
}

// MARK: dispatch

func run(_ arguments: [String]) throws -> Int32 {
    guard let verb = arguments.first else { print(topHelp); return 2 }
    if ["--help", "-h", "help"].contains(verb) { print(topHelp); return 0 }
    guard let help = helpText[verb] else { throw CLIError(message: "Unknown verb \(verb). Verbs: capture-data, problems, apply, preview, write, undo, guard.") }
    let rest = Array(arguments.dropFirst())
    if rest.contains("--help") || rest.contains("-h") { print(help); return 0 }
    switch verb {
    case "capture-data":
        return try captureData(try .parse(rest, valueFlags: selectorValueFlags.union(dataValueFlags), boolFlags: dataBoolFlags), problemsOnly: false)
    case "problems":
        return try captureData(try .parse(rest, valueFlags: selectorValueFlags.union(dataValueFlags).union(["propose"]), boolFlags: dataBoolFlags), problemsOnly: true)
    case "apply":
        return try apply(try .parse(rest, valueFlags: ["patch", "scratch", "repo"], boolFlags: []))
    case "preview":
        return try preview(try .parse(rest, valueFlags: selectorValueFlags.union(dataValueFlags).union(["patch"]), boolFlags: dataBoolFlags))
    case "write":
        return try write(try .parse(rest, valueFlags: ["patch", "patch-dir", "repo"], boolFlags: ["confirm", "allow-generated"]))
    case "undo":
        return try undo(try .parse(rest, valueFlags: ["receipt", "repo"], boolFlags: ["confirm"]))
    default:
        return try guardVerb(try .parse(rest, valueFlags: ["patch", "repo"], boolFlags: ["dry-run"]))
    }
}

do {
    exit(try run(Array(CommandLine.arguments.dropFirst())))
} catch let error as CLIError {
    fail(error.message, code: error.code)
} catch let error as AreaRepairError {
    switch error {
    case .guardFailed: fail(error.localizedDescription, code: 4)
    default: fail(error.localizedDescription, code: 2)
    }
} catch {
    fail("Internal error: \(error.localizedDescription)", code: 1)
}
