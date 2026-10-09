import RailCore
import RailPresentation
import SwiftUI

struct ShareComposerView: View {
    @Environment(AppLocalization.self) private var localization
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale

    @Bindable var itineraries: ItineraryStore
    @Bindable var riddenRoutes: RiddenRouteStore
    let journeyPresentation: (Train) -> JourneyPresentation

    @State private var model: ShareComposerModel
    @State private var renderer = ShareCardRenderController()
    @State private var derived = WorkspaceDerived()
    @State private var dateScopePresented = false
    @State private var shareFile: StatisticsShareFile?
    @State private var exporting = false
    @State private var exportTask: Task<Void, Never>?
    @State private var exportTicket = 0
    @State private var magnificationStart: Double?
    @State private var previewCanvasSize = CGSize.zero
    @State private var previousMapZoom: [UUID: Double] = [:]

    init(
        itineraries: ItineraryStore,
        riddenRoutes: RiddenRouteStore,
        statistics: MileageStatisticsStore,
        region: Region?, area: StatisticsArea?, colorScheme: ColorScheme,
        journeyPresentation: @escaping (Train) -> JourneyPresentation
    ) {
        self.itineraries = itineraries
        self.riddenRoutes = riddenRoutes
        self.journeyPresentation = journeyPresentation
        _model = State(initialValue: ShareComposerModel(
            region: region, area: area, colorScheme: colorScheme, adopting: statistics))
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    canvas
                    if !model.layout.overflow.isEmpty { overflowTray }
                    if model.effectiveScope.isEmpty {
                        Label(localization.statsText("ios.stats.shareNoOverlap"),
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("shareComposerScopeWarning")
                    }
                    controls
                    if let selected = selectedCard { inspector(selected) }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(localization.statsText("ios.stats.shareComposer"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localization.text("ios.cancel", fallback: "Cancel")) { dismiss() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    dateButton
                    regionMenu
                    appearanceButton
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(localization.statsText("ios.stats.shareExport")) { export() }
                        .disabled(renderer.isRendering || exporting || model.effectiveScope.isEmpty
                                  || renderer.completedKey != renderKey)
                        .accessibilityIdentifier("shareComposerExport")
                }
            }
        }
        .environment(\.colorScheme, model.colorScheme)
        .accessibilityIdentifier("shareComposer")
#if DEBUG
        .overlay(alignment: .topLeading) { debugProbe }
#endif
        .task(id: loadKey) { loadStatistics() }
        .task(id: renderKey) {
            let key = renderKey
            guard statisticsReadyForRender else { return }
            if shouldDebounceSelectedMapZoom() {
                do { try await Task.sleep(for: .milliseconds(140)) }
                catch is CancellationError { return }
                catch { return }
            }
            await renderer.render(
                model: model, itineraries: itineraries, rides: riddenRoutes.rides,
                localization: localization, journeyPresentation: journeyPresentation,
                key: key, canvasSize: previewPixelSize)
#if DEBUG
            if let url = model.debugExportURL {
                await renderer.writeDebugExport(
                    model: model, itineraries: itineraries, rides: riddenRoutes.rides,
                    localization: localization, journeyPresentation: journeyPresentation,
                    to: url, key: key)
            }
#endif
        }
        .sheet(item: $shareFile) { file in
            StatisticsShareView(file: file) { shareFile = nil }
        }
        .onChange(of: renderKey) { _, _ in cancelExport() }
        .onDisappear { cancelExport(); renderer.cancel(); model.statistics.cancelAll() }
    }

    private var canvas: some View {
        let pixels = model.size.pixelSize(for: model.ratio)
        return GeometryReader { proxy in
            let size = proxy.size
            let frames = ShareCanvasGeometry.frames(model: model, canvasSize: size)
            ZStack {
                Color.railElevated(.systemBackground)
                ForEach(model.cards) { card in
                    if let frame = frames[card.id] {
                        cardPreview(card, frame: frame)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
            }
            .onAppear { previewCanvasSize = size }
            .onChange(of: size) { _, newValue in previewCanvasSize = newValue }
        }
        .aspectRatio(pixels.width / pixels.height, contentMode: .fit)
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(localization.statsText("ios.stats.shareCanvas"))
    }

    @ViewBuilder
    private func cardPreview(_ card: ShareCard, frame: CGRect) -> some View {
        Group {
            if let image = renderer.images[card.id] {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ZStack {
                    Color.secondary.opacity(0.08)
                    ProgressView()
                }
            }
        }
        .frame(width: frame.width, height: frame.height)
        .background(Color.railElevated(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: ticketCornerRadius(card, frame: frame),
                                    style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: max(5, min(frame.width, frame.height) * 0.07),
                             style: .continuous)
                .stroke(model.selectedCardID == card.id ? Color.accentColor : .clear,
                        lineWidth: 3)
        }
        .position(x: frame.midX, y: frame.midY)
        .contentShape(Rectangle())
        .onTapGesture { model.selectedCardID = card.id }
        .draggable(card.id.uuidString)
        .dropDestination(for: String.self) { values, _ in
            guard let text = values.first, let source = UUID(uuidString: text),
                  let target = model.cards.firstIndex(where: { $0.id == card.id }) else { return false }
            model.move(source, to: target)
            return true
        }
        .simultaneousGesture(magnification(for: card))
        .accessibilityLabel(cardAccessibilityLabel(card))
        .accessibilityAddTraits(model.selectedCardID == card.id ? .isSelected : [])
    }

    private func magnification(for card: ShareCard) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                guard model.selectedCardID == card.id, case .map = card.kind else { return }
                if magnificationStart == nil { magnificationStart = card.mapZoom }
                model.setZoom((magnificationStart ?? card.mapZoom) * value, for: card.id)
            }
            .onEnded { _ in magnificationStart = nil }
    }

    private var overflowTray: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(model.cards.filter { model.layout.overflow.contains($0.id) }) { card in
                    Button { model.selectedCardID = card.id } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(cardTitle(card), systemImage: "rectangle.slash")
                            Text(localization.statsText("ios.stats.shareDoesNotFit"))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(Color.railElevated(.secondarySystemBackground),
                                    in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Picker(localization.statsText("ios.stats.shareRatio"), selection: Binding(
                get: { model.ratio }, set: { model.ratio = $0 })) {
                ForEach(ShareCanvasRatio.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("shareComposerRatio")

            HStack {
                sizeMenu
                layoutMenu
                addMenu
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var sizeMenu: some View {
        Menu {
            ForEach(ShareCanvasSize.allCases) { size in
                Button {
                    model.size = size
                } label: {
                    let pixels = size.pixelSize(for: model.ratio)
                    Label("\(sizeLabel(size)) · \(Int(pixels.width))×\(Int(pixels.height))",
                          systemImage: model.size == size ? "checkmark" : "photo")
                }
            }
        } label: { Label(localization.statsText("ios.stats.shareSize"), systemImage: "photo") }
    }

    private var layoutMenu: some View {
        Menu {
            ForEach(ShareLayoutPreset.allCases) { preset in
                Button(layoutName(preset)) { model.apply(preset) }
            }
        } label: { Label(localization.statsText("ios.stats.shareLayouts"), systemImage: "rectangle.3.group") }
    }

    private var addMenu: some View {
        Menu {
            Button { model.add(.ticket) } label: {
                Label(localization.statsText("ios.stats.shareTicket"), systemImage: "ticket")
            }
            .disabled(model.cards.contains { if case .ticket = $0.kind { true } else { false } })
            mapAddMenu
            Menu(localization.statsText("ios.stats.shareStatistics")) {
                ForEach(StatisticsCardKind.allCases.filter { $0 != .recordTicket }) { kind in
                    Button { model.add(.stat(kind)) } label: {
                        Label(localization.statsText(kind.localizationKey), systemImage: kind.systemImage)
                    }
                }
            }
        } label: { Label(localization.statsText("ios.stats.shareAdd"), systemImage: "plus") }
        .accessibilityIdentifier("shareComposerAddCard")
    }

    private var mapAddMenu: some View {
        Menu(localization.statsText("ios.stats.shareMap")) {
            Button { model.add(.map(.region(.jp))) } label: {
                Label(localization.text("ios.area.japanAll", fallback: "Japan (all)"), systemImage: "map")
            }
            japanAreaAddMenu
            Divider()
            ForEach([Region.tw, .hk, .mo, .kr]) { region in
                Button { model.add(.map(.region(region))) } label: {
                    Label(localization.text(region.localizationKey, fallback: region.fallbackName), systemImage: "map")
                }
            }
        }
    }

    private var japanAreaAddMenu: some View {
        Menu(localization.text(Region.jp.localizationKey, fallback: Region.jp.fallbackName)) {
            areaAddButton(.hokkaido)
            Menu(localization.text(StatisticsArea.honshu.localizationKey,
                                   fallback: StatisticsArea.honshu.fallbackName)) {
                areaAddButton(.honshu)
                Divider()
                ForEach(StatisticsArea.honshuAreas) { area in areaAddButton(area) }
            }
            areaAddButton(.shikoku); areaAddButton(.kyushu); areaAddButton(.okinawa)
        }
    }

    private func areaAddButton(_ area: StatisticsArea) -> some View {
        Button { model.add(.map(.japan(area))) } label: {
            Label(localization.text(area.localizationKey, fallback: area.fallbackName), systemImage: "map")
        }
    }

    private func inspector(_ card: ShareCard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(cardTitle(card)).font(.headline)
            Picker(localization.statsText("ios.stats.shareCardSize"), selection: Binding(
                get: { card.span }, set: { model.setSpan($0, for: card.id) })) {
                ForEach(model.allowedSpans(for: card), id: \.self) { span in
                    Text("\(span.columns)×\(span.rows)").tag(span)
                }
            }
            .pickerStyle(.segmented)
            if case .ticket = card.kind {
                Text(localization.statsText("ios.stats.shareTicketFixedRatio"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if case .map = card.kind {
                Picker(localization.statsText("ios.stats.shareMapRatio"), selection: Binding(
                    get: { card.mapRatio ?? .square },
                    set: { model.setMapRatio($0, for: card.id) })) {
                    ForEach(MapCardRatio.allCases) { Text($0.label).tag($0) }
                }
                HStack {
                    Text(localization.statsText("ios.stats.shareZoom"))
                    Slider(value: Binding(get: { card.mapZoom },
                                          set: { model.setZoom($0, for: card.id) }), in: 0.75...2)
                }
            }
            HStack {
                Button { model.moveEarlier(card.id) } label: { Image(systemName: "arrow.left") }
                Button { model.moveLater(card.id) } label: { Image(systemName: "arrow.right") }
                Spacer()
                Button(role: .destructive) { model.remove(card.id) } label: {
                    Label(localization.text("ios.delete", fallback: "Delete"), systemImage: "trash")
                }
            }
        }
        .padding(14)
        .background(Color.railElevated(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var dateButton: some View {
        Button { dateScopePresented = true } label: { Image(systemName: "calendar") }
            .popover(isPresented: $dateScopePresented) {
                StatisticsScopePicker(
                    statistics: model.statistics, availableDates: availableDates,
                    groups: journeyGroups, selectGroup: model.statistics.selectJourneyGroup)
                    .presentationCompactAdaptation(.sheet)
            }
            .accessibilityLabel(localization.statsText("ios.stats.scope"))
    }

    private var regionMenu: some View {
        Menu {
            Button(localization.text("ios.region.all", fallback: "All regions")) {
                model.baseRegion = nil; model.baseArea = nil
            }
            Divider()
            ForEach(Region.enabledOrdered) { region in
                if region == .jp { japanRegionMenu }
                else {
                    Button(localization.text(region.localizationKey, fallback: region.fallbackName)) {
                        model.baseRegion = region; model.baseArea = nil
                    }
                }
            }
        } label: { Image(systemName: "globe.asia.australia") }
        .accessibilityLabel(localization.text("country.label", fallback: "Region"))
    }

    private var appearanceButton: some View {
        Button {
            model.colorScheme = model.colorScheme == .dark ? .light : .dark
        } label: {
            Image(systemName: model.colorScheme == .dark ? "moon" : "sun.max")
        }
        .accessibilityLabel(localization.statsText("ios.stats.shareAppearance"))
        .accessibilityValue(localization.statsText(
            model.colorScheme == .dark ? "ios.stats.shareDark" : "ios.stats.shareLight"))
        .accessibilityIdentifier("shareComposerAppearance")
    }

    private var japanRegionMenu: some View {
        Menu(localization.text(Region.jp.localizationKey, fallback: Region.jp.fallbackName)) {
            Button(localization.text("ios.area.japanAll", fallback: "Japan (all)")) {
                model.baseRegion = .jp; model.baseArea = nil
            }
            Divider()
            regionAreaButton(.hokkaido)
            Menu(localization.text(StatisticsArea.honshu.localizationKey,
                                   fallback: StatisticsArea.honshu.fallbackName)) {
                regionAreaButton(.honshu); Divider()
                ForEach(StatisticsArea.honshuAreas) { area in regionAreaButton(area) }
            }
            regionAreaButton(.shikoku); regionAreaButton(.kyushu); regionAreaButton(.okinawa)
        }
    }

    private func regionAreaButton(_ area: StatisticsArea) -> some View {
        Button(localization.text(area.localizationKey, fallback: area.fallbackName)) {
            model.baseRegion = .jp; model.baseArea = area
        }
    }

    private var selectedCard: ShareCard? { model.cards.first { $0.id == model.selectedCardID } }
    private var scopedTrains: [Train] {
        guard let loaded = itineraries.loaded else { return [] }
        return model.effectiveScope.filter(loaded.trains, rides: riddenRoutes.rides).filter { train in
            RideLedger.hasBeenRidden(train)
                && model.statistics.includesYear(train)
                && model.statistics.includesJourneyGroup(train)
                && model.statistics.includesDate(train)
        }
    }
    private var journeyGroups: [JourneyGroup] {
        var seen = Set<String>()
        return (itineraries.store?.trains ?? itineraries.loaded?.trains ?? [])
            .compactMap(\.journeyGroup).filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    private var availableDates: [String] {
        guard let loaded = itineraries.loaded else { return [] }
        let scope = model.effectiveScope
        let members = derived.memberIDs(
            scope: scope, trains: loaded.trains, rides: riddenRoutes.rides)
        return derived.scopedDates(
            trains: loaded.trains, days: loaded.days, region: nil,
            year: model.statistics.selectedYear,
            scopeKey: "\(scope.key)|\(members.key)",
            filter: { members.ids.contains($0.id) })
    }

    private var selectedRoutesReady: Bool {
        guard let loaded = itineraries.loaded else { return false }
        // Area membership depends on solved geometry. Await the selected
        // country/date candidates before narrowing them to Japanese leaves.
        return riddenRoutes.hasSettledRoutes(in: loaded.trains) { train in
            model.effectiveScope.regions.contains(Region.resolved(train))
                && RideLedger.hasBeenRidden(train)
                && model.statistics.includesYear(train)
                && model.statistics.includesJourneyGroup(train)
                && model.statistics.includesDate(train)
        }
    }

    private var loadKey: String {
        let memberIDs = Set(scopedTrains.map(\.id))
        let ridesKey = riddenRoutes.rides.filter { memberIDs.contains($0.id) }
            .map { "\($0.id):\($0.geometryDigest)" }.joined(separator: ",")
        return "\(model.effectiveScope.key)|\(model.statistics.selectedYear.map(String.init) ?? "*")|\(model.statistics.selectedJourneyGroupID ?? "*")|\(model.statistics.dateSelection)|\(itineraries.storeGeneration)|routesReady:\(selectedRoutesReady)|\(ridesKey)"
    }
    private var renderKey: String {
        let cards = model.cards.map { "\($0.id):\($0.span.columns)x\($0.span.rows):\($0.mapZoom):\($0.kind)" }.joined()
        let preview = previewPixelSize
        return "\(loadKey)|\(model.statistics.publishGeneration)|\(model.statistics.publishedInputsKey ?? "-")|\(model.ratio.rawValue)|\(model.size.rawValue)|\(model.colorScheme)|\(Int(preview.width))x\(Int(preview.height))|\(cards)"
    }
    private var statisticsReadyForRender: Bool {
        if model.effectiveScope.isEmpty { return itineraries.loaded != nil }
        guard selectedRoutesReady, case .loaded = model.statistics.state else { return false }
        return model.statistics.publishedInputsKey == loadKey
    }
    private var previewPixelSize: CGSize {
        let points: CGSize
        if previewCanvasSize.width > 0, previewCanvasSize.height > 0 {
            points = previewCanvasSize
        } else {
            let width: CGFloat = 390
            points = CGSize(width: width, height: width / model.ratio.aspect)
        }
        let scale = min(displayScale, 1_400 / max(points.width, points.height))
        return CGSize(width: max(1, (points.width * scale).rounded()),
                      height: max(1, (points.height * scale).rounded()))
    }
    private func shouldDebounceSelectedMapZoom() -> Bool {
        guard let selectedCard, case .map = selectedCard.kind else { return false }
        let previous = previousMapZoom[selectedCard.id]
        previousMapZoom[selectedCard.id] = selectedCard.mapZoom
        return previous.map { $0 != selectedCard.mapZoom } ?? false
    }

    private func loadStatistics() {
        guard itineraries.loaded != nil else { return }
        let scope = model.effectiveScope
        let trains = scopedTrains
        let ids = Set(trains.map(\.id))
        model.statistics.load(countries: scope.countries, japanLeaves: scope.japanLeavesForIndex,
                              trains: trains, rides: riddenRoutes.rides.filter { ids.contains($0.id) },
                              inputsKey: loadKey)
    }

#if DEBUG
    private var debugProbe: some View {
        Text(" ")
            .foregroundStyle(.clear)
            .frame(width: 1, height: 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Share composer debug")
            .accessibilityValue(debugValue)
            .accessibilityIdentifier("shareComposerDebug")
            .accessibilityHidden(false)
    }

    private var debugValue: String {
        let pixels = model.size.pixelSize(for: model.ratio)
        let scopeName = model.scopeDisplayName(localization)
            .replacingOccurrences(of: ";", with: ",")
        let currentStatistics = model.statistics.publishedInputsKey == loadKey
            ? model.statistics.view : nil
        let km = currentStatistics.map {
            String(format: "%.1f", ($0.overall.riddenAll * 10).rounded() / 10)
        } ?? "-1"
        return [
            "ready=\(debugReady ? 1 : 0)",
            "scope=\(model.effectiveScope.key)",
            "scopeName=\(scopeName)",
            "cards=\(model.cards.count)",
            "overflow=\(model.layout.overflow.count)",
            "journeys=\(scopedTrains.count)",
            "km=\(km)",
            "ratio=\(model.ratio.rawValue)",
            "scheme=\(model.colorScheme == .dark ? "dark" : "light")",
            "px=\(Int(pixels.width))x\(Int(pixels.height))",
        ].joined(separator: ";")
    }

    private var debugReady: Bool {
        let statisticsLoaded = statisticsReadyForRender
        let placedCardsRendered = model.layout.placements.keys.allSatisfy {
            renderer.images[$0] != nil
        }
        let exportWritten = model.debugExportURL == nil
            || renderer.debugExportedKey == renderKey
        return statisticsLoaded && renderer.completedKey == renderKey
            && placedCardsRendered && exportWritten
    }
#endif

    private func export() {
        guard renderer.completedKey == renderKey else { return }
        exportTask?.cancel()
        exportTicket += 1
        let ticket = exportTicket
        let key = renderKey
        exporting = true
        exportTask = Task {
            let file = await renderer.export(
                model: model, itineraries: itineraries, rides: riddenRoutes.rides,
                localization: localization, journeyPresentation: journeyPresentation, key: key)
            guard !Task.isCancelled, exportTicket == ticket, renderKey == key else { return }
            shareFile = file
            exporting = false
            exportTask = nil
        }
    }

    private func cancelExport() {
        exportTicket += 1
        exportTask?.cancel()
        exportTask = nil
        exporting = false
    }

    private func cardTitle(_ card: ShareCard) -> String {
        switch card.kind {
        case .ticket: localization.statsText("ios.stats.shareTicket")
        case .map(let area): area.localizedName(localization)
        case .stat(let kind): localization.statsText(kind.localizationKey)
        }
    }
    private func cardAccessibilityLabel(_ card: ShareCard) -> String {
        let name: String
        if case .map(let area) = card.kind {
            name = localization.statsText("ios.stats.shareMap") + ", "
                + area.localizedName(localization)
        } else {
            name = cardTitle(card)
        }
        return localization.statsText("ios.stats.shareCardLabel", params: [
            "name": .string(name),
            "columns": .number(Double(card.span.columns)),
            "rows": .number(Double(card.span.rows)),
        ])
    }
    private func sizeLabel(_ size: ShareCanvasSize) -> String {
        switch size {
        case .small: localization.statsText("ios.stats.shareSizeSmall")
        case .medium: localization.statsText("ios.stats.shareSizeMedium")
        case .large: localization.statsText("ios.stats.shareSizeLarge")
        }
    }
    private func ticketCornerRadius(_ card: ShareCard, frame: CGRect) -> CGFloat {
        if case .ticket = card.kind { return 0 }
        return max(5, min(frame.width, frame.height) * 0.07)
    }
    private func layoutName(_ preset: ShareLayoutPreset) -> String {
        switch preset {
        case .japanIslands: localization.statsText("ios.stats.shareLayoutJapan")
        case .taiwan: localization.text(Region.tw.localizationKey, fallback: Region.tw.fallbackName)
        case .hongKong: localization.text(Region.hk.localizationKey, fallback: Region.hk.fallbackName)
        case .macau: localization.text(Region.mo.localizationKey, fallback: Region.mo.fallbackName)
        }
    }
}
