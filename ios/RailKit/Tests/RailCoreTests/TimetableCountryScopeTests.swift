import Foundation
import Testing
@testable import RailCore

struct TimetableCountryScopeTests {
    @Test func foreignDraftsCannotReceiveJapaneseTimetableFacts() throws {
        let database = try #require(TrainTimetableDatabase.bundled())
        let trip = try #require(try database.trips(on: "2026-09-30").first { $0.passengerStops.count >= 2 })
        for region in ["tw", "hk", "mo", "kr", "us", "ca", "unknown"] {
            let draft = Train(id: region, number: "", origin: "", destination: "", stops: [], region: region)
            #expect(TrainTimetableDatabase.bundled(country: region) == nil)
            #expect(!TrainTimetableDatabase.accepts(draft))
            #expect(trip.publishedStopsDraft(to: draft) == nil)
            #expect(trip.applying(to: draft) == nil)
            #expect(try JourneyEnglishName.official(for: draft, database: database) == nil)
        }
        for code in ["tw-official-1", "hk-mtr-1", "TRA-1000", "us-official-1", "ca-official-1"] {
            let legacy = Train(id: code, number: "", origin: "", destination: "",
                               stops: [Stop(name: "", n02StationCode: code)])
            #expect(!TrainTimetableDatabase.accepts(legacy))
            #expect(trip.publishedStopsDraft(to: legacy) == nil)
            #expect(TimetableTripMatch.candidates(for: legacy, among: [trip]).isEmpty)
        }
        let mislabeled = Train(id: "mislabeled", number: "", origin: "", destination: "",
                               stops: [Stop(name: "", n02StationCode: "US-AMTRAK-WAS")], region: "jp")
        #expect(!TrainTimetableDatabase.accepts(mislabeled))
        #expect(trip.publishedStopsDraft(to: mislabeled) == nil)
        let blank = Train(id: "legacy-jp", number: "", origin: "", destination: "", stops: [])
        #expect(TrainTimetableDatabase.accepts(blank))
        #expect(trip.publishedStopsDraft(to: blank)?.region == "jp")
    }

    @Test func appBundleArtifactTakesPriorityEvenWhenIncompatible() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "timetable-\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>test.timetable</string></dict></plist>".utf8)
            .write(to: directory.appending(path: "Info.plist"))
        let artifact = directory.appending(path: "train-service-timetable.sqlite")
        try Data("incompatible-artifact".utf8).write(to: artifact)
        let bundle = try #require(Bundle(url: directory))
        #expect(TrainTimetableDatabase.bundledURL(in: bundle)?.standardizedFileURL == artifact.standardizedFileURL)
        #expect(TrainTimetableDatabase.bundled(bundle: bundle) == nil)
    }
}
