import RailCore
import RailPresentation
import SwiftUI

struct ShareComposerView: View {
    @Environment(AppLocalization.self) private var localization
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @Bindable var itineraries: ItineraryStore
    @Bindable var riddenRoutes: RiddenRouteStore

    @State private var model: ShareComposerModel
    @State private var renderer = ShareCardRenderController()
    @State private var derived = WorkspaceDerived()
    @State private var dateScopePresented = false
    @State private var cardDateScopeID: UUID?
    @State private var shareFile: StatisticsShareFile?
    @State private var exporting = false
    @State private var exportFailed = false
    @State private var renderRetry = 0
    @State private var exportTask: Task<Void, Never>?
    @State private var exportTicket = 0
    @State private var previewCanvasSize = CGSize.zero
    @State private var previousMapZoom: [UUID: Double] = [:]
    @State private var isEditingCanvas = false
    @State private var interaction: ShareComposerInteraction?
    @State private var composerFrames: [String: CGRect] = [:]
    @State private var trayCardFrames: [UUID: CGRect] = [:]
    @State private var settleGeneration = 0
    @State private var pendingTrayDrop: UUID?
#if DEBUG
    @State private var debugDragGeometry = "none"
    @State private var debugDragEnd = "none"
#endif

    init(
        itineraries: ItineraryStore,
        riddenRoutes: RiddenRouteStore,
        statistics: MileageStatisticsStore,
        region: Region?, area: StatisticsArea?, colorScheme: ColorScheme
    ) {
        self.itineraries = itineraries
        self.riddenRoutes = riddenRoutes
        _model = State(initialValue: ShareComposerModel(
            region: region, area: area, colorScheme: colorScheme, adopting: statistics))
    }

    var body: some View {
        @Bindable var model = model
        let work = scopeWork
        let loadKey = loadKey(work)
        let renderKey = renderKey(work, loadKey: loadKey)
        let statisticsReady = statisticsReadyForRender(work)
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    canvas(renderKey: renderKey, statisticsReady: statisticsReady)
                    if let failure = statisticsFailure(work) {
                        VStack(spacing: 8) {
                            Text(failure.message)
                                .font(.footnote)
                            if failure.retryable {
                                Button(localization.text("ios.journeyShare.retry")) { loadStatistics() }
                            }
                        }
                        .disabled(interaction != nil)
                    }
                    if renderer.renderFailed, model.hasScopedContent {
                        VStack(spacing: 8) {
                            Text(localization.text("ios.stats.shareExportFailedBody"))
                                .font(.footnote)
                            Button(localization.text("ios.journeyShare.retry")) { renderRetry += 1 }
                        }
                        .accessibilityIdentifier("shareComposerRenderFailure")
                        .disabled(interaction != nil)
                    }
                    if !trayCards.isEmpty || isDraggingCanvasCard { overflowTray }
                    if !model.hasScopedContent {
                        Label(localization.text("ios.stats.shareNoOverlap"),
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("shareComposerScopeWarning")
                    }
                    controls
                        .disabled(interaction != nil)
                    if let selected = selectedCard {
                        inspector(selected)
                            .disabled(interaction != nil)
                    }
                }
                .padding(16)
            }
            .accessibilityIdentifier("shareComposerScroll")
            .scrollDisabled(interaction != nil)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(localization.text("ios.stats.shareComposer"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localization.text("ios.cancel", fallback: "Cancel")) { dismiss() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    editButton
                    dateButton
                        .disabled(interaction != nil)
                    regionMenu
                        .disabled(interaction != nil)
                    appearanceButton
                        .disabled(interaction != nil)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(localization.text("ios.stats.shareExport")) { export() }
                        .disabled(interaction != nil || model.layout.placements.isEmpty
                                  || renderer.isRendering || exporting || !model.hasScopedContent || !statisticsReady
                                  || renderer.completedKey != renderKey)
                        .accessibilityIdentifier("shareComposerExport")
                }
            }
        }
        .onPreferenceChange(ShareComposerFramePreferenceKey.self) { composerFrames = $0 }
        .onPreferenceChange(ShareComposerCardFramePreferenceKey.self) { frames in
            trayCardFrames = frames
            if let id = pendingTrayDrop, let frame = frames[id] {
                pendingTrayDrop = nil
                settleInteraction(to: frame)
            }
        }
        .overlay(alignment: .topLeading) {
            GeometryReader { proxy in
                liftedCardOverlay(origin: proxy.frame(in: .global).origin)
            }
            .allowsHitTesting(false)
        }
        .environment(\.colorScheme, model.colorScheme)
        .accessibilityIdentifier("shareComposer")
        .interactiveDismissDisabled(interaction != nil)
#if DEBUG
        .overlay(alignment: .topLeading) { debugProbe }
#endif
        .task(id: loadKey) { loadStatistics() }
        .task(id: renderKey) {
            let key = renderKey
            guard previewCanvasSize.width > 0, previewCanvasSize.height > 0 else { return }
            guard statisticsReady else { return }
            let prepared = preparedCards(work)
            if shouldDebounceSelectedMapZoom() {
                do { try await Task.sleep(for: .milliseconds(140)) }
                catch is CancellationError { return }
                catch { return }
            }
            guard previewCanvasSize.width > 0, previewCanvasSize.height > 0 else { return }
            await renderer.render(
                model: model, itineraries: itineraries, rides: riddenRoutes.rides,
                prepared: prepared, localization: localization,
                key: key, canvasSize: previewPixelSize)
#if DEBUG
            if let url = model.debugExportURL {
                await renderer.writeDebugExport(
                    model: model, itineraries: itineraries, rides: riddenRoutes.rides,
                    prepared: prepared, localization: localization,
                    to: url, key: key)
            }
#endif
        }
        .sheet(item: $shareFile) { file in
            StatisticsShareView(file: file) { shareFile = nil }
        }
        .alert(localization.text("ios.stats.shareExportFailed"), isPresented: $exportFailed) {
            Button(localization.text("ios.ok", fallback: "OK"), role: .cancel) { }
        } message: {
            Text(localization.text("ios.stats.shareExportFailedBody"))
        }
        .onChange(of: renderKey) { _, _ in cancelExport() }
        .onChange(of: statisticsReady) { _, ready in
            if !ready { renderer.discardPreview() }
        }
        .onChange(of: model.ratio) { _, _ in resetInteraction() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { resetInteraction() }
        }
        .onChange(of: isEditingCanvas) { _, editing in
            if !editing { cancelInteraction() }
        }
        .onDisappear {
            resetInteraction(); cancelExport(); renderer.cancel(); model.cancelStatistics()
        }
    }

    private func canvas(renderKey: String, statisticsReady: Bool) -> some View {
        ShareComposerCanvas(
            model: model,
            isEditing: $isEditingCanvas,
            interaction: $interaction,
            images: renderer.images,
            statisticsReady: statisticsReady,
            accessibilityLabels: Dictionary(uniqueKeysWithValues: model.cards.map {
                ($0.id, cardAccessibilityLabel($0))
            }),
            onSizeChange: { previewCanvasSize = $0 },
            onCardGesture: handleCanvasGesture
        )
    }

    private var overflowTray: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                if isDraggingCanvasCard,
                   !model.cards.contains(where: { $0.id == interaction?.id && $0.parked }) {
                    Label(localization.text("ios.stats.shareMotion.dropToTray"),
                          systemImage: "tray.and.arrow.down")
                        .font(.callout.weight(.semibold))
                        .padding(14)
                }
                ForEach(trayCards) { card in
                    trayCard(card)
                }
            }
            .padding(isEditingCanvas ? 18 : 0)
        }
        .scrollDisabled(interaction != nil)
        .frame(minHeight: 58)
        .background(
            (isDraggingOverTray ? Color.accentColor.opacity(0.18)
                : Color.railElevated(.secondarySystemBackground)),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isDraggingOverTray ? Color.accentColor : .clear, lineWidth: 2)
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ShareComposerFramePreferenceKey.self,
                    value: ["tray": proxy.frame(in: .global)])
            }
        }
    }

    private var trayCards: [ShareCard] {
        model.cards.filter { $0.parked || model.layout.overflow.contains($0.id) }
    }

    private var isDraggingCanvasCard: Bool {
        interaction?.source == .canvas && interaction?.isLifted == true
    }

    private var isDraggingOverTray: Bool {
        guard isDraggingCanvasCard, let interaction, interaction.phase == .lifted,
              let trayFrame = composerFrames["tray"] else {
            return false
        }
        return trayFrame.contains(interaction.location)
    }

    private func trayCard(_ card: ShareCard) -> some View {
        let index = model.cards.firstIndex(where: { $0.id == card.id }) ?? 0
        let isLifted = interaction?.id == card.id && interaction?.isLifted == true
        return ZStack(alignment: .topLeading) {
            ShareCardGestureLayer(isEditing: isEditingCanvas) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(cardTitle(card), systemImage: "rectangle.slash")
                    Text(localization.text(card.parked
                        ? "ios.stats.shareMotion.parked" : "ios.stats.shareDoesNotFit"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(Color.railElevated(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityAddTraits(model.selectedCardID == card.id ? .isSelected : [])
                .accessibilityIdentifier("shareComposerTrayCard-\(index)")
                .accessibilityAction { model.selectedCardID = card.id }
                .accessibilityAction(named: Text(localization.text(
                    "ios.stats.shareMotion.restore"))) {
                    guard interaction == nil else { return }
                    withAnimation(motionAnimation) { model.setParked(false, for: card.id) }
                }
                .accessibilityAction(named: Text(localization.text(
                    "ios.stats.shareMotion.remove"))) {
                    guard interaction == nil else { return }
                    withAnimation(motionAnimation) { model.remove(card.id) }
                }
            } onEvent: { event in
                let fallback = CGRect(x: 0, y: 0, width: 160, height: 58)
                handleTrayGesture(card, frame: trayCardFrames[card.id] ?? fallback, event: event)
            }

            if isEditingCanvas {
                Button {
                    withAnimation(motionAnimation) { model.remove(card.id) }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(.red, in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .offset(x: -17, y: -17)
                .disabled(interaction != nil)
                .accessibilityLabel(localization.text("ios.stats.shareMotion.remove"))
                .accessibilityIdentifier("shareComposerRemove-\(index)")
                .zIndex(2)
            }
        }
        .modifier(ShareComposerWobble(
            active: isEditingCanvas && !isLifted && !reduceMotion,
            seed: card.id.hashValue))
        .opacity(isLifted ? 0 : 1)
        .accessibilityHidden(isLifted)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ShareComposerCardFramePreferenceKey.self,
                    value: [card.id: proxy.frame(in: .global)])
            }
        }
        .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
    }

    @ViewBuilder
    private func liftedCardOverlay(origin: CGPoint) -> some View {
        if let interaction, interaction.isLifted,
           let card = model.cards.first(where: { $0.id == interaction.id }) {
            ShareComposerLiftedCard(
                card: card,
                image: interaction.snapshot,
                statisticsReady: interaction.snapshot != nil,
                reduceMotion: reduceMotion,
                size: interaction.size,
                isRaised: interaction.phase == .lifted,
                trayTitle: interaction.source == .tray ? cardTitle(card) : nil,
                trayCaption: interaction.source == .tray ? localization.text(card.parked
                    ? "ios.stats.shareMotion.parked" : "ios.stats.shareDoesNotFit") : nil)
            .position(x: interaction.location.x - interaction.grabOffset.width - origin.x,
                      y: interaction.location.y - interaction.grabOffset.height - origin.y)
            .zIndex(1_000)
            .transition(.identity)
        }
    }

    private func handleCanvasGesture(
        _ card: ShareCard, frame: CGRect, event: ShareCardGestureEvent
    ) {
        let canvasOrigin = composerFrames["canvas"]?.origin ?? .zero
        let globalFrame = frame.offsetBy(dx: canvasOrigin.x, dy: canvasOrigin.y)
        handleGesture(card, source: .canvas, originFrame: globalFrame, event: event)
    }

    private func handleTrayGesture(
        _ card: ShareCard, frame: CGRect, event: ShareCardGestureEvent
    ) {
        handleGesture(card, source: .tray, originFrame: frame, event: event)
    }

    private func handleGesture(
        _ card: ShareCard,
        source: ShareComposerInteraction.Source,
        originFrame: CGRect,
        event: ShareCardGestureEvent
    ) {
        switch event {
        case .tapped:
            guard interaction == nil else { return }
            model.selectedCardID = card.id
        case .began(let value):
            guard interaction == nil else { return }
#if DEBUG
            debugDragEnd = "began"
#endif
            interaction = ShareComposerInteraction(
                id: card.id,
                source: source,
                originalOrder: model.cards.map(\.id),
                tentativeOrder: model.cards.map(\.id),
                location: value.location,
                startLocation: value.startLocation,
                grabOffset: CGSize(width: value.startLocation.x - originFrame.midX,
                                   height: value.startLocation.y - originFrame.midY),
                size: originFrame.size,
                originFrame: originFrame)
        case .changed(let value):
            guard var current = interaction, current.id == card.id,
                  current.phase != .settling else { return }
            current.location = value.location
            interaction = current
            let movement = hypot(value.translation.width, value.translation.height)
            if current.phase == .pressed, isEditingCanvas, movement > 4 {
                liftInteraction(at: value.location)
            } else if current.phase == .lifted {
                updateLiveReflow(at: value.location)
            }
        case .longPressed(let value):
            guard interaction?.id == card.id, interaction?.phase == .pressed else { return }
            withAnimation(motionAnimation) { isEditingCanvas = true }
            liftInteraction(at: value.location)
        case .ended(let value):
#if DEBUG
            debugDragEnd = "ended:\(interaction.map { String(describing: $0.phase) } ?? "none")"
#endif
            guard let current = interaction, current.id == card.id else { return }
            if current.phase == .pressed {
                if hypot(value.translation.width, value.translation.height) <= 8,
                   !isEditingCanvas {
                    model.selectedCardID = card.id
                }
                interaction = nil
            } else if current.phase == .lifted {
                finishInteraction(at: value.location)
            }
        case .cancelled:
#if DEBUG
            debugDragEnd = "cancelled:\(interaction.map { String(describing: $0.phase) } ?? "none")"
#endif
            guard interaction?.id == card.id else { return }
            cancelInteraction()
        }
    }

    private func liftInteraction(at location: CGPoint) {
        guard var current = interaction, current.phase == .pressed else { return }
        current.phase = .lifted
        current.location = location
        current.snapshot = renderer.images[current.id]
        withAnimation(motionAnimation) { interaction = current }
        model.selectedCardID = current.id
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        updateLiveReflow(at: location)
    }

    private func updateLiveReflow(at location: CGPoint) {
        guard var current = interaction, current.phase == .lifted,
              let canvasFrame = composerFrames["canvas"], canvasFrame.width > 0 else { return }
        current.location = location
#if DEBUG
        debugDragGeometry = "outside:\(location):canvas=\(canvasFrame):grab=\(current.grabOffset)"
#endif
        guard canvasFrame.contains(location) else {
            let changed = current.tentativeOrder != current.originalOrder
            current.tentativeOrder = current.originalOrder
            current.previewingCanvas = false
            interaction = current
            if changed { UISelectionFeedbackGenerator().selectionChanged() }
            return
        }

        let cards = planningCards(draggedID: current.id, order: current.tentativeOrder)
        let localPoint = CGPoint(x: location.x - current.grabOffset.width - canvasFrame.minX,
                                 y: location.y - current.grabOffset.height - canvasFrame.minY)
        let order = ShareDragPlanner.bestOrder(
            cards: cards, draggedID: current.id, finger: localPoint,
            grid: model.grid, canvasSize: canvasFrame.size,
            currentOrder: current.tentativeOrder)
#if DEBUG
        debugDragGeometry = "inside:\(localPoint):canvas=\(canvasFrame):grab=\(current.grabOffset):index=\(order.firstIndex(of: current.id) ?? -1)"
#endif
        let changed = order != current.tentativeOrder
        current.tentativeOrder = order
        current.previewingCanvas = ShareCanvasGeometry.frames(
            cards: planningCards(draggedID: current.id, order: order),
            grid: model.grid, canvasSize: canvasFrame.size)[current.id] != nil
        // Only the canvas frames animate; direct manipulation follows the
        // finger immediately rather than repeatedly retargeting a spring.
        interaction = current
        if changed { UISelectionFeedbackGenerator().selectionChanged() }
    }

    private func planningCards(draggedID: UUID, order: [UUID]) -> [ShareCard] {
        let byID = Dictionary(uniqueKeysWithValues: model.cards.map { ($0.id, $0) })
        return order.compactMap { id in
            guard var card = byID[id] else { return nil }
            if id == draggedID { card.parked = false }
            return card
        }
    }

    private func finishInteraction(at location: CGPoint) {
        // A quick drag delivers few, coalesced changes; the last one can be
        // far from where the finger lifts. Plan once more at the release
        // point so the drop lands where the card was let go.
        updateLiveReflow(at: location)
        guard var current = interaction, current.phase == .lifted else { return }
        current.location = location
        interaction = current
        let canvasFrame = composerFrames["canvas"] ?? .zero
        let trayFrame = composerFrames["tray"] ?? .zero

        if current.source == .canvas, trayFrame.contains(location) {
            let order = current.originalOrder.filter { $0 != current.id } + [current.id]
            withAnimation(motionAnimation) {
                model.commitShareOrder(order)
                model.setParked(true, for: current.id)
            }
            // The newly parked tray card is measured in the next layout pass.
            // Start settling only once its actual destination is available.
            current.phase = .settling
            current.previewingCanvas = false
            pendingTrayDrop = current.id
            interaction = current
        } else if canvasFrame.contains(location), current.previewingCanvas {
            withAnimation(motionAnimation) {
                model.setParked(false, for: current.id)
                model.commitShareOrder(current.tentativeOrder)
            }
            let cards = planningCards(draggedID: current.id, order: current.tentativeOrder)
            guard let localFrame = ShareCanvasGeometry.frames(
                cards: cards, grid: model.grid, canvasSize: canvasFrame.size)[current.id]
            else { cancelInteraction(); return }
            settleInteraction(to: localFrame.offsetBy(dx: canvasFrame.minX, dy: canvasFrame.minY))
        } else {
            cancelInteraction()
        }
    }

    private func cancelInteraction() {
        guard var current = interaction, current.phase != .settling else { return }
        if current.phase == .pressed {
            interaction = nil
            return
        }
        current.tentativeOrder = current.originalOrder
        current.previewingCanvas = current.source == .canvas
        withAnimation(motionAnimation) { interaction = current }
        settleInteraction(to: current.originFrame)
    }

    private func settleInteraction(to frame: CGRect) {
        guard var current = interaction else { return }
        settleGeneration += 1
        let generation = settleGeneration
        current.phase = .settling
        current.location = CGPoint(x: frame.midX + current.grabOffset.width,
                                   y: frame.midY + current.grabOffset.height)
        current.size = frame.size
        withAnimation(reduceMotion ? nil : settleAnimation, completionCriteria: .removed) {
            interaction = current
        } completion: {
            guard settleGeneration == generation else { return }
            interaction = nil
        }
    }

    private func resetInteraction() {
        settleGeneration += 1
        pendingTrayDrop = nil
        interaction = nil
    }

    private var settleAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.15)
            : .spring(response: 0.4, dampingFraction: 0.7)
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Picker(localization.text("ios.stats.shareRatio"), selection: Binding(
                get: { model.ratio }, set: { value in
                    withAnimation(motionAnimation) { model.ratio = value }
                })) {
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
                    withAnimation(motionAnimation) { model.size = size }
                } label: {
                    let pixels = size.pixelSize(for: model.ratio)
                    Label("\(sizeLabel(size)) · \(Int(pixels.width))×\(Int(pixels.height))",
                          systemImage: model.size == size ? "checkmark" : "photo")
                }
            }
        } label: { Label(localization.text("ios.stats.shareSize"), systemImage: "photo") }
    }

    private var layoutMenu: some View {
        Menu {
            ForEach(ShareLayoutPreset.allCases) { preset in
                Button(layoutName(preset)) {
                    withAnimation(motionAnimation) { model.apply(preset) }
                }
            }
        } label: { Label(localization.text("ios.stats.shareLayouts"), systemImage: "rectangle.3.group") }
    }

    private var addMenu: some View {
        Menu {
            Button { withAnimation(motionAnimation) { model.add(.ticket) } } label: {
                Label(localization.text("ios.stats.shareTicket"), systemImage: "ticket")
            }
            .accessibilityIdentifier("shareComposerAddTicket")
            compactAddMenu
            mapAddMenu
            Menu(localization.text("ios.stats.shareStatistics")) {
                ForEach(StatisticsCardKind.allCases.filter { $0 != .recordTicket }) { kind in
                    Button { withAnimation(motionAnimation) { model.add(.stat(kind)) } } label: {
                        Label(localization.text(kind.localizationKey), systemImage: kind.systemImage)
                    }
                }
            }
        } label: { Label(localization.text("ios.stats.shareAdd"), systemImage: "plus") }
        .accessibilityIdentifier("shareComposerAddCard")
    }

    private var compactAddMenu: some View {
        Menu(localization.text("ios.stats.shareCompactCards")) {
            ForEach([CardShape.mini, .strip]) { shape in
                Section(cardShapeLabel(shape)) {
                    ForEach(StatisticsCardKind.compactOrder.filter { $0.widgetShapes.contains(shape) }) { kind in
                        Button {
                            withAnimation(motionAnimation) { model.add(.stat(kind), shape: shape) }
                        } label: {
                            Label(localization.text(kind.localizationKey) + " · "
                                  + (shape == .mini ? "1×1" : "2×1"), systemImage: kind.systemImage)
                        }
                        .accessibilityIdentifier("shareComposerAddCompact-\(kind.rawValue)-\(shape.rawValue)")
                    }
                }
            }
        }
    }

    private var mapAddMenu: some View {
        Menu(localization.text("ios.stats.shareMap")) {
            Button { withAnimation(motionAnimation) { model.add(.map(.region(.jp))) } } label: {
                Label(localization.text("ios.area.japanAll", fallback: "Japan (all)"), systemImage: "map")
            }
            japanAreaAddMenu
            Divider()
            ForEach([Region.tw, .hk, .mo, .kr]) { region in
                Button { withAnimation(motionAnimation) { model.add(.map(.region(region))) } } label: {
                    Label(localization.text(region.localizationKey, fallback: region.fallbackName), systemImage: "map")
                }
            }
        }
    }

    private var japanAreaAddMenu: some View {
        Menu(localization.text(Region.jp.localizationKey, fallback: Region.jp.fallbackName)) {
            ForEach(StatisticsArea.islands) { area in areaAddButton(area) }
        }
    }

    private func areaAddButton(_ area: StatisticsArea) -> some View {
        Button { withAnimation(motionAnimation) { model.add(.map(.japan(area))) } } label: {
            Label(localization.text(area.localizationKey, fallback: area.fallbackName), systemImage: "map")
        }
    }

    private func inspector(_ card: ShareCard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(cardTitle(card)).font(.headline)
            if case .map = card.kind {} else {
                cardRegionMenu(card)
                cardDatesControls(card)
            }
            if case .ticket = card.kind {
                Text(localization.text("ios.stats.shareTicketFixedRatio"))
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Picker(localization.text("ios.stats.shareCardSize"), selection: Binding(
                    get: { card.size.shape }, set: { value in
                        withAnimation(motionAnimation) { model.setShape(value, for: card.id) }
                    })) {
                    ForEach(card.kind.allowedShapes) { shape in
                        Image(systemName: cardShapeIcon(shape))
                            .accessibilityLabel(cardShapeLabel(shape))
                            .tag(shape)
                    }
                }
                .pickerStyle(.segmented)
            }
            Stepper(value: Binding(
                get: { card.size.scale }, set: { value in
                    withAnimation(motionAnimation) { model.setScale(value, for: card.id) }
                }), in: model.allowedScales(for: card)) {
                    Text("\(localization.text("ios.stats.shareCardSize")): \(cardScaleLabel(card.size.scale))")
                }
            if case .map = card.kind {
                HStack {
                    Text(localization.text("ios.stats.shareZoom"))
                    Slider(value: Binding(get: { card.mapZoom },
                                          set: { value in
                                              withAnimation(motionAnimation) {
                                                  model.setZoom(value, for: card.id)
                                              }
                                          }), in: 0.75...2)
                }
            }
            HStack {
                Button { withAnimation(motionAnimation) { model.moveEarlier(card.id) } } label: { Image(systemName: "arrow.left") }
                    .accessibilityLabel(localization.text("ios.stats.shareMotion.moveEarlier"))
                Button { withAnimation(motionAnimation) { model.moveLater(card.id) } } label: { Image(systemName: "arrow.right") }
                    .accessibilityLabel(localization.text("ios.stats.shareMotion.moveLater"))
                Spacer()
                Button(role: .destructive) {
                    withAnimation(motionAnimation) { model.remove(card.id) }
                } label: {
                    Label(localization.text("ios.delete", fallback: "Delete"), systemImage: "trash")
                }
            }
        }
        .padding(14)
        .background(Color.railElevated(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func cardRegionMenu(_ card: ShareCard) -> some View {
        Menu {
            Button(localization.text("ios.stats.shareInheritRegion")) { model.setScope(nil, for: card.id) }
            ForEach(Region.enabledOrdered) { region in
                if region == .jp {
                    Menu(localization.text(region.localizationKey, fallback: region.fallbackName)) {
                        Button(localization.text("ios.area.japanAll", fallback: "Japan (all)")) {
                            model.setScope(.region(.jp), for: card.id)
                        }
                        ForEach(StatisticsArea.islands) { area in
                            Button(localization.text(area.localizationKey, fallback: area.fallbackName)) {
                                model.setScope(.japan(area), for: card.id)
                            }
                        }
                    }
                } else {
                    Button(localization.text(region.localizationKey, fallback: region.fallbackName)) {
                        model.setScope(.region(region), for: card.id)
                    }
                }
            }
        } label: {
            Label(localization.text("ios.stats.shareCardRegion") + ": "
                  + model.scopeDisplayName(model.scope(for: card), localization: localization),
                  systemImage: "globe.asia.australia")
        }
        .accessibilityIdentifier("shareComposerCardRegion")
    }

    private func cardDatesControls(_ card: ShareCard) -> some View {
        HStack {
            Button(localization.text("ios.stats.shareCustomizeDates")) {
                model.customizeDates(for: card.id)
                cardDateScopeID = card.id
            }
            .accessibilityIdentifier("shareComposerCardDates")
            .popover(isPresented: Binding(
                get: { cardDateScopeID == card.id },
                set: { if !$0 { cardDateScopeID = nil } })) {
                StatisticsScopePicker(
                    statistics: model.statistics(for: card), availableDates: availableDates(for: card),
                    groups: journeyGroups, selectGroup: model.statistics(for: card).selectJourneyGroup)
                    .presentationCompactAdaptation(.sheet)
            }
            if card.usesCustomDates {
                Button(localization.text("ios.stats.shareInheritDates")) { model.inheritDates(for: card.id) }
            }
        }
    }

    private func cardShapeIcon(_ shape: CardShape) -> String {
        switch shape {
        case .mini: "1.square"
        case .strip: "rectangle.split.2x1"
        case .small: "square"
        case .medium: "rectangle"
        case .tall: "rectangle.portrait"
        case .large: "square.fill"
        }
    }

    private func cardShapeLabel(_ shape: CardShape) -> String {
        switch shape {
        case .mini: localization.text("ios.stats.shareShape.mini")
        case .strip: localization.text("ios.stats.shareShape.strip")
        case .small: localization.text("ios.stats.shareShape.square")
        case .medium: localization.text("ios.stats.shareShape.landscape")
        case .tall: localization.text("ios.stats.shareShape.portrait")
        case .large: localization.text("ios.stats.shareShape.largeSquare")
        }
    }

    private func cardScaleLabel(_ scale: Int) -> String {
        switch scale {
        case 1: sizeLabel(.small)
        case 2: sizeLabel(.medium)
        default: sizeLabel(.large)
        }
    }

    private var dateButton: some View {
        Button { dateScopePresented = true } label: { Image(systemName: "calendar") }
            .popover(isPresented: $dateScopePresented) {
                StatisticsScopePicker(
                    statistics: model.statistics, availableDates: availableDates,
                    groups: journeyGroups, selectGroup: model.statistics.selectJourneyGroup)
                    .presentationCompactAdaptation(.sheet)
            }
            .accessibilityLabel(localization.text("ios.stats.scope"))
    }

    private var editButton: some View {
        Button(localization.text(isEditingCanvas
            ? "ios.stats.shareMotion.done" : "ios.stats.shareMotion.edit")) {
            withAnimation(motionAnimation) { isEditingCanvas.toggle() }
        }
        .accessibilityIdentifier("shareComposerEditButton")
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
        .accessibilityLabel(localization.text("ios.stats.shareAppearance"))
        .accessibilityValue(localization.text(
            model.colorScheme == .dark ? "ios.stats.shareDark" : "ios.stats.shareLight"))
        .accessibilityIdentifier("shareComposerAppearance")
    }

    private var japanRegionMenu: some View {
        Menu(localization.text(Region.jp.localizationKey, fallback: Region.jp.fallbackName)) {
            Button(localization.text("ios.area.japanAll", fallback: "Japan (all)")) {
                model.baseRegion = .jp; model.baseArea = nil
            }
            Divider()
            ForEach(StatisticsArea.islands) { area in regionAreaButton(area) }
        }
    }

    private func regionAreaButton(_ area: StatisticsArea) -> some View {
        Button(localization.text(area.localizationKey, fallback: area.fallbackName)) {
            model.baseRegion = .jp; model.baseArea = area
        }
    }

    private var selectedCard: ShareCard? { model.cards.first { $0.id == model.selectedCardID } }
    private var motionAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.15)
            : .spring(response: 0.35, dampingFraction: 0.78)
    }
    private var scopedTrains: [Train] {
        guard let loaded = itineraries.loaded else { return [] }
        return model.effectiveScope.filter(loaded.trains, rides: riddenRoutes.rides).filter { train in
            RideLedger.hasBeenRidden(train)
                && model.statistics.includesYear(train)
                && model.statistics.includesJourneyGroup(train)
                && model.statistics.includesDate(train)
        }
    }
    private var journeyGroups: [JourneyGroup] { itineraries.orderedJourneyGroups }
    private var availableDates: [String] {
        guard let loaded = itineraries.loaded else { return [] }
        let scope = model.effectiveScope
        let members = derived.memberIDs(
            scope: scope, trains: loaded.trains, rides: riddenRoutes.rides)
        return derived.scopedDates(
            trains: loaded.trains, days: loaded.days, region: nil,
            year: model.statistics.selectedYear,
            scopeKey: "\(scope.key)|\(members.key)",
            memberIDs: members.ids)
    }

    private struct ScopeWork {
        var computation: ShareScopeComputation
        var trains: [Train]
    }

    /// One walk of the placed cards. Load, readiness and export all read this.
    private var scopeWork: [ScopeWork] {
        model.scopeComputations(
            itineraryGeneration: itineraries.storeGeneration,
            placedIDs: Set(model.layout.placements.keys)
        ).map { computation in
            ScopeWork(
                computation: computation,
                trains: trains(in: computation.scope, selection: computation.statistics))
        }
    }

    private func preparedCards(_ work: [ScopeWork]) -> [ShareRenderedCard] {
        var byCard: [UUID: (ShareScopeComputation, [Train])] = [:]
        for item in work {
            for id in item.computation.cardIDs {
                byCard[id] = (item.computation, item.trains)
            }
        }
        return model.cards.compactMap { card in
            guard let match = byCard[card.id] else { return nil }
            return ShareRenderedCard(
                cardID: card.id, scope: match.0.scope,
                scopeName: model.scopeDisplayName(match.0.scope, localization: localization),
                statistics: match.0.statistics, trains: match.1)
        }
    }

    private func trains(in scope: StatisticsScope, selection: MileageStatisticsStore) -> [Train] {
        scope.filter(itineraries.loaded?.trains ?? [], rides: riddenRoutes.rides).filter {
            RideLedger.hasBeenRidden($0) && selection.includesYear($0)
                && selection.includesJourneyGroup($0) && selection.includesDate($0)
        }
    }

    private func availableDates(for card: ShareCard) -> [String] {
        guard let loaded = itineraries.loaded else { return [] }
        let scope = model.scope(for: card)
        let members = derived.memberIDs(scope: scope, trains: loaded.trains, rides: riddenRoutes.rides)
        return derived.scopedDates(
            trains: loaded.trains, days: loaded.days, region: nil,
            year: model.statistics(for: card).selectedYear,
            scopeKey: "\(scope.key)|\(members.key)", memberIDs: members.ids)
    }

    private func selectedRoutesReady(_ work: [ScopeWork]) -> Bool {
        guard let loaded = itineraries.loaded else { return false }
        let watched = Set(work.flatMap { $0.trains.map(\.id) })
        return riddenRoutes.hasSettledRoutes(in: loaded.trains) { watched.contains($0.id) }
    }

    private func loadKey(_ work: [ScopeWork]) -> String {
        let identities = work.map(\.computation.identity).joined(separator: ";")
        let candidateIDs = Set(work.flatMap { $0.trains.map(\.id) })
        let ridesKey = riddenRoutes.rides.filter { candidateIDs.contains($0.id) }
            .map { "\($0.id):\($0.geometryDigest)" }.joined(separator: ",")
        return "\(identities)|routesReady:\(selectedRoutesReady(work))|\(ridesKey)"
    }

    private func renderKey(_ work: [ScopeWork], loadKey: String) -> String {
        let cards = model.cards.map {
            "\($0.id):\($0.span.columns)x\($0.span.rows):\($0.size.shape.rawValue):\($0.mapZoom):\($0.parked):\($0.kind):\(model.scope(for: $0).key):\(ShareComposerModel.dateKey(model.statistics(for: $0)))"
        }.joined()
        let publications = work.map {
            "\($0.computation.identity):\($0.computation.statistics.publishGeneration):\($0.computation.statistics.publishedInputsKey ?? "-")"
        }.joined(separator: ";")
        let preview = previewPixelSize
        return "\(loadKey)|\(publications)|\(model.ratio.rawValue)|\(model.size.rawValue)|\(model.colorScheme)|\(Int(preview.width))x\(Int(preview.height))|\(cards)|retry:\(renderRetry)"
    }

    private func statisticsReadyForRender(_ work: [ScopeWork]) -> Bool {
        guard Set(work.flatMap { $0.computation.cardIDs }) == Set(model.layout.placements.keys),
            work.allSatisfy({ ShareResourceRevision.failureMessage(for: $0.computation.scope.countries) == nil }),
            itineraries.loaded != nil, selectedRoutesReady(work) else { return false }
        return work.allSatisfy { item in
            let store = item.computation.statistics
            // A failed load is never ready: its cards would export empty
            // figures as though they were the reader's real statistics.
            if case .failed = store.state { return false }
            guard store.publishedInputsKey == statisticsInputKey(item) else { return false }
            if store.view == nil { return true }
            if case .loaded = store.state { return true }
            return false
        }
    }

    /// Why some statistics cannot be drawn. A failed load blocks rendering and
    /// can be retried; a passport the records cannot pair is a property of
    /// the data, so it is explained without blocking unrelated cards.
    private func statisticsFailure(_ work: [ScopeWork]) -> (message: String, retryable: Bool)? {
        for item in work {
            if let error = ShareResourceRevision.failureMessage(for: item.computation.scope.countries) {
                return (error, true)
            }
        }
        for item in work {
            let store = item.computation.statistics
            guard let message = store.failureMessage else { continue }
            if case .failed = store.state { return (message, true) }
            return (message, false)
        }
        return nil
    }

    private func statisticsInputKey(_ item: ScopeWork) -> String {
        let ids = Set(item.trains.map(\.id))
        let rides = riddenRoutes.rides.filter { ids.contains($0.id) }
            .map { "\($0.id):\($0.geometryDigest)" }.joined(separator: ",")
        let revision = ShareResourceRevision.token(for: item.computation.scope.countries)
        return "\(item.computation.scope.key)|\(ShareComposerModel.dateKey(item.computation.statistics))|\(revision)|\(itineraries.storeGeneration)|\(rides)"
    }

    private var previewPixelSize: CGSize {
        guard previewCanvasSize.width > 0, previewCanvasSize.height > 0 else { return .zero }
        let scale = min(displayScale, 1_400 / max(previewCanvasSize.width, previewCanvasSize.height))
        return CGSize(
            width: max(1, (previewCanvasSize.width * scale).rounded()),
            height: max(1, (previewCanvasSize.height * scale).rounded()))
    }
    private func shouldDebounceSelectedMapZoom() -> Bool {
        guard let selectedCard, case .map = selectedCard.kind else { return false }
        let previous = previousMapZoom[selectedCard.id]
        previousMapZoom[selectedCard.id] = selectedCard.mapZoom
        return previous.map { $0 != selectedCard.mapZoom } ?? false
    }

    private func loadStatistics() {
        guard itineraries.loaded != nil else { return }
        model.prepareCardStatistics()
        let work = scopeWork
        for item in work {
            let ids = Set(item.trains.map(\.id))
            item.computation.statistics.load(
                countries: item.computation.scope.countries,
                japanLeaves: item.computation.scope.japanLeavesForIndex,
                trains: item.trains,
                rides: riddenRoutes.rides.filter { ids.contains($0.id) },
                inputsKey: statisticsInputKey(item))
        }
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
        let page = scopeWork.first { $0.computation.statistics === model.statistics }
        let currentStatistics = page.flatMap {
            model.statistics.publishedInputsKey == statisticsInputKey($0) ? model.statistics.view : nil
        }
        let km = currentStatistics.map {
            String(format: "%.1f", ($0.overall.riddenAll * 10).rounded() / 10)
        } ?? "-1"
        return [
            "ready=\(debugReady ? 1 : 0)",
            "scope=\(model.effectiveScope.key)",
            "scopeName=\(scopeName)",
            "cards=\(model.cards.count)",
            "selectedCard=\(model.cards.firstIndex { $0.id == model.selectedCardID }.map(String.init) ?? "-")",
            "overflow=\(model.layout.overflow.count)",
            "interaction=\(interaction.map { String(describing: $0.phase) } ?? "idle")",
            "editing=\(isEditingCanvas ? 1 : 0)",
            "order=\(model.cards.map(debugCardKind).joined(separator: ","))",
            "layout=\(debugLayoutSignature)",
            "canvas=\(composerFrames["canvas"] ?? .zero)",
            "cardScopes=\(model.cards.map { model.scope(for: $0).key }.joined(separator: "~"))",
            "dragEnd=\(debugDragEnd)",
            "dragGeometry=\(debugDragGeometry)",
            "journeys=\(scopedTrains.count)",
            "km=\(km)",
            "ratio=\(model.ratio.rawValue)",
            "scheme=\(model.colorScheme == .dark ? "dark" : "light")",
            "px=\(Int(pixels.width))x\(Int(pixels.height))",
        ].joined(separator: ";")
    }

    private var debugReady: Bool {
        let work = scopeWork
        let key = renderKey(work, loadKey: loadKey(work))
        let statisticsLoaded = statisticsReadyForRender(work)
        let placedCardsRendered = model.layout.placements.keys.allSatisfy {
            renderer.images[$0] != nil
        }
        let exportWritten = model.debugExportURL == nil
            || renderer.debugExportedKey == key
        return statisticsLoaded && renderer.completedKey == key
            && placedCardsRendered && exportWritten
    }

    private var debugLayoutSignature: String {
        model.cards.map { card in
            let position = model.layout.placements[card.id].map {
                "\($0.column):\($0.row):\($0.columns):\($0.rows)"
            } ?? "tray"
            return "\(card.id.uuidString):\(card.size.shape.rawValue):\(position)"
        }.joined(separator: ",")
    }
#endif

    private func export() {
        let work = scopeWork
        let key = renderKey(work, loadKey: loadKey(work))
        guard interaction == nil, !model.layout.placements.isEmpty,
              statisticsReadyForRender(work), renderer.completedKey == key else { return }
        exportTask?.cancel()
        exportTicket += 1
        let ticket = exportTicket
        exporting = true
        exportTask = Task {
            let prepared = preparedCards(work)
            let file = await renderer.export(
                model: model, itineraries: itineraries, rides: riddenRoutes.rides,
                prepared: prepared, localization: localization, key: key)
            let currentWork = scopeWork
            guard !Task.isCancelled, exportTicket == ticket,
                statisticsReadyForRender(currentWork), renderKey(currentWork, loadKey: loadKey(currentWork)) == key else { return }
            shareFile = file
            exportFailed = file == nil
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
        case .ticket: localization.text("ios.stats.shareTicket")
        case .map(let area): area.localizedName(localization)
        case .stat(let kind): localization.text(kind.localizationKey)
        }
    }
#if DEBUG
    private func debugCardKind(_ card: ShareCard) -> String {
        switch card.kind {
        case .ticket: "ticket"
        case .stat(let kind): "stat:\(kind.rawValue)"
        case .map(.region(let region)): "map:\(region.rawValue)"
        case .map(.japan(let area)): "map:jp:\(area.rawValue)"
        }
    }
#endif
    private func cardAccessibilityLabel(_ card: ShareCard) -> String {
        let name: String
        if case .map(let area) = card.kind {
            name = localization.text("ios.stats.shareMap") + ", "
                + area.localizedName(localization)
        } else {
            name = cardTitle(card)
        }
        return localization.text("ios.stats.shareCardLabel", params: [
            "name": .string(name),
            "columns": .number(Double(card.span.columns)),
            "rows": .number(Double(card.span.rows)),
        ])
    }
    private func sizeLabel(_ size: ShareCanvasSize) -> String {
        switch size {
        case .small: localization.text("ios.stats.shareSizeSmall")
        case .medium: localization.text("ios.stats.shareSizeMedium")
        case .large: localization.text("ios.stats.shareSizeLarge")
        }
    }
    private func ticketCornerRadius(_ card: ShareCard, frame: CGRect) -> CGFloat {
        if case .ticket = card.kind { return 0 }
        return max(5, min(frame.width, frame.height) * 0.07)
    }
    private func layoutName(_ preset: ShareLayoutPreset) -> String {
        switch preset {
        case .japanIslands: localization.text("ios.stats.shareLayoutJapan")
        case .taiwan: localization.text(Region.tw.localizationKey, fallback: Region.tw.fallbackName)
        case .hongKong: localization.text(Region.hk.localizationKey, fallback: Region.hk.fallbackName)
        case .macau: localization.text(Region.mo.localizationKey, fallback: Region.mo.fallbackName)
        }
    }
}
