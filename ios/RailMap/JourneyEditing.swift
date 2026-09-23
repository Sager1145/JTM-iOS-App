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

    /// Adds and selects the new journey before its snapshot is handed off.
    ///
    /// `nil` means the add was refused (an import owns the store, or the
    /// working set is not there yet) as well as meaning "no id yet" — either
    /// way there is nothing to select or persist.
    @discardableResult
    func add(_ train: Train) -> String? {
        guard let id = itineraries.add(train) else { return nil }
        itineraries.selectedTrainID = id
        persist()
        return id
    }

    @discardableResult
    func replace(
        _ train: Train,
        replacing originalID: String
    ) -> ItineraryStore.SaveOutcome {
        let outcome = itineraries.replace(train, replacing: originalID)
        switch outcome {
        case .saved, .savedKeepingID:
            persist()
        case .refusedImportRunning, .notFound:
            break
        }
        return outcome
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
        let count = itineraries.rebuildRouteSections(id)
        persist()
        return count
    }

    func persist() {
        guard let store = itineraries.store else { return }
        library.save(store)
    }
}
