import XCTest

/// Launch hooks shared by the new-trip screen and the edit-mode ride editor.
///
/// Callers may set `launchArguments` and extra environment keys before calling.
/// Environment entries passed here override the defaults below. Both launches
/// start the app.
@MainActor
enum EditorLaunchSupport {
    /// One seeded journey (Train JSON dictionary, keys as Train's Codable keys)
    /// opened straight into RideEditorView edit mode.
    static func launchEditing(
        _ app: XCUIApplication,
        journey: [String: Any],
        environment: [String: String] = [:]
    ) {
        var env = baseEnvironment(sheet: "edit")
        env["RAILMAP_UI_TEST_STORE_BASE64"] = storeBase64(journey)
        for (key, value) in environment { env[key] = value }
        launch(app, environment: env)
    }

    /// Fresh store with the new-trip screen open.
    static func launchNewTrip(
        _ app: XCUIApplication,
        environment: [String: String] = [:]
    ) {
        var env = baseEnvironment(sheet: "new")
        for (key, value) in environment { env[key] = value }
        launch(app, environment: env)
    }

    static func stop(
        _ name: String,
        code: String?,
        type: String,
        arrival: String? = nil,
        departure: String? = nil,
        ridden: Bool = true
    ) -> [String: Any] {
        var stop: [String: Any] = [
            "name": name,
            "stop_type": type,
            "ride_segment": ridden,
        ]
        if let code { stop["n02_station_code"] = code }
        if let arrival { stop["arrival"] = arrival }
        if let departure { stop["departure"] = departure }
        return stop
    }

    private static func baseEnvironment(sheet: String) -> [String: String] {
        [
            "RAILMAP_UI_TEST_STORAGE_ID": UUID().uuidString,
            "RAILMAP_UI_TEST_TAB": "all",
            "RAILMAP_UI_TEST_STAGE": "expanded",
            "RAILMAP_UI_TEST_SHEET": sheet,
        ]
    }

    private static func launch(_ app: XCUIApplication, environment: [String: String]) {
        for (key, value) in environment {
            app.launchEnvironment[key] = value
        }
        if app.launchArguments.isEmpty {
            app.launchArguments = [
                "-AppleLanguages", "(en)",
                "-AppleLocale", "en_US",
                "-interface-language", "en",
            ]
        }
        app.launch()
    }

    /// `{ schema_version, trains: [journey] }` — the shape `TrainStore` decodes.
    private static func storeBase64(_ journey: [String: Any]) -> String {
        let store: [String: Any] = ["schema_version": "1.3", "trains": [journey]]
        let data = try! JSONSerialization.data(withJSONObject: store, options: [.sortedKeys])
        return data.base64EncodedString()
    }
}
