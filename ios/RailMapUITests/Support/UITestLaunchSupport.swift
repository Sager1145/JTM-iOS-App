import RailPresentation
import XCTest

/// UI cases describe the scenario; this is the only place that launches it.
@MainActor
enum UITestLaunchSupport {
    static func launch(_ app: XCUIApplication, storage: UITestLaunchConfiguration.Storage = .isolated) {
        app.uiTestLaunch = app.uiTestLaunch.preparedForLaunch(storage: storage)
        app.launch()
    }
}

extension XCUIApplication {
    var uiTestLaunch: UITestLaunchConfiguration {
        get { UITestLaunchConfiguration(environment: launchEnvironment) }
        set { launchEnvironment = newValue.environment }
    }
}
