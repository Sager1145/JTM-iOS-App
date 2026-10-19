import Foundation
import RailCore
import RailApplication
import Testing

@testable import RailMap

/// These tests use the app owners, real canonical files, and fresh directories.
/// Only Vision and the selected failing atomic write are substituted.
@MainActor
struct NativeImportPersistenceTests {
    @Test func injectedPreferencesKeepNavigationAndSampleFlagsInTheirOwnDomains() throws {
        let first = try IsolatedPreferences()
        let second = try IsolatedPreferences()
        defer { first.remove(); second.remove() }
        first.defaults.set("first", forKey: "last-viewed-train-id")
        second.defaults.set("second", forKey: "last-viewed-train-id")
        first.defaults.set(["first-sample"], forKey: "loaded-samples")
        second.defaults.set(["second-sample"], forKey: "loaded-samples")
        let firstItineraries = ItineraryStore(preferences: first.defaults)
        let secondItineraries = ItineraryStore(preferences: second.defaults)
        #expect(firstItineraries.lastViewedTrainID == "first")
        #expect(secondItineraries.lastViewedTrainID == "second")
        firstItineraries.selectedTrainID = "changed"
        #expect(first.defaults.string(forKey: "last-viewed-train-id") == "changed")
        #expect(second.defaults.string(forKey: "last-viewed-train-id") == "second")
        let firstLibrary = RideLibrary(preferences: first.defaults)
        let secondLibrary = RideLibrary(preferences: second.defaults)
        #expect(firstLibrary.loadedSamples == ["first-sample"])
        #expect(secondLibrary.loadedSamples == ["second-sample"])
        firstLibrary.noteSampleLoaded("extra")
        #expect(first.defaults.stringArray(forKey: "loaded-samples") == ["extra", "first-sample"])
        firstLibrary.forgetLoadedSamples()
        #expect(first.defaults.stringArray(forKey: "loaded-samples") == [])
        #expect(second.defaults.stringArray(forKey: "loaded-samples") == ["second-sample"])
    }

    @Test func cancellingSuspendedScreenshotReadingReturnsToWaitingAndRejectsLateOCR() async throws {
        let recognizer = SuspendedScreenshotRecognizer()
        let importer = TransferGuideImport(recognize: { _, progress in
            try await recognizer.read(progress: progress)
        })
        let reading = importer.read(pages: [Data([0])], names: ["cancelled.png"], stations: [], lines: [], existingIDs: [])
        defer {
            importer.cancel()
            recognizer.finish(with: screenshotReading())
        }
        try await waitUntil { recognizer.isSuspended }
        #expect(importer.isRunning)

        importer.cancel()
        #expect(importer.isRunning == false)
        if case .waiting = importer.phase {
            #expect(importer.draft == nil)
        } else {
            Issue.record("Cancelling recognition must return the picker to waiting")
        }

        // This recognizer deliberately ignores cancellation and completes
        // late, so the app owner's generation/cancellation guards are real.
        recognizer.finish(with: screenshotReading())
        // Join the actual owner after recognition resumes, including its
        // cancellation/generation fences and any possible draft publication.
        await reading.value
        #expect(importer.isRunning == false)
        #expect(importer.draft == nil)
        if case .waiting = importer.phase {} else {
            Issue.record("Late OCR progress or completion revived a cancelled reading")
        }
    }

    @Test(arguments: ImportPreflight.Mode.allCases)
    func startupImportRefusesAnUnloadedSavedBaseline(mode: ImportPreflight.Mode) async throws {
        let preferences = try IsolatedPreferences()
        defer { preferences.remove() }
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = RideLibrary(storage: RideStorage(directory: root), preferences: preferences.defaults)
        let saved = try #require((try await baseline(preferences: preferences.defaults)).store)
        let save = await library.saveResult(saved).value
        try #require(save.saved)
        let bytes = try Data(contentsOf: root.appending(path: "train-store.json"))
        let itineraries = ItineraryStore(preferences: preferences.defaults)
        itineraries.load(from: library)
        var committed = false
        do {
            _ = try await itineraries.runImport(text: document("incoming"), region: .jp,
                mode: mode, onProgress: { _ in }, onCommit: { committed = true })
            Issue.record("Import must refuse a baseline whose initial read has not finished")
        } catch {
            #expect(error.localizedDescription == "Journeys are still loading. Try the import again after loading finishes.")
        }
        #expect(!committed)
        try await waitUntil { itineraries.canReplace }
        #expect(itineraries.store?.trains.map(\.id) == ["original"])
        #expect(try Data(contentsOf: root.appending(path: "train-store.json")) == bytes)
        let summary = try await itineraries.runImport(text: document("incoming"), region: .jp,
            mode: mode, onProgress: { _ in })
        #expect(summary.imported == 1)
        #expect(itineraries.store?.trains.map(\.id) == (mode == .append ? ["original", "incoming"] : ["incoming"]))
    }

    @Test func preflightDoesNotCertifyAnUnloadedBaseline() throws {
        let preferences = try IsolatedPreferences()
        defer { preferences.remove() }
        let itineraries = ItineraryStore(preferences: preferences.defaults)
        let flow = ImportFlow()
        flow.load(document("incoming"), origin: .pasted)
        flow.check(itineraries: itineraries)
        #expect(flow.phaseKind == .editing)
        #expect(flow.report == nil)
    }

    @Test func importDiscardsAStagedSnapshotAfterItsBaselineChanges() async throws {
        let preferences = try IsolatedPreferences()
        defer { preferences.remove() }
        let itineraries = try await baseline(preferences: preferences.defaults)
        let restored = document("restored")
        var changed = false
        var committed = false
        do {
            _ = try await itineraries.runImport(text: document("incoming"), region: .jp,
                mode: .append, onProgress: { _ in
                    guard !changed else { return }
                    do {
                        _ = try await itineraries.runImport(
                            text: restored, region: .jp, mode: .replaceAll,
                            onProgress: { _ in })
                        changed = true
                    } catch { Issue.record(error) }
                }, onCommit: { committed = true })
            Issue.record("Staging must not overwrite a newer working-set revision")
        } catch {
            #expect(error.localizedDescription == "Journeys changed while the import was being prepared. Check the import again.")
        }
        #expect(changed)
        #expect(!committed)
        #expect(itineraries.store?.trains.map(\.id) == ["restored"])
    }

    @Test func regroupDoesNotRestoreSelectionAfterNewerNavigation() async throws {
        let preferences = try IsolatedPreferences()
        defer { preferences.remove() }
        let itineraries = try await baseline(preferences: preferences.defaults)
        try #require(itineraries.add(train("new")).outcome == "new")
        itineraries.selectedTrainID = "original"
        try await waitUntil { itineraries.loaded?.trains.count == 2 }
        #expect(itineraries.selectedTrainID == "original")
    }

    @Test func menuSelectionRestoreDoesNotOverrideNavigationThatReturnsToTheSameJourney() async throws {
        let preferences = try IsolatedPreferences()
        defer { preferences.remove() }
        let itineraries = try await baseline(preferences: preferences.defaults)
        try #require(itineraries.add(train("other")).outcome == "other")
        itineraries.selectedTrainID = "original"
        let menuRevision = itineraries.selectionRevision
        itineraries.selectedTrainID = "other"
        itineraries.selectedTrainID = "original"
        #expect(!itineraries.restoreSelection(nil, ifUnchangedSince: menuRevision))
        #expect(itineraries.selectedTrainID == "original")
        #expect(itineraries.restoreSelection("deleted", ifUnchangedSince: itineraries.selectionRevision))
        #expect(itineraries.selectedTrainID == nil)
    }

    @Test func failedSavedDeletionRetainsMetadataAndReportsFailure() async throws {
        let preferences = try IsolatedPreferences()
        defer { preferences.remove() }
        let root = try temporaryDirectory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
        }
        let library = RideLibrary(storage: RideStorage(directory: root), preferences: preferences.defaults)
        let original = try #require((try await baseline(preferences: preferences.defaults)).store)
        let save = await library.saveResult(original).value
        try #require(save.saved)
        await library.refreshSavedState()
        let previousDate = library.savedStoreDate
        let savedURL = root.appending(path: "train-store.json")
        let previousBytes = try Data(contentsOf: savedURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
        do {
            try await library.deleteSavedStore()
            Issue.record("An unwritable parent must report deletion failure")
        } catch {
            #expect(library.lastSaveError == error.localizedDescription)
        }
        #expect(library.hasSavedStore)
        #expect(library.savedStoreDate == previousDate)
        #expect(try Data(contentsOf: savedURL) == previousBytes)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        try await library.deleteSavedStore()
        #expect(!library.hasSavedStore)
        #expect(library.savedStoreDate == nil)
        #expect(library.lastSaveError == nil)
        // An already missing saved file is also a successful delete.
        try await library.deleteSavedStore()
    }

    @Test func durableRouteReplacementAndUndoSurviveReload() async throws {
        let preferences = try IsolatedPreferences()
        defer { preferences.remove() }
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = RideLibrary(storage: RideStorage(directory: root), preferences: preferences.defaults)
        let itineraries = try await baseline(preferences: preferences.defaults)
        let original = try #require(itineraries.store?.trains.first)
        let initialSave = await library.saveResult(try #require(itineraries.store)).value
        try #require(initialSave.saved)
        let savedURL = root.appending(path: "train-store.json")
        let originalBytes = try Data(contentsOf: savedURL)
        var repaired = original
        repaired.notes = "Repaired route fixture"
        let editing = JourneyEditing(itineraries: itineraries, library: library)
        let replacement = editing.replaceAndPersist(repaired, replacing: original.id)
        let save = try #require(replacement.persistence)
        #expect(await save.value.saved)
        #expect(try await library.savedStore().trains.first?.notes == repaired.notes)
        let undo = editing.replaceAndPersist(original, replacing: original.id)
        #expect(await (try #require(undo.persistence)).value.saved)
        #expect(try Data(contentsOf: savedURL) == originalBytes)
        #expect(try await library.savedStore().trains.first?.notes == original.notes)
    }

    @Test(arguments: ImportPreflight.Mode.allCases)
    func cancellationBeforeCommitKeepsWorkingAndSavedStores(mode: ImportPreflight.Mode) async throws {
        let preferences = try IsolatedPreferences()
        defer { preferences.remove() }
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = RideLibrary(storage: RideStorage(directory: root), preferences: preferences.defaults)
        let itineraries = try await baseline(preferences: preferences.defaults)
        let before = try #require(itineraries.store)
        let initialSave = await library.saveResult(before).value
        try #require(initialSave.saved)
        let savedBytes = try Data(contentsOf: root.appending(path: "train-store.json"))
        var committed = false

        let operation = Task {
            try await itineraries.runImport(
                text: document("incoming"), region: .jp, mode: mode,
                onProgress: { _ in withUnsafeCurrentTask { $0?.cancel() } },
                onCommit: { committed = true })
        }
        do {
            _ = try await operation.value
            Issue.record("Cancelled import unexpectedly committed")
        } catch {
            #expect(error is CancellationError)
        }

        #expect(committed == false)
        #expect(itineraries.isImporting == false)
        #expect(itineraries.store == before)
        #expect(try Data(contentsOf: root.appending(path: "train-store.json")) == savedBytes)
    }

    @Test(arguments: ImportPreflight.Mode.allCases)
    func cancellationAtCommitStillReturnsAndPersistsCommittedSnapshot(mode: ImportPreflight.Mode) async throws {
        let preferences = try IsolatedPreferences()
        defer { preferences.remove() }
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = RideLibrary(storage: RideStorage(directory: root), preferences: preferences.defaults)
        let itineraries = try await baseline(preferences: preferences.defaults)
        var committed = false

        let operation = Task {
            try await itineraries.runImport(
                text: document("incoming"), region: .jp, mode: mode,
                library: library,
                onProgress: { _ in }, onCommit: {
                    committed = true
                    withUnsafeCurrentTask { $0?.cancel() }
                })
        }
        let summary = try await operation.value
        #expect(committed)
        #expect(summary.imported == 1)
        #expect(summary.save.saved)
        #expect(summary.save.error == nil)
        #expect(itineraries.isImporting == false)
        let saved = try await library.savedStore()
        #expect(saved.trains.map(\.id) == (mode == .append ? ["original", "incoming"] : ["incoming"]))
    }

    @Test func importFlowCancellationBeforeWorkKeepsOriginalStore() async throws {
        let preferences = try IsolatedPreferences()
        defer { preferences.remove() }
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = RideLibrary(storage: RideStorage(directory: root), preferences: preferences.defaults)
        let itineraries = try await baseline(preferences: preferences.defaults)
        let before = try #require(itineraries.store)
        let flow = ImportFlow()
        flow.load(document("incoming"), origin: .pasted)
        flow.check(itineraries: itineraries)
        try await waitUntil { flow.phaseKind == .checked }

        flow.commit(itineraries: itineraries, library: library)
        #expect(flow.canCancel)
        flow.cancel()
        try await waitUntil { flow.phaseKind == .failed }
        if case .failed(let failure) = flow.phase {
            #expect(failure.neutral)
        } else {
            Issue.record("Cancellation did not publish its neutral result")
        }
        #expect(itineraries.store == before)
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "train-store.json").path) == false)
    }

    @Test func actualMainWriteFailureReportsItsOwnErrorAndRetrySavesCurrentEdits() async throws {
        let preferences = try IsolatedPreferences()
        defer { preferences.remove() }
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let storePath = root.appending(path: "train-store.json")
        // A directory at the file destination makes the real atomic write fail.
        try FileManager.default.createDirectory(at: storePath, withIntermediateDirectories: true)
        let library = RideLibrary(storage: RideStorage(directory: root), preferences: preferences.defaults)
        let itineraries = try await baseline(preferences: preferences.defaults)
        let flow = ImportFlow()
        flow.load(document("incoming"), origin: .pasted)
        flow.check(itineraries: itineraries)
        try await waitUntil { flow.phaseKind == .checked }
        flow.commit(itineraries: itineraries, library: library)
        try await waitUntil { flow.phaseKind == .finished }
        guard case .finished(let outcome) = flow.phase else {
            Issue.record("Import did not finish"); return
        }
        let error = try #require(outcome.saveError)
        #expect(error.isEmpty == false)
        #expect(library.lastSaveError == error)
        #expect(library.hasSavedStore == false)
        #expect(itineraries.store?.trains.map(\.id) == ["original", "incoming"])

        // Another edit between failure and retry must be the snapshot saved.
        let added = itineraries.add(train("intervening"))
        #expect(added.outcome == "intervening")
        try FileManager.default.removeItem(at: storePath)
        let retry = await itineraries.saveWorkingSet().value
        #expect(retry.saved)
        #expect(retry.error == nil)
        #expect(library.lastSaveError == nil)
        #expect(try await library.savedStore().trains.map(\.id) == ["original", "incoming", "intervening"])
        // This failed write's result is immutable even after a newer success.
        #expect(outcome.saveError == error)
    }

    @Test func screenshotSaveRetryDoesNotReinsertRecordsOrOverwriteInterveningEdits() async throws {
        let preferences = try IsolatedPreferences()
        defer { preferences.remove() }
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let storePath = root.appending(path: "train-store.json")
        try FileManager.default.createDirectory(at: storePath, withIntermediateDirectories: true)
        let library = RideLibrary(storage: RideStorage(directory: root), preferences: preferences.defaults)
        let itineraries = try await baseline(preferences: preferences.defaults)
        let reading = screenshotReading()
        let importer = TransferGuideImport(recognize: { _, progress in
            progress(1, 1)
            return reading
        })
        importer.read(pages: [Data([0])], names: ["route.png"], stations: [], lines: [], existingIDs: ["original"])
        try await waitUntil { if case .read = importer.phase { return true }; return false }
        #expect(importer.draft?.build.trains.count == 1)
        importer.cancel()
        if case .read = importer.phase {} else {
            Issue.record("Cancel must preserve an already-read screenshot draft")
        }
        let importedIDs = await importer.commit(into: itineraries, library: library)
        try #require(importedIDs.count == 1)
        guard case .imported(let count, let saveError) = importer.phase else {
            Issue.record("Screenshot import did not report its result"); return
        }
        #expect(count == 1)
        #expect(saveError != nil)
        importer.cancel()
        if case .imported(let retainedCount, let retainedError) = importer.phase {
            #expect(retainedCount == count)
            #expect(retainedError == saveError)
        } else {
            Issue.record("Cancel must preserve a committed screenshot's save result")
        }
        let importedID = try #require(importedIDs.first)
        var edited = try #require(itineraries.store?.trains.first { $0.id == importedID })
        edited.notes = "edited after failed save"
        #expect(itineraries.replace(edited, replacing: importedID).outcome == .saved)
        #expect(itineraries.add(train("intervening")).outcome == "intervening")
        try FileManager.default.removeItem(at: storePath)

        await importer.retrySave(into: itineraries, library: library)
        guard case .imported(let retriedCount, let retryError) = importer.phase else {
            Issue.record("Retry lost the imported result"); return
        }
        #expect(retriedCount == 1)
        #expect(retryError == nil)
        let saved = try await library.savedStore()
        #expect(saved.trains.map(\.id) == ["original", importedID, "intervening"])
        #expect(saved.trains.filter { $0.id == importedID }.count == 1)
        #expect(saved.trains.first { $0.id == importedID }?.notes == "edited after failed save")
        #expect(itineraries.store?.trains.map(\.id) == saved.trains.map(\.id))
    }

    @Test(arguments: ["train-store.json", "metadata.json", "train-store.backup-current.json"])
    func failedBackupPublicationKeepsPreviousGenerationRestorable(failingName: String) async throws {
        let preferences = try IsolatedPreferences()
        defer { preferences.remove() }
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let previous = TrainStore(trains: [train("recover-original")])
        let first = RideLibrary(storage: RideStorage(directory: root), preferences: preferences.defaults)
        try await first.snapshotBackup(previous, reason: .beforeDeleteAll)
        await first.refreshSavedState()
        let previousMeta = try #require(first.backup)
        let pointer = root.appending(path: "train-store.backup-current.json")
        let previousPointer = try Data(contentsOf: pointer)
        let generations = root.appending(path: "backup-generations")
        let previousNames = try FileManager.default.contentsOfDirectory(atPath: generations.path)
        let injectedError = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
        let library = RideLibrary(storage: RideStorage(directory: root, writeData: { data, url in
            if url.lastPathComponent == failingName {
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
            }
            try data.write(to: url, options: .atomic)
        }), preferences: preferences.defaults)
        do {
            try await library.snapshotBackup(TrainStore(trains: [train("replacement"), train("second")]), reason: .beforeReplace)
            Issue.record("Backup publication unexpectedly succeeded")
        } catch {
            let actual = error as NSError
            #expect(actual.domain == injectedError.domain)
            #expect(actual.code == injectedError.code)
        }
        #expect(library.backup == previousMeta)
        #expect(library.lastSaveError == injectedError.localizedDescription)
        #expect(try Data(contentsOf: pointer) == previousPointer)
        #expect(try FileManager.default.contentsOfDirectory(atPath: generations.path) == previousNames)

        // Restore with the production writer, after removing the injected fault.
        let recovery = RideLibrary(storage: RideStorage(directory: root), preferences: preferences.defaults)
        await recovery.refreshSavedState()
        let restoredMeta = try await recovery.restoreBackup()
        #expect(restoredMeta == previousMeta)
        #expect(try await recovery.savedStore().trains.map(\.id) == ["recover-original"])
        #expect(recovery.backup == nil)
    }

    @Test func failedRestoreKeepsRecoveryAvailableUntilRetryLands() async throws {
        let preferences = try IsolatedPreferences()
        defer { preferences.remove() }
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = RideLibrary(storage: RideStorage(directory: root), preferences: preferences.defaults)
        try await library.snapshotBackup(TrainStore(trains: [train("recover-original")]), reason: .beforeDeleteAll)
        await library.refreshSavedState()
        let previousMeta = try #require(library.backup)
        let pointer = root.appending(path: "train-store.backup-current.json")
        let previousPointer = try Data(contentsOf: pointer)
        let storePath = root.appending(path: "train-store.json")
        try FileManager.default.createDirectory(at: storePath, withIntermediateDirectories: true)

        do {
            _ = try await library.restoreBackup()
            Issue.record("Restore unexpectedly replaced the conflicting directory")
        } catch {
            #expect((error as NSError).domain == NSCocoaErrorDomain)
        }
        #expect(library.backup == previousMeta)
        #expect(try Data(contentsOf: pointer) == previousPointer)
        try FileManager.default.removeItem(at: storePath)

        let restoredMeta = try await library.restoreBackup()
        #expect(restoredMeta == previousMeta)
        #expect(try await library.savedStore().trains.map(\.id) == ["recover-original"])
        #expect(library.backup == nil)
        #expect(FileManager.default.fileExists(atPath: pointer.path) == false)
    }

    private func temporaryDirectory() throws -> URL {
        let root = URL.temporaryDirectory.appending(path: "native-import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// Seeds one original journey through the product import door.
    ///
    /// `runImport` refuses a store that has not finished its initial read, so
    /// this loads an empty library first, then replaces that working set.
    private func baseline(preferences: UserDefaults) async throws -> ItineraryStore {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = RideLibrary(storage: RideStorage(directory: root), preferences: preferences)
        let itineraries = ItineraryStore(preferences: preferences)
        itineraries.load(from: library)
        try await waitUntil { itineraries.canReplace }
        let summary = try await itineraries.runImport(
            text: document("original"), region: .jp, mode: .replaceAll,
            library: library, onProgress: { _ in })
        try #require(summary.imported == 1)
        try #require(summary.save.saved)
        try #require(itineraries.store?.trains.map(\.id) == ["original"])
        return itineraries
    }

    private func train(_ id: String) -> Train {
        Train(id: id, date: "2026-10-11", number: "Native fixture", origin: "東京", destination: "品川",
              stops: [Stop(name: "東京", departure: "09:00"), Stop(name: "品川", arrival: "09:08")], region: "jp")
    }

    private func document(_ id: String) -> String {
        MergedStore.export(TrainStore(trains: [train(id)]))
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(10))
        while condition() == false, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(2))
        }
        try #require(condition(), "Native owner did not reach its expected terminal phase")
    }

    private func screenshotReading() -> TransferGuideOCR.Reading {
        let rows: [[(String, Double)]] = [
            [("09:00→09:08", 10), ("(8分)", 160), ("10月11日(日)", 250)],
            [("09:00", 10), ("発", 70), ("東京", 110)],
            [("1駅", 10), ("JR東海道本線", 110)],
            [("09:08", 10), ("着", 70), ("品川", 110)],
            [("Yahoo!乗換案内", 100)],
        ]
        let lines = rows.enumerated().flatMap { row, tokens in
            tokens.map { text, x in
                TransferGuide.TextLine(text: text,
                    box: TransferGuide.Box(x: x, y: Double(row) * 36, width: Double(text.count) * 14, height: 20))
            }
        }
        return TransferGuideOCR.Reading(lines: lines, documentWidth: 420, documentHeight: 180,
            pageCount: 1, tileCount: 1, rawRows: lines.map(\.text))
    }
}

@MainActor
private final class SuspendedScreenshotRecognizer {
    private var continuation: CheckedContinuation<TransferGuideOCR.Reading, any Error>?
    private var progress: (@Sendable (Int, Int) -> Void)?
    var isSuspended: Bool { continuation != nil }

    func read(progress: @escaping @Sendable (Int, Int) -> Void) async throws -> TransferGuideOCR.Reading {
        self.progress = progress
        let reading = try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
        return reading
    }

    func finish(with reading: TransferGuideOCR.Reading) {
        progress?(1, 1)
        continuation?.resume(returning: reading)
        continuation = nil
        progress = nil
    }
}

private struct IsolatedPreferences {
    let suiteName: String
    let defaults: UserDefaults

    init() throws {
        suiteName = "native-import-preferences-\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    func remove() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
