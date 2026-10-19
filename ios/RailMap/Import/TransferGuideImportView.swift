import PhotosUI
import RailCore
import SwiftUI
import UniformTypeIdentifiers

// =========================================================================
//  TransferGuideImportView.swift — choose, read, check, commit.
//
//  The same order the JSON importer uses (§8.7), for the same reason: nothing
//  reaches the store from a screen that has not already said what will be
//  added. It matters more here, not less. A JSON file is what its author
//  wrote; a screenshot is what a text recogniser THINKS it saw, so the
//  preview is not a courtesy — it is the only place a misread digit can be
//  caught before it becomes a journey.
//
//  Date, ridden status and included legs are edited here. Optional AI
//  additions are reviewed in a separate sheet and only fill missing fields.
//  Corrections to recognized values remain in the ordinary ride editor.
// =========================================================================

struct TransferGuideImportView: View {
    @Environment(AppLocalization.self) private var localization
    @Environment(RailNetworkStore.self) private var network: RailNetworkStore?
    @Environment(\.dismiss) private var dismiss
    @Bindable var itineraries: ItineraryStore
    @Bindable var library: RideLibrary
    @State private var flow = TransferGuideImport()

    @State private var picked: [PhotosPickerItem] = []
    @State private var choosesFiles = false
    @State private var expandedLeg: Int?
    @State private var showsRaw = false
    @State private var showsAICompletion = false
    @State private var loadTask: Task<Void, Never>?
    @State private var isLoadingPages = false
    @State private var loadError: String?
    @State private var completionCatalogResult: Result<EditorCatalog, Error>?
    @State private var catalogAttempt = 0
    private var completionCatalog: EditorCatalog? {
        if case .success(let catalog) = completionCatalogResult { return catalog }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                sourceSection
                if isLoadingPages { readingSection(done: 0, total: 1) }
                if case .failure(let error) = completionCatalogResult {
                    Section {
                        Text(error.localizedDescription).font(.footnote)
                        Button(localization.text("ios.journeyShare.retry")) { catalogAttempt += 1 }
                    }
                }
                if let loadError { failureSection(key: "ios.guide.failUndecodable", detail: loadError) }
                switch flow.phase {
                case .waiting: EmptyView()
                case .reading(let done, let total): readingSection(done: done, total: total)
                case .failed(let key, let detail): failureSection(key: key, detail: detail)
                case .imported(let count, let saveError): importedSection(count, saveError: saveError)
                case .read:
                    if let draft = flow.draft {
                        summarySection(draft)
                        statusSection(draft)
                        legsSection(draft)
                        matchSection(draft)
                        noteSection(draft)
                        rawSection(draft)
                        Section {
                            Button { showsAICompletion = true } label: {
                                Label(localization.text("ios.ai.title", fallback: "AI completion"), systemImage: "sparkles")
                            }
                            .disabled(!draft.build.trains.contains(where: completionEligible))
                            .accessibilityIdentifier("guideAICompletion")
                        }
                    }
                }
            }
            .disabled(flow.isCommitting)
            .sheet(isPresented: $showsAICompletion) {
                if let draft = flow.draft {
                    JourneyCompletionView(trains: draft.build.trains,
                        context: draft.reading.rawRows.joined(separator: "\n")) { trains in
                        flow.applyCompletion(trains)
                    }
                }
            }
            .navigationTitle(localization.text("ios.guide.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localization.text("ios.cancel", fallback: "Cancel")) {
                        loadTask?.cancel()
                        flow.cancel()
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { actionBar }
            // This screen reads Japanese screenshots against the Japanese
            // package, so it is the surface that knows it needs that region —
            // which is where `RailNetworkStore.ensure(_:)` says the ask
            // belongs. Until now nothing here asked: `hasNetwork` waited for a
            // decode that only a pan across Japan with the network switched on
            // (or a visit to Passport, which used to decode every region to
            // frame a camera) would ever start, so opening the importer on a
            // fresh launch could sit on 路網載入中 indefinitely. Idempotent —
            // the second call is a set lookup.
            .task(id: catalogAttempt) {
                network?.ensure(.jp)
                do {
                    let loaded = try await Task.detached(priority: .utility) {
                        try loadCatalog(for: .jp)
                    }.value
                    guard !Task.isCancelled else { return }
                    completionCatalogResult = .success(loaded)
                } catch is CancellationError {
                    return
                } catch {
                    guard !Task.isCancelled else { return }
                    completionCatalogResult = .failure(error)
                }
            }
            .onDisappear { loadTask?.cancel(); flow.cancel() }
            .onChange(of: picked) { _, items in load(items) }
            .fileImporter(
                isPresented: $choosesFiles, allowedContentTypes: [.image],
                allowsMultipleSelection: true
            ) { result in
                load(files: result)
            }
        }
    }

    // MARK: - choosing

    @ViewBuilder
    private var sourceSection: some View {
        // `PhotosPicker`'s label builder is `@Sendable`, so it may not read
        // this view's main-actor state — and a localized string read from
        // inside it is exactly that. Resolving it out here, where the body
        // already is on the main actor, leaves the closure capturing a plain
        // `String`. The other pickers on this screen take their label from a
        // normal `Button`, which is why only this one needed it.
        let choosePhotos = localization.text("ios.guide.choosePhotos")
        Section {
            PhotosPicker(
                selection: $picked, maxSelectionCount: 8, selectionBehavior: .ordered, matching: .images,
                photoLibrary: .shared()
            ) {
                Label(choosePhotos, systemImage: "photo")
            }
            .accessibilityIdentifier("guidePhotoPicker")
            .disabled(isLoadingPages || flow.isRunning || flow.isCommitting || !hasNetwork)

            Button { choosesFiles = true } label: {
                Label(localization.text("ios.guide.chooseFiles"), systemImage: "folder")
            }
            .accessibilityIdentifier("guideFilePicker")
            .disabled(isLoadingPages || flow.isRunning || flow.isCommitting || !hasNetwork)

            if !flow.pageNames.isEmpty {
                LabeledContent(
                    localization.text(
                        "ios.guide.pages", params: ["count": .number(Double(flow.pageNames.count))])
                ) {
                    Text(flow.pageNames.joined(separator: ", "))
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
            }
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if !hasNetwork {
                    Text(localization.text("ios.guide.networkLoading"))
                        .foregroundStyle(.orange)
                }
                Text(localization.text("ios.guide.entryNote"))
            }
        }
    }

    /// Whether the Japanese package is loaded. Without it every station name
    /// reads as unmatched, which looks like a bad screenshot and is not.
    private var hasNetwork: Bool {
        (network?.stations.contains { $0.region == .jp }) ?? false
    }

    /// Keep the screenshot entry point on the same database-station plus corresponding-time
    /// rule as the editor and the completion sheet. The sheet repeats this check immediately
    /// before a request; this one only explains whether opening it can be useful yet.
    private func completionEligible(_ train: Train) -> Bool {
        let catalogs = completionCatalog.map { ["jp": $0] } ?? [:]
        return JourneyCompletion.requestEligibility(train: train, catalogs: catalogs).isEligible
    }

    @ViewBuilder
    private func readingSection(done: Int, total: Int) -> some View {
        Section {
            if total > 1 {
                ProgressView(
                    value: Double(done), total: Double(total),
                    label: {
                        Text(
                            localization.text(
                                "ios.guide.reading", params: [
                                    "done": .number(Double(done)),
                                    "total": .number(Double(total)),
                                ]))
                    })
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(localization.text("ios.guide.readingPlain"))
                }
            }
        }
    }

    @ViewBuilder
    private func failureSection(key: String, detail: String) -> some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localization.text("ios.guide.readFailed")).font(.headline)
                    Text(localization.text(key, params: ["detail": .string(detail)]))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
            }
        }
    }

    /// What was committed, on the screen that committed it.
    ///
    /// The sheet stays open rather than vanishing on the tap: three records
    /// arriving silently is indistinguishable from none arriving, and the JSON
    /// importer next door reports its outcome for the same reason (§8.7).
    @ViewBuilder
    private func importedSection(_ count: Int, saveError: String?) -> some View {
        Section {
            if let saveError {
                Text(localization.text("ios.guide.imported", params: ["count": .number(Double(count))]))
                    .font(.headline)
                DataErrorCard(
                    title: localization.text("data.saveFailedTitle"),
                    detail: saveError,
                    kept: localization.text("data.saveFailedKept"))
                    .accessibilityIdentifier("guideImportSaveFailure")
            } else {
                Label {
                    Text(
                        localization.text(
                            "ios.guide.imported", params: ["count": .number(Double(count))])
                    )
                    .font(.headline)
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }
        }
    }

    // MARK: - the route

    @ViewBuilder
    private func summarySection(_ draft: TransferGuideImport.Draft) -> some View {
        Section {
            if let from = draft.route.header.departure, let to = draft.route.header.arrival {
                LabeledContent(localization.text("ios.guide.windowLabel")) {
                    Text(
                        localization.text(
                            "ios.guide.window", params: ["from": .string(from), "to": .string(to)]))
                    .monospacedDigit()
                }
            }
            if let minutes = draft.route.header.durationMinutes {
                Text(
                    localization.text(
                        "ios.guide.duration", params: ["text": .string(duration(minutes))]))
                .font(.footnote).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                if let yen = draft.route.header.fareYen {
                    Text(
                        localization.text(
                            "ios.guide.fare", params: ["yen": .string(grouped(yen))]))
                }
                if let count = draft.route.header.transferCount {
                    Text(
                        localization.text(
                            "ios.guide.transfers", params: ["count": .number(Double(count))]))
                }
                if let km = draft.route.header.distanceKm {
                    Text(localization.text("ios.guide.distance", params: ["km": .number(km)]))
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            Label {
                Text(
                    draft.source == .unknown
                        ? localization.text("ios.guide.sourceUnknown")
                        : localization.text(
                            "ios.guide.source", params: ["app": .string(draft.source.label)])
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "app.badge.checkmark")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            DatePicker(
                localization.text("ios.guide.date"),
                selection: Binding(
                    get: { draft.date },
                    set: { flow.setDate($0, existingIDs: existingIDs) }),
                displayedComponents: .date)
        } header: {
            Text(localization.text("ios.guide.summary"))
        } footer: {
            Text(
                localization.text(
                    draft.dateWasRead ? "ios.guide.dateRead" : "ios.guide.dateGuessed"))
        }
    }

    // MARK: - ridden, or going to be

    @ViewBuilder
    private func statusSection(_ draft: TransferGuideImport.Draft) -> some View {
        Section {
            Picker(
                localization.text("ios.guide.status"),
                selection: Binding(
                    get: { draft.ridden },
                    set: { flow.setRidden($0, existingIDs: existingIDs) })
            ) {
                Text(localization.text("ios.guide.ridden")).tag(true)
                Text(localization.text("ios.guide.planned")).tag(false)
            }
            .pickerStyle(.segmented)
        } header: {
            Text(localization.text("ios.guide.status"))
        } footer: {
            Text(
                localization.text(
                    draft.ridden ? "ios.guide.riddenNote" : "ios.guide.plannedNote"))
        }
    }

    // MARK: - the trains

    @ViewBuilder
    private func legsSection(_ draft: TransferGuideImport.Draft) -> some View {
        Section {
            ForEach(Array(draft.legs.enumerated()), id: \.offset) { position, leg in
                legRow(draft, position: position, leg: leg)
            }
        } header: {
            Text(localization.text("ios.guide.legs"))
        }
    }

    @ViewBuilder
    private func legRow(
        _ draft: TransferGuideImport.Draft, position: Int, leg: TransferGuide.Leg
    ) -> some View {
        let included = draft.included.indices.contains(position) ? draft.included[position] : true
        VStack(alignment: .leading, spacing: 6) {
            Toggle(
                isOn: Binding(
                    get: { included },
                    set: { flow.setIncluded($0, at: position, existingIDs: existingIDs) })
            ) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(record(draft, position: position)?.number ?? leg.service).font(.headline)
                    Text(legSummary(leg))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    if let detail = legDetail(leg, train: record(draft, position: position)) {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                    if let lines = legLines(draft, position: position) {
                        Text(lines).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            DisclosureGroup(
                isExpanded: Binding(
                    get: { expandedLeg == position },
                    set: { expandedLeg = $0 ? position : nil })
            ) {
                ForEach(Array(leg.calls.enumerated()), id: \.offset) { index, call in
                    callRow(draft, position: position, index: index, call: call)
                }
            } label: {
                Text(
                    localization.text(
                        "ios.guide.legSummary", params: [
                            "count": .number(Double(leg.calls.count)),
                            "from": .string(leg.calls.first?.name ?? ""),
                            "depart": .string(leg.calls.first?.departure ?? ""),
                            "to": .string(leg.calls.last?.name ?? ""),
                            "arrive": .string(leg.calls.last?.arrival ?? ""),
                        ]))
                .font(.caption)
            }
        }
        .opacity(included ? 1 : 0.45)
    }

    @ViewBuilder
    private func callRow(
        _ draft: TransferGuideImport.Draft, position: Int, index: Int, call: TransferGuide.Call
    ) -> some View {
        let train = record(draft, position: position)
        let stop = train.flatMap { $0.stops.indices.contains(index) ? $0.stops[index] : nil }
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text([stop?.arrival ?? call.arrival, stop?.departure ?? call.departure]
                .compactMap { $0 }.joined(separator: " / "))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(call.name)
                    .font(.callout)
                if let qualifier = call.qualifier {
                    Text(qualifier).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
            if code(draft, position: position, index: index) == nil {
                Image(systemName: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - what matched

    @ViewBuilder
    private func matchSection(_ draft: TransferGuideImport.Draft) -> some View {
        Section {
            LabeledContent(localization.text("ios.guide.stations")) {
                Text(
                    localization.text(
                        "ios.guide.matched", params: [
                            "resolved": .number(Double(draft.build.resolvedCalls)),
                            "total": .number(Double(draft.build.totalCalls)),
                        ]))
            }
            if !draft.build.unresolved.isEmpty {
                Text(draft.build.unresolved.joined(separator: "、"))
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } footer: {
            if !draft.build.unresolved.isEmpty {
                Text(localization.text("ios.guide.unresolvedNote"))
            }
        }
    }

    @ViewBuilder
    private func noteSection(_ draft: TransferGuideImport.Draft) -> some View {
        let notes = draft.route.notes
        if !notes.isEmpty {
            Section {
                ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                    Label {
                        Text(sentence(note))
                            .font(.footnote)
                    } icon: {
                        Image(systemName: "info.circle").foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(localization.text("ios.guide.notes"))
            }
        }
    }

    @ViewBuilder
    private func rawSection(_ draft: TransferGuideImport.Draft) -> some View {
        Section {
            DisclosureGroup(isExpanded: $showsRaw) {
                Text(draft.reading.rawRows.joined(separator: "\n"))
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                if !draft.route.unclaimed.isEmpty {
                    Text(localization.text("ios.guide.unclaimed"))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(draft.route.unclaimed.joined(separator: " · "))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(localization.text("ios.guide.raw"))
                    Text(
                        localization.text(
                            "ios.guide.rawCount", params: [
                                "lines": .number(Double(draft.reading.rawRows.count)),
                                "pages": .number(Double(draft.reading.pageCount)),
                                "tiles": .number(Double(draft.reading.tileCount)),
                            ]))
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - committing

    @ViewBuilder
    private var actionBar: some View {
        switch flow.phase {
        case .read:
            if let draft = flow.draft {
                VStack(spacing: 6) {
                    Button {
                        Task {
                            let added = await flow.commit(
                                into: itineraries, library: library)
                            // Selected, so the map moves to what just arrived
                            // rather than leaving the reader to find it.
                            if let last = added.last { itineraries.selectedTrainID = last }
                        }
                    } label: {
                        Text(
                            localization.text(
                                "ios.guide.import", params: ["count": .number(Double(draft.build.trains.count))])
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .railMinimumTouchTarget()
                    .accessibilityIdentifier("guideImportCommit")
                    .disabled(draft.build.trains.isEmpty || itineraries.isImporting || flow.isCommitting)
                    if draft.build.trains.isEmpty {
                        Text(localization.text("ios.guide.nothing"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.bar)
            }
        case .imported(_, let saveError):
            if saveError != nil {
                Button {
                    Task { await flow.retrySave(into: itineraries, library: library) }
                } label: {
                    HStack {
                        if flow.isCommitting { ProgressView() }
                        Text(localization.text("data.saveRetry"))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .railMinimumTouchTarget()
                .disabled(flow.isCommitting)
                .accessibilityIdentifier("guideImportRetrySave")
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.bar)
            } else {
                Button { dismiss() } label: {
                    Text(localization.text("ios.guide.done")).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .railMinimumTouchTarget()
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.bar)
            }
        default:
            EmptyView()
        }
    }

    // MARK: - loading the chosen images

    private func load(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        loadTask?.cancel()
        isLoadingPages = true
        loadError = nil
        loadTask = Task {
            do {
                var pages: [Data] = []
                for item in items {
                    try Task.checkCancellation()
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        throw TransferGuideOCR.Failure.undecodable
                    }
                    pages.append(data)
                }
                try Task.checkCancellation()
                isLoadingPages = false
                guard !pages.isEmpty else { return }
                start(pages: pages, names: [])
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                isLoadingPages = false
                loadError = error.localizedDescription
            }
        }
    }

    private func load(files result: Result<[URL], Error>) {
        guard case .success(let urls) = result, !urls.isEmpty else { return }
        loadTask?.cancel()
        isLoadingPages = true
        loadError = nil
        loadTask = Task {
            do {
                var pages: [Data] = []
                var names: [String] = []
                for url in urls {
                    try Task.checkCancellation()
                    pages.append(try await ImportFileReader.read(url))
                    names.append(url.lastPathComponent)
                }
                try Task.checkCancellation()
                isLoadingPages = false
                start(pages: pages, names: names)
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                isLoadingPages = false
                loadError = error.localizedDescription
            }
        }
    }

    private func start(pages: [Data], names: [String]) {
        expandedLeg = nil
        showsRaw = false
        flow.read(
            pages: pages,
            names: names.isEmpty ? (1...pages.count).map { "#\($0)" } : names,
            stations: network?.stations ?? [],
            lines: network?.lines ?? [],
            existingIDs: existingIDs)
    }

    private var existingIDs: Set<String> {
        Set(itineraries.store?.trains.map(\.id) ?? [])
    }

    // MARK: - sentences

    /// The record one leg became — the records are built from the INCLUDED
    /// legs only, so a dropped leg shifts every record after it.
    private func record(_ draft: TransferGuideImport.Draft, position: Int) -> Train? {
        guard let index = draft.recordByLeg[position],
            draft.build.trains.indices.contains(index)
        else { return nil }
        return draft.build.trains[index]
    }

    private func code(
        _ draft: TransferGuideImport.Draft, position: Int, index: Int
    ) -> String? {
        guard let train = record(draft, position: position),
            train.stops.indices.contains(index)
        else { return nil }
        let value = train.stops[index].n02StationCode
        return (value?.isEmpty ?? true) ? nil : value
    }

    private func legSummary(_ leg: TransferGuide.Leg) -> String {
        var parts: [String] = []
        if let bound = leg.destination {
            parts.append(
                localization.text("ios.guide.legBound", params: ["bound": .string(bound)]))
        }
        if leg.startsHere { parts.append(localization.text("ios.guide.legStartsHere")) }
        if let cars = leg.carCount {
            parts.append(
                localization.text("ios.guide.legCars", params: ["count": .number(Double(cars))]))
        }
        if let platform = platformText(leg) { parts.append(platform) }
        return parts.joined(separator: " · ")
    }

    private func platformText(_ leg: TransferGuide.Leg) -> String? {
        switch (leg.departurePlatform, leg.arrivalPlatform) {
        case (let from?, let to?):
            localization.text(
                "ios.guide.legPlatforms", params: ["from": .number(Double(from)), "to": .number(Double(to))])
        case (let from?, nil):
            localization.text(
                "ios.guide.legPlatformFrom", params: ["from": .number(Double(from))])
        case (nil, let to?):
            localization.text("ios.guide.legPlatformTo", params: ["to": .number(Double(to))])
        default: nil
        }
    }

    private func legDetail(_ leg: TransferGuide.Leg, train: Train?) -> String? {
        var parts = leg.notes
        if let equipment = train?.vehicleType ?? leg.equipment { parts.insert(equipment, at: 0) }
        if let company = train?.company, !company.isEmpty { parts.insert(company, at: 0) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The lines the record will actually be solved along — the package's own
    /// spelling, not the screenshot's.
    private func legLines(_ draft: TransferGuideImport.Draft, position: Int) -> String? {
        guard let train = record(draft, position: position),
            let names = train.routePolicy?.preferredLineNames, !names.isEmpty
        else { return nil }
        return localization.text(
            "ios.guide.legLines", params: ["names": .string(names.joined(separator: "・"))])
    }

    private func sentence(_ note: TransferGuide.Note) -> String {
        let key =
            switch note.kind {
            case .noHeader: "ios.guide.noteNoHeader"
            case .noLegs: "ios.guide.noteNoLegs"
            case .timeWentBackwards: "ios.guide.noteBackwards"
            case .stationCountDisagrees: "ios.guide.noteCount"
            case .shortLeg: "ios.guide.noteShort"
            case .legNotRidden: "ios.guide.noteNotRidden"
            case .crossedMidnight: "ios.guide.noteMidnight"
            }
        return localization.text(key, params: ["subject": .string(note.subject)])
    }

    private func duration(_ minutes: Int) -> String {
        minutes >= 60
            ? localization.text(
                "ios.guide.hoursMinutes", params: [
                    "hours": .number(Double(minutes / 60)),
                    "minutes": .number(Double(minutes % 60)),
                ])
            : localization.text(
                "ios.guide.minutesOnly", params: ["minutes": .number(Double(minutes))])
    }

    private func grouped(_ yen: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: yen)) ?? "\(yen)"
    }
}
