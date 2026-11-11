import Foundation
import RailCore
import Testing

@testable import RailMap

/// "Remove sample trips" deletes only the trips a sample added (audit B5), and
/// "Reset to defaults" changes exactly the fields its footer lists (audit A17).
@MainActor
struct SampleTripsAndResetTests {
    private struct Isolated {
        let suite = "sample-trips-\(UUID().uuidString)"
        let defaults: UserDefaults
        let root: URL

        init() throws {
            defaults = try #require(UserDefaults(suiteName: suite))
            root = URL.temporaryDirectory.appending(path: "sample-trips-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        func remove() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func train(_ id: String) -> Train {
        Train(id: id, date: "2026-10-11", number: "Fixture", origin: "東京", destination: "品川",
              stops: [Stop(name: "東京", departure: "09:00"), Stop(name: "品川", arrival: "09:08")], region: "jp")
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(10))
        while condition() == false, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(2))
        }
        try #require(condition())
    }

    @Test func removingSampleTripsDeletesOnlyTheIdentifiersTheSampleAdded() async throws {
        let isolated = try Isolated()
        defer { isolated.remove() }
        let library = RideLibrary(storage: RideStorage(directory: isolated.root), preferences: isolated.defaults)
        let itineraries = ItineraryStore(preferences: isolated.defaults)
        itineraries.load(from: library)
        try await waitUntil { itineraries.canReplace }
        let text = MergedStore.export(TrainStore(trains: [train("sample-a"), train("own-1"), train("sample-b"), train("own-2")]))
        _ = try await itineraries.runImport(
            text: text, region: .jp, mode: .replaceAll, library: library, onProgress: { _ in })
        library.noteSampleLoaded("train-store")

        let removed = itineraries.removeTrains(withIDs: ["sample-a", "sample-b", "not-in-the-store"], clearing: library)

        #expect(removed.outcome == 2)
        #expect(itineraries.store?.trains.map(\.id) == ["own-1", "own-2"])
        #expect(library.loadedSamples.isEmpty, "no sample's trips are left, so no sample is marked loaded")
        let saved = try #require(await removed.save?.value)
        #expect(saved.saved)
    }

    @Test func removingWhenNoSampleTripIsPresentChangesNothing() async throws {
        let isolated = try Isolated()
        defer { isolated.remove() }
        let library = RideLibrary(storage: RideStorage(directory: isolated.root), preferences: isolated.defaults)
        let itineraries = ItineraryStore(preferences: isolated.defaults)
        itineraries.load(from: library)
        try await waitUntil { itineraries.canReplace }
        _ = try await itineraries.runImport(
            text: MergedStore.export(TrainStore(trains: [train("own-1")])), region: .jp, mode: .replaceAll,
            library: library, onProgress: { _ in })
        library.noteSampleLoaded("train-store")
        let generation = itineraries.storeGeneration

        let removed = itineraries.removeTrains(withIDs: ["sample-a"], clearing: library)

        #expect(removed.outcome == nil)
        #expect(itineraries.store?.trains.map(\.id) == ["own-1"])
        #expect(itineraries.storeGeneration == generation)
        #expect(library.loadedSamples == ["train-store"], "a refused removal does not forget the samples")
    }

    @Test func sampleTripIDsAreCachedAndIncludeALoadedSamplesIDs() async throws {
        let isolated = try Isolated()
        defer { isolated.remove() }
        let library = RideLibrary(storage: RideStorage(directory: isolated.root), preferences: isolated.defaults)
        let entry = try #require(RideLibrary.Sample.all.first)
        let loaded = try await library.sample(entry.resource)
        let ids = await library.allSampleTripIDs()
        #expect(!loaded.trains.isEmpty)
        for train in loaded.trains { #expect(ids.contains(train.id)) }
        for (legacy, now) in SampleLegacyRideIDs.map(for: entry.resource) where Set(loaded.trains.map(\.id)).contains(now) {
            #expect(ids.contains(legacy))
        }
        #expect(await library.allSampleTripIDs() == ids)
    }

    @Test func aStoreLeftFailedCanBeEmptiedByDeletingTheSavedFile() async throws {
        let isolated = try Isolated()
        defer { isolated.remove() }
        try Data("{ not a store".utf8).write(to: isolated.root.appending(path: "train-store.json"))
        let library = RideLibrary(storage: RideStorage(directory: isolated.root), preferences: isolated.defaults)
        let itineraries = ItineraryStore(preferences: isolated.defaults)
        itineraries.load(from: library)
        try await waitUntil { if case .failed = itineraries.state { return true } else { return false } }
        #expect(itineraries.store == nil)
        #expect(library.hasSavedStore)

        try await library.deleteSavedStore()
        itineraries.load(from: library)
        try await waitUntil { itineraries.canReplace }

        #expect(!library.hasSavedStore)
        #expect(itineraries.store?.trains.isEmpty == true)
    }

    @Test func pastingAnOfficialStoreDetectsItsRegion() {
        let flow = ImportFlow()
        flow.load("{\"trains\":[{\"id\":\"tw-official-1\"}]}", origin: .pasted)
        flow.prepareForPresentation()
        #expect(flow.detectedRegion == .tw)
        #expect(flow.region == .tw)
        // A sheet that prepared an empty paste first must not block detection.
        let reused = ImportFlow()
        reused.prepareForPresentation()
        reused.load("{\"trains\":[{\"id\":\"hk-official-1\"}]}", origin: .pasted)
        reused.prepareForPresentation()
        #expect(reused.detectedRegion == .hk)
    }

    @Test func everyBundledSampleIsKnownToTheRemoval() {
        // The removal matches ids read from these resources; a sample missing
        // from `Sample.all` would be impossible to remove.
        #expect(RideLibrary.Sample.all.count == 7)
        #expect(Set(RideLibrary.Sample.all.map(\.resource)).count == 7)
    }

    @Test func resetToDefaultsChangesExactlyTheFieldsTheFooterNames() throws {
        let suite = "display-reset-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let display = DisplaySettings(userDefaults: defaults)
        let untouched = DisplaySettings(userDefaults: try #require(UserDefaults(suiteName: suite + "-b")))
        defer { defaults.removePersistentDomain(forName: suite + "-b") }

        display.routeWidthScale = 2; display.riddenOpacity = 0.5; display.dimOpacity = 0.9
        display.terminalRadius = 9; display.stopRadius = 9; display.passRadius = 9
        display.markerStrokeScale = 2; display.focusBoost = 5; display.showFullCrossDay = true
        display.networkEra = .historicalOverlay
        display.nameReadingKana = true; display.nameReadingRomaji = true; display.nameReadingZh = true
        display.nameReadingsCustomized = true; display.showJourneyTranslations = true

        display.reset()

        // Map style: nine sliders and the cross-day switch.
        #expect(display.routeWidthScale == untouched.routeWidthScale)
        #expect(display.riddenOpacity == untouched.riddenOpacity)
        #expect(display.dimOpacity == untouched.dimOpacity)
        #expect(display.terminalRadius == untouched.terminalRadius)
        #expect(display.stopRadius == untouched.stopRadius)
        #expect(display.passRadius == untouched.passRadius)
        #expect(display.markerStrokeScale == untouched.markerStrokeScale)
        #expect(display.focusBoost == untouched.focusBoost)
        #expect(display.showFullCrossDay == untouched.showFullCrossDay)
        // Network era.
        #expect(display.networkEra == untouched.networkEra)
        // Name readings and translations.
        #expect(display.nameReadingKana == untouched.nameReadingKana)
        #expect(display.nameReadingRomaji == untouched.nameReadingRomaji)
        #expect(display.nameReadingZh == untouched.nameReadingZh)
        #expect(display.nameReadingsCustomized == untouched.nameReadingsCustomized)
        #expect(display.showJourneyTranslations == untouched.showJourneyTranslations)

        // The footer names these four groups, in every language, and never
        // claims "this screen only".
        let footer = try #require(AppStrings.table["ios.note.reset"])
        for language in [Localization.Language.en, .ja, .zhHans, .zhHant] {
            #expect(footer[language]?.isEmpty == false)
        }
        let english = try #require(footer[.en])
        for group in ["map style", "network era", "name readings", "translations"] {
            #expect(english.contains(group))
        }
        #expect(!english.contains("this screen"))
    }
}
