import RailCore

/// The workspace's synchronous journey mutations and their persistence edge.
///
/// `ItineraryStore` owns the in-memory transitions. This value pairs each
/// ordinary edit with one snapshot save, so a caller cannot update the working
/// set and forget to write the same generation to the reader's library.
@MainActor
struct JourneyEditing {
    let itineraries: ItineraryStore
    let library: RideLibrary

    struct Added {
        let id: String
        let persistence: Task<Bool, Never>
        let rollback: @MainActor () -> Bool
    }

    struct Replaced {
        let outcome: ItineraryStore.SaveOutcome
        let persistence: Task<Bool, Never>?
        let rollback: (@MainActor () -> Bool)?
    }

    /// Adds and selects the new journey before its snapshot is handed off.
    ///
    /// `nil` means the add was refused (an import owns the store, or the
    /// working set is not there yet) as well as meaning "no id yet" — either
    /// way there is nothing to select or persist.
    @discardableResult
    func add(_ train: Train) -> String? {
        addAndPersist(train)?.id
    }

    /// Returns the exact write started for this mutation so editor UI can
    /// remain open until that write has actually succeeded.
    func addAndPersist(_ train: Train) -> Added? {
        let selectedBefore = itineraries.selectedTrainID
        guard let id = itineraries.add(train) else { return nil }
        itineraries.selectedTrainID = id
        guard let committed = itineraries.store?.trains.first(where: { $0.id == id }) else {
            return nil
        }
        return Added(
            id: id,
            persistence: persistenceTask(),
            rollback: { [itineraries] in
                guard itineraries.store?.trains.first(where: { $0.id == id }) == committed,
                    itineraries.delete(id)
                else { return false }
                if itineraries.selectedTrainID == id || itineraries.selectedTrainID == nil {
                    itineraries.selectedTrainID = selectedBefore
                }
                return true
            })
    }

    @discardableResult
    func replace(
        _ train: Train,
        replacing originalID: String
    ) -> ItineraryStore.SaveOutcome {
        replaceAndPersist(train, replacing: originalID).outcome
    }

    /// Pairs the synchronous working-set replacement with its asynchronous
    /// disk result. Refused mutations have no persistence task.
    func replaceAndPersist(
        _ train: Train,
        replacing originalID: String
    ) -> Replaced {
        let selectedBefore = itineraries.selectedTrainID
        let original = itineraries.store?.trains.first(where: { $0.id == originalID })
        let outcome = itineraries.replace(train, replacing: originalID)
        switch outcome {
        case .saved, .savedKeepingID:
            let recordID: String
            switch outcome {
            case .saved: recordID = train.id
            case let .savedKeepingID(keptID, _): recordID = keptID
            case .refusedImportRunning, .notFound: preconditionFailure("handled above")
            }
            let committed = itineraries.store?.trains.first(where: { $0.id == recordID })
            let selectedAfter = itineraries.selectedTrainID
            return Replaced(
                outcome: outcome,
                persistence: persistenceTask(),
                rollback: { [itineraries] in
                    guard let original, let committed,
                        itineraries.store?.trains.first(where: { $0.id == recordID }) == committed
                    else { return false }
                    if recordID != original.id,
                        itineraries.store?.trains.contains(where: { $0.id == original.id }) == true
                    {
                        return false
                    }
                    switch itineraries.replace(original, replacing: recordID) {
                    case .saved:
                        if itineraries.selectedTrainID == selectedAfter {
                            itineraries.selectedTrainID = selectedBefore
                        }
                        return true
                    case .savedKeepingID, .refusedImportRunning, .notFound:
                        return false
                    }
                })
        case .refusedImportRunning, .notFound:
            return Replaced(outcome: outcome, persistence: nil, rollback: nil)
        }
    }

    func delete(_ id: String) {
        guard itineraries.delete(id) else { return }
        persist()
    }

    func duplicate(_ id: String) {
        guard itineraries.duplicate(id) != nil else { return }
        persist()
    }

    func move(_ id: String, by offset: Int) {
        guard itineraries.move(id, by: offset) else { return }
        persist()
    }

    func toggleVisibility(_ id: String) {
        guard itineraries.toggleVisibility(id) else { return }
        persist()
    }

    @discardableResult
    func rebuildRouteSections(_ id: String) -> Int? {
        guard let count = itineraries.rebuildRouteSections(id) else { return nil }
        persist()
        return count
    }

    @discardableResult
    func persist() -> Task<Bool, Never>? {
        guard itineraries.store != nil else { return nil }
        return persistenceTask()
    }

    private func persistenceTask() -> Task<Bool, Never> {
        // A successful ItineraryStore mutation requires a working set. Keep a
        // false result for the invariant breach so callers still retain their
        // editor rather than treating the missing write as success.
        guard let store = itineraries.store else { return Task { false } }
        return library.save(store)
    }
}
