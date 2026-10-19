import Foundation

/// Shared launch contract for the app and its UI-test runner. Raw keys remain
/// stable for simctl and screenshot harnesses; callers use named options.
public struct UITestLaunchConfiguration: Sendable, Equatable {
    public enum Key: String, CaseIterable, Sendable {
        case camera = "RAILMAP_UI_TEST_CAMERA"
        case cameraProduction = "RAILMAP_UI_TEST_CAMERA_PRODUCTION"
        case centeredGestureTarget = "RAILMAP_UI_TEST_CENTERED_GESTURE_TARGET"
        case chooser = "RAILMAP_UI_TEST_CHOOSER"
        case editorSection = "RAILMAP_UI_TEST_EDITOR_SECTION"
        case gestureTarget = "RAILMAP_UI_TEST_GESTURE_TARGET"
        case journeyInventory = "RAILMAP_UI_TEST_JOURNEY_INVENTORY"
        case layers = "RAILMAP_UI_TEST_LAYERS"
        case longDetail = "RAILMAP_UI_TEST_LONG_DETAIL"
        case playback = "RAILMAP_UI_TEST_PLAYBACK"
        case playbackHitProbe = "RAILMAP_UI_TEST_PLAYBACK_HIT_PROBE"
        case playbackTrainId = "RAILMAP_UI_TEST_PLAYBACK_TRAIN_ID"
        case query = "RAILMAP_UI_TEST_QUERY"
        case readyRide = "RAILMAP_UI_TEST_READY_RIDE"
        case region = "RAILMAP_UI_TEST_REGION"
        case reportReduceMotion = "RAILMAP_UI_TEST_REPORT_REDUCE_MOTION"
        case sample = "RAILMAP_UI_TEST_SAMPLE"
        case select = "RAILMAP_UI_TEST_SELECT"
        case shareBase = "RAILMAP_UI_TEST_SHARE_BASE"
        case shareCards = "RAILMAP_UI_TEST_SHARE_CARDS"
        case shareExportDir = "RAILMAP_UI_TEST_SHARE_EXPORT_DIR"
        case shareName = "RAILMAP_UI_TEST_SHARE_NAME"
        case sharePreset = "RAILMAP_UI_TEST_SHARE_PRESET"
        case shareRatio = "RAILMAP_UI_TEST_SHARE_RATIO"
        case shareScheme = "RAILMAP_UI_TEST_SHARE_SCHEME"
        case shareSize = "RAILMAP_UI_TEST_SHARE_SIZE"
        case sheet = "RAILMAP_UI_TEST_SHEET"
        case stage = "RAILMAP_UI_TEST_STAGE"
        case statsArea = "RAILMAP_UI_TEST_STATS_AREA"
        case statsRegion = "RAILMAP_UI_TEST_STATS_REGION"
        case storageId = "RAILMAP_UI_TEST_STORAGE_ID"
        case storeBase64 = "RAILMAP_UI_TEST_STORE_BASE64"
        case stress = "RAILMAP_UI_TEST_STRESS"
        case tab = "RAILMAP_UI_TEST_TAB"
        case tabBarProbe = "RAILMAP_UI_TEST_TAB_BAR_PROBE"
        case typography = "RAILMAP_UI_TEST_TYPOGRAPHY"
    }

    public enum Storage: Sendable {
        case isolated
        /// Memory measurements may use a container seeded outside the app.
        case existingContainer
    }

    public var environment: [String: String]

    public init(environment: [String: String] = [:]) {
        self.environment = environment
    }

    public subscript(key: Key) -> String? {
        get { environment[key.rawValue] }
        set { environment[key.rawValue] = newValue }
    }

    /// The app reads one immutable snapshot. Its DEBUG guards remain at callers.
    public static let current = Self(environment: ProcessInfo.processInfo.environment)

    /// Preserve a case's storage across relaunches and all non-test launch keys.
    public func preparedForLaunch(storage: Storage = .isolated) -> Self {
        var result = self
        if storage == .isolated, result[.storageId] == nil { result[.storageId] = UUID().uuidString }
        return result
    }

    /// Default workspace used by editor cases. Other scenarios retain their own
    /// destination, locale and sample choices.
    public static func editor(sheet: String, environment: [String: String] = [:]) -> Self {
        var result = Self(environment: environment).preparedForLaunch()
        result[.tab] = result[.tab] ?? "all"
        result[.stage] = result[.stage] ?? "expanded"
        result[.sheet] = result[.sheet] ?? sheet
        return result
    }
}
