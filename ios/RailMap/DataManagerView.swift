import RailCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The 資料管理 workspace, answering §5.8's question first: **where does the
/// data on screen come from, and is it safely saved?**
///
/// The previous version of this screen opened with a list of buttons, and the
/// answer to that question was somewhere in the middle of it. The order here
/// is the spec's: source, then anything blocking, then the ordinary task
/// groups, then — separated by real space and folded shut — the operations
/// that destroy things.
struct DataManagerView: View {
    @Environment(AppLocalization.self) private var localization
    /// Optional so this view can be previewed and hosted outside the shell
    /// that publishes the network store; the availability section simply has
    /// nothing to report when it is absent.
    @Environment(RailNetworkStore.self) private var network: RailNetworkStore?
    @Bindable var itineraries: ItineraryStore
    @Bindable var library: RideLibrary

    @State private var flow = ImportFlow()
    @State private var showsImporter = false
    @State private var showsGuideImporter = false
    @State private var showsImportChoice = false
    @State private var importsFile = false
    @State private var exportsFile = false
    @State private var exportDocument = TrainStoreDocument()
    @State private var rawPreviewExpanded = false
    @State private var rawPreview = ""
    @State private var copied = false
    @State private var fileToImport: URL?
    @State private var exportAction: ExportAction?
    private enum ExportAction { case file, clipboard }

    @State private var confirmDeleteSaved = false
    @State private var confirmDeleteAll = false
    /// The sample a long-press asked to replace EVERYTHING with, held while
    /// the confirmation is up so the dialog can name it.
    @State private var replaceCandidate: RideLibrary.Sample?
    @State private var confirmRestore = false

    /// An error that blocks a task stays on the screen next to the thing it
    /// blocked, and is dismissed by the reader — not by a timer (§3.1).
    @State private var operationError: OperationError?

    struct OperationError: Identifiable {
        var id = UUID()
        var titleKey: String
        var detail: String
        var keptKey: String
    }

    var body: some View {
        List {
            sourceSection
            blockingSections
            importSection
            exportSection
            samplesSection
            sampleRegionSections
            availabilitySection
            recoverySection
            dangerSection
        }
        .navigationTitle(localization.text("nav.data", fallback: "Data"))
        .sheet(isPresented: $showsImporter) {
            DataImportView(
                flow: flow, itineraries: itineraries, library: library)
        }
        .sheet(isPresented: $showsGuideImporter) {
            TransferGuideImportView(itineraries: itineraries, library: library)
        }
        .confirmationDialog(
            localization.text("sec.import", fallback: "Import"),
            isPresented: $showsImportChoice,
            titleVisibility: .visible
        ) {
            Button(localization.text("btn.openLocal", fallback: "Open JSON")) {
                showsImportChoice = false
                PresentationHost.afterTeardown { importsFile = true }
            }
            Button(localization.text("sec.importPaste", fallback: "Paste JSON")) {
                showsImportChoice = false
                PresentationHost.afterTeardown {
                    flow.load("", origin: .pasted)
                    showsImporter = true
                }
            }
        }
        .fileImporter(isPresented: $importsFile, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): fileToImport = url
            case .failure(let error): showImportError(error)
            }
        }
        .task(id: fileToImport) {
            guard let url = fileToImport else { return }
            defer { if fileToImport == url { fileToImport = nil } }
            do {
                let data = try await ImportFileReader.read(url)
                let text = await Task.detached(priority: .userInitiated) {
                    String(decoding: data, as: UTF8.self)
                }.value
                try Task.checkCancellation()
                flow.load(text, origin: .file(url.lastPathComponent))
                showsImporter = true
            } catch is CancellationError {
            } catch { showImportError(error) }
        }
        .task(id: exportAction) {
            guard let action = exportAction else { return }
            defer { exportAction = nil }
            guard let text = await itineraries.exportJSON(), !Task.isCancelled else { return }
            switch action {
            case .file:
                exportDocument = TrainStoreDocument(text: text)
                exportsFile = true
            case .clipboard:
                UIPasteboard.general.string = text
                copied = true
            }
        }
        .task(id: copied) {
            guard copied else { return }
            do { try await Task.sleep(for: .seconds(2)); copied = false }
            catch { }
        }
        .overlay {
            if fileToImport != nil || exportAction != nil { ProgressView().padding().background(.regularMaterial, in: Capsule()) }
        }
        .fileExporter(
            isPresented: $exportsFile,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "train-store"
        ) { result in
            if case .failure(let error) = result {
                operationError = OperationError(
                    titleKey: "data.saveFailedTitle",
                    detail: error.localizedDescription,
                    keptKey: "data.errorNothingChanged")
            }
        }
        .task(id: rawPreviewExpanded) {
            rawPreview = ""
            guard rawPreviewExpanded, let text = await itineraries.exportJSON(),
                !Task.isCancelled else { return }
            rawPreview = text
        }
    }

    private func showImportError(_ error: Error) {
        operationError = OperationError(titleKey: "data.errorImportTitle",
            detail: error.localizedDescription, keptKey: "data.errorNothingChanged")
    }

    // MARK: - §5.8 source hero

    private var sourceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.tint)
                        .frame(width: 44, height: 44)
                        .background(Color.accentColor.opacity(0.1), in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(sourceTitle).font(.headline)
                        Text(sourceSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)

                // One filled button per surface (§3.1). There is only one
                // thing to do next here now: everything on this screen acts on
                // the reader's own rides, so importing more of them is it.
                Button {
                    showsImportChoice = true
                } label: {
                    Label(
                        localization.text("sec.import", fallback: "Import"),
                        systemImage: "square.and.arrow.down"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .railMinimumTouchTarget()
                .disabled(itineraries.isImporting || fileToImport != nil)
            }
            .padding(.vertical, 6)
        } footer: {
            Text(localization.dataText("data.storageFootnote"))
        }
    }

    // MARK: - L0

    @ViewBuilder
    private var blockingSections: some View {
        // An import the reader has left running: the sheet can be dismissed
        // without cancelling it, and a store that is being replaced under you
        // has to say so on the screen you are actually looking at.
        if let summary = flow.committingSummary {
            Section {
                DataProgressSummaryView(summary: summary, visibility: flow.visibility) {
                    flow.cancel()
                }
            }
        }

        if case .failed(let message) = itineraries.state {
            Section {
                DataErrorCard(
                    title: localization.dataText("data.loadFailedTitle"),
                    detail: message,
                    kept: localization.dataText("data.loadFailedKept"))
                Button(localization.dataText("data.retryLoad")) {
                    itineraries.load(from: library)
                }
            }
        }

        if let saveError = library.lastSaveError {
            Section {
                DataErrorCard(
                    title: localization.dataText("data.saveFailedTitle"),
                    detail: saveError,
                    kept: localization.dataText("data.saveFailedKept"))
                Button(localization.dataText("data.saveRetry")) {
                    guard let store = itineraries.store else { return }
                    library.save(store)
                }
                .disabled(itineraries.store == nil || exportAction != nil)
            }
        }

        if let operationError {
            Section {
                DataErrorCard(
                    title: localization.dataText(operationError.titleKey),
                    detail: operationError.detail,
                    kept: localization.dataText(operationError.keptKey))
                Button(localization.dataText("data.dismiss")) {
                    self.operationError = nil
                }
            }
        }
    }

    // MARK: - import

    private var importSection: some View {
        Section {
            Button { importsFile = true } label: {
                Label(
                    localization.text("btn.openLocal", fallback: "Open JSON"),
                    systemImage: "folder")
            }
            Button {
                flow.load("", origin: .pasted)
                showsImporter = true
            } label: {
                Label(
                    localization.text("sec.importPaste", fallback: "Paste JSON text"),
                    systemImage: "doc.on.clipboard")
            }
            // A third door, and the only one that does not start from a file
            // this app wrote: a photograph of somebody else's route planner.
            // It lands in the same store through the same `add`, so nothing
            // downstream needs to know a journey arrived this way.
            Button { showsGuideImporter = true } label: {
                Label(
                    localization.guideText("ios.guide.entry"),
                    systemImage: "text.viewfinder")
            }
            .accessibilityIdentifier("guideImportButton")
        } header: {
            Text(localization.dataText("data.importGroup"))
        } footer: {
            Text(localization.dataText("data.preflightDateNote"))
        }
        .disabled(itineraries.isImporting || fileToImport != nil)
    }

    // MARK: - export, in one task group with the raw preview

    private var exportSection: some View {
        Section {
            Button {
                exportAction = .file
            } label: {
                Label(
                    localization.text("btn.exportJson", fallback: "Export JSON"),
                    systemImage: "square.and.arrow.up")
            }
            .disabled(itineraries.store == nil || exportAction != nil)

            Button {
                exportAction = .clipboard
            } label: {
                Label(
                    copied
                        ? localization.dataText("data.copied")
                        : localization.dataText("data.copyJSON"),
                    systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .disabled(itineraries.store == nil || exportAction != nil)

            // §5.8: the raw JSON preview is L4, and ships folded.
            DisclosureGroup(
                isExpanded: $rawPreviewExpanded,
                content: {
                    if rawPreview.isEmpty {
                        ProgressView()
                    } else {
                        Text(rawPreview.prefix(4000))
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                        if rawPreview.count > 4000 {
                            Text(localization.dataText("data.previewTruncated"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                },
                label: {
                    Text(localization.text("sec.rawPreview", fallback: "Raw JSON preview"))
                })
        } header: {
            Text(localization.dataText("data.exportGroup"))
        }
    }

    // MARK: - samples and the reader's own copy

    private var samplesSection: some View {
        Section {
            Button {
                guard let store = itineraries.store else { return }
                library.save(store)
            } label: {
                Label(
                    localization.text("btn.saveAsMine", fallback: "Save current rides"),
                    systemImage: "square.and.arrow.down")
            }
            .disabled(itineraries.store == nil || exportAction != nil)

            Button {
                itineraries.load(from: library)
            } label: {
                Label(
                    localization.text("btn.restoreMine", fallback: "Restore saved rides"),
                    systemImage: "arrow.uturn.backward")
            }
            .disabled(!library.hasSavedStore)
        } header: {
            Text(localization.text("ios.myRides", fallback: "My rides"))
        } footer: {
            Text(localization.dataText("data.storageFootnote"))
        }
        .disabled(itineraries.isImporting || fileToImport != nil)
    }

    /// The seven samples, grouped by the region each belongs to.
    ///
    /// **Loading one adds its rides to the working set.** In the web app the
    /// button replaces the store, because the store is one region's and the
    /// sample is that region's; with one merged store, replacing everything to
    /// see the Macao sample would delete the reader's Japanese rides. So a
    /// sample is folded in, a recovery copy is written first, and loading the
    /// same one twice updates those rides rather than duplicating them.
    ///
    /// The web app's 重置示例 — "this sample IS the store" — survives as the
    /// long-press action, where it has an unambiguous subject.
    /// The last enabled region that actually ships a sample — `us`/`ca` have
    /// none, and comparing against `Region.enabledOrdered.last` hid the
    /// footnote entirely once North America was enabled, because it sorts
    /// after every region this section draws a `Section` for.
    private var lastRegionWithSamples: Region? {
        Region.enabledOrdered.last { !RideLibrary.Sample.forRegion($0).isEmpty }
    }

    private var sampleRegionSections: some View {
        ForEach(Region.enabledOrdered) { region in
            let samples = RideLibrary.Sample.forRegion(region)
            if !samples.isEmpty {
                Section {
                    ForEach(samples) { sample in
                        Button {
                            loadSample(sample, replacingEverything: false)
                        } label: {
                            Label(
                                localization.text(sample.titleKey, fallback: sample.title),
                                systemImage: library.loadedSamples.contains(sample.resource)
                                    ? "checkmark.circle" : "doc.text")
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                // A context menu is itself a presentation on
                                // iOS. Let its controller leave before asking
                                // SwiftUI for the confirmation dialog.
                                PresentationHost.afterTeardown {
                                    replaceCandidate = sample
                                }
                            } label: {
                                Label(
                                    localization.text(
                                        "btn.resetDefaults", fallback: "Replace all rides"),
                                    systemImage: "arrow.counterclockwise")
                            }
                        }
                    }
                } header: {
                    Text(localization.text(region.localizationKey, fallback: region.fallbackName))
                } footer: {
                    if region == lastRegionWithSamples {
                        Text(localization.dataText("data.sampleFootnote"))
                    }
                }
            }
        }
        .disabled(itineraries.isImporting || fileToImport != nil)
    }

    /// Fold a sample in, or — from the long-press action — make it the whole
    /// working set. Either way a recovery copy is written first, because both
    /// can overwrite rides the reader edited.
    private func loadSample(_ sample: RideLibrary.Sample, replacingEverything: Bool) {
        // A `Task` because both doors now place the incoming rides in their
        // region before they are published, and that reads a shipped dataset
        // for the four whose station codes do not say which region they are.
        // The read is off the main actor and the button is disabled while an
        // import runs, so the only thing this changes for the reader is that
        // a Macanese sample arrives already Macanese instead of arriving
        // Japanese and failing to solve.
        Task {
            do {
                // Checked before spending a backup write on an action that
                // was never going to land: `replaceAll`/`merge` refuse under
                // the same conditions this mirrors, but only after the
                // snapshot below has already run.
                guard replacingEverything ? itineraries.canReplace : itineraries.canMutate else {
                    operationError = OperationError(
                        titleKey: "data.loadFailedTitle",
                        detail: localization.dataText("data.errorNothingChanged"),
                        keptKey: "data.loadFailedKept")
                    return
                }
                let incoming = try await library.sample(sample.resource)
                if let store = itineraries.store, !store.trains.isEmpty {
                    // Aborts into the catch below on failure, before either
                    // door touches the working set — a sample load must not
                    // overwrite rides a backup could not be taken of.
                    try await library.snapshotBackup(
                        store, reason: replacingEverything ? .beforeReplace : .beforeImport)
                }
                // `forgetLoadedSamples`/`noteSampleLoaded` only follow a
                // commit that actually landed: an import claiming the store
                // (or, for `replaceAll`, a load still reading it) refuses the
                // fold, and marking the sample "loaded" or forgetting the
                // others on the strength of a refusal would tell the reader
                // something happened that did not.
                let committed: Bool
                if replacingEverything {
                    switch await itineraries.replaceAll(with: incoming, into: library) {
                    case .committed:
                        library.forgetLoadedSamples()
                        committed = true
                    case .refused:
                        committed = false
                    }
                } else {
                    switch await itineraries.merge(incoming, into: library) {
                    case .committed: committed = true
                    case .refused: committed = false
                    }
                }
                if committed {
                    library.noteSampleLoaded(sample.resource)
                } else {
                    operationError = OperationError(
                        titleKey: "data.loadFailedTitle",
                        detail: ItineraryStore.ImportBusy().localizedDescription,
                        keptKey: "data.loadFailedKept")
                }
            } catch {
                operationError = OperationError(
                    titleKey: "data.loadFailedTitle",
                    detail: error.localizedDescription,
                    keptKey: "data.loadFailedKept")
            }
        }
    }

    // MARK: - §8.8 degradation

    @ViewBuilder
    private var availabilitySection: some View {
        if let network {
            Section {
                switch network.state {
                case .idle:
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(
                            localization.dataText(
                                "data.packageLoading",
                                ["region": .string(
                                    Region.enabledOrdered.map(regionName).joined(separator: "・"))]))
                    }
                case .loading(let pending):
                    HStack(spacing: 10) {
                        ProgressView()
                        // Named, because the five packages differ by three
                        // orders of magnitude and "still loading" says nothing
                        // about which one is holding the map up.
                        Text(
                            localization.dataText(
                                "data.packageLoading",
                                ["region": .string(
                                    pending.map(regionName).joined(separator: "・"))]))
                    }
                case .loaded(let regions, let failures, _):
                    ForEach(regions) { load in
                        Label(
                            localization.dataText(
                                "data.packageReady",
                                [
                                    "region": .string(regionName(load.region)),
                                    "count": .number(Double(load.lineCount)),
                                ]),
                            systemImage: "checkmark.circle")
                    }
                    // One package missing blocks that region's MAP. It does
                    // not block the records, and it does not block the other
                    // four regions either — which is the difference between a
                    // degraded app and a broken one.
                    ForEach(failures) { failure in
                        DataErrorCard(
                            title: localization.dataText(
                                "data.packageMissingTitle",
                                ["region": .string(regionName(failure.region))]),
                            detail: [
                                localization.dataText("data.packageMissingImpact"),
                                failure.message,
                            ].joined(separator: "\n"),
                            kept: localization.dataText("data.packageMissingKept"))
                    }
                    if !failures.isEmpty {
                        Button(localization.dataText("data.packageRetry")) {
                            network.loadAll()
                        }
                    }
                }
            } header: {
                Text(localization.dataText("data.availability"))
            }
        }
    }

    // MARK: - §8.6 recovery before confirmation

    /// Shown only when there is something to recover. §5.8 asks for the
    /// recovery path to be offered ahead of the destructive one, which it is:
    /// this sits directly above the danger zone, and every action in there
    /// writes the backup that puts this section on screen.
    @ViewBuilder
    private var recoverySection: some View {
        if let backup = library.backup {
            Section {
                VStack(alignment: .leading, spacing: 3) {
                    Text(
                        localization.dataText(
                            "data.backupAvailable",
                            [
                                "count": .number(Double(backup.trainCount)),
                                "time": .string(
                                    backup.created.formatted(
                                        Date.FormatStyle(date: .abbreviated, time: .shortened)
                                            .locale(localization.locale))),
                            ])
                    )
                    Text(localization.dataText(backup.reason.localizationKey))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                Button {
                    confirmRestore = true
                } label: {
                    Label(
                        localization.dataText("data.restoreBackup"),
                        systemImage: "clock.arrow.circlepath")
                }
                Button(role: .destructive) {
                    library.discardBackup()
                } label: {
                    Label(localization.dataText("data.discardBackup"), systemImage: "trash")
                }
            } header: {
                Text(localization.dataText("data.recovery"))
            }
            .disabled(itineraries.isImporting || fileToImport != nil)
            .confirmationDialog(
                localization.dataText("data.restoreBackup"),
                isPresented: $confirmRestore,
                titleVisibility: .visible
            ) {
                Button(localization.dataText("data.restoreBackup")) {
                    confirmRestore = false
                    PresentationHost.afterTeardown {
                        // A `Task` because the copy is queued behind any save
                        // still in flight. Waiting for it is what keeps the
                        // reload from reading the store the backup was meant
                        // to replace, and what puts a backup that could not be
                        // read in front of the reader instead of only in
                        // `lastSaveError`.
                        Task {
                            do {
                                _ = try await library.restoreBackup()
                                itineraries.load(from: library)
                            } catch {
                                operationError = OperationError(
                                    titleKey: "data.loadFailedTitle",
                                    detail: error.localizedDescription,
                                    keptKey: "data.errorNothingChanged")
                            }
                        }
                    }
                }
            } message: {
                Text(
                    localization.dataText(
                        "data.restoreBackupDetail",
                        ["count": .number(Double(backup.trainCount))]))
            }
        }
    }

    // MARK: - §5.8 danger zone: folded, and set apart

    private var dangerSection: some View {
        Section {
            DisclosureGroup(localization.text("grp.danger", fallback: "Danger zone")) {
                Button(role: .destructive) { confirmDeleteSaved = true } label: {
                    Label(
                        localization.text("btn.clearStorage", fallback: "Delete saved rides"),
                        systemImage: "trash")
                }
                .disabled(!library.hasSavedStore)

                Button(role: .destructive) { confirmDeleteAll = true } label: {
                    Label(localization.dataText("data.deleteAllTitle"), systemImage: "trash.slash")
                }
                .disabled(trainCount == 0)

            }
        }
        .listSectionSpacing(.custom(44))
        .disabled(itineraries.isImporting || fileToImport != nil)
        .confirmationDialog(
            localization.text("btn.clearStorage", fallback: "Delete saved rides"),
            isPresented: $confirmDeleteSaved,
            titleVisibility: .visible
        ) {
            Button(
                localization.text("btn.clearStorage", fallback: "Delete saved rides"),
                role: .destructive
            ) {
                confirmDeleteSaved = false
                PresentationHost.afterTeardown {
                    Task {
                        do {
                            if let store = itineraries.store {
                                try await library.snapshotBackup(store, reason: .beforeDeleteAll)
                            }
                            library.deleteSavedStore()
                            itineraries.load(from: library)
                        } catch {
                            operationError = OperationError(
                                titleKey: "data.loadFailedTitle",
                                detail: error.localizedDescription,
                                keptKey: "data.errorNothingChanged")
                        }
                    }
                }
            }
        } message: {
            Text(
                localization.dataText(
                    "data.deleteSavedScope", ["region": .string(regionName)])
                    + "\n" + localization.dataText("data.deleteAllRecovery"))
        }
        .confirmationDialog(
            localization.dataText("data.deleteAllTitle"),
            isPresented: $confirmDeleteAll,
            titleVisibility: .visible
        ) {
            Button(localization.dataText("data.deleteAllTitle"), role: .destructive) {
                confirmDeleteAll = false
                PresentationHost.afterTeardown {
                    Task {
                        do {
                            // Checked before spending a backup write on a
                            // delete that `deleteAll`'s own `mutate` was
                            // always going to refuse.
                            guard itineraries.canMutate else {
                                operationError = OperationError(
                                    titleKey: "data.loadFailedTitle",
                                    detail: localization.dataText("data.errorNothingChanged"),
                                    keptKey: "data.loadFailedKept")
                                return
                            }
                            if let store = itineraries.store {
                                try await library.snapshotBackup(store, reason: .beforeDeleteAll)
                            }
                            guard itineraries.deleteAll(clearing: library) else {
                                operationError = OperationError(
                                    titleKey: "data.loadFailedTitle",
                                    detail: localization.dataText("data.errorNothingChanged"),
                                    keptKey: "data.loadFailedKept")
                                return
                            }
                            if let store = itineraries.store {
                                library.save(store)
                            }
                        } catch {
                            operationError = OperationError(
                                titleKey: "data.loadFailedTitle",
                                detail: error.localizedDescription,
                                keptKey: "data.errorNothingChanged")
                        }
                    }
                }
            }
        } message: {
            Text(
                localization.dataText(
                    "data.deleteAllScope",
                    ["region": .string(regionName), "count": .number(Double(trainCount))])
                    + "\n" + localization.dataText("data.deleteAllRecovery"))
        }
        // 重置示例, which now names WHICH sample rather than "the one this
        // region ships": the reader long-pressed a specific one, so the
        // dialog can say what it is about to become.
        .confirmationDialog(
            localization.text(
                "confirm.resetDefaults",
                fallback: "Replace the current journeys with the bundled sample?"),
            isPresented: Binding(
                get: { replaceCandidate != nil },
                set: { if !$0 { replaceCandidate = nil } }),
            titleVisibility: .visible
        ) {
            Button(
                localization.text("btn.resetDefaults", fallback: "Reset sample"),
                role: .destructive
            ) {
                let sample = replaceCandidate
                replaceCandidate = nil
                PresentationHost.afterTeardown {
                    if let sample {
                        loadSample(sample, replacingEverything: true)
                    }
                }
            }
        } message: {
            Text(
                (replaceCandidate.map { localization.text($0.titleKey, fallback: $0.title) }
                    ?? "") + "\n" + localization.dataText("data.deleteAllRecovery"))
        }
    }

    // MARK: - the sentences the hero says

    private var trainCount: Int { itineraries.loaded?.trains.count ?? 0 }

    private func regionName(_ region: Region) -> String {
        localization.text(region.localizationKey, fallback: region.fallbackName)
    }

    /// Which regions the working set actually holds — the sentence that used
    /// to be "you are looking at Japan", now that no region is being looked at
    /// in particular.
    private var regionName: String {
        let regions = itineraries.loaded?.regions ?? []
        guard !regions.isEmpty else {
            return localization.text("date.all", fallback: "All")
        }
        return regions.map(regionName).joined(separator: "・")
    }

    private var sourceTitle: String {
        localization.text("ios.myRides", fallback: "My rides")
    }

    private var sourceSubtitle: String {
        guard itineraries.loaded != nil else {
            return localization.dataText("data.readingJourneys")
        }
        let count: [String: Localization.Param] = ["count": .number(Double(trainCount))]
        guard library.hasSavedStore else {
            return localization.dataText("data.notSavedOnDevice", count)
        }
        let saved = localization.dataText("data.savedOnDevice", count)
        guard let date = library.savedStoreDate else { return saved }
        return saved + " · "
            + date.formatted(
                Date.FormatStyle(date: .abbreviated, time: .shortened)
                    .locale(localization.locale))
    }
}
