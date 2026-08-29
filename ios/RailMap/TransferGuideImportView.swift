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
//  Nothing on this screen is editable except the three answers the screenshot
//  cannot give: which day, whether it happened, and which of its trains to
//  keep. Everything else is repaired in the ride editor afterwards, which is
//  a screen that already validates every rule; a second half-editor here
//  would be a second set of rules to keep in step.
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

    var body: some View {
        NavigationStack {
            Form {
                sourceSection
                switch flow.phase {
                case .waiting: EmptyView()
                case .reading(let done, let total): readingSection(done: done, total: total)
                case .failed(let key, let detail): failureSection(key: key, detail: detail)
                case .imported(let count): importedSection(count)
                case .read:
                    if let draft = flow.draft {
                        summarySection(draft)
                        statusSection(draft)
                        legsSection(draft)
                        matchSection(draft)
                        noteSection(draft)
                        rawSection(draft)
                    }
                }
            }
            .navigationTitle(localization.guideText("ios.guide.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localization.text("ios.cancel", fallback: "Cancel")) {
                        flow.cancel()
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { actionBar }
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
        let choosePhotos = localization.guideText("ios.guide.choosePhotos")
        Section {
            PhotosPicker(
                selection: $picked, maxSelectionCount: 8, matching: .images,
                photoLibrary: .shared()
            ) {
                Label(choosePhotos, systemImage: "photo")
            }
            .accessibilityIdentifier("guidePhotoPicker")
            .disabled(flow.isRunning || !hasNetwork)

            Button { choosesFiles = true } label: {
                Label(localization.guideText("ios.guide.chooseFiles"), systemImage: "folder")
            }
            .accessibilityIdentifier("guideFilePicker")
            .disabled(flow.isRunning || !hasNetwork)

            if !flow.pageNames.isEmpty {
                LabeledContent(
                    localization.guideText(
                        "ios.guide.pages", ["count": .number(Double(flow.pageNames.count))])
                ) {
                    Text(flow.pageNames.joined(separator: ", "))
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
            }
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if !hasNetwork {
                    Text(localization.guideText("ios.guide.networkLoading"))
                        .foregroundStyle(.orange)
                }
                Text(localization.guideText("ios.guide.entryNote"))
            }
        }
    }

    /// Whether the Japanese package is loaded. Without it every station name
    /// reads as unmatched, which looks like a bad screenshot and is not.
    private var hasNetwork: Bool {
        (network?.stations.contains { $0.region == .jp }) ?? false
    }

    @ViewBuilder
    private func readingSection(done: Int, total: Int) -> some View {
        Section {
            if total > 1 {
                ProgressView(
                    value: Double(done), total: Double(total),
                    label: {
                        Text(
                            localization.guideText(
                                "ios.guide.reading",
                                [
                                    "done": .number(Double(done)),
                                    "total": .number(Double(total)),
                                ]))
                    })
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(localization.guideText("ios.guide.readingPlain"))
                }
            }
        }
    }

    @ViewBuilder
    private func failureSection(key: String, detail: String) -> some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localization.guideText("ios.guide.readFailed")).font(.headline)
                    Text(localization.guideText(key, ["detail": .string(detail)]))
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
    private func importedSection(_ count: Int) -> some View {
        Section {
            Label {
                Text(
                    localization.guideText(
                        "ios.guide.imported", ["count": .number(Double(count))])
                )
                .font(.headline)
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        }
    }

    // MARK: - the route

    @ViewBuilder
    private func summarySection(_ draft: TransferGuideImport.Draft) -> some View {
        Section {
            if let from = draft.route.header.departure, let to = draft.route.header.arrival {
                LabeledContent(localization.guideText("ios.guide.windowLabel")) {
                    Text(
                        localization.guideText(
                            "ios.guide.window", ["from": .string(from), "to": .string(to)]))
                    .monospacedDigit()
                }
            }
            if let minutes = draft.route.header.durationMinutes {
                Text(
                    localization.guideText(
                        "ios.guide.duration", ["text": .string(duration(minutes))]))
                .font(.footnote).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                if let yen = draft.route.header.fareYen {
                    Text(
                        localization.guideText(
                            "ios.guide.fare", ["yen": .string(grouped(yen))]))
                }
                if let count = draft.route.header.transferCount {
                    Text(
                        localization.guideText(
                            "ios.guide.transfers", ["count": .number(Double(count))]))
                }
                if let km = draft.route.header.distanceKm {
                    Text(localization.guideText("ios.guide.distance", ["km": .number(km)]))
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            Label {
                Text(
                    draft.source == .unknown
                        ? localization.guideText("ios.guide.sourceUnknown")
                        : localization.guideText(
                            "ios.guide.source", ["app": .string(draft.source.label)])
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "app.badge.checkmark")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            DatePicker(
                localization.guideText("ios.guide.date"),
                selection: Binding(
                    get: { draft.date },
                    set: { flow.setDate($0, existingIDs: existingIDs) }),
                displayedComponents: .date)
        } header: {
            Text(localization.guideText("ios.guide.summary"))
        } footer: {
            Text(
                localization.guideText(
                    draft.dateWasRead ? "ios.guide.dateRead" : "ios.guide.dateGuessed"))
        }
    }

    // MARK: - ridden, or going to be

    @ViewBuilder
    private func statusSection(_ draft: TransferGuideImport.Draft) -> some View {
        Section {
            Picker(
                localization.guideText("ios.guide.status"),
                selection: Binding(
                    get: { draft.ridden },
                    set: { flow.setRidden($0, existingIDs: existingIDs) })
            ) {
                Text(localization.guideText("ios.guide.ridden")).tag(true)
                Text(localization.guideText("ios.guide.planned")).tag(false)
            }
            .pickerStyle(.segmented)
        } header: {
            Text(localization.guideText("ios.guide.status"))
        } footer: {
            Text(
                localization.guideText(
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
            Text(localization.guideText("ios.guide.legs"))
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
                    Text(leg.service).font(.headline)
                    Text(legSummary(leg))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    if let detail = legDetail(leg) {
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
                    localization.guideText(
                        "ios.guide.legSummary",
                        [
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
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text([call.arrival, call.departure].compactMap { $0 }.joined(separator: " / "))
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
            LabeledContent(localization.guideText("ios.guide.stations")) {
                Text(
                    localization.guideText(
                        "ios.guide.matched",
                        [
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
                Text(localization.guideText("ios.guide.unresolvedNote"))
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
                Text(localization.guideText("ios.guide.notes"))
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
                    Text(localization.guideText("ios.guide.unclaimed"))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(draft.route.unclaimed.joined(separator: " · "))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(localization.guideText("ios.guide.raw"))
                    Text(
                        localization.guideText(
                            "ios.guide.rawCount",
                            [
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
                            localization.guideText(
                                "ios.guide.import",
                                ["count": .number(Double(draft.build.trains.count))])
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .railMinimumTouchTarget()
                    .accessibilityIdentifier("guideImportCommit")
                    .disabled(draft.build.trains.isEmpty || itineraries.isImporting)
                    if draft.build.trains.isEmpty {
                        Text(localization.guideText("ios.guide.nothing"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.bar)
            }
        case .imported:
            Button { dismiss() } label: {
                Text(localization.guideText("ios.guide.done")).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .railMinimumTouchTarget()
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)
        default:
            EmptyView()
        }
    }

    // MARK: - loading the chosen images

    private func load(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            var pages: [Data] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    pages.append(data)
                }
            }
            guard !pages.isEmpty else { return }
            start(pages: pages, names: [])
        }
    }

    private func load(files result: Result<[URL], Error>) {
        guard case .success(let urls) = result, !urls.isEmpty else { return }
        var pages: [Data] = []
        var names: [String] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                pages.append(data)
                names.append(url.lastPathComponent)
            }
        }
        guard !pages.isEmpty else { return }
        start(pages: pages, names: names)
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
                localization.guideText("ios.guide.legBound", ["bound": .string(bound)]))
        }
        if leg.startsHere { parts.append(localization.guideText("ios.guide.legStartsHere")) }
        if let cars = leg.carCount {
            parts.append(
                localization.guideText("ios.guide.legCars", ["count": .number(Double(cars))]))
        }
        if let platform = platformText(leg) { parts.append(platform) }
        return parts.joined(separator: " · ")
    }

    private func platformText(_ leg: TransferGuide.Leg) -> String? {
        switch (leg.departurePlatform, leg.arrivalPlatform) {
        case (let from?, let to?):
            localization.guideText(
                "ios.guide.legPlatforms",
                ["from": .number(Double(from)), "to": .number(Double(to))])
        case (let from?, nil):
            localization.guideText(
                "ios.guide.legPlatformFrom", ["from": .number(Double(from))])
        case (nil, let to?):
            localization.guideText("ios.guide.legPlatformTo", ["to": .number(Double(to))])
        default: nil
        }
    }

    private func legDetail(_ leg: TransferGuide.Leg) -> String? {
        var parts = leg.notes
        if let equipment = leg.equipment { parts.insert(equipment, at: 0) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The lines the record will actually be solved along — the package's own
    /// spelling, not the screenshot's.
    private func legLines(_ draft: TransferGuideImport.Draft, position: Int) -> String? {
        guard let train = record(draft, position: position),
            let names = train.routePolicy?.preferredLineNames, !names.isEmpty
        else { return nil }
        return localization.guideText(
            "ios.guide.legLines", ["names": .string(names.joined(separator: "・"))])
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
        return localization.guideText(key, ["subject": .string(note.subject)])
    }

    private func duration(_ minutes: Int) -> String {
        minutes >= 60
            ? localization.guideText(
                "ios.guide.hoursMinutes",
                [
                    "hours": .number(Double(minutes / 60)),
                    "minutes": .number(Double(minutes % 60)),
                ])
            : localization.guideText(
                "ios.guide.minutesOnly", ["minutes": .number(Double(minutes))])
    }

    private func grouped(_ yen: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: yen)) ?? "\(yen)"
    }
}
