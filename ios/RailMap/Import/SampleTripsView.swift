import RailCore
import SwiftUI

/// The one page for sample trips, opened from a single row in the Data Library.
///
/// Samples used to be seven rows in up to five sections of the Data Library,
/// added by one tap with no question, replaced by a hidden long-press and
/// impossible to take out again (audit B5). Here:
///
/// - tapping a sample asks before it adds anything;
/// - "Replace all trips" is a visible row, and asks too;
/// - "Remove sample trips" deletes exactly the trips the samples added, by
///   their identifiers, and keeps every trip the reader made.
///
/// **Adding folds the sample's trips into the working set.** With one merged
/// store, replacing everything to see the Macao sample would delete the
/// reader's Japanese trips. Adding the same sample twice updates its trips
/// rather than duplicating them. Only "Replace all trips" discards the
/// reader's own trips, so only it writes a backup first, as does removing.
struct SampleTripsView: View {
    @Environment(AppLocalization.self) private var localization
    @Bindable var itineraries: ItineraryStore
    @Bindable var library: RideLibrary

    /// The sample a tap asked to add, held while the dialog is up so it can
    /// name it.
    @State private var addCandidate: RideLibrary.Sample?
    /// The sample "Replace all trips" was asked for.
    @State private var replaceCandidate: RideLibrary.Sample?
    @State private var confirmRemove = false
    /// Ids every bundled sample adds; read once off the main actor.
    @State private var sampleIDs: Set<String> = []
    @State private var operationError: String?

    /// Trips in the working set that a sample added.
    private var sampleTripCount: Int {
        guard !sampleIDs.isEmpty else { return 0 }
        return itineraries.loaded?.trains.reduce(0) { $0 + (sampleIDs.contains($1.id) ? 1 : 0) } ?? 0
    }

    private var lastRegionWithSamples: Region? {
        Region.enabledOrdered.last { !RideLibrary.Sample.forRegion($0).isEmpty }
    }

    var body: some View {
        List {
            if let operationError {
                Section {
                    DataErrorCard(
                        title: localization.text("data.loadFailedTitle"),
                        detail: operationError,
                        kept: localization.text("data.loadFailedKept"))
                    Button(localization.text("data.dismiss")) { self.operationError = nil }
                }
            }
            ForEach(Region.enabledOrdered) { region in
                let samples = RideLibrary.Sample.forRegion(region)
                if !samples.isEmpty {
                    Section {
                        ForEach(samples) { sample in
                            Button {
                                addCandidate = sample
                            } label: {
                                Label(
                                    localization.text(sample.titleKey, fallback: sample.title),
                                    systemImage: library.loadedSamples.contains(sample.resource)
                                        ? "checkmark.circle" : "doc.text")
                            }
                            .accessibilityIdentifier("sampleTrips-\(sample.resource)")
                        }
                    } header: {
                        Text(localization.text(region.localizationKey, fallback: region.fallbackName))
                    } footer: {
                        if region == lastRegionWithSamples {
                            Text(localization.text("data.sampleFootnote"))
                        }
                    }
                }
            }
            replaceSection
            removeSection
        }
        .disabled(itineraries.isImporting)
        .navigationTitle(localization.text("data.sampleTrips"))
        .navigationBarTitleDisplayMode(.inline)
        .task { sampleIDs = await library.allSampleTripIDs() }
        .confirmationDialog(
            addCandidate.map { localization.text($0.titleKey, fallback: $0.title) } ?? "",
            isPresented: Binding(
                get: { addCandidate != nil },
                set: { if !$0 { addCandidate = nil } }),
            titleVisibility: .visible,
            presenting: addCandidate
        ) { sample in
            Button(localization.text("data.sampleAdd")) {
                load(sample, replacingEverything: false)
            }
            .accessibilityIdentifier("sampleAddConfirm")
        } message: { _ in
            Text(localization.text("data.sampleAddDetail"))
        }
        .confirmationDialog(
            localization.text("data.sampleReplaceAll"),
            isPresented: Binding(
                get: { replaceCandidate != nil },
                set: { if !$0 { replaceCandidate = nil } }),
            titleVisibility: .visible,
            presenting: replaceCandidate
        ) { sample in
            Button(localization.text("data.sampleReplaceAll"), role: .destructive) {
                load(sample, replacingEverything: true)
            }
            .accessibilityIdentifier("sampleReplaceConfirm")
        } message: { sample in
            Text(
                localization.text(sample.titleKey, fallback: sample.title)
                    + "\n" + localization.text("data.deleteAllRecovery"))
        }
        .confirmationDialog(
            localization.text("data.sampleRemove"),
            isPresented: $confirmRemove,
            titleVisibility: .visible
        ) {
            Button(localization.text("data.sampleRemove"), role: .destructive) {
                removeSampleTrips()
            }
            .accessibilityIdentifier("sampleRemoveConfirm")
        } message: {
            Text(
                localization.text(
                    "data.sampleRemoveDetail", params: ["count": .number(Double(sampleTripCount))])
                    + "\n" + localization.text("data.deleteAllRecovery"))
        }
    }

    // MARK: - replace and remove

    private var replaceSection: some View {
        Section {
            Menu {
                ForEach(Region.enabledOrdered) { region in
                    ForEach(RideLibrary.Sample.forRegion(region)) { sample in
                        Button(localization.text(sample.titleKey, fallback: sample.title)) {
                            replaceCandidate = sample
                        }
                    }
                }
            } label: {
                Label(
                    localization.text("data.sampleReplaceAll"),
                    systemImage: "arrow.counterclockwise")
            }
            .accessibilityIdentifier("sampleReplaceAllMenu")
        } footer: {
            Text(localization.text("data.sampleReplaceAllNote"))
        }
    }

    private var removeSection: some View {
        Section {
            Button(role: .destructive) {
                confirmRemove = true
            } label: {
                Label(localization.text("data.sampleRemove"), systemImage: "trash")
            }
            .disabled(sampleTripCount == 0)
            .accessibilityIdentifier("sampleRemoveButton")
        } footer: {
            Text(localization.text("data.sampleRemoveNote"))
        }
    }

    // MARK: - actions

    /// Fold a sample in, or make it the whole working set. Only the second
    /// writes a recovery copy first: it discards the reader's own trips, while
    /// a fold replaces only that sample's trips with their bundled copies.
    private func load(_ sample: RideLibrary.Sample, replacingEverything: Bool) {
        Task {
            do {
                // Checked before spending a backup write on an action that
                // was never going to land.
                guard replacingEverything ? itineraries.canReplace : itineraries.canMutate else {
                    operationError = localization.text("data.errorNothingChanged")
                    return
                }
                let incoming = try await library.sample(sample.resource)
                if replacingEverything, let store = itineraries.store, !store.trains.isEmpty {
                    try await library.snapshotBackup(store, reason: .beforeReplace)
                }
                // The "loaded" note only follows a commit that landed: an
                // import claiming the store refuses the fold.
                let committed: Bool
                if replacingEverything {
                    switch try await itineraries.replaceAll(with: incoming, into: library).outcome {
                    case .committed:
                        library.forgetLoadedSamples()
                        committed = true
                    case .refused:
                        committed = false
                    }
                } else {
                    switch try await itineraries.merge(
                        incoming, into: library,
                        legacySampleIDs: SampleLegacyRideIDs.map(for: sample.resource)).outcome {
                    case .committed: committed = true
                    case .refused: committed = false
                    }
                }
                if committed {
                    library.noteSampleLoaded(sample.resource)
                } else {
                    operationError = ItineraryStore.ImportBusy().localizedDescription
                }
            } catch {
                operationError = error.localizedDescription
            }
        }
    }

    /// Deletes the trips whose identifiers a sample carries and keeps the rest.
    private func removeSampleTrips() {
        Task {
            do {
                guard itineraries.canMutate else {
                    operationError = localization.text("data.errorNothingChanged")
                    return
                }
                if let store = itineraries.store {
                    try await library.snapshotBackup(store, reason: .beforeRemoveSamples)
                }
                let ids = await library.allSampleTripIDs()
                guard itineraries.removeTrains(withIDs: ids, clearing: library).outcome != nil else {
                    operationError = localization.text("data.errorNothingChanged")
                    return
                }
            } catch {
                operationError = error.localizedDescription
            }
        }
    }
}
