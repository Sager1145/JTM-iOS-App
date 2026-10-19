import CoreGraphics
import Foundation
import SwiftUI
import UIKit

struct ShareComposerInteraction: Equatable {
    enum Source: Equatable { case canvas, tray }
    enum Phase: Equatable { case pressed, lifted, settling }

    var id: UUID
    var source: Source
    var phase: Phase = .pressed
    var originalOrder: [UUID]
    var tentativeOrder: [UUID]
    var location: CGPoint
    var startLocation: CGPoint
    var grabOffset: CGSize
    var size: CGSize
    var originFrame: CGRect
    var previewingCanvas = false
    // Freeze the lifted face while committing order/parking invalidates the
    // asynchronous renderer. Its replacement appears after the card lands.
    var snapshot: UIImage?

    var isLifted: Bool { phase != .pressed }
}

enum ShareCardGestureEvent {
    case tapped
    case began(DragGesture.Value)
    case changed(DragGesture.Value)
    case longPressed(DragGesture.Value)
    case ended(DragGesture.Value)
    case cancelled
}

struct ShareCardGestureLayer<Content: View>: View {
    let content: Content
    let isEditing: Bool
    let onEvent: (ShareCardGestureEvent) -> Void

    @GestureState private var longPressIsActive = false
    @GestureState private var editDragIsActive = false
    @GestureState private var touch: DragGesture.Value?
    @State private var pressToken: UUID?

    init(
        isEditing: Bool,
        @ViewBuilder content: () -> Content,
        onEvent: @escaping (ShareCardGestureEvent) -> Void
    ) {
        self.content = content()
        self.isEditing = isEditing
        self.onEvent = onEvent
    }

    var body: some View {
        content
            .highPriorityGesture(editDragGesture,
                                 including: editingDragEnabled ? .all : .none)
            .highPriorityGesture(pressDragGesture,
                                 including: editingDragEnabled ? .none : .all)
            .simultaneousGesture(tapGesture)
            // Observe the grab point without claiming scrolling. A successful
            // stationary long press enters the sequence before its drag has a
            // value, so it still needs the original touch to lift in place.
            .simultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .updating($touch) { value, touch, _ in touch = value })
            .onChange(of: gestureIsActive) { wasActive, isActive in
                guard wasActive, !isActive, let token = pressToken else { return }
                DispatchQueue.main.async {
                    guard pressToken == token else { return }
                    clearPress()
                    onEvent(.cancelled)
                }
            }
            .onDisappear {
                guard pressToken != nil else { return }
                clearPress()
                onEvent(.cancelled)
            }
    }

    // A short touch selects independently; an active drag owns the interaction.
    private var tapGesture: some Gesture {
        TapGesture().onEnded { onEvent(.tapped) }
    }

    private var gestureIsActive: Bool { longPressIsActive || editDragIsActive }

    // The press that entered editing keeps ownership until release. Subsequent
    // edit drags use a pan threshold, not a zero-duration long-press sequence
    // (which can fail to hand the initial touch to its second recognizer).
    private var editingDragEnabled: Bool { isEditing && !longPressIsActive }

    private var editDragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .updating($editDragIsActive) { _, active, _ in active = true }
            .onChanged { drag in
                beginDragIfNeeded(drag)
                onEvent(.changed(drag))
            }
            .onEnded { drag in
                clearPress()
                onEvent(.ended(drag))
            }
    }

    private var pressDragGesture: some Gesture {
        // Native long-press recognition lets the enclosing scroll view win
        // before activation. Keep the sequence mounted when edit mode changes
        // so the long press that entered editing retains its touch.
        LongPressGesture(minimumDuration: 0.4, maximumDistance: 8)
            .sequenced(before: DragGesture(minimumDistance: 0,
                                           coordinateSpace: .global))
            .updating($longPressIsActive) { _, active, _ in active = true }
            .onChanged { value in
                guard case .second(true, let value) = value,
                      let drag = value ?? touch else { return }
                beginDragIfNeeded(drag)
                onEvent(.changed(drag))
            }
            .onEnded { value in
                clearPress()
                if case .second(true, let drag?) = value { onEvent(.ended(drag)) }
                else { onEvent(.cancelled) }
            }
    }

    private func beginDragIfNeeded(_ drag: DragGesture.Value) {
        guard pressToken == nil else { return }
        pressToken = UUID()
        onEvent(.began(drag))
        onEvent(.longPressed(drag))
    }

    private func clearPress() {
        pressToken = nil
    }
}

struct ShareComposerFramePreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct ShareComposerCardFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension ShareCanvasGeometry {
    static func cornerRadius(card: ShareCard, frame: CGRect) -> CGFloat {
        if case .ticket = card.kind { return 0 }
        if case .stat(let kind) = card.kind {
            if kind == .recordTicket { return 0 }
            let shape = CardShape.matching(card.span, preferred: card.size.shape)
            let scale = min(frame.width / shape.designSize.width, frame.height / shape.designSize.height)
            return (shape.isCompact ? 11 : 22) * scale
        }
        return max(5, min(frame.width, frame.height) * 0.07)
    }

    static func frames(
        cards: [ShareCard], grid: (columns: Int, rows: Int), canvasSize: CGSize
    ) -> [UUID: CGRect] {
        let result = ShareLayout.pack(cards, columns: grid.columns, rows: grid.rows)
        guard let occupied = result.occupied else { return [:] }
        let metrics = metrics(grid: grid, occupied: occupied, canvasSize: canvasSize)
        let cardsByID = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
        return result.placements.reduce(into: [:]) { frames, entry in
            let (id, placement) = entry
            let column = placement.column - occupied.column
            let row = placement.row - occupied.row
            var frame = CGRect(
                x: metrics.origin.x + CGFloat(column) * (metrics.cell + metrics.gap),
                y: metrics.origin.y + CGFloat(row) * (metrics.cell + metrics.gap),
                width: CGFloat(placement.columns) * metrics.cell
                    + CGFloat(placement.columns - 1) * metrics.gap,
                height: CGFloat(placement.rows) * metrics.cell
                    + CGFloat(placement.rows - 1) * metrics.gap)
            if let card = cardsByID[id], case .ticket = card.kind {
                let exactHeight = frame.width / TicketFace.aspect
                frame = CGRect(x: frame.minX, y: frame.midY - exactHeight / 2,
                               width: frame.width, height: exactHeight)
            }
            frames[id] = frame
        }
    }

    static func cellEdge(
        cards: [ShareCard], grid: (columns: Int, rows: Int), canvasSize: CGSize
    ) -> CGFloat {
        let layout = ShareLayout.pack(cards, columns: grid.columns, rows: grid.rows)
        guard let occupied = layout.occupied else { return 0 }
        return metrics(grid: grid, occupied: occupied, canvasSize: canvasSize).cell
    }

    private static func metrics(
        grid: (columns: Int, rows: Int), occupied: GridRect, canvasSize: CGSize
    ) -> (cell: CGFloat, gap: CGFloat, origin: CGPoint) {
        let short = min(canvasSize.width, canvasSize.height)
        let outer = short * 0.04
        let gap = short * 0.015
        let availableWidth = canvasSize.width - outer * 2 - gap * CGFloat(grid.columns - 1)
        let availableHeight = canvasSize.height - outer * 2 - gap * CGFloat(grid.rows - 1)
        let cell = min(availableWidth / CGFloat(grid.columns),
                       availableHeight / CGFloat(grid.rows))
        let blockWidth = CGFloat(occupied.columns) * cell
            + CGFloat(occupied.columns - 1) * gap
        let blockHeight = CGFloat(occupied.rows) * cell
            + CGFloat(occupied.rows - 1) * gap
        return (cell, gap, CGPoint(x: (canvasSize.width - blockWidth) / 2,
                                  y: (canvasSize.height - blockHeight) / 2))
    }
}

enum ShareDragPlanner {
    /// Scores insertions using the exact letterboxed frames displayed by the canvas.
    static func bestOrder(
        cards: [ShareCard],
        draggedID: UUID,
        finger: CGPoint,
        grid: (columns: Int, rows: Int),
        canvasSize: CGSize,
        currentOrder: [UUID]
    ) -> [UUID] {
        guard cards.contains(where: { $0.id == draggedID }) else { return currentOrder }
        let byID = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
        let normalizedCurrent = currentOrder.filter { byID[$0] != nil }
        let remaining = cards.map(\.id).filter { !normalizedCurrent.contains($0) }
        let completeCurrent = normalizedCurrent + remaining
        let others = completeCurrent.filter { $0 != draggedID }

        func orderedCards(_ ids: [UUID]) -> [ShareCard] { ids.compactMap { byID[$0] } }
        let currentCards = orderedCards(completeCurrent)
        let originalOverflow = ShareLayout.pack(
            currentCards, columns: grid.columns, rows: grid.rows).overflow.count

        func distance(for ids: [UUID]) -> CGFloat {
            let candidateCards = orderedCards(ids)
            let layout = ShareLayout.pack(
                candidateCards, columns: grid.columns, rows: grid.rows)
            guard layout.overflow.count <= originalOverflow,
                  let frame = ShareCanvasGeometry.frames(
                    cards: candidateCards, grid: grid, canvasSize: canvasSize)[draggedID]
            else { return .greatestFiniteMagnitude }
            return hypot(frame.midX - finger.x, frame.midY - finger.y)
        }

        var best = completeCurrent
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for index in 0...others.count {
            var candidate = others
            candidate.insert(draggedID, at: index)
            let candidateDistance = distance(for: candidate)
            if candidateDistance < bestDistance {
                best = candidate
                bestDistance = candidateDistance
            }
        }

        let currentDistance = distance(for: completeCurrent)
        let hysteresis = ShareCanvasGeometry.cellEdge(
            cards: currentCards, grid: grid, canvasSize: canvasSize) / 4
        guard best != completeCurrent,
              bestDistance + hysteresis < currentDistance else { return completeCurrent }
        return best
    }
}

extension ShareComposerModel {
    func commitShareOrder(_ orderedIDs: [UUID]) {
        let valid = orderedIDs.filter { id in cards.contains(where: { $0.id == id }) }
        guard valid.count == cards.count, Set(valid).count == cards.count else { return }
        guard valid != cards.map(\.id) else { return }
        reorder(valid)
    }
}
