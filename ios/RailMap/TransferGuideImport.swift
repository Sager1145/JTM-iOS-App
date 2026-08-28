import Foundation
import Observation
import RailCore
import RailPresentation
import SwiftUI

// =========================================================================
//  TransferGuideImport.swift — one attempt at turning screenshots into
//  journeys, as a state machine the interface can render.
//
//  Deliberately shaped like ``ImportFlow``, and for the same reason: the
//  store owns the journeys, this owns one attempt at adding some, including
//  the attempts that are abandoned — which never reach the store at all.
//
//  The one decision this type makes that the parser cannot is the one the
//  reader is here for: whether these journeys HAPPENED or are going to. Both
//  produce the same stations, times and geometry; they differ in
//  `ride_segment`, which is what the mileage statistics count. A plan that
//  counted itself would report kilometres nobody has travelled.
// =========================================================================

@MainActor
@Observable
final class TransferGuideImport {

    enum Phase {
        case waiting
        case reading(done: Int, total: Int)
        case read
        /// A catalog key and a record value, kept apart. The interface writes
        /// the sentence; `detail` is the megapixel count or the framework's own
        /// message, which is not a key and must never be sent to one.
        case failed(key: String, detail: String)
        /// What was committed. The sheet stays open on this rather than
        /// vanishing: three records arriving silently is indistinguishable
        /// from none arriving.
        case imported(count: Int)
    }

    /// Everything the preview shows and the reader can change before
    /// committing. A value: cancelling the sheet is the whole undo.
    struct Draft {
        var route: TransferGuide.Route
        var reading: TransferGuideOCR.Reading
        /// The day the journey is on. Seeded from the screenshot where it
        /// printed one and from today where it did not, and editable either
        /// way — a screenshot has no year on it.
        var date: Date
        /// Whether the day came off the screenshot rather than the clock.
        var dateWasRead: Bool
        /// Which app took the screenshot. Worked out from the layout, not from
        /// the reader — there is one door, and it opens on both.
        var source: TransferGuide.Source
        /// The reader's answer to "did this happen?".
        var ridden: Bool
        /// One flag per ridable leg.
        var included: [Bool]
        /// The records as they stand, rebuilt whenever any of the above moves.
        var build: TransferGuide.BuildResult
        /// Which record each leg became. Kept rather than re-derived from the
        /// endpoints: an out-and-back journey has two legs with the same two
        /// station names, and matching by name would hand the second one the
        /// first one's stations.
        var recordByLeg: [Int: Int] = [:]

        var legs: [TransferGuide.Leg] { route.ridableLegs }
    }

    private(set) var phase: Phase = .waiting
    /// The file names, for the source row. Screenshots picked from the photo
    /// library have none, so this can be shorter than the page count.
    private(set) var pageNames: [String] = []
    private(set) var draft: Draft?
    private var pages: [Data] = []
    private var index = StationIndex([])
    private var task: Task<Void, Never>?

    var isRunning: Bool {
        if case .reading = phase { return true }
        return false
    }

    // MARK: - reading

    /// Reads the chosen screenshots and parses them into a draft.
    ///
    /// Cancels whatever was running: a reader who picks a second set of images
    /// while the first is still being recognised means the second set.
    func read(
        pages: [Data], names: [String], stations: [RailNetworkStore.DrawnStation],
        lines: [RailNetworkStore.DrawnLine], existingIDs: Set<String>
    ) {
        task?.cancel()
        self.pages = pages
        pageNames = names
        index = Self.index(stations: stations, lines: lines)
        phase = .reading(done: 0, total: 1)

        // A strong capture, not a weak one. `[weak self]` would make `self` a
        // captured VARIABLE, which the progress closure — a `@Sendable` one
        // running off this actor — may not read. The cycle it creates lasts
        // exactly as long as the recognition does, and `cancel()` ends it.
        task = Task { [self] in
            do {
                let reading = try await TransferGuideOCR.read(pages) { done, total in
                    Task { @MainActor in
                        guard self.isRunning else { return }
                        self.phase = .reading(done: done, total: total)
                    }
                }
                try Task.checkCancellation()
                await MainActor.run { self.parsed(reading, existingIDs: existingIDs) }
            } catch is CancellationError {
                return
            } catch {
                let failure = error as? TransferGuideOCR.Failure
                await MainActor.run {
                    self.phase = .failed(
                        key: Self.key(for: failure),
                        detail: failure == nil ? error.localizedDescription : Self.detail(failure))
                }
            }
        }
    }

    private static func key(for failure: TransferGuideOCR.Failure?) -> String {
        switch failure {
        case .undecodable: "ios.guide.failUndecodable"
        case .tooLarge: "ios.guide.failTooLarge"
        case .noText: "ios.guide.failNoText"
        case .unavailable: "ios.guide.failUnavailable"
        case nil: "ios.guide.failUndecodable"
        }
    }

    private static func detail(_ failure: TransferGuideOCR.Failure?) -> String {
        if case .tooLarge(let megapixels) = failure { return "\(megapixels) MP" }
        return ""
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    private func parsed(_ reading: TransferGuideOCR.Reading, existingIDs: Set<String>) {
        let read = TransferGuide.read(reading.lines)
        let route = read.route
        let now = Date()
        let today = RecordDate.todayParts(in: Self.clock, at: now)
        var date = RecordDate.date(from: today)
        var wasRead = false
        if let month = route.header.month, let day = route.header.day,
            let text = TransferGuide.calendarDate(
                month: month, day: day, year: route.header.year, today: today),
            let parsed = RecordDate.date(from: text)
        {
            date = parsed
            wasRead = true
        }

        var draft = Draft(
            route: route,
            reading: reading,
            date: date,
            dateWasRead: wasRead,
            source: read.source,
            // A journey in the future was not ridden yesterday, and one in the
            // past is not a plan. The reader can say otherwise; this is only
            // which answer the screen opens on.
            //
            // Two civil dates rather than two instants, both on Japan's clock:
            // the screenshot is of a Japanese journey, so "has this happened?"
            // is asked where the train is. A reader in London opening the sheet
            // at 19:00 is looking at a journey whose day in Japan has already
            // turned, and comparing the picker's midnight against `Date()`
            // would have called it a plan.
            ridden: Self.clock.isTodayOrEarlier(RecordDate.text(from: date), at: now),
            included: route.ridableLegs.map { _ in true },
            build: TransferGuide.BuildResult())
        rebuild(&draft, existingIDs: existingIDs)
        self.draft = draft
        phase = .read
    }

    // MARK: - the reader's changes

    func setDate(_ date: Date, existingIDs: Set<String>) {
        guard var draft else { return }
        draft.date = date
        rebuild(&draft, existingIDs: existingIDs)
        self.draft = draft
    }

    func setRidden(_ ridden: Bool, existingIDs: Set<String>) {
        guard var draft else { return }
        draft.ridden = ridden
        rebuild(&draft, existingIDs: existingIDs)
        self.draft = draft
    }

    func setIncluded(_ included: Bool, at position: Int, existingIDs: Set<String>) {
        guard var draft, draft.included.indices.contains(position) else { return }
        draft.included[position] = included
        rebuild(&draft, existingIDs: existingIDs)
        self.draft = draft
    }

    /// Rebuilds every record from the draft.
    ///
    /// Whole rather than incremental on purpose: the record ids are numbered
    /// by position, the station chain is solved across the WHOLE journey, and
    /// dropping a leg in the middle changes both. Rebuilding four records is
    /// nothing; keeping two ways of producing them in step is not.
    private func rebuild(_ draft: inout Draft, existingIDs: Set<String>) {
        var route = draft.route
        var kept: [TransferGuide.Leg] = []
        var recordByLeg: [Int: Int] = [:]
        for (position, leg) in draft.legs.enumerated()
        where draft.included.indices.contains(position) && draft.included[position] {
            recordByLeg[position] = kept.count
            kept.append(leg)
        }
        route.legs = kept
        draft.recordByLeg = recordByLeg
        draft.build = TransferGuide.build(
            route: route,
            options: TransferGuide.BuildOptions(
                date: RecordDate.text(from: draft.date),
                region: Region.jp.code,
                idPrefix: "yahoo",
                ridden: draft.ridden,
                existingIDs: existingIDs),
            stations: index)
    }

    // MARK: - committing

    /// Adds the drafted records to the store and writes it to this device.
    ///
    /// Returns the ids that landed. The store may keep an id of its own where
    /// one collided, which is why this reports what was added rather than what
    /// was asked for.
    @discardableResult
    func commit(into itineraries: ItineraryStore, library: RideLibrary) async -> [String] {
        guard let draft else { return [] }
        var added: [String] = []
        for train in draft.build.trains {
            if let id = itineraries.add(train) { added.append(id) }
        }
        // Every surface that changes a journey also persists it — otherwise
        // the import survives until the next launch and no further. Awaited,
        // because the screen says "imported 3" immediately afterwards, and a
        // write still queued behind another one has not landed yet.
        if let store = itineraries.store { await library.save(store).value }
        phase = .imported(count: added.count)
        return added
    }

    // MARK: - the clock

    /// The clock this importer's journeys are dated on.
    ///
    /// Japan's, for the same reason ``index(stations:lines:)`` reads only
    /// Japan's stations: Yahoo! 乗換案内 plans Japanese journeys, so a
    /// screenshot of one is a Japanese journey, and the day it is on is the
    /// day it is on in Japan. Nothing here converts a time the screenshot
    /// printed — 22:47 at 品川 is 22:47, and rewriting it into the reader's
    /// own zone would be this app editing somebody else's timetable.
    static let clock = RegionClock.japan

    // MARK: - the station table

    /// The rail package as the resolver needs it.
    ///
    /// Japan only, and that is not a limitation being papered over: Yahoo!
    /// 乗換案内 plans Japanese journeys, so a screenshot of one is a Japanese
    /// journey. Offering the region picker the JSON importer has would be
    /// offering a choice with one right answer.
    private static func index(
        stations: [RailNetworkStore.DrawnStation], lines: [RailNetworkStore.DrawnLine]
    ) -> StationIndex {
        var lineByID: [String: RailNetworkStore.DrawnLine] = [:]
        for line in lines where line.region == .jp { lineByID[line.id] = line }
        var entries: [StationIndex.Entry] = []
        entries.reserveCapacity(stations.count)
        for station in stations where station.region == .jp {
            let line = lineByID[station.lineID]
            entries.append(
                StationIndex.Entry(
                    code: station.stationCode,
                    name: station.name,
                    coordinate: station.coordinate,
                    line: StationIndex.LineRef(
                        name: line?.name ?? "",
                        operatorName: line?.operatorName,
                        colorHex: line?.colorHex)))
        }
        return StationIndex(entries)
    }
}
