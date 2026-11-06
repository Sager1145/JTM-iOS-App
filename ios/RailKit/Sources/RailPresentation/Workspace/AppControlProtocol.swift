#if DEBUG
import Foundation

/// The test-only control channel's wire format and dispatch rules.
///
/// An agent shell (`ios/tools/app-control.py`) drives the DEBUG app without
/// touching the screen: it writes a request (inline in a `railmap-test://`
/// URL, or as `inbox/<id>.json` in the app's container), the app runs it
/// through its own stores and views, and writes `results/result-<id>.json`.
///
/// Everything here is pure so it can be unit-tested; the app supplies an
/// ``AppControlDriver`` that performs each command through its existing code
/// paths. The whole file is DEBUG-only, like the app side.
public enum AppControl {
    public static let scheme = "railmap-test"
    /// Under the app's Application Support directory.
    public static let rootFolderName = "RailMapAppControl"
    /// Launch environment key that starts the inbox poller.
    public static let pollEnvironmentKey = "RAILMAP_APP_CONTROL"
    public static let inboxFolder = "inbox"
    public static let resultsFolder = "results"
    public static let screenshotsFolder = "screenshots"

    public static func resultFileName(_ id: String) -> String { "result-\(id).json" }

    /// Request IDs become file names, so only a safe alphabet is accepted.
    public static func isValidRequestID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 80
            && id.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }
            && id.unicodeScalars.allSatisfy(\.isASCII)
    }
}

// MARK: - JSON value

/// A JSON value, so requests and results stay schema-free on the wire.
public enum AppControlJSON: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([AppControlJSON])
    case object([String: AppControlJSON])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([AppControlJSON].self) { self = .array(value) }
        else { self = .object(try container.decode([String: AppControlJSON].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value):
            if value.rounded() == value, abs(value) < 1e15 { try container.encode(Int64(value)) }
            else { try container.encode(value) }
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    public var string: String? {
        switch self {
        case .string(let value): value
        case .number(let value): value.rounded() == value ? String(Int64(value)) : String(value)
        default: nil
        }
    }
    public var number: Double? {
        switch self {
        case .number(let value): value
        case .string(let value): Double(value)
        default: nil
        }
    }
    public var bool: Bool? {
        switch self {
        case .bool(let value): value
        case .string(let value): ["1", "true", "yes"].contains(value.lowercased()) ? true
            : ["0", "false", "no"].contains(value.lowercased()) ? false : nil
        case .number(let value): value != 0
        default: nil
        }
    }
    public var array: [AppControlJSON]? {
        if case .array(let value) = self { return value }
        return nil
    }
    public var object: [String: AppControlJSON]? {
        if case .object(let value) = self { return value }
        return nil
    }

    /// A list given as an array or as one comma-separated string.
    public var stringList: [String]? {
        if let array { return array.compactMap(\.string) }
        if case .string(let value) = self {
            return value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        return nil
    }
}

extension AppControlJSON: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral,
    ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral, ExpressibleByFloatLiteral, ExpressibleByNilLiteral
{
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(arrayLiteral elements: AppControlJSON...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, AppControlJSON)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
    public init(nilLiteral: ()) { self = .null }
}

// MARK: - request and command

public struct AppControlRequest: Codable, Equatable, Sendable {
    public var id: String
    public var command: String
    public var args: [String: AppControlJSON]

    public init(id: String, command: String, args: [String: AppControlJSON] = [:]) {
        self.id = id
        self.command = command
        self.args = args
    }

    enum CodingKeys: String, CodingKey { case id, command, args }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        command = try container.decode(String.self, forKey: .command)
        args = try container.decodeIfPresent([String: AppControlJSON].self, forKey: .args) ?? [:]
    }
}

/// What a trip command asks the editor to do. Every field is optional on an
/// edit; `from`/`to` are required for `addTrip`.
public struct AppControlTripSpec: Equatable, Sendable {
    /// Region code for a new trip (`jp`, `tw`, …). Ignored by edits.
    public var region: String?
    /// Station source code, or an exact station name.
    public var from: String?
    public var to: String?
    /// `yyyy-MM-dd`; the departure keeps its time of day.
    public var date: String?
    /// `nil` keeps the vias; `[]` clears them.
    public var via: [String]?
    /// Section index → corridor id.
    public var sectionChoices: [Int: String]
    /// Commit through the editor's own save after planning.
    public var save: Bool
    /// Accept a route that drops recorded stops (the editor's confirmation).
    public var confirmRemoval: Bool
    public var timeoutMs: Int

    public init(
        region: String? = nil, from: String? = nil, to: String? = nil, date: String? = nil,
        via: [String]? = nil, sectionChoices: [Int: String] = [:], save: Bool = false,
        confirmRemoval: Bool = false, timeoutMs: Int = 60_000
    ) {
        self.region = region
        self.from = from
        self.to = to
        self.date = date
        self.via = via
        self.sectionChoices = sectionChoices
        self.save = save
        self.confirmRemoval = confirmRemoval
        self.timeoutMs = timeoutMs
    }
}

public struct AppControlHideFilter: Equatable, Sendable {
    public enum Mode: String, Sendable { case set, add, remove, showAll }
    public var mode: Mode
    public var regions: [String]
    public var years: [Int]
    public var months: [String]

    public init(mode: Mode, regions: [String] = [], years: [Int] = [], months: [String] = []) {
        self.mode = mode
        self.regions = regions
        self.years = years
        self.months = months
    }
}

public enum AppControlCommand: Equatable, Sendable {
    case loadSamples([String])
    case useStorage(String)
    case reloadAll(wait: Bool, timeoutMs: Int)
    case state(includeTrips: Bool)
    case selectTrip(String)
    case focusTrip(String)
    case openEditor(String)
    case addTrip(AppControlTripSpec)
    case editTrip(id: String, AppControlTripSpec)
    case saveEditor(confirmRemoval: Bool, timeoutMs: Int)
    case cancelEditor
    case deleteTrip(String)
    case openStats
    case setHideFilter(AppControlHideFilter)
    case screenshot(name: String?)
    case wait(condition: String, timeoutMs: Int)

    /// Every command name the parser accepts, for the CLI's help and tests.
    public static let names = [
        "loadSamples", "useStorage", "reloadAll", "state", "selectTrip", "focusTrip", "openEditor",
        "addTrip", "editTrip", "saveEditor", "cancelEditor", "deleteTrip", "openStats", "setHideFilter",
        "screenshot", "wait",
    ]

    /// Conditions ``wait`` understands.
    public static let waitConditions = ["mapReady", "routesLoaded", "editorReady", "editorPlanned", "editorClosed", "idle"]

    public static let defaultSamples = ["train-store"]

    public var name: String {
        switch self {
        case .loadSamples: "loadSamples"
        case .useStorage: "useStorage"
        case .reloadAll: "reloadAll"
        case .state: "state"
        case .selectTrip: "selectTrip"
        case .focusTrip: "focusTrip"
        case .openEditor: "openEditor"
        case .addTrip: "addTrip"
        case .editTrip: "editTrip"
        case .saveEditor: "saveEditor"
        case .cancelEditor: "cancelEditor"
        case .deleteTrip: "deleteTrip"
        case .openStats: "openStats"
        case .setHideFilter: "setHideFilter"
        case .screenshot: "screenshot"
        case .wait: "wait"
        }
    }

    /// Whether the command can write to the ride store or its preferences.
    /// These are refused unless the app runs on an isolated (UUID) store.
    public var mutatesStore: Bool {
        switch self {
        case .loadSamples, .reloadAll, .saveEditor, .deleteTrip, .setHideFilter: true
        case .addTrip(let spec), .editTrip(_, let spec): spec.save
        case .useStorage, .state, .selectTrip, .focusTrip, .openEditor, .cancelEditor, .openStats,
             .screenshot, .wait: false
        }
    }

    public static func parse(_ request: AppControlRequest) throws -> AppControlCommand {
        var args = request.args
        // `editTrip` may nest its edits under `changes`.
        if request.command == "editTrip", let changes = args["changes"]?.object {
            args.removeValue(forKey: "changes")
            args.merge(changes) { _, change in change }
        }
        func string(_ key: String) throws -> String {
            guard let value = args[key]?.string, !value.isEmpty else { throw AppControlError.missingArgument(key) }
            return value
        }
        func optionalString(_ key: String) -> String? {
            args[key]?.string.flatMap { $0.isEmpty ? nil : $0 }
        }
        func int(_ key: String, default value: Int) throws -> Int {
            guard let raw = args[key] else { return value }
            guard let number = raw.number, number >= 0, number <= 3_600_000 else {
                throw AppControlError.invalidArgument(key, "expected a non-negative number")
            }
            return Int(number)
        }
        func bool(_ key: String, default value: Bool) throws -> Bool {
            guard let raw = args[key] else { return value }
            guard let flag = raw.bool else { throw AppControlError.invalidArgument(key, "expected a boolean") }
            return flag
        }
        func tripSpec(requiresEndpoints: Bool) throws -> AppControlTripSpec {
            var spec = AppControlTripSpec(
                region: optionalString("region"), from: optionalString("from"), to: optionalString("to"),
                date: optionalString("date"), via: args["via"]?.stringList,
                save: try bool("save", default: false),
                confirmRemoval: try bool("confirmRemoval", default: false),
                timeoutMs: try int("timeoutMs", default: 60_000))
            if requiresEndpoints {
                guard spec.from != nil else { throw AppControlError.missingArgument("from") }
                guard spec.to != nil else { throw AppControlError.missingArgument("to") }
            }
            if let date = spec.date, !Self.isDay(date) {
                throw AppControlError.invalidArgument("date", "expected yyyy-MM-dd")
            }
            if let raw = args["sectionChoices"] {
                spec.sectionChoices = try Self.sectionChoices(raw)
            }
            return spec
        }

        switch request.command {
        case "loadSamples":
            let samples = args["samples"]?.stringList ?? args["sample"]?.stringList ?? Self.defaultSamples
            guard !samples.isEmpty else { throw AppControlError.invalidArgument("samples", "empty list") }
            return .loadSamples(samples)
        case "useStorage":
            let id = try string("id")
            guard UUID(uuidString: id) != nil else { throw AppControlError.invalidArgument("id", "expected a UUID") }
            return .useStorage(id)
        case "reloadAll":
            return .reloadAll(wait: try bool("wait", default: true), timeoutMs: try int("timeoutMs", default: 600_000))
        case "state":
            return .state(includeTrips: try bool("trips", default: true))
        case "selectTrip": return .selectTrip(try string("id"))
        case "focusTrip": return .focusTrip(try string("id"))
        case "openEditor": return .openEditor(try string("id"))
        case "addTrip": return .addTrip(try tripSpec(requiresEndpoints: true))
        case "editTrip":
            return .editTrip(id: try string("id"), try tripSpec(requiresEndpoints: false))
        case "saveEditor":
            return .saveEditor(
                confirmRemoval: try bool("confirmRemoval", default: false),
                timeoutMs: try int("timeoutMs", default: 30_000))
        case "cancelEditor": return .cancelEditor
        case "deleteTrip": return .deleteTrip(try string("id"))
        case "openStats": return .openStats
        case "setHideFilter":
            let modeName = optionalString("mode") ?? "set"
            guard let mode = AppControlHideFilter.Mode(rawValue: modeName) else {
                throw AppControlError.invalidArgument("mode", "expected set, add, remove or showAll")
            }
            var years: [Int] = []
            for year in args["years"]?.stringList ?? [] {
                guard let value = Int(year) else { throw AppControlError.invalidArgument("years", year) }
                years.append(value)
            }
            return .setHideFilter(AppControlHideFilter(
                mode: mode, regions: args["regions"]?.stringList ?? [], years: years,
                months: args["months"]?.stringList ?? []))
        case "screenshot":
            let name = optionalString("name")
            if let name, !AppControl.isValidRequestID(name) {
                throw AppControlError.invalidArgument("name", "letters, digits, - and _ only")
            }
            return .screenshot(name: name)
        case "wait":
            let condition = try string("condition")
            guard Self.waitConditions.contains(condition) || condition.hasPrefix("trips>=") else {
                throw AppControlError.invalidArgument("condition", condition)
            }
            if condition.hasPrefix("trips>="), Int(condition.dropFirst("trips>=".count)) == nil {
                throw AppControlError.invalidArgument("condition", condition)
            }
            return .wait(condition: condition, timeoutMs: try int("timeoutMs", default: 60_000))
        default:
            throw AppControlError.unknownCommand(request.command)
        }
    }

    static func isDay(_ text: String) -> Bool {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        return parts.count == 3 && parts[0].count == 4 && parts[1].count == 2 && parts[2].count == 2
            && parts.allSatisfy { $0.allSatisfy(\.isASCII) && Int($0) != nil }
    }

    /// `["id0","id1"]` (by position) or `{"0":"id0","2":"id2"}`.
    static func sectionChoices(_ raw: AppControlJSON) throws -> [Int: String] {
        if let list = raw.array {
            var result: [Int: String] = [:]
            for (index, value) in list.enumerated() {
                guard let id = value.string else { continue }
                if !id.isEmpty { result[index] = id }
            }
            return result
        }
        if let object = raw.object {
            var result: [Int: String] = [:]
            for (key, value) in object {
                guard let index = Int(key), index >= 0, let id = value.string else {
                    throw AppControlError.invalidArgument("sectionChoices", key)
                }
                result[index] = id
            }
            return result
        }
        throw AppControlError.invalidArgument("sectionChoices", "expected an array or an object")
    }
}

public enum AppControlError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidRequest(String)
    case unknownCommand(String)
    case missingArgument(String)
    case invalidArgument(String, String)
    case sharedStorage
    case relaunchRequired(String)
    case notFound(String)
    case unavailable(String)
    case timeout(String)
    case failed(String)

    public var description: String {
        switch self {
        case .invalidRequest(let detail): "invalid request: \(detail)"
        case .unknownCommand(let name): "unknown command: \(name)"
        case .missingArgument(let key): "missing argument: \(key)"
        case .invalidArgument(let key, let detail): "invalid argument \(key): \(detail)"
        case .sharedStorage:
            "refused: the app is on the shared ride store; relaunch with an isolated storage UUID"
        case .relaunchRequired(let detail): "relaunchRequired: \(detail)"
        case .notFound(let what): "not found: \(what)"
        case .unavailable(let what): "unavailable: \(what)"
        case .timeout(let what): "timed out: \(what)"
        case .failed(let detail): detail
        }
    }

    /// The result `status` this error reports. Matches the CLI's exit codes.
    public var status: AppControlResult.Status {
        switch self {
        case .invalidRequest, .unknownCommand, .missingArgument, .invalidArgument, .sharedStorage, .relaunchRequired:
            .rejected
        case .timeout: .timeout
        case .notFound, .unavailable, .failed: .failed
        }
    }
}

// MARK: - URL

public enum AppControlURL: Equatable, Sendable {
    /// `railmap-test://run?request=<id>`: read `inbox/<id>.json`.
    case file(id: String)
    /// `railmap-test://run?json=<base64url request>`.
    case inline(AppControlRequest)

    public static func parse(_ url: URL) throws -> AppControlURL {
        guard url.scheme == AppControl.scheme else { throw AppControlError.invalidRequest("scheme") }
        guard url.host == "run" else { throw AppControlError.invalidRequest("host \(url.host ?? "")") }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let encoded = value("json") {
            guard let data = Data(base64URLEncoded: encoded) else { throw AppControlError.invalidRequest("json is not base64url") }
            let request: AppControlRequest
            do { request = try JSONDecoder().decode(AppControlRequest.self, from: data) }
            catch { throw AppControlError.invalidRequest("json does not decode: \(error.localizedDescription)") }
            guard AppControl.isValidRequestID(request.id) else { throw AppControlError.invalidRequest("id") }
            return .inline(request)
        }
        if let id = value("request") {
            guard AppControl.isValidRequestID(id) else { throw AppControlError.invalidRequest("id") }
            return .file(id: id)
        }
        throw AppControlError.invalidRequest("no request or json item")
    }

    public static func make(_ request: AppControlRequest) throws -> URL {
        let data = try JSONEncoder().encode(request)
        var components = URLComponents()
        components.scheme = AppControl.scheme
        components.host = "run"
        components.queryItems = [URLQueryItem(name: "json", value: data.base64URLEncodedString())]
        return components.url!
    }
}

extension Data {
    init?(base64URLEncoded text: String) {
        var base = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base += String(repeating: "=", count: (4 - base.count % 4) % 4)
        self.init(base64Encoded: base)
    }

    func base64URLEncodedString() -> String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - result and dispatch

public struct AppControlResult: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        case running, ok, rejected, failed, timeout
    }
    public var id: String
    public var command: String
    public var status: Status
    public var error: String?
    public var startedAt: String
    public var finishedAt: String?
    public var elapsedMs: Double?
    public var storageID: String?
    public var processID: Int32
    public var data: AppControlJSON?
}

/// Performs one parsed command through the app's own stores and views.
@MainActor
public protocol AppControlDriver: AnyObject {
    /// The UUID of the isolated ride store, or `nil` on the shared store.
    var isolatedStorageID: String? { get }
    func perform(_ command: AppControlCommand, requestID: String) async throws -> AppControlJSON
}

@MainActor
public enum AppControlDispatcher {
    /// Parses, applies the storage guard, times and runs one request. Never throws:
    /// every outcome is a result the CLI can read.
    public static func run(
        _ request: AppControlRequest, driver: AppControlDriver,
        clock: () -> Date = Date.init
    ) async -> AppControlResult {
        let started = clock()
        let storage = driver.isolatedStorageID
        var result = AppControlResult(
            id: request.id, command: request.command, status: .running, error: nil,
            startedAt: Self.timestamp(started), finishedAt: nil, elapsedMs: nil,
            storageID: storage, processID: ProcessInfo.processInfo.processIdentifier, data: nil)
        do {
            guard AppControl.isValidRequestID(request.id) else { throw AppControlError.invalidRequest("id") }
            let command = try AppControlCommand.parse(request)
            if case .useStorage(let wanted) = command {
                guard storage?.caseInsensitiveCompare(wanted) == .orderedSame else {
                    throw AppControlError.relaunchRequired(
                        "running storage is \(storage ?? "shared"); relaunch with RAILMAP_UI_TEST_STORAGE_ID=\(wanted)")
                }
            }
            if command.mutatesStore, storage == nil { throw AppControlError.sharedStorage }
            result.data = try await driver.perform(command, requestID: request.id)
            result.status = .ok
        } catch let error as AppControlError {
            result.status = error.status
            result.error = error.description
        } catch {
            result.status = .failed
            result.error = String(describing: error)
        }
        let finished = clock()
        result.finishedAt = Self.timestamp(finished)
        result.elapsedMs = (finished.timeIntervalSince(started) * 1000 * 10).rounded() / 10
        return result
    }

    static func timestamp(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .omitted))
    }
}
#endif
