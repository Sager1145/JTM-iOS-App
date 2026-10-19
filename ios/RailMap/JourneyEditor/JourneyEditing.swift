import RailApplication
import RailCore

/// Editor rollback for an add or replace that `ItineraryStore` already committed.
///
/// The store publishes the working set and queues the one save. This value
/// only remembers how to undo that publication when the record is still the
/// snapshot that was committed, then lets the store commit the undo. A later
/// edit makes rollback return false without writing over it.
@MainActor
struct JourneyEditing {
    let itineraries: ItineraryStore
    let library: RideLibrary

    struct Added {
        let id: String
        let persistence: Task<RideLibrary.SaveResult, Never>
        /// Deletes the added record only when it is still the committed snapshot.
        let rollback: @MainActor () -> Bool
    }

    struct Replaced {
        let outcome: ItineraryStore.SaveOutcome
        let persistence: Task<RideLibrary.SaveResult, Never>?
        /// Restores the previous record only when the committed snapshot is unchanged.
        let rollback: (@MainActor () -> Bool)?
    }

    init(itineraries: ItineraryStore, library: RideLibrary) {
        self.itineraries = itineraries
        self.library = library
        itineraries.attach(library)
    }

    /// Adds and selects the new journey. The store queues one save.
    ///
    /// `nil` means the add was refused: nothing was selected and nothing was written.
    func addAndPersist(_ train: Train) -> Added? {
        let selectedBefore = itineraries.selectedTrainID
        let commit = itineraries.add(train)
        guard let id = commit.outcome, let persistence = commit.save else { return nil }
        itineraries.selectedTrainID = id
        guard let committed = itineraries.store?.trains.first(where: { $0.id == id }) else {
            return nil
        }
        return Added(
            id: id,
            persistence: persistence,
            rollback: { [self] in
                guard itineraries.store?.trains.first(where: { $0.id == id }) == committed,
                    itineraries.delete(id).outcome
                else { return false }
                if itineraries.selectedTrainID == id || itineraries.selectedTrainID == nil {
                    itineraries.selectedTrainID = selectedBefore
                }
                return true
            })
    }

    /// Pairs the working-set replacement with the one save the store queued.
    /// A refused replacement has no save and no rollback.
    func replaceAndPersist(
        _ train: Train,
        replacing originalID: String
    ) -> Replaced {
        let selectedBefore = itineraries.selectedTrainID
        let original = itineraries.store?.trains.first(where: { $0.id == originalID })
        let commit = itineraries.replace(train, replacing: originalID)
        switch commit.outcome {
        case .saved, .savedKeepingID:
            let recordID: String
            switch commit.outcome {
            case .saved: recordID = train.id
            case let .savedKeepingID(keptID, _): recordID = keptID
            case .refusedImportRunning, .notFound, .unsupportedRegion: preconditionFailure("handled above")
            }
            guard let persistence = commit.save,
                let committed = itineraries.store?.trains.first(where: { $0.id == recordID })
            else {
                return Replaced(outcome: commit.outcome, persistence: commit.save, rollback: nil)
            }
            let selectedAfter = itineraries.selectedTrainID
            return Replaced(
                outcome: commit.outcome,
                persistence: persistence,
                rollback: { [self] in
                    guard let original,
                        itineraries.store?.trains.first(where: { $0.id == recordID }) == committed
                    else { return false }
                    if recordID != original.id,
                        itineraries.store?.trains.contains(where: { $0.id == original.id }) == true
                    {
                        return false
                    }
                    switch itineraries.replace(original, replacing: recordID).outcome {
                    case .saved:
                        if itineraries.selectedTrainID == selectedAfter {
                            itineraries.selectedTrainID = selectedBefore
                        }
                        return true
                    case .savedKeepingID, .refusedImportRunning, .notFound, .unsupportedRegion:
                        return false
                    }
                })
        case .refusedImportRunning, .notFound, .unsupportedRegion:
            return Replaced(outcome: commit.outcome, persistence: nil, rollback: nil)
        }
    }
}

/// Shared draft operations for guided create and the ride editor.
/// The two screens keep their own forms and share timetable draft preparation.
enum JourneyDraftWork {
    static let serviceTypeIDs = ["local", "rapid", "express", "limitedExpress", "highSpeed"]

    struct TimetableDraft: Sendable {
        var train: Train
        var serviceName: String
        var serviceDate: String
        var pattern: TrainServicePatterns.Pattern?
    }

    /// The occurrence applied onto `base`. Remember its evidence with the train actually kept.
    static func timetableDraft(
        from trip: TrainTimetableDatabase.Trip, appliedTo base: Train, ridden: Bool
    ) -> TimetableDraft? {
        guard let train = trip.canApplyToRouteEditor
            ? trip.applying(to: base, ridden: ridden)
            : trip.publishedStopsDraft(to: base, ridden: ridden)
        else { return nil }
        return TimetableDraft(
            train: train,
            serviceName: trip.service.canonicalName,
            serviceDate: trip.serviceDate,
            pattern: trip.canApplyToRouteEditor ? trip.compatibilityPattern() : nil)
    }
}
