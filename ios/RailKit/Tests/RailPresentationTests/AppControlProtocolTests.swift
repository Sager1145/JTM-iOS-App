#if DEBUG
import Foundation
import RailPresentation
import Testing

@MainActor
private final class RecordingDriver: AppControlDriver {
    var isolatedStorageID: String?
    var performed: [AppControlCommand] = []
    var failure: Error?

    init(storage: String?) { isolatedStorageID = storage }

    func perform(_ command: AppControlCommand, requestID: String) async throws -> AppControlJSON {
        performed.append(command)
        if let failure { throw failure }
        return ["command": .string(command.name), "requestID": .string(requestID)]
    }
}

struct AppControlProtocolTests {
    private let storage = "6F9619FF-8B86-D011-B42D-00C04FC964FF"

    private func parse(_ command: String, _ args: [String: AppControlJSON] = [:]) throws -> AppControlCommand {
        try AppControlCommand.parse(AppControlRequest(id: "r1", command: command, args: args))
    }

    @Test("Every advertised command name parses with its minimal arguments")
    func everyNameParses() throws {
        let minimal: [String: [String: AppControlJSON]] = [
            "useStorage": ["id": .string(storage)], "selectTrip": ["id": "t"], "focusTrip": ["id": "t"],
            "openEditor": ["id": "t"], "addTrip": ["from": "a", "to": "b"], "editTrip": ["id": "t"],
            "deleteTrip": ["id": "t"], "wait": ["condition": "idle"],
        ]
        for name in AppControlCommand.names {
            let command = try parse(name, minimal[name] ?? [:])
            #expect(command.name == name)
        }
    }

    @Test("loadSamples takes a list, a comma string, or defaults to the Japan sample")
    func loadSamples() throws {
        #expect(try parse("loadSamples") == .loadSamples(["train-store"]))
        #expect(try parse("loadSamples", ["samples": "train-store, train-store-tw"])
            == .loadSamples(["train-store", "train-store-tw"]))
        #expect(try parse("loadSamples", ["samples": ["train-store-hk"]]) == .loadSamples(["train-store-hk"]))
    }

    @Test("addTrip needs both endpoints and a well-formed date")
    func addTripValidation() throws {
        #expect(throws: AppControlError.missingArgument("to")) { try parse("addTrip", ["from": "a"]) }
        #expect(throws: AppControlError.invalidArgument("date", "expected yyyy-MM-dd")) {
            try parse("addTrip", ["from": "a", "to": "b", "date": "2025-1-3"])
        }
        let command = try parse("addTrip", [
            "from": "東京", "to": "新大阪", "date": "2025-01-03", "via": "名古屋,京都",
            "sectionChoices": ["c0", "", "c2"], "save": "true", "region": "jp",
        ])
        #expect(command == .addTrip(AppControlTripSpec(
            region: "jp", from: "東京", to: "新大阪", date: "2025-01-03", via: ["名古屋", "京都"],
            sectionChoices: [0: "c0", 2: "c2"], save: true)))
        #expect(command.mutatesStore)
        #expect(try !parse("addTrip", ["from": "a", "to": "b"]).mutatesStore)
    }

    @Test("editTrip accepts its edits flat or nested under changes")
    func editTripChanges() throws {
        let nested = try parse("editTrip", [
            "id": "t1", "changes": ["to": "大阪", "via": [], "sectionChoices": ["1": "x"]],
        ])
        #expect(nested == .editTrip(id: "t1", AppControlTripSpec(to: "大阪", via: [], sectionChoices: [1: "x"])))
        let flat = try parse("editTrip", ["id": "t1", "date": "2024-12-31"])
        #expect(flat == .editTrip(id: "t1", AppControlTripSpec(date: "2024-12-31")))
    }

    @Test("Arguments are checked before anything runs")
    func argumentErrors() throws {
        #expect(throws: AppControlError.unknownCommand("tap")) { try parse("tap") }
        #expect(throws: AppControlError.invalidArgument("id", "expected a UUID")) {
            try parse("useStorage", ["id": "shared"])
        }
        #expect(throws: AppControlError.invalidArgument("condition", "soon")) {
            try parse("wait", ["condition": "soon"])
        }
        #expect(try parse("wait", ["condition": "trips>=3", "timeoutMs": 500]) == .wait(condition: "trips>=3", timeoutMs: 500))
        #expect(throws: AppControlError.invalidArgument("mode", "expected set, add, remove or showAll")) {
            try parse("setHideFilter", ["mode": "toggle"])
        }
        #expect(try parse("setHideFilter", ["regions": "tw", "years": [2023]])
            == .setHideFilter(AppControlHideFilter(mode: .set, regions: ["tw"], years: [2023])))
        #expect(throws: AppControlError.invalidArgument("name", "letters, digits, - and _ only")) {
            try parse("screenshot", ["name": "../x"])
        }
    }

    @Test("URLs round-trip an inline request and name an inbox file")
    func urls() throws {
        let request = AppControlRequest(id: "ac-1", command: "state", args: ["trips": false, "label": "東京"])
        let url = try AppControlURL.make(request)
        #expect(url.scheme == AppControl.scheme)
        #expect(try AppControlURL.parse(url) == .inline(request))
        #expect(try AppControlURL.parse(URL(string: "railmap-test://run?request=ac-2")!) == .file(id: "ac-2"))
        #expect(throws: AppControlError.invalidRequest("id")) {
            try AppControlURL.parse(URL(string: "railmap-test://run?request=..%2Fx")!)
        }
        #expect(throws: AppControlError.invalidRequest("scheme")) {
            try AppControlURL.parse(URL(string: "https://run?request=a")!)
        }
    }

    @Test("Results encode as plain JSON that the CLI reads")
    func resultEncoding() throws {
        let data = try JSONEncoder().encode(AppControlJSON.object(["n": 3, "f": 1.5, "s": "x", "b": true, "z": nil]))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["n"] as? Int == 3)
        #expect(object?["f"] as? Double == 1.5)
        #expect(object?["z"] is NSNull)
    }

    @Test("Dispatch runs the parsed command and reports timing")
    @MainActor
    func dispatchOK() async {
        let driver = RecordingDriver(storage: storage)
        let result = await AppControlDispatcher.run(
            AppControlRequest(id: "ok-1", command: "loadSamples"), driver: driver)
        #expect(result.status == .ok)
        #expect(result.storageID == storage)
        #expect(result.elapsedMs != nil && result.finishedAt != nil)
        #expect(driver.performed == [.loadSamples(["train-store"])])
        #expect(result.data?.object?["requestID"] == "ok-1")
    }

    @Test("On the shared store, writes are refused and reads still run")
    @MainActor
    func sharedStoreGuard() async {
        let driver = RecordingDriver(storage: nil)
        let refused = await AppControlDispatcher.run(AppControlRequest(id: "w", command: "deleteTrip", args: ["id": "t"]), driver: driver)
        #expect(refused.status == .rejected)
        #expect(refused.error == AppControlError.sharedStorage.description)
        let saving = await AppControlDispatcher.run(
            AppControlRequest(id: "w2", command: "addTrip", args: ["from": "a", "to": "b", "save": true]), driver: driver)
        #expect(saving.status == .rejected)
        let read = await AppControlDispatcher.run(AppControlRequest(id: "r", command: "state"), driver: driver)
        #expect(read.status == .ok)
        #expect(driver.performed == [.state(includeTrips: true)])
    }

    @Test("useStorage only confirms the store the app was launched on")
    @MainActor
    func useStorage() async {
        let driver = RecordingDriver(storage: storage)
        let same = await AppControlDispatcher.run(
            AppControlRequest(id: "u1", command: "useStorage", args: ["id": .string(storage.lowercased())]), driver: driver)
        #expect(same.status == .ok)
        let other = await AppControlDispatcher.run(
            AppControlRequest(id: "u2", command: "useStorage", args: ["id": .string(UUID().uuidString)]), driver: driver)
        #expect(other.status == .rejected)
        #expect(other.error?.hasPrefix("relaunchRequired") == true)
    }

    @Test("Driver errors map to the CLI's statuses")
    @MainActor
    func errorMapping() async {
        let driver = RecordingDriver(storage: storage)
        driver.failure = AppControlError.timeout("editorPlanned")
        #expect(await AppControlDispatcher.run(AppControlRequest(id: "e1", command: "state"), driver: driver).status == .timeout)
        driver.failure = AppControlError.notFound("trip x")
        #expect(await AppControlDispatcher.run(AppControlRequest(id: "e2", command: "state"), driver: driver).status == .failed)
        let badID = await AppControlDispatcher.run(AppControlRequest(id: "a/b", command: "state"), driver: driver)
        #expect(badID.status == .rejected)
    }
}
#endif
