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
    @discardableResult
    func add(_ train: Train) -> String? {
        let id = itineraries.add(train)
        if let id { itineraries.selectedTrainID = id }
        persist()
        return id
    }

    @discardableResult
    func replace(
        _ train: Train,
        replacing originalID: String
    ) -> ItineraryStore.SaveOutcome {
        let outcome = itineraries.replace(train, replacing: originalID)
        persist()
        return outcome
    }

    func delete(_ id: String) {
        itineraries.delete(id)
        persist()
    }

    func duplicate(_ id: String) {
        itineraries.duplicate(id)
        persist()
    }

    func move(_ id: String, by offset: Int) {
        itineraries.move(id, by: offset)
        persist()
    }

    func toggleVisibility(_ id: String) {
        itineraries.toggleVisibility(id)
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
