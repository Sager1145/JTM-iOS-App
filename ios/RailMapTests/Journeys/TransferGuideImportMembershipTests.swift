import Foundation
import RailPresentation
import Testing
@testable import RailMap

/// A screenshot import opens "ridden" exactly when the editor would file the
/// trip under History, from the journey's first departure on Japan's clock,
/// and every leg of one screenshot is filed together.
@MainActor
struct TransferGuideImportMembershipTests {
    /// 2026-11-11 12:40 in Japan (03:40 UTC).
    private let now = Date(timeIntervalSince1970: 1_794_368_400)
    private var today: Date { RecordDate.date(from: "2026-11-11", in: TransferGuideImport.clock)! }

    @Test func laterTodayIsUpcoming() {
        #expect(TransferGuideImport.membership(date: today, firstDeparture: "18:30", now: now) == .upcoming)
    }

    @Test func alreadyDepartedTodayIsPast() {
        #expect(TransferGuideImport.membership(date: today, firstDeparture: "09:00", now: now) == .past)
    }

    /// A mid-journey screenshot: the first leg left this morning, the later
    /// legs are still ahead. The journey is judged once, by its first included
    /// leg, so no leg is filed apart from the others.
    @Test func midJourneyIsJudgedByItsFirstIncludedLeg() async throws {
        let importer = try await readTwoLegScreenshot()
        let draft = try #require(importer.draft)
        try #require(draft.legs.count == 2)
        var all = draft
        all.date = today
        all.included = [true, true]
        #expect(all.membership(now: now) == .past)
        // First leg excluded: the second leg's 13:10 departure decides.
        var second = all
        second.included = [false, true]
        #expect(second.membership(now: now) == .upcoming)
    }

    /// The ridden answer decides the list for every record, and the default
    /// answer follows the date until the reader chooses one.
    @Test func commitFilesEveryLegByTheRiddenAnswer() async throws {
        let preferences = try IsolatedPreferences()
        defer { preferences.remove() }
        let root = URL.temporaryDirectory.appending(path: "import-membership-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = RideLibrary(storage: RideStorage(directory: root), preferences: preferences.defaults)
        let itineraries = ItineraryStore(preferences: preferences.defaults)
        itineraries.load(from: library)
        try await waitUntil { itineraries.canReplace }

        let importer = try await readTwoLegScreenshot()
        let yesterday = Date().addingTimeInterval(-3 * 86_400)
        let nextWeek = Date().addingTimeInterval(7 * 86_400)
        // The reader has not touched the picker: the answer follows the date.
        importer.setDate(yesterday, existingIDs: [])
        #expect(importer.draft?.ridden == true)
        importer.setDate(nextWeek, existingIDs: [])
        #expect(importer.draft?.ridden == false)
        // Once chosen, the date no longer moves it.
        importer.setRidden(true, existingIDs: [])
        importer.setDate(nextWeek, existingIDs: [])
        #expect(importer.draft?.ridden == true)

        let ids = await importer.commit(into: itineraries, library: library)
        try #require(ids.count == 2)
        let filed = Set((itineraries.store?.trains ?? []).filter { ids.contains($0.id) }.map(\.listMembership))
        #expect(filed == [.past])
    }

    private func readTwoLegScreenshot() async throws -> TransferGuideImport {
        let rows: [[(String, Double)]] = [
            [("09:00→13:40", 10), ("(4時間40分)", 160), ("10月11日(日)", 250)],
            [("09:00", 10), ("発", 70), ("東京", 110)],
            [("1駅", 10), ("JR東海道本線", 110)],
            [("09:08", 10), ("着", 70), ("品川", 110)],
            [("13:10", 10), ("発", 70), ("品川", 110)],
            [("1駅", 10), ("JR山手線", 110)],
            [("13:40", 10), ("着", 70), ("渋谷", 110)],
            [("Yahoo!乗換案内", 100)],
        ]
        let lines = rows.enumerated().flatMap { row, tokens in
            tokens.map { text, x in
                TransferGuide.TextLine(text: text,
                    box: TransferGuide.Box(x: x, y: Double(row) * 36, width: Double(text.count) * 14, height: 20))
            }
        }
        let reading = TransferGuideOCR.Reading(lines: lines, documentWidth: 420, documentHeight: 300,
            pageCount: 1, tileCount: 1, rawRows: lines.map(\.text))
        let importer = TransferGuideImport(recognize: { _, progress in progress(1, 1); return reading })
        importer.read(pages: [Data([0])], names: ["route.png"], stations: [], lines: [], existingIDs: [])
        try await waitUntil { if case .read = importer.phase { return true }; return false }
        return importer
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(10))
        while condition() == false, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(2))
        }
        try #require(condition())
    }

    @Test func tomorrowIsUpcomingAndYesterdayIsPast() throws {
        let tomorrow = try #require(RecordDate.date(from: "2026-11-12", in: TransferGuideImport.clock))
        let yesterday = try #require(RecordDate.date(from: "2026-11-10", in: TransferGuideImport.clock))
        #expect(TransferGuideImport.membership(date: tomorrow, firstDeparture: "00:05", now: now) == .upcoming)
        #expect(TransferGuideImport.membership(date: yesterday, firstDeparture: "23:50", now: now) == .past)
    }
}

private struct IsolatedPreferences {
    let suiteName = "import-membership-\(UUID().uuidString)"
    let defaults: UserDefaults
    init() throws { defaults = try #require(UserDefaults(suiteName: suiteName)) }
    func remove() { defaults.removePersistentDomain(forName: suiteName) }
}
