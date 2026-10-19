import Foundation
import RailPresentation
import Testing

@Suite struct UITestLaunchConfigurationTests {
    @Test func preparationPreservesScenarioAndStorageAcrossRelaunches() throws {
        var configuration = UITestLaunchConfiguration(environment: ["AppleLanguages": "(ja)"])
        configuration[.tab] = "search"
        configuration[.query] = "20260703_01_haruka"
        let prepared = configuration.preparedForLaunch()
        let storage = try #require(prepared[.storageId])
        #expect(UUID(uuidString: storage) != nil)
        #expect(prepared.preparedForLaunch() == prepared)
        #expect(prepared[.tab] == "search")
        #expect(prepared[.query] == "20260703_01_haruka")
        #expect(prepared.environment["AppleLanguages"] == "(ja)")
    }

    @Test func externallySeededContainerRemainsSelected() {
        let configuration = UITestLaunchConfiguration(environment: ["AppleLanguages": "(en)"])
        let prepared = configuration.preparedForLaunch(storage: .existingContainer)
        #expect(prepared[.storageId] == nil)
        #expect(prepared.environment == configuration.environment)
    }

    @Test func editorDefaultsAllowScenarioOverrides() {
        let configuration = UITestLaunchConfiguration.editor(sheet: "new", environment: [
            "RAILMAP_UI_TEST_STORAGE_ID": "existing-case",
            "RAILMAP_UI_TEST_TAB": "search",
            "RAILMAP_UI_TEST_SHEET": "edit",
        ])
        #expect(configuration[.storageId] == "existing-case")
        #expect(configuration[.tab] == "search")
        #expect(configuration[.sheet] == "edit")
        #expect(configuration[.stage] == "expanded")
    }

    @Test func removingSeedRetainsOtherLaunchOptions() {
        var configuration = UITestLaunchConfiguration(environment: [
            "RAILMAP_UI_TEST_STORE_BASE64": "old-seed",
            "RAILMAP_UI_TEST_SAMPLE": "train-store",
        ])
        configuration[.storeBase64] = nil
        #expect(configuration.environment["RAILMAP_UI_TEST_STORE_BASE64"] == nil)
        #expect(configuration[.sample] == "train-store")
    }
}
